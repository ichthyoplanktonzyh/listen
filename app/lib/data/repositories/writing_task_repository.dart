import '../../models/api_failure.dart';
import '../../models/semantic_task.dart';
import '../../services/api_service.dart';

class WritingTaskOpenData {
  WritingTaskOpenData({
    required this.rubric,
    required List<SemanticAttemptView> attempts,
    this.draft,
  }) : attempts = List.unmodifiable(attempts);

  final SemanticRubricView rubric;
  final List<SemanticAttemptView> attempts;
  final WritingDraftView? draft;
}

class WritingTaskSubmission {
  const WritingTaskSubmission({required this.attempt, this.feedbackProviderId});

  final SemanticAttemptView attempt;
  final String? feedbackProviderId;
}

abstract interface class WritingTaskRepository {
  bool get isAvailable;

  Future<WritingTaskOpenData> openTask({
    required String purpose,
    required RubricSourceView source,
    required String responseLanguage,
    required List<RubricPointView> points,
  });

  Future<void> saveDraft({
    required String rubricId,
    required String promptSnapshot,
    required String transcript,
  });

  Future<WritingTaskSubmission> submitDraft({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required bool sourceTextVisible,
    required int? audioPlayCount,
    required String promptSnapshot,
    required String transcript,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  });

  Future<String> requestLlmFeedback({
    required String providerId,
    required String attemptId,
    required int responseRevision,
  });

  Future<List<WritingFeedbackFindingView>> requestLocalFeedback({
    required String attemptId,
    required int responseRevision,
  });

  Future<SemanticAttemptView> submitRevision({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required bool sourceTextVisible,
    required int? audioPlayCount,
    required String promptSnapshot,
    required String original,
    required String revised,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
    required Map<String, String> decisions,
    required List<WritingFeedbackFindingView> findings,
  });
}

class WritingTaskRepositoryFailure implements Exception {
  const WritingTaskRepositoryFailure(this.detail);

  final ApiFailure detail;
}

class LocalWritingTaskRepository implements WritingTaskRepository {
  LocalWritingTaskRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Writing task API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  Future<T> _request<T>(Future<T> Function(LocalApi api) request) async {
    try {
      return await request(_api);
    } catch (error) {
      throw WritingTaskRepositoryFailure(describeApiFailure(error));
    }
  }

  @override
  Future<WritingTaskOpenData> openTask({
    required String purpose,
    required RubricSourceView source,
    required String responseLanguage,
    required List<RubricPointView> points,
  }) => _request((api) async {
    Future<SemanticRubricView?> lookup() => api.lookupSemanticRubric(
      mediaId: source.mediaId,
      startMs: source.startMs,
      endMs: source.endMs,
      purpose: purpose,
      responseLanguage: responseLanguage,
      transcriptSnapshot: source.transcriptSnapshot,
    );

    var rubric = await lookup();
    if (rubric == null) {
      try {
        rubric = await api.createSemanticRubric(
          purpose: purpose,
          source: source,
          responseLanguage: responseLanguage,
          points: points,
          provenance: const SemanticProvenanceView(
            kind: 'manual',
            detail: 'writing studio fixed task rubric',
          ),
        );
      } catch (createError) {
        rubric = await lookup();
        if (rubric == null) rethrow;
      }
    }
    final attempts = await api.semanticRubricAttempts(rubric.id);
    final draft = await api.writingDraft(rubric.id);
    return WritingTaskOpenData(
      rubric: rubric,
      attempts: attempts,
      draft: draft,
    );
  });

  @override
  Future<void> saveDraft({
    required String rubricId,
    required String promptSnapshot,
    required String transcript,
  }) => _request(
    (api) => api.saveWritingDraft(
      rubricId: rubricId,
      promptSnapshot: promptSnapshot,
      transcript: transcript,
    ),
  );

  @override
  Future<WritingTaskSubmission> submitDraft({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required bool sourceTextVisible,
    required int? audioPlayCount,
    required String promptSnapshot,
    required String transcript,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  }) => _request((api) async {
    final attempt = await api.createWritingAttempt(
      kind: kind,
      target: target,
      rubricId: rubricId,
      rubricVersion: rubricVersion,
      sourceTextVisible: sourceTextVisible,
      audioPlayCount: audioPlayCount,
      promptSnapshot: promptSnapshot,
      revisions: [transcript],
      responseLanguage: responseLanguage,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
    );
    try {
      await api.deleteWritingDraft(rubricId);
    } catch (_) {
      // The immutable attempt is authoritative; stale scratch data is safe.
    }
    String? providerId;
    try {
      providerId = await api.preferredLlmProviderId('semantic_judgment');
    } catch (_) {
      // Provider discovery is optional and must not fail submission.
    }
    return WritingTaskSubmission(
      attempt: attempt,
      feedbackProviderId: providerId,
    );
  });

  @override
  Future<String> requestLlmFeedback({
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
  Future<List<WritingFeedbackFindingView>> requestLocalFeedback({
    required String attemptId,
    required int responseRevision,
  }) => _request(
    (api) => api.generateLocalWritingFindings(attemptId, responseRevision),
  );

  @override
  Future<SemanticAttemptView> submitRevision({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required bool sourceTextVisible,
    required int? audioPlayCount,
    required String promptSnapshot,
    required String original,
    required String revised,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
    required Map<String, String> decisions,
    required List<WritingFeedbackFindingView> findings,
  }) => _request((api) async {
    final attempt = await api.createWritingAttempt(
      kind: kind,
      target: target,
      rubricId: rubricId,
      rubricVersion: rubricVersion,
      sourceTextVisible: sourceTextVisible,
      audioPlayCount: audioPlayCount,
      promptSnapshot: promptSnapshot,
      revisions: [original, revised],
      responseLanguage: responseLanguage,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
    );
    for (final finding in findings) {
      final decision = decisions[finding.id];
      if (decision == null) continue;
      await api.createWritingDisposition(
        findingId: finding.id,
        decision: decision,
        resultingAttemptId: decision == 'accepted' ? attempt.id : null,
        resultingRevision: decision == 'accepted' ? 2 : null,
      );
    }
    return attempt;
  });
}
