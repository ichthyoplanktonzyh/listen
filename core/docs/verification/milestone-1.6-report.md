# Milestone 1.6 Verification Report

Date: 2026-06-10
Release: 0.4.0

## Delivered

- Schema v5 durable user definitions and personal notes.
- Vocabulary asset bundle v2 with v1 import compatibility.
- Transactional TXT/CSV-oriented external vocabulary import API.
- Provider registry and aggregated dictionary result model with isolated errors.
- Responsive subtitle presets, automatic native subtitle suppression, and
  switchable transcript/learning/diagnosis side panel.
- Simplified Chinese and English desktop localization with system default.

## Automated Evidence

- `cargo test --workspace`
- `cargo clippy --workspace --all-targets -- -D warnings`
- Flutter analyze and widget tests
- `scripts/validate-contracts.sh`
- `scripts/verify-m1.sh`, `scripts/verify-m15.sh`, and `scripts/verify-m16.sh`
- macOS packaged MVP smoke test

The final package hash is recorded during release closure.

## Release Artifact

`dist/LLPlayerNext-macos-arm64.zip`

SHA-256 c27c95f12b698cb6ccd5713f522908e4907e1e302620f6f385966fbd9700b93f
