# Project State

> Updated: 2026-10-19 CST.

## Repository transition

The owner accepted [decision 0005](decisions/0005-single-repository-development.md):
App, Core, Gen, and project documentation now share this repository. The
migration changes source topology and development/release workflow; it does
not implement the product model below. Validation and import evidence are in
[the migration record](docs/development/monorepo-migration.md).

## Current position

Listen's project-level theoretical model has converged. The authority is now
[MODEL.md](MODEL.md): a language world compiles Raw Sources into Complete
Learning Materials; a separate learning world turns Learner–Material relations
into Activities, Language Slices, Meaningful Learning Episodes, Personal
Corpus, learner-state projections, and new Acquisition Experiences.

The implementation remains in **Product Alpha**, but its previous Phase 1
documentation was based on the superseded partial-material/capability-completion
model. App, Core, and Gen must now be audited and realigned against the Complete
Learning Material contract, revised by
[decision 0004](decisions/0004-text-learning-and-full-sound-processing.md).
Earlier code and plans are evidence about current
implementation, not authority over the new model.

Speech Learning Representation is intentionally defined above individual
artifacts. Current local Core/Gen evolution already supersedes parts of older
GitHub wording: Signal Facts and Speech Structure may span Word/Phone timing,
Word Acoustics, connected-speech analysis, and Prosody Analysis; semantic Sense
Groups remain distinct from Prosodic Chunks; the retired legacy Chunk Timeline
must not be restored as the project model. Learner-relative Perceptual Guidance
remains a Learning Experience concern rather than fixed Gen output.

## Confirmed project decisions

- Listen is an authentic-material language-capability acquisition system;
- the project is divided into a language world and a learner-relative learning
  world;
- Raw Source, material production, and Complete Learning Material are distinct
  lifecycle stages;
- formal learning begins from a validated Complete Learning Material;
- text-only materials support formal learning without TTS;
- Sense Groups are text-side and support learning without audio;
- present source audio and requested TTS receive the same full sound-processing
  scope, not minimum processing plus optional speech enhancements;
- present Canonical Audio and Canonical Text form one aligned Material Revision;
- Structured Reading provides text coordinates; Structured Timed Text adds
  exact audio mappings when audio exists;
- Sentence Translation for a declared Support Language belongs to the
  material contract;
- Speech Learning Representation follows Signal Facts -> Speech Structure ->
  Perceptual Guidance and is not one provider-specific artifact;
- Gen compiles Language Experience; Core/App compile Learner-relative Learning
  Experience;
- Learning Activity describes a cognitive relation, not a page or feature;
- Language Slice is the re-enterable atomic experience pointer of the Personal
  Corpus;
- Personal Corpus Entries combine Slice, Learner Relation, and Meaningful
  Learning History;
- text-only Slices are valid; later TTS never rewrites earlier learning history;
- early Corpus use is freely browsable, with explicit selection into learning
  or review; automated next-experience selection is not a prerequisite;
- Exposure, Attention, Learning, and Acquisition remain distinct;
- Personal Corpus facts remain separate from Personal L2 World and Learner
  State projections;
- reading, listening, speaking, and writing are independent capability
  dimensions;
- durable state remains simple while episode evidence remains rich;
- review combines reactivation, re-perception, and transfer;
- Review Schedule answers when; Acquisition Experience answers what;
- advanced policy and Sensa integration remain evidence-gated future work.

## Superseded baseline

Neither arbitrary Raw Source import nor mandatory audio for every text material
defines formal learning. A text-only material can satisfy its text-learning
contract without TTS; present audio requires the full sound-processing scope.
The former universal audio/TTS requirement in decision 0003 is superseded, but
its Source/learning boundary and honest evidence principles remain.

The exact rendition/resource identity work remains useful where it supports
source fidelity, stable anchors, provenance, and compatibility. It no longer
defines the formal learning boundary.

## Next transition

Create a replacement project execution plan for **Phase 1: Complete
Learning Material Alpha**. Before implementation, audit:

1. App Source/preview versus formal-learning journeys;
2. Core material identity and modality-aware contract validation;
3. Gen text-side production, including Sense Groups, and full audio processing
   for source audio or requested TTS;
4. current local speech resources and evidence classes versus older published
   contracts;
5. migration and preservation of existing learner facts;
6. text-only and audio-backed Source -> material -> Activity proofs, followed
   by learner-selected Personal Corpus re-entry.

The pre-convergence Phase 1 completion and validation plans are historical
inputs. They must not be executed as the active project plan without being
replaced or explicitly reconciled with [MODEL.md](MODEL.md).
