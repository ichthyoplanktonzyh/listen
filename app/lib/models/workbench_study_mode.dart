/// How the listening channel's transcript is presented.
///
/// These are *displays of the same transcript*, not separate surfaces, so they
/// live as render branches inside `TranscriptPanel` rather than opening a new
/// window. That is the whole point of typing them: the mode is one first-class
/// value the menu selects and the panel reads, instead of a string threaded
/// through callbacks.
///
/// The intensive states (single-sentence, cloze, dictation) are a
/// different shape — they take over the pane as a focus surface — and are still
/// started through `PracticeActionsCoordinator`. They join this enum when P1
/// builds their full-cover shell; until then keeping them out means every value
/// here drives a real transcript render branch, none is a dead placeholder.
enum WorkbenchStudyMode {
  /// Follow the transcript while listening — the resting display.
  normal,

  /// Hide the sentence text and go by ear; the current sentence can be revealed
  /// on demand. Seeking and scroll position are preserved because the rows stay
  /// laid out, only their text is redacted.
  blindListening;

  /// Whether the transcript shows its sentence text plainly. False in blind
  /// mode, where the text is redacted line by line.
  bool get showsPlainText => this == WorkbenchStudyMode.normal;
}
