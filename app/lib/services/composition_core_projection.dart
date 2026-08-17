/// Projects Core-owned candidate analysis resources of an adopted package
/// onto the composition enhancement shapes the workbench renders.
///
/// Core is now the single authority for package sentence identity: the
/// `subtitle_text_track` is read back through `mediaSubtitles` as a real
/// subtitle track, and the five analysis resources are read back through that
/// track's LLTimeline export with every `sentence_id` already re-keyed to the
/// track's global sentence ids. This module therefore performs no id
/// remapping — it only selects the package's candidate resources and converts
/// their already-inclusive Core spans into the App's display shapes.
///
/// The wire map is parsed here, at the service boundary, rather than growing
/// the display-oriented `LLTimelineDocument` model with every candidate
/// family. The rules mirror the retired package-payload projection:
///
/// * spans are taken from Core's inclusive token indices — never guessed;
/// * a chunk no word timing covers is dropped rather than given invented
///   boundaries;
/// * a missing, malformed, or out-of-range item drops that item alone.
library;

import '../models/composition.dart';
import '../models/timeline.dart';

const _packageCandidateSource = 'package:subtitle_text_track';
const _packageGeneratorId = 'listen-resource-package';
const _acousticCueArtifactKind = 'rhythm_word_acoustic_cues';

/// Projects the package candidates exported by Core for [track] into the
/// enhancement maps consumed by `ResolvedComposition`.
///
/// When Core has not landed candidates for a family — a package that carried
/// no such resource, or an older adoption from before the landing existed —
/// that family contributes an empty map and nothing else is affected.
CompositionResourceProjection projectCompositionResourcesFromCore({
  required SubtitleTrack track,
  required Map<String, dynamic> documentJson,
}) {
  final tokensBySentence = _sentenceTokens(track);
  final wordTimeline = _selectPackageResource(
    _decodeList(documentJson['word_timelines'], WordTimeline.fromJson),
    isPackage: _isPackageWordTimeline,
  );
  final senseGroupAnalysis = _selectPackageResource(
    _decodeList(
      documentJson['sense_group_analyses'],
      SenseGroupAnalysis.fromJson,
    ),
    isPackage: _isPackageSenseGroupAnalysis,
  );
  final prosody = _decodeList(
    documentJson['prosody_analyses'],
    (json) => _parseProsody(json),
  );
  final prosodyAnalysis = _selectPackageResource(
    prosody,
    isPackage: _isPackageProsodyAnalysis,
  );
  final phoneTimelines =
      _decodeList(documentJson['phone_timelines'], PhoneTimeline.fromJson)
          .where(_isPackagePhoneTimeline)
          .where((timeline) => timeline.status != 'archived')
          .toList(growable: false);
  final artifacts = _decodeList(
    documentJson['artifacts'],
    LLTimelineArtifact.fromJson,
  );

  final timingsBySentence = _wordTimingsBySentence(wordTimeline?.words);

  return CompositionResourceProjection(
    timingsBySentence: timingsBySentence,
    senseGroupsBySentence: _senseGroupsBySentence(senseGroupAnalysis),
    chunkPartitionsBySentence: _chunkPartitionsBySentence(
      prosodyAnalysis,
      timingsBySentence,
      tokensBySentence,
    ),
    acousticsBySentence: _acousticsBySentence(artifacts, wordTimeline?.id),
    prosodyAnchorsBySentence: _prosodyAnchorsBySentence(prosodyAnalysis),
    phonesBySentence: _phonesBySentence(phoneTimelines),
  );
}

/// The wire facts of one Core `prosody_analysis` resource, including its
/// anchors. The display-oriented model keeps only the chunk projection, so
/// the anchor list is parsed here where the composition surface consumes it.
final class _ProsodyAnalysisView {
  const _ProsodyAnalysisView({
    required this.id,
    required this.algorithm,
    required this.status,
    required this.chunks,
    required this.anchors,
  });

  final String id;
  final String algorithm;
  final String status;
  final List<ProsodicChunk> chunks;
  final List<CompositionProsodyAnchor> anchors;
}

_ProsodyAnalysisView _parseProsody(Map<String, dynamic> json) {
  final chunks = _decodeList(json['chunks'], ProsodicChunk.fromJson);
  final anchors = <CompositionProsodyAnchor>[];
  final anchorValues = json['anchors'];
  if (anchorValues is List) {
    for (final value in anchorValues) {
      if (value is! Map) continue;
      final anchor = Map<String, dynamic>.from(value);
      final wordRef = anchor['word_ref'];
      if (wordRef is! Map) continue;
      final sentenceId = wordRef['sentence_id'];
      final tokenIndex = wordRef['token_index'];
      final confidence = anchor['confidence'];
      if (sentenceId is! String ||
          tokenIndex is! int ||
          tokenIndex < 0 ||
          confidence is! num) {
        continue;
      }
      anchors.add(
        CompositionProsodyAnchor(
          sentenceId: sentenceId,
          tokenIndex: tokenIndex,
          lexicalStress: anchor['lexical_stress'] as String?,
          realizedProminence: (anchor['realized_prominence'] as num?)
              ?.toDouble(),
          utteranceRole: anchor['utterance_role'] as String?,
          evidence: ((anchor['evidence'] as List<dynamic>?) ?? const [])
              .whereType<String>()
              .toList(growable: false),
          confidence: confidence.toDouble(),
          syllableIndex: anchor['syllable_index'] as int?,
        ),
      );
    }
  }
  return _ProsodyAnalysisView(
    id: json['id'] as String,
    algorithm: json['algorithm'] as String? ?? '',
    status: json['status'] as String? ?? 'candidate',
    chunks: chunks,
    anchors: anchors,
  );
}

List<T> _decodeList<T>(Object? value, T Function(Map<String, dynamic>) decode) {
  if (value is! List) return const [];
  final result = <T>[];
  for (final item in value) {
    if (item is! Map) continue;
    try {
      result.add(decode(Map<String, dynamic>.from(item)));
    } on Object {
      // A malformed optional analysis item costs only itself.
    }
  }
  return List.unmodifiable(result);
}

/// Sentence id → token texts, indexed exactly as the subtitle track indexes
/// them. Whitespace and punctuation keep their slots because every analysis
/// resource addresses them by token index.
Map<String, List<String>> _sentenceTokens(SubtitleTrack track) {
  final result = <String, List<String>>{};
  for (final cue in track.cues) {
    final byIndex = <int, String>{};
    for (final token in cue.tokens) {
      if (token.index < 0) continue;
      byIndex[token.index] = token.text;
    }
    if (byIndex.isEmpty) continue;
    var highest = -1;
    for (final index in byIndex.keys) {
      if (index > highest) highest = index;
    }
    result[cue.id] = List<String>.generate(
      highest + 1,
      (index) => byIndex[index] ?? '',
      growable: false,
    );
  }
  return Map.unmodifiable(result);
}

bool _isPackageWordTimeline(WordTimeline timeline) =>
    timeline.metricsJson.fields['exchange_source'] == _packageCandidateSource;

bool _isPackagePhoneTimeline(PhoneTimeline timeline) =>
    timeline.metricsJson.fields['exchange_source'] == _packageCandidateSource;

bool _isPackageSenseGroupAnalysis(SenseGroupAnalysis analysis) =>
    analysis.algorithm == _packageGeneratorId ||
    analysis.metricsJson.fields['exchange_source'] == _packageCandidateSource;

bool _isPackageProsodyAnalysis(_ProsodyAnalysisView analysis) =>
    analysis.algorithm == _packageGeneratorId;

/// Prefers the package's active resource, then its candidate; a non-package
/// resource is only used when Core exposes no package resource at all for the
/// family (for example an older adopted edition).
T? _selectPackageResource<T extends Object>(
  List<T> values, {
  required bool Function(T) isPackage,
}) {
  final usable = values
      .where((value) => _statusOf(value) != 'archived')
      .toList(growable: false);
  final packages = usable.where(isPackage).toList(growable: false);
  final pool = packages.isNotEmpty ? packages : usable;
  for (final value in pool) {
    if (_statusOf(value) == 'active') return value;
  }
  return pool.isEmpty ? null : pool.first;
}

String _statusOf(Object value) => switch (value) {
  WordTimeline timeline => timeline.status,
  PhoneTimeline timeline => timeline.status,
  SenseGroupAnalysis analysis => analysis.status,
  _ProsodyAnalysisView analysis => analysis.status,
  _ => '',
};

Map<String, List<WordTiming>> _wordTimingsBySentence(List<WordTiming>? words) {
  if (words == null || words.isEmpty) return const {};
  final result = <String, List<WordTiming>>{};
  for (final word in words) {
    result.putIfAbsent(word.sentenceId, () => <WordTiming>[]).add(word);
  }
  for (final values in result.values) {
    values.sort((a, b) => a.tokenIndex.compareTo(b.tokenIndex));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<WordTiming>.unmodifiable(entry.value),
  });
}

Map<String, List<SenseGroup>> _senseGroupsBySentence(
  SenseGroupAnalysis? analysis,
) {
  if (analysis == null) return const {};
  final result = <String, List<SenseGroup>>{};
  for (final group in analysis.groups) {
    result.putIfAbsent(group.sentenceId, () => <SenseGroup>[]).add(group);
  }
  for (final values in result.values) {
    values.sort((a, b) => a.groupIndex.compareTo(b.groupIndex));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<SenseGroup>.unmodifiable(entry.value),
  });
}

Map<String, SentenceChunkPartition> _chunkPartitionsBySentence(
  _ProsodyAnalysisView? analysis,
  Map<String, List<WordTiming>> timingsBySentence,
  Map<String, List<String>> tokensBySentence,
) {
  if (analysis == null) return const {};
  final bySentence = <String, List<DisplayChunk>>{};
  final sourcesBySentence = <String, Set<String>>{};
  for (final chunk in analysis.chunks) {
    final tokens = tokensBySentence[chunk.sentenceId];
    if (tokens == null ||
        chunk.startTokenIndex < 0 ||
        chunk.startTokenIndex > chunk.endTokenIndex ||
        chunk.endTokenIndex >= tokens.length) {
      continue;
    }
    final window = _windowFor(
      timingsBySentence[chunk.sentenceId],
      chunk.startTokenIndex,
      chunk.endTokenIndex,
    );
    if (window == null) continue;
    bySentence
        .putIfAbsent(chunk.sentenceId, () => <DisplayChunk>[])
        .add(
          DisplayChunk(
            index: chunk.chunkIndex,
            tokenStart: chunk.startTokenIndex,
            tokenEnd: chunk.endTokenIndex,
            text: _joinTokens(
              tokens,
              chunk.startTokenIndex,
              chunk.endTokenIndex,
            ),
            start: window.start,
            end: window.end,
          ),
        );
    sourcesBySentence
        .putIfAbsent(chunk.sentenceId, () => <String>{})
        .addAll(window.sources);
  }
  final result = <String, SentenceChunkPartition>{};
  for (final entry in bySentence.entries) {
    final ordered = entry.value..sort((a, b) => a.index.compareTo(b.index));
    final sources = sourcesBySentence[entry.key] ?? const <String>{};
    result[entry.key] = SentenceChunkPartition(
      sentenceId: entry.key,
      chunks: List<DisplayChunk>.unmodifiable(ordered),
      partitionerId: 'composition:prosody_analysis',
      partitionerVersion: 'listen.resource.prosody-analysis.v1',
      timingQuality: sources.length == 1 ? sources.single : 'mixed',
    );
  }
  return Map.unmodifiable(result);
}

Map<String, List<CompositionWordAcoustics>> _acousticsBySentence(
  List<LLTimelineArtifact> artifacts,
  String? wordTimelineId,
) {
  if (wordTimelineId == null) return const {};
  final result = <String, List<CompositionWordAcoustics>>{};
  for (final artifact in artifacts) {
    if (artifact.kind != _acousticCueArtifactKind) continue;
    if (artifact.payload['timeline_id'] != wordTimelineId) continue;
    final cues = artifact.payload['cues'];
    if (cues is! List) continue;
    for (final value in cues) {
      if (value is! Map) continue;
      final cue = Map<String, dynamic>.from(value);
      final sentenceId = cue['sentence_id'];
      final tokenIndex = cue['token_index'];
      final energy = _numericMap(cue['energy']);
      final pitch = _numericMap(cue['pitch']);
      final duration = _numericMap(cue['duration']);
      final voicedFrameRatio = cue['voiced_frame_ratio'];
      if (sentenceId is! String || tokenIndex is! int || tokenIndex < 0) {
        continue;
      }
      if (energy == null || pitch == null || duration == null) continue;
      if (voicedFrameRatio is! num) continue;
      result
          .putIfAbsent(sentenceId, () => <CompositionWordAcoustics>[])
          .add(
            CompositionWordAcoustics(
              sentenceId: sentenceId,
              tokenIndex: tokenIndex,
              energy: energy,
              pitch: pitch,
              duration: duration,
              voicedFrameRatio: voicedFrameRatio.toDouble(),
            ),
          );
    }
  }
  for (final values in result.values) {
    values.sort((a, b) => a.tokenIndex.compareTo(b.tokenIndex));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<CompositionWordAcoustics>.unmodifiable(entry.value),
  });
}

Map<String, List<CompositionProsodyAnchor>> _prosodyAnchorsBySentence(
  _ProsodyAnalysisView? analysis,
) {
  if (analysis == null) return const {};
  final result = <String, List<CompositionProsodyAnchor>>{};
  for (final anchor in analysis.anchors) {
    result
        .putIfAbsent(anchor.sentenceId, () => <CompositionProsodyAnchor>[])
        .add(anchor);
  }
  for (final values in result.values) {
    values.sort((a, b) => a.tokenIndex.compareTo(b.tokenIndex));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<CompositionProsodyAnchor>.unmodifiable(entry.value),
  });
}

Map<String, List<DetectedPhone>> _phonesBySentence(
  List<PhoneTimeline> timelines,
) {
  final result = <String, List<DetectedPhone>>{};
  for (final timeline in timelines) {
    final sentenceId = timeline.sentenceId;
    if (sentenceId == null) continue;
    for (final phone in timeline.phones) {
      if (phone.tokenIndex == null) continue;
      result.putIfAbsent(sentenceId, () => <DetectedPhone>[]).add(phone);
    }
  }
  for (final values in result.values) {
    values.sort((a, b) => a.start.compareTo(b.start));
  }
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<DetectedPhone>.unmodifiable(entry.value),
  });
}

/// The media window covering an inclusive token span, plus the timing sources
/// that reported it. Null when no timing falls inside the span.
({Duration start, Duration end, Set<String> sources})? _windowFor(
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
  if (start == null || end == null) return null;
  return (start: start, end: end, sources: sources);
}

String _joinTokens(List<String> tokens, int start, int end) {
  if (start >= tokens.length) return '';
  final last = end < tokens.length ? end : tokens.length - 1;
  return tokens.sublist(start, last + 1).join().trim();
}

Map<String, num>? _numericMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, num>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! num) return null;
    result[entry.key as String] = entry.value as num;
  }
  return result;
}
