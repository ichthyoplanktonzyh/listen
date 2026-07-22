part of '../timeline.dart';

// LLTimeline document, metadata, artifacts, detected phones
// Split out of timeline.dart (mechanical decomposition).

class PhoneTimelineSummary {
  const PhoneTimelineSummary({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.providerId,
    required this.providerVersion,
    required this.phoneSet,
    required this.precision,
    required this.createdBy,
    required this.status,
    required this.phoneCount,
    required this.findingCount,
    required this.canActivate,
    required this.canArchive,
    required this.canDelete,
    this.sentenceId,
    this.parentWordTimelineId,
    this.parentPhoneticAnalysisId,
    this.modelId,
    this.modelRevision,
    this.start,
    this.end,
    this.averageConfidence,
  });

  factory PhoneTimelineSummary.fromJson(Map<String, dynamic> json) =>
      PhoneTimelineSummary(
        id: json['id'] as String,
        trackId: json['track_id'] as String,
        mediaId: json['media_id'] as String,
        sentenceId: json['sentence_id'] as String?,
        parentWordTimelineId: json['parent_word_timeline_id'] as String?,
        parentPhoneticAnalysisId:
            json['parent_phonetic_analysis_id'] as String?,
        providerId: json['provider_id'] as String,
        providerVersion: json['provider_version'] as String,
        modelId: json['model_id'] as String?,
        modelRevision: json['model_revision'] as String?,
        phoneSet: json['phone_set'] as String,
        precision: json['precision'] as String,
        createdBy: json['created_by'] as String,
        status: json['status'] as String,
        phoneCount: json['phone_count'] as int,
        findingCount: json['finding_count'] as int,
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
  final String? sentenceId;
  final String? parentWordTimelineId;
  final String? parentPhoneticAnalysisId;
  final String providerId;
  final String providerVersion;
  final String? modelId;
  final String? modelRevision;
  final String phoneSet;
  final String precision;
  final String createdBy;
  final String status;
  final int phoneCount;
  final int findingCount;
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
    required this.activePhoneTimelineId,
    required this.activeChunkTimelineId,
    required this.rhythmFrames,
    required this.artifacts,
  });

  factory LLTimelineDocument.fromJson(Map<String, dynamic> json) =>
      LLTimelineDocument(
        schema: json['schema'] as String,
        metadata: LLTimelineMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>,
        ),
        activeWordTimelineId: json['active_word_timeline_id'] as String?,
        activePhoneTimelineId: json['active_phone_timeline_id'] as String?,
        activeChunkTimelineId: json['active_chunk_timeline_id'] as String?,
        rhythmFrames: ((json['rhythm_frames'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  LLTimelineRhythmFrame.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
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
  final String? activePhoneTimelineId;
  final String? activeChunkTimelineId;
  final List<LLTimelineRhythmFrame> rhythmFrames;
  final List<LLTimelineArtifact> artifacts;

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'metadata': metadata.toJson(),
    'active_word_timeline_id': activeWordTimelineId,
    'active_phone_timeline_id': activePhoneTimelineId,
    'active_chunk_timeline_id': activeChunkTimelineId,
    'rhythm_frames': rhythmFrames
        .map((value) => value.toJson())
        .toList(growable: false),
    'artifacts': artifacts
        .map((value) => value.toJson())
        .toList(growable: false),
  };

  bool get importedResource =>
      metadata.trackSource == 'lltimeline-json-v1' ||
      artifacts.isNotEmpty ||
      rhythmFrames.isNotEmpty ||
      activeWordTimelineId != null ||
      activePhoneTimelineId != null ||
      activeChunkTimelineId != null;

  RhythmFrame? rhythmFrameForSentence(String sentenceId) {
    for (final frame in rhythmFrames) {
      if (frame.sentenceId == sentenceId && frame.isActive) {
        return frame.rhythmFrame;
      }
    }
    for (final frame in rhythmFrames) {
      if (frame.sentenceId == sentenceId) return frame.rhythmFrame;
    }
    return null;
  }
}

class LLTimelineRhythmFrame {
  const LLTimelineRhythmFrame({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.sentenceId,
    required this.providerId,
    required this.providerVersion,
    required this.status,
    required this.metricsJson,
    required this.rhythmFrame,
    required this.createdAt,
    required this.updatedAt,
    this.parentWordTimelineId,
  });

  factory LLTimelineRhythmFrame.fromJson(Map<String, dynamic> json) =>
      LLTimelineRhythmFrame(
        id: json['id'] as String,
        trackId: json['track_id'] as String,
        mediaId: json['media_id'] as String,
        sentenceId: json['sentence_id'] as String,
        parentWordTimelineId: json['parent_word_timeline_id'] as String?,
        providerId: json['provider_id'] as String,
        providerVersion: json['provider_version'] as String,
        status: json['status'] as String,
        metricsJson: TimelineMetrics.fromJson(json['metrics_json']),
        rhythmFrame: RhythmFrame.fromJson(
          json['rhythm_frame'] as Map<String, dynamic>,
        ),
        createdAt: Duration(milliseconds: json['created_at_ms'] as int),
        updatedAt: Duration(milliseconds: json['updated_at_ms'] as int),
      );

  final String id;
  final String trackId;
  final String mediaId;
  final String sentenceId;
  final String? parentWordTimelineId;
  final String providerId;
  final String providerVersion;
  final String status;
  final TimelineMetrics metricsJson;
  final RhythmFrame rhythmFrame;
  final Duration createdAt;
  final Duration updatedAt;

  bool get isActive => status == 'active';

  Map<String, dynamic> toJson() => {
    'id': id,
    'track_id': trackId,
    'media_id': mediaId,
    'sentence_id': sentenceId,
    'parent_word_timeline_id': parentWordTimelineId,
    'provider_id': providerId,
    'provider_version': providerVersion,
    'status': status,
    'metrics_json': metricsJson.toJson(),
    'rhythm_frame': rhythmFrame.toJson(),
    'created_at_ms': createdAt.inMilliseconds,
    'updated_at_ms': updatedAt.inMilliseconds,
  };
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
      extra: Map<String, dynamic>.from((json['extra'] as Map?) ?? const {}),
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

  Map<String, dynamic> toJson() => {
    'created_at_ms': createdAt.inMilliseconds,
    'generator': {
      'id': generatorId,
      'version': generatorVersion,
      'mode': generatorMode,
    },
    'media': {'title': mediaTitle, 'fingerprint': mediaFingerprint},
    'language': language,
    'human_reviewed': humanReviewed,
    'extra': extra,
  };
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

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'provider_id': providerId,
    'provider_version': providerVersion,
    'payload': payload,
  };
}

Duration? _durationFromNullableMs(int? value) =>
    value == null ? null : Duration(milliseconds: value);

class DetectedPhone {
  const DetectedPhone({
    required this.symbol,
    required this.displayIpa,
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
    displayIpa: (json['display_ipa'] as String?) ?? json['symbol'] as String,
    phoneSet: json['phone_set'] as String,
    start: Duration(milliseconds: json['start_ms'] as int),
    end: Duration(milliseconds: json['end_ms'] as int),
    confidence: (json['confidence'] as num?)?.toDouble(),
    tokenIndex: json['token_index'] as int?,
    provider: json['provider_id'] as String,
    modelRevision: json['model_revision'] as String,
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'display_ipa': displayIpa,
    'phone_set': phoneSet,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'confidence': confidence,
    'token_index': tokenIndex,
    'provider_id': provider,
    'model_revision': modelRevision,
  };

  final String symbol;
  final String displayIpa;
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

List<DetectedPhone> synthesizePhonesFromDictionary(
  Map<String, dynamic> pronunciation,
  List<WordTiming> wordTimings,
) {
  final words = pronunciation['words'] as List<dynamic>? ?? const [];
  if (words.isEmpty || wordTimings.isEmpty) return const [];

  final timingByToken = <int, WordTiming>{};
  for (final wt in wordTimings) {
    timingByToken[wt.tokenIndex] = wt;
  }

  final result = <DetectedPhone>[];
  for (final raw in words) {
    final word = raw as Map<String, dynamic>;
    final tokenIndex = word['token_index'] as int;
    final timing = timingByToken[tokenIndex];
    if (timing == null) continue;

    final variants = word['variants'] as List<dynamic>? ?? const [];
    if (variants.isEmpty) continue;
    final phonemes =
        (variants[0] as Map<String, dynamic>)['phonemes'] as List<dynamic>? ??
        const [];
    if (phonemes.isEmpty) continue;

    final startMs = timing.start.inMilliseconds;
    final endMs = timing.end.inMilliseconds;
    final durationMs = endMs - startMs;
    final perPhonemeMs = durationMs / phonemes.length;

    for (var i = 0; i < phonemes.length; i++) {
      final p = phonemes[i] as Map<String, dynamic>;
      final pStart = startMs + (perPhonemeMs * i).round();
      final pEnd = startMs + (perPhonemeMs * (i + 1)).round();
      result.add(
        DetectedPhone(
          symbol: p['symbol'] as String,
          displayIpa: (p['display_ipa'] as String?) ?? p['symbol'] as String,
          phoneSet: (p['phoneme_set'] as String?) ?? 'ipa',
          start: Duration(milliseconds: pStart),
          end: Duration(milliseconds: pEnd),
          confidence: null,
          tokenIndex: tokenIndex,
          provider: 'dictionary',
          modelRevision: '',
        ),
      );
    }
  }
  return result;
}

List<DetectedPhone> buildLearningPhones({
  required Map<String, dynamic>? pronunciation,
  required List<WordTiming>? wordTimings,
  required List<DetectedPhone> observedPhones,
  bool allowObservedOnlyFallback = true,
}) {
  final expectedPhones = pronunciation == null || wordTimings == null
      ? const <DetectedPhone>[]
      : synthesizePhonesFromDictionary(pronunciation, wordTimings);
  if (expectedPhones.isEmpty) {
    return allowObservedOnlyFallback ? observedPhones : const [];
  }
  if (observedPhones.isEmpty) return expectedPhones;

  final observedByToken = <int, List<DetectedPhone>>{};
  for (final observed in observedPhones) {
    final tokenIndex = observed.tokenIndex;
    if (tokenIndex == null) continue;
    observedByToken.putIfAbsent(tokenIndex, () => []).add(observed);
  }
  final consumedByToken = <int, int>{};

  return [
    for (final expected in expectedPhones)
      _learningPhoneFromExpected(
        expected,
        _alignedObservedPhone(
          expected,
          observedByToken,
          consumedByToken,
          observedPhones,
        ),
      ),
  ];
}

DetectedPhone _learningPhoneFromExpected(
  DetectedPhone expected,
  DetectedPhone? observed,
) {
  if (observed == null) return expected;
  return DetectedPhone(
    symbol: expected.symbol,
    displayIpa: expected.displayIpa,
    phoneSet: expected.phoneSet,
    start: observed.start,
    end: observed.end,
    confidence: observed.confidence,
    tokenIndex: expected.tokenIndex,
    provider: '${expected.provider}+${observed.provider}-timing',
    modelRevision: observed.modelRevision,
  );
}

DetectedPhone? _alignedObservedPhone(
  DetectedPhone expected,
  Map<int, List<DetectedPhone>> observedByToken,
  Map<int, int> consumedByToken,
  List<DetectedPhone> observedPhones,
) {
  final tokenIndex = expected.tokenIndex;
  if (tokenIndex != null) {
    final candidates = observedByToken[tokenIndex];
    if (candidates != null && candidates.isNotEmpty) {
      final next = consumedByToken[tokenIndex] ?? 0;
      if (next < candidates.length) {
        consumedByToken[tokenIndex] = next + 1;
        return candidates[next];
      }
      return null;
    }
  }

  var bestOverlap = Duration.zero;
  DetectedPhone? best;
  for (final observed in observedPhones) {
    final overlap = _durationOverlap(
      expected.start,
      expected.end,
      observed.start,
      observed.end,
    );
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      best = observed;
    }
  }
  return bestOverlap > Duration.zero ? best : null;
}

List<DetectedPhone> buildSoundPatternPhones(SoundAnalysis? soundAnalysis) {
  if (soundAnalysis == null || soundAnalysis.learningPhones.isEmpty) {
    return const [];
  }
  final modelRevision =
      soundAnalysis.modelRevision ?? soundAnalysis.providerVersion;
  return soundAnalysis.learningPhones
      .map(
        (phone) => phone.toDetectedPhone(
          provider: soundAnalysis.providerId,
          modelRevision: modelRevision,
        ),
      )
      .toList(growable: false);
}

Duration _durationOverlap(
  Duration aStart,
  Duration aEnd,
  Duration bStart,
  Duration bEnd,
) {
  final start = aStart > bStart ? aStart : bStart;
  final end = aEnd < bEnd ? aEnd : bEnd;
  return end > start ? end - start : Duration.zero;
}

List<PhonemeRibbonFinding> buildPhonemeRibbonFindings({
  required List<Map<String, dynamic>> rawFindings,
  required List<DetectedPhone> phones,
  SoundAnalysis? soundAnalysis,
}) {
  if (phones.isEmpty) return const [];

  final observedToLearning = <int, int>{};
  if (soundAnalysis != null) {
    for (var i = 0; i < soundAnalysis.learningPhones.length; i++) {
      final observedIndex = soundAnalysis.learningPhones[i].observedPhoneIndex;
      if (observedIndex != null) observedToLearning[observedIndex] = i;
    }
  }

  final result = <PhonemeRibbonFinding>[];
  if (soundAnalysis != null) {
    for (final explanation in soundAnalysis.connectedSpeech) {
      final start = explanation.phoneStart;
      final end = explanation.phoneEnd;
      if (start == null || end == null || start > end) continue;
      if (start < 0 || end >= phones.length) continue;
      result.add(
        PhonemeRibbonFinding(
          phoneStart: start,
          phoneEnd: end,
          findingType: explanation.family,
          status: _connectedSpeechStatus(explanation.status),
          confidence: explanation.confidence.clamp(0.0, 1.0).toDouble(),
          evidence: explanation.evidence,
          learnerLabelOverride: explanation.label,
          learnerHint: explanation.hint,
        ),
      );
    }
  }
  for (final finding in rawFindings) {
    final rawStart = finding['aligned_phone_start'] as int?;
    final rawEnd = finding['aligned_phone_end'] as int?;
    if (rawStart == null || rawEnd == null || rawStart > rawEnd) continue;

    final displayIndexes = <int>[];
    for (
      var observedIndex = rawStart;
      observedIndex <= rawEnd;
      observedIndex++
    ) {
      final displayIndex = soundAnalysis == null
          ? observedIndex
          : observedToLearning[observedIndex];
      if (displayIndex != null &&
          displayIndex >= 0 &&
          displayIndex < phones.length) {
        displayIndexes.add(displayIndex);
      }
    }
    if (displayIndexes.isEmpty && soundAnalysis != null) {
      final nearest = _nearestLearningPhoneIndex(
        rawStart,
        rawEnd,
        observedToLearning,
        phones.length,
      );
      if (nearest != null) displayIndexes.add(nearest);
    }
    if (displayIndexes.isEmpty) continue;
    displayIndexes.sort();

    result.add(
      PhonemeRibbonFinding(
        phoneStart: displayIndexes.first,
        phoneEnd: displayIndexes.last,
        findingType: finding['finding_type'] as String? ?? 'audio_evidence',
        status: finding['status'] as String? ?? 'uncertain',
        confidence: (finding['confidence'] as num?)?.toDouble() ?? 0.0,
        evidence: finding['evidence'] as String? ?? '',
      ),
    );
  }
  return result;
}

String _connectedSpeechStatus(String status) {
  switch (status) {
    case 'detected_in_audio':
      return 'detected_in_audio';
    case 'supported_by_audio':
      return 'supported_by_alignment';
    case 'possible_by_rule':
      return 'uncertain';
    default:
      return status;
  }
}

int? _nearestLearningPhoneIndex(
  int observedStart,
  int observedEnd,
  Map<int, int> observedToLearning,
  int phoneCount,
) {
  int? bestIndex;
  var bestDistance = 1 << 30;
  for (final entry in observedToLearning.entries) {
    final distance = entry.key < observedStart
        ? observedStart - entry.key
        : entry.key > observedEnd
        ? entry.key - observedEnd
        : 0;
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = entry.value;
    }
  }
  if (bestIndex == null || bestIndex < 0 || bestIndex >= phoneCount) {
    return null;
  }
  return bestIndex;
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
