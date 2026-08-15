import 'dart:convert';
import 'dart:io';

import '../models/adopted_composition.dart';
import '../models/timeline.dart';

/// Bridges an adopted composition's structured reading into the
/// subtitle-track surface, so the media workbench transcript panel can show a
/// prepared learning transcript.
///
/// The Core package surface and the subtitle-track surface do not share
/// storage: a freshly prepared learning transcript otherwise stays invisible
/// to the workbench. This service round-trips the reading through the
/// track-import API Core already owns — sentence text plus per-sentence anchor
/// times become an srt file and then a durable subtitle track.
///
/// Word-level timelines and phoneme resources from the package stay on the
/// composition surface for now; this bridge only makes the transcript itself
/// visible and sentence-followable.
class CompositionTranscriptBridge {
  const CompositionTranscriptBridge({
    required this.readComposition,
    required this.readResourcePayload,
    required this.importSubtitle,
  });

  /// Reads the adopted composition of a material (Core-owned interface).
  final Future<AdoptedComposition> Function(String materialId) readComposition;

  /// Reads one resource payload's exact bytes of an adopted composition.
  final Future<List<int>> Function(String materialId, String resourceId)
  readResourcePayload;

  /// Imports an srt file into the media's subtitle tracks.
  final Future<SubtitleTrack> Function(String mediaId, String path)
  importSubtitle;

  /// Imports the adopted composition's structured reading as a subtitle
  /// track. Returns the imported track, or null when the composition has no
  /// reading or no sentence times to bridge.
  Future<SubtitleTrack?> bridge(String materialId, String mediaId) async {
    final composition = await readComposition(materialId);
    final reading = composition.resourceOfKind('structured_reading');
    final anchors = composition.resourceOfKind('anchor_time_alignment');
    if (reading == null || anchors == null) return null;
    final readingBytes = await readResourcePayload(materialId, reading.resourceId);
    final anchorBytes = await readResourcePayload(materialId, anchors.resourceId);
    final srt = compositionToSrt(
      jsonDecode(utf8.decode(readingBytes)) as Map<String, dynamic>,
      jsonDecode(utf8.decode(anchorBytes)) as Map<String, dynamic>,
    );
    if (srt == null) return null;
    final directory = Directory.systemTemp.createTempSync(
      'listen-learning-transcript-',
    );
    final path = '${directory.path}/learning-transcript.srt';
    await File(path).writeAsString(srt, flush: true);
    return importSubtitle(mediaId, path);
  }

  /// Builds srt text from the structured reading and its anchor alignments.
  ///
  /// Sentences come from the reading's `anchors` (character offsets into
  /// `text`); times come from the `anchor_time_alignment` `alignments`
  /// (sentence id → start ms). Each sentence's end is the next sentence's
  /// start; the final sentence gets a nominal tail. Sentences without a time
  /// anchor are dropped — an unanchored line would be a fabrication.
  static String? compositionToSrt(
    Map<String, dynamic> reading,
    Map<String, dynamic> alignment,
  ) {
    final text = reading['text'];
    final anchors = reading['anchors'];
    final alignments = alignment['alignments'];
    if (text is! String || anchors is! List || alignments is! List) {
      return null;
    }
    final sentenceText = <String, String>{};
    for (final anchor in anchors) {
      if (anchor is! Map) continue;
      final id = anchor['anchor_id'];
      final start = anchor['start_offset'];
      final end = anchor['end_offset'];
      if (id is! String ||
          !id.startsWith('sentence-') ||
          start is! int ||
          end is! int) {
        continue;
      }
      sentenceText[id] = text.substring(start, end).trim();
    }
    final times = <String, int>{};
    for (final entry in alignments) {
      if (entry is! Map) continue;
      final id = entry['anchor_id'];
      final ms = entry['media_time_ms'];
      if (id is String && ms is int) times[id] = ms;
    }
    final ordered = sentenceText.keys.toList()
      ..sort((a, b) => (times[a] ?? 0).compareTo(times[b] ?? 0));
    if (ordered.isEmpty) return null;
    final buffer = StringBuffer();
    var index = 1;
    for (var i = 0; i < ordered.length; i += 1) {
      final id = ordered[i];
      final startMs = times[id];
      if (startMs == null) continue;
      final endMs = i + 1 < ordered.length
          ? (times[ordered[i + 1]] ?? startMs + 3000)
          : startMs + 5000;
      if (endMs <= startMs) continue;
      final body = sentenceText[id] ?? '';
      if (body.isEmpty) continue;
      buffer
        ..writeln(index)
        ..writeln('${_srtTime(startMs)} --> ${_srtTime(endMs)}')
        ..writeln(body)
        ..writeln();
      index += 1;
    }
    return buffer.isEmpty || index == 1 ? null : buffer.toString();
  }

  static String _srtTime(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    final millis = ms % 1000;
    String pad(int value, [int width = 2]) =>
        value.toString().padLeft(width, '0');
    return '${pad(h)}:${pad(m)}:${pad(s)},${pad(millis, 3)}';
  }
}
