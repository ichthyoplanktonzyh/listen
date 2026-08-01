import '../../models/api_failure.dart';
import '../../models/runtime_resources.dart';
import '../../models/timeline.dart';
import '../../services/api_service.dart';

abstract interface class TranscriptionRepository {
  ApiFailure failureDetail(Object error);
  Future<List<TranscriptionProviderView>> providers();
  Future<List<TranscriptionModelView>> models();
  Future<List<TranscriptionJobView>> jobs();
  Future<void> createJob({
    required String mediaId,
    required String modelId,
    required bool secondary,
    required bool translate,
    String? language,
    required bool force,
  });
  Future<void> registerCustomModel(String path);
  Future<void> installModel(String id);
  Future<void> cancelModelInstall(String id);
  Future<void> deleteModel(String id);
  Future<void> cancelJob(String id);
  Future<void> retryJob(String id);
  Future<SubtitleTrack> readSubtitle(String id);
  Future<String> exportSubtitleSrt(String id);
  Future<void> archiveJob(String id);
}

final class LocalTranscriptionRepository implements TranscriptionRepository {
  const LocalTranscriptionRepository(this._api);
  final LocalApi _api;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);
  @override
  Future<List<TranscriptionProviderView>> providers() =>
      _api.transcriptionProviders();
  @override
  Future<List<TranscriptionModelView>> models() => _api.transcriptionModels();
  @override
  Future<List<TranscriptionJobView>> jobs() => _api.transcriptionJobs();
  @override
  Future<void> createJob({
    required String mediaId,
    required String modelId,
    required bool secondary,
    required bool translate,
    String? language,
    required bool force,
  }) async {
    await _api.createTranscriptionJob(
      mediaId: mediaId,
      modelId: modelId,
      secondary: secondary,
      translate: translate,
      language: language,
      force: force,
    );
  }

  @override
  Future<void> registerCustomModel(String path) async {
    await _api.registerCustomTranscriptionModel(path);
  }

  @override
  Future<void> installModel(String id) async {
    await _api.installTranscriptionModel(id);
  }

  @override
  Future<void> cancelModelInstall(String id) async {
    await _api.cancelTranscriptionModelInstall(id);
  }

  @override
  Future<void> deleteModel(String id) => _api.deleteTranscriptionModel(id);
  @override
  Future<void> cancelJob(String id) => _api.cancelTranscriptionJob(id);
  @override
  Future<void> retryJob(String id) async {
    await _api.retryTranscriptionJob(id);
  }

  @override
  Future<SubtitleTrack> readSubtitle(String id) => _api.readSubtitle(id);
  @override
  Future<String> exportSubtitleSrt(String id) => _api.exportSubtitleSrt(id);
  @override
  Future<void> archiveJob(String id) => _api.archiveTranscriptionJob(id);
}
