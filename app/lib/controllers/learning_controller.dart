import 'package:flutter/foundation.dart';

import '../models/timeline.dart';
import '../models/types.dart';
import '../state/store.dart';

const _unset = Object();

/// The two things the right-hand panel can be.
///
/// It used to be five: transcript, subtitle resources, word, diagnosis and
/// inbox, each replacing the others. That made the transcript one drawer among
/// five, so looking up a word or asking for an analysis took the text off
/// screen — the reader came back and had to find their place again. The
/// transcript is the floor of this workbench, not a drawer: word lookups now
/// open as a bubble over it and analysis expands inside the sentence, which
/// leaves exactly two panes worth switching between.
enum SidePanelTab {
  /// The interactive transcript. Resident: nothing replaces it.
  transcript,

  /// What this session has produced — the selected word in full, and the
  /// listening inbox.
  notes,
}

/// Immutable snapshot of learning-related state.
class LearningState {
  LearningState({
    Map<String, LexicalEntry> wordEntries = const {},
    Map<String, LexicalEntryDetails> phraseEntries = const {},
    Map<String, LexicalCapabilityProfile> capabilityProfiles = const {},
    this.selectedLexicalDetails,
    this.selectedDictionary,
    this.selectedPronunciation,
    this.selectedToken,
    this.selectedCue,
    List<PhraseCandidate> phraseCandidates = const [],
    this.diagnosis,
    this.tab = SidePanelTab.transcript,
    this.diagnosisExpanded = false,
  }) : _wordEntries = Map.unmodifiable(wordEntries),
       _phraseEntries = Map.unmodifiable(phraseEntries),
       _capabilityProfiles = Map.unmodifiable(capabilityProfiles),
       _phraseCandidates = List.unmodifiable(phraseCandidates);

  final Map<String, LexicalEntry> _wordEntries;
  final Map<String, LexicalEntryDetails> _phraseEntries;
  final Map<String, LexicalCapabilityProfile> _capabilityProfiles;
  final LexicalEntryDetails? selectedLexicalDetails;
  final DictionaryLookupBundle? selectedDictionary;
  final WordPronunciation? selectedPronunciation;
  final SubtitleToken? selectedToken;
  final Cue? selectedCue;
  final List<PhraseCandidate> _phraseCandidates;
  final Diagnosis? diagnosis;
  final SidePanelTab tab;

  /// Whether the current sentence's analysis is open inside the transcript.
  ///
  /// The analysis used to be a tab, which is why it could be "open" while the
  /// sentence it described was not on screen. Being an expansion of one
  /// sentence, it is a boolean about that sentence and nothing else.
  final bool diagnosisExpanded;

  Map<String, LexicalEntry> get wordEntries => Map.unmodifiable(_wordEntries);
  Map<String, LexicalEntryDetails> get phraseEntries =>
      Map.unmodifiable(_phraseEntries);
  Map<String, LexicalCapabilityProfile> get capabilityProfiles =>
      Map.unmodifiable(_capabilityProfiles);
  List<PhraseCandidate> get phraseCandidates =>
      List.unmodifiable(_phraseCandidates);

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
    SidePanelTab? tab,
    bool? diagnosisExpanded,
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
    tab: tab ?? this.tab,
    diagnosisExpanded: diagnosisExpanded ?? this.diagnosisExpanded,
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

  LearningController() : _store = Store(LearningState()) {
    _store.addListener(notifyListeners);
  }

  /// The reactive store — allows fine-grained field subscriptions.
  Store<LearningState> get store => _store;

  LearningState get state => _store.state;
  List<String> get availableLanguages => List.unmodifiable(_availableLanguages);
  LanguageProfile? get currentLanguageProfile => _currentLanguageProfile;
  LanguageProfile? languageProfileFor(String languageCode) =>
      _languageProfiles[languageCode];

  set availableLanguages(List<String> value) {
    _availableLanguages = List.unmodifiable(value);
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
  SidePanelTab get tab => _store.state.tab;
  bool get diagnosisExpanded => _store.state.diagnosisExpanded;
  SubtitleToken? get selectedToken => _store.state.selectedToken;
  Cue? get selectedCue => _store.state.selectedCue;

  void setWordEntries(Map<String, LexicalEntry> entries) =>
      _store.update((s) => s.copyWith(wordEntries: entries));

  void setPhraseEntries(Map<String, LexicalEntryDetails> entries) =>
      _store.update((s) => s.copyWith(phraseEntries: entries));

  /// Selecting a word no longer moves the panel. The lookup surfaces as a
  /// bubble anchored to the word in the transcript; the panel only follows
  /// when the reader explicitly asks for the full entry.
  void selectWord(LexicalEntryDetails? details) => _store.update(
    (s) => s.copyWith(
      selectedLexicalDetails: details,
      selectedDictionary: null,
      selectedPronunciation: null,
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

  void selectTab(SidePanelTab tab) =>
      _store.update((s) => s.copyWith(tab: tab));

  /// Opens or closes the analysis inside the current sentence. Collapsing does
  /// not discard [diagnosis]: re-opening the same sentence shows what was
  /// already loaded instead of asking for it again.
  void setDiagnosisExpanded(bool expanded) =>
      _store.update((s) => s.copyWith(diagnosisExpanded: expanded));

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
