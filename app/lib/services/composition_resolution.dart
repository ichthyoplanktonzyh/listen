import 'dart:convert';

import '../models/adopted_composition.dart';
import '../models/composition.dart';
import '../models/timeline.dart';

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
  SubtitleTrack? transcript,
  CompositionResourceProjection enhancements =
      const CompositionResourceProjection(),
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
    transcript: transcript,
    enhancements: enhancements,
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
