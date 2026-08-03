import 'dart:async';
import 'package:llplayer_next/models/media_download.dart';
import 'package:llplayer_next/models/media_resolution.dart';
import 'package:llplayer_next/models/types.dart';
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

class TestMediaImportRepository implements MediaImportRepository {
  TestMediaImportRepository({this.probedDurationMs});

  final int? probedDurationMs;

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
    final completer = Completer<String?>();
    completers[entryId] = completer;
    return TestMediaDownloadHandle(entryId, completer);
  }

  @override
  Future<ResolvedVideoDetails> resolveVideoDetails(String pageUrl) async =>
      const ResolvedVideoDetails(
        id: '',
        title: 'YouTube Video',
        description: '',
        durationMs: 0,
        viewCount: 0,
        thumbnail: null,
        channelId: '',
        uploadDate: '',
      );
  @override
  Future<ResolvedChannelDetails> resolveChannelDetails(
    String channelUrl,
  ) async => const ResolvedChannelDetails(id: '', name: '');
  @override
  Future<List<EmbeddedSubtitle>> probeSubtitles(String mediaPath) async => [];
  @override
  Future<int?> probeMediaDurationMs(String mediaPath) async =>
      probedDurationMs;
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

class TestMediaLibraryRepository implements MediaLibraryRepository {
  TestMediaLibraryRepository({this.mediaDurationMs = 300000});

  final int? mediaDurationMs;

  final List<MediaLibraryEntry> _entries = [];

  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());

  @override
  Future<SavedVocabularyCount> savedVocabularyCount({
    required String language,
  }) async => const SavedVocabularyCount(total: 0, capped: false);

  @override
  Future<List<MediaLibraryEntry>> listMediaLibrary() async => _entries;

  @override
  Future<MediaLibraryEntry> setTriageIntent(
    String mediaId,
    String? intent,
  ) async => throw UnimplementedError();

  @override
  Future<MediaItem> registerMedia(String path, {int? durationMs}) async {
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
