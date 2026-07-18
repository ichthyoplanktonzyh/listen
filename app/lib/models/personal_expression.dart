class PersonalExpressionSourceView {
  const PersonalExpressionSourceView({
    required this.kind,
    required this.text,
    this.title,
    this.mediaId,
    this.mediaFingerprint,
    this.trackId,
    this.sentenceId,
    this.semanticAttemptId,
    this.startMs,
    this.endMs,
    this.candidateRef,
  });

  factory PersonalExpressionSourceView.fromJson(Map<String, dynamic> json) =>
      PersonalExpressionSourceView(
        kind: json['kind'] as String,
        text: json['text'] as String,
        title: json['title'] as String?,
        mediaId: json['media_id'] as String?,
        mediaFingerprint: json['media_fingerprint'] as String?,
        trackId: json['track_id'] as String?,
        sentenceId: json['sentence_id'] as String?,
        semanticAttemptId: json['semantic_attempt_id'] as String?,
        startMs: json['start_ms'] as int?,
        endMs: json['end_ms'] as int?,
        candidateRef: json['candidate_ref'] as String?,
      );

  final String kind;
  final String text;
  final String? title,
      mediaId,
      mediaFingerprint,
      trackId,
      sentenceId,
      semanticAttemptId;
  final int? startMs, endMs;
  final String? candidateRef;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'text': text,
    'title': title,
    'media_id': mediaId,
    'media_fingerprint': mediaFingerprint,
    'track_id': trackId,
    'sentence_id': sentenceId,
    'semantic_attempt_id': semanticAttemptId,
    'start_ms': startMs,
    'end_ms': endMs,
    'candidate_ref': candidateRef,
  };
}

class SentencePatternSlotView {
  const SentencePatternSlotView({
    required this.name,
    this.prompt,
    this.exampleValue,
    this.required = true,
  });

  factory SentencePatternSlotView.fromJson(Map<String, dynamic> json) =>
      SentencePatternSlotView(
        name: json['name'] as String,
        prompt: json['prompt'] as String?,
        exampleValue: json['example_value'] as String?,
        required: json['required'] as bool? ?? true,
      );

  final String name;
  final String? prompt, exampleValue;
  final bool required;

  Map<String, dynamic> toJson() => {
    'name': name,
    'prompt': prompt,
    'example_value': exampleValue,
    'required': required,
  };
}

class SentencePatternVersionView {
  const SentencePatternVersionView({
    required this.id,
    required this.patternId,
    required this.version,
    required this.name,
    required this.patternText,
    required this.slots,
    this.note,
    this.systemConstructionId,
    required this.createdAtMs,
  });

  factory SentencePatternVersionView.fromJson(
    Map<String, dynamic> json,
  ) => SentencePatternVersionView(
    id: json['id'] as String,
    patternId: json['pattern_id'] as String,
    version: json['version'] as int,
    name: json['name'] as String,
    patternText: json['pattern_text'] as String,
    slots: (json['slots'] as List<dynamic>)
        .map(
          (value) =>
              SentencePatternSlotView.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    note: json['note'] as String?,
    systemConstructionId: json['system_construction_id'] as String?,
    createdAtMs: json['created_at_ms'] as int,
  );

  final String id, patternId, name, patternText;
  final int version, createdAtMs;
  final List<SentencePatternSlotView> slots;
  final String? note, systemConstructionId;
}

class SentencePatternAssetView {
  const SentencePatternAssetView({
    required this.id,
    required this.language,
    required this.source,
    required this.currentVersion,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory SentencePatternAssetView.fromJson(Map<String, dynamic> json) =>
      SentencePatternAssetView(
        id: json['id'] as String,
        language: json['language'] as String,
        source: PersonalExpressionSourceView.fromJson(
          json['source'] as Map<String, dynamic>,
        ),
        currentVersion: SentencePatternVersionView.fromJson(
          json['current_version'] as Map<String, dynamic>,
        ),
        createdAtMs: json['created_at_ms'] as int,
        updatedAtMs: json['updated_at_ms'] as int,
      );

  final String id, language;
  final PersonalExpressionSourceView source;
  final SentencePatternVersionView currentVersion;
  final int createdAtMs, updatedAtMs;
}

class PersonalExpressionAttemptView {
  const PersonalExpressionAttemptView({
    required this.id,
    required this.patternId,
    required this.patternVersionId,
    required this.channel,
    required this.assistance,
    required this.responseText,
    this.rawTranscript,
    this.recordingAssetId,
    required this.selfAssessment,
    this.contextNote,
    required this.completedAtMs,
  });

  factory PersonalExpressionAttemptView.fromJson(Map<String, dynamic> json) =>
      PersonalExpressionAttemptView(
        id: json['id'] as String,
        patternId: json['pattern_id'] as String,
        patternVersionId: json['pattern_version_id'] as String,
        channel: json['channel'] as String,
        assistance: json['assistance'] as String,
        responseText: json['response_text'] as String,
        rawTranscript: json['raw_transcript'] as String?,
        recordingAssetId: json['recording_asset_id'] as String?,
        selfAssessment: json['self_assessment'] as String,
        contextNote: json['context_note'] as String?,
        completedAtMs: json['completed_at_ms'] as int,
      );

  final String id,
      patternId,
      patternVersionId,
      channel,
      assistance,
      responseText,
      selfAssessment;
  final String? rawTranscript, recordingAssetId, contextNote;
  final int completedAtMs;
}

/// Typed portable transfer document. Nested DTOs are decoded before the
/// original JSON is retained for file export, so callers never parse HTTP.
class PersonalExpressionExportBundleView {
  const PersonalExpressionExportBundleView({
    required this.schema,
    required this.exportedAtMs,
    required this.patternCount,
    required this.json,
  });

  factory PersonalExpressionExportBundleView.fromJson(
    Map<String, dynamic> json,
  ) {
    final patterns = json['patterns'] as List<dynamic>;
    for (final pattern in patterns) {
      final value = pattern as Map<String, dynamic>;
      SentencePatternAssetView.fromJson(value['asset'] as Map<String, dynamic>);
      for (final version in value['versions'] as List<dynamic>) {
        SentencePatternVersionView.fromJson(version as Map<String, dynamic>);
      }
      for (final attempt in value['attempts'] as List<dynamic>) {
        PersonalExpressionAttemptView.fromJson(attempt as Map<String, dynamic>);
      }
    }
    return PersonalExpressionExportBundleView(
      schema: json['schema'] as String,
      exportedAtMs: json['exported_at_ms'] as int,
      patternCount: patterns.length,
      json: Map<String, dynamic>.unmodifiable(json),
    );
  }

  final String schema;
  final int exportedAtMs, patternCount;
  final Map<String, dynamic> json;
  Map<String, dynamic> toJson() => json;
}
