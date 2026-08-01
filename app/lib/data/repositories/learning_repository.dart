import '../../models/api_failure.dart';
import '../../models/types.dart';
import '../../services/api_service.dart';

/// Narrow data boundary used by the subtitle learning workflow.
abstract interface class LearningRepository {
  bool get isAvailable;

  ApiFailure failureDetail(Object error);

  Future<List<PhraseCandidate>> phraseCandidates(String cueId);

  Future<List<LexicalEntry>> readWordEntries(
    List<String> lemmas, {
    required String language,
  });

  Future<List<LexicalEntryDetails>> readPhraseEntries({
    required String language,
  });

  Future<LexicalEntryDetails> upsertWord(
    String lemma,
    String displayForm,
    String? status, {
    required String language,
    Map<String, dynamic>? source,
  });

  Future<LexicalEntryDetails> entryDetails(String entryId);

  Future<DictionaryLookupBundle> lookupDictionary(
    String lemma, {
    required String language,
  });

  Future<WordPronunciation> lookupPronunciation(String word);

  Future<LanguageProfile> lookupLanguageProfile(String language);

  Future<LexicalEntryDetails> updateLearningContent(
    String entryId, {
    String? userDefinition,
    String? personalNote,
  });

  Future<void> createObservation({
    required String lexicalEntryId,
    required String sentenceId,
    required String originalForm,
    required bool heard,
    Map<String, dynamic>? source,
  });

  Future<void> setCapabilityOverride(
    String entryId,
    String capability, {
    String? conclusion,
  });
}

/// Local-core implementation. The supplier lets the long-lived coordinator
/// follow core restarts without storing a stale [LocalApi] instance.
class LocalLearningRepository implements LearningRepository {
  LocalLearningRepository(this._getApi);

  final LocalApi? Function() _getApi;

  LocalApi get _api =>
      _getApi() ?? (throw StateError('Local learning API is unavailable'));

  @override
  bool get isAvailable => _getApi() != null;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  @override
  Future<List<PhraseCandidate>> phraseCandidates(String cueId) =>
      _api.phraseCandidates(cueId);

  @override
  Future<List<LexicalEntry>> readWordEntries(
    List<String> lemmas, {
    required String language,
  }) => _api.readLexicalEntriesBatch(lemmas, language: language);

  @override
  Future<List<LexicalEntryDetails>> readPhraseEntries({
    required String language,
  }) => _api.lexicalEntries(kind: 'phrase', language: language);

  @override
  Future<LexicalEntryDetails> upsertWord(
    String lemma,
    String displayForm,
    String? status, {
    required String language,
    Map<String, dynamic>? source,
  }) => _api.upsertWordLexicalEntry(
    lemma,
    displayForm,
    status,
    language: language,
    source: source,
  );

  @override
  Future<LexicalEntryDetails> entryDetails(String entryId) =>
      _api.lexicalEntryDetails(entryId);

  @override
  Future<DictionaryLookupBundle> lookupDictionary(
    String lemma, {
    required String language,
  }) => _api.lookupDictionary(lemma, language: language);

  @override
  Future<WordPronunciation> lookupPronunciation(String word) =>
      _api.lookupPronunciation(word);

  @override
  Future<LanguageProfile> lookupLanguageProfile(String language) =>
      _api.lookupLanguageProfile(language);

  @override
  Future<LexicalEntryDetails> updateLearningContent(
    String entryId, {
    String? userDefinition,
    String? personalNote,
  }) => _api.updateLexicalLearningContent(
    entryId,
    userDefinition: userDefinition,
    personalNote: personalNote,
  );

  @override
  Future<void> createObservation({
    required String lexicalEntryId,
    required String sentenceId,
    required String originalForm,
    required bool heard,
    Map<String, dynamic>? source,
  }) => _api.createLexicalObservation(
    lexicalEntryId: lexicalEntryId,
    sentenceId: sentenceId,
    originalForm: originalForm,
    heard: heard,
    source: source,
  );

  @override
  Future<void> setCapabilityOverride(
    String entryId,
    String capability, {
    String? conclusion,
  }) async {
    await _api.setCapabilityOverride(
      entryId,
      capability,
      conclusion: conclusion,
    );
  }
}

/// Null object for workflows that only use the request-generation helpers.
class UnavailableLearningRepository implements LearningRepository {
  const UnavailableLearningRepository();

  Never _unavailable() =>
      throw StateError('A LearningRepository was not configured');

  @override
  bool get isAvailable => false;

  @override
  ApiFailure failureDetail(Object error) => describeApiFailure(error);

  @override
  Future<void> createObservation({
    required String lexicalEntryId,
    required String sentenceId,
    required String originalForm,
    required bool heard,
    Map<String, dynamic>? source,
  }) => _unavailable();

  @override
  Future<LexicalEntryDetails> entryDetails(String entryId) => _unavailable();

  @override
  Future<DictionaryLookupBundle> lookupDictionary(
    String lemma, {
    required String language,
  }) => _unavailable();

  @override
  Future<LanguageProfile> lookupLanguageProfile(String language) =>
      _unavailable();

  @override
  Future<WordPronunciation> lookupPronunciation(String word) => _unavailable();

  @override
  Future<List<PhraseCandidate>> phraseCandidates(String cueId) =>
      _unavailable();

  @override
  Future<List<LexicalEntryDetails>> readPhraseEntries({
    required String language,
  }) => _unavailable();

  @override
  Future<List<LexicalEntry>> readWordEntries(
    List<String> lemmas, {
    required String language,
  }) => _unavailable();

  @override
  Future<void> setCapabilityOverride(
    String entryId,
    String capability, {
    String? conclusion,
  }) => _unavailable();

  @override
  Future<LexicalEntryDetails> updateLearningContent(
    String entryId, {
    String? userDefinition,
    String? personalNote,
  }) => _unavailable();

  @override
  Future<LexicalEntryDetails> upsertWord(
    String lemma,
    String displayForm,
    String? status, {
    required String language,
    Map<String, dynamic>? source,
  }) => _unavailable();
}
