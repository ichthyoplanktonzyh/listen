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
covered by the strict local gate. `listen-gen` is now a separate remote
repository with a deterministic release bundle; `listen-app` pins commit
`41a53336` and verifies the release and artifact bytes before launch.

Core now also has an additive local-path HTTP adapter for exact-media package
import. It returns the imported track and structured receipt, preserves the
candidate-only/idempotent persistence semantics, and exposes stable redacted
invalid-package and media-mismatch errors. The receipt carries validated
resource provenance and review status while leaving opaque-resource trust
facts unknown. The contract remains unreleased.

A real three-repository fixture round trip has passed from the pinned Gen bundle
through native `.listenpkg` production into pinned Core HTTP candidate import.
The R0 gate is now fail-closed:
[listen-app#101](https://github.com/ichthyoplanktonzyh/listen-app/pull/101)
verifies structured Flutter test events, rejects every skipped or failed stage,
understands Gen's actual contract lock, resolves repository paths deliberately
from ordinary checkouts and worktrees, and asserts through exported Core state
that package import leaves all active timeline selections empty. The initial
extraction and trustworthy cutover-evidence acceptance are therefore satisfied.
Production cutover, richer native resources and legacy deletion continue under
[`001-ROADMAP.md`](001-ROADMAP.md) and the linked cross-repository issues.

Core whole-media generation is no longer a path to extend, and the R1 Core
slice has now deleted it: whole-media transcription jobs/routes, their
DTOs/events, the SQLite CAS job store and downstream legacy triggers are gone;
`RecordingTranscriptionCoordinator` retains learner-recording transcription and
the provider/model catalog. Because the deletion removes the published
`/v1/transcription/jobs*` surface, the unreleased contract is a major `2.0.0`.
Learner-recording and realtime behavior remain Core responsibilities. The App
legacy entry points and `scripts/timeline-production` remain deletion targets
after their corresponding roadmap slice exits.
