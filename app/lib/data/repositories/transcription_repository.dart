import '../../models/api_failure.dart';
import '../../models/runtime_resources.dart';
import '../../services/api_service.dart';

/// The transcription model surface retained for learner recording and realtime
/// conversation: selecting an installed model, installing/cancelling/removing
/// one, and registering a custom one.
///
/// Whole-media transcription jobs are no longer part of this repository. The
/// app prepares transcripts through the pinned listen-gen package journey
/// instead of Core's `/v1/transcription/jobs` surface, so the job operations
/// (create/cancel/retry/archive/read/export) were removed along with the
/// transcription center that consumed them.
abstract interface class TranscriptionRepository {
  ApiFailure failureDetail(Object error);
  Future<List<TranscriptionProviderView>> providers();
  Future<List<TranscriptionModelView>> models();
  Future<void> registerCustomModel(String path);
  Future<void> installModel(String id);
  Future<void> cancelModelInstall(String id);
  Future<void> deleteModel(String id);
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
}
