# Milestone 1.9 Verification Report

Milestone 1.9 adds provider-neutral pronunciation, sentence IPA, deterministic
word timings, local current-word highlighting, and rule-based connected-speech
hints.

## Automated Coverage

- `speech-analysis` tests cover stress, IPA mapping, unknown-word fallback,
  monotonic bounded timing, the no-audio-detection rule boundary, and the
  fixed 18-rule catalog's examples and counterexamples.
- the fixed 100-sentence en-US baseline covers common and irregular words,
  names, numbers, abbreviations, punctuation, phrases, unknown words,
  hyphenation, and contextual rule pairs.
- persistence tests cover schema v1-v7 migration to v8 and old-data retention.
- canonical pronunciation cache tests verify provider/version isolation.
- API and contract tests cover pronunciation providers, sentence analysis,
  track analysis, word timing generation, fixed rule metadata, cache/provider
  events, and non-blocking speech jobs with cancellation and retry.
- an API regression queues a 10,000-sentence pronunciation job without waiting
  for completion, then cancels and retries it.
- Flutter tests cover settings v1-v6 migration to v7 and local word selection.
- `scripts/verify-m19.sh` exercises the integrated local API and historical
  regression suite.

## Verification Result

Verified on macOS Apple Silicon on 2026-06-12:

- `scripts/verify-m19.sh`: passed on the current integrated tree, including the
  M1, M1.5, M1.6, M1.7, and M1.8 historical regressions.
- `cargo test --workspace`: passed.
- `cargo clippy --workspace --all-targets -- -D warnings`: passed.
- `cargo fmt --check`: passed.
- `flutter analyze`: passed.
- `flutter test`: passed, 31 tests.
- `scripts/validate-contracts.sh`: passed.
- `scripts/build-macos-mvp.sh`: produced
  `dist/LLPlayerNext-macos-arm64.zip`, SHA-256
  `683765f32f8935e91c5be045c66abb6b49dd71550fd136a2cd55081203a02bc4`.

The package flow clears inherited macOS provenance attributes before signing
and does not preserve those attributes in the release zip. This prevents dyld
startup stalls seen when launching directly from the Xcode build directory.

## Frontend Refactor Integration

The modular Flutter frontend branch was merged after the initial M1.9
acceptance-candidate commit. M1.9 state now follows the controller/widget
boundaries, and nullable controller-state clearing is covered by regression
tests.

- `flutter analyze`: passed.
- `flutter test`: passed, 35 tests.
- `scripts/verify-m19.sh`: passed after integration.
- macOS release archive build: passed after integration.
- Post-integration `scripts/verify-mvp.sh` independent launch on the current
  machine: blocked by the
  host security configuration. macOS AMFI reports error `-423` for the
  ad-hoc-signed executable because Developer Mode is disabled and the keychain
  contains no valid code-signing identities. The earlier M1.9 acceptance
  package passed the independent smoke test before this host policy became
  active. A signed build or explicit Developer Mode enablement is required to
  repeat the final launch smoke test.

The desktop diagnosis card now exposes pronunciation provider/version,
degradation reason, reusable pronunciation-cache state, and current word-timing
source.

## Startup Regression

The apparent blank-window regression was the core-loading screen waiting while
M1.8 synchronously re-read and hashed the installed 66 MB ECDICT resource.
Installed resources are still checksum-verified before publication, while
startup discovery now uses file metadata. Measured sidecar handshake time
dropped from about 3.25 seconds to 6-11 milliseconds with warm filesystem
caches. The desktop loading screen now exposes core status, errors, and retry;
failed handshakes also terminate their sidecar process.

## Product Boundary

All rule hints are labeled as contextual predictions. No M1.9 result claims a
weak form, linking, flapping, deletion, contraction, or assimilation was
detected in the real audio.

## Manual Acceptance

The collaborative checklist in `docs/planning/milestone-1.9.md` remains the
authoritative manual acceptance list. The release candidate must be opened on
macOS and confirmed by the user before the final `v0.7.0` tag is created.
