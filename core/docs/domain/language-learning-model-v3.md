# Language Learning Domain Model v3

Status: current domain map for [core issue #81](https://github.com/ichthyoplanktonzyh/listen-core/issues/81), based on `origin/main` at `9027157`.

This document connects the language-learning vocabulary in
[`CONTEXT.md`](../../CONTEXT.md) to the facts that exist in Rust and OpenAPI.
It is not a migration plan and does not make future concepts into published
contracts.

## Model spine

```text
Learner + Learning Goal
        ↓
Content Document → Content Selection
        ↓
Learning Activity → Attempt → Performance
        ↓
Observation and/or Judgment
        ↓ explicit qualification
Evidence
        ↓
Projection Proposal → User Decision
        ↓                         ↑
Effective Capability ← optional User Override
        ↓
Gap → Learning Agenda → next Learning Activity
```

The arrows describe responsibility, not a requirement that every activity
write every later fact. An activity may end with only an Attempt. A Judgment is
not automatically qualified Evidence. A Projection Proposal is not capability
until the appropriate user decision and projection write occur.

## Language-general core and language variation

The model is language-general inside Listen's current product envelope:
second-language learning from voiced media with a language-bearing text track.
The following boundaries do not depend on English:

- bounded content and task inputs;
- separate object identities and learner capability relations;
- activity, attempt, performance, evidence, judgment, projection, and user
  authority;
- receptive/productive direction and provenance-preserving history;
- gaps and next-action aggregation.

Language structure remains parameterized. `LanguageLearningProfile` declares
open tokenization, lexical granularity, normalization, listening-unit,
pronunciation, sound-feature, rhythm/prosody, morphology, and diagnosis-reason
kinds. Unknown or unsupported capabilities degrade explicitly. The code
currently has English, Mandarin Chinese, and Japanese profiles.

Listening/reading/speaking/writing are the current evidence modalities and the
four independent lexical capability dimensions. They are not a universal
ontology for every possible language or learning object. Construction evidence
retains those four modalities while its spike-level capability summary is
recognition/production. A future object may expose only the channels that make
sense for it; no cross-channel implication is assumed.

This means the core is language-pluggable, not language-structure-free. A
language still needs appropriate segmentation, normalization, pronunciation,
speech, construction, and diagnosis behavior. Signed-language learning,
text-only material, and languages outside the current voiced-media envelope
would require an explicit product and contract extension.

## Content, exemplar, and object boundaries

### Content Document and Content Selection

`ContentDocument` is the learnable whole. Today it is a domain composition, not
a Rust aggregate or OpenAPI schema: `MediaItem` owns the media work/identity
and availability facts, `SubtitleTrack` owns a provenanced text component, and
timelines/analyses are replaceable enrichments. A missing or archived media
source does not erase the document's retained text, snapshots, or learner
history. A media file by itself is therefore only one component of a Content
Document.

There is no domain-authoritative “active SubtitleTrack”.
`MediaLibraryEntry.primary_track_id` is a derived default, and the client may
select another available track in its current context. The text track is part
of the document; word/chunk/phone/sense-group/syntax/rhythm outputs are
Analysis Resources rather than peer document components.

`ContentSelection` is the explicit, bounded task input. Today its facts are
repeated in purpose-specific snapshots:

- `RubricSource` carries media/track context, time bounds, language, and
  transcript snapshot;
- `PracticeTarget` and `PracticeAnchor` carry target and range anchors, while
  `PracticeItem.prompt_snapshot` freezes the prompt;
- `PatternSourceSnapshot` carries source text and optional navigation bounds;
- `PlayableSegment` carries availability for bounded playback.

These shapes prove the concept but do not yet form one canonical
`ContentSelection` wire type. `PlaybackContext`, a sentence ID, or “from the
current cursor onward” must not silently substitute for a selection.

### Sentence, exemplar, and selection

- `SubtitleSentence` is a cue-derived text/time unit inside a track.
- `SentenceExemplar` is a concrete sentence plus retained source context used
  to exemplify a reusable pattern. The same wording in another source is a
  different exemplar.
- `ContentSelection` is the bounded input to one activity and may contain less
  than, exactly, or more than one sentence.

They are related, but none is an alias for another.

### Learning Object is a concept family

The family intentionally has no universal parent identity:

| Member | Identity and authority | Current status |
|---|---|---|
| `LexicalUnit` | Language + granularity + opaque normalized key; a phrase is lexical granularity | Production Rust, persistence, and OpenAPI through `LexicalEntry.unit` |
| `ListeningPhenomenon` | Audible occurrence or contrast anchored in speech/time evidence | Conceptual family over word/chunk/phone timelines, sound analysis, connected speech, rhythm, and listening hotspots; no single type |
| `Construction` | Current spike identity is language + curator-owned key + schema version; stable identity versus immutable definition revision remains an explicit #80 decision | Pure domain spike and gold fixture only; no production persistence or OpenAPI |
| `UserSentencePattern` | Learner-owned asset with immutable versions and source snapshot | Production Rust, persistence, CRUD/search/version history, export, and OpenAPI |

`ConstructionOccurrence` is a rebuildable analysis of an exemplar and may
overlap or nest. `UserSentencePattern` is durable user authority and may carry
an optional Construction link, but the link cannot rename it or become a
creation prerequisite.

This model constrains the future #80 lifecycle: an automatic matcher may create
only a replaceable Construction Occurrence Proposal. The proposed confirmed
occurrence read combines a proposal with a durable user or curator decision;
parser output cannot mint Construction identity or become learner authority by
itself. #80 must finalize that lifecycle and record an ADR if its authority
choice is hard to reverse.

The current production User Sentence Pattern link is an optional opaque
`ConstructionId` stored in the pattern-version JSON. Existence, same-language
validity, and an exact Construction revision are not yet enforceable and belong
to #80.

`Phrase` is a `LexicalUnit` granularity. `Collection`, folder, deck, and list
are organizational concepts. Current `LexicalSenseFolder` groups occurrences
by a learner-managed sense label, and imported Anki decks organize scheduling;
neither turns its membership into a new phrase or other language object. There
is no general-purpose Collection contract today.

`SenseGroup` and `Prosodic Chunk` also stay separate: the former is a semantic
text span, while the latter represents organization in the speech signal.
Neither becomes a reusable lexical phrase merely because it spans words.

## Activity, fact, and authority layers

### Authority map

| Layer | Owns | Current examples | Replacement rule |
|---|---|---|---|
| Document facts | Media work/identity, availability, and provenanced text components | `MediaItem`, `SubtitleTrack`, `SubtitleSentence` | Source loss changes availability; it does not rewrite retained learning history |
| Durable learner facts | What the learner did, produced, observed, corrected, or explicitly decided | Attempts/responses, `LearningObservation`, adjudications, proposal decisions, capability history, User Sentence Pattern versions | Preserve independently of replaceable analyses; append or version where the concrete lifecycle guarantees it |
| Derived Analysis Resource | Replaceable interpretation of content or speech | Word/Chunk/Phone timelines, `SenseGroupAnalysis`, syntactic analysis, sound/rhythm analysis; future `ConstructionOccurrence` proposals | Rebuild with provenance; replacement must not delete learner facts |
| Projection/read layer | Versioned conclusions and query-oriented interpretations | `CapabilityProjection`, `ProjectionProposal`, production corpus, semantic embedding index, content-fit/gap views | Recompute by version where allowed; append audit-relevant proposal/history and never rewrite learner facts |
| User authority | Explicit learner intent, ownership, correction, or exception | User Sentence Pattern, capability override, proposal decision, judgment adjudication, explicit content triage; future Learning Goal | Automatic analysis may suggest but cannot silently overwrite |

One current lifecycle conflicts with the target durability boundary:
hard-deleting a User Sentence Pattern cascades to its versions and Personal
Expression attempts. ADR 0035 deprecates that legacy operation in favor of
archive/restore. Archive preserves the pattern identity, immutable versions,
uses, source snapshots, and historical explanations; it is not privacy
erasure. The published DELETE operation must retain its documented legacy
meaning during a compatibility window rather than silently becoming archive or
erasure, then be removed through an explicit breaking contract migration.

`LLTimelineDocument` is a versioned interchange envelope that can carry text
segments and several Analysis Resources. It is not a separate Learning Object
or the domain authority for a Content Document. Import validates the complete
document before writing, then commits the source identity when needed, text
track, carried resources, active selections, and corpus projection in one
transaction. A failed resource write or projection rebuild therefore leaves no
partial import. Detached imports use a synthetic `lltimeline://` media identity
marked unavailable until explicitly attached to registered media.

Derived Explanations translate source facts or Analysis Resources into
learner-facing meaning. They may be regenerated or withdrawn as analysis
changes and do not become learner facts unless the learner performs a separate,
explicitly modeled action.

Removing a technical resource destination from ordinary product navigation
does not remove backend authority or lifecycle controls. Analysis Resources
retain their existing lifecycle surfaces for provenance, rebuild, diagnostics,
and contextual recovery, plus import/export where currently supported; they
simply are not peer learning destinations.

Availability is also not goal-relative readiness. A source can be available
while a requested activity is not ready because it lacks a valid selection,
required analysis, permission, or channel support. Conversely, a Source
Snapshot may keep history explainable while the media operation remains
unavailable. A future goal-relative readiness read should name the requested
activity and distinguish `ready`, `preparing`, `unavailable`, `degraded`, and
`failed`, with a reason, progress where relevant, and concrete recovery
actions. `degraded` is valid only when the same goal, channel, and authority
semantics remain intact. `MediaAvailability`, `SubtitleTrackStatus`,
`TimelineStatus`, and `LearningResourceState` remain source-specific facts,
not aliases for Activity Readiness.

### Activity and attempt families

`LearningActivity` and `Attempt` are ubiquitous-language families, not proposed
base tables. Current concrete families preserve different invariants:

| Activity family | Attempt/performance fact | Outcome boundary |
|---|---|---|
| Deterministic practice | `PracticeItem` → `PracticeAttempt` | Task result/evaluation; qualified lexical anchors may write `LearningObservation` |
| Semantic reading/speaking/writing | `SemanticRubric` → `SemanticTaskAttempt` + `AttemptResponse` | Attempt completes or is abandoned; semantic outcome belongs to `SemanticJudgment` |
| Scheduled review | `ReviewItem` → `ReviewAttempt` | Rating and schedule transition; may write channelized observation and hunting candidate |
| Personal expression | `UserSentencePatternVersion` → `PersonalExpressionAttempt` | Immutable use plus learner self-assessment; not capability evidence by itself |
| Realtime conversation | `RealtimeConversationSession` → ordered turns | Conversation facts and learner-output corpus; not a fixed-answer task |

A speaking Personal Expression use references the Pattern Production semantic
attempt that owns its prompt, recording, and transcript. Construction MVP must
reuse that performance rather than create a parallel production attempt.

`LearningSession` is currently a future user-journey concept. Existing
`PracticeSession`, extensive-listening session facts, semantic attempts, and
realtime sessions are narrower and must not be renamed or physically merged.
A future contract request needs only enough information to restore:

- learner goal or entry reason when one was explicitly chosen;
- posture/channel and activity stage;
- Content Document plus bounded Content Selection, or a user-owned prompt;
- assistance snapshot and the authoritative concrete activity/attempt refs;
- started, resumable, completed, cancelled, unavailable, and source-loss
  semantics;
- one explainable next action at closeout.

It does not require a universal session/event table.

### Evidence and judgment

The current factual layers are:

1. **Attempt/performance facts** — what the learner did and under what
   conditions.
2. **Observation facts** — `LearningObservation` is append-only,
   lexical-targeted, channelized, assistance-aware, and source-referenced.
3. **Automatic interpretation** — `SemanticJudgment` records a fully
   provenanced per-point verdict or abstain over one response revision.
4. **User correction of interpretation** — `JudgmentAdjudication` appends a
   correction without rewriting the judgment.
5. **Evidence qualification** — an explicit, versioned rule determines which
   retained observation, performance, judgment, or adjudication facts support
   one stated conclusion. Retention alone is not qualification.
6. **Projection proposal** — `ProjectionProposal` explains a versioned
   capability conclusion from qualified observations.
7. **User decision** — `ProjectionDecision` confirms or rejects the proposal.
8. **Capability state** — the current projection and optional
   `CapabilityOverride` remain separate; override wins only in the effective
   read. Legacy, imported, and historical pre-confirmation projections remain
   explicit compatibility facts, while new evidence-derived proposals use the
   confirmation gate.

Therefore:

```text
Attempt != Observation
Observation != automatically qualified Evidence
Evidence != Judgment
Judgment Adjudication != Capability Override
Projection Proposal != Effective Capability
```

`unassessed` means no current conclusion. It never means `not_acquired`.

### Capability and channel

Channel is a relation in an activity, observation, or capability; it is not a
kind of Learning Object.

- Lexical capability uses independent reading, listening, speaking, and writing
  dimensions.
- Receptive direction is expressed through reading/listening evidence where
  available.
- Productive direction is expressed through speaking/writing evidence where
  available.
- Construction spike capability summarizes recognition/production but retains
  evidence modality, so the summary does not erase the channel facts.
- `ProductionChannel` and `PersonalExpressionChannel` cover productive output
  provenance; they do not replace lexical capability dimensions.

The word `capability` is also used for runtime/provider availability in code
and OpenAPI. In product-domain discussion, qualify that as **runtime
capability** or **provider capability**; unqualified **Capability** means the
learner–object relation.

### Assistance

Assistance is an attempt condition and provenance fact, not a capability
score. Existing types preserve different factual distinctions:

| Current type | Facts retained |
|---|---|
| `AssistanceLevel` | none, partial text, full text for lexical observations |
| `SpeakingAssistanceLevel` | full sentence, keywords, no text |
| `PersonalExpressionAssistance` | template visible, slot hints, keywords, no text |
| `ProductionAssistance` | content anchored, reconstruction, learner revision, explicit target, model suggested, direct imitation, unknown |
| `SemanticTaskConditions` | source visibility, replay count, notes, recall timing, and prompt snapshot |

A shared Assistance Ladder may merge their presentation, but must not collapse
direct imitation, source reconstruction, model help, and independent production
into a false total order. Historical attempts keep the source-specific factual
snapshot.

## Gap and Learning Agenda

`Gap` is a read interpretation over assessed capabilities, evidence, or a
learner goal. Current examples are `CrossModalReviewCandidate`,
`ProductionGapReview`, and semantic production-gap enrichment. Missing evidence
and `unassessed` are not gaps by themselves.

`LearningAgenda` is a future client-facing aggregate, not a new queue identity.
Its current authoritative sources include:

| Source | Authority and lifecycle to preserve |
|---|---|
| `ReviewItem` / `ReviewSchedule` | Due scheduling, suspension/archive, and attempt-driven schedule transitions |
| `ListeningInboxItem` | Captured difficulty and explicit resolution |
| `HuntingCandidate` / `HuntingTarget` | Failure-derived candidate versus learner-confirmed new-context target |
| `UpgradeSuggestion` | Legacy recognition-upgrade proposal and accept/reject lifecycle |
| `ProjectionProposal` | Channel capability proposal, evidence refs, and confirm/reject lifecycle |
| `CrossModalReviewCandidate` | Read-only gap recommendation from effective capability |
| `ProductionGapReview` | Read-only receptive-to-productive candidate ranking |
| Coach suggestion views | Explainable recommendation over existing facts |

A minimal Agenda item needs a source kind/ref, learner-facing reason, action
kind, target/channel, estimated scope, source availability, immutable
explanation snapshot, and return context. `open`, `defer`, `dismiss`,
`complete`, or `decide` commands must route to the source that owns that
lifecycle. Agenda does not copy those states into a universal record, and the
same underlying fact should be deduplicated in presentation.

## Rust and OpenAPI mapping

| Domain term | Current Rust fact(s) | Current OpenAPI schema(s) | Classification |
|---|---|---|---|
| Learner | Narrow single-user `LearnerProfile` settings fact; no complete Learner identity/aggregate | No schema | Current implicit ownership scope plus a limited profile |
| Learning Goal | No type | No schema | Future user authority requested by app #73 |
| Content Document | Conceptually `MediaItem` + at least one language-known `SubtitleTrack`; optional analysis resources | `MediaItem`, `MediaLibraryEntry`, `SubtitleTrack` | Composite concept; no first-class aggregate or enforced invariant prevents media-only rows or language-null tracks |
| Subtitle Text Track | `SubtitleTrack`, `SubtitleSentence`, `SubtitleToken` | Same named schemas | Document text component, not a derived analysis |
| Analysis Resource | Word/Chunk/Phone timelines, `SenseGroupAnalysis`, syntactic analysis, sound/rhythm analysis | Corresponding schemas | Replaceable, provenance-bearing derived artifacts |
| LLTimeline interchange | `LLTimelineDocument`, including sense-group analyses and active-analysis selection | `LLTimelineDocument`, currently omitting both sense-group fields | Versioned interchange envelope with a known Rust/OpenAPI contract drift; not a Learning Object |
| Content Selection | `RubricSource`; `PracticeTarget` + `PracticeAnchor`; `PatternSourceSnapshot`; `PlayableSegment` | Same named schemas except no canonical `ContentSelection` | Repeated bounded-snapshot facts; future contract seam |
| Playback Context | Media/track/range facts plus client cursor and playback state | No canonical schema | Client context that may create a selection; not task authority |
| Source Snapshot | `RubricSource`, `PatternSourceSnapshot`, `PracticeItem.prompt_snapshot`, retained response source facts | Corresponding embedded schemas and fields | Current purpose-specific immutable history |
| Sentence Exemplar | `construction::SentenceExemplar` | None | Spike-only domain type |
| Task Prompt | `PracticeItem.prompt_snapshot`; semantic rubric prompt/source; pattern version text | Purpose-specific practice, semantic-task, and pattern schemas | Current purpose-specific fact; no universal prompt |
| Learning Object | No universal parent type | No schema | Concept family only; member identities remain separate |
| Lexical Unit | `LexicalUnit`; durable wrapper `LexicalEntry` | `LexicalUnit`, `LexicalEntry`, `LexicalOccurrence` | Production |
| Listening Phenomenon | `WordTiming`, `PhoneTimeline`, `ConnectedSpeechExplanation`, `RhythmFrame`, `ListeningHotspot` | Corresponding timeline and sound-analysis schemas | Conceptual family; no universal identity |
| Sense Group | `SenseGroup`, `SenseGroupAnalysis` | `SenseGroup`, `SenseGroupAnalysis` | Production analysis |
| Prosodic Chunk | `ProsodyAnalysis` with declared token spans and word-anchored prominence/stress/utterance roles; only playback times are projected through the Word Timeline. The legacy `ChunkTimeline` representation was retired in R5 (2026-08-09) | `ProsodyAnalysis` and related package/timeline schemas | Production analysis, distinct from Sense Group |
| Construction | `Construction`, `ConstructionOccurrence`, `ConstructionEvidence`, `ConstructionCapabilityProfile` | None | Spike-only; core #80 owns productionization |
| Construction Occurrence | `construction::ConstructionOccurrence` | None | Spike-only; production authority remains #80 work |
| Construction Occurrence Proposal | No production type; syntax/dependency candidates are inputs, not this authority | None | Future #80 lifecycle constraint |
| User Sentence Pattern | Spike `construction::UserSentencePattern`; production `UserSentencePatternAsset` + `UserSentencePatternVersion` | `UserSentencePatternAsset`, `UserSentencePatternVersion`, `PatternSourceSnapshot` | Production user asset plus older spike representation |
| Derived Explanation | Connected-speech, diagnosis, syntax, rhythm, writing, and semantic explanation families | Purpose-specific explanation and feedback schemas | Current conceptual family over replaceable or provenance-bearing interpretations |
| Learning Activity | `PracticeItem`, `SemanticRubric`, `ReviewItem`, realtime session intent | Purpose-specific schemas | Concept family only |
| Attempt | `PracticeAttempt`, `SemanticTaskAttempt`, `ReviewAttempt`, `PersonalExpressionAttempt` | Corresponding schemas | Concrete fact families; no universal attempt |
| Performance | `PracticeAttempt.input`; `AttemptResponse`; personal-expression response; realtime learner turn | Embedded in corresponding attempt/turn schemas | Concrete facts |
| Assistance | `AssistanceLevel`, `SpeakingAssistanceLevel`, `PersonalExpressionAssistance`, `ProductionAssistance`, task conditions | Corresponding enums/conditions | Multiple factual vocabularies |
| Constructed Speaking Task | `SemanticTaskKind::L2Retelling` and `PatternProduction` with semantic attempt/response | Semantic task/attempt/response schemas | Production activity family |
| Personal Expression Use | `PersonalExpressionAttempt`, optionally linked to its semantic Pattern Production attempt | `PersonalExpressionAttempt` and create request | Production user-owned use fact; current DELETE cascades history, while ADR 0035 defines archive/restore as its replacement lifecycle |
| Realtime Conversation / Conversation History | `RealtimeConversationSession`, ordered `RealtimeConversationTurn` | Corresponding realtime session/turn schemas | Production durable conversation facts |
| Production Corpus | `ProductionCorpusDocument`, entry, hit, and summary read types | Corresponding production-corpus schemas | Production rebuildable read layer |
| Observation | `LearningObservation`; legacy `LexicalObservation` | Both schemas | New append-only authority plus legacy context record |
| Evidence | Qualified `LearningObservation`/attempt/judgment facts; spike `ConstructionEvidence` | No universal evidence schema | Qualification relation over retained facts, not a parent record |
| Judgment | `SemanticJudgment`; writing findings are a separate feedback family | `SemanticJudgment`, `WritingFeedbackFinding` | Production, provenance-bearing |
| Judgment Adjudication | `JudgmentAdjudication` | `JudgmentAdjudication` | Production user correction |
| Projection Proposal | `ProjectionProposal`, `ProjectionAudit` | Same schemas | Production |
| User Decision | `ProjectionDecision` | Projection decision endpoint | Confirm/reject authority for one proposal |
| User Override | `CapabilityOverride` | `CapabilityOverride` inside `LexicalCapabilityProfile` | Production |
| Effective Capability | `LexicalCapabilityProfile` + `CapabilityDimensionState::effective_assessment` | `LexicalCapabilityProfile`, `CapabilityDimensionState` | Production read model |
| Capability | `LexicalCapabilityProfile`; spike `ConstructionCapabilityProfile` | Lexical capability schemas; no universal capability schema | Learner–object relation with object-specific projections |
| Channel | `LexicalCapability`, `ReviewChannel`, `ProductionChannel`, `PersonalExpressionChannel`, construction evidence modality | Repeated channel enums | Same user vocabulary, purpose-specific types |
| Receptive / Productive Capability | Directional interpretation over channel-specific evidence and capability; Construction spike has recognition/production summary | No universal directional schema | Conceptual read; no cross-channel implication |
| Unassessed | `CapabilityDimensionState::effective_assessment()` returns `CapabilityAssessment::Unassessed` when both projection and override are absent | Inline `unassessed` enum value in capability schemas | Explicit effective-read result, not failure |
| Gap | `CrossModalReviewCandidate`, `ProductionGapReview` | Same schemas plus semantic enrichment | Production read models |
| Learning Agenda | No type | No schema | Future read aggregate requested by app #71 |
| Agenda Item | No type | No schema | Future view owned by app #71; source lifecycle remains authoritative |
| Review Queue | `ReviewItem`, `ReviewSchedule`, `ReviewAttempt` | Corresponding review schemas/routes | Production source lifecycle, not Agenda identity |
| Listening Inbox | `ListeningInboxItem` | `ListeningInboxItem` | Production source lifecycle |
| Hunting Target | `HuntingCandidate`, `HuntingTarget` | Corresponding schemas | Production candidate and learner-confirmed target lifecycles |
| Learning Session | Narrow `PracticeSession`, realtime and listening session facts | Narrow session/attempt routes and schemas | Future journey concept; no universal session |
| Collection | `LexicalSenseFolder`; imported deck metadata are narrower concepts | Sense-folder and review-deck schemas | No general Collection contract |
| Availability | `MediaAvailability`, `SubtitleTrackStatus`, `TimelineStatus`, `LearningResourceState`, `PlayableSegmentAvailability` | Corresponding purpose-specific schemas | Current source/resource facts; not learner readiness |
| Activity readiness | Purpose-specific availability checks such as `PlayableSegmentAvailability`; runtime/resource support facts | `PlayableSegmentAvailability`, `LanguageLearningProfile`, resource capability views | No unified goal-relative readiness schema |
| Unavailable State / Fallback | Purpose-specific errors, availability values, and explicit adapter behavior | No universal schema | Current behavior is fragmented; future activity contracts must preserve goal, channel, authority, and recovery semantics |

## Keep, merge in presentation, and deprecation candidates

### Keep

- Distinct identities for the four Learning Object members.
- Media, text tracks, source snapshots, and replaceable analyses as separable
  facts.
- Purpose-specific attempt families and their invariants.
- Preserve attempts, observations, judgments, adjudications, proposals,
  decisions, capability history, and user-owned pattern versions independently
  of replaceable analyses; retain append/version semantics where their concrete
  lifecycle guarantees them.
- Four lexical capability dimensions with `unassessed` distinct from
  `not_acquired`.
- Review, Inbox, Hunting, proposal, and gap source identities.
- Construction and User Sentence Pattern as separate authority domains.

### Merge in presentation only

- Present `MediaItem` plus the selected language-bearing track as one Content
  Document in client context; do not invent an authoritative active
  track, and keep resource lifecycle controls contextual.
- Present bounded source facts as Content Selection and Task Prompt; do not
  merge the existing purpose-specific histories.
- Call concrete practice, semantic, review, and personal-expression records
  Attempts in learner-facing explanations without creating a parent entity.
- Use one channel vocabulary and one assistance vocabulary in the user
  experience while retaining each source enum and provenance.
- Aggregate Review, Listening Inbox, Hunting, upgrade/projection proposals,
  gaps, and Coach suggestions in Learning Agenda.
- Present the production `UserSentencePatternAsset`/version model as User
  Sentence Pattern; treat the spike `construction::UserSentencePattern` as a
  validation precursor, not a second product asset.

### Deprecation candidates, not authorized removals

| Candidate | Why | Exit condition |
|---|---|---|
| `LearningStatus` and status-based upgrade fields | Three-value reading/listening coupling is a compatibility view superseded by channel capability | Every consumer, import/export path, content-fit input, and upgrade flow uses capability/evidence semantics; explicit contract migration and versioning exist |
| Legacy `LexicalObservation` | Latest-wins context record lacks channel, assistance, and append-only history | Diagnosis and all API consumers use `LearningObservation` or an equally precise replacement; bundle migration is defined |
| `RecognitionEvidence` + `UpgradeSuggestion` pipeline | Duplicates evidence/proposal concepts beside `LearningObservation` + `ProjectionProposal` | Recognition thresholds and confirmation behavior are reproduced through qualified observations/proposals with history and compatibility tests |
| Generic `/learning-resources` product vocabulary | Describes downloadable runtime assets as if they were learner-facing language objects | Consumers move to explicitly named runtime asset/capability contracts while install, checksum, license, failure, and removal authority remains available |
| Legacy User Sentence Pattern `DELETE` | Cascades immutable versions and Personal Expression attempts, yet does not constitute complete privacy erasure | Archive/restore is released and consumed; the deprecated route is removed through an explicit breaking contract migration |
| Legacy sentence `word_timings` beside versioned `WordTimeline` | Two representations of the same timing family invite drift and ambiguous authority | Every current consumer reads the selected versioned timeline or an explicit compatibility projection; migration and contract aliases are tested |
| Individual timeline `/export` aliases that return the same representation as `GET` | Duplicate routes imply an export distinction that the contract does not provide | Consumers use one canonical retrieval route or export gains an explicitly different format/behavior with compatibility coverage |
| User-facing “Listening Inbox”, “Hunting List”, and queue names as primary destinations | Internal lifecycle names expose queue management rather than learning intent | Learning Agenda provides deduplicated routing, availability, reason, and commands back to each owner |
| Generic use of `capability` for both learner mastery and runtime support | Creates domain ambiguity | Product contracts and docs qualify runtime/provider capability consistently |

No item in this table may be deleted without an explicit consumer inventory,
compatibility window, migration, and contract-version decision.

## Dependencies and next contract requests

- **Construction MVP — core #80:** consumes the object/authority boundary here.
  It must revisit English-centric closed variant fields, define the narrow
  supported construction set, and add persistence/OpenAPI only after the real
  occurrence → explanation → recognition → variant production → evidence
  journey is specified. Before implementation, #80 must:
  - decide stable Construction identity versus immutable definition revision;
    the spike tuple `(language, key, schema_version)` is current code fact, not
    an approved production lifecycle;
  - keep automatic occurrence proposals replaceable and provenanced while
    retaining user or curator decisions and source snapshots as durable facts;
  - reuse `SemanticTaskKind::PatternProduction` for prompt, recording, and
    transcript authority rather than create a parallel production attempt;
  - let qualified Construction evidence retain its listening, reading,
    speaking, or writing Channel and assistance facts without immediately
    manufacturing a recognition/production capability projection;
  - validate an optional User Sentence Pattern link against an existing,
    same-language Construction revision while preserving independent creation,
    wording, versioning, unlinking, and source-loss survival;
  - keep Personal YouGlish construction search under core #48 as a read adapter
    over confirmed occurrences, not as a Construction identity or evidence
    writer.
- **Learning Session — app #70:** supplies the journey and state-machine
  information request. Core should respond with the smallest resumability and
  closeout contract, not a universal session table.
- **Learning Agenda — app #71:** supplies Agenda item fixtures, deduplication,
  commands, latency, and partial-failure semantics. Core should add a read
  aggregate only if composing current APIs is inadequate.
- **Assistance Ladder — app #72:** supplies channel-specific legal combinations
  and user vocabulary. Core should add only missing attempt snapshots and must
  preserve the distinctions in the assistance table above.
- **Learning Goal — app #73:** remains user authority that may affect ranking
  and explanation, never evidence, capability, or content access.

All resulting API changes remain contract-first and require compatibility
classification, contract validation, immutable release artifacts, and an
explicit `listen-app` lock update.

## ADR assessment

The original model added no ADR because its hard-to-reverse boundaries were
already recorded by ADRs 0012, 0015–0017, 0020–0021, 0024–0025, and 0028. ADR
0035 now resolves the Personal Expression hard-delete conflict by choosing
archive/restore and separating future erasure. The Construction occurrence
authority lifecycle remains undecided and may require its own ADR when
finalized.
