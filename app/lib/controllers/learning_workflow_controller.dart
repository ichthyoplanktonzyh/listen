import '../models/timeline.dart';
import '../models/types.dart';
import '../services/api_service.dart';
import 'learning_controller.dart';

class LearningWordStatusUpdate {
  const LearningWordStatusUpdate({required this.tokenText});

  final String tokenText;
}

class LearningWorkflowController {
  int _diagnosisGeneration = 0;
  int _phraseCandidateGeneration = 0;
  int _openWordGeneration = 0;

  Future<void> loadPhraseCandidates({
    required LocalApi? api,
    required Cue? cue,
    required LearningController learning,
    required bool Function() isMounted,
    required String? Function() currentCueId,
  }) async {
    final generation = ++_phraseCandidateGeneration;
    if (api == null || cue == null) {
      if (isMounted()) learning.setPhraseCandidates(const []);
      return;
    }
    try {
      if (isMounted() &&
          _isCurrentPhraseRequest(generation, cue.id, currentCueId())) {
        learning.setPhraseCandidates(const []);
      }
      final candidates = await api.phraseCandidates(cue.id);
      if (isMounted() &&
          _isCurrentPhraseRequest(generation, cue.id, currentCueId())) {
        learning.setPhraseCandidates(candidates);
      }
    } catch (_) {
      if (isMounted() &&
          _isCurrentPhraseRequest(generation, cue.id, currentCueId())) {
        learning.setPhraseCandidates(const []);
      }
    }
  }

  Future<void> loadWordEntries({
    required LocalApi? api,
    required SubtitleTrack? track,
    required String language,
    required LearningController learning,
    required bool Function() isMounted,
  }) async {
    final lemmas = track?.cues
        .expand((cue) => cue.tokens)
        .where((token) => token.kind == 'word' && token.normalized != null)
        .map((token) => token.normalized!)
        .toSet()
        .toList();
    // Background sync after a track or language change; a missing core or
    // track is not a user action, so silence is correct here.
    if (lemmas == null || api == null) return;
    final values = await api.readLexicalEntriesBatch(
      lemmas,
      language: language,
    );
    if (!isMounted()) return;
    final entries = Map<String, LexicalEntry>.fromEntries(
      values.map((entry) => MapEntry(entry.normalizedForm, entry)),
    );
    learning.setWordEntries(entries);
  }

  Future<void> loadPhraseEntries({
    required LocalApi? api,
    required String language,
    required LearningController learning,
    required bool Function() isMounted,
  }) async {
    // Background sync path, mirroring [loadWordEntries]: silence is correct.
    if (api == null) return;
    final values = await api.lexicalEntries(kind: 'phrase', language: language);
    if (!isMounted()) return;
    final entries = Map<String, LexicalEntryDetails>.fromEntries(
      values.map((details) => MapEntry(details.entry.normalizedForm, details)),
    );
    learning.setPhraseEntries(entries);
  }

  Future<void> openWord({
    required LocalApi? api,
    required SubtitleToken token,
    required Cue cue,
    required String language,
    required LearningController learning,
    required bool Function() isMounted,
    Map<String, dynamic>? Function(SubtitleToken token, Cue cue)? sourceFor,
  }) async {
    final lemma = token.normalized;
    if (lemma == null) return;
    final generation = ++_openWordGeneration;
    if (isMounted()) {
      learning.setSelectedToken(token);
      learning.setSelectedCue(cue);
      learning.selectWord(null);
      learning.selectSidePanel(2);
    }
    // User feedback for a missing core is owned by VocabularyActionsCoordinator,
    // which guards before delegating; this stays a pure workflow.
    if (api == null) return;
    final source = sourceFor?.call(token, cue);
    var entry = learning.wordEntries[lemma];
    if (entry == null) {
      final details = await api.upsertWordLexicalEntry(
        lemma,
        token.text,
        null,
        language: language,
        source: source,
      );
      entry = details.entry;
      if (!_isCurrentOpenWord(generation, isMounted)) return;
      learning.updateSingleWordEntry(lemma, entry);
      if (details.capabilityProfile != null) {
        learning.updateCapabilityProfile(lemma, details.capabilityProfile!);
      }
      learning.selectWord(details);
    } else {
      // Record the occurrence before reloading details, otherwise the
      // fire-and-forget write races the reload and the just-encountered source
      // sentence can be missing from the panel until the word is reopened.
      if (source != null) {
        try {
          await api.upsertWordLexicalEntry(
            lemma,
            token.text,
            null,
            language: language,
            source: source,
          );
        } catch (_) {}
      }
      if (!_isCurrentOpenWord(generation, isMounted)) return;
      learning.selectWord(LexicalEntryDetails(entry: entry));
      final details = await _loadExistingWordDetails(api, entry);
      if (!_isCurrentOpenWord(generation, isMounted)) return;
      entry = details.entry;
      learning.updateSingleWordEntry(lemma, entry);
      if (details.capabilityProfile != null) {
        learning.updateCapabilityProfile(lemma, details.capabilityProfile!);
      }
      learning.selectWord(details);
    }

    final dictionary = await _tryLoad(
      () => api.lookupDictionary(lemma, language: language),
    );
    if (dictionary != null && _isCurrentOpenWord(generation, isMounted)) {
      learning.setSelectedDictionary(dictionary);
    }

    final pronunciation = await _tryLoad(
      () => api.lookupPronunciation(token.text),
    );
    if (pronunciation != null && _isCurrentOpenWord(generation, isMounted)) {
      learning.setSelectedPronunciation(pronunciation);
    }

    if (learning.languageProfileFor(language) != null) return;
    final languageProfile = await _tryLoad(
      () => api.lookupLanguageProfile(language),
    );
    if (languageProfile != null && _isCurrentOpenWord(generation, isMounted)) {
      learning.setLanguageProfile(languageProfile);
    }
  }

  bool _isCurrentOpenWord(int generation, bool Function() isMounted) =>
      isMounted() && generation == _openWordGeneration;

  Future<LexicalEntryDetails> _loadExistingWordDetails(
    LocalApi api,
    LexicalEntry entry,
  ) async {
    try {
      return await api.lexicalEntryDetails(entry.id);
    } catch (_) {
      return LexicalEntryDetails(entry: entry);
    }
  }

  Future<T?> _tryLoad<T>(Future<T> Function() loader) async {
    try {
      return await loader();
    } catch (_) {
      return null;
    }
  }

  Future<LexicalEntryDetails?> markFirstWord({
    required LocalApi? api,
    required Cue? cue,
    required String? wordStatus,
    required String language,
    required LearningController learning,
    required bool Function() isMounted,
    required Map<String, dynamic>? Function(SubtitleToken token, Cue cue)
    sourceFor,
  }) async {
    if (cue == null || api == null) return null;
    final tokens = cue.tokens
        .where((value) => value.kind == 'word' && value.normalized != null)
        .toList(growable: false);
    final token = tokens.isEmpty ? null : tokens.first;
    if (token == null) return null;
    final details = await api.upsertWordLexicalEntry(
      token.normalized!,
      token.text,
      wordStatus,
      language: language,
      source: sourceFor(token, cue),
    );
    if (isMounted()) {
      learning.updateSingleWordEntry(token.normalized!, details.entry);
    }
    return details;
  }

  Future<LearningWordStatusUpdate?> setSelectedWordStatus({
    required LocalApi? api,
    required String? selected,
    required String language,
    required LearningController learning,
    required bool Function() isMounted,
    required Map<String, dynamic>? Function(SubtitleToken token, Cue cue)
    sourceFor,
  }) async {
    final token = learning.selectedToken;
    final cue = learning.selectedCue;
    if (token?.normalized == null || cue == null || api == null) return null;
    final details = await api.upsertWordLexicalEntry(
      token!.normalized!,
      token.text,
      selected,
      language: language,
      source: sourceFor(token, cue),
    );
    if (!isMounted()) return null;
    learning.updateSingleWordEntry(token.normalized!, details.entry);
    learning.selectWord(details);
    return LearningWordStatusUpdate(tokenText: token.text);
  }

  Future<void> saveSelectedLearningContent({
    required LocalApi? api,
    required String? definition,
    required String? note,
    required LearningController learning,
    required bool Function() isMounted,
  }) async {
    final entry = learning.selectedLexicalDetails?.entry;
    // Missing-core feedback is owned by VocabularyActionsCoordinator; a null
    // entry means no word is selected, which the editor UI already gates.
    if (entry == null || api == null) return;
    final details = await api.updateLexicalLearningContent(
      entry.id,
      userDefinition: definition,
      personalNote: note,
    );
    if (isMounted()) learning.selectWord(details);
  }

  Future<bool> observeSelected({
    required LocalApi? api,
    required bool heard,
    required LearningController learning,
    required Map<String, dynamic>? Function(SubtitleToken token, Cue cue)
    sourceFor,
  }) async {
    final token = learning.selectedToken;
    final cue = learning.selectedCue;
    final entry = learning.selectedLexicalDetails?.entry;
    if (token == null || cue == null || entry == null || api == null) {
      return false;
    }
    await api.createLexicalObservation(
      lexicalEntryId: entry.id,
      sentenceId: cue.id,
      originalForm: token.text,
      heard: heard,
      source: sourceFor(token, cue),
    );
    return true;
  }

  Future<void> setCapabilityOverride({
    required LocalApi? api,
    required String capability,
    required String? conclusion,
    required LearningController learning,
    required bool Function() isMounted,
    Map<String, dynamic>? Function(SubtitleToken token, Cue cue)? sourceFor,
  }) async {
    final entry = learning.selectedLexicalDetails?.entry;
    // Same ownership split as [saveSelectedLearningContent]: silence here,
    // feedback in the coordinator.
    if (entry == null || api == null) return;
    await api.setCapabilityOverride(
      entry.id,
      capability,
      conclusion: conclusion,
    );
    if (conclusion == 'not_acquired' && sourceFor != null) {
      final token = learning.selectedToken;
      final cue = learning.selectedCue;
      if (token?.normalized != null && cue != null) {
        final source = sourceFor(token!, cue);
        if (source != null) {
          // Awaited so the occurrence is persisted before the details fetch
          // below reflects it; wrapped so a failed occurrence write never
          // discards the capability override that already succeeded.
          try {
            await api.upsertWordLexicalEntry(
              token.normalized!,
              token.text,
              null,
              language: entry.language,
              source: source,
            );
          } catch (_) {}
        }
      }
    }
    final details = await api.lexicalEntryDetails(entry.id);
    if (!isMounted()) return;
    final lemma = entry.normalizedForm;
    learning.updateSingleWordEntry(lemma, details.entry);
    if (details.capabilityProfile != null) {
      learning.updateCapabilityProfile(lemma, details.capabilityProfile!);
    }
    learning.selectWord(details);
  }

  Future<void> refreshDiagnosis({
    required Cue? cue,
    required Future<Diagnosis> Function(String cueId) diagnose,
    required String? Function() currentCueId,
    required void Function(Diagnosis? diagnosis) setDiagnosis,
  }) async {
    final generation = ++_diagnosisGeneration;
    if (cue == null) {
      setDiagnosis(null);
      return;
    }
    try {
      final value = await diagnose(cue.id);
      if (_isCurrent(generation, cue.id, currentCueId())) {
        setDiagnosis(value);
      }
    } catch (_) {
      if (_isCurrent(generation, cue.id, currentCueId())) {
        setDiagnosis(null);
      }
    }
  }

  Future<void> recordCurrentSource({
    required LocalApi? api,
    required String language,
    required LearningController learning,
    required bool Function() isMounted,
    required Map<String, dynamic>? Function(SubtitleToken token, Cue cue)
    sourceFor,
  }) async {
    final token = learning.selectedToken;
    final cue = learning.selectedCue;
    // Same ownership split as [saveSelectedLearningContent]: silence here,
    // feedback in the coordinator.
    if (token?.normalized == null || cue == null || api == null) return;
    final source = sourceFor(token!, cue);
    if (source == null) return;
    final details = await api.upsertWordLexicalEntry(
      token.normalized!,
      token.text,
      null,
      language: language,
      source: source,
    );
    if (!isMounted()) return;
    learning.selectWord(details);
  }

  bool _isCurrent(int generation, String cueId, String? currentCueId) =>
      generation == _diagnosisGeneration && cueId == currentCueId;

  bool _isCurrentPhraseRequest(
    int generation,
    String cueId,
    String? currentCueId,
  ) => generation == _phraseCandidateGeneration && cueId == currentCueId;
}
