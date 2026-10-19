# Milestone 2.0 Phase 0 Verification Report

## Status

Phase 0 research infrastructure is implemented. Provider evaluation and
release-provider selection are not complete.

## Completed

- Fixed 60-slot evaluation catalog covering news, interview, and conversation;
  normal and fast speech; clean and noisy recordings; and all required target
  phenomena.
- Candidate registry records candidate role, current eligibility, license
  status, constraints, and primary sources.
- Provider-neutral scorer reports Phone Error Rate, timeline validity, and
  subtitle-token association coverage.
- Smoke fixtures verify deterministic scoring and release-gate calculations.
- CI runs `scripts/verify-m20-phase0.sh` so catalog and scoring drift fail the
  build.
- Proposed ADR prevents premature product integration or
  `detected_in_audio` claims.
- Vosk/Kaldi is registered as a lightweight ASR and forced-alignment research
  baseline, not as a proven detected-phone provider.
- An isolated candidate harness checks the pinned ZIPA dependency/artifact
  boundary, requires licensed external audio, rejects output without monotonic
  per-phone timestamps, and records reproducibility/performance metadata.
- The first balanced 10-case development batch is locked, and an external-input
  manifest validator checks immutable checksums, explicit licenses, bounded
  word/phone timelines, and independent review before candidate execution.
- A pinned, explicit opt-in Python 3.11 ZIPA research environment and
  research-only CTC ONNX runner execute successfully outside the product path.
- Focused desktop widget tests cover the audio-analysis model/job center,
  cancellation/retry actions, and distinct current-sentence/whole-track
  analysis triggers.
- Local detected-phone selection is tested across non-monotonic playback
  position changes representing seek, loop return, and drag behavior.
- Provider-neutral schema v9 contracts, durable jobs, detected-phone timelines,
  alignments, findings, feedback, API/events, and desktop settings are
  implemented behind a disabled-by-default research-provider boundary.
- The deterministic research fixture verifies lifecycle and UI integration,
  cannot be installed or distributed, and never upgrades its low-confidence
  findings to `detected_in_audio`.

## Remaining Gates

- All 60 catalog cases are still `planned`; none has a human-verified actual
  phone reference in the repository.
- The first 10 development slots are selected, but their licensed audio and
  independently reviewed actual-phone references have not been supplied.
- No candidate has been executed or measured on the fixed evaluation set.
- No release-quality Apple Silicon performance measurements exist. A
  non-quality smoke run on the repository's generated 10-second license-clear
  audio measured INT8 RTF `0.187640`, observed child-process peak RSS
  `556662784` bytes, and model size `70677672` bytes. This proves only that the
  isolated adapter runs on the target host.
- ZIPA CTC ONNX output exposes frame-level `log_probs` and `log_probs_len`, but
  upstream simplified inference discards frame spans. An experimental CTC
  argmax span projection is implemented and smoke-tested; real-audio
  calibration is still required before ZIPA timestamps can be treated as
  stable.
- The current research host is Apple M1 Max / 32 GiB / arm64. An isolated
  Python 3.11 environment now contains the pinned ZIPA dependencies, and the
  checksum-verified INT8 model is stored outside the repository. The model
  license metadata remains unverified, so this environment is research-only.
- High-confidence finding precision has not been manually reviewed.
- Exact model revisions, checksums, training-data provenance, and distribution
  reviews are incomplete.
- ZIPA code and model provenance are now tracked separately: the inspected
  GitHub code revision is `f96afe2842868bb1d3cea1efe191806fdcd3c955`, while
  the model-repository revision remains
  `9a8d85ba0d2adcbafe7087b82180d0e65c6f3426`.
- No release provider has been selected.

## Decision

Milestone 2.0 remains incomplete. The provider-neutral scaffold may continue to
evolve, but release-provider activation and real-audio claims must wait until
the Phase 0 gates in ADR 0008 and the milestone plan are satisfied.

## Automated Verification

Verified on macOS Apple M1 Max / 32 GiB / arm64 on 2026-06-14:

- `scripts/verify-m20-phase0.sh`: passed.
- `LLPLAYERNEXT_M20_SKIP_HISTORY=1 scripts/verify-m20.sh`: passed.
- Rust tests: 150 passed.
- Flutter tests: 46 passed.
- Rust formatting, workspace Clippy with warnings denied, Flutter analysis, and
  contract validation: passed.
- `git diff --check`, Python bytecode compilation, and shell syntax check:
  passed.
- The latest complete `scripts/verify-m20.sh` historical regression passed
  contracts, formatting, Clippy, all 150 Rust tests, Flutter analysis, and all
  45 Flutter tests that existed at the time of that run.
- `scripts/build-macos-mvp.sh` and `scripts/verify-mvp.sh` passed, including
  release build, bundled runtime discovery, ad-hoc signing verification,
  extracted-package launch, video/audio smoke, and persistence checks.

## Automatic Requirement Audit

- Covered now: schema/settings migrations; fake-provider success, partial,
  cancellation, failure, retry, interruption, idempotency, whole-track output,
  feedback backup, monotonic bounded timelines, low-confidence claim safety,
  alignment operations, required finding families, analysis version retention,
  model deletion resilience, task-center actions, whole-track trigger,
  non-monotonic playback-position highlighting, historical regression, and
  packaged macOS smoke.
- Blocked on a selected real candidate flow: model download interruption,
  checksum mismatch, incompatibility, missing license, and insufficient-space
  paths.
- Blocked on a reviewed candidate phone inventory: provider-specific detected
  phone to IPA display mapping.
- Blocked on licensed real evaluation inputs: candidate quality/performance
  benchmarks and manual high-confidence finding precision.
