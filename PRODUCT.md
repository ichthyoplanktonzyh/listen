# Listen Product Semantics

This document describes product direction. Current scope and execution priority
are defined in [STATE.md](STATE.md) and [ROADMAP.md](ROADMAP.md).

The active implementation is restricted to audio/video listening, requested
contextual help, intentional collection, Personal Corpus re-entry, and listening
review. Document materials, independent reading/writing/speaking activities,
AI conversation, and learning-coach policies are deferred to separate branches.
The broader model below does not require those implementations in the product.

> Status: owner-approved semantic baseline, revision 7, 2026-09-08.

This document defines what Listen is, why it exists, and the durable product
principles that follow from the project model. The theoretical structure and
learning boundary are authoritative in [MODEL.md](MODEL.md). This document does
not claim current implementation completeness or define executable contracts.

## Purpose

Listen helps people turn authentic language they care about into language
capability they can actually use.

It does this by compiling arbitrary Sources into Complete Learning Materials,
supporting meaningful interaction with those materials, retaining re-enterable
Language Slices and learning history in a Personal Corpus, and using those
experiences to develop independent reading, listening, speaking, and writing
capabilities.

Listening is the current implementation focus. The domain can describe four
independent capability dimensions without implementing four activity systems
at the same time.

## Product statement

Listen is an authentic-material language-capability acquisition system. It
starts from real articles, books, podcasts, recordings, audio, and video;
compiles them into complete, interactive language experiences; and helps the
Learner build a Personal Corpus that can be revisited for perception,
understanding, retrieval, production, and transfer.

> Turn authentic language into experiences you can re-enter, learn from, and
> make part of your own L2 world.

Authentic Experience and Personal Corpus are the product's two distinctive
ideas. The first keeps learning grounded in real language. The second prevents
useful experience from disappearing when one session ends.

## Product principles

### Authentic material, not a mandatory curriculum

Learning is grounded in language-bearing material chosen or accepted by the
Learner. Listen may offer activities, review, and next experiences, but it does
not require one course, one deck, or one fixed sequence.

### Separate Source from formal Learning Material

A file, URL, feed item, article, document, podcast, recording, audio file, or
video first enters the language world as a Raw Source. Source acquisition,
preview, recovery, and compilation are production concerns.

Formal learning begins from a Complete Learning Material qualified under the
modality-aware contract in [MODEL.md](MODEL.md). Text-only materials support
normal text-based learning without TTS. Existing audio requires the full
sound-processing scope, not a minimum tier with separately requested speech
enhancements. Sentence Translation remains required for the declared Support
Language; unrelated optional explanations may be added later.

This distinction prevents the learning system from treating every missing
foundation as an ordinary UI fallback. A failed or incomplete compilation is
reported as production state; it is not disguised as a complete learning
experience.

### One aligned language experience

Canonical audio and canonical text are aligned representations of one Material
Revision when audio exists, not separate learner-owned materials. Text Sources
gain faithful audio only on Learner request; that audio then receives the same
full processing as source audio. Sources with audio gain verified text through
transcription or another qualified path. Source video is retained when present.

Structured Reading and stable Text Anchors support reading, lookup, translation,
and Language Slices independently of sound. Sense Groups support meaning-group
reading and focus without audio or TTS. When audio exists, Structured Timed Text
adds exact audio mappings for synchronized highlighting, replay, loops, and
speech learning; Sense Groups do not substitute for Prosodic Chunks.

### Listening-first, four-dimensional

Listen gives special depth to the path from acoustic signal through perception,
segmentation, form, and meaning. Reading, listening, speaking, and writing
remain independent learner capabilities. Success in one never silently proves
another.

The product currently deepens listening and defers independent reading,
speaking, and writing activities. Vocabulary capability state remains
four-dimensional; displaying or manually marking those dimensions does not
require the deferred activities, output assessment, or coach automation.

### Speech analysis must become perceptual guidance

Speech Learning Representation connects Signal Facts, Speech Structure, and
Perceptual Guidance. It distinguishes observed acoustic evidence from text
priors, predictions, and estimates; keeps semantic Sense Groups distinct from
Prosodic Chunks; and records provenance for replaceable analyses.

The learner-facing purpose is not to display phonetic terminology. It is to
guide attention and produce a better second act of listening. Material-side
speech truth can be shared; what the Learner should focus on now is
learner-relative.

Full processing does not require every sound phenomenon to exist. Unsupported
analysis, insufficient evidence, failure, and a qualified absence remain
distinct; missing evidence is not filled with an unlabeled prediction. The
Learner can choose which analyses to view. Minimum Sufficient Scaffold governs
that presentation, not which required material analyses are performed.

### Gen compiles language; the learning system compiles experience

Gen produces reusable material-side truth and structure. Core preserves the
canonical material, episode, evidence, and learner-state semantics. App presents
the activity, attention, support, re-entry, and navigation experience.

Provider workflows, model choices, and derivation recipes do not cross the
formal learning boundary. The learning system consumes a declared Complete
Learning Material contract.

### One Workbench across materials and activities

The [unified Workbench](MODEL.md#unified-workbench-consumption) consumes
Core-provided materials and learning semantics. Reading and Sense Groups,
audio/video interaction, later TTS enrichment, and Corpus-selected learning or
review share this workspace rather than separate consumption systems. Views
and Activity modes can differ without changing material ownership or exposing
Gen's production workflow; the Workbench hosts Activities rather than defining
one universal Activity or fixed layout.

### Learning Activity describes cognition, not UI

A Learning Activity names what the Learner is trying to do with language:
listen for meaning, perceive a difficult form, read, dictate, reconstruct,
shadow, retrieve, speak, or write. Buttons, pages, subtitle toggles, and replay
controls are support actions unless they participate in such an operation.

The set of activities stays open. Listen does not build a large universal
taxonomy before product evidence requires it.

### Language Slices preserve re-entry and context

When a bounded piece of a material becomes meaningful to the Learner, Listen
can retain it as a Language Slice. A Slice points to the exact Material
Revision, text span, exact audio rendition/range when available, and compatible
resources. A text-only Slice is valid. It normally does not copy a new audio
file or become a new material.

The Learner can reopen the Slice, recover surrounding context, and replay it
when its referenced audio is available. Later TTS adds a new listening
possibility without turning previous reading history into listening evidence.

### Personal Corpus stores meaningful relationships

The Personal Corpus is not merely the Personal Library, a search index, a
bookmark list, or a vocabulary deck. It preserves Language Slices together
with Learner Relations and Meaningful Learning Episodes.

It acts as memory, an evidence base, and an experience reservoir. Repeated
authentic occurrences of one language object become a personalized set for
review and transfer.

Initially, it is a freely browsable personal language space: inspect entries,
context, and history; choose entries to add to learning or review; then enter
the corresponding Activity. An explicit save can begin the history without a
completed exercise. Browsing alone is not an attempt, and automatic scheduling
or next-experience selection is not a prerequisite.

### Preserve fact history; replace interpretation

Exposure, attention, learning, and acquisition are distinct. Raw clickstream
does not silently become learner state. Meaningful Episodes preserve outcomes,
conditions, assistance, source context, and provenance.

Personal Corpus answers what happened. Personal L2 World and Learner State are
versioned interpretations of that history. New projection logic may reinterpret
the evidence but never rewrite the underlying facts. Explicit Learner authority
remains distinct from model inference.

### Simple durable state, rich episode evidence

Listen does not prematurely persist a giant tensor of every possible subskill.
A simple long-lived capability state may be backed by rich evidence about
context, speaker, rate, assistance, perception, production, and transfer. Real
usage determines which additional projections deserve durable product status.

### Review means reactivation, re-perception, and transfer

Scheduling decides when a learner-language relation returns. Acquisition
Experience decides what the Learner should do when it returns. These are
different concerns.

Listening review begins by re-entering the original Slice audio-first. Failure
reveals only the minimum sufficient scaffold: focused replay, a perceptual or
rhythmic cue, speech explanation, timed text, then translation. Support must
lead back to listening.

Same-recording success may reflect acoustic memorization. Robustness is tested
through new sentences, speakers, rates, prosody, realizations, or contexts.

### Policy follows evidence

Listen does not need a large configurable policy framework today. It needs to
identify the difficulty that occurred, offer the most direct useful help,
decide which meaningful experience enters the Personal Corpus, and choose how
that authentic experience should be re-entered later.

More complex adaptation follows validated behavior rather than theoretical
completeness.

### Replaceable production, reusable results

Models, tools, and providers remain replaceable. Qualified material-side
results carry provenance, compatibility, and version identity so another
Learner can reuse a compiled Learning Material without needing the producer's
runtime or credentials.

A Content Package is a distribution mechanism for a coherent Complete Learning
Material composition. It is not a course, a learner backup, or the central
learning object.

### Public material, private learning

Compiled materials, editions, and community metadata may be shared when rights
permit. Personal Corpus entries, learning episodes, attempts, notes, learner
state, and explicit decisions belong to the Learner and are never embedded in a
public package.

### Multilingual core, language-aware representation

The two-world model, Language Slice, episode history, four capability
dimensions, and evidence boundaries are language-general. Tokenization,
lexical identity, writing systems, pronunciation, tone, stress, mora, rhythm,
prosody, morphology, and perceptual guidance are language-aware capabilities.

Unsupported language-specific analysis degrades honestly during material
production; the product must not silently substitute an English-shaped model.

### Account-enhanced and offline-capable

Desktop and mobile are joint product targets. Both retain local learning,
Personal Corpus, and review capability once required material resources are
available. A personal computer can produce materials and deliver them to a
phone, but prepared learning does not depend on that computer staying online.

Local-first does not require all computation to be local. The Production
Executor and Model Provider are independent choices: a personal computer or
remote service can organize production using local models, vendor APIs, or a
mixture. All routes deliver the same qualified material contract. Calling a
vendor API from a computer still depends on that computer executing the task.

An account may support synchronization, subscriptions, publishing, and
cross-device recovery. Compiled materials and private learning history remain
usable offline within their rights and storage constraints. Production tasks,
material delivery, and private learning-data replication are distinct concerns.
See the approved [desktop/mobile and production design](docs/architecture/devices-and-production.md)
for deployment and delivery decisions; it does not assert implemented support.

## Durable learner journey

```text
bring or discover a Raw Source
    -> compile and qualify a Complete Learning Material
    -> enter a Learning Activity
    -> focus or retain a Language Slice
    -> form a Meaningful Learning Episode
    -> grow the Personal Corpus
    -> re-enter experience for repair, production, or transfer
```

Acquisition, source binding, provider execution, qualification, packaging,
installation, and adoption may run behind the material-production journey.
They do not become learning activities merely because they are technically
complex.

## Personal data boundary

Listen preserves and synchronizes data the Learner cannot safely recreate:
Personal Corpus entries, explicit retention, Language Slices, meaningful
episodes, attempts, judgments, decisions, capability history, notes, and
progress.

Compiled public artifacts, caches, indexes, and Learner Inferences may be
recreated or downloaded again. Their lifecycle must not erase durable learner
facts.

## Non-goals

Listen does not currently aim to:

- accept an incomplete Raw Source as if it already satisfied the formal
  learning contract;
- prescribe a universal curriculum or mandatory activity sequence;
- treat a file, player screen, subtitle track, package, or exercise as the
  product's central learning object;
- infer acquisition from clicks or exposure alone;
- collapse Personal Corpus facts and Learner State projections;
- infer listening, speaking, or writing capability from reading success;
- expose raw phonetic analysis without converting it into useful perception;
- encode every conceivable listening subskill as permanent state;
- bind material compilation to one provider or model;
- couple Listen to Sensa before cross-product behavior is validated;
- make every optional explanation a validity requirement.

## Deliberately deferred decisions

- exact provider and qualification gates for every required material resource;
- the complete set of Learning Activities and acquisition experiences;
- projection algorithms and state vocabularies for every Language Object;
- adaptive policy decomposition beyond the minimum product questions;
- community moderation, reputation, and business models;
- hosted synchronization topology and large private-asset policy;
- long-term shared identity or corpus integration with Sensa.
