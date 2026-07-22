part of '../types.dart';

// Word/sentence pronunciation and phonetic analysis.
// Split out of types.dart (mechanical decomposition).

class WordPronunciation {
  const WordPronunciation({
    required this.tokenIndex,
    required this.text,
    required this.normalized,
    this.variants = const [],
  });

  factory WordPronunciation.fromJson(Map<String, dynamic> json) =>
      WordPronunciation(
        tokenIndex: json['token_index'] as int? ?? 0,
        text: json['text'] as String? ?? '',
        normalized: json['normalized'] as String? ?? '',
        variants: ((json['variants'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  PronunciationVariant.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final int tokenIndex;
  final String text;
  final String normalized;
  final List<PronunciationVariant> variants;

  Map<String, dynamic> toJson() => {
    'token_index': tokenIndex,
    'text': text,
    'normalized': normalized,
    'variants': variants.map((value) => value.toJson()).toList(growable: false),
  };
}

class PronunciationVariant {
  const PronunciationVariant({
    this.phonemes = const [],
    required this.displayIpa,
    this.isFallback = false,
  });

  factory PronunciationVariant.fromJson(Map<String, dynamic> json) =>
      PronunciationVariant(
        phonemes: ((json['phonemes'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  PronunciationPhoneme.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        displayIpa: json['display_ipa'] as String? ?? '',
        isFallback: json['is_fallback'] as bool? ?? false,
      );

  final List<PronunciationPhoneme> phonemes;
  final String displayIpa;
  final bool isFallback;

  Map<String, dynamic> toJson() => {
    'phonemes': phonemes.map((value) => value.toJson()).toList(growable: false),
    'display_ipa': displayIpa,
    'is_fallback': isFallback,
  };
}

class PronunciationPhoneme {
  const PronunciationPhoneme({
    required this.symbol,
    this.phonemeSet,
    this.displayIpa,
    this.stress,
    this.syllableIndex,
    this.tokenIndex,
    this.startMs,
    this.endMs,
    this.confidence,
  });

  factory PronunciationPhoneme.fromJson(Map<String, dynamic> json) =>
      PronunciationPhoneme(
        symbol: json['symbol'] as String? ?? '',
        phonemeSet: json['phoneme_set'] as String?,
        displayIpa: json['display_ipa'] as String?,
        stress: json['stress'] as int?,
        syllableIndex: json['syllable_index'] as int?,
        tokenIndex: json['token_index'] as int?,
        startMs: json['start_ms'] as int?,
        endMs: json['end_ms'] as int?,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );

  final String symbol;
  final String? phonemeSet;
  final String? displayIpa;
  final int? stress;
  final int? syllableIndex;
  final int? tokenIndex;
  final int? startMs;
  final int? endMs;
  final double? confidence;

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'phoneme_set': phonemeSet,
    'display_ipa': displayIpa,
    'stress': stress,
    'syllable_index': syllableIndex,
    'token_index': tokenIndex,
    'start_ms': startMs,
    'end_ms': endMs,
    'confidence': confidence,
  };
}

// ──────────────────────────────────────────────
// Pronunciation Provider
// ──────────────────────────────────────────────

class PronunciationProvider {
  const PronunciationProvider({
    required this.id,
    required this.displayName,
    required this.version,
    this.degraded = false,
    this.diagnostic,
  });

  factory PronunciationProvider.fromJson(Map<String, dynamic> json) =>
      PronunciationProvider(
        id: json['id'] as String? ?? '',
        displayName:
            json['display_name'] as String? ?? json['id'] as String? ?? '',
        version: json['version'] as String? ?? '',
        degraded: json['degraded'] as bool? ?? false,
        diagnostic: json['diagnostic'] as String?,
      );

  final String id;
  final String displayName;
  final String version;
  final bool degraded;
  final String? diagnostic;
}

// ──────────────────────────────────────────────
// Pronunciation Analysis (per sentence)
// ──────────────────────────────────────────────

class PronunciationAnalysis {
  const PronunciationAnalysis({
    required this.sentenceId,
    this.language = '',
    this.accent = '',
    this.providerId = '',
    this.providerVersion = '',
    this.phonemeSet = '',
    required this.displayIpa,
    this.words = const [],
    this.phonemes = const [],
    this.rules = const [],
  });

  factory PronunciationAnalysis.fromJson(Map<String, dynamic> json) =>
      PronunciationAnalysis(
        sentenceId: json['sentence_id'] as String? ?? '',
        language: json['language'] as String? ?? '',
        accent: json['accent'] as String? ?? '',
        providerId:
            json['provider_id'] as String? ?? json['provider'] as String? ?? '',
        providerVersion: json['provider_version'] as String? ?? '',
        phonemeSet: json['phoneme_set'] as String? ?? '',
        displayIpa: json['display_ipa'] as String? ?? '',
        words: ((json['words'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  WordPronunciation.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        phonemes: ((json['phonemes'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  PronunciationPhoneme.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        rules: ((json['rules'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  PronunciationRule.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
      );

  final String sentenceId;
  final String language;
  final String accent;
  final String providerId;
  final String providerVersion;
  final String phonemeSet;
  final String displayIpa;
  final List<WordPronunciation> words;
  final List<PronunciationPhoneme> phonemes;
  final List<PronunciationRule> rules;

  Map<String, dynamic> toJson() => {
    'sentence_id': sentenceId,
    'language': language,
    'accent': accent,
    'provider_id': providerId,
    'provider_version': providerVersion,
    'phoneme_set': phonemeSet,
    'display_ipa': displayIpa,
    'words': words.map((value) => value.toJson()).toList(growable: false),
    'phonemes': phonemes.map((value) => value.toJson()).toList(growable: false),
    'rules': rules.map((value) => value.toJson()).toList(growable: false),
  };
}

class PronunciationRule {
  const PronunciationRule({
    required this.ruleFamily,
    required this.reason,
    required this.status,
    required this.confidence,
  });

  factory PronunciationRule.fromJson(Map<String, dynamic> json) =>
      PronunciationRule(
        ruleFamily: json['rule_family'] as String,
        reason: json['reason'] as String,
        status: json['status'] as String,
        confidence: (json['confidence'] as num).toDouble(),
      );

  final String ruleFamily;
  final String reason;
  final String status;
  final double confidence;

  Map<String, dynamic> toJson() => {
    'rule_family': ruleFamily,
    'reason': reason,
    'status': status,
    'confidence': confidence,
  };
}

// ──────────────────────────────────────────────
// Language Profile
// ──────────────────────────────────────────────

class LanguageProfile {
  const LanguageProfile({
    required this.languageCode,
    this.pronunciation,
    this.segmentation,
    this.capabilities = const {},
  });

  factory LanguageProfile.fromJson(Map<String, dynamic> json) =>
      LanguageProfile(
        languageCode: json['language_code'] as String,
        pronunciation: json['pronunciation'] as String?,
        segmentation: json['segmentation'] as String?,
        capabilities:
            (json['capabilities'] as Map<String, dynamic>?) ?? const {},
      );

  final String languageCode;
  final String? pronunciation;
  final String? segmentation;
  final Map<String, dynamic> capabilities;

  Map<String, dynamic> toJson() => {
    'language_code': languageCode,
    'pronunciation': pronunciation,
    'segmentation': segmentation,
    'capabilities': capabilities,
  };
}

// ──────────────────────────────────────────────
// Phonetic Analysis (experimental sound pattern)
// ──────────────────────────────────────────────

class PhoneticAnalysis {
  const PhoneticAnalysis({
    this.id = '',
    this.jobId = '',
    this.mediaId = '',
    this.trackId = '',
    this.sentenceId,
    this.audioStartMs,
    this.audioEndMs,
    required this.providerId,
    this.providerVersion = '',
    this.modelId = '',
    required this.modelRevision,
    this.modelChecksumSha256 = '',
    required this.phoneSet,
    this.detectedPhones = const [],
    this.findings = const [],
    this.soundAnalysis,
    this.analyzerVersion = '',
    this.createdAtMs,
  });

  factory PhoneticAnalysis.fromJson(
    Map<String, dynamic> json,
  ) => PhoneticAnalysis(
    id: json['id'] as String? ?? '',
    jobId: json['job_id'] as String? ?? '',
    mediaId: json['media_id'] as String? ?? '',
    trackId: json['track_id'] as String? ?? '',
    sentenceId: json['sentence_id'] as String?,
    audioStartMs: json['audio_start_ms'] as int?,
    audioEndMs: json['audio_end_ms'] as int?,
    providerId: json['provider_id'] as String? ?? '',
    providerVersion: json['provider_version'] as String? ?? '',
    modelId: json['model_id'] as String? ?? '',
    modelRevision: json['model_revision'] as String? ?? '',
    modelChecksumSha256: json['model_checksum_sha256'] as String? ?? '',
    phoneSet: json['phone_set'] as String? ?? '',
    detectedPhones: ((json['detected_phones'] as List<dynamic>?) ?? const [])
        .map((value) => DetectedPhone.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    findings: ((json['findings'] as List<dynamic>?) ?? const [])
        .map((value) => PhoneticFinding.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    soundAnalysis: json['sound_analysis'] is Map
        ? SoundAnalysis.fromJson(
            Map<String, dynamic>.from(json['sound_analysis'] as Map),
          )
        : null,
    analyzerVersion: json['analyzer_version'] as String? ?? '',
    createdAtMs: json['created_at_ms'] as int?,
  );

  final String id;
  final String jobId;
  final String mediaId;
  final String trackId;
  final String? sentenceId;
  final int? audioStartMs;
  final int? audioEndMs;
  final String providerId;
  final String providerVersion;
  final String modelId;
  final String modelRevision;
  final String modelChecksumSha256;
  final String phoneSet;
  final List<DetectedPhone> detectedPhones;
  final List<PhoneticFinding> findings;
  final SoundAnalysis? soundAnalysis;
  final String analyzerVersion;
  final int? createdAtMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'job_id': jobId,
    'media_id': mediaId,
    'track_id': trackId,
    'sentence_id': sentenceId,
    'audio_start_ms': audioStartMs,
    'audio_end_ms': audioEndMs,
    'provider_id': providerId,
    'provider_version': providerVersion,
    'model_id': modelId,
    'model_revision': modelRevision,
    'model_checksum_sha256': modelChecksumSha256,
    'phone_set': phoneSet,
    'detected_phones': detectedPhones.map((p) => p.toJson()).toList(),
    'findings': findings.map((value) => value.toJson()).toList(),
    'sound_analysis': soundAnalysis?.toJson(),
    'analyzer_version': analyzerVersion,
    'created_at_ms': createdAtMs,
  };
}

class PhoneticFinding {
  const PhoneticFinding({
    required this.id,
    this.analysisId = '',
    required this.findingType,
    this.affectedTokenStart = 0,
    this.affectedTokenEnd = 0,
    this.canonicalPhones = const [],
    this.detectedPhones = const [],
    this.alignedPhoneStart,
    this.alignedPhoneEnd,
    required this.audioStartMs,
    required this.audioEndMs,
    required this.confidence,
    this.evidence = '',
    required this.status,
  });

  factory PhoneticFinding.fromJson(
    Map<String, dynamic> json,
  ) => PhoneticFinding(
    id: json['id'] as String? ?? '',
    analysisId: json['analysis_id'] as String? ?? '',
    findingType: json['finding_type'] as String? ?? '',
    affectedTokenStart: json['affected_token_start'] as int? ?? 0,
    affectedTokenEnd: json['affected_token_end'] as int? ?? 0,
    canonicalPhones: ((json['canonical_phones'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
    detectedPhones: ((json['detected_phones'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
    alignedPhoneStart: json['aligned_phone_start'] as int?,
    alignedPhoneEnd: json['aligned_phone_end'] as int?,
    audioStartMs: json['audio_start_ms'] as int? ?? 0,
    audioEndMs: json['audio_end_ms'] as int? ?? 0,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    evidence: json['evidence'] as String? ?? '',
    status: json['status'] as String? ?? '',
  );

  final String id;
  final String analysisId;
  final String findingType;
  final int affectedTokenStart;
  final int affectedTokenEnd;
  final List<String> canonicalPhones;
  final List<String> detectedPhones;
  final int? alignedPhoneStart;
  final int? alignedPhoneEnd;
  final int audioStartMs;
  final int audioEndMs;
  final double confidence;
  final String evidence;
  final String status;

  bool get detectedInAudio => status == 'detected_in_audio';

  Map<String, dynamic> toJson() => {
    'id': id,
    'analysis_id': analysisId,
    'finding_type': findingType,
    'affected_token_start': affectedTokenStart,
    'affected_token_end': affectedTokenEnd,
    'canonical_phones': canonicalPhones,
    'detected_phones': detectedPhones,
    'aligned_phone_start': alignedPhoneStart,
    'aligned_phone_end': alignedPhoneEnd,
    'audio_start_ms': audioStartMs,
    'audio_end_ms': audioEndMs,
    'confidence': confidence,
    'evidence': evidence,
    'status': status,
  };
}
