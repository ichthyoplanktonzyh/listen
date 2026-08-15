import 'dart:async';
import 'package:llplayer_next/models/discovery.dart';
import 'package:llplayer_next/models/media_download.dart';
import 'package:llplayer_next/models/media_resolution.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/data/repositories/media_library_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/saved_vocabulary_count.dart';
import 'package:llplayer_next/models/embedded_subtitle.dart';

class TestMediaDownloadHandle implements MediaDownloadHandle {
  TestMediaDownloadHandle(String entryId, Completer<String?> completedCompleter)
    : completed = completedCompleter.future {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final nextProgress = timer.tick * 0.1;
      if (nextProgress >= 1.0) {
        _controller.add(1.0);
        completedCompleter.complete('/path/to/downloaded/[$entryId].mp4');
        timer.cancel();
      } else {
        _controller.add(nextProgress);
      }
    });
  }

  final StreamController<double> _controller =
      StreamController<double>.broadcast();
  late final Timer _timer;
  @override
  final Future<String?> completed;

  @override
  Stream<double> get progress => _controller.stream;

  @override
  void cancel() {
    _timer.cancel();
  }
}

/// A download that fails the way the real one does: `completed` finishes with
/// an error rather than a null path.
class TestFailingDownloadHandle implements MediaDownloadHandle {
  TestFailingDownloadHandle({
    Duration after = const Duration(milliseconds: 60),
  }) {
    _timer = Timer(after, () {
      if (_cancelled) return;
      _controller.add(0.3);
      _completer.completeError(StateError('yt-dlp exited with status 1.'));
    });
  }

  final _controller = StreamController<double>.broadcast();
  final _completer = Completer<String?>();
  late final Timer _timer;
  bool _cancelled = false;

  @override
  Future<String?> get completed => _completer.future;

  @override
  Stream<double> get progress => _controller.stream;

  @override
  void cancel() {
    _cancelled = true;
    _timer.cancel();
  }
}

class TestMediaImportRepository implements MediaImportRepository {
  TestMediaImportRepository({
    this.probedDurationMs,
    this.resolvedDurationMs = 0,
    this.resolveGate,
    this.downloadFails = false,
    this.holdDownload = false,
    this.downloadLaunchGate,
  });

  /// True makes every download end in an error instead of a path.
  final bool downloadFails;

  /// True keeps `completed` pending so a test can settle a cancel first and
  /// then release the late callback.
  final bool holdDownload;

  /// When set, the downloader launch parks before returning its handle, so a
  /// test can hold the window between `controller.starting()` and
  /// `controller.attach()` open and cancel inside it.
  Completer<void>? downloadLaunchGate;

  final int? probedDurationMs;
  final int resolvedDurationMs;

  /// Holds every `resolveVideoDetails` call open until completed, so a test can
  /// observe which background duration workers were still running.
  final Completer<void>? resolveGate;

  /// Every page URL a duration worker asked about, in call order.
  final resolvedUrls = <String>[];

  final completers = <String, Completer<String?>>{};

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());

  @override
  Future<String?> pickDownloadDirectory({
    required String confirmButtonText,
  }) async {
    return '/mock/download/dir';
  }

  @override
  Future<String> resolveOnlineMedia(String pageUrl) async => '';

  /// Every page URL handed to the external-tool path, in call order.
  final downloadedUrls = <String>[];

  @override
  Future<MediaDownloadHandle> downloadOnlineMedia(
    String pageUrl,
    String directory,
  ) async {
    downloadedUrls.add(pageUrl);
    final entryId = pageUrl.contains('i-bbc-1') ? 'i-bbc-1' : 'i-bbc-2';
    if (downloadFails) return TestFailingDownloadHandle();
    final completer = Completer<String?>();
    completers[entryId] = completer;
    if (downloadLaunchGate != null) await downloadLaunchGate!.future;
    if (holdDownload) return TestHeldDownloadHandle(completer);
    return TestMediaDownloadHandle(entryId, completer);
  }

  /// Every enclosure URL handed to the direct-fetch path, with the size the
  /// feed advertised, so a test can tell which acquisition actually ran.
  final enclosureRequests = <({String url, int? expectedBytes})>[];

  @override
  Future<MediaDownloadHandle> downloadEnclosure(
    String mediaUrl,
    String directory, {
    int? expectedBytes,
  }) async {
    enclosureRequests.add((url: mediaUrl, expectedBytes: expectedBytes));
    if (downloadFails) return TestFailingDownloadHandle();
    final entryId = mediaUrl.contains('i-bbc-1') ? 'i-bbc-1' : 'i-bbc-2';
    final completer = Completer<String?>();
    completers[entryId] = completer;
    if (downloadLaunchGate != null) await downloadLaunchGate!.future;
    if (holdDownload) return TestHeldDownloadHandle(completer);
    return TestMediaDownloadHandle(entryId, completer);
  }

  /// Every article URL handed to the document path, so a test can tell which
  /// acquisition actually ran.
  final articleRequests = <String>[];

  @override
  Future<String?> downloadArticle(String articleUrl, String directory) async {
    articleRequests.add(articleUrl);
    if (downloadFails) return null;
    final entryId = articleUrl.contains('i-doc-1') ? 'i-doc-1' : 'i-doc-2';
    final completer = Completer<String?>();
    completer.complete('/path/to/downloaded/[$entryId].html');
    completers[entryId] = completer;
    return completer.future;
  }

  @override
  Future<ResolvedVideoDetails> resolveVideoDetails(String pageUrl) async {
    resolvedUrls.add(pageUrl);
    await resolveGate?.future;
    return ResolvedVideoDetails(
      id: '',
      title: 'YouTube Video',
      description: '',
      durationMs: resolvedDurationMs,
      viewCount: 0,
      thumbnail: null,
      channelId: '',
      uploadDate: '',
    );
  }

  @override
  Future<ResolvedChannelDetails> resolveChannelDetails(
    String channelUrl,
  ) async => const ResolvedChannelDetails(id: '', name: '');
  @override
  Future<List<EmbeddedSubtitle>> probeSubtitles(String mediaPath) async => [];
  @override
  Future<int?> probeMediaDurationMs(String mediaPath) async => probedDurationMs;
  @override
  Future<String> extractTextSubtitle(
    String mediaPath,
    EmbeddedSubtitle subtitle,
  ) async => '';
}

/// A download that never finishes on its own; the test completes it by hand.
class TestHeldDownloadHandle implements MediaDownloadHandle {
  TestHeldDownloadHandle(this._completer);

  final Completer<String?> _completer;
  final _controller = StreamController<double>.broadcast();

  @override
  Future<String?> get completed => _completer.future;

  @override
  Stream<double> get progress => _controller.stream;

  @override
  void cancel() {}
}

class TestMediaLibraryRepository implements MediaLibraryRepository {
  TestMediaLibraryRepository({
    this.mediaDurationMs = 300000,
    this.available = true,
    this.failListing = false,
    this.failRegister = false,
    List<MediaLibraryEntry> seed = const [],
  }) {
    _entries.addAll(seed);
  }

  /// Builds the library row a previous session's download would have left, so
  /// a test can start from "this was already acquired".
  static MediaLibraryEntry entry({required String id, required String path}) =>
      MediaLibraryEntry(
        media: MediaItem(
          id: id,
          path: path,
          fingerprint: 'fp-$id',
          title: 'Seeded $id',
          kind: 'audio',
          durationMs: 300000,
          availability: 'local',
          createdAtMs: 0,
          updatedAtMs: 0,
        ),
        primaryTrackId: null,
        fit: null,
        triageIntent: null,
        familiarMaterial: false,
      );

  /// True makes registration throw the way a core rejection does.
  final bool failRegister;

  final int? mediaDurationMs;

  /// False stands in for a disconnected core: nothing can be asked.
  bool available;

  /// True makes the listing throw, the way a broken core connection does.
  final bool failListing;

  final List<MediaLibraryEntry> _entries = [];

  /// Grows the library after construction (e.g. a core reconnect seeding the
  /// entry the first, disconnected check could not see).
  void addEntry(MediaLibraryEntry entry) => _entries.add(entry);

  /// Drops every row (e.g. a folder emptied on disk), so a test can show a
  /// definitive no-match where an earlier refresh answered local.
  void clearEntries() => _entries.clear();

  @override
  bool get isAvailable => available;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());

  @override
  Future<SavedVocabularyCount> savedVocabularyCount({
    required String language,
  }) async => const SavedVocabularyCount(total: 0, capped: false);

  @override
  @override
  Future<MediaItem> readMedia(String mediaId) async =>
      throw StateError('not used in discovery tests');
  @override
  Future<List<MediaLibraryEntry>> listMediaLibrary() async {
    if (failListing) throw StateError('media library listing failed');
    return _entries;
  }

  @override
  Future<MediaLibraryEntry> setTriageIntent(
    String mediaId,
    String? intent,
  ) async => throw UnimplementedError();

  @override
  Future<MediaItem> registerMedia(
    String path, {
    int? durationMs,
    required bool retain,
  }) async {
    if (failRegister) throw StateError('register failed');
    // A document must never be registered as media: the fake answers the way
    // Core would refuse bytes it cannot probe as a media file. The article
    // path never reaches here — a test that does reach it with an .html path
    // has taken the wrong intake.
    if (path.endsWith('.html') || path.endsWith('.htm')) {
      throw StateError('refused: $path is a document, not media');
    }
    final regExp = RegExp(r'\[([^\]]+)\]');
    final match = regExp.firstMatch(path);
    final entryId = match?.group(1) ?? 'i-bbc-1';

    final media = MediaItem(
      id: 'media-$entryId',
      path: path,
      fingerprint: 'fp-$entryId',
      title: 'Downloaded Media $entryId',
      kind: 'video',
      durationMs: durationMs ?? mediaDurationMs,
      availability: 'local',
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final primaryTrackId = entryId == 'i-bbc-1' ? 'track-$entryId' : null;

    final entry = MediaLibraryEntry(
      media: media,
      primaryTrackId: primaryTrackId,
      fit: null,
      triageIntent: null,
      familiarMaterial: false,
    );

    _entries.add(entry);
    return media;
  }
}

ContentSource testContentSource(String id, {String? name}) => ContentSource(
  id: id,
  name: name ?? id,
  language: 'en',
  description: 'Source $id',
  cover: ChannelCoverTone.slate,
  kind: ContentSourceKind.youtube,
  avatarUrl: null,
);

DiscoveryItem testDiscoveryItem(String id, String sourceId) => DiscoveryItem(
  id: id,
  sourceId: sourceId,
  title: 'Entry $id',
  description: '',
  // Null like the real YouTube Atom feed, which publishes no durations: the
  // background workers exist precisely because this arrives unknown.
  durationMs: null,
  language: 'en',
  publishedOn: '2026-08-01',
  thumbnailUrl: null,
  viewCount: 0,
  acquisition: AcquisitionMode.externalTool,
  contentKind: ItemContentKind.video,
  mediaUrl: 'https://www.youtube.com/watch?v=$id',
);

/// A podcast episode: a duration the feed stated, an enclosure to fetch
/// directly, and audio rather than video.
DiscoveryItem testPodcastItem(String id, String sourceId) => DiscoveryItem(
  id: id,
  sourceId: sourceId,
  title: 'Episode $id',
  description: '',
  durationMs: 360000,
  language: 'en',
  publishedOn: '2026-08-01',
  thumbnailUrl: null,
  viewCount: 0,
  acquisition: AcquisitionMode.enclosure,
  contentKind: ItemContentKind.audio,
  mediaUrl: 'https://cdn.example.com/$id.mp3',
  mediaByteLength: 8123456,
);

/// A document item: an article link the feed offered, fetched as a document.
DiscoveryItem testArticleItem(String id, String sourceId) => DiscoveryItem(
  id: id,
  sourceId: sourceId,
  title: 'Article $id',
  description: '',
  durationMs: null,
  language: 'en',
  publishedOn: '2026-08-01',
  thumbnailUrl: null,
  viewCount: 0,
  acquisition: AcquisitionMode.article,
  contentKind: ItemContentKind.article,
  entryUrl: 'https://blog.example.com/$id',
);

/// A feed item with show notes but no enclosure: discoverable, not acquirable.
DiscoveryItem testUnacquirableItem(String id, String sourceId) => DiscoveryItem(
  id: id,
  sourceId: sourceId,
  title: 'Notes for $id',
  description: '',
  durationMs: null,
  language: 'en',
  publishedOn: '2026-08-01',
  thumbnailUrl: null,
  viewCount: 0,
);

/// A discovery feed the test drives: which sources exist, which entries each
/// one answers with, which of them fail, and — through [gates] — when they
/// answer at all, so the in-flight window is observable.
class TestDiscoveryRepository implements DiscoveryRepository {
  TestDiscoveryRepository({
    List<ContentSource> sources = const [],
    Map<String, List<DiscoveryItem>> entries = const {},
  }) : _sources = List.of(sources),
       _entries = Map.of(entries);

  final List<ContentSource> _sources;
  final Map<String, List<DiscoveryItem>> _entries;

  /// Set to make `sources()` throw instead of answering.
  bool failSources = false;

  /// Sources whose feed throws instead of answering.
  final failingSources = <String>{};

  /// A source's feed waits on its gate before answering.
  final gates = <String, Completer<void>>{};

  @override
  Future<List<ContentSource>> sources() async {
    if (failSources) throw StateError('source list unavailable');
    return List.unmodifiable(_sources);
  }

  @override
  Future<List<DiscoveryItem>> entriesFor(String sourceId) async {
    await gates[sourceId]?.future;
    if (failingSources.contains(sourceId)) {
      throw StateError('feed for $sourceId unavailable');
    }
    return List.unmodifiable(_entries[sourceId] ?? const <DiscoveryItem>[]);
  }

  @override
  Future<DiscoveryItem> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => throw UnimplementedError();

  @override
  Future<ContentSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) => throw UnimplementedError();
}
