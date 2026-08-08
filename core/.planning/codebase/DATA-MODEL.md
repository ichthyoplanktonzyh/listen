# Data Model

The durable model is owned by `domain` plus repository interfaces in
`application`, with SQLite implementations in `persistence-sqlite`.

The current language-learning domain map and Rust/OpenAPI terminology mapping
are documented in
[`docs/domain/language-learning-model-v3.md`](../../docs/domain/language-learning-model-v3.md).
The canonical ubiquitous-language glossary is
[`CONTEXT.md`](../../CONTEXT.md).

Key invariants:

- stable IDs, not display strings or file paths, identify durable records;
- `LearningObject` is a concept family, not a universal persisted parent;
- `ContentDocument` is a conceptual composition of media and at least one
  language-known text track; no aggregate or database invariant currently
  prevents media-only rows or language-null tracks. `ContentSelection` is
  represented by purpose-specific bounded snapshots rather than one canonical
  type;
- activity and attempt are concept families whose concrete records retain
  purpose-specific invariants;
- learning assets/history outlive replaceable media, subtitles, and generated
  resources;
- source snapshots preserve provenance/history but do not impersonate missing
  requested media/audio;
- `MediaAvailability::Missing` covers detached LLTimeline media and lost real
  sources; a synthetic `lltimeline://` identity cannot become available through
  an availability-only update;
- attempts, observations/evidence, judgments, adjudications, projection
  proposals, user decisions, overrides, and effective capability remain
  distinguishable;
- lexical capability uses independent reading, listening, speaking, and
  writing dimensions; `unassessed` is not `not_acquired`;
- Review, Listening Inbox, Hunting, proposal, and gap records keep their own
  identities even when a future Learning Agenda aggregates their presentation;
- ADR 0035 defines archive/restore as the target User Sentence Pattern
  lifecycle and keeps future Personal Content Erasure separate. The current
  runtime still exposes a deprecated-target cascade DELETE until the
  persistence and contract slices implement that migration;
- versioned LLTimeline/resource schemas are compatibility boundaries;
- `LearningPreparationRun` is an application-owned orchestration record, not a
  Learning Object or generic resource. It stores exact source selection,
  input/plan fingerprints, revision, retry lineage, and four named foundation
  step slots (WordTimeline, Prosody, SenseGroup, plus derived audible
  structure). Only queued/running/cancelling runs participate in target-level
  single-flight;
- Prosody Analysis is the single semantic source for the Prosodic Chunk
  foundation slot: a word-anchored resource projected losslessly from
  content-package v1 `prosody_analysis` (schema `listen.resource.prosody-analysis.v1`).
  Imported analyses are persisted as candidates and never activated by import
  or readiness. Prosodic chunk spans are declared by the resource; only their
  playback times are derived through the parent Word Timeline. Sense Group
  analysis is a separate resource family with a separate lifecycle. Legacy
  `ChunkTimeline` remains readable but is not a foundation fallback;
- destructive migration or cascade behavior requires explicit requirement,
  tests, and release/migration notes.

Detailed aggregate evolution should be documented beside the active backend
phase and reflected here only when it becomes current code fact.
