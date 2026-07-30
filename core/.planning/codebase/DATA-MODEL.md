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
- versioned LLTimeline/resource schemas are compatibility boundaries;
- destructive migration or cascade behavior requires explicit requirement,
  tests, and release/migration notes.

Detailed aggregate evolution should be documented beside the active backend
phase and reflected here only when it becomes current code fact.
