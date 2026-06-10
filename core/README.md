# LLPlayerNext

Clean-room, macOS-first rewrite of a listening-comprehension media player.

**Current release:** Milestone 1.5 complete, version `0.3.0`.

The Milestone 1 MVP targets macOS Apple Silicon and includes the core learning
loop, dual text subtitles, drag and drop, configurable subtitle presentation,
embedded text-subtitle extraction, and optional yt-dlp URL resolution. Windows,
Linux, mobile, OpenSubtitles, and bitmap-subtitle learning remain later work.

Version 0.3.0 makes vocabulary learning records durable independently of media:
status-driven vocabulary books, status history, source sentence snapshots,
missing-media recovery, and versioned JSON export/import are included.

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
./scripts/build-macos-mvp.sh
./scripts/verify-mvp.sh
```

The local API binds only to loopback and reports its random port and bearer
token in a structured startup handshake. See `docs/architecture/` for module,
data, and lifecycle boundaries.

The macOS Apple Silicon release artifact is written to
`dist/LLPlayerNext-macos-arm64.zip`.

No license is granted for this repository at this stage. The old LLPlayer
repository is a behavioral reference only; source code is not copied into this
project.
