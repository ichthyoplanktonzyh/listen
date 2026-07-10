import 'timeline.dart';

// ──────────────────────────────────────────────
// Typed domain models replacing Map<String, dynamic>
// ──────────────────────────────────────────────

/// A user's lexical learning asset.
class LexicalEntry {
  const LexicalEntry({
    required this.id,
    required this.normalizedForm,
    required this.displayForm,
    required this.kind,
    this.status,
    this.userDefinition,
    this.personalNote,
    required this.language,
  });

  factory LexicalEntry.fromJson(Map<String, dynamic> json) => LexicalEntry(
    id: json['id'] as String,
    normalizedForm: json['normalized_form'] as String,
    displayForm: json['display_form'] as String,
    kind: json['kind'] as String,
    status: json['status'] as String?,
    userDefinition: json['user_definition'] as String?,
    personalNote: json['personal_note'] as String?,
    language: json['language'] as String,
  );

  final String id;
  final String normalizedForm;
  final String displayForm;
  final String kind;

  /// Learning status: null | 'unknown_meaning' | 'known_not_recognized' | 'known_recognized'
  final String? status;
  final String? userDefinition;
  final String? personalNote;
  final String language;

  Map<String, dynamic> toJson() => {
    'id': id,
    'normalized_form': normalizedForm,
    'display_form': displayForm,
    'kind': kind,
    'status': status,
    'user_definition': userDefinition,
    'personal_note': personalNote,
    'language': language,
  };

  LexicalEntry copyWith({
    String? status,
    String? userDefinition,
    String? personalNote,
  }) => LexicalEntry(
    id: id,
    normalizedForm: normalizedForm,
    displayForm: displayForm,
    kind: kind,
    status: status ?? this.status,
    userDefinition: userDefinition ?? this.userDefinition,
    personalNote: personalNote ?? this.personalNote,
    language: language,
  );
}

/// History entry for a lexical asset status change.
class LexicalStatusHistory {
  const LexicalStatusHistory({
    this.previousStatus,
    this.newStatus,
    required this.changeSource,
    required this.changedAtMs,
  });

  factory LexicalStatusHistory.fromJson(Map<String, dynamic> json) =>
      LexicalStatusHistory(
        previousStatus: json['previous_status'] as String?,
        newStatus: json['new_status'] as String?,
        changeSource: json['change_source'] as String,
        changedAtMs: json['changed_at_ms'] as int,
      );

  final String? previousStatus;
  final String? newStatus;
  final String changeSource;
  final int changedAtMs;

  Map<String, dynamic> toJson() => {
    'previous_status': previousStatus,
    'new_status': newStatus,
    'change_source': changeSource,
    'changed_at_ms': changedAtMs,
  };
}

/// An occurrence/source-snapshot of a lexical asset in context.
class LexicalOccurrence {
  const LexicalOccurrence({
    required this.mediaTitleSnapshot,
    required this.mediaFingerprintSnapshot,
    required this.sentenceTextSnapshot,
    required this.startMsSnapshot,
    required this.endMsSnapshot,
    required this.encounterCount,
    this.originalForm,
    this.mediaId,
    this.sentenceId,
  });

  factory LexicalOccurrence.fromJson(Map<String, dynamic> json) =>
      LexicalOccurrence(
        mediaTitleSnapshot: json['media_title_snapshot'] as String,
        mediaFingerprintSnapshot: json['media_fingerprint_snapshot'] as String,
        sentenceTextSnapshot: json['sentence_text_snapshot'] as String,
        startMsSnapshot: json['start_ms_snapshot'] as int,
        endMsSnapshot: json['end_ms_snapshot'] as int,
        encounterCount: json['encounter_count'] as int,
        originalForm: json['original_form'] as String?,
        mediaId: json['media_id'] as String?,
        sentenceId: json['sentence_id'] as String?,
      );

  final String mediaTitleSnapshot;
  final String mediaFingerprintSnapshot;
  final String sentenceTextSnapshot;
  final int startMsSnapshot;
  final int endMsSnapshot;
  final int encounterCount;
  final String? originalForm;
  final String? mediaId;
  final String? sentenceId;

  Map<String, dynamic> toJson() => {
    'media_title_snapshot': mediaTitleSnapshot,
    'media_fingerprint_snapshot': mediaFingerprintSnapshot,
    'sentence_text_snapshot': sentenceTextSnapshot,
    'start_ms_snapshot': startMsSnapshot,
    'end_ms_snapshot': endMsSnapshot,
    'encounter_count': encounterCount,
    'original_form': originalForm,
    'media_id': mediaId,
    'sentence_id': sentenceId,
  };
}

/// Full lexical asset details returned by the API.
class LexicalEntryDetails {
  const LexicalEntryDetails({
    required this.entry,
    this.history = const [],
    this.occurrences = const [],
    this.capabilityProfile,
  });

  factory LexicalEntryDetails.fromJson(Map<String, dynamic> json) =>
      LexicalEntryDetails(
        entry: LexicalEntry.fromJson(json['entry'] as Map<String, dynamic>),
        history: ((json['history'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  LexicalStatusHistory.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        occurrences: ((json['occurrences'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  LexicalOccurrence.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        capabilityProfile: json['capability_profile'] is Map
            ? LexicalCapabilityProfile.fromJson(
                Map<String, dynamic>.from(json['capability_profile'] as Map),
              )
            : null,
      );

  final LexicalEntry entry;
  final List<LexicalStatusHistory> history;
  final List<LexicalOccurrence> occurrences;
  final LexicalCapabilityProfile? capabilityProfile;

  Map<String, dynamic> toJson() => {
    'entry': entry.toJson(),
    'history': history.map((value) => value.toJson()).toList(growable: false),
    'occurrences': occurrences
        .map((value) => value.toJson())
        .toList(growable: false),
    if (capabilityProfile != null)
      'capability_profile': capabilityProfile!.toJson(),
  };
}

// ──────────────────────────────────────────────
// Capability Profile (Phase 3.4.1)
// ──────────────────────────────────────────────

class CapabilityProjection {
  const CapabilityProjection({
    required this.conclusion,
    required this.source,
    required this.algorithmVersion,
    required this.updatedAtMs,
  });

  factory CapabilityProjection.fromJson(Map<String, dynamic> json) =>
      CapabilityProjection(
        conclusion: json['conclusion'] as String,
        source: json['source'] as String,
        algorithmVersion: json['algorithm_version'] as String,
        updatedAtMs: json['updated_at_ms'] as int,
      );

  final String conclusion;
  final String source;
  final String algorithmVersion;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'conclusion': conclusion,
    'source': source,
    'algorithm_version': algorithmVersion,
    'updated_at_ms': updatedAtMs,
  };
}

class CapabilityOverride {
  const CapabilityOverride({
    required this.conclusion,
    required this.source,
    required this.updatedAtMs,
  });

  factory CapabilityOverride.fromJson(Map<String, dynamic> json) =>
      CapabilityOverride(
        conclusion: json['conclusion'] as String,
        source: json['source'] as String,
        updatedAtMs: json['updated_at_ms'] as int,
      );

  final String conclusion;
  final String source;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'conclusion': conclusion,
    'source': source,
    'updated_at_ms': updatedAtMs,
  };
}

class CapabilityDimensionState {
  const CapabilityDimensionState({this.projection, this.userOverride});

  factory CapabilityDimensionState.fromJson(Map<String, dynamic> json) =>
      CapabilityDimensionState(
        projection: json['projection'] is Map
            ? CapabilityProjection.fromJson(
                Map<String, dynamic>.from(json['projection'] as Map),
              )
            : null,
        userOverride: json['user_override'] is Map
            ? CapabilityOverride.fromJson(
                Map<String, dynamic>.from(json['user_override'] as Map),
              )
            : null,
      );

  final CapabilityProjection? projection;
  final CapabilityOverride? userOverride;

  String get effectiveAssessment {
    if (userOverride != null) return userOverride!.conclusion;
    if (projection != null) return projection!.conclusion;
    return 'unassessed';
  }

  Map<String, dynamic> toJson() => {
    'projection': projection?.toJson(),
    'user_override': userOverride?.toJson(),
  };
}

class LexicalCapabilityProfile {
  const LexicalCapabilityProfile({
    required this.lexicalEntryId,
    this.senseId,
    required this.reading,
    required this.listening,
    required this.speaking,
    required this.writing,
  });

  factory LexicalCapabilityProfile.fromJson(Map<String, dynamic> json) =>
      LexicalCapabilityProfile(
        lexicalEntryId: json['lexical_entry_id'] as String,
        senseId: json['sense_id'] as String?,
        reading: CapabilityDimensionState.fromJson(
          _asMap(json['reading']),
        ),
        listening: CapabilityDimensionState.fromJson(
          _asMap(json['listening']),
        ),
        speaking: CapabilityDimensionState.fromJson(
          _asMap(json['speaking']),
        ),
        writing: CapabilityDimensionState.fromJson(
          _asMap(json['writing']),
        ),
      );

  final String lexicalEntryId;
  final String? senseId;
  final CapabilityDimensionState reading;
  final CapabilityDimensionState listening;
  final CapabilityDimensionState speaking;
  final CapabilityDimensionState writing;

  Map<String, dynamic> toJson() => {
    'lexical_entry_id': lexicalEntryId,
    'sense_id': senseId,
    'reading': reading.toJson(),
    'listening': listening.toJson(),
    'speaking': speaking.toJson(),
    'writing': writing.toJson(),
  };
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

// ──────────────────────────────────────────────
// Diagnosis
// ──────────────────────────────────────────────

class DiagnosisHint {
  const DiagnosisHint({
    required this.kind,
    this.lexicalEntryIds = const [],
    this.reasons = const [],
  });

  factory DiagnosisHint.fromJson(Map<String, dynamic> json) => DiagnosisHint(
    kind: json['kind'] as String,
    lexicalEntryIds: ((json['lexical_entry_ids'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
    reasons: ((json['reasons'] as List<dynamic>?) ?? const [])
        .cast<String>()
        .toList(growable: false),
  );

  final String kind;
  final List<String> lexicalEntryIds;
  final List<String> reasons;
}

class Diagnosis {
  const Diagnosis({this.hints = const []});

  factory Diagnosis.fromJson(Map<String, dynamic> json) => Diagnosis(
    hints: ((json['hints'] as List<dynamic>?) ?? const [])
        .map((value) => DiagnosisHint.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
  );

  final List<DiagnosisHint> hints;

  Map<String, dynamic> toJson() => {
    'hints': hints
        .map(
          (h) => {
            'kind': h.kind,
            'lexical_entry_ids': h.lexicalEntryIds,
            'reasons': h.reasons,
          },
        )
        .toList(),
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
    this.reason,
  });

  factory PhraseCandidate.fromJson(Map<String, dynamic> json) =>
      PhraseCandidate(
        canonicalForm: json['canonical_form'] as String,
        displayForm: json['display_form'] as String,
        tokenStart: json['token_start'] as int,
        tokenEnd: json['token_end'] as int,
        confidence: (json['confidence'] as num?)?.toDouble(),
        reason: json['reason'] as String?,
      );

  final String canonicalForm;
  final String displayForm;
  final int tokenStart;
  final int tokenEnd;
  final double? confidence;
  final String? reason;

  Map<String, dynamic> toJson() => {
    'canonical_form': canonicalForm,
    'display_form': displayForm,
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'confidence': confidence,
    'reason': reason,
  };
}

// ──────────────────────────────────────────────
// Dictionary Lookup
// ──────────────────────────────────────────────

class DictionaryLookupBundle {
  const DictionaryLookupBundle({
    required this.query,
    required this.normalizedLemma,
    this.results = const [],
  });

  factory DictionaryLookupBundle.fromJson(Map<String, dynamic> json) =>
      DictionaryLookupBundle(
        query: json['query'] as String? ?? '',
        normalizedLemma: json['normalized_lemma'] as String? ?? '',
        results: ((json['results'] as List<dynamic>?) ?? const [])
            .map(
              (value) => DictionaryLookupResult.fromJson(
                value as Map<String, dynamic>,
              ),
            )
            .toList(growable: false),
      );

  final String query;
  final String normalizedLemma;
  final List<DictionaryLookupResult> results;

  Map<String, dynamic> toJson() => {
    'query': query,
    'normalized_lemma': normalizedLemma,
    'results': results.map((value) => value.toJson()).toList(growable: false),
  };
}

class DictionaryLookupResult {
  const DictionaryLookupResult({
    required this.provider,
    this.lookup,
    this.error,
  });

  factory DictionaryLookupResult.fromJson(Map<String, dynamic> json) {
    final lookup = json['lookup'];
    return DictionaryLookupResult(
      provider: DictionaryProviderDescriptor.fromJson(
        (json['provider'] as Map<String, dynamic>?) ?? const {},
      ),
      lookup: lookup is Map<String, dynamic>
          ? DictionaryLookup.fromJson(lookup)
          : null,
      error: json['error'] as String?,
    );
  }

  final DictionaryProviderDescriptor provider;
  final DictionaryLookup? lookup;
  final String? error;

  Map<String, dynamic> toJson() => {
    'provider': provider.toJson(),
    'lookup': lookup?.toJson(),
    'error': error,
  };
}

class DictionaryProviderDescriptor {
  const DictionaryProviderDescriptor({
    required this.id,
    required this.displayName,
    this.supportedLanguages = const [],
    this.providesDefinitions = false,
    this.providesPhonetics = false,
    this.providesAudio = false,
    this.offline = false,
  });

  factory DictionaryProviderDescriptor.fromJson(Map<String, dynamic> json) =>
      DictionaryProviderDescriptor(
        id: json['id'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        supportedLanguages:
            ((json['supported_languages'] as List<dynamic>?) ?? const [])
                .cast<String>()
                .toList(growable: false),
        providesDefinitions: json['provides_definitions'] as bool? ?? false,
        providesPhonetics: json['provides_phonetics'] as bool? ?? false,
        providesAudio: json['provides_audio'] as bool? ?? false,
        offline: json['offline'] as bool? ?? false,
      );

  final String id;
  final String displayName;
  final List<String> supportedLanguages;
  final bool providesDefinitions;
  final bool providesPhonetics;
  final bool providesAudio;
  final bool offline;

  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'supported_languages': supportedLanguages,
    'provides_definitions': providesDefinitions,
    'provides_phonetics': providesPhonetics,
    'provides_audio': providesAudio,
    'offline': offline,
  };
}

class DictionaryLookup {
  const DictionaryLookup({
    required this.query,
    required this.lemma,
    this.definitions = const [],
    this.phonetics = const [],
    this.characterBreakdowns = const [],
    this.provider,
    this.cachedAtMs,
  });

  factory DictionaryLookup.fromJson(Map<String, dynamic> json) =>
      DictionaryLookup(
        query: json['query'] as String? ?? '',
        lemma: json['lemma'] as String? ?? '',
        definitions: ((json['definitions'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  DictionaryDefinition.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        phonetics: ((json['phonetics'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  DictionaryPhonetic.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        characterBreakdowns:
            ((json['character_breakdowns'] as List<dynamic>?) ?? const [])
                .map(
                  (value) => CharacterBreakdown.fromJson(
                    value as Map<String, dynamic>,
                  ),
                )
                .toList(growable: false),
        provider: json['provider'] as String?,
        cachedAtMs: json['cached_at_ms'] as int?,
      );

  final String query;
  final String lemma;
  final List<DictionaryDefinition> definitions;
  final List<DictionaryPhonetic> phonetics;
  final List<CharacterBreakdown> characterBreakdowns;
  final String? provider;
  final int? cachedAtMs;

  Map<String, dynamic> toJson() => {
    'query': query,
    'lemma': lemma,
    'definitions': definitions
        .map((value) => value.toJson())
        .toList(growable: false),
    'phonetics': phonetics
        .map((value) => value.toJson())
        .toList(growable: false),
    'character_breakdowns': characterBreakdowns
        .map((value) => value.toJson())
        .toList(growable: false),
    'provider': provider,
    'cached_at_ms': cachedAtMs,
  };
}

class DictionaryDefinition {
  const DictionaryDefinition({required this.text, this.partOfSpeech});

  factory DictionaryDefinition.fromJson(Map<String, dynamic> json) =>
      DictionaryDefinition(
        text: json['text'] as String? ?? '',
        partOfSpeech: json['part_of_speech'] as String?,
      );

  final String text;
  final String? partOfSpeech;

  Map<String, dynamic> toJson() => {
    'text': text,
    'part_of_speech': partOfSpeech,
  };
}

class DictionaryPhonetic {
  const DictionaryPhonetic({required this.text, this.region, this.audioUrl});

  factory DictionaryPhonetic.fromJson(Map<String, dynamic> json) =>
      DictionaryPhonetic(
        text: json['text'] as String? ?? '',
        region: json['region'] as String?,
        audioUrl: json['audio_url'] as String?,
      );

  final String text;
  final String? region;
  final String? audioUrl;

  Map<String, dynamic> toJson() => {
    'text': text,
    'region': region,
    'audio_url': audioUrl,
  };
}

class CharacterBreakdown {
  const CharacterBreakdown({
    required this.character,
    this.phonetic = '',
    this.meaning = '',
  });

  factory CharacterBreakdown.fromJson(Map<String, dynamic> json) =>
      CharacterBreakdown(
        character: json['character'] as String? ?? '',
        phonetic: json['phonetic'] as String? ?? '',
        meaning: json['meaning'] as String? ?? '',
      );

  final String character;
  final String phonetic;
  final String meaning;

  Map<String, dynamic> toJson() => {
    'character': character,
    'phonetic': phonetic,
    'meaning': meaning,
  };
}

// ──────────────────────────────────────────────
// Word Pronunciation Lookup
// ──────────────────────────────────────────────

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

/// One explainability datum behind a content-fit band (ADR 0018). `decisive`
/// marks the signals that selected or escalated the band; the rest are
/// informational context.
class FitSignal {
  const FitSignal({
    required this.kind,
    required this.value,
    required this.decisive,
  });

  factory FitSignal.fromJson(Map<String, dynamic> json) => FitSignal(
    kind: json['kind'] as String,
    value: (json['value'] as num).toDouble(),
    decisive: json['decisive'] as bool? ?? false,
  );

  final String kind;
  final double value;
  final bool decisive;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'value': value,
    'decisive': decisive,
  };
}

class DifficultyDimension {
  const DifficultyDimension({required this.fit, required this.signals});

  factory DifficultyDimension.fromJson(Map<String, dynamic> json) =>
      DifficultyDimension(
        fit: json['fit'] as String,
        signals: (json['signals'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((value) => FitSignal.fromJson(Map<String, dynamic>.from(value)))
            .toList(),
      );

  final String fit;
  final List<FitSignal> signals;

  List<FitSignal> get decisiveSignals =>
      signals.where((signal) => signal.decisive).toList();

  Map<String, dynamic> toJson() => {
    'fit': fit,
    'signals': signals.map((signal) => signal.toJson()).toList(),
  };
}

/// Media-level dual-dimension content fit (ADR 0018). Bands are expectation
/// management, never gates: the UI may render them but must not hide, lock,
/// or discourage any material because of them.
class ContentDifficultyProfile {
  const ContentDifficultyProfile({
    required this.subjectKind,
    required this.subjectId,
    required this.language,
    required this.meaning,
    required this.sound,
    required this.assessedTokenRatio,
    required this.evidenceGrade,
    required this.algorithmVersion,
    required this.computedAtMs,
    required this.inputFingerprint,
  });

  factory ContentDifficultyProfile.fromJson(Map<String, dynamic> json) =>
      ContentDifficultyProfile(
        subjectKind: json['subject_kind'] as String,
        subjectId: json['subject_id'] as String,
        language: json['language'] as String,
        meaning: DifficultyDimension.fromJson(
          Map<String, dynamic>.from(json['meaning'] as Map),
        ),
        sound: DifficultyDimension.fromJson(
          Map<String, dynamic>.from(json['sound'] as Map),
        ),
        assessedTokenRatio: (json['assessed_token_ratio'] as num).toDouble(),
        evidenceGrade: json['evidence_grade'] as String,
        algorithmVersion: json['algorithm_version'] as String,
        computedAtMs: json['computed_at_ms'] as int,
        inputFingerprint: json['input_fingerprint'] as String,
      );

  final String subjectKind;
  final String subjectId;
  final String language;
  final DifficultyDimension meaning;
  final DifficultyDimension sound;
  final double assessedTokenRatio;
  final String evidenceGrade;
  final String algorithmVersion;
  final int computedAtMs;
  final String inputFingerprint;

  /// Mirrors the backend honesty threshold (MIN_ASSESSED_TOKEN_RATIO): below
  /// it the bands are a conservative guess and the degraded-estimate state
  /// must be shown instead of confident copy.
  bool get hasSufficientVocabularyProfile => assessedTokenRatio >= 0.5;

  bool get usageCalibrated => evidenceGrade == 'usage_calibrated';

  /// Golden target material: meaning is accessible but decoding is not
  /// (meaning comprehensible-or-easier, sound challenging-or-harder).
  bool get isIntensiveListeningTarget {
    const easier = {'too_easy', 'comprehensible'};
    const harder = {'challenging', 'too_hard'};
    return easier.contains(meaning.fit) && harder.contains(sound.fit);
  }

  Map<String, dynamic> toJson() => {
    'subject_kind': subjectKind,
    'subject_id': subjectId,
    'language': language,
    'meaning': meaning.toJson(),
    'sound': sound.toJson(),
    'assessed_token_ratio': assessedTokenRatio,
    'evidence_grade': evidenceGrade,
    'algorithm_version': algorithmVersion,
    'computed_at_ms': computedAtMs,
    'input_fingerprint': inputFingerprint,
  };
}

class ColdStartWordCandidate {
  const ColdStartWordCandidate({
    required this.displayForm,
    required this.normalizedForm,
    required this.occurrenceCount,
  });

  factory ColdStartWordCandidate.fromJson(Map<String, dynamic> json) =>
      ColdStartWordCandidate(
        displayForm: json['display_form'] as String,
        normalizedForm: json['normalized_form'] as String,
        occurrenceCount: json['occurrence_count'] as int,
      );

  final String displayForm;
  final String normalizedForm;
  final int occurrenceCount;

  Map<String, dynamic> toJson() => {
    'display_form': displayForm,
    'normalized_form': normalizedForm,
    'occurrence_count': occurrenceCount,
  };
}

/// Registered media as served by `GET /v1/media` (nested in
/// [MediaLibraryEntry]).
class MediaItem {
  const MediaItem({
    required this.id,
    required this.path,
    required this.fingerprint,
    required this.title,
    required this.kind,
    required this.durationMs,
    required this.availability,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    id: json['id'] as String,
    path: json['path'] as String,
    fingerprint: json['fingerprint'] as String,
    title: json['title'] as String,
    kind: json['kind'] as String,
    durationMs: json['duration'] as int?,
    availability: json['availability'] as String,
    createdAtMs: json['created_at_ms'] as int,
    updatedAtMs: json['updated_at_ms'] as int,
  );

  final String id;
  final String path;
  final String fingerprint;
  final String title;
  final String kind;
  final int? durationMs;
  final String availability;
  final int createdAtMs;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'fingerprint': fingerprint,
    'title': title,
    'kind': kind,
    'duration': durationMs,
    'availability': availability,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

/// Triage queue names derived client-side from [MediaLibraryEntry] facts.
abstract final class TriageQueue {
  static const extensive = 'extensive';
  static const intensive = 'intensive';
  static const deferred = 'deferred';
}

/// One media-library row for triage (Phase 3.5 Slice 5): media plus the
/// facts queue grouping derives from. Queues only suggest — ignoring them
/// changes nothing about playback or learning behavior (P3/P5 red lines).
class MediaLibraryEntry {
  const MediaLibraryEntry({
    required this.media,
    required this.primaryTrackId,
    required this.fit,
    required this.triageIntent,
    required this.familiarMaterial,
  });

  factory MediaLibraryEntry.fromJson(Map<String, dynamic> json) =>
      MediaLibraryEntry(
        media: MediaItem.fromJson(Map<String, dynamic>.from(json['media'] as Map)),
        primaryTrackId: json['primary_track_id'] as String?,
        fit: json['fit'] == null
            ? null
            : ContentDifficultyProfile.fromJson(
                Map<String, dynamic>.from(json['fit'] as Map),
              ),
        triageIntent: json['triage_intent'] as String?,
        familiarMaterial: json['familiar_material'] as bool? ?? false,
      );

  final MediaItem media;
  final String? primaryTrackId;
  final ContentDifficultyProfile? fit;

  /// 'pin_extensive' | 'pin_intensive' | 'defer' | null.
  final String? triageIntent;
  final bool familiarMaterial;

  /// Golden target material: readable meaning, hard decoding.
  bool get isGoldenTarget => fit?.isIntensiveListeningTarget ?? false;

  /// Derives the suggested queue (ADR 0018 decision 6, all rules
  /// heuristic_proxy): explicit user intent wins, then the familiar-material
  /// relisten supply (when enabled), then fit bands — golden targets go to
  /// intensive, any too_hard dimension defers, everything else is extensive
  /// material. Returns null when no fact supports a suggestion.
  String? triageQueue({bool familiarSupply = true}) {
    switch (triageIntent) {
      case 'pin_extensive':
        return TriageQueue.extensive;
      case 'pin_intensive':
        return TriageQueue.intensive;
      case 'defer':
        return TriageQueue.deferred;
    }
    if (familiarSupply && familiarMaterial) return TriageQueue.extensive;
    final fit = this.fit;
    if (fit == null) return null;
    if (fit.isIntensiveListeningTarget) return TriageQueue.intensive;
    if (fit.meaning.fit == 'too_hard' || fit.sound.fit == 'too_hard') {
      return TriageQueue.deferred;
    }
    return TriageQueue.extensive;
  }

  Map<String, dynamic> toJson() => {
    'media': media.toJson(),
    'primary_track_id': primaryTrackId,
    'fit': fit?.toJson(),
    'triage_intent': triageIntent,
    'familiar_material': familiarMaterial,
  };
}
