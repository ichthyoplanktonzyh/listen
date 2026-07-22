part of '../timeline.dart';

// Word/Chunk timelines, evidence, sense groups
// Split out of timeline.dart (mechanical decomposition).

class WordTiming {
  const WordTiming({
    required this.sentenceId,
    required this.tokenIndex,
    required this.start,
    required this.end,
    required this.source,
    required this.provider,
    this.text = '',
    this.confidence,
    this.providerVersion = '',
  });

  factory WordTiming.fromJson(Map<String, dynamic> json) => WordTiming(
    sentenceId: json['sentence_id'] as String,
    tokenIndex: json['token_index'] as int,
    text: json['text'] as String? ?? '',
    start: Duration(milliseconds: json['start_ms'] as int),
    end: Duration(milliseconds: json['end_ms'] as int),
    confidence: (json['confidence'] as num?)?.toDouble(),
    source: json['timing_source'] as String,
    provider: json['provider_id'] as String,
    providerVersion: json['provider_version'] as String? ?? '',
  );

  final String sentenceId;
  final int tokenIndex;
  final String text;
  final Duration start;
  final Duration end;
  final double? confidence;
  final String source;
  final String provider;
  final String providerVersion;

  WordTiming copyWith({
    Duration? start,
    Duration? end,
    String? source,
    String? provider,
    String? providerVersion,
    double? confidence,
  }) => WordTiming(
    sentenceId: sentenceId,
    tokenIndex: tokenIndex,
    text: text,
    start: start ?? this.start,
    end: end ?? this.end,
    confidence: confidence ?? this.confidence,
    source: source ?? this.source,
    provider: provider ?? this.provider,
    providerVersion: providerVersion ?? this.providerVersion,
  );

  Map<String, dynamic> toJson() => {
    'sentence_id': sentenceId,
    'token_index': tokenIndex,
    'text': text,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'confidence': confidence,
    'timing_source': source,
    'provider_id': provider,
    'provider_version': providerVersion,
  };
}

class TimelineMetrics {
  const TimelineMetrics(this.fields);
  const TimelineMetrics.empty() : fields = const {};

  factory TimelineMetrics.fromJson(Object? json) => json is Map
      ? TimelineMetrics(Map<String, dynamic>.from(json))
      : const TimelineMetrics.empty();

  final Map<String, dynamic> fields;

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(fields);
}

class ChunkEvidence {
  const ChunkEvidence(this.fields);
  const ChunkEvidence.empty() : fields = const {};

  factory ChunkEvidence.fromJson(Object? json) => json is Map
      ? ChunkEvidence(Map<String, dynamic>.from(json))
      : const ChunkEvidence.empty();

  final Map<String, dynamic> fields;

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(fields);
}

class WordTimeline {
  const WordTimeline({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.algorithmId,
    required this.algorithmVersion,
    required this.configHash,
    required this.createdBy,
    required this.status,
    required this.metricsJson,
    required this.words,
    required this.createdAt,
    required this.updatedAt,
    this.parentTimelineId,
  });

  factory WordTimeline.fromJson(Map<String, dynamic> json) => WordTimeline(
    id: json['id'] as String,
    trackId: json['track_id'] as String,
    mediaId: json['media_id'] as String,
    algorithmId: json['algorithm_id'] as String,
    algorithmVersion: json['algorithm_version'] as String,
    configHash: json['config_hash'] as String,
    parentTimelineId: json['parent_timeline_id'] as String?,
    createdBy: json['created_by'] as String,
    status: json['status'] as String,
    metricsJson: TimelineMetrics.fromJson(json['metrics_json']),
    words: (json['words'] as List<dynamic>)
        .map((value) => WordTiming.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    createdAt: Duration(milliseconds: json['created_at_ms'] as int),
    updatedAt: Duration(milliseconds: json['updated_at_ms'] as int),
  );

  final String id;
  final String trackId;
  final String mediaId;
  final String algorithmId;
  final String algorithmVersion;
  final String configHash;
  final String? parentTimelineId;
  final String createdBy;
  final String status;
  final TimelineMetrics metricsJson;
  final List<WordTiming> words;
  final Duration createdAt;
  final Duration updatedAt;
}

class WordTimelineSummary {
  const WordTimelineSummary({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.algorithmId,
    required this.algorithmVersion,
    required this.createdBy,
    required this.status,
    required this.lifecycleStage,
    required this.wordCount,
    required this.providerIds,
    required this.timingSources,
    required this.canActivate,
    required this.canArchive,
    required this.canDelete,
    this.parentTimelineId,
    this.start,
    this.end,
    this.averageConfidence,
  });

  factory WordTimelineSummary.fromJson(Map<String, dynamic> json) =>
      WordTimelineSummary(
        id: json['id'] as String,
        trackId: json['track_id'] as String,
        mediaId: json['media_id'] as String,
        algorithmId: json['algorithm_id'] as String,
        algorithmVersion: json['algorithm_version'] as String,
        parentTimelineId: json['parent_timeline_id'] as String?,
        createdBy: json['created_by'] as String,
        status: json['status'] as String,
        lifecycleStage: json['lifecycle_stage'] as String,
        wordCount: json['word_count'] as int,
        start: _durationFromNullableMs(json['start_ms'] as int?),
        end: _durationFromNullableMs(json['end_ms'] as int?),
        providerIds: (json['provider_ids'] as List<dynamic>)
            .cast<String>()
            .toList(growable: false),
        timingSources: (json['timing_sources'] as List<dynamic>)
            .cast<String>()
            .toList(growable: false),
        averageConfidence: (json['average_confidence'] as num?)?.toDouble(),
        canActivate: json['can_activate'] as bool,
        canArchive: json['can_archive'] as bool,
        canDelete: json['can_delete'] as bool,
      );

  final String id;
  final String trackId;
  final String mediaId;
  final String algorithmId;
  final String algorithmVersion;
  final String? parentTimelineId;
  final String createdBy;
  final String status;
  final String lifecycleStage;
  final int wordCount;
  final Duration? start;
  final Duration? end;
  final List<String> providerIds;
  final List<String> timingSources;
  final double? averageConfidence;
  final bool canActivate;
  final bool canArchive;
  final bool canDelete;

  bool get isActive => status == 'active';
  bool get humanReviewed =>
      createdBy == 'user' || lifecycleStage == 'user_adjusted';
}

class ChunkTimelineChunk {
  const ChunkTimelineChunk({
    required this.id,
    required this.sentenceId,
    required this.chunkIndex,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.start,
    required this.end,
    required this.text,
    required this.boundarySources,
    required this.confidence,
    required this.warnings,
    required this.evidenceJson,
  });

  factory ChunkTimelineChunk.fromJson(Map<String, dynamic> json) =>
      ChunkTimelineChunk(
        id: json['id'] as String,
        sentenceId: json['sentence_id'] as String,
        chunkIndex: json['chunk_index'] as int,
        startWordIndex: json['start_word_index'] as int,
        endWordIndex: json['end_word_index'] as int,
        start: Duration(milliseconds: json['start_ms'] as int),
        end: Duration(milliseconds: json['end_ms'] as int),
        text: json['text'] as String,
        boundarySources:
            ((json['boundary_sources'] as List<dynamic>?) ?? const [])
                .cast<String>()
                .toList(growable: false),
        confidence: (json['confidence'] as num).toDouble(),
        warnings: ((json['warnings'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
        evidenceJson: ChunkEvidence.fromJson(json['evidence_json']),
      );

  final String id;
  final String sentenceId;
  final int chunkIndex;
  final int startWordIndex;
  final int endWordIndex;
  final Duration start;
  final Duration end;
  final String text;
  final List<String> boundarySources;
  final double confidence;
  final List<String> warnings;
  final ChunkEvidence evidenceJson;

  DisplayChunk toDisplayChunk({required int sentenceLocalIndex}) =>
      DisplayChunk(
        index: sentenceLocalIndex,
        tokenStart: startWordIndex,
        tokenEnd: endWordIndex,
        text: text,
        start: start,
        end: end,
      );
}

class ChunkTimeline {
  const ChunkTimeline({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.providerId,
    required this.providerVersion,
    required this.algorithm,
    required this.precision,
    required this.createdBy,
    required this.status,
    required this.metricsJson,
    required this.chunks,
    required this.createdAt,
    required this.updatedAt,
    this.parentWordTimelineId,
  });

  factory ChunkTimeline.fromJson(Map<String, dynamic> json) => ChunkTimeline(
    id: json['id'] as String,
    trackId: json['track_id'] as String,
    mediaId: json['media_id'] as String,
    parentWordTimelineId: json['parent_word_timeline_id'] as String?,
    providerId: json['provider_id'] as String,
    providerVersion: json['provider_version'] as String,
    algorithm: json['algorithm'] as String,
    precision: json['precision'] as String,
    createdBy: json['created_by'] as String,
    status: json['status'] as String,
    metricsJson: TimelineMetrics.fromJson(json['metrics_json']),
    chunks: (json['chunks'] as List<dynamic>)
        .map(
          (value) => ChunkTimelineChunk.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    createdAt: Duration(milliseconds: json['created_at_ms'] as int),
    updatedAt: Duration(milliseconds: json['updated_at_ms'] as int),
  );

  final String id;
  final String trackId;
  final String mediaId;
  final String? parentWordTimelineId;
  final String providerId;
  final String providerVersion;
  final String algorithm;
  final String precision;
  final String createdBy;
  final String status;
  final TimelineMetrics metricsJson;
  final List<ChunkTimelineChunk> chunks;
  final Duration createdAt;
  final Duration updatedAt;

  bool get isActive => status == 'active';
}

class ChunkTimelineSummary {
  const ChunkTimelineSummary({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.providerId,
    required this.providerVersion,
    required this.algorithm,
    required this.precision,
    required this.createdBy,
    required this.status,
    required this.chunkCount,
    required this.canActivate,
    required this.canArchive,
    required this.canDelete,
    this.parentWordTimelineId,
    this.start,
    this.end,
    this.averageConfidence,
  });

  factory ChunkTimelineSummary.fromJson(Map<String, dynamic> json) =>
      ChunkTimelineSummary(
        id: json['id'] as String,
        trackId: json['track_id'] as String,
        mediaId: json['media_id'] as String,
        parentWordTimelineId: json['parent_word_timeline_id'] as String?,
        providerId: json['provider_id'] as String,
        providerVersion: json['provider_version'] as String,
        algorithm: json['algorithm'] as String,
        precision: json['precision'] as String,
        createdBy: json['created_by'] as String,
        status: json['status'] as String,
        chunkCount: json['chunk_count'] as int,
        start: _durationFromNullableMs(json['start_ms'] as int?),
        end: _durationFromNullableMs(json['end_ms'] as int?),
        averageConfidence: (json['average_confidence'] as num?)?.toDouble(),
        canActivate: json['can_activate'] as bool,
        canArchive: json['can_archive'] as bool,
        canDelete: json['can_delete'] as bool,
      );

  final String id;
  final String trackId;
  final String mediaId;
  final String? parentWordTimelineId;
  final String providerId;
  final String providerVersion;
  final String algorithm;
  final String precision;
  final String createdBy;
  final String status;
  final int chunkCount;
  final Duration? start;
  final Duration? end;
  final double? averageConfidence;
  final bool canActivate;
  final bool canArchive;
  final bool canDelete;

  bool get isActive => status == 'active';
}

class SenseGroup {
  const SenseGroup({
    required this.id,
    required this.sentenceId,
    required this.groupIndex,
    required this.startTokenIndex,
    required this.endTokenIndex,
    required this.text,
    required this.confidence,
    required this.sources,
    this.label,
    this.headTokenIndex,
  });

  factory SenseGroup.fromJson(Map<String, dynamic> json) => SenseGroup(
    id: json['id'] as String,
    sentenceId: json['sentence_id'] as String,
    groupIndex: json['group_index'] as int,
    startTokenIndex: json['start_token_index'] as int,
    endTokenIndex: json['end_token_index'] as int,
    text: json['text'] as String,
    label: json['label'] as String?,
    headTokenIndex: json['head_token_index'] as int?,
    confidence: (json['confidence'] as num).toDouble(),
    sources: ((json['sources'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
  );

  final String id;
  final String sentenceId;
  final int groupIndex;
  final int startTokenIndex;
  final int endTokenIndex;
  final String text;
  final String? label;
  final int? headTokenIndex;
  final double confidence;
  final List<String> sources;

  Map<String, dynamic> toJson() => {
    'id': id,
    'sentence_id': sentenceId,
    'group_index': groupIndex,
    'start_token_index': startTokenIndex,
    'end_token_index': endTokenIndex,
    'text': text,
    'label': label,
    'head_token_index': headTokenIndex,
    'confidence': confidence,
    'sources': sources,
  };
}

/// Projects a text-only sense group through sentence-local word timings.
///
/// The input does not need to be ordered. A partial projection is valid as
/// long as at least one timing belongs to the group's inclusive token span.
({int startMs, int endMs})? senseGroupPlaybackRange(
  SenseGroup group,
  List<WordTiming> timings,
) {
  int? startMs;
  int? endMs;
  for (final timing in timings) {
    if (timing.sentenceId != group.sentenceId ||
        timing.tokenIndex < group.startTokenIndex ||
        timing.tokenIndex > group.endTokenIndex) {
      continue;
    }
    final timingStartMs = timing.start.inMilliseconds;
    final timingEndMs = timing.end.inMilliseconds;
    if (startMs == null || timingStartMs < startMs) startMs = timingStartMs;
    if (endMs == null || timingEndMs > endMs) endMs = timingEndMs;
  }
  return startMs == null || endMs == null
      ? null
      : (startMs: startMs, endMs: endMs);
}

class SenseGroupAnalysis {
  const SenseGroupAnalysis({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.providerId,
    required this.providerVersion,
    required this.algorithm,
    required this.createdBy,
    required this.status,
    required this.metricsJson,
    required this.groups,
    required this.createdAt,
    required this.updatedAt,
    this.parentWordTimelineId,
  });

  factory SenseGroupAnalysis.fromJson(Map<String, dynamic> json) =>
      SenseGroupAnalysis(
        id: json['id'] as String,
        trackId: json['track_id'] as String,
        mediaId: json['media_id'] as String,
        parentWordTimelineId: json['parent_word_timeline_id'] as String?,
        providerId: json['provider_id'] as String,
        providerVersion: json['provider_version'] as String,
        algorithm: json['algorithm'] as String,
        createdBy: json['created_by'] as String,
        status: json['status'] as String,
        metricsJson: TimelineMetrics.fromJson(json['metrics_json']),
        groups: (json['groups'] as List<dynamic>)
            .map((value) => SenseGroup.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        createdAt: Duration(milliseconds: json['created_at_ms'] as int),
        updatedAt: Duration(milliseconds: json['updated_at_ms'] as int),
      );

  final String id;
  final String trackId;
  final String mediaId;
  final String? parentWordTimelineId;
  final String providerId;
  final String providerVersion;
  final String algorithm;
  final String createdBy;
  final String status;
  final TimelineMetrics metricsJson;
  final List<SenseGroup> groups;
  final Duration createdAt;
  final Duration updatedAt;

  bool get isActive => status == 'active';
}

class SenseGroupAnalysisSummary {
  const SenseGroupAnalysisSummary({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.providerId,
    required this.providerVersion,
    required this.algorithm,
    required this.createdBy,
    required this.status,
    required this.groupCount,
    required this.canActivate,
    required this.canArchive,
    required this.canDelete,
    this.parentWordTimelineId,
  });

  factory SenseGroupAnalysisSummary.fromJson(Map<String, dynamic> json) =>
      SenseGroupAnalysisSummary(
        id: json['id'] as String,
        trackId: json['track_id'] as String,
        mediaId: json['media_id'] as String,
        parentWordTimelineId: json['parent_word_timeline_id'] as String?,
        providerId: json['provider_id'] as String,
        providerVersion: json['provider_version'] as String,
        algorithm: json['algorithm'] as String,
        createdBy: json['created_by'] as String,
        status: json['status'] as String,
        groupCount: json['group_count'] as int,
        canActivate: json['can_activate'] as bool,
        canArchive: json['can_archive'] as bool,
        canDelete: json['can_delete'] as bool,
      );

  final String id;
  final String trackId;
  final String mediaId;
  final String? parentWordTimelineId;
  final String providerId;
  final String providerVersion;
  final String algorithm;
  final String createdBy;
  final String status;
  final int groupCount;
  final bool canActivate;
  final bool canArchive;
  final bool canDelete;

  bool get isActive => status == 'active';
}
