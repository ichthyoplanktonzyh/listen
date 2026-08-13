import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/discovery.dart';
import '../../services/feed_parser.dart';
import '../../services/subscription_store.dart';
import 'media_import_repository.dart';

/// Content-resource discovery boundary for the home preflight.
///
/// Each family answers for its own sources: a feed is fetched and parsed
/// here in the app, a YouTube channel goes through its own Atom feed and,
/// for acquisition, an external tool. The preflight also ships a fixture
/// implementation backed by a bundled catalog.
abstract interface class DiscoveryRepository {
  Future<List<ContentSource>> sources();

  Future<List<DiscoveryItem>> entriesFor(String sourceId);

  Future<DiscoveryItem> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  );

  Future<ContentSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  );
}

/// Loads the bundled sample catalog used by the preflight and widget previews.
/// No network, no platform state — the point is the information architecture,
/// not the data source.
final class FixtureDiscoveryRepository implements DiscoveryRepository {
  FixtureDiscoveryRepository();

  static const _assetPath = 'assets/discovery_fixtures.json';

  List<ContentSource>? _sources;
  List<DiscoveryItem>? _entries;

  Future<void> _ensureLoaded() async {
    if (_sources != null) return;
    final source = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(source) as Map<dynamic, dynamic>;
    final sources = <ContentSource>[
      for (final raw in decoded['sources'] as List<dynamic>)
        _sourceFromMap(raw as Map<dynamic, dynamic>),
    ];
    final kindsById = {for (final source in sources) source.id: source.kind};
    final entries = <DiscoveryItem>[
      for (final raw in decoded['items'] as List<dynamic>)
        _entryFromMap(
          raw as Map<dynamic, dynamic>,
          kindsById[raw['channelId']] ?? ContentSourceKind.youtube,
        ),
    ];
    _sources = List.unmodifiable(sources);
    _entries = List.unmodifiable(entries);
  }

  @override
  Future<List<ContentSource>> sources() async {
    await _ensureLoaded();
    return _sources!;
  }

  @override
  Future<List<DiscoveryItem>> entriesFor(String sourceId) async {
    await _ensureLoaded();
    return List.unmodifiable(
      _entries!.where((entry) => entry.sourceId == sourceId),
    );
  }

  @override
  Future<DiscoveryItem> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ContentSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) {
    throw UnimplementedError();
  }
}

ContentSource _sourceFromMap(Map<dynamic, dynamic> map) => ContentSource(
  id: map['id'] as String,
  name: map['name'] as String,
  language: map['language'] as String,
  description: map['description'] as String,
  cover: _coverFromName(map['cover'] as String),
  kind: _kindFromName(map['kind'] as String),
  avatarUrl: map['avatarUrl'] as String?,
);

/// The fixture catalog is written in Content Source / Discovery Item terms:
/// every source declares its kind and every entry carries only the evidence
/// that kind has — enclosure URLs for podcast sources, article links for
/// document sources, a YouTube watch identity for video sources.
DiscoveryItem _entryFromMap(Map<dynamic, dynamic> map, ContentSourceKind kind) {
  final id = map['id'] as String;
  final isYoutube = kind == ContentSourceKind.youtube;
  final isDocument = kind == ContentSourceKind.document;
  return DiscoveryItem(
    id: id,
    sourceId: map['channelId'] as String,
    title: map['title'] as String,
    description: map['description'] as String,
    durationMs: map['durationMs'] as int?,
    language: map['language'] as String,
    publishedOn: map['publishedOn'] as String,
    thumbnailUrl: map['thumbnailUrl'] as String?,
    viewCount: map['viewCount'] as int? ?? 0,
    acquisition: isYoutube
        ? AcquisitionMode.externalTool
        : isDocument
        ? AcquisitionMode.article
        : AcquisitionMode.enclosure,
    contentKind: isYoutube
        ? ItemContentKind.video
        : isDocument
        ? ItemContentKind.article
        : ItemContentKind.audio,
    mediaUrl: isYoutube
        ? 'https://www.youtube.com/watch?v=$id'
        : map['mediaUrl'] as String?,
    entryUrl: map['entryUrl'] as String?,
    mediaByteLength: map['mediaByteLength'] as int?,
  );
}

ContentSourceKind _kindFromName(String name) => switch (name) {
  'youtube' => ContentSourceKind.youtube,
  'podcast' => ContentSourceKind.podcast,
  'document' => ContentSourceKind.document,
  _ => ContentSourceKind.youtube,
};

ChannelCoverTone _coverFromName(String name) => switch (name) {
  'green' => ChannelCoverTone.green,
  'amber' => ChannelCoverTone.amber,
  'blue' => ChannelCoverTone.blue,
  'slate' => ChannelCoverTone.slate,
  'rose' => ChannelCoverTone.rose,
  _ => ChannelCoverTone.slate,
};

/// Discovery over YouTube's per-channel Atom feed.
///
/// Discovery only. Listing a video here grants no acquisition right: the
/// download path below runs a user-provided external tool, on the user's own
/// responsibility, which is why entries from this source are marked
/// [AcquisitionMode.externalTool] rather than sharing the podcast enclosure
/// path.
final class YoutubeDiscoveryRepository implements DiscoveryRepository {
  YoutubeDiscoveryRepository({
    SubscriptionStore? subscriptions,
    HttpClient? client,
    this.feedBaseUrl = 'https://www.youtube.com/feeds/videos.xml',
    this.retryBackoff = const Duration(milliseconds: 400),
  }) : _subscriptions = subscriptions ?? SubscriptionStore.inMemory(),
       _client = client ?? HttpClient();

  final HttpClient _client;

  /// Where the per-channel Atom feed lives. A field so a test can point it at
  /// a local server and drive the status codes this endpoint really returns.
  final String feedBaseUrl;

  /// Delay before the first retry; the second waits twice as long.
  ///
  /// A field so tests do not spend a real second proving the retry happens.
  final Duration retryBackoff;

  /// How many times a feed request is attempted before the surface is told the
  /// source failed.
  ///
  /// Measured on 2026-08-05: the same channel feed URL, requested repeatedly
  /// seconds apart, answered 200, 404 and 500 in no pattern — for channels
  /// that verifiably exist, and identically under a browser user agent. The
  /// endpoint throttles by returning "not found". One attempt therefore failed
  /// roughly half the time, and the surface said "this source could not be
  /// loaded" about a channel that was fine.
  ///
  /// Three attempts, not more: a channel that really is gone answers the same
  /// way, and making the person wait longer to be told so is its own dishonesty.
  static const _attempts = 3;

  /// Subscribed channels, durable when the composition root supplied a backed
  /// store. They used to live in a plain list and vanish on restart.
  final SubscriptionStore _subscriptions;

  /// The starter channels.
  ///
  /// Every id here was resolved from the channel's own page on 2026-08-05 and
  /// is the one YouTube's Atom feed answers to. Two of them used to be
  /// invented strings — Wired and SciShow — and those two sources could never
  /// load at all, which read as the same failure as the throttling above.
  ///
  /// `avatarUrl` is null on all of them for the same reason: the six
  /// `yt3.googleusercontent.com` links that used to be here were fabricated
  /// too. Nothing renders the avatar today, so a real one would have to be
  /// fetched when something does.
  static const List<ContentSource> _defaultSources = [
    ContentSource(
      id: 'UCsooa4yRKGN_zEE8iknghZA',
      name: 'TED-Ed',
      language: 'en',
      description:
          'Carefully curated educational videos, many of which are collaborations between talented educators and animators.',
      cover: ChannelCoverTone.rose,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
    ContentSource(
      id: 'UCsXVk37bltHxD1rDPwtNM8Q',
      name: 'Kurzgesagt – In a Nutshell',
      language: 'en',
      description:
          'Animation videos explaining science, space, technology, history, and philosophy with beautiful illustration.',
      cover: ChannelCoverTone.blue,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
    ContentSource(
      id: 'UCLXo7UDZvByw2ixzpQCufnA',
      name: 'Vox',
      language: 'en',
      description:
          'Vox helps you understand our complex world with news, context, maps, and video essays on society and science.',
      cover: ChannelCoverTone.slate,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
    ContentSource(
      id: 'UCftwRNsjfRo08xYE31tkiyw',
      name: 'Wired',
      language: 'en',
      description:
          'Wired is where tomorrow is realized, focusing on technology, science, culture, and business through interviews.',
      cover: ChannelCoverTone.green,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
    ContentSource(
      id: 'UCHaHD477h-FeBbVh9Sh7syA',
      name: 'BBC Learning English',
      language: 'en',
      description:
          'Learn English from the BBC with new videos, podcasts, and quizzes published every week to improve your skills.',
      cover: ChannelCoverTone.amber,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
    ContentSource(
      id: 'UCZYTClx2T1of7BRZ86-8fow',
      name: 'SciShow',
      language: 'en',
      description:
          'SciShow explores the unexpected, explaining the scientific mysteries of the universe and daily life.',
      cover: ChannelCoverTone.blue,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    ),
  ];

  @override
  Future<List<ContentSource>> sources() async {
    if (!_subscriptions.isLoaded) await _subscriptions.load();
    return List.unmodifiable([
      ..._defaultSources,
      ..._subscriptions.of(ContentSourceKind.youtube),
    ]);
  }

  /// Throws on transport, status, or parse failure. Swallowing it here would
  /// hand the surface an empty list, which reads as "this channel has no
  /// videos" — indistinguishable from offline or rate-limited.
  @override
  Future<List<DiscoveryItem>> entriesFor(String sourceId) async {
    final body = await _fetchFeed(sourceId);
    final feed = parseFeed(body, assumeFormat: FeedFormat.atom);
    return [
      for (final item in feed.items) _itemFrom(item, sourceId),
    ];
  }

  DiscoveryItem _itemFrom(ParsedFeedItem item, String sourceId) {
    final videoId = item.id;
    return DiscoveryItem(
      id: videoId,
      sourceId: sourceId,
      title: item.title,
      description: item.description,
      // The Atom feed carries no duration. It used to be filled with a
      // hardcoded five minutes, which every card then rendered as a real
      // badge; unknown stays unknown until the view model's duration
      // resolver reports an actual one.
      durationMs: null,
      language: 'en',
      publishedOn: item.publishedOn,
      thumbnailUrl: item.imageUrl,
      viewCount: item.viewCount,
      acquisition: AcquisitionMode.externalTool,
      contentKind: ItemContentKind.video,
      mediaUrl: 'https://www.youtube.com/watch?v=$videoId',
      entryUrl: item.entryUrl,
    );
  }

  /// The feed XML for [sourceId], retried through the endpoint's throttling.
  ///
  /// Only the status is retried. A transport failure is the machine's own
  /// network and repeating it just delays the same answer, while a body that
  /// arrived is a body — retrying because it parsed to nothing would hide a
  /// channel that genuinely has no videos.
  Future<String> _fetchFeed(String sourceId) async {
    final uri = Uri.parse('$feedBaseUrl?channel_id=$sourceId');
    var delay = retryBackoff;
    for (var attempt = 1; ; attempt++) {
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      final response = await request.close();
      if (response.statusCode == 200) {
        return response.transform(utf8.decoder).join();
      }
      await response.drain<void>();
      if (attempt >= _attempts) {
        throw HttpException(
          'YouTube RSS server returned status ${response.statusCode} '
          'on $_attempts attempts',
          uri: uri,
        );
      }
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }

  @override
  Future<DiscoveryItem> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) async {
    final details = await importRepo.resolveVideoDetails(url);
    return DiscoveryItem(
      id: details.id,
      sourceId: details.channelId,
      title: details.title,
      description: details.description,
      durationMs: details.durationMs,
      language: 'en',
      publishedOn: details.uploadDate,
      thumbnailUrl: details.thumbnail,
      viewCount: details.viewCount,
      acquisition: AcquisitionMode.externalTool,
      contentKind: ItemContentKind.video,
      mediaUrl: url,
    );
  }

  @override
  Future<ContentSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) async {
    final details = await importRepo.resolveChannelDetails(url);

    final newSource = ContentSource(
      id: details.id,
      name: details.name,
      language: 'en',
      description: 'Custom imported channel from YouTube.',
      cover: ChannelCoverTone.slate,
      kind: ContentSourceKind.youtube,
      avatarUrl: null,
    );

    await _subscriptions.add(newSource);
    return newSource;
  }
}
