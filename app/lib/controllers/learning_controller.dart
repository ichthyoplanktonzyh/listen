import 'package:flutter/foundation.dart';

import '../models/timeline.dart';
import '../state/store.dart';

const _unset = Object();

/// Immutable snapshot of learning-related state.
class LearningState {
  const LearningState({
    this.wordProfiles = const {},
    this.phraseProfiles = const {},
    this.selectedWordDetails,
    this.selectedDictionary,
    this.selectedPronunciation,
    this.selectedToken,
    this.selectedCue,
    this.phraseCandidates = const [],
    this.diagnosis,
    this.sidePanel = 0,
  });

  final Map<String, Map<String, dynamic>> wordProfiles;
  final Map<String, Map<String, dynamic>> phraseProfiles;
  final Map<String, dynamic>? selectedWordDetails;
  final Map<String, dynamic>? selectedDictionary;
  final Map<String, dynamic>? selectedPronunciation;
  final SubtitleToken? selectedToken;
  final Cue? selectedCue;
  final List<Map<String, dynamic>> phraseCandidates;
  final Map<String, dynamic>? diagnosis;
  final int sidePanel;

  LearningState copyWith({
    Map<String, Map<String, dynamic>>? wordProfiles,
    Map<String, Map<String, dynamic>>? phraseProfiles,
    Object? selectedWordDetails = _unset,
    Object? selectedDictionary = _unset,
    Object? selectedPronunciation = _unset,
    Object? selectedToken = _unset,
    Object? selectedCue = _unset,
    List<Map<String, dynamic>>? phraseCandidates,
    Object? diagnosis = _unset,
    int? sidePanel,
  }) => LearningState(
    wordProfiles: wordProfiles ?? this.wordProfiles,
    phraseProfiles: phraseProfiles ?? this.phraseProfiles,
    selectedWordDetails: identical(selectedWordDetails, _unset)
        ? this.selectedWordDetails
        : selectedWordDetails as Map<String, dynamic>?,
    selectedDictionary: identical(selectedDictionary, _unset)
        ? this.selectedDictionary
        : selectedDictionary as Map<String, dynamic>?,
    selectedPronunciation: identical(selectedPronunciation, _unset)
        ? this.selectedPronunciation
        : selectedPronunciation as Map<String, dynamic>?,
    selectedToken: identical(selectedToken, _unset)
        ? this.selectedToken
        : selectedToken as SubtitleToken?,
    selectedCue: identical(selectedCue, _unset)
        ? this.selectedCue
        : selectedCue as Cue?,
    phraseCandidates: phraseCandidates ?? this.phraseCandidates,
    diagnosis: identical(diagnosis, _unset)
        ? this.diagnosis
        : diagnosis as Map<String, dynamic>?,
    sidePanel: sidePanel ?? this.sidePanel,
  );

  bool get hasDiagnosis => diagnosis != null;
  bool get hasWordSelected => selectedWordDetails != null;
}

/// Controls vocabulary learning state: word profiles, dictionary lookups,
/// phrase candidates, and sentence diagnosis.
///
/// Uses [Store] internally for fine-grained reactive state.
class LearningController extends ChangeNotifier {
  final Store<LearningState> _store;
  List<String> _availableLanguages = const ['en', 'zh', 'ja'];
  final Map<String, Map<String, dynamic>> _languageProfiles = {};
  Map<String, dynamic>? _currentLanguageProfile;

  LearningController() : _store = Store(const LearningState()) {
    _store.addListener(notifyListeners);
  }

  /// The reactive store — allows fine-grained field subscriptions.
  Store<LearningState> get store => _store;

  LearningState get state => _store.state;
  List<String> get availableLanguages => _availableLanguages;
  Map<String, dynamic>? get currentLanguageProfile => _currentLanguageProfile;

  set availableLanguages(List<String> value) {
    _availableLanguages = value;
    notifyListeners();
  }

  /// Create a [ValueNotifier] that tracks a specific derived value.
  ValueNotifier<R> select<R>(R Function(LearningState) selector) =>
      _store.select(selector);

  // Convenience accessors
  Map<String, Map<String, dynamic>> get wordProfiles =>
      _store.state.wordProfiles;
  Map<String, Map<String, dynamic>> get phraseProfiles =>
      _store.state.phraseProfiles;
  Map<String, dynamic>? get selectedWordDetails =>
      _store.state.selectedWordDetails;
  Map<String, dynamic>? get selectedDictionary =>
      _store.state.selectedDictionary;
  Map<String, dynamic>? get selectedPronunciation =>
      _store.state.selectedPronunciation;
  List<Map<String, dynamic>> get phraseCandidates =>
      _store.state.phraseCandidates;
  Map<String, dynamic>? get diagnosis => _store.state.diagnosis;
  int get sidePanel => _store.state.sidePanel;
  SubtitleToken? get selectedToken => _store.state.selectedToken;
  Cue? get selectedCue => _store.state.selectedCue;

  void setWordProfiles(Map<String, Map<String, dynamic>> profiles) =>
      _store.update((s) => s.copyWith(wordProfiles: profiles));

  void setPhraseProfiles(Map<String, Map<String, dynamic>> profiles) =>
      _store.update((s) => s.copyWith(phraseProfiles: profiles));

  void selectWord(Map<String, dynamic>? details) => _store.update(
    (s) => s.copyWith(
      selectedWordDetails: details,
      selectedDictionary: null,
      selectedPronunciation: null,
      sidePanel: details != null ? 2 : s.sidePanel,
    ),
  );

  void setSelectedDictionary(Map<String, dynamic>? dict) =>
      _store.update((s) => s.copyWith(selectedDictionary: dict));

  void setSelectedPronunciation(Map<String, dynamic>? pron) =>
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
    final profile = await fetcher(languageCode);
    _languageProfiles[languageCode] = profile;
    _currentLanguageProfile = profile;
    notifyListeners();
  }

  void setPhraseCandidates(List<Map<String, dynamic>> candidates) =>
      _store.update((s) => s.copyWith(phraseCandidates: candidates));

  void setDiagnosis(Map<String, dynamic>? diagnosis) =>
      _store.update((s) => s.copyWith(diagnosis: diagnosis));

  void selectSidePanel(int index) =>
      _store.update((s) => s.copyWith(sidePanel: index));

  void setSelectedToken(SubtitleToken? token) =>
      _store.update((s) => s.copyWith(selectedToken: token));

  void setSelectedCue(Cue? cue) =>
      _store.update((s) => s.copyWith(selectedCue: cue));

  void updateSingleWordProfile(String lemma, Map<String, dynamic> profile) {
    final s = _store.state;
    final profiles = Map<String, Map<String, dynamic>>.from(s.wordProfiles);
    profiles[lemma] = profile;
    _store.update((st) => st.copyWith(wordProfiles: profiles));
  }

  void updateSinglePhraseProfile(
    String canonical,
    Map<String, dynamic> profile,
  ) {
    final s = _store.state;
    final profiles = Map<String, Map<String, dynamic>>.from(s.phraseProfiles);
    profiles[canonical] = profile;
    _store.update((st) => st.copyWith(phraseProfiles: profiles));
  }

  void clearSelection() => _store.update(
    (s) => s.copyWith(
      selectedWordDetails: null,
      selectedDictionary: null,
      selectedPronunciation: null,
    ),
  );

  /// Update the status of a word in the local cache.
  void updateWordStatusLocally(String lemma, String? status) {
    final s = _store.state;
    final profiles = Map<String, Map<String, dynamic>>.from(s.wordProfiles);
    if (status == null) {
      profiles.remove(lemma);
    } else {
      profiles[lemma] = {...?profiles[lemma], 'status': status, 'lemma': lemma};
    }
    _store.update((st) => st.copyWith(wordProfiles: profiles));
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }
}
