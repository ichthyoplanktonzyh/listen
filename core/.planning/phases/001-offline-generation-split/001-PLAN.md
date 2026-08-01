# Offline Generation Split Plan

## Slice

1. Inventory the current whole-media ASR and word-timing implementations and
   distinguish them from learner-recording and realtime ASR.
2. Add a producer-native media-to-package interface with a deterministic fake
   adapter and retain LLTimeline only as a compatibility command.
3. Add a dedicated Core atomic package-import repository operation with
   candidate-only and idempotent semantics.
4. Compare native and legacy paths with fixed fixtures, inspect the native
   output through Core, and run strict local validation.
5. Mark the old whole-media paths as legacy; defer deletion until a later
   production cutover slice.

## Acceptance

- Native output contains one Subtitle Text Track and its dependent Word
  Timeline and passes the v1 inspector.
- Identical input and configuration produce identical archive bytes.
- Reimport creates no duplicate track or analysis resource.
- Import never changes an existing active resource and never creates an active
  selection from package state.
- Any write failure rolls back track, resource, active-selection, and corpus
  effects together.
- Fixed native and LLTimeline-compat fixtures agree on learner-visible subtitle
  and word-timing semantics.

## Progress

The contract inspection and candidate-only Core import slice is implemented and
covered by the strict local gate. An unpublished external-producer prototype
has passed deterministic fake/command-adapter tests, the legacy semantic
comparison, and the Core inspector. It has no remote handoff, release, or
production-model smoke evidence yet.

Core now also has an additive local-path HTTP adapter for exact-media package
import. It returns the imported track and structured receipt, preserves the
candidate-only/idempotent persistence semantics, and exposes stable redacted
invalid-package and media-mismatch errors. The contract remains unreleased.

Production cutover and legacy deletion remain open. No existing Core
whole-media, learner-recording, realtime, or `scripts/timeline-production`
implementation is removed by this slice.
