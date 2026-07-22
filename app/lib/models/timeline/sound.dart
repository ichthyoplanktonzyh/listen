part of '../timeline.dart';

// Phone timeline + sound analysis primitives
// Split out of timeline.dart (mechanical decomposition).

class PhoneTimeline {
  const PhoneTimeline({
    required this.id,
    required this.trackId,
    required this.mediaId,
    required this.providerId,
    required this.providerVersion,
    required this.phoneSet,
    required this.precision,
    required this.createdBy,
    required this.status,
    required this.metricsJson,
    required this.phones,
    required this.alignments,
    required this.findings,
    required this.createdAt,
    required this.updatedAt,
    this.soundAnalysis,
    this.sentenceId,
    this.parentWordTimelineId,
    this.parentPhoneticAnalysisId,
    this.modelId,
    this.modelRevision,
  });

  factory PhoneTimeline.fromJson(Map<String, dynamic> json) => PhoneTimeline(
    id: json['id'] as String,
    trackId: json['track_id'] as String,
    mediaId: json['media_id'] as String,
    sentenceId: json['sentence_id'] as String?,
    parentWordTimelineId: json['parent_word_timeline_id'] as String?,
    parentPhoneticAnalysisId: json['parent_phonetic_analysis_id'] as String?,
    providerId: json['provider_id'] as String,
    providerVersion: json['provider_version'] as String,
    modelId: json['model_id'] as String?,
    modelRevision: json['model_revision'] as String?,
    phoneSet: json['phone_set'] as String,
    precision: json['precision'] as String,
    createdBy: json['created_by'] as String,
    status: json['status'] as String,
    metricsJson: TimelineMetrics.fromJson(json['metrics_json']),
    phones: ((json['phones'] as List<dynamic>?) ?? const [])
        .map((value) => DetectedPhone.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    alignments: ((json['alignments'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .toList(growable: false),
    findings: ((json['findings'] as List<dynamic>?) ?? const [])
        .cast<Map<String, dynamic>>()
        .toList(growable: false),
    soundAnalysis: json['sound_analysis'] is Map
        ? SoundAnalysis.fromJson(
            Map<String, dynamic>.from(json['sound_analysis'] as Map),
          )
        : null,
    createdAt: Duration(milliseconds: json['created_at_ms'] as int),
    updatedAt: Duration(milliseconds: json['updated_at_ms'] as int),
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
  final TimelineMetrics metricsJson;
  final List<DetectedPhone> phones;
  final List<Map<String, dynamic>> alignments;
  final List<Map<String, dynamic>> findings;
  final SoundAnalysis? soundAnalysis;
  final Duration createdAt;
  final Duration updatedAt;

  bool get isActive => status == 'active';

  Map<String, dynamic> toSoundPatternJson() => {
    'id': id,
    'sentence_id': sentenceId,
    'provider_id': providerId,
    'provider_version': providerVersion,
    'model_revision': modelRevision ?? providerVersion,
    'phone_set': phoneSet,
    'precision': precision,
    'metrics_json': metricsJson.toJson(),
    'detected_phones': phones.map((value) => value.toJson()).toList(),
    'alignments': alignments,
    'findings': findings,
    if (soundAnalysis != null) 'sound_analysis': soundAnalysis!.toJson(),
  };
}

class SoundAnalysis {
  const SoundAnalysis({
    required this.providerId,
    required this.providerVersion,
    required this.phoneSet,
    required this.generatedFrom,
    required this.learningPhones,
    required this.connectedSpeech,
    required this.syllables,
    required this.prosodicPhrases,
    this.modelRevision,
    this.rhythmFrame,
  });

  factory SoundAnalysis.fromJson(Map<String, dynamic> json) => SoundAnalysis(
    providerId: json['provider_id'] as String,
    providerVersion: json['provider_version'] as String,
    modelRevision: json['model_revision'] as String?,
    phoneSet: json['phone_set'] as String,
    generatedFrom: json['generated_from'] as String,
    learningPhones: ((json['learning_phones'] as List<dynamic>?) ?? const [])
        .map(
          (value) => SoundLearningPhone.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    connectedSpeech: ((json['connected_speech'] as List<dynamic>?) ?? const [])
        .map(
          (value) => ConnectedSpeechExplanation.fromJson(
            value as Map<String, dynamic>,
          ),
        )
        .toList(growable: false),
    syllables: ((json['syllables'] as List<dynamic>?) ?? const [])
        .map((value) => SoundSyllable.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    prosodicPhrases: ((json['prosodic_phrases'] as List<dynamic>?) ?? const [])
        .map(
          (value) =>
              SoundProsodicPhrase.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    rhythmFrame: json['rhythm_frame'] is Map
        ? RhythmFrame.fromJson(
            Map<String, dynamic>.from(json['rhythm_frame'] as Map),
          )
        : null,
  );

  final String providerId;
  final String providerVersion;
  final String? modelRevision;
  final String phoneSet;
  final String generatedFrom;
  final List<SoundLearningPhone> learningPhones;
  final List<ConnectedSpeechExplanation> connectedSpeech;
  final List<SoundSyllable> syllables;
  final List<SoundProsodicPhrase> prosodicPhrases;
  final RhythmFrame? rhythmFrame;

  Map<String, dynamic> toJson() => {
    'provider_id': providerId,
    'provider_version': providerVersion,
    'model_revision': modelRevision,
    'phone_set': phoneSet,
    'generated_from': generatedFrom,
    'learning_phones': learningPhones.map((value) => value.toJson()).toList(),
    'connected_speech': connectedSpeech.map((value) => value.toJson()).toList(),
    'syllables': syllables.map((value) => value.toJson()).toList(),
    'prosodic_phrases': prosodicPhrases.map((value) => value.toJson()).toList(),
    if (rhythmFrame != null) 'rhythm_frame': rhythmFrame!.toJson(),
  };
}

class SoundLearningPhone {
  const SoundLearningPhone({
    required this.symbol,
    required this.displayIpa,
    required this.phoneSet,
    required this.start,
    required this.end,
    required this.evidence,
    this.confidence,
    this.tokenIndex,
    this.stress,
    this.observedPhoneIndex,
    this.observedSymbol,
  });

  factory SoundLearningPhone.fromJson(Map<String, dynamic> json) =>
      SoundLearningPhone(
        symbol: json['symbol'] as String,
        displayIpa:
            (json['display_ipa'] as String?) ?? json['symbol'] as String,
        phoneSet: json['phone_set'] as String,
        start: Duration(milliseconds: json['start_ms'] as int),
        end: Duration(milliseconds: json['end_ms'] as int),
        confidence: (json['confidence'] as num?)?.toDouble(),
        tokenIndex: json['token_index'] as int?,
        stress: json['stress'] as int?,
        observedPhoneIndex: json['observed_phone_index'] as int?,
        observedSymbol: json['observed_symbol'] as String?,
        evidence: json['evidence'] as String,
      );

  final String symbol;
  final String displayIpa;
  final String phoneSet;
  final Duration start;
  final Duration end;
  final double? confidence;
  final int? tokenIndex;
  final int? stress;
  final int? observedPhoneIndex;
  final String? observedSymbol;
  final String evidence;

  DetectedPhone toDetectedPhone({
    required String provider,
    required String modelRevision,
  }) => DetectedPhone(
    symbol: symbol,
    displayIpa: displayIpa,
    phoneSet: phoneSet,
    start: start,
    end: end,
    confidence: confidence,
    tokenIndex: tokenIndex,
    provider: provider,
    modelRevision: modelRevision,
  );

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'display_ipa': displayIpa,
    'phone_set': phoneSet,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'confidence': confidence,
    'token_index': tokenIndex,
    'stress': stress,
    'observed_phone_index': observedPhoneIndex,
    'observed_symbol': observedSymbol,
    'evidence': evidence,
  };
}

class ConnectedSpeechExplanation {
  const ConnectedSpeechExplanation({
    required this.family,
    required this.label,
    required this.hint,
    required this.confidence,
    required this.status,
    required this.expectedSymbols,
    required this.learningSymbols,
    required this.observedSymbols,
    required this.evidence,
    this.phoneStart,
    this.phoneEnd,
    this.tokenStart,
    this.tokenEnd,
  });

  factory ConnectedSpeechExplanation.fromJson(
    Map<String, dynamic> json,
  ) => ConnectedSpeechExplanation(
    family: json['family'] as String,
    label: json['label'] as String,
    hint: json['hint'] as String? ?? '',
    phoneStart: json['phone_start'] as int?,
    phoneEnd: json['phone_end'] as int?,
    tokenStart: json['token_start'] as int?,
    tokenEnd: json['token_end'] as int?,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    status: json['status'] as String,
    expectedSymbols: ((json['expected_symbols'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    learningSymbols: ((json['learning_symbols'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    observedSymbols: ((json['observed_symbols'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    evidence: json['evidence'] as String? ?? '',
  );

  final String family;
  final String label;
  final String hint;
  final int? phoneStart;
  final int? phoneEnd;
  final int? tokenStart;
  final int? tokenEnd;
  final double confidence;
  final String status;
  final List<String> expectedSymbols;
  final List<String> learningSymbols;
  final List<String> observedSymbols;
  final String evidence;

  Map<String, dynamic> toJson() => {
    'family': family,
    'label': label,
    'hint': hint,
    'phone_start': phoneStart,
    'phone_end': phoneEnd,
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'confidence': confidence,
    'status': status,
    'expected_symbols': expectedSymbols,
    'learning_symbols': learningSymbols,
    'observed_symbols': observedSymbols,
    'evidence': evidence,
  };
}

class SoundSyllable {
  const SoundSyllable({
    required this.phones,
    required this.onset,
    required this.nucleus,
    required this.coda,
    required this.start,
    required this.end,
    required this.stress,
  });

  factory SoundSyllable.fromJson(Map<String, dynamic> json) => SoundSyllable(
    phones: ((json['phones'] as List<dynamic>?) ?? const []).cast<int>(),
    onset: ((json['onset'] as List<dynamic>?) ?? const []).cast<int>(),
    nucleus: ((json['nucleus'] as List<dynamic>?) ?? const []).cast<int>(),
    coda: ((json['coda'] as List<dynamic>?) ?? const []).cast<int>(),
    start: Duration(milliseconds: json['start_ms'] as int),
    end: Duration(milliseconds: json['end_ms'] as int),
    stress: json['stress'] as String,
  );

  final List<int> phones;
  final List<int> onset;
  final List<int> nucleus;
  final List<int> coda;
  final Duration start;
  final Duration end;
  final String stress;

  Map<String, dynamic> toJson() => {
    'phones': phones,
    'onset': onset,
    'nucleus': nucleus,
    'coda': coda,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'stress': stress,
  };
}

class SoundProsodicPhrase {
  const SoundProsodicPhrase({
    required this.syllables,
    required this.start,
    required this.end,
    required this.boundaryEvidence,
    required this.confidence,
  });

  factory SoundProsodicPhrase.fromJson(Map<String, dynamic> json) =>
      SoundProsodicPhrase(
        syllables: ((json['syllables'] as List<dynamic>?) ?? const [])
            .cast<int>(),
        start: Duration(milliseconds: json['start_ms'] as int),
        end: Duration(milliseconds: json['end_ms'] as int),
        boundaryEvidence: json['boundary_evidence'] as String,
        confidence: (json['confidence'] as num).toDouble(),
      );

  final List<int> syllables;
  final Duration start;
  final Duration end;
  final String boundaryEvidence;
  final double confidence;

  Map<String, dynamic> toJson() => {
    'syllables': syllables,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'boundary_evidence': boundaryEvidence,
    'confidence': confidence,
  };
}
