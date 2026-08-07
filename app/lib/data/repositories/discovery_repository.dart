import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/discovery.dart';
import '../../services/subscription_store.dart';
import 'media_import_repository.dart';

/// Content-resource discovery boundary for the home preflight.
///
/// The preflight ships with a fixture implementation backed by a bundled
/// catalog; a real implementation would aggregate channel metadata and lesson
/// listings from a source such as a curated catalog or a platform feed, and
/// stays behind this seam.
abstract interface class DiscoveryRepository {
  Future<List<MediaSource>> sources();

  Future<List<MediaEntry>> entriesFor(String sourceId);

  Future<PackageStatus> checkPackage(String entryId);

  Future<MediaEntry> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  );

  Future<MediaSource> resolveCustomChannel(
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

  List<MediaSource>? _sources;
  List<MediaEntry>? _entries;

  Future<void> _ensureLoaded() async {
    if (_sources != null) return;
    final source = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(source) as Map<dynamic, dynamic>;
    final sources = <MediaSource>[
      for (final raw in decoded['channels'] as List<dynamic>)
        _sourceFromMap(raw as Map<dynamic, dynamic>),
    ];
    final typesById = {for (final source in sources) source.id: source.type};
    final entries = <MediaEntry>[
      for (final raw in decoded['items'] as List<dynamic>)
        _entryFromMap(
          raw as Map<dynamic, dynamic>,
          typesById[raw['channelId']] ?? MediaSourceType.youtube,
        ),
    ];
    _sources = List.unmodifiable(sources);
    _entries = List.unmodifiable(entries);
  }

  @override
  Future<List<MediaSource>> sources() async {
    await _ensureLoaded();
    return _sources!;
  }

  @override
  Future<List<MediaEntry>> entriesFor(String sourceId) async {
    await _ensureLoaded();
    return List.unmodifiable(
      _entries!.where((entry) => entry.sourceId == sourceId),
    );
  }

  @override
  Future<PackageStatus> checkPackage(String entryId) async {
    await _ensureLoaded();
    // Simulate core lookup delay
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final entry = _entries!.firstWhere((e) => e.id == entryId);
    return entry.hasPackage
        ? PackageStatus.available
        : PackageStatus.notAvailable;
  }

  @override
  Future<MediaEntry> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<MediaSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) {
    throw UnimplementedError();
  }
}

MediaSource _sourceFromMap(Map<dynamic, dynamic> map) => MediaSource(
  id: map['id'] as String,
  name: map['name'] as String,
  language: map['language'] as String,
  description: map['description'] as String,
  cover: _coverFromName(map['cover'] as String),
  type: _typeFromName(map['type'] as String),
  avatarUrl: map['avatarUrl'] as String?,
);

/// The fixture used to hand every entry a `youtube.com/watch?v=` URL, whatever
/// its channel said it was — so a podcast channel's episodes claimed to be
/// YouTube videos. The acquisition path follows the channel's type instead.
MediaEntry _entryFromMap(Map<dynamic, dynamic> map, MediaSourceType type) {
  final id = map['id'] as String;
  final isYoutube = type == MediaSourceType.youtube;
  return MediaEntry(
    id: id,
    sourceId: map['channelId'] as String,
    title: map['title'] as String,
    description: map['description'] as String,
    durationMs: map['durationMs'] as int?,
    language: map['language'] as String,
    publishedOn: map['publishedOn'] as String,
    thumbnailUrl: map['thumbnailUrl'] as String?,
    viewCount: map['viewCount'] as int? ?? 0,
    hasPackage: map['hasPackage'] as bool? ?? false,
    acquisition: isYoutube
        ? MediaAcquisition.externalTool
        : MediaAcquisition.enclosure,
    mediaKind: isYoutube ? MediaKind.video : MediaKind.audio,
    mediaUrl: isYoutube
        ? 'https://www.youtube.com/watch?v=$id'
        : map['enclosureUrl'] as String?,
  );
}

MediaSourceType _typeFromName(String name) => switch (name) {
  'youtube' => MediaSourceType.youtube,
  'podcast' => MediaSourceType.podcast,
  _ => MediaSourceType.youtube,
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
/// [MediaAcquisition.externalTool] rather than sharing the podcast enclosure
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
  static const List<MediaSource> _defaultSources = [
    MediaSource(
      id: 'UCsooa4yRKGN_zEE8iknghZA',
      name: 'TED-Ed',
      language: 'en',
      description:
          'Carefully curated educational videos, many of which are collaborations between talented educators and animators.',
      cover: ChannelCoverTone.rose,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    ),
    MediaSource(
      id: 'UCsXVk37bltHxD1rDPwtNM8Q',
      name: 'Kurzgesagt – In a Nutshell',
      language: 'en',
      description:
          'Animation videos explaining science, space, technology, history, and philosophy with beautiful illustration.',
      cover: ChannelCoverTone.blue,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    ),
    MediaSource(
      id: 'UCLXo7UDZvByw2ixzpQCufnA',
      name: 'Vox',
      language: 'en',
      description:
          'Vox helps you understand our complex world with news, context, maps, and video essays on society and science.',
      cover: ChannelCoverTone.slate,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    ),
    MediaSource(
      id: 'UCftwRNsjfRo08xYE31tkiyw',
      name: 'Wired',
      language: 'en',
      description:
          'Wired is where tomorrow is realized, focusing on technology, science, culture, and business through interviews.',
      cover: ChannelCoverTone.green,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    ),
    MediaSource(
      id: 'UCHaHD477h-FeBbVh9Sh7syA',
      name: 'BBC Learning English',
      language: 'en',
      description:
          'Learn English from the BBC with new videos, podcasts, and quizzes published every week to improve your skills.',
      cover: ChannelCoverTone.amber,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    ),
    MediaSource(
      id: 'UCZYTClx2T1of7BRZ86-8fow',
      name: 'SciShow',
      language: 'en',
      description:
          'SciShow explores the unexpected, explaining the scientific mysteries of the universe and daily life.',
      cover: ChannelCoverTone.blue,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    ),
  ];

  @override
  Future<List<MediaSource>> sources() async {
    if (!_subscriptions.isLoaded) await _subscriptions.load();
    return List.unmodifiable([
      ..._defaultSources,
      ..._subscriptions.of(MediaSourceType.youtube),
    ]);
  }

  /// Throws on transport, status, or parse failure. Swallowing it here would
  /// hand the surface an empty list, which reads as "this channel has no
  /// videos" — indistinguishable from offline or rate-limited.
  @override
  Future<List<MediaEntry>> entriesFor(String sourceId) async {
    final body = await _fetchFeed(sourceId);

    final entryMatches = RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(body);
    final entries = <MediaEntry>[];
    for (final match in entryMatches) {
      final segment = match.group(1) ?? '';
      final videoId = RegExp(
        r'<yt:videoId>([^<]+)</yt:videoId>',
      ).firstMatch(segment)?.group(1)?.trim();
      final titleRaw =
          RegExp(
            r'<title>([^<]+)</title>',
          ).firstMatch(segment)?.group(1)?.trim() ??
          '';
      final descRaw =
          RegExp(
            r'<media:description>([\s\S]*?)</media:description>',
          ).firstMatch(segment)?.group(1)?.trim() ??
          '';
      final published =
          RegExp(
            r'<published>([^<]+)</published>',
          ).firstMatch(segment)?.group(1)?.trim() ??
          '';
      final thumb = RegExp(
        r'<media:thumbnail\s+url="([^"]+)"',
      ).firstMatch(segment)?.group(1)?.trim();
      final viewsRaw = RegExp(
        r'<media:statistics\s+views="(\d+)"',
      ).firstMatch(segment)?.group(1);
      final views = viewsRaw == null ? 0 : int.tryParse(viewsRaw) ?? 0;

      if (videoId == null || videoId.isEmpty) continue;

      entries.add(
        MediaEntry(
          id: videoId,
          sourceId: sourceId,
          title: _decodeXml(titleRaw),
          description: _decodeXml(descRaw),
          // The Atom feed carries no duration. It used to be filled with a
          // hardcoded five minutes, which every card then rendered as a real
          // badge; unknown stays unknown until `_resolveRemoteDurations`
          // reports an actual one.
          durationMs: null,
          language: 'en',
          publishedOn: published,
          thumbnailUrl: thumb,
          viewCount: views,
          hasPackage: false,
          acquisition: MediaAcquisition.externalTool,
          mediaKind: MediaKind.video,
          mediaUrl: 'https://www.youtube.com/watch?v=$videoId',
        ),
      );
    }
    return entries;
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

  /// The feed carries no package information, and this repository has no way
  /// to ask the core — so the honest answer is that it does not know.
  @override
  Future<PackageStatus> checkPackage(String entryId) async {
    return PackageStatus.undetermined;
  }

  @override
  Future<MediaEntry> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) async {
    final details = await importRepo.resolveVideoDetails(url);
    return MediaEntry(
      id: details.id,
      sourceId: details.channelId,
      title: details.title,
      description: details.description,
      durationMs: details.durationMs,
      language: 'en',
      publishedOn: details.uploadDate,
      thumbnailUrl: details.thumbnail,
      viewCount: details.viewCount,
      hasPackage: false,
      acquisition: MediaAcquisition.externalTool,
      mediaKind: MediaKind.video,
      mediaUrl: url,
    );
  }

  @override
  Future<MediaSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) async {
    final details = await importRepo.resolveChannelDetails(url);

    final newSource = MediaSource(
      id: details.id,
      name: details.name,
      language: 'en',
      description: 'Custom imported channel from YouTube.',
      cover: ChannelCoverTone.slate,
      type: MediaSourceType.youtube,
      avatarUrl: null,
    );

    await _subscriptions.add(newSource);
    return newSource;
  }

  String _decodeXml(String val) {
    return val
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&reg;', '®')
        .replaceAll('&copy;', '©');
  }
}
