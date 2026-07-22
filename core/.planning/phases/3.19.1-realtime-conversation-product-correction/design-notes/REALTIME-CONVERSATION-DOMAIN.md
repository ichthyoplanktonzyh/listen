# Realtime Conversation Domain Language

This glossary defines the user-owned realtime conversation facts shared by free and topic-anchored surfaces.

## Language

**Conversation Session**:
One continuous realtime conversation between the learner and a provider-backed assistant.
_Avoid_: Recording, attempt, learner turn

**Conversation Turn**:
One ordered learner or assistant contribution within a Conversation Session.
_Avoid_: Session, utterance file, response blob

**Learner Turn**:
A Conversation Turn spoken or explicitly entered by the learner.
_Avoid_: User session, provider caption

**Assistant Turn**:
A Conversation Turn produced by the realtime assistant.
_Avoid_: Feedback, learner output, production

**Provider Caption**:
Provider-originated text used as live guidance and correlation, without learner-output authority.
_Avoid_: Transcript, learner answer, local transcript

**Local Learner Transcript**:
Text produced from one Learner Turn's local recording by the bundled transcription path; when completed, it is the
text authority for learner output.
_Avoid_: Provider caption, conversation transcript

**Conversation History**:
The durable ordered set of Learner Turns and Assistant Turns belonging to one Conversation Session.
_Avoid_: Production Corpus, combined transcript

**Production Corpus**:
The rebuildable projection of finalized learner-owned output used by personal production search and Gap Review.
_Avoid_: Conversation History, assistant history

**Free Conversation**:
A Conversation Session started from a user-owned prompt or no topic context.
_Avoid_: Unbounded content selection

**Topic-anchored Conversation**:
A Conversation Session whose visible context is an explicit bounded content selection or explicit user-owned topic.
_Avoid_: Current playback conversation, whole-document inference

