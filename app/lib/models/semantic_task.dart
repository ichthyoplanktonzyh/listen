// Phase 3.11 semantic-task DTOs, first consumed by the Reading Studio
// (Phase 3.13). Handwritten per ADR 0014; pinned to the Rust API shapes by
// test/contract/semantic_task_contract_test.dart against the committed gold
// fixture (testdata/semantic-task/gold-fixture-v1.json).
//
// These are read models plus request payload builders. All identity
// (fingerprint ids, hashes, timestamps) is minted server-side; the client
// never invents ids.

class RubricPointView {
  const RubricPointView({
    required this.pointId,
    required this.importance,
    required this.statement,
    this.acceptedParaphraseNotes,
  });

  final String pointId;

  /// `required` or `optional`.
  final String importance;
  final String statement;
  final String? acceptedParaphraseNotes;

  factory RubricPointView.fromJson(Map<String, dynamic> json) =>
      RubricPointView(
        pointId: json['point_id'] as String,
        importance: json['importance'] as String? ?? 'required',
        statement: json['statement'] as String,
        acceptedParaphraseNotes: json['accepted_paraphrase_notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'point_id': pointId,
    'importance': importance,
    'statement': statement,
    'accepted_paraphrase_notes': acceptedParaphraseNotes,
  };
}

class RubricSourceView {
  const RubricSourceView({
    this.mediaId,
    this.trackId,
    required this.startMs,
    required this.endMs,
    required this.language,
    required this.transcriptSnapshot,
  });

  final String? mediaId;
  final String? trackId;
  final int startMs;
  final int endMs;
  final String language;
  final String transcriptSnapshot;

  factory RubricSourceView.fromJson(Map<String, dynamic> json) =>
      RubricSourceView(
        mediaId: json['media_id'] as String?,
        trackId: json['track_id'] as String?,
        startMs: (json['start_ms'] as num).toInt(),
        endMs: (json['end_ms'] as num).toInt(),
        language: json['language'] as String,
        transcriptSnapshot: json['transcript_snapshot'] as String,
      );

  Map<String, dynamic> toJson() => {
    'media_id': mediaId,
    'track_id': trackId,
    'start_ms': startMs,
    'end_ms': endMs,
    'language': language,
    'transcript_snapshot': transcriptSnapshot,
  };
}

class SemanticProvenanceView {
  const SemanticProvenanceView({
    required this.kind,
    this.detail,
    this.modelId,
    this.promptVersion,
    this.schemaVersion,
  });

  /// `fixture`, `manual`, or `llm`.
  final String kind;
  final String? detail;
  final String? modelId;
  final String? promptVersion;
  final String? schemaVersion;

  factory SemanticProvenanceView.fromJson(Map<String, dynamic> json) =>
      SemanticProvenanceView(
        kind: json['kind'] as String,
        detail: json['detail'] as String?,
        modelId: json['model_id'] as String?,
        promptVersion: json['prompt_version'] as String?,
        schemaVersion: json['schema_version'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'detail': detail,
    'model_id': modelId,
    'prompt_version': promptVersion,
    'schema_version': schemaVersion,
  };
}

class SemanticRubricView {
  const SemanticRubricView({
    required this.id,
    required this.purpose,
    required this.source,
    required this.responseLanguage,
    required this.points,
    required this.version,
    required this.provenance,
    required this.createdAtMs,
  });

  final String id;

  /// A `SemanticTaskKind` in snake_case (e.g. `reading_comprehension`).
  final String purpose;
  final RubricSourceView source;
  final String responseLanguage;
  final List<RubricPointView> points;
  final int version;
  final SemanticProvenanceView provenance;
  final int createdAtMs;

  factory SemanticRubricView.fromJson(Map<String, dynamic> json) =>
      SemanticRubricView(
        id: json['id'] as String,
        purpose: json['purpose'] as String,
        source: RubricSourceView.fromJson(
          json['source'] as Map<String, dynamic>,
        ),
        responseLanguage: json['response_language'] as String,
        points: (json['points'] as List<dynamic>)
            .map((p) => RubricPointView.fromJson(p as Map<String, dynamic>))
            .toList(growable: false),
        version: (json['version'] as num).toInt(),
        provenance: SemanticProvenanceView.fromJson(
          json['provenance'] as Map<String, dynamic>,
        ),
        createdAtMs: (json['created_at_ms'] as num).toInt(),
      );
}

class AttemptResponseView {
  const AttemptResponseView({
    required this.revision,
    this.rawTranscript,
    required this.transcript,
    required this.source,
    required this.language,
    required this.recordedAtMs,
  });

  final int revision;
  final String? rawTranscript;
  final String transcript;

  /// `typed` or `asr`.
  final String source;
  final String language;
  final int recordedAtMs;

  factory AttemptResponseView.fromJson(Map<String, dynamic> json) =>
      AttemptResponseView(
        revision: (json['revision'] as num).toInt(),
        rawTranscript: json['raw_transcript'] as String?,
        transcript: json['transcript'] as String,
        source: json['source'] as String,
        language: json['language'] as String,
        recordedAtMs: (json['recorded_at_ms'] as num).toInt(),
      );
}

class SemanticConditionsView {
  const SemanticConditionsView({
    required this.sourceTextVisible,
    this.audioPlayCount,
    required this.notesAllowed,
    this.speakingAssistance,
    this.speakingRecall,
    this.promptSnapshot,
  });

  final bool sourceTextVisible;
  final int? audioPlayCount;
  final bool notesAllowed;
  final String? speakingAssistance;
  final String? speakingRecall;
  final String? promptSnapshot;

  factory SemanticConditionsView.fromJson(Map<String, dynamic> json) =>
      SemanticConditionsView(
        sourceTextVisible: json['source_text_visible'] as bool,
        audioPlayCount: (json['audio_play_count'] as num?)?.toInt(),
        notesAllowed: json['notes_allowed'] as bool? ?? false,
        speakingAssistance: json['speaking_assistance'] as String?,
        speakingRecall: json['speaking_recall'] as String?,
        promptSnapshot: json['prompt_snapshot'] as String?,
      );
}

class SemanticAttemptView {
  const SemanticAttemptView({
    required this.id,
    required this.kind,
    required this.rubricId,
    required this.rubricVersion,
    required this.conditions,
    required this.responses,
    required this.status,
    required this.startedAtMs,
    this.endedAtMs,
  });

  final String id;
  final String kind;
  final String rubricId;
  final int rubricVersion;
  final SemanticConditionsView conditions;
  final List<AttemptResponseView> responses;

  /// `completed` or `abandoned`.
  final String status;
  final int startedAtMs;
  final int? endedAtMs;

  factory SemanticAttemptView.fromJson(Map<String, dynamic> json) =>
      SemanticAttemptView(
        id: json['id'] as String,
        kind: json['kind'] as String,
        rubricId: json['rubric_id'] as String,
        rubricVersion: (json['rubric_version'] as num).toInt(),
        conditions: SemanticConditionsView.fromJson(
          json['conditions'] as Map<String, dynamic>,
        ),
        responses: (json['responses'] as List<dynamic>)
            .map((r) => AttemptResponseView.fromJson(r as Map<String, dynamic>))
            .toList(growable: false),
        status: json['status'] as String,
        startedAtMs: (json['started_at_ms'] as num).toInt(),
        endedAtMs: (json['ended_at_ms'] as num?)?.toInt(),
      );
}

class ResponseSpanView {
  const ResponseSpanView({required this.startChar, required this.endChar});

  final int startChar;
  final int endChar;

  factory ResponseSpanView.fromJson(Map<String, dynamic> json) =>
      ResponseSpanView(
        startChar: (json['start_char'] as num).toInt(),
        endChar: (json['end_char'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
    'start_char': startChar,
    'end_char': endChar,
  };
}

class PointJudgmentView {
  const PointJudgmentView({
    required this.pointId,
    required this.verdict,
    required this.supportingSpans,
  });

  final String pointId;

  /// `covered`, `partial`, `missing`, or `uncertain`.
  final String verdict;
  final List<ResponseSpanView> supportingSpans;

  factory PointJudgmentView.fromJson(
    Map<String, dynamic> json,
  ) => PointJudgmentView(
    pointId: json['point_id'] as String,
    verdict: json['verdict'] as String,
    supportingSpans: (json['supporting_spans'] as List<dynamic>? ?? const [])
        .map((s) => ResponseSpanView.fromJson(s as Map<String, dynamic>))
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'point_id': pointId,
    'verdict': verdict,
    'supporting_spans': supportingSpans.map((s) => s.toJson()).toList(),
  };
}

class JudgmentAbstainView {
  const JudgmentAbstainView({required this.reason, this.note});

  final String reason;
  final String? note;

  factory JudgmentAbstainView.fromJson(Map<String, dynamic> json) =>
      JudgmentAbstainView(
        reason: json['reason'] as String,
        note: json['note'] as String?,
      );
}

class SemanticJudgmentView {
  const SemanticJudgmentView({
    required this.id,
    required this.attemptId,
    required this.responseRevision,
    required this.rubricId,
    required this.rubricVersion,
    required this.rubricSourceSha256,
    required this.points,
    this.abstain,
    required this.provenance,
    required this.evidenceClass,
    required this.createdAtMs,
  });

  final String id;
  final String attemptId;
  final int responseRevision;
  final String rubricId;
  final int rubricVersion;
  final String rubricSourceSha256;
  final List<PointJudgmentView> points;
  final JudgmentAbstainView? abstain;
  final SemanticProvenanceView provenance;
  final String evidenceClass;
  final int createdAtMs;

  bool get isAbstain => abstain != null;

  String? verdictFor(String pointId) {
    for (final point in points) {
      if (point.pointId == pointId) return point.verdict;
    }
    return null;
  }

  factory SemanticJudgmentView.fromJson(Map<String, dynamic> json) =>
      SemanticJudgmentView(
        id: json['id'] as String,
        attemptId: json['attempt_id'] as String,
        responseRevision: (json['response_revision'] as num).toInt(),
        rubricId: json['rubric_id'] as String,
        rubricVersion: (json['rubric_version'] as num).toInt(),
        rubricSourceSha256: json['rubric_source_sha256'] as String,
        points: (json['points'] as List<dynamic>? ?? const [])
            .map((p) => PointJudgmentView.fromJson(p as Map<String, dynamic>))
            .toList(growable: false),
        abstain: json['abstain'] == null
            ? null
            : JudgmentAbstainView.fromJson(
                json['abstain'] as Map<String, dynamic>,
              ),
        provenance: SemanticProvenanceView.fromJson(
          json['provenance'] as Map<String, dynamic>,
        ),
        evidenceClass: json['evidence_class'] as String,
        createdAtMs: (json['created_at_ms'] as num).toInt(),
      );
}

class JudgmentAdjudicationView {
  const JudgmentAdjudicationView({
    required this.id,
    required this.judgmentId,
    required this.pointId,
    required this.priorVerdict,
    required this.userVerdict,
    this.note,
    required this.occurredAtMs,
  });

  final String id;
  final String judgmentId;
  final String pointId;
  final String priorVerdict;
  final String userVerdict;
  final String? note;
  final int occurredAtMs;

  factory JudgmentAdjudicationView.fromJson(Map<String, dynamic> json) =>
      JudgmentAdjudicationView(
        id: json['id'] as String,
        judgmentId: json['judgment_id'] as String,
        pointId: json['point_id'] as String,
        priorVerdict: json['prior_verdict'] as String,
        userVerdict: json['user_verdict'] as String,
        note: json['note'] as String?,
        occurredAtMs: (json['occurred_at_ms'] as num).toInt(),
      );
}

class WritingFeedbackFindingView {
  const WritingFeedbackFindingView({
    required this.id,
    required this.attemptId,
    required this.responseRevision,
    required this.layer,
    required this.severity,
    this.sourceSpan,
    required this.message,
    this.suggestedReplacement,
    required this.providerId,
  });

  final String id;
  final String attemptId;
  final int responseRevision;
  final String layer;
  final String severity;
  final ResponseSpanView? sourceSpan;
  final String message;
  final String? suggestedReplacement;
  final String providerId;

  factory WritingFeedbackFindingView.fromJson(Map<String, dynamic> json) =>
      WritingFeedbackFindingView(
        id: json['id'] as String,
        attemptId: json['attempt_id'] as String,
        responseRevision: (json['response_revision'] as num).toInt(),
        layer: json['layer'] as String,
        severity: json['severity'] as String,
        sourceSpan: json['source_span'] == null
            ? null
            : ResponseSpanView.fromJson(
                json['source_span'] as Map<String, dynamic>,
              ),
        message: json['message'] as String,
        suggestedReplacement: json['suggested_replacement'] as String?,
        providerId:
            (json['provenance'] as Map<String, dynamic>)['provider_id']
                as String,
      );
}

class WritingDraftView {
  const WritingDraftView({
    required this.rubricId,
    required this.promptSnapshot,
    required this.transcript,
    required this.updatedAtMs,
  });

  final String rubricId;
  final String promptSnapshot;
  final String transcript;
  final int updatedAtMs;

  factory WritingDraftView.fromJson(Map<String, dynamic> json) =>
      WritingDraftView(
        rubricId: json['rubric_id'] as String,
        promptSnapshot: json['prompt_snapshot'] as String,
        transcript: json['transcript'] as String,
        updatedAtMs: (json['updated_at_ms'] as num).toInt(),
      );
}

class WritingFindingDispositionView {
  const WritingFindingDispositionView({
    required this.id,
    required this.findingId,
    required this.decision,
    this.resultingAttemptId,
    this.resultingResponseRevision,
  });

  final String id;
  final String findingId;
  final String decision;
  final String? resultingAttemptId;
  final int? resultingResponseRevision;

  factory WritingFindingDispositionView.fromJson(Map<String, dynamic> json) =>
      WritingFindingDispositionView(
        id: json['id'] as String,
        findingId: json['finding_id'] as String,
        decision: json['decision'] as String,
        resultingAttemptId: json['resulting_attempt_id'] as String?,
        resultingResponseRevision: (json['resulting_response_revision'] as num?)
            ?.toInt(),
      );
}
