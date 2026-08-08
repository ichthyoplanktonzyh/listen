# State

> Updated: 2026-08-08 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `2.0.0` (published; major bump for the whole-media ASR deletion)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.3`

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

R1 of the whole-media cutover is complete. Core no longer owns whole-media ASR
jobs. The combined `TranscriptionCoordinator` became
`RecordingTranscriptionCoordinator`; the `/v1/transcription/jobs*` routes,
whole-media job DTOs/events, the SQLite CAS job store, the
`transcription-job-changed` event and the sound-line auto-trigger were deleted.
Learner-recording transcription (`/v1/recording-transcriptions*`) and the
provider/model catalog routes remain. Because deleting the published
`/v1/transcription/jobs*` surface breaks the consumer contract, contract
`2.0.0` was published in immutable release `v0.7.0-split.3` from Core commit
`54497e9`.

App PR [listen-app#102](https://github.com/ichthyoplanktonzyh/listen-app/pull/102)
(merge `a3e6564`) removed every Core whole-media job client, event/DTO, center,
settings and misleading secondary-generation action. Missing-transcript and
primary generation now use the pinned Gen package journey only. The App pins
Core `54497e9`, contract `2.0.0` and runtime `0.7.0`; the real pinned
Gen `41a53336` -> native `.listenpkg` -> Core HTTP import -> candidate-only
assertion passes against those exact commits.

At R1 the packaged media tools are shared rather than Gen-only. Core retains
`whisper-cli` for learner-recording transcription and `ffmpeg`/`ffprobe` for
SoundLine and other Core media paths; the App also uses `ffmpeg`/`ffprobe` for
media helpers. The App supplies Gen tool paths only after the pinned Gen bundle
and pinned Core runtime artifact verify.

The legacy `scripts/timeline-production` tree and runtime/release inputs
exclusive to later retired production paths remain deletion targets for R5.

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

1. Add native aligned Word Timeline production in Gen under R2; R2 has not
   started as part of this closeout.
2. Resolve Core ChunkTimeline versus package Prosody semantics, then migrate
   Sense Group, Word Acoustics, Prosody and optional Phone Timeline producers.
3. Delete `scripts/timeline-production` and runtime/release inputs exclusive to
   the retired Core production path.
4. Define Content Edition, Media Rendition, Timeline Compatibility, and the
   Package Listing/Release interface before a hosted catalog journey.
5. Split core issue #80 into a production-model slice followed by an
   app-originated contract slice; do not promote the English-centric spike
   variant enums into the multilingual contract.
6. Keep immutable `v0.7.0-split.3` as the R1 consumer baseline. Contract
   `2.0.0` removes the whole-media `/v1/transcription/jobs*` surface and the
   `transcription-job-changed` event; learner-recording transcription,
   provider and model routes remain unchanged.
7. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
8. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
