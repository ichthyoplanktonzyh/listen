# Listen Context Map

This map assigns authority across the language world and learning world defined
in [MODEL.md](MODEL.md). All current modules live in one Git repository.
It describes durable seams, not detailed source directories,
transport shapes, or current implementation completeness.

The active scope is audio/video listening, as defined in [STATE.md](STATE.md)
and [JOURNEYS.md](JOURNEYS.md). Responsibilities below do not require deferred
document, conversation, output-training, or coach implementations to remain in
the runtime.

Desktop and mobile are joint targets under the approved
[devices and production design](docs/architecture/devices-and-production.md).
Production execution and device exchange below describe target responsibilities;
[runtime architecture](docs/architecture/runtime.md) describes current processes.

## Contexts

### Learning Experience — `app/`

Owns the learner-facing learning world:

- selecting and resuming a Learning Activity;
- presenting a Complete Learning Material;
- owning the unified Workbench that consumes Core-provided materials and
  learning semantics across modalities and Activity modes;
- presenting transcript text and Sense Groups as support within audio/video
  listening; standalone text learning and text-source TTS are deferred;
- establishing a Language Slice or Learning Focus;
- exposing the Minimum Sufficient Scaffold;
- turning Speech Learning Representation into contextual Perceptual Guidance;
- recording learner intent, attempts, and explicit judgments through Core;
- navigating between a Personal Corpus Entry, its Slice, and original material;
- browsing Corpus history and explicitly adding selected entries to learning
  or review without requiring automatic recommendations;
- presenting listening review, perceptual repair, and further listening contexts;
- source discovery, acquisition, preview, executor selection, production-task
  and delivery progress, and recovery UX on desktop and mobile.

App does not define canonical material validity, Speech Structure truth,
Personal Corpus facts, capability projection semantics, provider execution, or
community registry truth.

### Semantic Runtime — `core/`

Owns the executable semantics and persistence boundaries for:

- Complete Learning Material identity and contract validation;
- Material Revisions, canonical representations, Structured Reading, Structured
  Timed Text, exact anchors/locators, and resource compatibility;
- Language Objects, Language Slices, Learner Relations, Meaningful Learning
  Episodes, Learning Observations, and Learning Facts;
- Personal Corpus and rebuildable occurrence/search projections;
- evidence qualification, Learner State, Personal L2 World projections, and
  independent reading/listening/speaking/writing capability dimensions;
- activity/attempt facts, assistance conditions, schedules, candidates, and
  explicit Learner authority;
- package validation, installation, adoption, and synchronization merge
  semantics.

Core does not own provider implementations, learner-facing navigation, fixed
activity choreography, or hosted community infrastructure.

### Learning Material Production — `gen/`

Owns the language-world compiler that turns Raw Sources into qualified,
reusable Complete Learning Materials:

- Source intake normalization and exact input identity;
- transcription and text qualification for audio/video Sources;
- Structured Timed Text and audio/text alignment;
- audio-independent text-side Sense Group analysis;
- Sentence Translation for declared Support Languages;
- Signal Facts, Speech Structure, and other material-side Speech Learning
  Representation resources;
- optional grammar, semantic, pragmatic, discourse, and contextual enrichment;
- provider/model selection, recipes, provenance, evidence classes,
  qualification, deterministic packaging, and honest failure.

Gen may emit multiple compatible resources rather than one monolithic speech
artifact. Present audio requires the full sound-processing scope in
[MODEL.md](MODEL.md); neither provider defaults nor missing analysis turn it
into an optional enhancement. Gen does not own Perceptual Guidance, Learner
State, Meaningful Learning Episodes, Personal Corpus, review scheduling, or
activity selection.

### Production Execution — target adapters, placement undecided

Owns durable Material Production Task acceptance, dispatch, input acquisition,
execution attempts, cancellation/recovery, and result publication. A personal
computer or remote service can fill this role while using the same Gen
compiler and material contract. Gen retains provider execution and material
qualification; Model Providers do not become task or material authorities.

The executor reports production outcome separately from each recipient's
delivery/readiness state. It does not adopt materials on a learner's behalf,
own private learning history, or turn operational progress into learning facts.
Concrete hosting, task protocols, and source placement remain undecided.

### Device Exchange — target adapters, placement undecided

Owns device pairing/authentication, production-task transport, resumable
material delivery, and private-state replication using Core's merge semantics.
Local direct transfer is preferred; optional relay transport can store and
forward when devices are remote or not online together. A relay is independent
of the Production Executor and does not acquire canonical learning authority.

Task transport, immutable material delivery, and private learning-data
replication remain separate concerns even if they share infrastructure.
Public distribution has different access and lifecycle semantics from private
device exchange. A complete account or community system is not a prerequisite
for the first paired-device journey.

### Project Governance — root documentation

Owns the project model, product semantics, ubiquitous language,
cross-module responsibilities, learner journeys, roadmap, and current project state. Root prose does not override executable contracts or runtime
facts owned by the modules.

### Community — deferred context

Will own public package distribution, mutable listings, public Community Corpus
indexing, publishers, subscriptions, ratings, reports, moderation, and update
discovery. Hosted accounts and cross-device recovery may complement device
exchange later; they are not required for local prepared learning.

Public material distribution and private Personal Corpus synchronization remain
separate data planes even if one hosted product implements both. Repository,
protocol, service, and deployment boundaries remain undecided.

## External contexts

- **Material Sources** publish or identify Raw Sources. Discovery does not grant
  playback, download, compilation, or redistribution rights.
- **Model Providers** perform replaceable material production or
  learner-relative inference. Their outputs cross typed, provenance-bearing
  seams and never become authority merely because a model produced them.
- **External Context Providers** return supplemental authentic contexts. Their
  results remain attributed and ephemeral until ordinary material compilation
  and learning relations bring them into Listen.
- **Sensa** is a potential future peer centered on Meaning Acquisition. Listen
  has no current runtime or data dependency on it.

## Relationships

```text
Material Sources
      │ Raw Source
      ▼
App acquisition / preview (desktop or mobile)
      │ durable task and authorized inputs
      ▼
Production Executor (personal computer or remote)
      │ compiler execution using selected Model Providers
      ▼
Gen  -- qualified Complete Learning Material package --> Core
                                                               │
                                                               │ canonical model,
                                                               │ episodes, corpus,
                                                               │ learner state
                                                               ▼
                                                     App Workbench
                                                               │
                                                               ▼
                                                       Learning Experience

App  <---- tasks / delivery / private sync ----> Device Exchange
Core <---- private merge semantics ------------> Device Exchange
App  <---- discovery / publishing -------------> Community

listen -----> project meaning and governance links
```

## Authority matrix

| Concern | Authority |
|---|---|
| Project theoretical model and durable invariants | `listen` |
| Product principles and ubiquitous language | `listen` |
| Detailed learner-facing Activity and scaffold UX | `app/` |
| Unified Workbench and its material/Activity views | `app/` using Core semantics |
| Source discovery, acquisition, preview, and production progress UX | `app/` |
| Durable task execution, recovery, and result publication | Production Execution |
| Device pairing, task transport, and private material delivery | Device Exchange |
| Complete Learning Material executable contract | `core/` |
| Structured Timed Text, anchors, locators, and compatibility | `core/` |
| Language Slice, episode, Personal Corpus, and learner facts | `core/` |
| Evidence, Learner State, and capability projection semantics | `core/` |
| Raw Source derivation and provider execution | `gen/` |
| Canonical audio/text production and alignment | `gen/` |
| Sentence Translation production | `gen/` |
| Signal Facts and Speech Structure production | `gen/` |
| Perceptual Guidance selection and presentation | Core semantics + App experience |
| Package validation, installation, and adoption | `core/` |
| Public package discovery and distribution | Community |
| Private-state replication | Device Exchange using Core merge semantics |
| External context results | External provider with attribution and limits |

## Stable seams

### App through Production Executor to Gen: material production intent

App supplies the exact learner-authorized Raw Source, target material identity,
declared Target/Support Languages, reusable compatible inputs, and requested
Complete Learning Material contract. Gen owns provider execution, derivation,
qualification, progress, cancellation, retry, provenance, and immutable output.

The target executor persists dispatch and attempt state independently of the
App connection, and carries compiler progress and outcomes back to the App.
Executor placement and Model Provider choice are independent. Moving execution
does not change the required material contract or promote raw provider output
to canonical learning input.

App does not prescribe provider steps, and Gen does not decide how a Learner
will experience the result.

### Gen to Core: qualified material-side artifact

The seam is a versioned, data-only Content Package carrying one qualified
Learning Edition: canonical text and Structured Reading, translation, text-side
groups, and, when audio is present, the audio, Structured Timed Text, and full
material-side speech resources. Optional enrichments, exact dependencies,
provenance, evidence class, and compatibility remain explicit.

Core validates identity and the modality-aware contract before exposing the
composition as Complete Learning Material. Installed candidates do not silently
become learner facts or overwrite adopted material.

### Core to Workbench: unified material consumption

Core validates and organizes processed material resources and supplies their
canonical semantics and learning projections to the App Workbench. The
[unified consumption boundary](MODEL.md#unified-workbench-consumption) applies
to text-only, audio, video, and later-enriched materials alike.

App owns adaptive views, components, and Activity modes within that Workbench;
it does not bypass Core to interpret provider-specific Gen results as material
authority. TTS enrichment and Corpus-selected learning/review use the same
boundary rather than separate material consumers. Source preview and Corpus
browsing remain distinct journeys, not additional formal-learning workbenches.

### App to Core: learner intent and factual outcomes

App expresses material choice, activity intent, bounded Slice/Focus,
assistance conditions, attempts, explicit judgments, and observable outcomes.
Core records durable facts and returns canonical reads and projections.

UI state, clickstream, provider configuration, and model prompts do not become
shared semantic authority.

### Material facts to learner-relative guidance

Signal Facts and Speech Structure are reusable material-side resources.
Perceptual Guidance is derived at experience time using the current Slice,
Activity, recent failure, Learner State, prior meaning knowledge, and available
supports.

The seam must preserve why a cue is available, what evidence supports it, and
what assistance the Learner actually received. A generated explanation cannot
rewrite the underlying Signal Facts or learner history.

### Client to Device Exchange and Community

Public compiled material and private learning history use separate authority,
privacy, lifecycle, and deletion semantics. Public artifacts are
content-addressed and replaceable; Personal Corpus entries and meaningful
learner facts are authenticated, mergeable, and learner-owned.
Production completion does not establish delivery or local readiness; each
recipient validates required resources through Core before learning.

## Architectural invariants

- Raw Source and Complete Learning Material are different lifecycle stages.
- Desktop and mobile share learning semantics and retain local prepared learning.
- Production Executor placement and Model Provider choice are independent.
- Production tasks, material delivery, and private learning-data replication
  have separate lifecycles and authority.
- Formal Learning Activities consume only a validated Complete Learning
  Material contract.
- Processed materials reach one unified App Workbench through Core; Workbench
  views and Activity modes vary without bypassing the semantic boundary.
- Current formal learning starts from audio/video; standalone text material
  and text-source TTS are deferred.
- Present audio receives the full sound-processing scope.
- Canonical audio, when present, and canonical text represent one Material Revision.
- Structured Reading supplies audio-independent coordinates; Structured Timed
  Text binds them to exact audio.
- Sentence Translation is required for the declared learner-facing Support
  Language; other explanations are optional enrichments.
- Speech Learning Representation spans multiple qualified resources and never
  collapses into one provider-specific artifact.
- Predicted, estimated, canonical, aligned, and observed speech evidence remain
  distinguishable.
- Sense Group and Prosodic Chunk remain separate concepts and lifecycles.
- Sense Groups are text-side representations used as help within the current
  audio/video listening journey; they are not Prosodic Chunks.
- Gen owns material-side representation; learner-relative Perceptual Guidance
  remains in the learning world.
- Language Slices point back to the original Material Revision and context.
- Saved listening Slices retain exact audio/text coordinates; new resources
  never rewrite earlier episode facts.
- Personal Corpus facts outlive packages, models, projections, and indexes.
- Exposure and clickstream do not automatically become learner state.
- Reading, listening, speaking, and writing remain independent dimensions.
- Review scheduling and Acquisition Experience selection remain separate.
- Public material never contains private Meaningful Learning Episodes.
- Sensa integration remains a future option, not a present architectural
  dependency.
