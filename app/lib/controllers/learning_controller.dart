import 'package:flutter/foundation.dart';

import '../models/timeline.dart';

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
    Map<String, dynamic>? selectedWordDetails,
    Map<String, dynamic>? selectedDictionary,
    Map<String, dynamic>? selectedPronunciation,
    SubtitleToken? selectedToken,
    Cue? selectedCue,
    List<Map<String, dynamic>>? phraseCandidates,
    Map<String, dynamic>? diagnosis,
    int? sidePanel,
  }) =>
      LearningState(
        wordProfiles: wordProfiles ?? this.wordProfiles,
        phraseProfiles: phraseProfiles ?? this.phraseProfiles,
        selectedWordDetails: selectedWordDetails ?? this.selectedWordDetails,
        selectedDictionary: selectedDictionary ?? this.selectedDictionary,
        selectedPronunciation:
            selectedPronunciation ?? this.selectedPronunciation,
        selectedToken: selectedToken ?? this.selectedToken,
        selectedCue: selectedCue ?? this.selectedCue,
        phraseCandidates: phraseCandidates ?? this.phraseCandidates,
        diagnosis: diagnosis ?? this.diagnosis,
        sidePanel: sidePanel ?? this.sidePanel,
      );

  bool get hasDiagnosis => diagnosis != null;
  bool get hasWordSelected => selectedWordDetails != null;
}

/// Controls vocabulary learning state: word profiles, dictionary lookups,
/// phrase candidates, and sentence diagnosis.
class LearningController extends ChangeNotifier {
  LearningState _state = const LearningState();

  LearningState get state => _state;

  // Convenience accessors
  Map<String, Map<String, dynamic>> get wordProfiles => _state.wordProfiles;
  Map<String, Map<String, dynamic>> get phraseProfiles => _state.phraseProfiles;
  Map<String, dynamic>? get selectedWordDetails => _state.selectedWordDetails;
  Map<String, dynamic>? get selectedDictionary => _state.selectedDictionary;
  Map<String, dynamic>? get selectedPronunciation =>
      _state.selectedPronunciation;
  List<Map<String, dynamic>> get phraseCandidates => _state.phraseCandidates;
  Map<String, dynamic>? get diagnosis => _state.diagnosis;
  int get sidePanel => _state.sidePanel;
  SubtitleToken? get selectedToken => _state.selectedToken;
  Cue? get selectedCue => _state.selectedCue;

  void _update(LearningState Function(LearningState) fn) {
    _state = fn(_state);
    notifyListeners();
  }

  void setWordProfiles(Map<String, Map<String, dynamic>> profiles) =>
      _update((s) => s.copyWith(wordProfiles: profiles));

  void setPhraseProfiles(Map<String, Map<String, dynamic>> profiles) =>
      _update((s) => s.copyWith(phraseProfiles: profiles));

  void selectWord(Map<String, dynamic>? details) =>
      _update(
        (s) => s.copyWith(
          selectedWordDetails: details,
          selectedDictionary: null,
          selectedPronunciation: null,
          sidePanel: details != null ? 1 : s.sidePanel,
        ),
      );

  void setSelectedDictionary(Map<String, dynamic>? dict) =>
      _update((s) => s.copyWith(selectedDictionary: dict));

  void setSelectedPronunciation(Map<String, dynamic>? pron) =>
      _update((s) => s.copyWith(selectedPronunciation: pron));

  void setPhraseCandidates(List<Map<String, dynamic>> candidates) =>
      _update((s) => s.copyWith(phraseCandidates: candidates));

  void setDiagnosis(Map<String, dynamic>? diagnosis) =>
      _update((s) => s.copyWith(diagnosis: diagnosis));

  void selectSidePanel(int index) =>
      _update((s) => s.copyWith(sidePanel: index));

  void setSelectedToken(SubtitleToken? token) =>
      _update((s) => s.copyWith(selectedToken: token));

  void setSelectedCue(Cue? cue) =>
      _update((s) => s.copyWith(selectedCue: cue));

  void updateSingleWordProfile(
    String lemma,
    Map<String, dynamic> profile,
  ) {
    final profiles = Map<String, Map<String, dynamic>>.from(_state.wordProfiles);
    profiles[lemma] = profile;
    _update((s) => s.copyWith(wordProfiles: profiles));
  }

  void updateSinglePhraseProfile(
    String canonical,
    Map<String, dynamic> profile,
  ) {
    final profiles =
        Map<String, Map<String, dynamic>>.from(_state.phraseProfiles);
    profiles[canonical] = profile;
    _update((s) => s.copyWith(phraseProfiles: profiles));
  }

  void clearSelection() =>
      _update(
        (s) => s.copyWith(
          selectedWordDetails: null,
          selectedDictionary: null,
          selectedPronunciation: null,
        ),
      );

  /// Update the status of a word in the local cache.
  void updateWordStatusLocally(String lemma, String? status) {
    final profiles = Map<String, Map<String, dynamic>>.from(_state.wordProfiles);
    if (status == null) {
      profiles.remove(lemma);
    } else {
      profiles[lemma] = {
        ...?profiles[lemma],
        'status': status,
        'lemma': lemma,
      };
    }
    _update((s) => s.copyWith(wordProfiles: profiles));
  }
}
