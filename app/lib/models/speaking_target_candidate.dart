/// A saved lexical item detected in the learner's speaking attempt.
///
/// This is an immutable presentation model shared by the speaking coordinator
/// and its view. It deliberately contains no widget or rendering concerns.
class SpeakingTargetCandidate {
  const SpeakingTargetCandidate({
    required this.lexicalEntryId,
    required this.surfaceForm,
  });

  final String lexicalEntryId;
  final String surfaceForm;
}
