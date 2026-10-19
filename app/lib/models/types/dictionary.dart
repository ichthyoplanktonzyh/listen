part of '../types.dart';

// Dictionary lookup bundles, providers, character breakdown.
// Split out of types.dart (mechanical decomposition).

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
