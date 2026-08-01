# Offline Generation Split Context

## Decision

The first extraction slice moves the expensive, reusable whole-media path

```text
media -> ASR Subtitle Text Track -> Word Timeline -> deterministic .listenpkg
```

behind the `contracts/content-package/v1` exchange boundary. A producer emits
the native package resources directly; LLTimeline conversion is migration
compatibility and is not the new production interface.

## Core Boundary

Core continues to own media fingerprints, bounded package inspection,
candidate persistence, explicit active selection, durable learning records,
and the learner-facing consumption runtime. Package import is candidate-only:
it cannot activate a resource even when a family has no active selection, and
it cannot replace or downgrade an existing active selection.

Core also continues to own learner-recording transcription and realtime
conversation behavior. Those workflows are learner-dependent or genuinely
realtime and are not part of reusable offline content generation.

## Migration Constraint

The current whole-media transcription runtime and
`scripts/timeline-production` remain temporarily available as legacy migration
sources. They are not deleted in this slice. Cutover requires a native producer
fixture to pass Core inspection and atomic import with equivalent subtitle and
word-timing semantics. Removal can happen only after the new path is selected
in production and that cutover is verified.

## Safety

- Normal tests use fake or committed fixture ASR output and spend no model
  credit.
- A package contains no local paths, credentials, raw provider responses,
  learner facts, or Core lifecycle state.
- Import validation completes before persistence starts.
- Idempotency and rollback are properties of one dedicated package-import unit
  of work, not the legacy LLTimeline import policy.
