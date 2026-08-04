import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/discovery.dart';
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
    final entries = <MediaEntry>[
      for (final raw in decoded['items'] as List<dynamic>)
        _entryFromMap(raw as Map<dynamic, dynamic>),
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

MediaEntry _entryFromMap(Map<dynamic, dynamic> map) => MediaEntry(
  id: map['id'] as String,
  sourceId: map['channelId'] as String,
  title: map['title'] as String,
  description: map['description'] as String,
  durationMs: map['durationMs'] as int,
  language: map['language'] as String,
  publishedOn: map['publishedOn'] as String,
  thumbnailUrl: map['thumbnailUrl'] as String?,
  viewCount: map['viewCount'] as int? ?? 0,
  hasPackage: map['hasPackage'] as bool? ?? false,
  videoUrl: 'https://www.youtube.com/watch?v=${map['id']}',
);

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

final class LiveDiscoveryRepository implements DiscoveryRepository {
  LiveDiscoveryRepository();

  final HttpClient _client = HttpClient();

  static const List<MediaSource> _defaultSources = [
    MediaSource(
      id: 'UCsooa4yRKGN_zEE8iknghZA',
      name: 'TED-Ed',
      language: 'en',
      description:
          'Carefully curated educational videos, many of which are collaborations between talented educators and animators.',
      cover: ChannelCoverTone.rose,
      type: MediaSourceType.youtube,
      avatarUrl:
          'https://yt3.googleusercontent.com/ytc/AIdrodkkwq6d9uQ6yP5978r81H7X14X5G-0L5a2G9X8=s176-c-k-c0x00ffffff-no-rj',
    ),
    MediaSource(
      id: 'UCsXVk37bltHxD1rDPwtNM8Q',
      name: 'Kurzgesagt – In a Nutshell',
      language: 'en',
      description:
          'Animation videos explaining science, space, technology, history, and philosophy with beautiful illustration.',
      cover: ChannelCoverTone.blue,
      type: MediaSourceType.youtube,
      avatarUrl:
          'https://yt3.googleusercontent.com/ytc/AIdrodfU_mD_31qX1-N-q_G_1_Q_V-0L5_Y_1_Q=s176-c-k-c0x00ffffff-no-rj',
    ),
    MediaSource(
      id: 'UCLXo7UDZvByw2ixzpQCufnA',
      name: 'Vox',
      language: 'en',
      description:
          'Vox helps you understand our complex world with news, context, maps, and video essays on society and science.',
      cover: ChannelCoverTone.slate,
      type: MediaSourceType.youtube,
      avatarUrl:
          'https://yt3.googleusercontent.com/ytc/AIdrodfV_mD_31qX1-N-q_G_1_Q_V-0L5_Y_1_Q=s176-c-k-c0x00ffffff-no-rj',
    ),
    MediaSource(
      id: 'UCn8zNIfYAQNdrFRrr8oibKw',
      name: 'Wired',
      language: 'en',
      description:
          'Wired is where tomorrow is realized, focusing on technology, science, culture, and business through interviews.',
      cover: ChannelCoverTone.green,
      type: MediaSourceType.youtube,
      avatarUrl:
          'https://yt3.googleusercontent.com/ytc/AIdrodfW_mD_31qX1-N-q_G_1_Q_V-0L5_Y_1_Q=s176-c-k-c0x00ffffff-no-rj',
    ),
    MediaSource(
      id: 'UCHaHD477h-FeBbVh9Sh7syA',
      name: 'BBC Learning English',
      language: 'en',
      description:
          'Learn English from the BBC with new videos, podcasts, and quizzes published every week to improve your skills.',
      cover: ChannelCoverTone.amber,
      type: MediaSourceType.youtube,
      avatarUrl:
          'https://yt3.googleusercontent.com/ytc/AIdrodfA_mD_31qX1-N-q_G_1_Q_V-0L5_Y_1_Q=s176-c-k-c0x00ffffff-no-rj',
    ),
    MediaSource(
      id: 'UC6nSFpj9HTCZ5t-N3Rm3-HA',
      name: 'SciShow',
      language: 'en',
      description:
          'SciShow explores the unexpected, explaining the scientific mysteries of the universe and daily life.',
      cover: ChannelCoverTone.blue,
      type: MediaSourceType.youtube,
      avatarUrl:
          'https://yt3.googleusercontent.com/ytc/AIdrodfS_mD_31qX1-N-q_G_1_Q_V-0L5_Y_1_Q=s176-c-k-c0x00ffffff-no-rj',
    ),
  ];

  final List<MediaSource> _customSources = [];

  @override
  Future<List<MediaSource>> sources() async {
    return List.unmodifiable([..._defaultSources, ..._customSources]);
  }

  /// Throws on transport, status, or parse failure. Swallowing it here would
  /// hand the surface an empty list, which reads as "this channel has no
  /// videos" — indistinguishable from offline or rate-limited.
  @override
  Future<List<MediaEntry>> entriesFor(String sourceId) async {
    final url = 'https://www.youtube.com/feeds/videos.xml?channel_id=$sourceId';
    final request = await _client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'YouTube RSS server returned status ${response.statusCode}',
      );
    }
    final body = await response.transform(utf8.decoder).join();

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
          durationMs: 300000, // placeholder (5 minutes)
          language: 'en',
          publishedOn: published,
          thumbnailUrl: thumb,
          viewCount: views,
          hasPackage: false,
          videoUrl: 'https://www.youtube.com/watch?v=$videoId',
        ),
      );
    }
    return entries;
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
      videoUrl: url,
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

    if (!_customSources.any((s) => s.id == details.id)) {
      _customSources.add(newSource);
    }
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
