class ProductionCorpusDocumentView {
  const ProductionCorpusDocumentView({
    required this.id,
    required this.language,
    required this.channel,
    required this.assistance,
    required this.attemptId,
    required this.rubricId,
    required this.responseRevision,
    required this.taskKind,
    required this.mediaId,
    required this.startMs,
    required this.endMs,
    required this.responseText,
    required this.producedAtMs,
  });

  factory ProductionCorpusDocumentView.fromJson(Map<String, dynamic> json) =>
      ProductionCorpusDocumentView(
        id: json['id'] as String,
        language: json['language'] as String,
        channel: json['channel'] as String,
        assistance: json['assistance'] as String,
        attemptId: json['attempt_id'] as String,
        rubricId: json['rubric_id'] as String,
        responseRevision: json['response_revision'] as int,
        taskKind: json['task_kind'] as String,
        mediaId: json['media_id'] as String?,
        startMs: json['start_ms'] as int,
        endMs: json['end_ms'] as int,
        responseText: json['response_text'] as String,
        producedAtMs: json['produced_at_ms'] as int,
      );

  final String id;
  final String language;
  final String channel;
  final String assistance;
  final String attemptId;
  final String rubricId;
  final int responseRevision;
  final String taskKind;
  final String? mediaId;
  final int startMs;
  final int endMs;
  final String responseText;
  final int producedAtMs;
}

class ProductionCorpusEntryView {
  const ProductionCorpusEntryView({
    required this.id,
    required this.documentId,
    required this.normalizedKey,
    required this.displayText,
    required this.startChar,
    required this.endChar,
  });

  factory ProductionCorpusEntryView.fromJson(Map<String, dynamic> json) =>
      ProductionCorpusEntryView(
        id: json['id'] as String,
        documentId: json['document_id'] as String,
        normalizedKey: json['normalized_key'] as String,
        displayText: json['display_text'] as String,
        startChar: json['start_char'] as int,
        endChar: json['end_char'] as int,
      );

  final String id;
  final String documentId;
  final String normalizedKey;
  final String displayText;
  final int startChar;
  final int endChar;
}

class ProductionCorpusHitView {
  const ProductionCorpusHitView({required this.document, this.entry});

  factory ProductionCorpusHitView.fromJson(Map<String, dynamic> json) =>
      ProductionCorpusHitView(
        document: ProductionCorpusDocumentView.fromJson(
          json['document'] as Map<String, dynamic>,
        ),
        entry: json['entry'] == null
            ? null
            : ProductionCorpusEntryView.fromJson(
                json['entry'] as Map<String, dynamic>,
              ),
      );

  final ProductionCorpusDocumentView document;
  final ProductionCorpusEntryView? entry;
}

class ProductionGapTargetView {
  const ProductionGapTargetView({
    required this.lexicalEntryId,
    required this.normalizedKey,
    required this.displayForm,
    required this.frequencyRank,
    required this.frequencyBand,
    required this.evidenceStrength,
    required this.recencyBand,
    required this.explanation,
  });
  factory ProductionGapTargetView.fromJson(Map<String, dynamic> json) =>
      ProductionGapTargetView(
        lexicalEntryId: json['lexical_entry_id'] as String,
        normalizedKey: json['normalized_key'] as String,
        displayForm: json['display_form'] as String,
        frequencyRank: json['frequency_rank'] as int?,
        frequencyBand: json['frequency_band'] as int?,
        evidenceStrength: json['evidence_strength'] as int,
        recencyBand: json['recency_band'] as int,
        explanation: (json['explanation'] as List<dynamic>).cast<String>(),
      );
  final String lexicalEntryId;
  final String normalizedKey;
  final String displayForm;
  final int? frequencyRank;
  final int? frequencyBand;
  final int evidenceStrength;
  final int recencyBand;
  final List<String> explanation;
}

class ProductionGapReviewView {
  const ProductionGapReviewView({
    required this.readiness,
    required this.documentCount,
    required this.tokenCount,
    required this.lemmaCount,
    required this.candidateCount,
    required this.targets,
  });
  factory ProductionGapReviewView.fromJson(
    Map<String, dynamic> json,
  ) => ProductionGapReviewView(
    readiness: json['readiness'] as String,
    documentCount: json['document_count'] as int,
    tokenCount: json['token_count'] as int,
    lemmaCount: json['lemma_count'] as int,
    candidateCount: json['candidate_count'] as int,
    targets: (json['targets'] as List<dynamic>)
        .map(
          (value) =>
              ProductionGapTargetView.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
  );
  final String readiness;
  final int documentCount;
  final int tokenCount;
  final int lemmaCount;
  final int candidateCount;
  final List<ProductionGapTargetView> targets;
}
