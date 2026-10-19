# Content package integration fixtures

`listen-gen-r4-rich.listenpkg` is a deterministic package produced by
`listen-gen` 0.3.0 from merge commit
`42649d9f3687bdc9374151efcbc827c6a4dae61b`. It contains Subtitle Text Track,
Word Timeline, Sense Group Analysis, Word Acoustics, Prosody Analysis with
explicit Prosodic Chunk spans, and audio-backed Phone Timeline resources.

Package SHA-256:
`8ff4534c23892cec347d803e6d3d76ce82a8d60ba5d034b93bedb36f93d03577`.

The persistence integration test imports this package twice and verifies that
Core keeps every projected resource candidate-only and idempotent, never
activates a resource, and does not regenerate a legacy Chunk Timeline. Set
`LISTEN_GEN_R4_PACKAGE` to test another locally generated package with the same
deterministic media fixture fingerprint.
