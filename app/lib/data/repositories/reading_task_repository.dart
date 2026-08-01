import '../../models/api_failure.dart';
import '../../models/semantic_task.dart';
import '../../services/api_service.dart';

/// Narrow data boundary for reading/listening semantic tasks.
abstract interface class ReadingTaskRepository {
  bool get isAvailable;

  Future<SemanticRubricView?> lookupRubric({
    required String? mediaId,
    required int startMs,
    required int endMs,
    required String purpose,
    required String responseLanguage,
    required String transcriptSnapshot,
  });

  Future<List<SemanticAttemptView>> rubricAttempts(String rubricId);

  Future<List<SemanticJudgmentView>> attemptJudgments(String attemptId);

  Future<List<JudgmentAdjudicationView>> judgmentAdjudications(
    String judgmentId,
  );

  Future<({String? judgment, String? rubric})> providers();

  Future<RubricDraftView> generateRubric({
    required String providerId,
    required String purpose,
    required String sourceLanguage,
    required String responseLanguage,
    required String transcriptSnapshot,
  });

  Future<SemanticRubricView> saveRubric({
    required String purpose,
    required RubricSourceView source,
    required String responseLanguage,
    required List<RubricPointView> points,
    required SemanticProvenanceView provenance,
    required int startMs,
    required int endMs,
    required String transcriptSnapshot,
  });

  Future<SemanticAttemptView> createAttempt({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required bool sourceTextVisible,
    required int audioPlayCount,
    required String? l1Trigger,
    required String responseTranscript,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  });

  Future<SemanticJudgmentView> createJudgment({
    required String attemptId,
    required int responseRevision,
    required String rubricId,
    required int rubricVersion,
    required String rubricTranscriptSnapshot,
    required String responseTranscript,
    required List<PointJudgmentView> points,
    required SemanticProvenanceView provenance,
    required String evidenceClass,
  });

  Future<JudgmentAdjudicationView> createAdjudication({
    required String judgmentId,
    required String pointId,
    required String priorVerdict,
    required String userVerdict,
    String? note,
  });

  Future<SemanticJudgmentView> judgeWithProvider({
    required String providerId,
    required String attemptId,
    required int responseRevision,
  });
}

class ReadingTaskRepositoryFailure implements Exception {
  const ReadingTaskRepositoryFailure(this.detail);

  final ApiFailure detail;
}

/// Local-core adapter. The supplier follows core restarts without retaining a
/// stale API client inside the long-lived ViewModel graph.
class LocalReadingTaskRepository implements ReadingTaskRepository {
  LocalReadingTaskRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Reading task API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  Future<T> _request<T>(Future<T> Function(LocalApi api) request) async {
    try {
      return await request(_api);
    } catch (error) {
      throw ReadingTaskRepositoryFailure(describeApiFailure(error));
    }
  }

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
  Future<List<SemanticAttemptView>> rubricAttempts(String rubricId) =>
      _request((api) => api.semanticRubricAttempts(rubricId));

  @override
  Future<List<SemanticJudgmentView>> attemptJudgments(String attemptId) =>
      _request((api) => api.semanticAttemptJudgments(attemptId));

  @override
  Future<List<JudgmentAdjudicationView>> judgmentAdjudications(
    String judgmentId,
  ) => _request((api) => api.judgmentAdjudications(judgmentId));

  @override
  Future<({String? judgment, String? rubric})> providers() =>
      _request((api) async {
        final providers = await api.llmProviders();
        return (
          judgment: pickLlmProviderId(providers, 'semantic_judgment'),
          rubric: pickLlmProviderId(providers, 'rubric_generation'),
        );
      });

  @override
  Future<RubricDraftView> generateRubric({
    required String providerId,
    required String purpose,
    required String sourceLanguage,
    required String responseLanguage,
    required String transcriptSnapshot,
  }) => _request(
    (api) => api.generateRubricViaLlmProvider(
      providerId,
      purpose: purpose,
      sourceLanguage: sourceLanguage,
      responseLanguage: responseLanguage,
      transcriptSnapshot: transcriptSnapshot,
    ),
  );

  @override
  Future<SemanticRubricView> saveRubric({
    required String purpose,
    required RubricSourceView source,
    required String responseLanguage,
    required List<RubricPointView> points,
    required SemanticProvenanceView provenance,
    required int startMs,
    required int endMs,
    required String transcriptSnapshot,
  }) async {
    try {
      return await _api.createSemanticRubric(
        purpose: purpose,
        source: source,
        responseLanguage: responseLanguage,
        points: points,
        provenance: provenance,
      );
    } catch (createError) {
      try {
        final recovered = await _api.lookupSemanticRubric(
          mediaId: source.mediaId,
          startMs: startMs,
          endMs: endMs,
          purpose: purpose,
          responseLanguage: responseLanguage,
          transcriptSnapshot: transcriptSnapshot,
        );
        if (recovered != null) return recovered;
      } catch (_) {
        // Preserve the original create failure when recovery also fails.
      }
      throw ReadingTaskRepositoryFailure(describeApiFailure(createError));
    }
  }

  @override
  Future<SemanticAttemptView> createAttempt({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required bool sourceTextVisible,
    required int audioPlayCount,
    required String? l1Trigger,
    required String responseTranscript,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  }) => _request(
    (api) => api.createSemanticAttempt(
      kind: kind,
      target: target,
      rubricId: rubricId,
      rubricVersion: rubricVersion,
      sourceTextVisible: sourceTextVisible,
      audioPlayCount: audioPlayCount,
      l1Trigger: l1Trigger,
      responseTranscript: responseTranscript,
      responseLanguage: responseLanguage,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
    ),
  );

  @override
  Future<SemanticJudgmentView> createJudgment({
    required String attemptId,
    required int responseRevision,
    required String rubricId,
    required int rubricVersion,
    required String rubricTranscriptSnapshot,
    required String responseTranscript,
    required List<PointJudgmentView> points,
    required SemanticProvenanceView provenance,
    required String evidenceClass,
  }) => _request(
    (api) => api.createSemanticJudgment(
      attemptId: attemptId,
      responseRevision: responseRevision,
      rubricId: rubricId,
      rubricVersion: rubricVersion,
      rubricTranscriptSnapshot: rubricTranscriptSnapshot,
      responseTranscript: responseTranscript,
      points: points,
      provenance: provenance,
      evidenceClass: evidenceClass,
    ),
  );

  @override
  Future<JudgmentAdjudicationView> createAdjudication({
    required String judgmentId,
    required String pointId,
    required String priorVerdict,
    required String userVerdict,
    String? note,
  }) => _request(
    (api) => api.createJudgmentAdjudication(
      judgmentId: judgmentId,
      pointId: pointId,
      priorVerdict: priorVerdict,
      userVerdict: userVerdict,
      note: note,
    ),
  );

  @override
  Future<SemanticJudgmentView> judgeWithProvider({
    required String providerId,
    required String attemptId,
    required int responseRevision,
  }) => _request(
    (api) => api.judgeViaLlmProvider(
      providerId,
      attemptId: attemptId,
      responseRevision: responseRevision,
    ),
  );
}
