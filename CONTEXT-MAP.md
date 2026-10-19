# Listen Context Map

This map assigns authority across the language world and learning world defined
in [MODEL.md](MODEL.md). It describes durable seams, not source directories,
transport shapes, or current implementation completeness.

## Contexts

### Learning Experience — `listen-app`

Owns the learner-facing learning world:

- selecting and resuming a Learning Activity;
- presenting a Complete Learning Material;
- owning the unified Workbench that consumes Core-provided materials and
  learning semantics across modalities and Activity modes;
- supporting text-only learning and Sense Group interaction without TTS;
- requesting TTS on Learner intent and presenting full audio-processing status;
- establishing a Language Slice or Learning Focus;
- exposing the Minimum Sufficient Scaffold;
- turning Speech Learning Representation into contextual Perceptual Guidance;
- recording learner intent, attempts, and explicit judgments through Core;
- navigating between a Personal Corpus Entry, its Slice, and original material;
- browsing Corpus history and explicitly adding selected entries to learning
  or review without requiring automatic recommendations;
- presenting review, repair, production, and transfer experiences;
- source discovery, acquisition, preview, compilation progress, and recovery UX.

App does not define canonical material validity, Speech Structure truth,
Personal Corpus facts, capability projection semantics, provider execution, or
community registry truth.

### Semantic Runtime — `listen-core`

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

### Learning Material Production — `listen-gen`

Owns the language-world compiler that turns Raw Sources into qualified,
reusable Complete Learning Materials:

- Source intake normalization and exact input identity;
- faithful TTS for text Sources when requested, not as a text-learning gate;
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

### Project Governance — `listen`

Owns the project model, product semantics, ubiquitous language,
cross-repository boundaries, learner journeys, roadmap, durable cross-repository
decisions, and current project state. It owns no executable contract or runtime
fact.

### Community and Sync — required future context

Will own accounts/devices, private-state replication, immutable package
distribution, mutable listings, public Community Corpus indexing, publishers,
subscriptions, ratings, reports, moderation, and update discovery.

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
listen-app acquisition / preview
      │ production request and exact authorized inputs
      ▼
listen-gen  -- qualified Complete Learning Material package --> listen-core
                                                               │
                                                               │ canonical model,
                                                               │ episodes, corpus,
                                                               │ learner state
                                                               ▼
                                                     listen-app Workbench
                                                               │
                                                               ▼
                                                       Learning Experience

listen-app  <---- discovery / publishing / sync ----> Community and Sync
listen-core <---- private merge semantics ----------> Community and Sync

listen -----> project meaning and governance links
```

## Authority matrix

| Concern | Authority |
|---|---|
| Project theoretical model and durable invariants | `listen` |
| Product principles and ubiquitous language | `listen` |
| Detailed learner-facing Activity and scaffold UX | `listen-app` |
| Unified Workbench and its material/Activity views | `listen-app` using Core semantics |
| Source discovery, acquisition, preview, and production progress UX | `listen-app` |
| Complete Learning Material executable contract | `listen-core` |
| Structured Timed Text, anchors, locators, and compatibility | `listen-core` |
| Language Slice, episode, Personal Corpus, and learner facts | `listen-core` |
| Evidence, Learner State, and capability projection semantics | `listen-core` |
| Raw Source derivation and provider execution | `listen-gen` |
| Canonical audio/text production and alignment | `listen-gen` |
| Sentence Translation production | `listen-gen` |
| Signal Facts and Speech Structure production | `listen-gen` |
| Perceptual Guidance selection and presentation | Core semantics + App experience |
| Package validation, installation, and adoption | `listen-core` |
| Public package discovery and distribution | Community and Sync |
| Private-state replication | Community and Sync using Core merge semantics |
| External context results | External provider with attribution and limits |

## Stable seams

### App to Gen: material production intent

App supplies the exact learner-authorized Raw Source, target material identity,
declared Target/Support Languages, reusable compatible inputs, and requested
Complete Learning Material contract. Gen owns provider execution, derivation,
qualification, progress, cancellation, retry, provenance, and immutable output.

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

### Client to Community and Sync

Public compiled material and private learning history use separate authority,
privacy, lifecycle, and deletion semantics. Public artifacts are
content-addressed and replaceable; Personal Corpus entries and meaningful
learner facts are authenticated, mergeable, and learner-owned.

## Architectural invariants

- Raw Source and Complete Learning Material are different lifecycle stages.
- Formal Learning Activities consume only a validated Complete Learning
  Material contract.
- Processed materials reach one unified App Workbench through Core; Workbench
  views and Activity modes vary without bypassing the semantic boundary.
- Text-only material can support formal learning without TTS.
- Present audio receives the full sound-processing scope; requested TTS enters
  the same scope, not a reduced tier.
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
- Sense Group analysis and learning are available independently of audio.
- Gen owns material-side representation; learner-relative Perceptual Guidance
  remains in the learning world.
- Language Slices point back to the original Material Revision and context.
- Text-only Slices are valid; adding audio never rewrites earlier episode facts.
- Personal Corpus facts outlive packages, models, projections, and indexes.
- Exposure and clickstream do not automatically become learner state.
- Reading, listening, speaking, and writing remain independent dimensions.
- Review scheduling and Acquisition Experience selection remain separate.
- Public material never contains private Meaningful Learning Episodes.
- Sensa integration remains a future option, not a present architectural
  dependency.
