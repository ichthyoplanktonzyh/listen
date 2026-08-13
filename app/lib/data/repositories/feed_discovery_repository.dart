import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/discovery.dart';
import '../../services/feed_parser.dart';
import '../../services/subscription_store.dart';
import 'discovery_repository.dart';
import 'media_import_repository.dart';

/// Discovery over RSS and Atom feeds: podcasts and article/blog feeds.
///
/// These are the remote sources where discovery and acquisition are both
/// first-class: the feed lists the items and hands over what the publisher
/// put there — a media enclosure for a podcast, an article link for a
/// document feed. There is no extractor to keep alive and no platform term
/// being stretched, so this is the path the rest of the journey —
/// generation, import, learning — gets exercised against.
///
/// A source id is the feed URL. For a feed the address is the stable thing to
/// point at; there is no separate channel identifier to prefer. The source
/// kind (podcast or document) is decided at subscription time from what the
/// feed actually carries, so a feed whose items are enclosures and a feed
/// whose items are articles never stand in for each other.
final class FeedDiscoveryRepository implements DiscoveryRepository {
  FeedDiscoveryRepository({
    HttpClient? client,
    String? starterAssetPath,
    SubscriptionStore? subscriptions,
  }) : _client = client ?? HttpClient(),
       _starterAssetPath = starterAssetPath ?? _defaultStarterAsset,
       _subscriptions = subscriptions ?? SubscriptionStore.inMemory();

  static const _defaultStarterAsset = 'assets/starter_feeds.json';

  final HttpClient _client;
  final String _starterAssetPath;

  /// Parsed feeds for this session.
  ///
  /// `entriesFor` used to refetch on every selection, so clicking away from a
  /// channel and back paid the whole download again. A feed's item list is
  /// the same for the minutes a person spends browsing it; refreshing it is a
  /// deliberate act, not a side effect of navigation.
  final Map<String, ParsedFeed> _feeds = {};

  List<ContentSource>? _starters;

  /// Subscribed feeds, durable when the composition root supplied a backed
  /// store. Held here only through the store so a restart cannot disagree with
  /// what is on screen.
  final SubscriptionStore _subscriptions;

  List<ContentSource> get _customSources =>
      _subscriptions.of(ContentSourceKind.podcast) +
      _subscriptions.of(ContentSourceKind.document);

  /// A feed source id is its feed URL, and YouTube channel ids are never
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
  Future<List<ContentSource>> sources() async {
    if (!_subscriptions.isLoaded) await _subscriptions.load();
    final starters = _starters ??= await _loadStarters();
    return List.unmodifiable([...starters, ..._customSources]);
  }

  Future<List<ContentSource>> _loadStarters() async {
    final raw = await rootBundle.loadString(_starterAssetPath);
    final decoded = jsonDecode(raw) as Map<dynamic, dynamic>;
    return [
      for (final entry in decoded['feeds'] as List<dynamic>)
        _sourceFromMap(entry as Map<dynamic, dynamic>),
    ];
  }

  /// Throws on transport, status or format failure rather than returning an
  /// empty list: "this feed has published nothing" and "we could not read the
  /// feed" must not render as the same screen.
  @override
  Future<List<DiscoveryItem>> entriesFor(String sourceId) async {
    final feed = await _fetchFeed(sourceId);
    final kind = _kindOf(sourceId, feed);
    return [
      for (final item in feed.items)
        _itemFrom(item, sourceId, feed.language, kind),
    ];
  }

  /// A feed has no per-item subscribe action; an item is reached through its
  /// feed.
  @override
  Future<DiscoveryItem> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => throw const FeedFormatException(
    'A feed item is added by subscribing to its feed, not on its own.',
  );

  /// Subscribes to a feed pasted by the user. The feed is fetched and parsed
  /// before the source is added, so a bad URL fails here rather than becoming
  /// a channel that is permanently empty.
  @override
  Future<ContentSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) async {
    final trimmed = url.trim();
    final feed = await _fetchFeed(trimmed);

    final source = ContentSource(
      id: trimmed,
      name: feed.title.isEmpty ? trimmed : feed.title,
      language: feed.language.isEmpty ? '' : feed.language,
      description: feed.description,
      cover: ChannelCoverTone.slate,
      kind: _kindOf(trimmed, feed),
      avatarUrl: feed.imageUrl,
    );

    await _subscriptions.add(source);
    return source;
  }

  /// Drops the cached feed for [sourceId] so the next read goes to the
  /// network. The refresh affordance is the caller's to offer.
  void forget(String sourceId) => _feeds.remove(sourceId);

  /// What the feed's items mean: enclosures are media (podcast), article
  /// links are documents. Decided from the feed's own content, never assumed.
  ContentSourceKind _kindOf(String sourceId, ParsedFeed feed) {
    if (_customSources.any((source) => source.id == sourceId)) {
      final subscribed = _customSources.firstWhere(
        (source) => source.id == sourceId,
      );
      return subscribed.kind;
    }
    for (final item in feed.items) {
      if (item.enclosureUrl != null) return ContentSourceKind.podcast;
      if (item.entryUrl != null) return ContentSourceKind.document;
    }
    return ContentSourceKind.document;
  }

  Future<ParsedFeed> _fetchFeed(String feedUrl) async {
    final cached = _feeds[feedUrl];
    if (cached != null) return cached;
    final feed = await _downloadFeed(feedUrl);
    _feeds[feedUrl] = feed;
    return feed;
  }

  Future<ParsedFeed> _downloadFeed(String feedUrl) async {
    final uri = Uri.parse(feedUrl);
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw const FeedFormatException(
        'A feed address must be an http or https URL.',
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
    final body = await readFeedBody(response.transform(utf8.decoder));
    // Even a capped feed is hundreds of kilobytes of XML, and parsing it on
    // the UI isolate showed up as a dropped frame rather than as work.
    return Isolate.run(() => parseFeed(body, maxItems: feedItemLimit));
  }

  DiscoveryItem _itemFrom(
    ParsedFeedItem item,
    String sourceId,
    String feedLanguage,
    ContentSourceKind kind,
  ) {
    final enclosure = item.enclosureUrl;
    return DiscoveryItem(
      id: item.id,
      sourceId: sourceId,
      title: item.title,
      description: item.description,
      durationMs: item.durationMs,
      language: feedLanguage,
      publishedOn: item.publishedOn,
      thumbnailUrl: item.imageUrl,
      viewCount: item.viewCount,
      acquisition: switch (kind) {
        ContentSourceKind.podcast => enclosure == null
            ? AcquisitionMode.none
            : AcquisitionMode.enclosure,
        ContentSourceKind.document => item.entryUrl == null
            ? AcquisitionMode.none
            : AcquisitionMode.article,
        ContentSourceKind.youtube => AcquisitionMode.externalTool,
      },
      contentKind: switch (kind) {
        ContentSourceKind.podcast => _kindFor(enclosure == null
            ? null
            : item.enclosureType),
        ContentSourceKind.document => ItemContentKind.article,
        ContentSourceKind.youtube => ItemContentKind.video,
      },
      mediaUrl: kind == ContentSourceKind.podcast ? enclosure : null,
      entryUrl: item.entryUrl,
      publisherId: item.publisherId,
      mediaByteLength: item.enclosureBytes,
    );
  }

  ItemContentKind _kindFor(String? enclosureType) =>
      enclosureType != null && enclosureType.toLowerCase().startsWith('video/')
      ? ItemContentKind.video
      : ItemContentKind.audio;
}

ContentSource _sourceFromMap(Map<dynamic, dynamic> map) => ContentSource(
  id: map['url'] as String,
  name: map['name'] as String,
  language: map['language'] as String? ?? '',
  description: map['description'] as String? ?? '',
  cover: _coverFromName(map['cover'] as String? ?? ''),
  kind: ContentSourceKind.podcast,
  avatarUrl: null,
);

ChannelCoverTone _coverFromName(String name) => switch (name) {
  'green' => ChannelCoverTone.green,
  'amber' => ChannelCoverTone.amber,
  'blue' => ChannelCoverTone.blue,
  'rose' => ChannelCoverTone.rose,
  _ => ChannelCoverTone.slate,
};
