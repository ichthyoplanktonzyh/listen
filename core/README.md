# LLPlayerNext

Clean-room, macOS-first rewrite of a listening-comprehension media player.

**New thread / maintainer handoff:** read
[`docs/handoff/project-handoff-2026-06-12.md`](docs/handoff/project-handoff-2026-06-12.md).

**Current release candidate:** Milestone 1.9, version `0.7.0`.

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
- `spikes/`: disposable M0 technology prototypes.
- `apps/desktop/`: formal Flutter macOS desktop client.
- `testdata/`: generated, license-clear M0 media and subtitle fixtures.

## M0 quick start

```sh
./testdata/generate.sh
./scripts/validate-contracts.sh
```

Prototype-specific commands live in each spike README.

## Verification

```sh
cargo fmt --check
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
./scripts/validate-contracts.sh
./scripts/verify-m1.sh
./scripts/verify-m15.sh
./scripts/verify-m16.sh
./scripts/verify-m17.sh
./scripts/verify-m18.sh
./scripts/verify-m19.sh
./scripts/build-macos-mvp.sh
./scripts/verify-mvp.sh
```

The local API binds only to loopback and reports its random port and bearer
token in a structured startup handshake. See `docs/architecture/` for module,
data, and lifecycle boundaries.

The macOS Apple Silicon release artifact is written to
`dist/LLPlayerNext-macos-arm64.zip`.

Build and license-check the pinned ASR runtime with
`./scripts/build-asr-runtime.sh`. Runtime provenance and redistribution notes
are documented in `docs/release/asr-runtime.md`.

No license is granted for this repository at this stage. The old LLPlayer
repository is a behavioral reference only; source code is not copied into this
project.
