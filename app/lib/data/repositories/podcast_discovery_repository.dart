import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/discovery.dart';
import '../../services/podcast_feed_parser.dart';
import 'discovery_repository.dart';
import 'media_import_repository.dart';

/// Discovery over podcast RSS.
///
/// Podcasts are the one remote source where discovery and acquisition are both
/// first-class: the feed lists the episodes and hands over a media URL the
/// publisher put there for clients to fetch. There is no extractor to keep
/// alive and no platform term being stretched, so this is the path the rest of
/// the journey — generation, import, learning — gets exercised against.
///
/// A source id is the feed URL. For a podcast the feed address is the stable
/// thing to point at; there is no separate channel identifier to prefer.
final class PodcastDiscoveryRepository implements DiscoveryRepository {
  PodcastDiscoveryRepository({HttpClient? client, String? starterAssetPath})
    : _client = client ?? HttpClient(),
      _starterAssetPath = starterAssetPath ?? _defaultStarterAsset;

  static const _defaultStarterAsset = 'assets/podcast_starter_feeds.json';

  final HttpClient _client;
  final String _starterAssetPath;

  /// Parsed feeds for this session.
  ///
  /// `entriesFor` used to refetch on every selection, so clicking away from a
  /// channel and back paid the whole download again. A feed's episode list is
  /// the same for the minutes a person spends browsing it; refreshing it is a
  /// deliberate act, not a side effect of navigation.
  final Map<String, PodcastFeed> _feeds = {};

  List<MediaSource>? _starters;
  final List<MediaSource> _customSources = [];

  /// A podcast source id is its feed URL, and YouTube channel ids are never
  /// URLs — so the shape answers this even before [sources] has been awaited
  /// and the starter list exists to search.
  bool owns(String sourceId) {
    final uri = Uri.tryParse(sourceId);
    if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
      return true;
    }
    return _starters?.any((source) => source.id == sourceId) == true ||
        _customSources.any((source) => source.id == sourceId);
  }

  @override
  Future<List<MediaSource>> sources() async {
    final starters = _starters ??= await _loadStarters();
    return List.unmodifiable([...starters, ..._customSources]);
  }

  Future<List<MediaSource>> _loadStarters() async {
    final raw = await rootBundle.loadString(_starterAssetPath);
    final decoded = jsonDecode(raw) as Map<dynamic, dynamic>;
    return [
      for (final entry in decoded['feeds'] as List<dynamic>)
        _sourceFromMap(entry as Map<dynamic, dynamic>),
    ];
  }

  /// Throws on transport, status or format failure rather than returning an
  /// empty list: "this podcast has published nothing" and "we could not read
  /// the feed" must not render as the same screen.
  @override
  Future<List<MediaEntry>> entriesFor(String sourceId) async {
    final feed = await _fetchFeed(sourceId);
    return [
      for (final episode in feed.episodes)
        _entryFrom(episode, sourceId, feed.language),
    ];
  }

  /// Whether a package exists is Core's fact, and this repository has no way
  /// to ask it, so it does not claim one either way.
  @override
  Future<PackageStatus> checkPackage(String entryId) async =>
      PackageStatus.undetermined;

  /// A podcast has no per-episode subscribe action; an episode is reached
  /// through its feed.
  @override
  Future<MediaEntry> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => throw const PodcastFeedFormatException(
    'A podcast episode is added by subscribing to its feed, not on its own.',
  );

  /// Subscribes to a feed pasted by the user. The feed is fetched and parsed
  /// before the source is added, so a bad URL fails here rather than becoming
  /// a channel that is permanently empty.
  @override
  Future<MediaSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) async {
    final trimmed = url.trim();
    final feed = await _fetchFeed(trimmed);

    final source = MediaSource(
      id: trimmed,
      name: feed.title.isEmpty ? trimmed : feed.title,
      language: feed.language.isEmpty ? '' : feed.language,
      description: feed.description,
      cover: ChannelCoverTone.slate,
      type: MediaSourceType.podcast,
      avatarUrl: feed.imageUrl,
    );

    _customSources.removeWhere((existing) => existing.id == source.id);
    _customSources.add(source);
    return source;
  }

  /// Drops the cached feed for [sourceId] so the next read goes to the
  /// network. The refresh affordance is the caller's to offer.
  void forget(String sourceId) => _feeds.remove(sourceId);

  Future<PodcastFeed> _fetchFeed(String feedUrl) async {
    final cached = _feeds[feedUrl];
    if (cached != null) return cached;
    final feed = await _downloadFeed(feedUrl);
    _feeds[feedUrl] = feed;
    return feed;
  }

  Future<PodcastFeed> _downloadFeed(String feedUrl) async {
    final uri = Uri.parse(feedUrl);
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw const PodcastFeedFormatException(
        'A podcast feed address must be an http or https URL.',
      );
    }

    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'The feed host answered ${response.statusCode}.',
        uri: uri,
      );
    }
    final body = await readPodcastFeedBody(response.transform(utf8.decoder));
    // Even a capped feed is hundreds of kilobytes of XML, and parsing it on
    // the UI isolate showed up as a dropped frame rather than as work.
    return Isolate.run(
      () => parsePodcastFeed(body, maxEpisodes: podcastEpisodeLimit),
    );
  }

  MediaEntry _entryFrom(
    PodcastEpisode episode,
    String sourceId,
    String feedLanguage,
  ) {
    final url = episode.enclosureUrl;
    return MediaEntry(
      id: episode.guid,
      sourceId: sourceId,
      title: episode.title,
      description: episode.description,
      durationMs: episode.durationMs,
      language: feedLanguage,
      publishedOn: episode.publishedOn,
      thumbnailUrl: episode.imageUrl,
      // Podcast feeds do not publish play counts. Zero here means "the source
      // does not report this", and the surface omits the figure rather than
      // showing a channel where every episode has no listeners.
      viewCount: 0,
      hasPackage: false,
      acquisition: url == null
          ? MediaAcquisition.none
          : MediaAcquisition.enclosure,
      mediaKind: _kindFor(episode.enclosureType),
      mediaUrl: url,
      mediaByteLength: episode.enclosureBytes,
    );
  }

  MediaKind _kindFor(String? enclosureType) =>
      enclosureType != null && enclosureType.toLowerCase().startsWith('video/')
      ? MediaKind.video
      : MediaKind.audio;
}

MediaSource _sourceFromMap(Map<dynamic, dynamic> map) => MediaSource(
  id: map['url'] as String,
  name: map['name'] as String,
  language: map['language'] as String? ?? '',
  description: map['description'] as String? ?? '',
  cover: _coverFromName(map['cover'] as String? ?? ''),
  type: MediaSourceType.podcast,
  avatarUrl: null,
);

ChannelCoverTone _coverFromName(String name) => switch (name) {
  'green' => ChannelCoverTone.green,
  'amber' => ChannelCoverTone.amber,
  'blue' => ChannelCoverTone.blue,
  'rose' => ChannelCoverTone.rose,
  _ => ChannelCoverTone.slate,
};
