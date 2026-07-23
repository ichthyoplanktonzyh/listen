import 'package:flutter/foundation.dart';

import '../models/timeline.dart';
import '../models/types.dart';
import '../state/store.dart';

const _unset = Object();

/// Immutable snapshot of learning-related state.
class LearningState {
  const LearningState({
    this.wordEntries = const {},
    this.phraseEntries = const {},
    this.capabilityProfiles = const {},
    this.selectedLexicalDetails,
    this.selectedDictionary,
    this.selectedPronunciation,
    this.selectedToken,
    this.selectedCue,
    this.phraseCandidates = const [],
    this.diagnosis,
    this.sidePanel = 0,
  });

  final Map<String, LexicalEntry> wordEntries;
  final Map<String, LexicalEntryDetails> phraseEntries;
  final Map<String, LexicalCapabilityProfile> capabilityProfiles;
  final LexicalEntryDetails? selectedLexicalDetails;
  final DictionaryLookupBundle? selectedDictionary;
  final WordPronunciation? selectedPronunciation;
  final SubtitleToken? selectedToken;
  final Cue? selectedCue;
  final List<PhraseCandidate> phraseCandidates;
  final Diagnosis? diagnosis;
  final int sidePanel;

  LearningState copyWith({
    Map<String, LexicalEntry>? wordEntries,
    Map<String, LexicalEntryDetails>? phraseEntries,
    Map<String, LexicalCapabilityProfile>? capabilityProfiles,
    Object? selectedLexicalDetails = _unset,
    Object? selectedDictionary = _unset,
    Object? selectedPronunciation = _unset,
    Object? selectedToken = _unset,
    Object? selectedCue = _unset,
    List<PhraseCandidate>? phraseCandidates,
    Object? diagnosis = _unset,
    int? sidePanel,
  }) => LearningState(
    wordEntries: wordEntries ?? this.wordEntries,
    phraseEntries: phraseEntries ?? this.phraseEntries,
    capabilityProfiles: capabilityProfiles ?? this.capabilityProfiles,
    selectedLexicalDetails: identical(selectedLexicalDetails, _unset)
        ? this.selectedLexicalDetails
        : selectedLexicalDetails as LexicalEntryDetails?,
    selectedDictionary: identical(selectedDictionary, _unset)
        ? this.selectedDictionary
        : selectedDictionary as DictionaryLookupBundle?,
    selectedPronunciation: identical(selectedPronunciation, _unset)
        ? this.selectedPronunciation
        : selectedPronunciation as WordPronunciation?,
    selectedToken: identical(selectedToken, _unset)
        ? this.selectedToken
        : selectedToken as SubtitleToken?,
    selectedCue: identical(selectedCue, _unset)
        ? this.selectedCue
        : selectedCue as Cue?,
    phraseCandidates: phraseCandidates ?? this.phraseCandidates,
    diagnosis: identical(diagnosis, _unset)
        ? this.diagnosis
        : diagnosis as Diagnosis?,
    sidePanel: sidePanel ?? this.sidePanel,
  );

  bool get hasDiagnosis => diagnosis != null;
  bool get hasWordSelected => selectedLexicalDetails != null;
}

/// Controls vocabulary learning state: lexical entries, dictionary lookups,
/// phrase candidates, and sentence diagnosis.
///
/// Uses [Store] internally for fine-grained reactive state.
class LearningController extends ChangeNotifier {
  final Store<LearningState> _store;
  List<String> _availableLanguages = const ['en', 'zh', 'ja'];
  final Map<String, LanguageProfile> _languageProfiles = {};
  LanguageProfile? _currentLanguageProfile;

  LearningController() : _store = Store(const LearningState()) {
    _store.addListener(notifyListeners);
  }

  /// The reactive store — allows fine-grained field subscriptions.
  Store<LearningState> get store => _store;

  LearningState get state => _store.state;
  List<String> get availableLanguages => _availableLanguages;
  LanguageProfile? get currentLanguageProfile => _currentLanguageProfile;
  LanguageProfile? languageProfileFor(String languageCode) =>
      _languageProfiles[languageCode];

  set availableLanguages(List<String> value) {
    _availableLanguages = value;
    notifyListeners();
  }

  /// Create a [ValueNotifier] that tracks a specific derived value.
  ValueNotifier<R> select<R>(R Function(LearningState) selector) =>
      _store.select(selector);

  // Convenience accessors
  Map<String, LexicalEntry> get wordEntries => _store.state.wordEntries;
  Map<String, LexicalEntryDetails> get phraseEntries =>
      _store.state.phraseEntries;
  Map<String, LexicalCapabilityProfile> get capabilityProfiles =>
      _store.state.capabilityProfiles;
  LexicalEntryDetails? get selectedLexicalDetails =>
      _store.state.selectedLexicalDetails;
  DictionaryLookupBundle? get selectedDictionary =>
      _store.state.selectedDictionary;
  WordPronunciation? get selectedPronunciation =>
      _store.state.selectedPronunciation;
  List<PhraseCandidate> get phraseCandidates => _store.state.phraseCandidates;
  Diagnosis? get diagnosis => _store.state.diagnosis;
  int get sidePanel => _store.state.sidePanel;
  SubtitleToken? get selectedToken => _store.state.selectedToken;
  Cue? get selectedCue => _store.state.selectedCue;

  void setWordEntries(Map<String, LexicalEntry> entries) =>
      _store.update((s) => s.copyWith(wordEntries: entries));

  void setPhraseEntries(Map<String, LexicalEntryDetails> entries) =>
      _store.update((s) => s.copyWith(phraseEntries: entries));

  void selectWord(LexicalEntryDetails? details) => _store.update(
    (s) => s.copyWith(
      selectedLexicalDetails: details,
      selectedDictionary: null,
      selectedPronunciation: null,
      sidePanel: details != null ? 2 : s.sidePanel,
    ),
  );

  void setSelectedDictionary(DictionaryLookupBundle? dict) =>
      _store.update((s) => s.copyWith(selectedDictionary: dict));

  void setSelectedPronunciation(WordPronunciation? pron) =>
      _store.update((s) => s.copyWith(selectedPronunciation: pron));

  Future<void> loadLanguageProfile(
    String languageCode,
    Future<Map<String, dynamic>> Function(String) fetcher,
  ) async {
    if (_languageProfiles.containsKey(languageCode)) {
      _currentLanguageProfile = _languageProfiles[languageCode];
      notifyListeners();
      return;
    }
    final profile = LanguageProfile.fromJson(await fetcher(languageCode));
    _languageProfiles[languageCode] = profile;
    _currentLanguageProfile = profile;
    notifyListeners();
  }

  void setLanguageProfile(LanguageProfile profile) {
    _languageProfiles[profile.languageCode] = profile;
    _currentLanguageProfile = profile;
    notifyListeners();
  }

  void setPhraseCandidates(List<PhraseCandidate> candidates) =>
      _store.update((s) => s.copyWith(phraseCandidates: candidates));

  void setDiagnosis(Diagnosis? diagnosis) =>
      _store.update((s) => s.copyWith(diagnosis: diagnosis));

  void selectSidePanel(int index) =>
      _store.update((s) => s.copyWith(sidePanel: index));

  void setSelectedToken(SubtitleToken? token) =>
      _store.update((s) => s.copyWith(selectedToken: token));

  void setSelectedCue(Cue? cue) =>
      _store.update((s) => s.copyWith(selectedCue: cue));

  void updateSingleWordEntry(String lemma, LexicalEntry entry) {
    final s = _store.state;
    final entries = Map<String, LexicalEntry>.from(s.wordEntries);
    entries[lemma] = entry;
    _store.update((st) => st.copyWith(wordEntries: entries));
  }

  void updateCapabilityProfile(
    String normalizedForm,
    LexicalCapabilityProfile profile,
  ) {
    final profiles = Map<String, LexicalCapabilityProfile>.from(
      _store.state.capabilityProfiles,
    );
    profiles[normalizedForm] = profile;
    _store.update((s) => s.copyWith(capabilityProfiles: profiles));
  }

  void updateSinglePhraseEntry(String canonical, LexicalEntryDetails details) {
    final s = _store.state;
    final entries = Map<String, LexicalEntryDetails>.from(s.phraseEntries);
    entries[canonical] = details;
    _store.update((st) => st.copyWith(phraseEntries: entries));
  }

  void clearSelection() => _store.update(
    (s) => s.copyWith(
      selectedLexicalDetails: null,
      selectedDictionary: null,
      selectedPronunciation: null,
    ),
  );

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }
}
