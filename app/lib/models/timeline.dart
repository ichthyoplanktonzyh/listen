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
  const SubtitleTrack({required this.id, required this.cues});

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) => SubtitleTrack(
    id: json['id'] as String,
    cues: (json['sentences'] as List<dynamic>)
        .map((value) => Cue.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  final String id;
  final List<Cue> cues;
}

class WordTiming {
  const WordTiming({
    required this.sentenceId,
    required this.tokenIndex,
    required this.start,
    required this.end,
    required this.source,
    required this.provider,
  });

  factory WordTiming.fromJson(Map<String, dynamic> json) => WordTiming(
    sentenceId: json['sentence_id'] as String,
    tokenIndex: json['token_index'] as int,
    start: Duration(milliseconds: json['start_ms'] as int),
    end: Duration(milliseconds: json['end_ms'] as int),
    source: json['timing_source'] as String,
    provider: json['provider_id'] as String,
  );

  final String sentenceId;
  final int tokenIndex;
  final Duration start;
  final Duration end;
  final String source;
  final String provider;
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
    index: json['index'] as int,
    tokenStart: json['token_start'] as int,
    tokenEnd: json['token_end'] as int,
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
