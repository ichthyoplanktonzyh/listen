/// The learner-facing shape of an adopted Composition.
///
/// Pure domain data, deliberately separate from the resolver that builds it
/// (`services/composition_resolution.dart`): the workbench's session state
/// holds these types, and `lib/models` may not depend on `lib/services`.
library;

import 'timeline.dart';

/// One sentence of the adopted composition's reading structure: an exact
/// byte window into the Structured Reading's logical text.
class CompositionSentence {
  const CompositionSentence({
    required this.id,
    required this.index,
    required this.text,
    required this.startByte,
    required this.endByte,
  });

  final String id;
  final int index;
  final String text;
  final int startByte;
  final int endByte;
}

/// One anchor of the structured reading: a block, a sentence, or a span,
/// addressed by byte offsets into the logical text.
class CompositionAnchor {
  const CompositionAnchor({
    required this.anchorId,
    required this.kind,
    required this.startOffset,
    required this.endOffset,
  });

  final String anchorId;

  /// 'block' | 'sentence' | 'span'.
  final String kind;
  final int startOffset;
  final int endOffset;
}

/// The learner-facing content of one adopted Composition, resolved through
/// Core's composition interface: the exact logical text and sentence
/// structure, the reading anchors, the anchor-to-time alignment, and the
/// derived audio (when the composition carries one).
class ResolvedComposition {
  ResolvedComposition({
    required this.releaseId,
    required this.editionId,
    required this.logicalText,
    required List<CompositionSentence> sentences,
    required List<CompositionAnchor> anchors,
    required this.alignments,
    this.derivedMediaPath,
    this.transcript,
    this.enhancements = const CompositionResourceProjection(),
  }) : _sentences = List.unmodifiable(sentences),
       _anchors = List.unmodifiable(anchors);

  final String releaseId;
  final String editionId;
  final String logicalText;
  final List<CompositionSentence> _sentences;
  List<CompositionSentence> get sentences => List.unmodifiable(_sentences);
  final List<CompositionAnchor> _anchors;
  List<CompositionAnchor> get anchors => List.unmodifiable(_anchors);

  /// anchor id → media time in milliseconds.
  final Map<String, int> alignments;

  /// Local path of the downloaded derived audio, when the composition carries
  /// one with embedded bytes.
  final String? derivedMediaPath;

  /// The package's exact timed text track, when one was selected into the
  /// adopted composition. This is the shape the existing workbench transcript
  /// already consumes; keeping it here lets text→TTS use that same right-hand
  /// panel instead of a second, simplified sentence renderer.
  final SubtitleTrack? transcript;

  /// Whether the timed text can drive the app's actual learning interactions,
  /// not merely display lines. A tokenless timed track is useful evidence and
  /// remains preserved, but it cannot support word lookup or token-bound
  /// analysis and therefore is not a complete learning surface.
  bool get hasInteractiveTranscript {
    final cues = transcript?.cues;
    return cues != null &&
        cues.isNotEmpty &&
        cues.every((cue) => cue.tokens.any((token) => token.kind == 'word'));
  }

  /// What the package's word-level resources contribute — word timings,
  /// sense groups, acoustic measurements, prosodic chunks and anchors, and
  /// phone timings.
  final CompositionResourceProjection enhancements;
}

/// Exact acoustic evidence measured for one word in the composition's Word
/// Timeline. The maps retain the payload's named numeric facts without
/// translating them into a second analysis vocabulary in the App.
class CompositionWordAcoustics {
  CompositionWordAcoustics({
    required this.sentenceId,
    required this.tokenIndex,
    required Map<String, num> energy,
    required Map<String, num> pitch,
    required Map<String, num> duration,
    required this.voicedFrameRatio,
  }) : energy = Map.unmodifiable(energy),
       pitch = Map.unmodifiable(pitch),
       duration = Map.unmodifiable(duration);

  final String sentenceId;
  final int tokenIndex;
  final Map<String, num> energy;
  final Map<String, num> pitch;
  final Map<String, num> duration;
  final double voicedFrameRatio;
}

/// One word-anchored fact from `prosody_analysis.anchors`.
class CompositionProsodyAnchor {
  CompositionProsodyAnchor({
    required this.sentenceId,
    required this.tokenIndex,
    required this.lexicalStress,
    required this.realizedProminence,
    required this.utteranceRole,
    required List<String> evidence,
    required this.confidence,
    this.syllableIndex,
  }) : evidence = List.unmodifiable(evidence);

  final String sentenceId;
  final int tokenIndex;
  final String? lexicalStress;
  final double? realizedProminence;
  final String? utteranceRole;
  final List<String> evidence;
  final double confidence;
  final int? syllableIndex;
}

/// What one composition's word-level resources contribute to the workbench.
class CompositionResourceProjection {
  const CompositionResourceProjection({
    this.timingsBySentence = const {},
    this.senseGroupsBySentence = const {},
    this.chunkPartitionsBySentence = const {},
    this.acousticsBySentence = const {},
    this.prosodyAnchorsBySentence = const {},
    this.phonesBySentence = const {},
  });

  final Map<String, List<WordTiming>> timingsBySentence;
  final Map<String, List<SenseGroup>> senseGroupsBySentence;
  final Map<String, SentenceChunkPartition> chunkPartitionsBySentence;
  final Map<String, List<CompositionWordAcoustics>> acousticsBySentence;
  final Map<String, List<CompositionProsodyAnchor>> prosodyAnchorsBySentence;
  final Map<String, List<DetectedPhone>> phonesBySentence;

  bool get isEmpty =>
      timingsBySentence.isEmpty &&
      senseGroupsBySentence.isEmpty &&
      chunkPartitionsBySentence.isEmpty &&
      acousticsBySentence.isEmpty &&
      prosodyAnchorsBySentence.isEmpty &&
      phonesBySentence.isEmpty;
}
