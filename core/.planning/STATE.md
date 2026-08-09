# State

> Updated: 2026-08-10 CST

## Position

- Repository: `ichthyoplanktonzyh/listen-core`
- Default implementation owner: Codex
- Consumer: `ichthyoplanktonzyh/listen-app`
- API generation: `1`
- Contract version: `3.2.0` (additive durable Learning Material lifecycle;
  published in `v0.7.0-phase1.2`)
- Runtime/workspace version: `0.7.0`
- Published split baseline: `v0.7.0-split.4`

## Current Work

Product Alpha Phase 1, Single-user Core Loop Alpha, is active in the canonical
project roadmap. Core phase
[`003-single-user-material-retention`](phases/003-single-user-material-retention/003-CLOSEOUT.md)
is complete and published as `v0.7.0-phase1.1` with contract `3.1.0`.

Core phase
[`004-durable-learning-material`](phases/004-durable-learning-material/004-CLOSEOUT.md)
is complete and published as `v0.7.0-phase1.2`. Contract `3.2.0` adds path-free
text, media and mixed Learning Materials, immutable revisions, explicit
material membership, media-to-material
resolution, and SQLite v59 backfill. Material membership synchronizes the
legacy retained-media projection for compatibility. The clean tagged runtime
passed archive verification, startup handshake, health and graceful-shutdown
smoke outside the source tree. Consumer pinning and cross-repository acceptance
are the next transition; no new Core implementation phase is active.

## Completed Foundation

Content Package v2 is complete as a contract and producer vertical. It defines
one immutable Package Release per Learning Edition snapshot, with separate
release, resource, blob, Media Rendition and delivery identities. Core now owns
the v2 contract, three golden material shapes, bounded two-pass inspection and a
pure candidate Installation Plan beside unchanged v1 behavior; Gen produces
deterministic hybrid/referenced-media and embedded carriers. Credential-free
Gen-to-Core probes cover both delivery modes. This slice does not force
text-only material into the current media-centered persistence or change the
App/HTTP contract.

The owner also fixed the learner-journey constraint: import or discover a
material, use it immediately, enrich it when useful, retain it intentionally,
and rediscover it through the corpus. RSS/Atom subscriptions are a first-class
Content Source entry path. Package Installation stays candidate-only while a
separate explicit Learning Edition Adoption intent lets App keep **start
learning** simple without leaking package internals.

The owner has accepted the whole-media producer cutover roadmap. Content-package
v1 has bounded inspection, typed projection, and a candidate-only atomic import
seam. `listen-gen` now has a remote, a deterministic release bundle and native
Subtitle Text Track, aligned Word Timeline, Sense Group, Word Acoustics,
Prosody Analysis and optional qualified audio-backed Phone Timeline production.
`listen-app` pins Gen merge `42649d9f` as tool `0.3.0`, verifies the artifact
before launch and owns the package-generation journey.

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

R3 is complete via Core PR
[#118](https://github.com/ichthyoplanktonzyh/listen-core/pull/118)
(merge `81a1977`). Core now owns a
`ProsodyAnalysis` domain resource that is the single semantic source for the
Prosodic Chunk foundation slot, projected losslessly from content-package v1
`prosody_analysis`. Package import consumes the resource as a candidate (typed
`Consumed` receipt), and foundation readiness reuses an imported analysis whose
parent Word Timeline matches the selected timeline without regenerating an
equivalent resource and without activating it. Playback times are derived
through the Word Timeline (no persisted time duplication). Chunk spans are
package-declared rather than inferred from word roles. Sense Group analysis stays a separate resource family with a
separate lifecycle. Foundation no longer generates legacy `ChunkTimeline` as a
fallback; R5 retired that duplicate family. The new
resource family is exposed additively through
the LLTimeline document (`prosody_analyses` / `active_prosody_analysis_id`).

R4 is complete. Gen PR
[listen-gen#6](https://github.com/ichthyoplanktonzyh/listen-gen/pull/6)
(merge `42649d9f`) added the four rich producers in dependency order behind the
same package operation. Deterministic fixtures cover exact provenance,
degradation, cancellation, timeout/process reaping and redacted failures;
unqualified phone evidence abstains. Core PR
[#120](https://github.com/ichthyoplanktonzyh/listen-core/pull/120)
(merge `0baff6f`) committed a six-resource Gen package and proved atomic,
idempotent, candidate-only import with no legacy ChunkTimeline generation.
Core PR [#121](https://github.com/ichthyoplanktonzyh/listen-core/pull/121)
published contract `2.1.0` and runtime `0.7.0` as immutable release
`v0.7.0-split.4` from `b0b0dc81`.

App PR [listen-app#105](https://github.com/ichthyoplanktonzyh/listen-app/pull/105)
(merge `1711eff5`) pins that Core release and Gen `0.3.0`. Its
credential-free, model-free three-repository gate generates and imports all six
resources, checks exact producer identities, consumes Word Acoustics into the
timeline artifact, leaves all imported analyses as candidates, and confirms no
active Word, Phone or legacy Chunk Timeline.

R5 is complete. Core PR
[#123](https://github.com/ichthyoplanktonzyh/listen-core/pull/123)
(merge `105568ed`) deleted
`scripts/timeline-production`, the legacy `ChunkTimeline` domain and
persistence, the LLTimeline chunk fields, and the eight
`/v1/*chunk-timelines*` HTTP operations with their OpenAPI schemas and
generated-client identity. Removing published operations and LLTimeline
fields is breaking, so the current contract is `3.0.0`; its locally assembled
contract/runtime archives were hash-verified and App pins those identities
without a Core GitHub release URL. Corpus chunk occurrences now project from the
active Prosody Analysis (the sole prosodic-chunk semantic source); Sense Group
stays independent; content-package import stays candidate-only and foundation
preparation never regenerates a chunk representation. Historical migration
0013 stays immutable and a new forward migration v57 drops the retired
`chunk_timeline_runs` storage from upgraded databases. Shared
`whisper-cli`/`ffmpeg`/`ffprobe` remain for learner-recording transcription,
realtime and SoundLine paths; only inputs exclusive to the retired
whole-media production path were removed. Gen PR
[#7](https://github.com/ichthyoplanktonzyh/listen-gen/pull/7) (tool `0.4.0`)
binds the release manifest to a strict verifier-checked runtime/toolchain
identity and published immutable `v0.4.0` from merge `a660946a`. App PR
[listen-app#106](https://github.com/ichthyoplanktonzyh/listen-app/pull/106)
(merge `5dcf6ae`) records the final Core/Gen identities; the real model-free
six-resource round trip passes against that pinned stack.

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

1. Complete the consumer pin to `v0.7.0-phase1.2` and the material lifecycle
   cross-repository acceptance against those exact artifacts.
2. Retain `v0.7.0-split.4` as the immutable R4 baseline. App R5 now pins Gen
   merge `a660946a` / tool `0.4.0` and Core merge `105568ed` / contract
   `3.0.0` / runtime `0.7.0`; the Core archives are local-only and verified by
   exact SHA-256, while Gen `v0.4.0` is published immutably.
3. Treat Content Package v2 as the completed release/inspection/producer seam;
   durable Learning Material now exists independently, while Package
   Installation, Learning Edition Adoption and hosted catalog behavior remain
   later explicit slices.
4. Split core issue #80 into a production-model slice followed by an
   app-originated contract slice; do not promote the English-centric spike
   variant enums into the multilingual contract.
5. Keep immutable `v0.7.0-split.4` as the R4 consumer baseline. Contract
   `2.1.0` preserves the R1 whole-media job deletion and additively exposes the
   R3 Prosody Analysis projection; learner-recording transcription, provider
   and model routes remain unchanged.
6. Run the Apple Silicon short-audio cascade smoke only with explicit model
   download/live-inference authorization.
7. Remove the exact `local-runtime` HTTP route debt allowlist one route module
   at a time.
