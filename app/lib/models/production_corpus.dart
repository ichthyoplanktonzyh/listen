/// One written or spoken response derived from a completed semantic task.
/// The projection is rebuildable from the authoritative attempt.
class ProductionCorpusDocumentView {
  const ProductionCorpusDocumentView({
    required this.id,
    required this.language,
    required this.channel,
    required this.assistance,
    required this.attemptId,
    required this.rubricId,
    required this.responseRevision,
    required this.activityKind,
    this.mediaId,
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
        responseRevision: (json['response_revision'] as num).toInt(),
        activityKind: json['activity_kind'] as String,
        mediaId: json['media_id'] as String?,
        startMs: (json['start_ms'] as num).toInt(),
        endMs: (json['end_ms'] as num).toInt(),
        responseText: json['response_text'] as String,
        producedAtMs: (json['produced_at_ms'] as num).toInt(),
      );

  final String id;
  final String language;
  final String channel;
  final String assistance;
  final String attemptId;
  final String rubricId;
  final int responseRevision;
  final String activityKind;
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
        startChar: (json['start_char'] as num).toInt(),
        endChar: (json['end_char'] as num).toInt(),
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
