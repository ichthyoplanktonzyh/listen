# State

> Updated: 2026-08-08 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `2.0.0` (unreleased; major bump for the whole-media ASR deletion)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.1`

## Current Work

The owner has accepted the whole-media producer cutover roadmap. Content-package
v1 has bounded inspection, typed projection, and a candidate-only atomic import
seam. `listen-gen` now has a remote, a deterministic release bundle and native
Subtitle Text Track production with optional provider-supplied Word Timeline.
`listen-app` pins Gen commit `41a53336`, verifies the artifact before launch and
owns the package-generation journey.

The additive local package-import HTTP contract exposes the bounded, atomic
candidate-only application seam with a typed receipt and stable redacted
failure codes. A real pinned Gen -> package -> Core fixture round trip passes.
[listen-app#101](https://github.com/ichthyoplanktonzyh/listen-app/pull/101)
made that gate fail-closed: structured Flutter events prove the
named test ran and passed, every skipped or failed stage is non-zero, repository
status resolves worktrees deliberately and reconciles Gen's contract lock, and
exported Core state proves no imported timeline became active.

The R1 Core slice of the whole-media cutover is implemented on this branch:
Core no longer owns whole-media ASR jobs. The combined `TranscriptionCoordinator`
became `RecordingTranscriptionCoordinator`; the `/v1/transcription/jobs*`
routes, whole-media job DTOs/events, the SQLite CAS job store, the
`transcription-job-changed` event and the sound-line auto-trigger were deleted.
Learner-recording transcription (`/v1/recording-transcriptions*`) and the
provider/model catalog routes remain. Because deleting the published
`/v1/transcription/jobs*` surface breaks the consumer contract, the unreleased
contract advances to major `2.0.0` with an explicit migration.

App cutover is NOT complete: `listen-app` still contains reachable clients and
UI for Core's legacy whole-media transcription jobs and must migrate them to the
pinned Gen package journey before `2.0.0` can be published and locked. The
legacy `scripts/timeline-production` tree and runtime/release inputs exclusive
to the retired Core production path remain deletion targets for R5.

Execution is synchronized by Core #111, Gen #4 and App #100. Core #103 was
closed as superseded because it kept whole-media ASR orchestration in Core.

## Established Boundaries

- Core owns canonical OpenAPI, Rust/Python backend, schemas, and runtime artifacts.
- App owns Flutter, client compatibility, lock file, and final product assembly.
- Cross-repo synchronization uses immutable releases and explicit lock updates.
- Imported monorepo planning is frozen under `archive/monorepo-baseline/`.
- Root `CHANGELOG.md` is updated only by a release owner from merged PRs.
- `ECOSYSTEM.md` records shared product decisions; repository planning remains
  limited to Core-owned facts and work.

## Known Operational Constraint

GitHub-hosted Actions cannot currently start because of account billing/spending
state. Local validation is required and CI red-with-zero-steps is infrastructure,
not code evidence.

## Next

1. Complete the App-side whole-media consumer cutover
   ([listen-app#100](https://github.com/ichthyoplanktonzyh/listen-app/issues/100)):
   cut the remaining media transcription consumers to the pinned Gen package
   journey and delete the old `/v1/transcription/jobs*` client surface; Core's
   side of that deletion is already implemented under contract `2.0.0`.
2. Add native aligned Word Timeline production in Gen.
3. Resolve Core ChunkTimeline versus package Prosody semantics, then migrate
   Sense Group, Word Acoustics, Prosody and optional Phone Timeline producers.
4. Delete `scripts/timeline-production` and runtime/release inputs exclusive to
   the retired Core production path.
5. Define Content Edition, Media Rendition, Timeline Compatibility, and the
   Package Listing/Release interface before a hosted catalog journey.
6. Split core issue #80 into a production-model slice followed by an
   app-originated contract slice; do not promote the English-centric spike
   variant enums into the multilingual contract.
7. Publish immutable `2.0.0` contract/runtime artifacts only after owner
   approval and after the App migration lands, then complete the `listen-app`
   lock and DTO handoff. `2.0.0` is a major, consumer-breaking release: it
   removes the whole-media `/v1/transcription/jobs*` surface and the
   `transcription-job-changed` event; consumers must migrate media
   transcription to the Gen package journey while learner-recording
   transcription, provider and model routes remain unchanged.
8. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
9. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
