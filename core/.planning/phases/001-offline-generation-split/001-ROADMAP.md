# Whole-Media Generation Cutover Roadmap

> Accepted direction: 2026-08-08 CST
>
> GitHub umbrella: [listen-core#111](https://github.com/ichthyoplanktonzyh/listen-core/issues/111)
>
> Gen execution: [listen-gen#4](https://github.com/ichthyoplanktonzyh/listen-gen/issues/4)
>
> App cutover: [listen-app#100](https://github.com/ichthyoplanktonzyh/listen-app/issues/100)

## Outcome

Reusable, content-bound whole-media generation has one external seam:

```text
listen-app
  verifies and starts one pinned producer, presents progress/cancel/recovery
      |
      v
listen-gen
  media bytes + generation configuration
      -> versioned machine events
      -> deterministic native .listenpkg
      |
      v
listen-core
  bounded validation -> atomic candidate import -> explicit active lifecycle
```

The interface is the Gen machine protocol plus the Core-owned content-package
contract. Provider flags, model protocols, subprocesses and intermediate files
stay inside Gen. Core never calls Gen and Gen never imports Core source or
touches Core persistence.

Core retains learner-recording transcription, realtime conversation, TTS,
learner-dependent LLM/judgment, learner-owned indexes, package validation,
candidate installation, active selection and durable learning history.

## Current Baseline

The first extraction slice is working rather than hypothetical:

- `listen-gen` commit `41a53336` has native media preprocessing, ASR adapters,
  machine events, cancellation, deterministic package production and a
  verifiable release bundle;
- `listen-app/listen_gen.lock.json` pins that exact producer and verifies the
  release and artifact bytes before launch;
- Core commit `b980a206` exposes bounded content-package inspection and atomic,
  idempotent, candidate-only HTTP import;
- the pinned three-repository fixture round trip passes:
  Gen release bundle -> native `.listenpkg` -> Core HTTP import -> candidate
  receipt;
- Core still contains forced alignment, content-bound
  SoundLine/phonetic/foundation producers and `scripts/timeline-production`;
  whole-media transcription jobs/routes were deleted in the R1 Core slice;
- App still contains reachable clients and UI for Core's legacy whole-media
  transcription jobs;
- Gen's ASR tools are still delivered through the Core runtime payload.

The old path is now duplication, not a fallback to extend.

## Sequencing

### R0 — Trust the cutover evidence — complete

Owner: App, with Core/Gen fixtures.

- Make `tool/verify_local_content_package_roundtrip.sh` fail unless the Flutter
  E2E case actually ran and passed. A dependency/setup failure must not print
  `verify-roundtrip: OK`.
- Register or remove the undeclared `e2e` tag warning.
- Make `tool/repo_status.py` select the intended Core checkout rather than an
  arbitrary sibling worktree and understand Gen's contract lock.
- Keep the round trip credential-free and model-free.

Exit: one command proves the exact pinned producer bytes can generate a package
accepted by the exact pinned Core runtime, and every skipped or failed stage is
non-zero.

Completed by [listen-app#101](https://github.com/ichthyoplanktonzyh/listen-app/pull/101)
(merge commit `2531f2a`). The gate resolves App dependencies offline from the
caller's existing Pub cache, verifies a Flutter JSON event report for the exact
non-skipped passing E2E case, and prints success only after every build, verify,
test, report, and checkout-cleanliness check succeeds. Its regression suite
covers dependency, Gen build/verify, Core build, Flutter runner, skipped,
failed, missing, and malformed-report failures. The real credential-free run
proved pinned Gen `41a53336` -> native `.listenpkg` -> pinned Core `b980a206`
HTTP import, then exported Core state with no active Word, Phone, or Chunk
Timeline selection.

### R1 — Cut over and delete whole-media ASR in Core — Core slice implemented

Owners: Core and App. Gen's existing ASR path is the replacement.

The Core slice of R1 is implemented on the current branch:

- `TranscriptionCoordinator` was split by lifecycle into
  `RecordingTranscriptionCoordinator`; learner-recording transcription, its
  model/provenance and the `/v1/recording-transcriptions*` contract are
  retained.
- Whole-media transcription job lifecycle, routes, DTOs/events, the
  `transcription-job-changed` event, the SQLite CAS job store and downstream
  legacy triggers (including the sound-line auto-trigger) were removed.
- Deleting the published `/v1/transcription/jobs*` surface is a consumer
  breaking change, so the unreleased contract advances to major `2.0.0`.

Remaining R1 work is the App cutover:

- Remove the App repository, view-model, panels and actions that call
  `/v1/transcription/jobs*` for media.
- Route missing-transcript preparation only through the pinned Gen package
  journey.
- Decide which remaining Core learner/realtime paths truly require
  `whisper-cli`, and stop making Core implicitly publish Gen-only runtime
  inputs.

Exit: App contains no Core whole-media transcription call; Core contains no
whole-media ASR job or provider ownership; learner recording and realtime tests
remain green. Core's half of that exit is met; the App half tracks
[listen-app#100](https://github.com/ichthyoplanktonzyh/listen-app/issues/100)
and must land before `2.0.0` is published.

This slice supersedes [listen-core#103](https://github.com/ichthyoplanktonzyh/listen-core/issues/103),
whose plan kept whole-media ASR orchestration in Core.

### R2 — Produce aligned Word Timeline natively in Gen

Owner: Gen.

- Add a Gen-internal, provider-neutral alignment interface with a deterministic
  fake adapter and at least one production adapter.
- Emit content-package v1 `word_timeline` directly, with exact Subtitle Text
  Track dependency, provider/model/config provenance and typed timing source.
- Preserve a valid subtitle package when optional alignment honestly degrades;
  cancellation, timeout and process reaping remain explicit.
- Reuse behavioral fixtures and qualification evidence from Core, but do not
  copy the legacy `scripts/timeline-production` module tree.

Exit: the first-class `whisper-cpp` path can produce a useful aligned package,
and Core accepts it without a producer-specific interface.

[listen-core#9](https://github.com/ichthyoplanktonzyh/listen-core/issues/9)
remains relevant as an algorithm-quality backlog, but reusable production
implementation belongs in Gen.

### R3 — Resolve Chunk/Prosody semantics

Owner: Core contract/domain, coordinated with Gen and App.

Core foundation preparation currently persists `ChunkTimeline`, while
content-package v1 exchanges `word_acoustics` and `prosody_analysis`; Core also
cannot yet project `prosody_analysis` losslessly. This must be resolved before
claiming foundation parity.

- Decide which existing Chunk behavior is a Prosodic Chunk resource, which is
  a derived playback projection and which should be deleted.
- Prefer the existing package dependency graph over adding another near-synonym
  solely to preserve a legacy Core type.
- Define Core projection/readiness semantics for imported Prosody without
  silently activating candidates.
- Keep Sense Group semantically independent from acoustic/prosodic grouping.

Exit: an imported package can satisfy the agreed foundation slots without Core
regenerating an equivalent content-bound resource.

### R4 — Add rich package producers

Owner: Gen; Core owns schema/projection changes.

Migrate in dependency order:

1. `sense_group_analysis` from Subtitle Text Track;
2. `word_acoustics` from Word Timeline plus normalized audio;
3. `prosody_analysis` from Word Timeline, Word Acoustics and optional Sense
   Group evidence;
4. `phone_timeline` from separately authorized, qualified audio-backed phone
   analysis.

Every slice uses the same Gen operation and package seam, deterministic local
fixtures, exact digest/provenance assertions, cancellation and redacted failure
tests, and Core inspector/import compatibility. Low-quality phone evidence
abstains; it never fabricates observed speech.

Existing Core issues [#13](https://github.com/ichthyoplanktonzyh/listen-core/issues/13),
[#6](https://github.com/ichthyoplanktonzyh/listen-core/issues/6) and related
algorithm backlogs remain quality work, not reasons to keep production in Core.

### R5 — Retire the legacy production tree

Owners: Core, App and release assembly.

- Delete `scripts/timeline-production`, whole-media forced-align/runtime glue
  and release inputs used only by the removed path.
- Delete dead Core HTTP/event contracts and App compatibility parsing.
- Bind the Gen release to an explicit verified runtime/toolchain identity.
- Keep shared `ffmpeg`/`ffprobe` delivery explicit because App media scanning
  and playback helpers also consume them.
- Update current architecture/planning facts and leave historical decisions as
  superseded records.

Exit: deleting Gen would make reusable whole-media generation disappear rather
than reappear across Core and App; deleting the Core consumer would not remove
the open producer or package format.

## Cutover Policy

This is a single-owner project. Do not create feature flags, compatibility
wrappers or a long dual-run period. Once a slice has:

1. deterministic replacement fixtures;
2. pinned cross-repository success evidence;
3. cancellation, failure-redaction and provenance coverage; and
4. direct-consumer cutover,

delete the superseded implementation in that slice.

Published artifacts and contracts remain immutable. Internal code and
unreleased routes are not preserved merely because they already exist.

## Completion

- Gen is the only reusable whole-media producer.
- App launches one immutable Gen release and has no Core whole-media job UX.
- Core owns consumption and learning semantics, not offline producer runtimes.
- Native packages can carry the agreed foundation resources without a legacy
  LLTimeline production step or duplicate Core regeneration.
- The legacy production tree and its exclusive runtime/release code are gone.
- The three linked GitHub issues contain the authoritative execution status;
  this document records stable sequence, ownership and exit criteria.
