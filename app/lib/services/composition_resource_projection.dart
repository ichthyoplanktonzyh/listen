/// Fallback projection for the package's tokenless `timed_text_track`.
///
/// Core lands media subtitles as a real track at adoption. A document has no
/// source media id, so this module also validates its selected tokenized
/// subtitle and rich-resource payloads in a detached, local namespace.
///
/// `timed_text_track` has no Core landing and remains the honest display-only
/// fallback for packages that carry no tokenized subtitle track.
library;

import 'dart:convert';

import '../models/composition.dart';
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

/// Projects a tokenized `subtitle_text_track` that Core kept as a selected
/// composition resource but could not attach to a source media id.
///
/// This is deliberately a different track namespace from Core's landed
/// `package:subtitle_text_track`: detached document audio has no media track
/// and therefore cannot safely participate in Core's global sentence/timeline
/// APIs. All text, token slots and sentence times below are copied from the
/// verified Core payload; this function never derives coordinates.
SubtitleTrack? projectCompositionDetachedSubtitleTranscript(
  List<int>? payload, {
  required String trackId,
}) {
  if (trackId.isEmpty) return null;
  final decoded = _decodeStrict(payload);
  final values = decoded?['sentences'];
  if (values is! List || values.isEmpty) return null;

  final cues = <Cue>[];
  final sentenceIds = <String>{};
  for (final value in values) {
    if (value is! Map) return null;
    final sentence = Map<String, dynamic>.from(value);
    final id = sentence['id'];
    final index = sentence['index'];
    final displayText = sentence['display_text'];
    final startMs = sentence['start_ms'];
    final endMs = sentence['end_ms'];
    final tokenValues = sentence['tokens'];
    if (id is! String ||
        id.isEmpty ||
        index is! int ||
        index < 0 ||
        displayText is! String ||
        displayText.isEmpty ||
        startMs is! int ||
        startMs < 0 ||
        endMs is! int ||
        endMs <= startMs ||
        !sentenceIds.add(id) ||
        tokenValues is! List ||
        tokenValues.isEmpty) {
      return null;
    }

    final tokens = <SubtitleToken>[];
    final displayRunes = displayText.runes.toList(growable: false);
    final reconstructed = StringBuffer();
    var previousEnd = 0;
    for (
      var tokenPosition = 0;
      tokenPosition < tokenValues.length;
      tokenPosition++
    ) {
      final value = tokenValues[tokenPosition];
      if (value is! Map) return null;
      final token = Map<String, dynamic>.from(value);
      final tokenIndex = token['index'];
      final kind = token['kind'];
      final text = token['text'];
      final normalized = token['normalized'];
      final startChar = token['start_char'];
      final endChar = token['end_char'];
      if (tokenIndex is! int ||
          tokenIndex != tokenPosition ||
          kind is! String ||
          !const {
            'word',
            'whitespace',
            'punctuation',
            'other',
          }.contains(kind) ||
          text is! String ||
          text.isEmpty ||
          (normalized != null && normalized is! String) ||
          (kind == 'word' && normalized is! String) ||
          startChar is! int ||
          endChar is! int ||
          startChar != previousEnd ||
          endChar <= startChar ||
          endChar > displayRunes.length ||
          endChar - startChar != text.runes.length ||
          !_sameRunes(displayRunes.sublist(startChar, endChar), text.runes)) {
        return null;
      }
      reconstructed.write(text);
      tokens.add(
        SubtitleToken(
          index: tokenIndex,
          kind: kind,
          text: text,
          normalized: normalized as String?,
        ),
      );
      previousEnd = endChar;
    }
    if (previousEnd != displayRunes.length ||
        reconstructed.toString() != displayText) {
      return null;
    }

    cues.add(
      Cue(
        id: id,
        index: index,
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
        text: displayText,
        tokens: List<SubtitleToken>.unmodifiable(tokens),
      ),
    );
  }

  cues.sort((a, b) => a.index.compareTo(b.index));
  var previousCueEnd = Duration.zero;
  for (var position = 0; position < cues.length; position++) {
    final cue = cues[position];
    if (cue.index != position || cue.start < previousCueEnd) return null;
    previousCueEnd = cue.end;
  }
  final language = decoded?['language'];
  if (language != null && (language is! String || language.isEmpty)) {
    return null;
  }
  return SubtitleTrack(
    id: trackId,
    language: language as String?,
    source: 'composition:detached:subtitle_text_track',
    cues: List<Cue>.unmodifiable(cues),
  );
}

bool _sameRunes(Iterable<int> left, Iterable<int> right) {
  final a = left.toList(growable: false);
  final b = right.toList(growable: false);
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Projects the optional rich resources of a detached composition onto the
/// exact local subtitle sentence/token namespace returned by
/// [projectCompositionDetachedSubtitleTranscript].
///
/// Core can re-key these resources to global sentence ids only when a source
/// media id exists. A document's TTS rendition has no such id, so this path
/// validates every reference and time window locally and deliberately keeps
/// the detached namespace. Invalid entries (or an invalid family) are
/// dropped independently; no timing is invented from text or audio.
CompositionResourceProjection projectCompositionDetachedResources({
  required SubtitleTrack track,
  required Map<String, List<int>> payloads,
}) {
  final tokenTables = <String, Map<int, SubtitleToken>>{};
  final cueById = <String, Cue>{};
  for (final cue in track.cues) {
    cueById[cue.id] = cue;
    tokenTables[cue.id] = {for (final token in cue.tokens) token.index: token};
  }

  final timingsBySentence = _detachedWordTimings(
    _decodeStrict(payloads['word_timeline']),
    cueById: cueById,
    tokenTables: tokenTables,
  );
  final timingByRef = <String, WordTiming>{};
  for (final values in timingsBySentence.values) {
    for (final timing in values) {
      timingByRef[_detachedRefKey(timing.sentenceId, timing.tokenIndex)] =
          timing;
    }
  }

  return CompositionResourceProjection(
    timingsBySentence: timingsBySentence,
    senseGroupsBySentence: _detachedSenseGroups(
      _decodeStrict(payloads['sense_group_analysis']),
      cueById: cueById,
      tokenTables: tokenTables,
      timingByRef: timingByRef,
    ),
    chunkPartitionsBySentence: _detachedChunks(
      _decodeStrict(payloads['prosody_analysis']),
      cueById: cueById,
      tokenTables: tokenTables,
      timingsBySentence: timingsBySentence,
    ),
    acousticsBySentence: _detachedAcoustics(
      _decodeStrict(payloads['word_acoustics']),
      timingByRef: timingByRef,
    ),
    prosodyAnchorsBySentence: _detachedProsodyAnchors(
      _decodeStrict(payloads['prosody_analysis']),
      timingByRef: timingByRef,
    ),
    phonesBySentence: _detachedPhones(
      _decodeStrict(payloads['phone_timeline']),
      cueById: cueById,
      timingByRef: timingByRef,
    ),
  );
}

Map<String, List<WordTiming>> _detachedWordTimings(
  Map<String, dynamic>? decoded, {
  required Map<String, Cue> cueById,
  required Map<String, Map<int, SubtitleToken>> tokenTables,
}) {
  final values = decoded?['words'];
  if (values is! List) return const {};
  final result = <String, List<WordTiming>>{};
  final seen = <String>{};
  for (final value in values) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final sentenceId = _detachedSentenceId(item, cueById);
    final tokenIndex = item['token_index'];
    final startMs = item['start_ms'];
    final endMs = item['end_ms'];
    final source = item['timing_source'];
    if (sentenceId == null ||
        tokenIndex is! int ||
        tokenIndex < 0 ||
        startMs is! int ||
        endMs is! int ||
        startMs < 0 ||
        endMs <= startMs ||
        source is! String ||
        !_detachedTimingSources.contains(source)) {
      continue;
    }
    final cue = cueById[sentenceId]!;
    final token = tokenTables[sentenceId]![tokenIndex];
    if (token == null || token.kind != 'word') continue;
    if (startMs < cue.start.inMilliseconds || endMs > cue.end.inMilliseconds) {
      continue;
    }
    final key = _detachedRefKey(sentenceId, tokenIndex);
    if (!seen.add(key)) continue;
    final confidenceValue = item['confidence'];
    final confidence = _detachedConfidence(confidenceValue);
    if (item.containsKey('confidence') && confidence == null) continue;
    result
        .putIfAbsent(sentenceId, () => <WordTiming>[])
        .add(
          WordTiming(
            sentenceId: sentenceId,
            tokenIndex: tokenIndex,
            text: token.text,
            start: Duration(milliseconds: startMs),
            end: Duration(milliseconds: endMs),
            confidence: confidence,
            source: source,
            provider: 'composition-detached',
            providerVersion: 'verified-payload',
          ),
        );
  }
  for (final values in result.values) {
    values.sort((a, b) => a.tokenIndex.compareTo(b.tokenIndex));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<WordTiming>.unmodifiable(entry.value),
  });
}

Map<String, List<SenseGroup>> _detachedSenseGroups(
  Map<String, dynamic>? decoded, {
  required Map<String, Cue> cueById,
  required Map<String, Map<int, SubtitleToken>> tokenTables,
  required Map<String, WordTiming> timingByRef,
}) {
  final values = decoded?['groups'];
  if (values is! List) return const {};
  final result = <String, List<SenseGroup>>{};
  final seen = <String>{};
  for (final value in values) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final sentenceId = _detachedSentenceId(item, cueById);
    final groupIndex = item['group_index'];
    final start = item['start_token_index'];
    final endExclusive = item['end_token_index_exclusive'];
    final confidenceValue = item['confidence'];
    final confidence = _detachedConfidence(confidenceValue);
    final sources = item['sources'];
    final label = item['label'];
    if (sentenceId == null ||
        groupIndex is! int ||
        groupIndex < 0 ||
        start is! int ||
        endExclusive is! int ||
        start < 0 ||
        endExclusive <= start ||
        confidence == null ||
        sources is! List ||
        sources.isEmpty ||
        !sources.every((source) => source is String && source.isNotEmpty)) {
      continue;
    }
    if (label != null && label is! String) continue;
    final tokens = tokenTables[sentenceId]!;
    if (endExclusive > tokens.length ||
        !_detachedSpanHasTiming(sentenceId, start, endExclusive, timingByRef)) {
      continue;
    }
    final id = '$sentenceId:$groupIndex';
    if (!seen.add(id)) continue;
    final head = item['head_token_index'];
    if (head != null &&
        (head is! int || head < start || head >= endExclusive)) {
      continue;
    }
    result
        .putIfAbsent(sentenceId, () => <SenseGroup>[])
        .add(
          SenseGroup(
            id: id,
            sentenceId: sentenceId,
            groupIndex: groupIndex,
            startTokenIndex: start,
            endTokenIndex: endExclusive - 1,
            text: _detachedJoinTokens(tokens, start, endExclusive - 1),
            confidence: confidence,
            sources: sources.cast<String>().toList(growable: false),
            label: label as String?,
            headTokenIndex: head as int?,
          ),
        );
  }
  for (final values in result.values) {
    values.sort((a, b) => a.groupIndex.compareTo(b.groupIndex));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<SenseGroup>.unmodifiable(entry.value),
  });
}

Map<String, SentenceChunkPartition> _detachedChunks(
  Map<String, dynamic>? decoded, {
  required Map<String, Cue> cueById,
  required Map<String, Map<int, SubtitleToken>> tokenTables,
  required Map<String, List<WordTiming>> timingsBySentence,
}) {
  final values = decoded?['chunks'];
  if (values is! List) return const {};
  final chunksBySentence = <String, List<DisplayChunk>>{};
  final sourcesBySentence = <String, Set<String>>{};
  final seen = <String>{};
  for (final value in values) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final sentenceId = _detachedSentenceId(item, cueById);
    final index = item['chunk_index'];
    final start = item['start_token_index'];
    final endExclusive = item['end_token_index_exclusive'];
    final confidence = _detachedConfidence(item['confidence']);
    if (sentenceId == null ||
        index is! int ||
        index < 0 ||
        start is! int ||
        endExclusive is! int ||
        start < 0 ||
        endExclusive <= start ||
        confidence == null) {
      continue;
    }
    final tokens = tokenTables[sentenceId]!;
    if (endExclusive > tokens.length) continue;
    final window = _detachedWindow(
      timingsBySentence[sentenceId],
      start,
      endExclusive - 1,
    );
    if (window == null) continue;
    final key = '$sentenceId:$index';
    if (!seen.add(key)) continue;
    final nucleus = item['nucleus_token_index'];
    if (nucleus != null &&
        (nucleus is! int || nucleus < start || nucleus >= endExclusive)) {
      continue;
    }
    chunksBySentence
        .putIfAbsent(sentenceId, () => <DisplayChunk>[])
        .add(
          DisplayChunk(
            index: index,
            tokenStart: start,
            tokenEnd: endExclusive - 1,
            text: _detachedJoinTokens(tokens, start, endExclusive - 1),
            start: window.start,
            end: window.end,
          ),
        );
    sourcesBySentence
        .putIfAbsent(sentenceId, () => <String>{})
        .addAll(window.sources);
  }
  return Map.unmodifiable({
    for (final entry in chunksBySentence.entries)
      entry.key: SentenceChunkPartition(
        sentenceId: entry.key,
        chunks: List<DisplayChunk>.unmodifiable(
          entry.value..sort((a, b) => a.index.compareTo(b.index)),
        ),
        partitionerId: 'composition:detached:prosody_analysis',
        partitionerVersion: 'verified-payload',
        timingQuality:
            (sourcesBySentence[entry.key] ?? const <String>{}).length == 1
            ? sourcesBySentence[entry.key]!.single
            : 'mixed',
      ),
  });
}

Map<String, List<CompositionWordAcoustics>> _detachedAcoustics(
  Map<String, dynamic>? decoded, {
  required Map<String, WordTiming> timingByRef,
}) {
  final values = decoded?['measurements'];
  if (values is! List) return const {};
  final result = <String, List<CompositionWordAcoustics>>{};
  final seen = <String>{};
  for (final value in values) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final ref = _detachedRef(item['word_ref']);
    final timing = ref == null ? null : timingByRef[ref.key];
    final energy = _detachedNumericMap(item['energy']);
    final pitch = _detachedNumericMap(item['pitch']);
    final duration = _detachedNumericMap(item['duration']);
    final voiced = _detachedConfidence(item['voiced_frame_ratio']);
    if (ref == null ||
        timing == null ||
        energy == null ||
        pitch == null ||
        duration == null ||
        voiced == null ||
        !seen.add(ref.key)) {
      continue;
    }
    final resolvedRef = ref;
    result
        .putIfAbsent(resolvedRef.sentenceId, () => <CompositionWordAcoustics>[])
        .add(
          CompositionWordAcoustics(
            sentenceId: resolvedRef.sentenceId,
            tokenIndex: resolvedRef.tokenIndex,
            energy: energy,
            pitch: pitch,
            duration: duration,
            voicedFrameRatio: voiced,
          ),
        );
  }
  for (final values in result.values) {
    values.sort((a, b) => a.tokenIndex.compareTo(b.tokenIndex));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<CompositionWordAcoustics>.unmodifiable(entry.value),
  });
}

Map<String, List<CompositionProsodyAnchor>> _detachedProsodyAnchors(
  Map<String, dynamic>? decoded, {
  required Map<String, WordTiming> timingByRef,
}) {
  final values = decoded?['anchors'];
  if (values is! List) return const {};
  final result = <String, List<CompositionProsodyAnchor>>{};
  final seen = <String>{};
  for (final value in values) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final ref = _detachedRef(item['word_ref']);
    final confidence = _detachedConfidence(item['confidence']);
    final evidence = item['evidence'];
    final realized = item['realized_prominence'];
    final syllable = item['syllable_index'];
    final lexicalStress = item['lexical_stress'];
    final utteranceRole = item['utterance_role'];
    if (syllable != null && (syllable is! int || syllable < 0)) continue;
    if (lexicalStress != null && lexicalStress is! String) continue;
    if (utteranceRole != null && utteranceRole is! String) continue;
    if (realized is! num || realized < 0 || realized > 1) continue;
    if (ref == null ||
        timingByRef[ref.key] == null ||
        confidence == null ||
        evidence is! List ||
        evidence.isEmpty ||
        !evidence.every((entry) => entry is String && entry.isNotEmpty) ||
        !seen.add('${ref.key}:${syllable ?? -1}')) {
      continue;
    }
    final resolvedRef = ref;
    result
        .putIfAbsent(resolvedRef.sentenceId, () => <CompositionProsodyAnchor>[])
        .add(
          CompositionProsodyAnchor(
            sentenceId: resolvedRef.sentenceId,
            tokenIndex: resolvedRef.tokenIndex,
            lexicalStress: lexicalStress as String?,
            realizedProminence: realized.toDouble(),
            utteranceRole: utteranceRole as String?,
            evidence: evidence.cast<String>().toList(growable: false),
            confidence: confidence,
            syllableIndex: syllable as int?,
          ),
        );
  }
  for (final values in result.values) {
    values.sort((a, b) => a.tokenIndex.compareTo(b.tokenIndex));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<CompositionProsodyAnchor>.unmodifiable(entry.value),
  });
}

Map<String, List<DetectedPhone>> _detachedPhones(
  Map<String, dynamic>? decoded, {
  required Map<String, Cue> cueById,
  required Map<String, WordTiming> timingByRef,
}) {
  final values = decoded?['phones'];
  if (values is! List) return const {};
  final result = <String, List<DetectedPhone>>{};
  for (final value in values) {
    if (value is! Map) continue;
    final item = Map<String, dynamic>.from(value);
    final ref = _detachedRef(item['word_ref']);
    final timing = ref == null ? null : timingByRef[ref.key];
    final symbol = item['symbol'];
    final startMs = item['start_ms'];
    final endMs = item['end_ms'];
    final confidenceValue = item['confidence'];
    final confidence = _detachedConfidence(confidenceValue);
    final phoneSet = decoded?['phone_set'];
    final precision = decoded?['precision'];
    if (ref == null ||
        timing == null ||
        symbol is! String ||
        symbol.isEmpty ||
        startMs is! int ||
        endMs is! int ||
        endMs <= startMs ||
        startMs < timing.start.inMilliseconds ||
        endMs > timing.end.inMilliseconds ||
        (confidenceValue != null && confidence == null) ||
        phoneSet is! String ||
        phoneSet.isEmpty ||
        precision is! String ||
        precision.isEmpty) {
      continue;
    }
    final cue = cueById[ref.sentenceId];
    if (cue == null ||
        startMs < cue.start.inMilliseconds ||
        endMs > cue.end.inMilliseconds) {
      continue;
    }
    final displayIpa = item['display_ipa'];
    if (displayIpa != null && displayIpa is! String) continue;
    result
        .putIfAbsent(ref.sentenceId, () => <DetectedPhone>[])
        .add(
          DetectedPhone(
            symbol: symbol,
            displayIpa: displayIpa as String? ?? symbol,
            phoneSet: phoneSet,
            start: Duration(milliseconds: startMs),
            end: Duration(milliseconds: endMs),
            confidence: confidence,
            tokenIndex: ref.tokenIndex,
            provider: 'composition-detached',
            modelRevision: 'verified-payload',
          ),
        );
  }
  for (final values in result.values) {
    values.sort((a, b) => a.start.compareTo(b.start));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<DetectedPhone>.unmodifiable(entry.value),
  });
}

const _detachedTimingSources = {
  'asr_reported',
  'asr_aligned',
  'forced_aligned',
  'estimated',
  'user_adjusted',
};

String? _detachedSentenceId(
  Map<String, dynamic> value,
  Map<String, Cue> cueById,
) {
  final id = value['sentence_id'];
  if (value.containsKey('sentence_id')) {
    return id is String && cueById.containsKey(id) ? id : null;
  }
  final index = value['sentence_index'];
  if (index is! int || index < 0) return null;
  for (final cue in cueById.values) {
    if (cue.index == index) return cue.id;
  }
  return null;
}

({String sentenceId, int tokenIndex, String key})? _detachedRef(Object? value) {
  if (value is! Map) return null;
  final map = Map<String, dynamic>.from(value);
  final sentenceId = map['sentence_id'];
  final tokenIndex = map['token_index'];
  if (sentenceId is! String ||
      sentenceId.isEmpty ||
      tokenIndex is! int ||
      tokenIndex < 0) {
    return null;
  }
  return (
    sentenceId: sentenceId,
    tokenIndex: tokenIndex,
    key: _detachedRefKey(sentenceId, tokenIndex),
  );
}

String _detachedRefKey(String sentenceId, int tokenIndex) =>
    '$sentenceId#$tokenIndex';

double? _detachedConfidence(Object? value) {
  if (value is! num || value < 0 || value > 1) return null;
  return value.toDouble();
}

Map<String, num>? _detachedNumericMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, num>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! num) return null;
    result[entry.key as String] = entry.value as num;
  }
  return result.isEmpty ? null : result;
}

bool _detachedSpanHasTiming(
  String sentenceId,
  int start,
  int endExclusive,
  Map<String, WordTiming> timingByRef,
) {
  for (var index = start; index < endExclusive; index++) {
    if (timingByRef[_detachedRefKey(sentenceId, index)] != null) return true;
  }
  return false;
}

({Duration start, Duration end, Set<String> sources})? _detachedWindow(
  List<WordTiming>? timings,
  int startToken,
  int endToken,
) {
  if (timings == null) return null;
  Duration? start;
  Duration? end;
  final sources = <String>{};
  for (final timing in timings) {
    if (timing.tokenIndex < startToken || timing.tokenIndex > endToken) {
      continue;
    }
    if (start == null || timing.start < start) start = timing.start;
    if (end == null || timing.end > end) end = timing.end;
    sources.add(timing.source);
  }
  if (start == null || end == null || end <= start) return null;
  return (start: start, end: end, sources: sources);
}

String _detachedJoinTokens(Map<int, SubtitleToken> tokens, int start, int end) {
  final values = <String>[];
  for (var index = start; index <= end; index++) {
    final token = tokens[index];
    if (token == null) return '';
    values.add(token.text);
  }
  return values.join().trim();
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

Map<String, dynamic>? _decodeStrict(List<int>? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
