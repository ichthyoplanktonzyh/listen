part of '../timeline.dart';

// Display-oriented derived views (chunks, cursor)
// Split out of timeline.dart (mechanical decomposition).

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
  Duration displayGapTolerance = Duration.zero,
}) {
  final position = mediaPosition - offset;
  WordTiming? previous;
  for (final timing in timings) {
    if (position >= timing.start && position < timing.end) {
      return timing.tokenIndex;
    }
    if (position < timing.start) {
      if (previous != null &&
          displayGapTolerance > Duration.zero &&
          position >= previous.end) {
        final elapsedSincePrevious = position - previous.end;
        if (elapsedSincePrevious <= displayGapTolerance) {
          return previous.tokenIndex;
        }
      }
      return null;
    }
    previous = timing;
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
