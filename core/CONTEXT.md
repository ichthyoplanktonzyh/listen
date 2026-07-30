# Listen Language Learning Context

Listen turns real, language-bearing content into bounded learning activities,
traceable learning facts, and user-directed next actions. This glossary names
the concepts that must remain consistent across languages and across listening,
reading, speaking, and writing.

## Learner Intent

**Learner**:
The person whose activities, evidence, capabilities, assets, and decisions form
one learning history.
_Avoid_: Account, profile

**Learning Goal**:
A learner-owned statement of where or why the learner wants to use a language;
it guides recommendations but is not evidence of capability.
_Avoid_: Capability, course level

## Content And Context

**Content Document**:
A learnable whole that binds a media work and its identity to at least one
language-bearing text track with provenance; source availability is separate.
_Avoid_: Media file, subtitle resource, task input

**Subtitle Text Track**:
A timed, language-bearing text component of a Content Document with its own
source provenance.
_Avoid_: Standalone learning destination, analysis result

**Content Selection**:
An explicit, bounded, snapshot-stable part of a Content Document chosen as the
source of one activity; it may contain one sentence, several sentences, or a
passage.
_Avoid_: Current content, whatever is playing, implicit context

**Playback Context**:
The document, cursor, and playback state currently open to the learner. It may
help create a Content Selection but is not itself a task input.
_Avoid_: Content Selection, task source

**Source Snapshot**:
An immutable historical explanation of what a learning fact referred to. It
preserves context after source loss but does not make missing media available.
_Avoid_: Playable source, replacement media

**Sentence Exemplar**:
A concrete sentence in retained context that may exemplify one or more
language patterns; identical wording from another context is another exemplar.
_Avoid_: Construction, canonical sentence

**Task Prompt**:
The stable instructions and source snapshot presented for one activity,
derived from a Content Selection or a user-owned asset.
_Avoid_: Current sentence, live player state

## Learning Objects

**Learning Object**:
A conceptual family of things about which a learner can build capability. Its
members do not share one identity, authority, or lifecycle merely by belonging
to the family.
_Avoid_: Universal learning item, generic target record

**Lexical Unit**:
A language-relative vocabulary identity with an explicit granularity, such as
character, morpheme, word, or phrase, and a language-appropriate normalization.
_Avoid_: Token, subtitle word, collection

**Listening Phenomenon**:
An audible target in real speech, such as a phone contrast, reduction,
connected-speech event, boundary, stress pattern, or prosodic group.
_Avoid_: Lexical Unit, text chunk

**Construction**:
A language-scoped, versioned form–meaning–communicative-function abstraction
whose identity is not inferred from a single sentence.
_Avoid_: Sentence Exemplar, parse tree, User Sentence Pattern

**Construction Occurrence**:
A provenanced annotation that locates one Construction in one Sentence
Exemplar; it may overlap or nest with other occurrences.
_Avoid_: Construction, personal pattern

**Construction Occurrence Proposal**:
A replaceable, provenance-bearing suggestion that one Sentence Exemplar
instantiates one Construction. It may be confirmed or rejected but cannot mint
Construction identity or become learner authority by itself.
_Avoid_: Construction Occurrence, canonical Construction, capability evidence

**User Sentence Pattern**:
A versioned, learner-owned expression template retained with its source
snapshot; a Construction link may explain it but never owns or renames it.
_Avoid_: Canonical Construction, automatic projection

**Archived User Sentence Pattern**:
A User Sentence Pattern withdrawn from active reuse while its identity,
immutable versions, uses, source snapshots, and historical meaning remain.
_Avoid_: Deleted pattern, erased content, inactive version

**Personal Content Erasure**:
An explicit, irreversible removal of learner-owned content across every
declared authoritative and derived representation within a stated scope.
_Avoid_: Archive, ordinary pattern removal, hidden content

**Sense Group**:
A contiguous semantic processing span in sentence text.
_Avoid_: Prosodic Chunk, reusable phrase

**Prosodic Chunk**:
A span grouped by how a speaker organized the speech signal.
_Avoid_: Sense Group, phrase

**Collection**:
A learner-facing organizational container for references to learning objects;
membership does not create a new linguistic object.
_Avoid_: Phrase, Lexical Unit, capability

**Analysis Resource**:
A replaceable, provenance-bearing analysis derived from a Content Document,
such as word timing, sound grouping, syntax, or rhythm structure.
_Avoid_: Subtitle Text Track, learner history, user authority

**Derived Explanation**:
A learner-facing interpretation built from source facts or an Analysis
Resource, with its uncertainty and provenance retained.
_Avoid_: Source truth, learner fact, canonical identity

## Activity And Performance

**Learning Activity**:
A bounded undertaking with a learning purpose, a channel, and an explicit
source or user-owned prompt.
_Avoid_: Feature, screen, queue

**Attempt**:
One completed or explicitly abandoned undertaking of one Learning Activity,
including the conditions and assistance present at the time.
_Avoid_: Capability, score, session

**Performance**:
The learner-produced response or behavior within an Attempt.
_Avoid_: Judgment, capability

**Assistance**:
A factual snapshot of support available during an Attempt, including visible
text, keywords, structural hints, reconstruction, imitation, or model help.
_Avoid_: Difficulty, capability, universal assistance score

**Learning Session**:
A recoverable learner-perceived sequence of related activities around a goal,
posture, and content scope.
_Avoid_: Practice Attempt, Realtime Conversation, universal event container

**Constructed Speaking Task**:
A bounded speaking activity with one Task Prompt and learner response, such as
retelling or pattern production.
_Avoid_: Realtime Conversation, conversation turn

**Personal Expression Use**:
One completed use of one immutable User Sentence Pattern version with its
channel, assistance, response, and learner self-assessment. A speaking use
references the Constructed Speaking Task that owns the prompt, recording, and
corrected transcript; it is not a second transcript authority and is not
qualified Construction evidence by itself.
_Avoid_: Duplicate speaking attempt, automatic capability conclusion

**Realtime Conversation**:
One continuous free or topic-anchored interaction made of ordered learner and
assistant turns, without a fixed expected answer.
_Avoid_: Constructed Speaking Task, role exercise

**Conversation History**:
The durable ordered learner and assistant turns from a Realtime Conversation.
_Avoid_: Production Corpus, combined learner answer

**Production Corpus**:
A rebuildable view of finalized learner-owned output; assistant output is not
learner production.
_Avoid_: Conversation History, evidence authority

## Evidence And Authority

**Observation**:
A target- and channel-specific record of what happened in one context,
including outcome, assistance, and source.
_Avoid_: Capability, projection

**Evidence**:
An observation or other retained performance fact that satisfies an explicit
qualification rule for a stated conclusion.
_Avoid_: Any event, score, truth

**Judgment**:
A provenanced verdict over one Performance or one rubric point; it does not by
itself declare durable capability.
_Avoid_: Evidence qualification, Projection, Capability

**Judgment Adjudication**:
A learner confirmation or correction of one assertion in a Judgment.
_Avoid_: Capability override, judgment mutation

**Projection Proposal**:
A versioned, explainable system recommendation for one capability conclusion,
derived from qualified evidence and awaiting a User Decision.
_Avoid_: Capability, automatic truth

**User Decision**:
A learner confirmation or rejection of a Projection Proposal; it changes only
the authority explicitly attached to that proposal.
_Avoid_: User Override, Judgment Adjudication

**User Override**:
An explicit learner declaration for one object and capability dimension that
outranks a system projection without deleting its evidence.
_Avoid_: Proposal confirmation, corrected judgment

**Effective Capability**:
The current read of a learner–object capability relation: a User Override when
present, otherwise the current system projection, otherwise unassessed. New
evidence-derived conclusions require the applicable confirmation authority.
_Avoid_: Latest attempt, raw score, legacy status

## Capability And Channel

**Capability**:
An assessed relation between a Learner and a Learning Object in a stated
direction or modality.
_Avoid_: Property of the object, runtime feature support

**Channel**:
The modality through which an activity, Attempt, observation/evidence, or
capability relates the learner to an object: listening, reading, speaking, or
writing where applicable.
_Avoid_: Learning Object kind, product section

**Receptive Capability**:
The ability to recognize and interpret a Learning Object through an available
receptive channel.
_Avoid_: Listening only, recognition event

**Productive Capability**:
The ability to use a Learning Object through an available productive channel.
_Avoid_: Speaking only, production event

**Unassessed**:
The absence of a current capability conclusion.
_Avoid_: Not acquired, failure

## Next Actions

**Gap**:
An explainable mismatch among assessed capabilities, qualified evidence, or a
Learning Goal that may motivate a next action.
_Avoid_: Missing data, unassessed capability, failure

**Learning Agenda**:
A learner-facing aggregation of a small number of executable next actions
while each source keeps its own identity and authority.
_Avoid_: Universal queue, task manager

**Agenda Item**:
One explainable next-action view with a reason, action, scope, availability,
and reference back to its authoritative source.
_Avoid_: New learning object, copied queue record

**Review Queue**:
A schedule of due or available review activities for existing review items.
_Avoid_: Learning Agenda, deck of language objects

**Listening Inbox**:
Captured listening difficulties awaiting an explicit resolution.
_Avoid_: Learning Agenda, subtitle folder

**Hunting Target**:
A learner-confirmed intention to notice or test a language target in new
content contexts.
_Avoid_: Review failure, generic bookmark

## Availability

**Availability**:
Whether a source or resource can currently support a requested operation.
_Avoid_: Learning readiness, capability, quality

**Activity Readiness**:
Whether the available source, resources, and permissions are sufficient for
one specified Learning Activity and learner goal.
_Avoid_: Availability, general installation state

**Unavailable State**:
A condition where the requested activity cannot be performed because a
required source, analysis, channel support, or permission is absent. It names
the blocking reason and a concrete recovery path without pretending the
activity occurred.
_Avoid_: Silent fallback, generic error, source snapshot as live availability

**Fallback**:
An alternate path that preserves the same learner goal and authority semantics
when the preferred path is unavailable. If the learning goal, requested
channel, or evidence meaning changes, it is a different activity.
_Avoid_: Any degraded screen, substitute goal, changed evidence semantics
