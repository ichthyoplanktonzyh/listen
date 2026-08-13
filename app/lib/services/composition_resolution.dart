import 'dart:convert';

import '../models/adopted_composition.dart';

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
}

/// Resolves the learner content of an adopted composition from its exact
/// payload bytes. Pure over the Core facts: transport and file ownership stay
/// in the caller. A missing or malformed required payload resolves to null —
/// the surface degrades honestly instead of guessing.
///
/// [structuredReadingPayload] must be the exact `structured_reading` payload
/// bytes of the composition; [alignmentPayload] the exact
/// `anchor_time_alignment` payload, or null when the composition carries
/// none. Anchor offsets are half-open byte windows into the logical text.
ResolvedComposition? resolveCompositionContent({
  required AdoptedComposition composition,
  required List<int> structuredReadingPayload,
  List<int>? alignmentPayload,
  String? derivedMediaPath,
}) {
  final structuredReading = _decodePayload(structuredReadingPayload);
  if (structuredReading == null) return null;
  final text = structuredReading['text'];
  if (text is! String) return null;

  final anchorMaps = structuredReading['anchors'];
  if (anchorMaps is! List<dynamic>) return null;
  final anchors = <CompositionAnchor>[];
  final sentences = <CompositionSentence>[];
  var sentenceIndex = 0;
  for (final value in anchorMaps) {
    if (value is! Map) continue;
    final map = Map<String, dynamic>.from(value);
    final anchorId = map['anchor_id'];
    final kind = map['kind'];
    final start = map['start_offset'];
    final end = map['end_offset'];
    if (anchorId is! String || kind is! String) continue;
    if (start is! int || end is! int) continue;
    anchors.add(
      CompositionAnchor(
        anchorId: anchorId,
        kind: kind,
        startOffset: start,
        endOffset: end,
      ),
    );
    if (kind == 'sentence') {
      sentences.add(
        CompositionSentence(
          id: anchorId,
          index: sentenceIndex++,
          text: _sliceBytes(text, start, end),
          startByte: start,
          endByte: end,
        ),
      );
    }
  }

  final alignments = <String, int>{};
  final alignment = _decodePayload(alignmentPayload);
  if (alignment != null) {
    final entries = alignment['alignments'];
    if (entries is List<dynamic>) {
      for (final value in entries) {
        if (value is! Map) continue;
        final map = Map<String, dynamic>.from(value);
        final anchorId = map['anchor_id'];
        final mediaTime = map['media_time_ms'];
        if (anchorId is! String || mediaTime is! int) continue;
        alignments[anchorId] = mediaTime;
      }
    }
  }

  return ResolvedComposition(
    releaseId: composition.releaseId,
    editionId: composition.editionId,
    logicalText: text,
    sentences: sentences,
    anchors: anchors,
    alignments: alignments,
    derivedMediaPath: derivedMediaPath,
  );
}

Map<String, dynamic>? _decodePayload(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  } on FormatException {
    return null;
  }
}

/// Slices [text] by UTF-8 byte offsets: the exact half-open window into the
/// logical text's encoded bytes.
String _sliceBytes(String text, int start, int end) {
  final bytes = utf8.encode(text);
  final safeStart = start.clamp(0, bytes.length);
  final safeEnd = end.clamp(safeStart, bytes.length);
  return utf8.decode(bytes.sublist(safeStart, safeEnd), allowMalformed: true);
}
