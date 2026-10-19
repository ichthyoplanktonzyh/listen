# Listen Roadmap

> Status: owner-approved model-aligned roadmap, revised 2026-09-08.

This is the project-wide outcome roadmap. It follows the project model in
[MODEL.md](MODEL.md) and does not preserve implementation sequencing from the
superseded partial-material model. Repository tasks and temporary execution
plans belong in issues or replacement Supervisor plans.

A phase is complete when its exit conditions hold across the relevant
repositories. Dates and feature counts do not advance a phase.

## Completed stage: Project Model Convergence

Listen's theoretical center has converged around:

- a language world and a learner-relative learning world;
- Raw Source -> Learning Material Compiler -> Complete Learning Material;
- audio-independent Structured Reading and Sense Groups, with Structured Timed
  Text for audio-backed interaction;
- text learning without TTS and full sound processing whenever audio is present;
- Speech Learning Representation as Signal Facts -> Speech Structure ->
  Perceptual Guidance;
- Language Slice -> Meaningful Learning Episode -> Personal Corpus;
- Personal Corpus facts distinct from Personal L2 World projections;
- independent reading, listening, speaking, and writing capabilities;
- review as reactivation, re-perception, and transfer;
- scheduling separated from Acquisition Experience selection.

The model is now the authority for product choices. Current code and earlier
execution plans may lag it and require deliberate replacement rather than
compatibility-driven preservation.

## Phase 1: Complete Learning Material Alpha — active realignment

Prove one reliable end-to-end language-world path from representative Raw
Sources to a validated Complete Learning Material that the learning world can
consume without provider knowledge.

Exit conditions:

- local document/text, audio, and video inputs plus at least one discovered
  remote Source enter one explicit Raw Source lifecycle;
- Source preview, acquisition, compilation, failure, retry, and formal learning
  remain distinct states and journeys;
- text Sources support formal text-based learning without TTS, including
  audio-independent Sense Group interaction;
- requested TTS produces faithful Canonical Audio and enters the same full
  sound-processing scope as source audio; Sources with audio produce qualified text;
- Structured Timed Text supplies stable utterance/sentence/token text spans and
  exact mappings to Canonical Audio;
- sentence-level translation exists for a declared Support Language;
- for audio-backed materials, the full scope in [MODEL.md](MODEL.md) includes
  provenance-bearing Signal Facts and
  Speech Structure, distinguishes observed/estimated/predicted evidence, and
  keeps Sense Groups distinct from Prosodic Chunks;
- the current Prosody Analysis and Word Timeline path, rather than retired
  Chunk Timeline semantics, represents Prosodic Chunks;
- Core validates the modality-aware Complete Learning Material contract and exposes
  one adopted coherent composition to App;
- Gen provider details and derivation graphs do not cross the Learning
  Boundary;
- incomplete or failed production is never presented as a complete Learning
  Material;
- absent phenomena, inapplicable analysis, insufficient evidence, unsupported
  analysis, and failed processing remain distinguishable; predictions never
  substitute for missing observation, and no reduced speech tier is introduced;
- existing durable learner facts survive the contract realignment.

## Phase 2: Personal Corpus Alpha/Beta

Make the Learner's authentic experience history the product's compounding
center rather than treating retained materials or search indexes as the Corpus.

Exit conditions:

- a Language Slice points to one exact Material Revision, Canonical Text span,
  Canonical Audio rendition/range when available, and compatible resources;
- text-only Slices and their history remain valid when audio is added later;
- a Slice remains re-enterable from local and restored state without copying a
  detached material by default;
- Meaningful Learning Episodes preserve Activity, conditions, assistance,
  attempt/judgment, outcome, context, and provenance;
- Exposure and clickstream cannot silently update acquisition or capability;
- Personal Corpus Entries combine Slice, Learner Relation, and meaningful
  history;
- occurrences and search indexes remain rebuildable projections rather than
  Corpus authority;
- Personal Corpus can serve as memory, Evidence Base, and Experience Reservoir;
- the Learner can freely browse entries and their context/history, select them
  for learning or review, and enter an Activity without automated scheduling
  or recommendation being a prerequisite;
- detached or replaced source/media resources are reported and recoverable
  without deleting learner facts;
- export, backup, recovery, and removal have explicit integrity and privacy
  semantics.

## Phase 3: Acquisition Experience Alpha/Beta

Turn Personal Corpus experiences into deliberate capability development while
keeping durable state simple and evidence rich.

Exit conditions:

- each existing Learning Activity names a cognitive intent, bounded input,
  assistance conditions, factual outcome, and resume behavior;
- reading, listening, speaking, and writing have independent evidence and
  effective capability reads;
- Personal Corpus facts, evidence qualification, Learner Inference, explicit
  Learner authority, and effective state remain separate layers;
- listening review starts audio-first from an original Slice and applies the
  Minimum Sufficient Scaffold progressively;
- material-side speech evidence can produce learner-relative Perceptual
  Guidance without becoming a fixed Gen-authored answer;
- support leads back to another act of listening and records which support was
  needed;
- transfer experiences vary sentence, speaker, rate, prosody, realization, or
  context rather than equating same-item repetition with mastery;
- Review Schedule answers when while Acquisition Experience answers what;
- representative reading, speaking, and writing paths prove that the four-
  dimension model is extensible without one mandatory workflow;
- product evidence determines whether more adaptive policies or finer durable
  subskills are warranted.

## Phase 4: Multi-device Sync Beta

Protect Complete Learning Materials, Personal Corpus, and private learner facts
across devices while keeping public material distribution separate.

Exit conditions:

- the future hosted context and repository/service boundary are chosen
  explicitly before implementation;
- identity, privacy, authentication, ownership, conflict, deletion, offline,
  and recovery semantics are documented and tested;
- Language Slices and Episodes remain meaningful when large source assets are
  temporarily unavailable;
- durable learner facts synchronize without treating replaceable packages,
  indexes, analyses, or inference projections as the same kind of state;
- interrupted synchronization is resumable and cannot silently lose accepted
  learner changes;
- another device can recover supported private state and re-enter available
  experiences.

## Phase 5: Community Learning Material Ecosystem

Allow a qualified Complete Learning Material to be produced once, discovered,
and reused by other Learners when rights permit.

Exit conditions:

- immutable Package Releases and mutable Listings have separate identities and
  lifecycle rules;
- publishers can submit qualified Learning Editions and Learners can discover,
  verify, acquire, install, and adopt them;
- packages declare Target/Support Languages, modalities, and the exact contract
  resources they satisfy;
- fingerprint and compatibility matching avoids duplicate production while
  allowing multiple editions for the same Material Revision;
- publisher, review, license, provenance, speech-evidence class, moderation,
  and security facts remain distinct;
- public artifacts contain no private Personal Corpus Entries or learner facts;
- Gen has a contributor and release path independent of one provider or model.

## Phase 6: Intelligence and Expansion

Add optional capabilities after the material, corpus, and acquisition loops are
validated. Candidates include richer language-specific speech representation,
additional acquisition experiences, external authentic-context search,
explainable experience selection, advanced transfer generation, community
feedback, and carefully validated Sensa interoperability.

These are opportunity directions, not committed features. Suggestions remain
candidates rather than commands. Shared identity or Corpus integration with
Sensa requires its own evidence and durable cross-product decision.

## Sequencing rules

- Exit conditions, not dates, advance a phase.
- Complete Learning Material contract work precedes formal learning-experience
  work that depends on it.
- Durable factual richness is preferred before irreversible inference
  complexity; simple state may be reprojected from rich history.
- Contract replacement may be coordinated across repositories while the
  project remains pre-stable, but learner facts and published immutable
  artifacts are never silently rewritten.
- Speech resource implementation may evolve independently behind the durable
  Signal Facts / Speech Structure / Perceptual Guidance boundary.
- New activities, hosted infrastructure, adaptive policy breadth, Sensa
  integration, and optional enrichments do not block earlier phases unless the
  owner changes this roadmap explicitly.
