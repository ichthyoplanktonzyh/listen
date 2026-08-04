import 'dart:async';
import 'package:llplayer_next/models/discovery.dart';
import 'package:llplayer_next/models/media_download.dart';
import 'package:llplayer_next/models/media_resolution.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/data/repositories/content_package_repository.dart';
import 'package:llplayer_next/data/repositories/media_library_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/content_package.dart';
import 'package:llplayer_next/models/saved_vocabulary_count.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/embedded_subtitle.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';

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
  TestFailingDownloadHandle({Duration after = const Duration(milliseconds: 60)}) {
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
  });

  /// True makes every download end in an error instead of a path.
  final bool downloadFails;

  /// True keeps `completed` pending so a test can settle a cancel first and
  /// then release the late callback.
  final bool holdDownload;

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

  @override
  Future<MediaDownloadHandle> downloadOnlineMedia(
    String pageUrl,
    String directory,
  ) async {
    final entryId = pageUrl.contains('i-bbc-1') ? 'i-bbc-1' : 'i-bbc-2';
    if (downloadFails) return TestFailingDownloadHandle();
    final completer = Completer<String?>();
    completers[entryId] = completer;
    if (holdDownload) return TestHeldDownloadHandle(completer);
    return TestMediaDownloadHandle(entryId, completer);
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

class TestContentPackageRun implements ListenGenProcessRun {
  TestContentPackageRun();

  final StreamController<ListenGenMachineEvent> _controller =
      StreamController<ListenGenMachineEvent>.broadcast();
  final Completer<String> _packagePath = Completer<String>();

  bool get isComplete => _packagePath.isCompleted;

  @override
  Stream<ListenGenMachineEvent> get events => _controller.stream;

  @override
  Future<String> get packagePath => _packagePath.future;

  /// Emits the machine protocol lifecycle up to the first progress phase.
  void emitRunning() {
    _controller.add(
      ListenGenMachineEvent(sequence: 0, kind: ListenGenEventKind.protocol),
    );
    _controller.add(
      ListenGenMachineEvent(sequence: 1, kind: ListenGenEventKind.started),
    );
    _controller.add(
      ListenGenMachineEvent(
        sequence: 2,
        kind: ListenGenEventKind.phase,
        phase: 'transcribing',
      ),
    );
    _controller.add(
      ListenGenMachineEvent(
        sequence: 3,
        kind: ListenGenEventKind.completed,
        packageSha256: 'sha256:${'a' * 64}',
        mediaFingerprint: 'sha256:${'b' * 64}',
        resources: const [],
        warnings: const [],
      ),
    );
  }

  /// Resolves the package path, the way a successful listen-gen run does.
  void completeSuccessfully() {
    _packagePath.complete('/tmp/generated.listenpkg');
  }

  /// Emits a failed terminal event and fails the package path.
  void failWith(String code) {
    _controller.add(
      ListenGenMachineEvent(
        sequence: 1,
        kind: ListenGenEventKind.failed,
        code: code,
        message: 'generator failed',
      ),
    );
    if (!_packagePath.isCompleted) {
      _packagePath.completeError(ListenGenProcessFailure(code));
    }
  }

  @override
  void cancel() {
    _controller.add(
      ListenGenMachineEvent(sequence: 4, kind: ListenGenEventKind.cancelled),
    );
    if (!_packagePath.isCompleted) {
      _packagePath.completeError(const ListenGenProcessFailure('cancelled'));
    }
  }

  @override
  Future<void> cleanUp() async {}
}

class TestContentPackageRepository implements ContentPackageRepository {
  final List<TestContentPackageRun> runs = [];
  final List<ContentPackageGenerationRequest> requests = [];

  @override
  bool get coreAvailable => true;

  @override
  bool get generatorConfigured => true;

  @override
  ApiFailure failureDetail(Object error) => error is ListenGenProcessFailure
      ? ApiFailure(raw: '', code: error.code, retryable: true)
      : ApiFailure(raw: error.toString(), message: error.toString());

  @override
  Future<String?> pickPackage() async => null;

  @override
  Future<ContentPackageImportReceipt> importPackage({
    required String mediaId,
    required String packagePath,
  }) async => ContentPackageImportReceipt(
    manifestSha256: 'sha256:${'c' * 64}',
    track: SubtitleTrack(id: 'track-$mediaId', cues: const []),
  );

  @override
  Future<ListenGenProcessRun> startGeneration(
    ContentPackageGenerationRequest request,
  ) async {
    requests.add(request);
    final run = TestContentPackageRun();
    runs.add(run);
    return run;
  }
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
  });

  /// True makes registration throw the way a core rejection does.
  final bool failRegister;

  final int? mediaDurationMs;

  /// False stands in for a disconnected core: nothing can be asked.
  final bool available;

  /// True makes the listing throw, the way a broken core connection does.
  final bool failListing;

  final List<MediaLibraryEntry> _entries = [];

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
  Future<MediaItem> registerMedia(String path, {int? durationMs}) async {
    if (failRegister) throw StateError('register failed');
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

MediaSource testMediaSource(String id, {String? name}) => MediaSource(
  id: id,
  name: name ?? id,
  language: 'en',
  description: 'Source $id',
  cover: ChannelCoverTone.slate,
  type: MediaSourceType.youtube,
  avatarUrl: null,
);

MediaEntry testMediaEntry(String id, String sourceId) => MediaEntry(
  id: id,
  sourceId: sourceId,
  title: 'Entry $id',
  description: '',
  durationMs: 300000,
  language: 'en',
  publishedOn: '2026-08-01',
  thumbnailUrl: null,
  viewCount: 0,
  hasPackage: false,
  videoUrl: 'https://www.youtube.com/watch?v=$id',
);

/// A discovery feed the test drives: which sources exist, which entries each
/// one answers with, which of them fail, and — through [gates] — when they
/// answer at all, so the in-flight window is observable.
class TestDiscoveryRepository implements DiscoveryRepository {
  TestDiscoveryRepository({
    List<MediaSource> sources = const [],
    Map<String, List<MediaEntry>> entries = const {},
  }) : _sources = List.of(sources),
       _entries = Map.of(entries);

  final List<MediaSource> _sources;
  final Map<String, List<MediaEntry>> _entries;

  /// Set to make `sources()` throw instead of answering.
  bool failSources = false;

  /// Sources whose feed throws instead of answering.
  final failingSources = <String>{};

  /// A source's feed waits on its gate before answering.
  final gates = <String, Completer<void>>{};

  @override
  Future<List<MediaSource>> sources() async {
    if (failSources) throw StateError('source list unavailable');
    return List.unmodifiable(_sources);
  }

  @override
  Future<List<MediaEntry>> entriesFor(String sourceId) async {
    await gates[sourceId]?.future;
    if (failingSources.contains(sourceId)) {
      throw StateError('feed for $sourceId unavailable');
    }
    return List.unmodifiable(_entries[sourceId] ?? const <MediaEntry>[]);
  }

  @override
  Future<PackageStatus> checkPackage(String entryId) async =>
      PackageStatus.undetermined;

  @override
  Future<MediaEntry> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => throw UnimplementedError();

  @override
  Future<MediaSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) => throw UnimplementedError();
}
