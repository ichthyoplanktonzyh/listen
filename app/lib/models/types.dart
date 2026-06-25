import 'timeline.dart';

// ──────────────────────────────────────────────
// Typed domain models replacing Map<String, dynamic>
// ──────────────────────────────────────────────

/// A user's word learning profile.
class WordProfile {
  const WordProfile({
    required this.id,
    required this.normalizedLemma,
    required this.displayForm,
    this.status,
    this.userDefinition,
    this.personalNote,
    required this.language,
  });

  factory WordProfile.fromJson(Map<String, dynamic> json) => WordProfile(
    id: json['id'] as String,
    normalizedLemma: json['normalized_lemma'] as String,
    displayForm: json['display_form'] as String,
    status: json['status'] as String?,
    userDefinition: json['user_definition'] as String?,
    personalNote: json['personal_note'] as String?,
    language: json['language'] as String,
  );

  final String id;
  final String normalizedLemma;
  final String displayForm;

  /// Word status: null | 'unknown_meaning' | 'known_not_recognized' | 'known_recognized'
  final String? status;
  final String? userDefinition;
  final String? personalNote;
  final String language;

  Map<String, dynamic> toJson() => {
    'id': id,
    'normalized_lemma': normalizedLemma,
    'display_form': displayForm,
    'status': status,
    'user_definition': userDefinition,
    'personal_note': personalNote,
    'language': language,
  };

  WordProfile copyWith({
    String? status,
    String? userDefinition,
    String? personalNote,
  }) => WordProfile(
    id: id,
    normalizedLemma: normalizedLemma,
    displayForm: displayForm,
    status: status ?? this.status,
    userDefinition: userDefinition ?? this.userDefinition,
    personalNote: personalNote ?? this.personalNote,
    language: language,
  );
}

/// History entry for a word's status change.
class WordStatusHistory {
  const WordStatusHistory({
    required this.status,
    this.source,
    required this.changedAt,
  });

  factory WordStatusHistory.fromJson(Map<String, dynamic> json) =>
      WordStatusHistory(
        status: json['status'] as String,
        source: json['source'] as Map<String, dynamic>?,
        changedAt: DateTime.fromMillisecondsSinceEpoch(
          json['changed_at'] as int,
        ),
      );

  final String status;
  final Map<String, dynamic>? source;
  final DateTime changedAt;
}

/// An occurrence/source-snapshot of a word in context.
class WordOccurrence {
  const WordOccurrence({
    required this.mediaTitleSnapshot,
    required this.mediaFingerprintSnapshot,
    required this.sentenceTextSnapshot,
    required this.startMsSnapshot,
    required this.endMsSnapshot,
    required this.encounterCount,
    this.mediaId,
    this.sentenceId,
  });

  factory WordOccurrence.fromJson(Map<String, dynamic> json) => WordOccurrence(
    mediaTitleSnapshot: json['media_title_snapshot'] as String,
    mediaFingerprintSnapshot: json['media_fingerprint_snapshot'] as String,
    sentenceTextSnapshot: json['sentence_text_snapshot'] as String,
    startMsSnapshot: json['start_ms_snapshot'] as int,
    endMsSnapshot: json['end_ms_snapshot'] as int,
    encounterCount: json['encounter_count'] as int,
    mediaId: json['media_id'] as String?,
    sentenceId: json['sentence_id'] as String?,
  );

  final String mediaTitleSnapshot;
  final String mediaFingerprintSnapshot;
  final String sentenceTextSnapshot;
  final int startMsSnapshot;
  final int endMsSnapshot;
  final int encounterCount;
  final String? mediaId;
  final String? sentenceId;
}

/// Full word details returned by the API.
class WordDetail {
  const WordDetail({
    required this.profile,
    this.history = const [],
    this.occurrences = const [],
  });

  factory WordDetail.fromJson(Map<String, dynamic> json) => WordDetail(
    profile: WordProfile.fromJson(
      json['profile'] as Map<String, dynamic>,
    ),
    history: ((json['history'] as List<dynamic>?) ?? const [])
        .map(
          (value) => WordStatusHistory.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    occurrences: ((json['occurrences'] as List<dynamic>?) ?? const [])
        .map(
          (value) => WordOccurrence.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
  );

  final WordProfile profile;
  final List<WordStatusHistory> history;
  final List<WordOccurrence> occurrences;
}

// ──────────────────────────────────────────────
// Diagnosis
// ──────────────────────────────────────────────

class DiagnosisHint {
  const DiagnosisHint({
    required this.kind,
    this.reasons = const [],
  });

  factory DiagnosisHint.fromJson(Map<String, dynamic> json) => DiagnosisHint(
    kind: json['kind'] as String,
    reasons: ((json['reasons'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
  );

  final String kind;
  final List<String> reasons;
}

class Diagnosis {
  const Diagnosis({
    this.hints = const [],
  });

  factory Diagnosis.fromJson(Map<String, dynamic> json) => Diagnosis(
    hints: ((json['hints'] as List<dynamic>?) ?? const [])
        .map((value) => DiagnosisHint.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  final List<DiagnosisHint> hints;

  Map<String, dynamic> toJson() => {
    'hints': hints.map((h) => {'kind': h.kind, 'reasons': h.reasons}).toList(),
  };
}

// ──────────────────────────────────────────────
// Phrase Candidate
// ──────────────────────────────────────────────

class PhraseCandidate {
  const PhraseCandidate({
    required this.canonicalForm,
    required this.displayForm,
    required this.tokenStart,
    required this.tokenEnd,
    this.confidence,
  });

  factory PhraseCandidate.fromJson(Map<String, dynamic> json) =>
      PhraseCandidate(
        canonicalForm: json['canonical_form'] as String,
        displayForm: json['display_form'] as String,
        tokenStart: json['token_start'] as int,
        tokenEnd: json['token_end'] as int,
        confidence: (json['confidence'] as num?)?.toDouble(),
      );

  final String canonicalForm;
  final String displayForm;
  final int tokenStart;
  final int tokenEnd;
  final double? confidence;

  Map<String, dynamic> toJson() => {
    'canonical_form': canonicalForm,
    'display_form': displayForm,
    'token_start': tokenStart,
    'token_end': tokenEnd,
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
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        version: json['version'] as String,
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
    required this.displayIpa,
    this.phonemes = const [],
    this.provider,
    this.rules = const [],
  });

  factory PronunciationAnalysis.fromJson(Map<String, dynamic> json) =>
      PronunciationAnalysis(
        sentenceId: json['sentence_id'] as String,
        displayIpa: json['display_ipa'] as String,
        phonemes: ((json['phonemes'] as List<dynamic>?) ?? const [])
            .map((value) => PhonemeInfo.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
        provider: json['provider'] as String?,
        rules: ((json['rules'] as List<dynamic>?) ?? const [])
            .map(
              (value) => PronunciationRule.fromJson(
                value as Map<String, dynamic>,
              ),
            )
            .toList(growable: false),
      );

  final String sentenceId;
  final String displayIpa;
  final List<PhonemeInfo> phonemes;
  final String? provider;
  final List<PronunciationRule> rules;
}

class PhonemeInfo {
  const PhonemeInfo({
    required this.symbol,
  });

  factory PhonemeInfo.fromJson(Map<String, dynamic> json) => PhonemeInfo(
    symbol: json['symbol'] as String,
  );

  final String symbol;
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
        capabilities: (json['capabilities'] as Map<String, dynamic>?) ??
            const {},
      );

  final String languageCode;
  final String? pronunciation;
  final String? segmentation;
  final Map<String, dynamic> capabilities;
}

// ──────────────────────────────────────────────
// Phonetic Analysis (experimental sound pattern)
// ──────────────────────────────────────────────

class PhoneticAnalysis {
  const PhoneticAnalysis({
    required this.providerId,
    required this.modelRevision,
    required this.phoneSet,
    this.detectedPhones = const [],
    this.findings = const [],
  });

  factory PhoneticAnalysis.fromJson(Map<String, dynamic> json) =>
      PhoneticAnalysis(
        providerId: json['provider_id'] as String,
        modelRevision: json['model_revision'] as String,
        phoneSet: json['phone_set'] as String,
        detectedPhones: ((json['detected_phones'] as List<dynamic>?) ?? const [])
            .map(
              (value) => DetectedPhone.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        findings: ((json['findings'] as List<dynamic>?) ?? const [])
            .map((value) => value as Map<String, dynamic>)
            .toList(growable: false),
      );

  final String providerId;
  final String modelRevision;
  final String phoneSet;
  final List<DetectedPhone> detectedPhones;
  final List<Map<String, dynamic>> findings;

  Map<String, dynamic> toJson() => {
    'provider_id': providerId,
    'model_revision': modelRevision,
    'phone_set': phoneSet,
    'detected_phones': detectedPhones.map((p) => p.toJson()).toList(),
    'findings': findings,
  };
}
