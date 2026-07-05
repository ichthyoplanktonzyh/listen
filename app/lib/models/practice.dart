class PracticeSession {
  const PracticeSession({
    required this.id,
    required this.mode,
    this.mediaId,
    this.trackId,
    required this.source,
    required this.startedAtMs,
    this.endedAtMs,
  });

  factory PracticeSession.fromJson(Map<String, dynamic> json) =>
      PracticeSession(
        id: json['id'] as String,
        mode: json['mode'] as String,
        mediaId: json['media_id'] as String?,
        trackId: json['track_id'] as String?,
        source: json['source'] as String,
        startedAtMs: json['started_at_ms'] as int,
        endedAtMs: json['ended_at_ms'] as int?,
      );

  final String id;
  final String mode;
  final String? mediaId;
  final String? trackId;
  final String source;
  final int startedAtMs;
  final int? endedAtMs;

  PracticeSession copyWith({int? endedAtMs}) => PracticeSession(
    id: id,
    mode: mode,
    mediaId: mediaId,
    trackId: trackId,
    source: source,
    startedAtMs: startedAtMs,
    endedAtMs: endedAtMs ?? this.endedAtMs,
  );
}

class CreatePracticeSession {
  const CreatePracticeSession({
    required this.mode,
    this.mediaId,
    this.trackId,
    this.source,
  });

  final String mode;
  final String? mediaId;
  final String? trackId;
  final String? source;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'media_id': mediaId,
    'track_id': trackId,
    'source': source,
  };
}

class PracticeTarget {
  const PracticeTarget({
    required this.kind,
    this.id,
    this.sentenceId,
    this.chunkId,
    this.startMs,
    this.endMs,
  });

  factory PracticeTarget.fromJson(Map<String, dynamic> json) => PracticeTarget(
    kind: json['kind'] as String,
    id: json['id'] as String?,
    sentenceId: json['sentence_id'] as String?,
    chunkId: json['chunk_id'] as String?,
    startMs: json['start_ms'] as int?,
    endMs: json['end_ms'] as int?,
  );

  final String kind;
  final String? id;
  final String? sentenceId;
  final String? chunkId;
  final int? startMs;
  final int? endMs;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'sentence_id': sentenceId,
    'chunk_id': chunkId,
    'start_ms': startMs,
    'end_ms': endMs,
  };
}

class PracticeAnchor {
  const PracticeAnchor({
    required this.kind,
    required this.id,
    this.label,
    this.lexicalEntryId,
    this.sentenceId,
    this.tokenStart,
    this.tokenEnd,
    this.startMs,
    this.endMs,
  });

  factory PracticeAnchor.fromJson(Map<String, dynamic> json) => PracticeAnchor(
    kind: json['kind'] as String,
    id: json['id'] as String,
    label: json['label'] as String?,
    lexicalEntryId: json['lexical_entry_id'] as String?,
    sentenceId: json['sentence_id'] as String?,
    tokenStart: json['token_start'] as int?,
    tokenEnd: json['token_end'] as int?,
    startMs: json['start_ms'] as int?,
    endMs: json['end_ms'] as int?,
  );

  final String kind;
  final String id;
  final String? label;
  final String? lexicalEntryId;
  final String? sentenceId;
  final int? tokenStart;
  final int? tokenEnd;
  final int? startMs;
  final int? endMs;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'label': label,
    'lexical_entry_id': lexicalEntryId,
    'sentence_id': sentenceId,
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'start_ms': startMs,
    'end_ms': endMs,
  };
}

class PracticeItem {
  const PracticeItem({
    required this.id,
    this.sessionId,
    required this.kind,
    required this.target,
    required this.promptSnapshot,
    required this.expectedAnswer,
    required this.anchors,
    required this.createdAtMs,
  });

  factory PracticeItem.fromJson(Map<String, dynamic> json) => PracticeItem(
    id: json['id'] as String,
    sessionId: json['session_id'] as String?,
    kind: json['kind'] as String,
    target: PracticeTarget.fromJson(json['target'] as Map<String, dynamic>),
    promptSnapshot: json['prompt_snapshot'] as String,
    expectedAnswer: json['expected_answer'],
    anchors: ((json['anchors'] as List<dynamic>?) ?? const [])
        .map((value) => PracticeAnchor.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    createdAtMs: json['created_at_ms'] as int,
  );

  final String id;
  final String? sessionId;
  final String kind;
  final PracticeTarget target;
  final String promptSnapshot;
  final Object? expectedAnswer;
  final List<PracticeAnchor> anchors;
  final int createdAtMs;
}

class CreatePracticeItem {
  const CreatePracticeItem({
    this.sessionId,
    required this.kind,
    required this.target,
    required this.promptSnapshot,
    required this.expectedText,
    required this.anchors,
  });

  final String? sessionId;
  final String kind;
  final PracticeTarget target;
  final String promptSnapshot;
  final String expectedText;
  final List<PracticeAnchor> anchors;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'kind': kind,
    'target': target.toJson(),
    'prompt_snapshot': promptSnapshot,
    'expected_text': expectedText,
    'anchors': anchors.map((value) => value.toJson()).toList(growable: false),
  };
}

class SubmitPracticeAttempt {
  const SubmitPracticeAttempt({
    required this.itemId,
    required this.textAnswer,
    required this.createReviewItemOnFailure,
  });

  final String itemId;
  final String textAnswer;
  final bool createReviewItemOnFailure;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'text_answer': textAnswer,
    'create_review_item_on_failure': createReviewItemOnFailure,
  };
}

class PracticeTokenEvaluation {
  const PracticeTokenEvaluation({
    this.expected,
    this.actual,
    required this.result,
  });

  factory PracticeTokenEvaluation.fromJson(Map<String, dynamic> json) =>
      PracticeTokenEvaluation(
        expected: json['expected'] as String?,
        actual: json['actual'] as String?,
        result: json['result'] as String,
      );

  final String? expected;
  final String? actual;
  final String result;
}

class PracticeEvaluation {
  const PracticeEvaluation({
    required this.summary,
    required this.tokenResults,
    required this.extra,
  });

  factory PracticeEvaluation.fromJson(
    Map<String, dynamic> json,
  ) => PracticeEvaluation(
    summary: json['summary'] as String,
    tokenResults: ((json['token_results'] as List<dynamic>?) ?? const [])
        .map(
          (value) =>
              PracticeTokenEvaluation.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    extra: json['extra'],
  );

  final String summary;
  final List<PracticeTokenEvaluation> tokenResults;
  final Object? extra;
}

class PracticeAttempt {
  const PracticeAttempt({
    required this.id,
    required this.itemId,
    required this.submittedAtMs,
    required this.input,
    required this.result,
    this.score,
    required this.evaluation,
    required this.generatedObservationIds,
    required this.generatedReviewItemIds,
  });

  factory PracticeAttempt.fromJson(Map<String, dynamic> json) =>
      PracticeAttempt(
        id: json['id'] as String,
        itemId: json['item_id'] as String,
        submittedAtMs: json['submitted_at_ms'] as int,
        input: json['input'],
        result: json['result'] as String,
        score: (json['score'] as num?)?.toDouble(),
        evaluation: PracticeEvaluation.fromJson(
          json['evaluation'] as Map<String, dynamic>,
        ),
        generatedObservationIds:
            ((json['generated_observation_ids'] as List<dynamic>?) ?? const [])
                .cast<String>()
                .toList(growable: false),
        generatedReviewItemIds:
            ((json['generated_review_item_ids'] as List<dynamic>?) ?? const [])
                .cast<String>()
                .toList(growable: false),
      );

  final String id;
  final String itemId;
  final int submittedAtMs;
  final Object? input;
  final String result;
  final double? score;
  final PracticeEvaluation evaluation;
  final List<String> generatedObservationIds;
  final List<String> generatedReviewItemIds;

  PracticeAttempt copyWith({List<String>? generatedReviewItemIds}) =>
      PracticeAttempt(
        id: id,
        itemId: itemId,
        submittedAtMs: submittedAtMs,
        input: input,
        result: result,
        score: score,
        evaluation: evaluation,
        generatedObservationIds: generatedObservationIds,
        generatedReviewItemIds:
            generatedReviewItemIds ?? this.generatedReviewItemIds,
      );
}

class ReviewSource {
  const ReviewSource({
    required this.kind,
    this.id,
    this.practiceAttemptId,
    this.lexicalEntryId,
    this.mediaId,
    this.trackId,
  });

  factory ReviewSource.fromJson(Map<String, dynamic> json) => ReviewSource(
    kind: json['kind'] as String,
    id: json['id'] as String?,
    practiceAttemptId: json['practice_attempt_id'] as String?,
    lexicalEntryId: json['lexical_entry_id'] as String?,
    mediaId: json['media_id'] as String?,
    trackId: json['track_id'] as String?,
  );

  final String kind;
  final String? id;
  final String? practiceAttemptId;
  final String? lexicalEntryId;
  final String? mediaId;
  final String? trackId;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'practice_attempt_id': practiceAttemptId,
    'lexical_entry_id': lexicalEntryId,
    'media_id': mediaId,
    'track_id': trackId,
  };
}

class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.source,
    required this.anchors,
    required this.promptSnapshot,
    required this.status,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory ReviewItem.fromJson(Map<String, dynamic> json) => ReviewItem(
    id: json['id'] as String,
    source: ReviewSource.fromJson(json['source'] as Map<String, dynamic>),
    anchors: ((json['anchors'] as List<dynamic>?) ?? const [])
        .map((value) => PracticeAnchor.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    promptSnapshot: json['prompt_snapshot'] as String,
    status: json['status'] as String,
    createdAtMs: json['created_at_ms'] as int,
    updatedAtMs: json['updated_at_ms'] as int,
  );

  final String id;
  final ReviewSource source;
  final List<PracticeAnchor> anchors;
  final String promptSnapshot;
  final String status;
  final int createdAtMs;
  final int updatedAtMs;
}

class CreateReviewItem {
  const CreateReviewItem({
    required this.source,
    required this.anchors,
    required this.promptSnapshot,
  });

  final ReviewSource source;
  final List<PracticeAnchor> anchors;
  final String promptSnapshot;

  Map<String, dynamic> toJson() => {
    'source': source.toJson(),
    'anchors': anchors.map((value) => value.toJson()).toList(growable: false),
    'prompt_snapshot': promptSnapshot,
  };
}

class ReviewSchedule {
  const ReviewSchedule({
    required this.itemId,
    required this.algorithm,
    required this.dueAtMs,
    required this.lapseCount,
    this.stability,
    this.difficulty,
    this.intervalDays,
  });

  factory ReviewSchedule.fromJson(Map<String, dynamic> json) => ReviewSchedule(
    itemId: json['item_id'] as String,
    algorithm: json['algorithm'] as String,
    dueAtMs: json['due_at_ms'] as int,
    stability: (json['stability'] as num?)?.toDouble(),
    difficulty: (json['difficulty'] as num?)?.toDouble(),
    intervalDays: (json['interval_days'] as num?)?.toDouble(),
    lapseCount: json['lapse_count'] as int,
  );

  final String itemId;
  final String algorithm;
  final int dueAtMs;
  final double? stability;
  final double? difficulty;
  final double? intervalDays;
  final int lapseCount;
}

class ReviewAttempt {
  const ReviewAttempt({
    required this.id,
    required this.itemId,
    required this.reviewedAtMs,
    required this.rating,
    this.practiceAttemptId,
    this.nextDueAtMs,
  });

  factory ReviewAttempt.fromJson(Map<String, dynamic> json) => ReviewAttempt(
    id: json['id'] as String,
    itemId: json['item_id'] as String,
    reviewedAtMs: json['reviewed_at_ms'] as int,
    rating: json['rating'] as String,
    practiceAttemptId: json['practice_attempt_id'] as String?,
    nextDueAtMs: json['next_due_at_ms'] as int?,
  );

  final String id;
  final String itemId;
  final int reviewedAtMs;
  final String rating;
  final String? practiceAttemptId;
  final int? nextDueAtMs;
}

class ReviewCard {
  const ReviewCard({
    required this.kind,
    required this.answer,
    this.cue,
    this.target,
  });

  factory ReviewCard.fromJson(Map<String, dynamic> json) => ReviewCard(
    kind: json['kind'] as String,
    cue: json['cue'] as String?,
    answer: json['answer'] as String,
    target: json['target'] as String?,
  );

  final String kind;
  final String? cue;
  final String answer;
  final String? target;
}

class ReviewQueueEntry {
  const ReviewQueueEntry({
    required this.item,
    required this.schedule,
    required this.card,
  });

  factory ReviewQueueEntry.fromJson(Map<String, dynamic> json) =>
      ReviewQueueEntry(
        item: ReviewItem.fromJson(json['item'] as Map<String, dynamic>),
        schedule: ReviewSchedule.fromJson(
          json['schedule'] as Map<String, dynamic>,
        ),
        card: ReviewCard.fromJson(json['card'] as Map<String, dynamic>),
      );

  final ReviewItem item;
  final ReviewSchedule schedule;
  final ReviewCard card;

  int? get playbackStartMs => item.anchors
      .map((value) => value.startMs)
      .whereType<int>()
      .fold<int?>(
        null,
        (value, next) => value == null || next < value ? next : value,
      );

  int? get playbackEndMs => item.anchors
      .map((value) => value.endMs)
      .whereType<int>()
      .fold<int?>(
        null,
        (value, next) => value == null || next > value ? next : value,
      );
}

class ReviewSubmission {
  const ReviewSubmission({
    required this.attempt,
    required this.schedule,
    required this.generatedObservationIds,
    required this.huntingCandidateIds,
  });

  factory ReviewSubmission.fromJson(
    Map<String, dynamic> json,
  ) => ReviewSubmission(
    attempt: ReviewAttempt.fromJson(json['attempt'] as Map<String, dynamic>),
    schedule: ReviewSchedule.fromJson(json['schedule'] as Map<String, dynamic>),
    generatedObservationIds:
        ((json['generated_observation_ids'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
    huntingCandidateIds:
        ((json['hunting_candidate_ids'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
  );

  final ReviewAttempt attempt;
  final ReviewSchedule schedule;
  final List<String> generatedObservationIds;
  final List<String> huntingCandidateIds;
}

class DiagnosisHintEvidence {
  const DiagnosisHintEvidence({required this.kind, required this.reasons});

  factory DiagnosisHintEvidence.fromJson(Map<String, dynamic> json) =>
      DiagnosisHintEvidence(
        kind: json['kind'] as String,
        reasons: ((json['reasons'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
      );

  final String kind;
  final List<String> reasons;

  Map<String, dynamic> toJson() => {'kind': kind, 'reasons': reasons};
}

class RecordStuckPointInput {
  const RecordStuckPointInput({
    required this.sessionId,
    required this.target,
    required this.anchors,
    this.label,
    this.diagnosisHints = const [],
  });

  final String sessionId;
  final PracticeTarget target;
  final List<PracticeAnchor> anchors;
  final String? label;
  final List<DiagnosisHintEvidence> diagnosisHints;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'target': target.toJson(),
    'anchors': anchors.map((value) => value.toJson()).toList(growable: false),
    'label': label,
    'diagnosis_hints': diagnosisHints
        .map((value) => value.toJson())
        .toList(growable: false),
  };
}

class RecordDiagnosisViewInput {
  const RecordDiagnosisViewInput({
    required this.sessionId,
    required this.target,
    required this.anchors,
    this.label,
    this.diagnosisHints = const [],
  });

  final String sessionId;
  final PracticeTarget target;
  final List<PracticeAnchor> anchors;
  final String? label;
  final List<DiagnosisHintEvidence> diagnosisHints;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'target': target.toJson(),
    'anchors': anchors.map((value) => value.toJson()).toList(growable: false),
    'label': label,
    'diagnosis_hints': diagnosisHints
        .map((value) => value.toJson())
        .toList(growable: false),
  };
}

class CloseStuckPointInput {
  const CloseStuckPointInput({
    required this.sessionId,
    required this.targetKey,
    this.reason,
  });

  final String sessionId;
  final String targetKey;
  final String? reason;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'target_key': targetKey,
    'reason': reason,
  };
}

class CompletePracticeSessionInput {
  const CompletePracticeSessionInput({
    this.markFamiliar = true,
    this.comprehensionReport,
  });

  final bool markFamiliar;
  final String? comprehensionReport;

  Map<String, dynamic> toJson() => {
    'mark_familiar': markFamiliar,
    'comprehension_report': comprehensionReport,
  };
}

class StuckPointSummary {
  const StuckPointSummary({
    required this.targetKey,
    required this.status,
    this.target,
    required this.anchors,
    this.label,
    this.markedAtMs,
    required this.updatedAtMs,
    this.playbackStartMs,
    this.playbackEndMs,
    required this.practiceAttemptIds,
    required this.reviewItemIds,
    required this.diagnosisHints,
  });

  factory StuckPointSummary.fromJson(
    Map<String, dynamic> json,
  ) => StuckPointSummary(
    targetKey: json['target_key'] as String,
    status: json['status'] as String,
    target: json['target'] == null
        ? null
        : PracticeTarget.fromJson(json['target'] as Map<String, dynamic>),
    anchors: ((json['anchors'] as List<dynamic>?) ?? const [])
        .map((value) => PracticeAnchor.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    label: json['label'] as String?,
    markedAtMs: json['marked_at_ms'] as int?,
    updatedAtMs: json['updated_at_ms'] as int,
    playbackStartMs: json['playback_start_ms'] as int?,
    playbackEndMs: json['playback_end_ms'] as int?,
    practiceAttemptIds:
        ((json['practice_attempt_ids'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
    reviewItemIds: ((json['review_item_ids'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
    diagnosisHints: ((json['diagnosis_hints'] as List<dynamic>?) ?? const [])
        .map(
          (value) =>
              DiagnosisHintEvidence.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
  );

  final String targetKey;
  final String status;
  final PracticeTarget? target;
  final List<PracticeAnchor> anchors;
  final String? label;
  final int? markedAtMs;
  final int updatedAtMs;
  final int? playbackStartMs;
  final int? playbackEndMs;
  final List<String> practiceAttemptIds;
  final List<String> reviewItemIds;
  final List<DiagnosisHintEvidence> diagnosisHints;
}

class StuckPointAttribution {
  const StuckPointAttribution({
    required this.kind,
    this.reason,
    required this.count,
  });

  factory StuckPointAttribution.fromJson(Map<String, dynamic> json) =>
      StuckPointAttribution(
        kind: json['kind'] as String,
        reason: json['reason'] as String?,
        count: json['count'] as int,
      );

  final String kind;
  final String? reason;
  final int count;
}

class PracticeSessionSummary {
  const PracticeSessionSummary({
    required this.session,
    required this.stuckPoints,
    required this.stuckCount,
    required this.resolvedCount,
    required this.activeVerifiedCount,
    required this.reviewCount,
    required this.unexplainedCount,
    required this.skippedCount,
    required this.closedCount,
    required this.openCount,
    required this.attributionCounts,
    required this.familiarMaterialMarked,
  });

  factory PracticeSessionSummary.fromJson(
    Map<String, dynamic> json,
  ) => PracticeSessionSummary(
    session: PracticeSession.fromJson(json['session'] as Map<String, dynamic>),
    stuckPoints: ((json['stuck_points'] as List<dynamic>?) ?? const [])
        .map(
          (value) => StuckPointSummary.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    stuckCount: json['stuck_count'] as int,
    resolvedCount: json['resolved_count'] as int,
    activeVerifiedCount: json['active_verified_count'] as int,
    reviewCount: json['review_count'] as int,
    unexplainedCount: json['unexplained_count'] as int,
    skippedCount: json['skipped_count'] as int,
    closedCount: json['closed_count'] as int,
    openCount: json['open_count'] as int,
    attributionCounts:
        ((json['attribution_counts'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  StuckPointAttribution.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
    familiarMaterialMarked: json['familiar_material_marked'] as bool,
  );

  final PracticeSession session;
  final List<StuckPointSummary> stuckPoints;
  final int stuckCount;
  final int resolvedCount;
  final int activeVerifiedCount;
  final int reviewCount;
  final int unexplainedCount;
  final int skippedCount;
  final int closedCount;
  final int openCount;
  final List<StuckPointAttribution> attributionCounts;
  final bool familiarMaterialMarked;
}
