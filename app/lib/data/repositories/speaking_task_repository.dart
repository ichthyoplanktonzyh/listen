import '../../models/api_failure.dart';
import '../../models/practice.dart';
import '../../models/runtime_resources.dart';
import '../../models/semantic_task.dart';
import '../../services/api_service.dart';

abstract interface class SpeakingTaskRepository {
  bool get isAvailable;

  Future<SemanticRubricView?> lookupRubric({
    required String? mediaId,
    required int startMs,
    required int endMs,
    required String purpose,
    required String responseLanguage,
    required String transcriptSnapshot,
  });
  Future<SemanticRubricView> createRubric({
    required String purpose,
    required RubricSourceView source,
    required String responseLanguage,
    required List<RubricPointView> points,
    required SemanticProvenanceView provenance,
  });
  Future<List<TranscriptionModelView>> transcriptionModels();
  Future<RecordingAsset> createRecording(CreateRecordingAsset input);
  Future<RecordingAudioFacts> recordingAudioFacts(String recordingId);
  Future<RecordingTranscriptionJobView> createTranscription({
    required String recordingId,
    required String modelId,
    required String language,
  });
  Future<RecordingTranscriptionJobView> readTranscription(String id);
  Future<RecordingTranscriptionJobView> cancelTranscription(String id);
  Future<SemanticAttemptView> createSpokenAttempt({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required int audioPlayCount,
    required String? speakingAssistance,
    required String speakingRecall,
    required String? promptSnapshot,
    required String recordingAssetId,
    required String rawTranscript,
    required String correctedTranscript,
    required String asrReliability,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  });
  Future<String?> preferredFeedbackProvider();
  Future<String> requestFeedback({
    required String providerId,
    required String attemptId,
    required int responseRevision,
  });
  Future<ReviewItem> createReview(CreateReviewItem input);
  Future<void> submitReview(String reviewItemId, String rating);
  Future<void> confirmTarget({
    required String attemptId,
    required String lexicalEntryId,
    required String surfaceForm,
    required String sentenceId,
  });
}

final class LocalSpeakingTaskRepository implements SpeakingTaskRepository {
  const LocalSpeakingTaskRepository(this._api);

  final LocalApi? Function() _api;

  LocalApi get _current =>
      _api() ?? (throw StateError('Local core is unavailable'));

  Future<T> _request<T>(Future<T> Function(LocalApi api) operation) async {
    try {
      return await operation(_current);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(describeApiFailure(error), stackTrace);
    }
  }

  @override
  bool get isAvailable => _api() != null;

  @override
  Future<SemanticRubricView?> lookupRubric({
    required String? mediaId,
    required int startMs,
    required int endMs,
    required String purpose,
    required String responseLanguage,
    required String transcriptSnapshot,
  }) => _request(
    (api) => api.lookupSemanticRubric(
      mediaId: mediaId,
      startMs: startMs,
      endMs: endMs,
      purpose: purpose,
      responseLanguage: responseLanguage,
      transcriptSnapshot: transcriptSnapshot,
    ),
  );

  @override
  Future<SemanticRubricView> createRubric({
    required String purpose,
    required RubricSourceView source,
    required String responseLanguage,
    required List<RubricPointView> points,
    required SemanticProvenanceView provenance,
  }) => _request(
    (api) => api.createSemanticRubric(
      purpose: purpose,
      source: source,
      responseLanguage: responseLanguage,
      points: points,
      provenance: provenance,
    ),
  );

  @override
  Future<List<TranscriptionModelView>> transcriptionModels() =>
      _request((api) => api.transcriptionModels());

  @override
  Future<RecordingAsset> createRecording(CreateRecordingAsset input) =>
      _request((api) => api.createRecordingAsset(input));

  @override
  Future<RecordingAudioFacts> recordingAudioFacts(String recordingId) =>
      _request((api) => api.recordingAudioFacts(recordingId));

  @override
  Future<RecordingTranscriptionJobView> createTranscription({
    required String recordingId,
    required String modelId,
    required String language,
  }) => _request(
    (api) => api.createRecordingTranscription(
      recordingId: recordingId,
      modelId: modelId,
      language: language,
    ),
  );

  @override
  Future<RecordingTranscriptionJobView> readTranscription(String id) =>
      _request((api) => api.recordingTranscriptionJob(id));

  @override
  Future<RecordingTranscriptionJobView> cancelTranscription(String id) =>
      _request((api) => api.cancelRecordingTranscription(id));

  @override
  Future<SemanticAttemptView> createSpokenAttempt({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required int audioPlayCount,
    required String? speakingAssistance,
    required String speakingRecall,
    required String? promptSnapshot,
    required String recordingAssetId,
    required String rawTranscript,
    required String correctedTranscript,
    required String asrReliability,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  }) => _request(
    (api) => api.createSpokenSemanticAttempt(
      kind: kind,
      target: target,
      rubricId: rubricId,
      rubricVersion: rubricVersion,
      audioPlayCount: audioPlayCount,
      speakingAssistance: speakingAssistance,
      speakingRecall: speakingRecall,
      promptSnapshot: promptSnapshot,
      recordingAssetId: recordingAssetId,
      rawTranscript: rawTranscript,
      correctedTranscript: correctedTranscript,
      asrReliability: asrReliability,
      responseLanguage: responseLanguage,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
    ),
  );

  @override
  Future<String?> preferredFeedbackProvider() =>
      _request((api) => api.preferredLlmProviderId('semantic_judgment'));

  @override
  Future<String> requestFeedback({
    required String providerId,
    required String attemptId,
    required int responseRevision,
  }) => _request(
    (api) => api.feedbackViaLlmProvider(
      providerId,
      attemptId: attemptId,
      responseRevision: responseRevision,
    ),
  );

  @override
  Future<ReviewItem> createReview(CreateReviewItem input) =>
      _request((api) => api.createReviewItem(input));

  @override
  Future<void> submitReview(String reviewItemId, String rating) async {
    await _request((api) => api.submitReviewAttempt(reviewItemId, rating));
  }

  @override
  Future<void> confirmTarget({
    required String attemptId,
    required String lexicalEntryId,
    required String surfaceForm,
    required String sentenceId,
  }) async {
    await _request(
      (api) => api.confirmSpeakingTarget(
        attemptId: attemptId,
        lexicalEntryId: lexicalEntryId,
        surfaceForm: surfaceForm,
        sentenceId: sentenceId,
      ),
    );
  }
}

final class UnavailableSpeakingTaskRepository
    implements SpeakingTaskRepository {
  const UnavailableSpeakingTaskRepository();
  Never get _unavailable => throw const ApiFailure(raw: 'unavailable');
  @override
  bool get isAvailable => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => _unavailable;
}
