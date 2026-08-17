/// Fallback projection for the package's tokenless `timed_text_track`.
///
/// `subtitle_text_track` is no longer projected here: Core lands it as a real
/// subtitle track at adoption, and `CompositionSessionService` reads it back
/// through `ResourceRepository.mediaSubtitles` with global sentence ids. The
/// five analysis resource families are likewise read back through Core's
/// LLTimeline export (`composition_core_projection.dart`).
///
/// `timed_text_track` has no Core landing and remains the honest display-only
/// fallback for packages that carry no tokenized subtitle track.
library;

import 'dart:convert';

import '../models/timeline.dart';

/// Reads v2 `timed_text_track` into the transcript shape.
///
/// That contract carries exact segment text and time spans but deliberately
/// carries no tokens. The cues therefore keep an empty token list; the text
/// panel renders [Cue.text] directly and does not claim word lookup, word
/// timing, sense-group or prosody precision that this resource never stated.
SubtitleTrack? projectCompositionTimedTranscript(
  List<int>? payload, {
  required String trackId,
}) {
  final decoded = _decode(payload);
  final segments = decoded?['segments'];
  if (segments is! List) return null;
  final cues = <Cue>[];
  for (final value in segments) {
    if (value is! Map) continue;
    final id = value['id'];
    final index = value['index'];
    final startMs = value['start_ms'];
    final endMs = value['end_ms'];
    final segmentText = value['text'];
    if (id is! String || id.isEmpty || index is! int || index < 0) continue;
    if (startMs is! int || endMs is! int || endMs < startMs) continue;
    if (segmentText is! String || segmentText.isEmpty) continue;
    cues.add(
      Cue(
        id: id,
        index: index,
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
        text: segmentText,
        tokens: const [],
      ),
    );
  }
  if (cues.isEmpty) return null;
  cues.sort((a, b) => a.index.compareTo(b.index));
  final language = decoded?['language'];
  return SubtitleTrack(
    id: trackId,
    language: language is String ? language : null,
    source: 'composition',
    cues: List<Cue>.unmodifiable(cues),
  );
}

Map<String, dynamic>? _decode(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    // A resource that does not parse is a resource the workbench does not
    // have. It is never a reason to fail the material.
    return null;
  }
}
