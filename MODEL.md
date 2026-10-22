# Listen Project Model

This document describes product direction. Current scope and execution priority
are defined in [STATE.md](STATE.md) and [ROADMAP.md](ROADMAP.md).

The current implementation follows only the audio/video listening journey in
[JOURNEYS.md](JOURNEYS.md). The model's other Source modalities and capability
dimensions describe possible future scope, not runtime requirements for this
stage.

> Status: owner-approved model, revision 4, 2026-10-22. Workbench entry and
> foundational/on-demand resource policy are targets, not implementation claims.

This document is the project-level authority for Listen's theoretical model.
It defines the relationship among the language world, the learning world,
Complete Learning Materials, Personal Corpus, learner state, and capability
acquisition. Product principles in [PRODUCT.md](PRODUCT.md), domain terms in
[DOMAIN.md](DOMAIN.md), and module responsibilities in
[CONTEXT-MAP.md](CONTEXT-MAP.md) must remain consistent with this model.

This is a product and domain model, not an executable schema. App, Core, and Gen
may temporarily lag it while their contracts are realigned. Current speech
artifact names are implementation details; the durable representation boundary
defined here must not be reduced to one provider, model, timeline, or analysis
type.

## Definition

Listen is an authentic-material language-capability acquisition system. It
compiles arbitrary sources into complete, interactive language experiences,
lets a Learner retain re-enterable Language Slices with their meaningful
learning history, and uses those experiences to develop independent reading,
listening, speaking, and writing capabilities.

Its model spine is:

```text
Language Material
      -> Learning Experience
      -> Personal Corpus
      -> Capability Growth
```

Listen is not a media player with subtitles and lookup attached, and it is not
a mandatory curriculum or a collection of disconnected exercises. Its center
is the continuing relationship between a Learner and authentic language.

## Two worlds and the learning boundary

Listen separates the material-side language world from the learner-relative
learning world:

```text
LANGUAGE WORLD
────────────────────────────────────
Raw Source
    ├── Native Media Resources -> Workbench playback, before production
    └── explicit material-production request
            ↓
        Learning Material Compiler / listen-gen
            ↓
        Complete Learning Material (foundational contract satisfied)
            ├── Canonical Text / Structured Reading
            ├── Sentence Translation
            ├── when audio exists: exact sentence/word timed text
            └── compatible on-demand resources, produced or reused as requested

══════════════ LEARNING BOUNDARY ══════════════

LEARNING WORLD
────────────────────────────────────
Learner × Complete Learning Material
    ↓
Learning Activity
    ↓
Language Slice / Focus
    ↓
Meaningful Learning Episode
    ↓
Personal Corpus
    ├── Experience Reservoir ─────────┐
    └── Evidence Base                 │
             ↓                        │
      Learner State / Personal L2 World
      Reading / Listening / Speaking / Writing
             └───────────┬────────────┘
                         ↓
              Next Learning Experience
                         ↺
```

The language world answers: **what is this language experience?**

The learning world answers: **what has happened between this Learner and this
language, and what should happen next?**

A file, URL, feed item, article, EPUB, podcast, audio file, video, or pasted text
enters Listen as a Raw Source. Selecting it opens the same MaterialWorkbench
before material production. Accessible native media and source-provided
resources support ordinary playback; an inaccessible source shows an honest
acquisition or recovery state. Entering the workspace does not establish
learning readiness, a learning attempt, or acquired capability.

Resource-dependent learning actions become available when their exact
dependencies are qualified. Complete Learning Material names satisfaction of
the foundational contract below; it is not an entry requirement for the
Workbench or a requirement to finish every possible analysis before any useful
action. Detailed presentation and the full journey are in [JOURNEYS.md](JOURNEYS.md).

## Complete Learning Material contract

"Complete" means qualified under the foundational contract for the material's
actual modalities, not that every possible analysis has run. The active
audio/video listening contract requires qualified interactive text, exact
sentence/word timing and media alignment, and Sentence Translation in the
declared Support Languages. Detailed sound analysis is on demand.

The broader model still permits text-only learning without TTS; standalone
text materials and activities remain outside the current implementation scope.
Native playback and partially ready resources never masquerade as satisfying
the complete foundational contract.

### 1. Language Experience

The canonical core is:

```text
Canonical Text     REQUIRED
Structured Reading REQUIRED
Audio              PRESENT IN SOURCE OR REQUESTED THROUGH TTS
Video              IF THE SOURCE HAS VIDEO
```

A text source does not need audio to become a Complete Learning Material. The
Learner may request faithful TTS when a sound-based experience is wanted. An
audio source, or video with an audio track, gains canonical text through
transcription or another verified text path. Source video is preserved when
present; Listen does not require synthetic video or invent an audio track for
silent video.

When audio exists, audio and text are aligned representations of one Material
Revision, not two separate learner-owned materials. Adding faithful TTS need
not change the text's identity, but every audio-dependent resource binds to its
exact rendition; another voice or recording cannot reuse timings implicitly.

### 2. Interactive Representation

Structured Reading supplies exact canonical text, hierarchy, sentence/token
spans, and stable Text Anchors independently of audio. It supports reading,
lookup, translation, Language Slices, and meaningful learning history without
inventing audio locators.

Sense Group analysis belongs to this text side: semantic/syntactic grouping is
on demand and does not require audio or TTS. Text-only materials can support
meaning-group reading, focusing, and Slice selection. The same groups can also accompany
audio-backed learning, but are not evidence of audible prosodic boundaries.

When audio exists, Structured Timed Text relates that text structure to the
exact Canonical Audio:

```text
Utterance / Sentence
├── stable identity
├── canonical text span
├── audio time range
├── Token
│   ├── text span
│   ├── lexical identity when available
│   └── audio time range
└── compatible text/speech structure references
```

Structured Timed Text adds synchronized highlighting, sentence replay, bounded
loops, and timed speech explanation to the text-based interaction coordinates.
Its absence is not a defect in a text-only material with no requested audio.

Exactness matters. Stable text anchors, time locators, resource identities, and
compatibility evidence must make clear which Material Revision and canonical
audio/text pair a resource describes. An inferred or approximate mapping must
not be presented as exact.

Qualified native subtitles may be reused after normalization and compatibility
checks; ASR is one production route, not a mandatory rerun. Sentence timing
alone does not satisfy exact word-level interaction. Failure to obtain word
timing leaves that dependency unavailable rather than distributing sentence
duration uniformly and calling it exact.

### 3. Meaning Scaffold

A Complete Learning Material includes sentence-level translation for the
declared Support Language used by the Learner. Translation is part of the
material contract rather than an accidental enrichment. This requirement is
independent of whether audio exists.

A listening preparation request must declare the Learner's Support Language;
a missing declaration is a prerequisite to resolve, not permission to skip
translation and claim foundational readiness.

Grammar, semantics, pragmatics, discourse, cultural context, and other
explanations are valuable optional enrichments. Their absence does not make the
material incomplete when the required sentence translation exists.

### 4. Resource policy and readiness

Resources have three distinct product roles:

- **Native Media Resources** permit ordinary playback before preparation:
  source media, audio tracks, supplied subtitles, and chapters where available.
  Their presence alone does not establish qualified learning resources.
- **Foundational Learning Resources** provide shared interaction coordinates
  and essential meaning support. Preparing a material for basic listening
  fills these requirements by qualifying reusable inputs or producing gaps.
- **On-demand Learning Resources** add deeper analysis or explanations when
  requested for a sentence, Slice, or whole material. They can be retained
  and reused without becoming prerequisites for foundational readiness.

The foundational requirements map to current resource types as follows:

| Domain requirement | Current representation | Supported interaction |
|---|---|---|
| Qualified canonical text, sentence and token spans, stable anchors | `structured_reading` | Interactive text, word/phrase selection, text-backed Slice saving |
| Exact text-to-media binding | `anchor_time_alignment` | Return from an anchor to this exact recording |
| Exact sentence and word/token time ranges | subtitle/timed-text representations and `word_timeline` | Synchronized highlighting, seek, sentence/word replay and loops |
| Sentence Translation in declared Support Languages | `translation` | Essential meaning support aligned to the same text |

`subtitle_text_track` and `timed_text_track` are existing representation forms,
not additional competing canonical texts to manufacture. Validity requires the
capability and compatible resources, not duplicated storage. Original playable
media is a rendition/input prerequisite, not a generated learning-resource kind.

| On-demand result | Current resource or capability |
|---|---|
| Semantic/syntactic Sense Groups | `sense_group_analysis`; distinct from foundational sentence segmentation |
| Word duration, energy, pitch and other acoustic analysis | `word_acoustics`; distinct from mandatory word timing |
| Continuous acoustic tracks and speech/silence analysis | `acoustic_track`, `speech_activity` |
| Prominence, rhythm, weak forms and prosodic structure | `prosody_analysis` |
| Phone timing and audio-backed realization/comparison | `phone_timeline` and phonetic-analysis capabilities |
| Word/phrase meaning, reference pronunciation, grammar, pragmatic or cultural explanation | Dictionary, pronunciation and explanation capabilities; not all have a package resource kind |

Perceptual Guidance is learner-relative help selected or composed at experience
time, not a universal material answer to precompute. A VAD or acoustic operation
may run internally to produce alignment without obliging delivery of a separate
analysis resource for every material. Cost and implementation maturity do not
determine whether a domain dependency is required. An additional Support
Language is an explicit request; declared languages must actually be supported.

Readiness has separate assessments: playable, some qualified learning resources
available, foundational learning ready, and requested on-demand results ready.
These can coexist and are derived from exact dependencies on each device, not
one linear completion flag or Gen process success. A missing optional analysis
does not invalidate foundational learning; a failed required translation or
timing does not silently become optional. Available actions may use qualified
partial resources without claiming the full foundational contract is met.

The package schema's `base`/`assistance` roles describe resource relationships,
not this product policy: translation is assistance yet foundational. A release's
`required` declaration is also distinct from the product-wide foundational
requirements. Schema acceptance alone does not prove foundational readiness.
These tables define target semantics, not changes to existing package schemas.

### 5. Speech Learning Representation

Speech Learning Representation is Listen's distinctive bridge from a sound
recording to learnable listening experience. Its purpose is not merely to label
phonetic phenomena; it must support the question: **why does the real speech
sound this way, and where should the Learner direct attention?**

Exact interactive text and sentence/word alignment belong to the foundational
contract for audio. Deeper material-side sound processing is available on demand
for source audio or any explicitly generated audio. Its analysis scope includes:

- qualified text, sentence/word timing, and exact audio/text alignment;
- reusable text-side Sense Groups together with distinct audio-side prosodic
  grouping; Sense Groups remain independently usable without audio;
- continuous and word-level acoustic evidence, including duration, energy,
  pitch/voicing where applicable, and speech/silence intervals;
- information/stress anchors, nuclei, weak groups, compression, and boundaries;
- audio-backed phone evidence and its relationship to canonical pronunciation;
- Citation Pronunciation, Connected-speech Prediction, and Actual Delivery
  comparison, including evidence-qualified connected-speech phenomena;
- material-side listening hotspots that can support contextual Perceptual
  Guidance and focused replay.

A requested analysis must qualify its actual scope, not claim every recording
exhibits every phenomenon. Absence of a phenomenon, inapplicability, insufficient
evidence, unsupported analysis, processing failure, and not requested are
distinct outcomes. Skipped or failed analysis is not successful analysis;
predictions never fill an observed-evidence gap as if measured.

The Learner can request the analyses needed now or prepare a larger scope in
advance. Minimum Sufficient Scaffold governs presentation of available help.
On-demand production and selective presentation are separate decisions; neither
weakens exactness or provenance for a result that is actually supplied.

Speech Learning Representation has three layers:

```text
Signal Facts
    ↓
Speech Structure
    ↓
Perceptual Guidance
```

#### Signal Facts

Signal Facts are material-side, evidence-bearing descriptions of the actual
audio, such as:

- word and phone timing;
- observed phone realization;
- duration, energy, pitch/F0, and other acoustic cues;
- continuous acoustic tracks, voicing, and speech/silence intervals;
- confidence, provenance, signal source, and evidence class.

Predicted, canonical, forced-aligned, and directly observed facts remain
distinguishable. Text priors and timing estimates must not masquerade as
observed acoustic evidence.

#### Speech Structure

Speech Structure interprets signal and text evidence into useful organization,
such as:

- prominence, information/stress anchors, and nuclei;
- rhythm, weak groups, compression, and listening hotspots;
- prosodic boundaries and Prosodic Chunks;
- reduction, linking, assimilation, deletion, and other connected-speech
  phenomena.

This is a conceptual layer over multiple versioned resources, not one universal
artifact. A semantic Sense Group is distinct from a Prosodic Chunk. A Prosodic
Chunk binds exact words to compatible audio timing without requiring a
particular implementation artifact.

Citation Pronunciation describes conventional reference pronunciation;
Connected-speech Prediction describes a possible contextual realization;
Actual Delivery interprets evidence from this exact recording. These are
comparison perspectives, not the three layers of Speech Learning Representation
and not interchangeable claims of observation.

#### Perceptual Guidance

Perceptual Guidance turns material-side facts into learner-relative attention
guidance: what to listen for now, which anchor matters, which support to reveal,
and when to replay.

It is not fixed material truth and must not be precomputed by Gen as one answer
for every Learner. The same speech can require different guidance depending on
the Learner's prior meaning knowledge, listening evidence, current failure, and
available support.

Speech analysis is useful only when it can be converted into a better act of
listening. Listen is a perceptual learning system, not a phonetics annotation
viewer.

## Production and learning responsibilities

The boundary can be summarized as:

> Gen compiles Language Experience; Core and App compile Learner-relative
> Learning Experience.

Gen describes the material: canonical representations, boundaries, alignment,
actual speech realization, acoustic facts, prosodic structure, translations,
and other reusable material-side resources. Gen owns provider execution and
records exact provenance and qualification.

Core owns the canonical semantics for Complete Learning Materials, Language
Slices, meaningful learning facts, evidence, learner state, and capability
projections. It preserves the distinction between durable facts and replaceable
interpretation.

App owns the learner-facing experience: activity intent, attention, progressive
support, interaction, re-entry, and navigation between a Slice and its original
context.

Once a Complete Learning Material crosses the learning boundary, the learning
system consumes its declared contract and does not depend on how a particular
provider or recipe produced it.

This model is device-independent. Desktop and mobile share material identity,
Language Slices, Personal Corpus facts, and capability semantics while retaining
their own local learning capability. A Material Production Task can be assigned
to a personal-computer or remote Production Executor; the executor's choice of
Model Provider does not change the formal learning boundary. Prepared learning
does not require the original executor or provider to remain available. The
[desktop/mobile and production design](docs/architecture/devices-and-production.md)
defines the approved deployment target without declaring it implemented.

### Unified Workbench consumption

The same MaterialWorkbench hosts native playback before production, background
preparation progress, qualified resource-backed interaction, and learning or
review selected from the Personal Corpus. Core supplies source/media identity,
availability, resource validity, and learning semantics; the App does not
interpret provider-specific Gen output as material authority.

Entering the Workbench does not require a qualified Learning Edition. Playback
uses accessible media and its native resources; dependent learning actions open
only when their qualified resources are available. Resource production can
continue while watching or after leaving the page. Returning preserves media
context and playback position; resource failure does not break native playback.

Text-only, audio, video, and subsequently enriched materials share this
consumption boundary. Views, components, and activity modes adapt to the
material's qualified resources and the Learner's intent: text and Sense Group
interaction need no audio, while audio-backed views add synchronized playback
and sound-learning support. Adding TTS extends the same material's experience
in the Workbench rather than introducing a separate consumption workflow.

Selecting a Personal Corpus Entry for learning or review returns to this
Workbench with its Language Slice, Activity intent, and relevant history. The
Workbench does not replace the Corpus's separate browsing role or equate
browsing with a Learning Activity.

Unified means one shared consumption model, not one fixed layout, one global
instance, or one monolithic implementation component. A Workbench hosts
Activities; it is not itself a Learning Activity. This is the target product
boundary, not a claim that current App implementations are already unified.

## Learning Activity

The central relation in the learning world is:

```text
Learner × material with qualified resources for the chosen operation
```

A Learning Activity names the meaningful cognitive operation the Learner is
performing with that material, such as listening for meaning, intensive
listening, reading, dictation, shadowing, reconstruction, speaking, or writing.

A screen, button, subtitle toggle, replay control, or explanation panel is not
automatically a Learning Activity. It may be a support action inside one.
Listen keeps the Activity family open and does not require a universal course
sequence or a large taxonomy before real product evidence demands it.

## Language Slice

A Language Slice is the atomic re-enterable experience pointer of the Personal
Corpus. Saving one requires qualified Canonical Text and stable Text Anchors;
playback alone never enables a textless audio-range Corpus save:

```text
Language Slice
├── Material Revision
├── canonical text span
├── exact audio rendition and time range, when available
└── compatible related resource references
```

A Slice may cover a word, expression, phrase, Sense Group, Prosodic Chunk,
sentence, utterance, or another bounded text-backed span. It does not normally
copy a new audio file or become a new Material. It points back to the original
material so the Learner can reopen the Slice, recover surrounding context, and
return to the whole experience. A text-only Slice is fully valid and can enter
the Personal Corpus without audio. Re-entry then means reopening the text and
its context, not mandatory playback.

Qualified text can enable Slice saving before translation or every other
foundational resource is ready. Saving a Slice with original-audio seek/replay
also requires its accurate media mapping. Before qualified text exists, the
Learner can retain the whole Source in the Personal Library and keep playback
progress, but cannot save a textless audio segment into the Personal Corpus.

Later TTS can add compatible listening resources and new listening episodes;
it cannot turn earlier reading episodes into listening experience, rewrite
their assistance conditions, or silently rebind old audio locators.

## Meaningful Learning Episode

Listen preserves the distinctions:

```text
Exposure ≠ Attention
Attention ≠ Learning
Learning ≠ Acquisition
```

Playback passing a point, pausing, opening text, or clicking a token is first an
interaction observation or telemetry event. It must not silently become learner
state.

A Meaningful Learning Episode records a learner-significant relationship with a
Slice or target, for example:

- explicitly saving or focusing a Slice;
- explicitly reporting difficulty or lack of understanding;
- completing a bounded recognition or production attempt;
- failing, receiving a speech cue, then successfully perceiving the audio;
- producing language with recorded assistance conditions;
- succeeding or failing in a new context, speaker, rate, or realization.

The episode preserves conditions, assistance, source context, outcome, and
provenance richly enough for future reinterpretation. Personal Corpus stores
meaningful learning history, not raw clickstream.

## Personal Corpus

The Personal Corpus is not merely a retained-material collection, search index,
bookmark list, or vocabulary deck. Its atomic entry is:

```text
Personal Corpus Entry
    = Language Slice
    + Learner Relation
    + Meaningful Learning History
```

It has three simultaneous roles:

1. **Memory** — what authentic language the Learner has meaningfully
   experienced.
2. **Evidence Base** — durable facts from which learner state may be inferred.
3. **Experience Reservoir** — original and related Slices that can be reused for
   review, repair, production, and transfer.

The Personal Corpus is the compounding mechanism of Listen. Multiple authentic
occurrences of the same language object naturally form a personalized training
set rather than isolated cards.

An Entry concretely preserves its re-enterable Slice and source context, the
Learner's intentional relation, and the history of what happened: intent,
available/used assistance, attempts or judgments, outcomes, and provenance.
An explicit save may be the first meaningful episode; a completed exercise or
mastery judgment is not a prerequisite. Merely importing or browsing material
does not create this relationship automatically.

Initially, the Corpus is a freely browsable personal language space. The
Learner can inspect entries and their context/history, then explicitly add
selected entries to learning or review and enter the corresponding Activity.
Browsing is not itself a new attempt or evidence of acquisition. An adaptive
recommendation engine or scheduler is not required for this loop; later
suggestions assist rather than replace Learner choice.

## Personal L2 World and learner state

Personal Corpus answers: **what has the Learner experienced?** It is durable
fact history.

Personal L2 World answers: **what can currently be inferred about the
Learner's second-language world?** It is a replaceable interpretation or
projection.

```text
Personal Corpus
      ↓
Evidence qualification and interpretation
      ↓
Learner State / Personal L2 World
```

Changing an inference algorithm may reinterpret history but must not rewrite or
delete the underlying Corpus episodes. Explicit Learner authority remains
separate from automatic inference.

## Four independent capability dimensions

Each relevant Language Object may participate in four independent learner
relations:

```text
Language Object
├── Reading
├── Listening
├── Speaking
└── Writing
```

Evidence in one dimension does not imply capability in another. Seeing and
understanding an expression does not prove real-time auditory recognition;
auditory recognition does not prove speaking or writing retrieval.

Long-lived capability state should remain simple while episode evidence remains
rich. Listen does not prematurely persist a large capability tensor for
auditory discrimination, segmentation, reduction, prosody, speaker robustness,
rate tolerance, and every other subskill. Those details remain available in
episode evidence and may support future, versioned projections when real usage
justifies them.

## Acquisition Experience and review

Listen review is not only card recall. It combines:

```text
Reactivation + Re-perception + Transfer
```

The system separates two decisions:

- **When** should a learner-language relation be reactivated? A scheduler such
  as SRS or FSRS may answer this.
- **What** should the Learner experience when it returns? Listen's acquisition
  experience answers this.

Scheduling is not the Learning Experience.
The early product supports Learner-selected re-entry from the Personal Corpus
without requiring a schedule or automatic next-experience decision.

### Listening acquisition loop

Listening currently has the clearest model:

1. **Re-enter the original experience.** Begin from the original Slice, audio
   first, without immediately revealing text or translation.
2. **Repair with the minimum sufficient scaffold.** After failure, add only the
   least support needed:

   ```text
   original audio
       ↓
   replay / focus range
       ↓
   rhythm or perceptual cue
       ↓
   speech explanation
       ↓
   timed text
       ↓
   translation
   ```

3. **Re-perceive.** Direct attention using Speech Learning Representation, then
   listen again so support leads back to successful perception rather than to
   memorized terminology.
4. **Transfer.** Move beyond same-recording acoustic memory to a new sentence,
   speaker, rate, prosody, acoustic realization, or context. Same-Slice success
   alone is not final proof of robust listening capability.

Reading, speaking, and writing will have their own acquisition experience
spaces:

```text
Reading:  written form -> language structure -> meaning
Listening: acoustic signal -> perception -> segmentation -> form -> meaning
Speaking: meaning/intention -> expression retrieval -> phonological planning -> speech
Writing:  meaning/intention -> expression retrieval -> lexical/construction choice -> text
```

The model preserves all four dimensions without prematurely productizing every
possible activity or adaptive policy.

## Policy restraint

Listen may eventually need target selection, experience selection,
scaffolding, assessment, transfer, scheduling, and stop policies. The current
product should not implement a large abstract policy system before behavior
shows that it is necessary.

For now, it must answer three practical questions:

```text
What difficulty just occurred, and what is the most direct useful help?

Which meaningful experiences enter the Personal Corpus, and when return?

When they return, how should authentic language be experienced again?
```

## Relationship with Sensa

Listen is independently viable and does not currently depend on Sensa.

Long term, Sensa may center Meaning Acquisition while Listen centers authentic
Language Experience and four-dimensional capability acquisition. They may
eventually share Language Identity, Personal Corpus, and reliable learner facts.
Listen must not introduce cross-product coupling before Sensa validates its own
acquisition model with real users.

## Durable invariants

- Selecting a Source opens the Workbench before production; native playback
  does not imply qualified learning resources or acquired capability.
- Resource-dependent learning actions require their own qualified inputs;
  Complete Learning Material means the full foundational contract is met.
- Text-only material supports formal learning without TTS; audio generation is
  on demand, not a condition of text-learning validity.
- Audio listening requires qualified interactive text, exact sentence/word
  timing and media binding, and declared Sentence Translation; deeper sound
  analysis and explanations are on demand.
- Canonical Text, Structured Reading, and declared Sentence Translation support
  text learning; Structured Timed Text binds exact audio when it exists.
- Requested analysis preserves honest absence, insufficient evidence,
  unsupported analysis and failure; it need not find every phenomenon.
- Resource production and selective display of available scaffolds are distinct.
- Sense Groups are on-demand text-side help, independent of audio; they do
  not replace foundational sentence segmentation or Prosodic Chunks.
- Material-side facts and learner-relative guidance remain separate.
- Signal evidence states what is observed, predicted, or inferred honestly.
- Sense Group and Prosodic Chunk remain distinct.
- Learning Activity describes a cognitive relation, not UI structure.
- Processed materials pass through Core and share one App Workbench consumption
  boundary; different views and Activity modes do not create separate systems.
- A Language Slice remains linked to its original material and context.
- Corpus Slice saving requires qualified text and stable anchors; audio
  re-entry additionally requires accurate alignment. Textless audio-range
  saving is outside the selected product model.
- A text-only Slice is valid; later audio never rewrites earlier experience.
- Personal Corpus retains meaningful episodes, not raw clickstream.
- Early Corpus re-entry is learner-selected browsing, learning, and review;
  automated selection is not a prerequisite.
- Personal Corpus facts and Personal L2 World projections never collapse into
  one mutable state.
- Reading, listening, speaking, and writing do not imply one another.
- Durable state stays simple; rich evidence remains available for later
  reinterpretation.
- Review separates scheduling from acquisition experience and aims for transfer,
  not same-item memorization.
- Learner facts outlive replaceable packages, analyses, models, and providers.
