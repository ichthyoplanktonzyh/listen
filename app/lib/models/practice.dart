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
  });

  factory ReviewSource.fromJson(Map<String, dynamic> json) => ReviewSource(
    kind: json['kind'] as String,
    id: json['id'] as String?,
    practiceAttemptId: json['practice_attempt_id'] as String?,
    lexicalEntryId: json['lexical_entry_id'] as String?,
  );

  final String kind;
  final String? id;
  final String? practiceAttemptId;
  final String? lexicalEntryId;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': id,
    'practice_attempt_id': practiceAttemptId,
    'lexical_entry_id': lexicalEntryId,
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
