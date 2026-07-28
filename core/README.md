# listen-core

Local-first production engine, Rust application services, loopback HTTP API,
canonical contracts, and release runtime for the listen desktop application.

This repository is the authority for `contracts/openapi/v1.yaml`. Consumer
repositories integrate through immutable contract and runtime archives; they
must pin an exact core commit rather than reading this repository's moving
`main` branch.

**New thread / maintainer handoff:** read
[`docs/handoff/project-handoff-2026-06-14-m2.0-progress.md`](docs/handoff/project-handoff-2026-06-14-m2.0-progress.md).

**Current completed release:** Milestone 1.9, version `0.7.0`.

Milestone 2.0 Phase 0 research is active. A fixed 60-slot real-speech
evaluation catalog, provider-neutral phonetic scorer, candidate registry, and
proposed provider-research ADR are available. Provider-neutral schema v9
contracts, durable jobs, alignment findings, feedback, and an opt-in desktop
surface are implemented against a deterministic research fixture. That fixture
is disabled in normal builds and is not a release provider. No real-audio
phonetic provider has passed the quality and licensing gates, so the product
does not claim any real result is `detected_in_audio`. See
[`docs/planning/milestone-2.0-phase0-research.md`](docs/planning/milestone-2.0-phase0-research.md).
The proposed open-source/commercial and extensible-provider strategy is
recorded in
[`ADR 0009`](docs/decisions/0009-open-source-commercial-and-provider-ecosystem.md);
it does not yet replace the repository's current no-license-granted state.

Collaborative M1.9 functional acceptance is complete. Independent distribution
signing and notarization are explicitly deferred from M1.9: the current Apple
Development identity supports development launches but does not make an
independently extracted archive distributable. When double-clicking a build is
blocked by local signing or AMFI, use the standard
[macOS functional testing fallback](docs/development/macos-functional-testing.md).

Milestone 1.9 adds canonical pronunciation and sentence IPA, deterministic word
timings with local current-word highlighting, and clearly labeled rule-based
connected-speech hints. Track-wide speech enhancement jobs run in the
background and support progress, cancellation, and retry. CMUdict remains an
explicit optional resource and all enhancements degrade safely without
blocking playback.

The Milestone 1 MVP targets macOS Apple Silicon and includes the core learning
loop, dual text subtitles, drag and drop, configurable subtitle presentation,
embedded text-subtitle extraction, and optional yt-dlp URL resolution. Windows,
Linux, mobile, and bitmap-subtitle learning remain later work.

Version 0.3.0 makes vocabulary learning records durable independently of media:
status-driven vocabulary books, status history, source sentence snapshots,
missing-media recovery, and versioned JSON export/import are included.

Version 0.4.0 adds responsive subtitle presets, Chinese/English UI switching,
existing TXT/CSV vocabulary import, a unified learning panel, durable personal
definitions and notes, and a provider-agnostic multi-dictionary query boundary.

Version 0.4.1 adds draggable subtitle placement and independent font controls,
while fixing the video texture black-screen regression found during validation.

Version 0.5.0 adds local whole-media ASR subtitle generation with a replaceable
provider/model contract, durable background jobs, explicit model management,
generated-track provenance, SRT export, and bundled macOS Apple Silicon
whisper.cpp/FFmpeg runtimes. Models remain explicit user downloads.

## Repository layout

- `contracts/player-adapter/`: transport-neutral player command, state, and event schemas.
- `docs/decisions/`: architecture decision records.
- `docs/verification/`: behavior baselines and verification results.
- `crates/`: Rust domain, application, persistence, and HTTP API.
- `scripts/`: contract validation, release packaging, and production tooling.
- `testdata/`: generated, license-clear M0 media and subtitle fixtures.

## M0 quick start

```sh
./testdata/generate.sh
./scripts/validate-contracts.sh
```

Prototype-specific commands live in each spike README.

## Verification

To start and manually test the complete Flutter app with either the pinned
runtime or unreleased local core code, follow
[`docs/development/full-app-local-testing.md`](docs/development/full-app-local-testing.md).

```sh
# Fast local feedback for the Rust workspace
./scripts/test.sh --rust

# Complete strict Rust quality gate used by CI
./scripts/test.sh --rust --strict

# Contract and artifact checks
./scripts/validate-contracts.sh
python3 -m unittest scripts/test_release_artifacts.py

# Test the testing infrastructure itself
./scripts/test-infrastructure.sh

# Historical milestone acceptance suites
./scripts/verify-m1.sh
./scripts/verify-m15.sh

# Milestone 2.0 Phase 0 research-infrastructure checks
./scripts/verify-m20-phase0.sh

# Milestone 2.0 contracts, schema v9, and fake-provider workflow
./scripts/verify-m20.sh
./scripts/verify-m16.sh
./scripts/verify-m17.sh
./scripts/verify-m18.sh
./scripts/verify-m19.sh
```

See `docs/features/testing-workflow.md` for runner modes, retained failure logs,
coverage, benchmark compilation, fuzz smoke tests, and known limitations.

The local API binds only to loopback and reports its random port and bearer
token in a structured startup handshake. See `docs/architecture/` for module,
data, and lifecycle boundaries.

Versioned consumer inputs are built with `scripts/package-contracts.sh` and
`scripts/package-runtime-bundle.sh`. Both archives include manifests with the
source commit, compatibility versions, and per-file SHA-256 hashes.

Build and license-check the pinned ASR runtime with
`./scripts/build-asr-runtime.sh`. Runtime provenance and redistribution notes
are documented in `docs/release/asr-runtime.md`.

No license is granted for this repository at this stage. The old LLPlayer
repository is a behavioral reference only; source code is not copied into this
project.
