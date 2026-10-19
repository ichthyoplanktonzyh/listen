import '../../models/api_failure.dart';
import '../../services/api_service.dart';

/// Data boundary for the speaking channel's learner context and completion
/// handoff. Recording and task concerns remain in their dedicated services.
abstract interface class SpeakingSessionRepository {
  bool get isAvailable;

  Future<String?> learnerL1Language();

  Future<void> recordPersonalExpressionAttempt({
    required String patternId,
    required String patternVersionId,
    required String responseText,
    required String rawTranscript,
    required String recordingAssetId,
    required String semanticAttemptId,
    required String selfAssessment,
  });
}

class SpeakingSessionRepositoryFailure implements Exception {
  const SpeakingSessionRepositoryFailure(this.detail);

  final ApiFailure detail;
}

class LocalSpeakingSessionRepository implements SpeakingSessionRepository {
  LocalSpeakingSessionRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Speaking session API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  Future<T> _request<T>(Future<T> Function(LocalApi api) request) async {
    try {
      return await request(_api);
    } catch (error) {
      throw SpeakingSessionRepositoryFailure(describeApiFailure(error));
    }
  }

  @override
  Future<String?> learnerL1Language() =>
      _request((api) async => (await api.learnerProfile()).l1Language);

  @override
  Future<void> recordPersonalExpressionAttempt({
    required String patternId,
    required String patternVersionId,
    required String responseText,
    required String rawTranscript,
    required String recordingAssetId,
    required String semanticAttemptId,
    required String selfAssessment,
  }) => _request((api) async {
    await api.recordPersonalExpressionAttempt(
      patternId: patternId,
      patternVersionId: patternVersionId,
      channel: 'speaking',
      assistance: 'no_text',
      responseText: responseText,
      rawTranscript: rawTranscript,
      recordingAssetId: recordingAssetId,
      semanticAttemptId: semanticAttemptId,
      selfAssessment: selfAssessment,
    );
  });
}
