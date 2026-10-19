/// How the listening channel's transcript is presented — the "reading states"
/// the reference product groups under its study-mode menu (阅读 / 盲听 / 选词).
///
/// These are *displays of the same transcript*, not separate surfaces, so they
/// live as render branches inside `TranscriptPanel` rather than opening a new
/// window. That is the whole point of typing them: the mode is one first-class
/// value the menu selects and the panel reads, instead of a string threaded
/// through callbacks.
///
/// The intensive states (single-sentence, cloze, dictation, shadowing) are a
/// different shape — they take over the pane as a focus surface — and are still
/// started through `PracticeActionsCoordinator`. They join this enum when P1
/// builds their full-cover shell; until then keeping them out means every value
/// here drives a real transcript render branch, none is a dead placeholder.
enum WorkbenchStudyMode {
  /// Read the transcript while listening — the resting display.
  normal,

  /// Hide the sentence text and go by ear; the current sentence can be revealed
  /// on demand. Seeking and scroll position are preserved because the rows stay
  /// laid out, only their text is redacted.
  blindListening,

  /// The current sentence, blanked, to be refilled from a pool of word choices.
  /// The pool and answers are a backend gap (see workbench-backend-gaps.md), so
  /// this mode currently renders an honest, unavailable placeholder rather than
  /// a fabricated exercise.
  wordSelection;

  bool get isBlind => this == WorkbenchStudyMode.blindListening;
  bool get isWordSelection => this == WorkbenchStudyMode.wordSelection;

  /// Whether the transcript shows its sentence text plainly. False in blind
  /// mode, where the text is redacted line by line.
  bool get showsPlainText => this == WorkbenchStudyMode.normal;
}
