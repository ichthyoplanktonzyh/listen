import 'dart:async';
import 'package:llplayer_next/models/media_download.dart';
import 'package:llplayer_next/models/media_resolution.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/models/runtime_resources.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/data/repositories/transcription_repository.dart';
import 'package:llplayer_next/data/repositories/media_library_repository.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/saved_vocabulary_count.dart';
import 'package:llplayer_next/models/timeline.dart';
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

class TestMediaImportRepository implements MediaImportRepository {
  TestMediaImportRepository();

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
  Future<String> extractTextSubtitle(
    String mediaPath,
    EmbeddedSubtitle subtitle,
  ) async => '';
}

class TestTranscriptionRepository implements TranscriptionRepository {
  final Map<String, TranscriptionJobView> _jobs = {};

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: error.toString(), message: error.toString());

  @override
  Future<List<TranscriptionProviderView>> providers() async => [];

  @override
  Future<List<TranscriptionModelView>> models() async {
    return const [
      TranscriptionModelView(
        id: 'whisper-base',
        displayName: 'Whisper Base',
        revision: '1',
        sizeBytes: 1000,
        quality: 'medium',
        englishOnly: false,
        state: 'installed',
        installedBytes: 1000,
        license: 'MIT',
      ),
    ];
  }

  @override
  Future<List<TranscriptionJobView>> jobs() async {
    final updated = <String, TranscriptionJobView>{};
    _jobs.forEach((key, job) {
      if (job.status == 'completed') {
        updated[key] = job;
      } else {
        final nextProgress = job.phaseProgress + 40;
        if (nextProgress >= 100) {
          updated[key] = TranscriptionJobView(
            id: job.id,
            mediaId: job.mediaId,
            mediaTitle: job.mediaTitle,
            modelId: job.modelId,
            destination: job.destination,
            status: 'completed',
            phaseProgress: 100,
            createdAtMs: job.createdAtMs,
          );
        } else {
          updated[key] = TranscriptionJobView(
            id: job.id,
            mediaId: job.mediaId,
            mediaTitle: job.mediaTitle,
            modelId: job.modelId,
            destination: job.destination,
            status: 'transcribing',
            phaseProgress: nextProgress,
            createdAtMs: job.createdAtMs,
          );
        }
      }
    });
    _jobs.addAll(updated);
    return _jobs.values.toList();
  }

  @override
  Future<void> createJob({
    required String mediaId,
    required String modelId,
    required bool secondary,
    required bool translate,
    String? language,
    required bool force,
  }) async {
    _jobs[mediaId] = TranscriptionJobView(
      id: 'job-$mediaId',
      mediaId: mediaId,
      mediaTitle: 'Title',
      modelId: modelId,
      destination: 'dest',
      status: 'transcribing',
      phaseProgress: 25,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> registerCustomModel(String path) async {}
  @override
  Future<void> installModel(String id) async {}
  @override
  Future<void> cancelModelInstall(String id) async {}
  @override
  Future<void> deleteModel(String id) async {}
  @override
  Future<void> cancelJob(String id) async {
    _jobs.removeWhere((_, job) => job.id == id);
  }

  @override
  Future<void> retryJob(String id) async {}
  @override
  Future<SubtitleTrack> readSubtitle(String id) async =>
      throw UnimplementedError();
  @override
  Future<String> exportSubtitleSrt(String id) async => '';
  @override
  Future<void> archiveJob(String id) async {}
}

class TestMediaLibraryRepository implements MediaLibraryRepository {
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
  Future<MediaItem> registerMedia(String path) async {
    final regExp = RegExp(r'\[([^\]]+)\]');
    final match = regExp.firstMatch(path);
    final entryId = match?.group(1) ?? 'i-bbc-1';

    final media = MediaItem(
      id: 'media-$entryId',
      path: path,
      fingerprint: 'fp-$entryId',
      title: 'Downloaded Media $entryId',
      kind: 'video',
      durationMs: 300000,
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
