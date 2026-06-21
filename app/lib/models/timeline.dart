class SubtitleToken {
  const SubtitleToken({
    required this.index,
    required this.kind,
    required this.text,
    required this.normalized,
  });

  factory SubtitleToken.fromJson(Map<String, dynamic> json) => SubtitleToken(
    index: json['index'] as int,
    kind: json['kind'] as String,
    text: json['text'] as String,
    normalized: json['normalized'] as String?,
  );

  final int index;
  final String kind;
  final String text;
  final String? normalized;
}

class Cue {
  const Cue({
    required this.id,
    required this.index,
    required this.start,
    required this.end,
    required this.text,
    required this.tokens,
  });

  factory Cue.fromJson(Map<String, dynamic> json) => Cue(
    id: json['id'] as String,
    index: json['index'] as int,
    start: Duration(milliseconds: json['start'] as int),
    end: Duration(milliseconds: json['end'] as int),
    text: json['display_text'] as String,
    tokens: (json['tokens'] as List<dynamic>)
        .map((value) => SubtitleToken.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  final String id;
  final int index;
  final Duration start;
  final Duration end;
  final String text;
  final List<SubtitleToken> tokens;
}

class SubtitleTrack {
  const SubtitleTrack({
    required this.id,
    required this.cues,
    this.mediaId,
    this.fingerprint,
    this.source = 'subtitle',
    this.status = 'available',
  });

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) => SubtitleTrack(
    id: json['id'] as String,
    mediaId: json['media_id'] as String?,
    fingerprint: json['fingerprint'] as String?,
    source: json['source'] as String? ?? 'subtitle',
    status: json['status'] as String? ?? 'available',
    cues: (json['sentences'] as List<dynamic>)
        .map((value) => Cue.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  final String id;
  final String? mediaId;
  final String? fingerprint;
  final String source;
  final String status;
  final List<Cue> cues;

  bool get archived => status == 'archived';
}

class SubtitleResourceCapabilities {
  const SubtitleResourceCapabilities({
    required this.sentenceTiming,
    required this.wordTiming,
    required this.chunkTiming,
    required this.phoneTiming,
    this.sentenceCount = 0,
    this.wordTimingCount = 0,
    this.chunkCount = 0,
    this.phoneCount = 0,
    this.error,
  });

  factory SubtitleResourceCapabilities.fromCounts({
    required int sentenceCount,
    required int wordTimingCount,
    required int chunkCount,
    required int phoneCount,
    String? error,
  }) => SubtitleResourceCapabilities(
    sentenceTiming: sentenceCount > 0,
    wordTiming: wordTimingCount > 0,
    chunkTiming: chunkCount > 0,
    phoneTiming: phoneCount > 0,
    sentenceCount: sentenceCount,
    wordTimingCount: wordTimingCount,
    chunkCount: chunkCount,
    phoneCount: phoneCount,
    error: error,
  );

  static const empty = SubtitleResourceCapabilities(
    sentenceTiming: false,
    wordTiming: false,
    chunkTiming: false,
    phoneTiming: false,
  );

  final bool sentenceTiming;
  final bool wordTiming;
  final bool chunkTiming;
  final bool phoneTiming;
  final int sentenceCount;
  final int wordTimingCount;
  final int chunkCount;
  final int phoneCount;
  final String? error;

  bool get hasAnyTiming =>
      sentenceTiming || wordTiming || chunkTiming || phoneTiming;
}

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
    metricsJson: Map<String, dynamic>.from(
      (json['metrics_json'] as Map?) ?? const {},
    ),
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
  final Map<String, dynamic> metricsJson;
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
        evidenceJson: Map<String, dynamic>.from(
          (json['evidence_json'] as Map?) ?? const {},
        ),
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
  final Map<String, dynamic> evidenceJson;

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
    metricsJson: Map<String, dynamic>.from(
      (json['metrics_json'] as Map?) ?? const {},
    ),
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
  final Map<String, dynamic> metricsJson;
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

class LLTimelineDocument {
  const LLTimelineDocument({
    required this.schema,
    required this.metadata,
    required this.activeWordTimelineId,
    required this.activeChunkTimelineId,
    required this.artifacts,
  });

  factory LLTimelineDocument.fromJson(Map<String, dynamic> json) =>
      LLTimelineDocument(
        schema: json['schema'] as String,
        metadata: LLTimelineMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>,
        ),
        activeWordTimelineId: json['active_word_timeline_id'] as String?,
        activeChunkTimelineId: json['active_chunk_timeline_id'] as String?,
        artifacts: ((json['artifacts'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  LLTimelineArtifact.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String schema;
  final LLTimelineMetadata metadata;
  final String? activeWordTimelineId;
  final String? activeChunkTimelineId;
  final List<LLTimelineArtifact> artifacts;

  bool get importedResource =>
      metadata.trackSource == 'lltimeline-json-v1' ||
      artifacts.isNotEmpty ||
      activeWordTimelineId != null ||
      activeChunkTimelineId != null;
}

class LLTimelineMetadata {
  const LLTimelineMetadata({
    required this.createdAt,
    required this.generatorId,
    required this.generatorVersion,
    required this.generatorMode,
    required this.mediaTitle,
    required this.mediaFingerprint,
    required this.humanReviewed,
    required this.extra,
    this.language,
  });

  factory LLTimelineMetadata.fromJson(Map<String, dynamic> json) {
    final generator = json['generator'] as Map<String, dynamic>;
    final media = json['media'] as Map<String, dynamic>;
    return LLTimelineMetadata(
      createdAt: Duration(milliseconds: json['created_at_ms'] as int),
      generatorId: generator['id'] as String,
      generatorVersion: generator['version'] as String,
      generatorMode: generator['mode'] as String,
      mediaTitle: media['title'] as String,
      mediaFingerprint: media['fingerprint'] as String,
      language: json['language'] as String?,
      humanReviewed: json['human_reviewed'] as bool,
      extra: (json['extra'] as Map<String, dynamic>?) ?? const {},
    );
  }

  final Duration createdAt;
  final String generatorId;
  final String generatorVersion;
  final String generatorMode;
  final String mediaTitle;
  final String mediaFingerprint;
  final String? language;
  final bool humanReviewed;
  final Map<String, dynamic> extra;

  String? get trackSource => extra['track_source'] as String?;
}

class LLTimelineArtifact {
  const LLTimelineArtifact({
    required this.kind,
    required this.payload,
    this.providerId,
    this.providerVersion,
  });

  factory LLTimelineArtifact.fromJson(Map<String, dynamic> json) =>
      LLTimelineArtifact(
        kind: json['kind'] as String,
        providerId: json['provider_id'] as String?,
        providerVersion: json['provider_version'] as String?,
        payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
      );

  final String kind;
  final String? providerId;
  final String? providerVersion;
  final Map<String, dynamic> payload;
}

Duration? _durationFromNullableMs(int? value) =>
    value == null ? null : Duration(milliseconds: value);

class DetectedPhone {
  const DetectedPhone({
    required this.symbol,
    required this.phoneSet,
    required this.start,
    required this.end,
    required this.confidence,
    required this.tokenIndex,
    required this.provider,
    required this.modelRevision,
  });

  factory DetectedPhone.fromJson(Map<String, dynamic> json) => DetectedPhone(
    symbol: json['symbol'] as String,
    phoneSet: json['phone_set'] as String,
    start: Duration(milliseconds: json['start_ms'] as int),
    end: Duration(milliseconds: json['end_ms'] as int),
    confidence: (json['confidence'] as num?)?.toDouble(),
    tokenIndex: json['token_index'] as int?,
    provider: json['provider_id'] as String,
    modelRevision: json['model_revision'] as String,
  );

  final String symbol;
  final String phoneSet;
  final Duration start;
  final Duration end;
  final double? confidence;
  final int? tokenIndex;
  final String provider;
  final String modelRevision;
}

DetectedPhone? currentDetectedPhoneAt(
  List<DetectedPhone> phones,
  Duration mediaPosition, {
  Duration offset = Duration.zero,
}) {
  final position = mediaPosition - offset;
  for (final phone in phones) {
    if (position >= phone.start && position < phone.end) return phone;
  }
  return null;
}

Map<String, Map<String, dynamic>> latestPhoneticAnalysesBySentence(
  List<Map<String, dynamic>> analyses,
) {
  final values = <String, Map<String, dynamic>>{};
  for (final analysis in analyses) {
    final sentenceId = analysis['sentence_id'] as String?;
    if (sentenceId != null) values.putIfAbsent(sentenceId, () => analysis);
  }
  return values;
}

class DisplayChunk {
  const DisplayChunk({
    required this.index,
    required this.tokenStart,
    required this.tokenEnd,
    required this.text,
    required this.start,
    required this.end,
  });

  factory DisplayChunk.fromJson(Map<String, dynamic> json) => DisplayChunk(
    index: json['index'] as int? ?? json['chunk_index'] as int,
    tokenStart: json['token_start'] as int? ?? json['start_word_index'] as int,
    tokenEnd: json['token_end'] as int? ?? json['end_word_index'] as int,
    text: json['text'] as String,
    start: Duration(milliseconds: json['start_ms'] as int),
    end: Duration(milliseconds: json['end_ms'] as int),
  );

  final int index;
  final int tokenStart;
  final int tokenEnd;
  final String text;
  final Duration start;
  final Duration end;
}

class SentenceChunkPartition {
  const SentenceChunkPartition({
    required this.sentenceId,
    required this.chunks,
    required this.partitionerId,
    required this.partitionerVersion,
    required this.timingQuality,
  });

  factory SentenceChunkPartition.fromJson(Map<String, dynamic> json) =>
      SentenceChunkPartition(
        sentenceId: json['sentence_id'] as String,
        chunks: (json['chunks'] as List<dynamic>)
            .map(
              (value) => DisplayChunk.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        partitionerId: json['partitioner_id'] as String,
        partitionerVersion: json['partitioner_version'] as String,
        timingQuality: json['timing_quality'] as String,
      );

  final String sentenceId;
  final List<DisplayChunk> chunks;
  final String partitionerId;
  final String partitionerVersion;
  final String timingQuality;
}

Map<String, SentenceChunkPartition> chunkPartitionsFromTimeline(
  ChunkTimeline timeline,
) {
  final grouped = <String, List<ChunkTimelineChunk>>{};
  for (final chunk in timeline.chunks) {
    grouped.putIfAbsent(chunk.sentenceId, () => []).add(chunk);
  }
  return Map<String, SentenceChunkPartition>.fromEntries(
    grouped.entries.map((entry) {
      final chunks = [...entry.value]
        ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
      return MapEntry(
        entry.key,
        SentenceChunkPartition(
          sentenceId: entry.key,
          chunks: [
            for (var index = 0; index < chunks.length; index += 1)
              chunks[index].toDisplayChunk(sentenceLocalIndex: index),
          ],
          partitionerId: timeline.providerId,
          partitionerVersion: timeline.providerVersion,
          timingQuality: timeline.precision,
        ),
      );
    }),
  );
}

int? currentWordTokenIndex(
  List<WordTiming> timings,
  Duration mediaPosition, {
  Duration offset = Duration.zero,
}) {
  final position = mediaPosition - offset;
  for (final timing in timings) {
    if (position >= timing.start && position < timing.end) {
      return timing.tokenIndex;
    }
  }
  return null;
}

int? currentChunkAtPosition(
  SentenceChunkPartition? partition,
  Duration mediaPosition, {
  Duration offset = Duration.zero,
}) {
  if (partition == null) return null;
  final position = mediaPosition - offset;
  for (final chunk in partition.chunks) {
    if (position >= chunk.start && position < chunk.end) {
      return chunk.index;
    }
  }
  return null;
}

class TimelineCursor {
  const TimelineCursor(this.cues, {this.offset = Duration.zero});

  final List<Cue> cues;
  final Duration offset;

  Cue? current(Duration mediaPosition) {
    final position = mediaPosition - offset;
    var low = 0;
    var high = cues.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (cues[middle].start <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    for (var index = low - 1; index >= 0; index--) {
      final cue = cues[index];
      if (position < cue.end) return cue;
    }
    return null;
  }

  Cue? previous(Cue? cue) {
    if (cue == null) return null;
    final index = cues.indexWhere((value) => value.id == cue.id);
    return index > 0 ? cues[index - 1] : null;
  }

  Cue? next(Cue? cue) {
    if (cue == null) return cues.firstOrNull;
    final index = cues.indexWhere((value) => value.id == cue.id);
    return index >= 0 && index + 1 < cues.length ? cues[index + 1] : null;
  }

  Duration mediaStart(Cue cue) => _nonNegative(cue.start + offset);
  Duration mediaEnd(Cue cue) => _nonNegative(cue.end + offset);

  Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
