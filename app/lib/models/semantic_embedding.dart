class SemanticEmbeddingDescriptorView {
  const SemanticEmbeddingDescriptorView({
    required this.modelId,
    required this.modelVersion,
    required this.dimension,
    required this.modelFingerprint,
    required this.local,
  });

  factory SemanticEmbeddingDescriptorView.fromJson(Map<String, dynamic> json) =>
      SemanticEmbeddingDescriptorView(
        modelId: json['model_id'] as String,
        modelVersion: json['model_version'] as String,
        dimension: json['dimension'] as int,
        modelFingerprint: json['model_fingerprint'] as String,
        local: json['local'] as bool,
      );

  final String modelId;
  final String modelVersion;
  final int dimension;
  final String modelFingerprint;
  final bool local;
}

class SemanticEmbeddingCapabilityView {
  const SemanticEmbeddingCapabilityView({
    required this.status,
    required this.indexedSourceCount,
    this.descriptor,
    this.reason,
  });

  factory SemanticEmbeddingCapabilityView.fromJson(Map<String, dynamic> json) =>
      SemanticEmbeddingCapabilityView(
        status: json['status'] as String,
        indexedSourceCount: json['indexed_source_count'] as int,
        descriptor: json['descriptor'] == null
            ? null
            : SemanticEmbeddingDescriptorView.fromJson(
                json['descriptor'] as Map<String, dynamic>,
              ),
        reason: json['reason'] as String?,
      );

  final String status;
  final int indexedSourceCount;
  final SemanticEmbeddingDescriptorView? descriptor;
  final String? reason;
  bool get canSearch => status == 'ready' && indexedSourceCount > 0;
}

class SemanticSearchSourceView {
  const SemanticSearchSourceView({
    required this.kind,
    required this.sourceId,
    required this.language,
    required this.text,
    this.channel,
    this.mediaId,
    required this.startMs,
    required this.endMs,
  });

  factory SemanticSearchSourceView.fromJson(Map<String, dynamic> json) =>
      SemanticSearchSourceView(
        kind: json['kind'] as String,
        sourceId: json['source_id'] as String,
        language: json['language'] as String,
        text: json['text'] as String,
        channel: json['channel'] as String?,
        mediaId: json['media_id'] as String?,
        startMs: json['start_ms'] as int? ?? 0,
        endMs: json['end_ms'] as int? ?? 0,
      );

  final String kind;
  final String sourceId;
  final String language;
  final String text;
  final String? channel;
  final String? mediaId;
  final int startMs;
  final int endMs;
}

class SemanticSearchHitView {
  const SemanticSearchHitView({
    required this.source,
    required this.similarity,
    required this.modelFingerprint,
  });

  factory SemanticSearchHitView.fromJson(Map<String, dynamic> json) =>
      SemanticSearchHitView(
        source: SemanticSearchSourceView.fromJson(
          json['source'] as Map<String, dynamic>,
        ),
        similarity: (json['similarity'] as num).toDouble(),
        modelFingerprint: json['model_fingerprint'] as String,
      );

  final SemanticSearchSourceView source;
  final double similarity;
  final String modelFingerprint;
}

class SemanticSearchResultView {
  const SemanticSearchResultView({
    required this.capability,
    required this.query,
    required this.hits,
  });

  factory SemanticSearchResultView.fromJson(Map<String, dynamic> json) =>
      SemanticSearchResultView(
        capability: SemanticEmbeddingCapabilityView.fromJson(
          json['capability'] as Map<String, dynamic>,
        ),
        query: json['query'] as String,
        hits: (json['hits'] as List<dynamic>)
            .map(
              (value) =>
                  SemanticSearchHitView.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final SemanticEmbeddingCapabilityView capability;
  final String query;
  final List<SemanticSearchHitView> hits;
}
