# State

> Updated: 2026-08-08 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `2.1.0` (unreleased additive R3 projection; published consumer baseline remains `2.0.0`)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.3`

## Current Work

The owner has accepted the whole-media producer cutover roadmap. Content-package
v1 has bounded inspection, typed projection, and a candidate-only atomic import
seam. `listen-gen` now has a remote, a deterministic release bundle and native
Subtitle Text Track plus aligned Word Timeline production. `listen-app` pins
Gen merge `c3564c35` as tool `0.2.0`, verifies the artifact before launch and
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

R2 is complete. Gen PR
[listen-gen#5](https://github.com/ichthyoplanktonzyh/listen-gen/pull/5)
(merge `c3564c35`) added a provider-neutral alignment seam, deterministic
fixture and command adapters, and a first-class `whisper-cpp` adapter. Native
content-package v1 `word_timeline` resources carry exact Subtitle dependency,
alignment provider/model/config provenance and typed `asr_aligned` timing;
optional alignment failure preserves the subtitle package with typed warnings,
while timeout, cancellation, process reaping, bounded output and runtime/model
mutation checks remain explicit. Core accepts the result through the existing
producer-neutral package contract with no Core API or runtime change.

App PR [listen-app#103](https://github.com/ichthyoplanktonzyh/listen-app/pull/103)
(merge `f91d7b1`) added additive protocol compatibility coverage. App PR
[listen-app#104](https://github.com/ichthyoplanktonzyh/listen-app/pull/104)
(merge `813c58b1`) pins Gen `0.2.0` at `c3564c35`; the real model-free round
trip proves `listen-gen.alignment/0.2.0` Word Timeline provenance, exact Core
`54497e9` candidate-only import and no active timeline selection.

The R3 Core slice resolves Chunk versus Prosody semantics. Core now owns a
`ProsodyAnalysis` domain resource that is the single semantic source for the
Prosodic Chunk foundation slot, projected losslessly from content-package v1
`prosody_analysis`. Package import consumes the resource as a candidate (typed
`Consumed` receipt), and foundation readiness reuses an imported analysis whose
parent Word Timeline matches the selected timeline without regenerating an
equivalent resource and without activating it. Playback times are derived
through the Word Timeline (no persisted time duplication). Chunk spans are package-declared rather than inferred from
word roles. Sense Group analysis stays a separate resource family with a
separate lifecycle. Foundation no longer generates legacy `ChunkTimeline` as a
fallback; that readable legacy family is an R5 retirement target. The new resource family is exposed additively through
the LLTimeline document (`prosody_analyses` / `active_prosody_analysis_id`).

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

1. R2 native aligned Word Timeline production is complete; retain Gen
   `c3564c35` / tool `0.2.0` as the immutable App producer pin.
2. R3 (Core slice) resolves the Core `ChunkTimeline` versus package
   `prosody_analysis` semantics: `ProsodyAnalysis` is the single semantic
   source for the Prosodic Chunk foundation slot, imported losslessly as a
   candidate that satisfies foundation readiness without regeneration or
   silent activation; chunk spans are declared in Prosody and only playback
   times are projected through the Word Timeline; Sense Group stays independent;
   legacy `ChunkTimeline` is not a foundation fallback (R5 retirement target). Next: Gen/App
   prosody producers and consumer cutover under R4.
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
