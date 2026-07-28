# Data Model

The durable model is owned by `domain` plus repository interfaces in
`application`, with SQLite implementations in `persistence-sqlite`.

Key invariants:

- stable IDs, not display strings or file paths, identify durable records;
- learning assets/history outlive replaceable media, subtitles, and generated
  resources;
- source snapshots preserve provenance/history but do not impersonate missing
  requested media/audio;
- evidence, projections, overrides, and provider/model provenance remain
  distinguishable;
- versioned LLTimeline/resource schemas are compatibility boundaries;
- destructive migration or cascade behavior requires explicit requirement,
  tests, and release/migration notes.

Detailed aggregate evolution should be documented beside the active backend
phase and reflected here only when it becomes current code fact.
