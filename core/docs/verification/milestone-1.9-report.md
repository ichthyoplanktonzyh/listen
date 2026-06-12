# Milestone 1.9 Verification Report

Milestone 1.9 adds provider-neutral pronunciation, sentence IPA, deterministic
word timings, local current-word highlighting, and rule-based connected-speech
hints.

## Automated Coverage

- `speech-analysis` tests cover stress, IPA mapping, unknown-word fallback,
  monotonic bounded timing, and the no-audio-detection rule boundary.
- persistence tests cover schema v1-v7 migration to v8 and old-data retention.
- API and contract tests cover pronunciation providers, sentence analysis,
  track analysis, word timing generation, rule metadata, and event names.
- Flutter tests cover settings v1-v6 migration to v7 and local word selection.
- `scripts/verify-m19.sh` exercises the integrated local API and historical
  regression suite.

## Verification Result

Verified on macOS Apple Silicon on 2026-06-12:

- `scripts/verify-m19.sh`: passed, including the M1, M1.5, M1.6, M1.7, and
  M1.8 historical regressions.
- `cargo test --workspace`: passed.
- `cargo clippy --workspace --all-targets -- -D warnings`: passed.
- `cargo fmt --check`: passed.
- `flutter analyze`: passed.
- `flutter test`: passed, 31 tests.
- `scripts/validate-contracts.sh`: passed.
- `scripts/build-macos-mvp.sh`: produced
  `dist/LLPlayerNext-macos-arm64.zip`.
- `scripts/verify-mvp.sh`: passed against the app extracted from the release
  archive, including schema v8 initialization, video/audio import, dual
  subtitles, playback progress, restart persistence, bundled runtime checks,
  and code-signature verification.

The package flow clears inherited macOS provenance attributes before signing
and does not preserve those attributes in the release zip. This prevents dyld
startup stalls seen when launching directly from the Xcode build directory.

## Product Boundary

All rule hints are labeled as contextual predictions. No M1.9 result claims a
weak form, linking, flapping, deletion, contraction, or assimilation was
detected in the real audio.

## Manual Acceptance

The collaborative checklist in `docs/planning/milestone-1.9.md` remains the
authoritative manual acceptance list. The release candidate must be opened on
macOS and confirmed by the user before the final `v0.7.0` tag is created.
