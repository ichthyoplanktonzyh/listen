# Changelog

## Unreleased

- Started Milestone 2.0 Phase 0 with a fixed 60-slot real-speech evaluation
  catalog covering news, interview, conversation, speech rate, recording
  quality, and six target connected-speech phenomena.
- Added a provider-neutral phonetic evaluation tool that reports Phone Error
  Rate, detected-phone timeline validity, and subtitle-token association
  coverage, with success and failure smoke fixtures.
- Recorded candidate-provider roles, licensing constraints, a concrete Phase 0
  execution plan, and a proposed ADR that prevents product integration or
  `detected_in_audio` claims before quality and licensing gates pass.
- Added Vosk/Kaldi as a lightweight ASR and forced-alignment research baseline,
  without treating canonical decoder alignment as real detected-phone output.
- Proposed an AGPL/commercial dual-license direction and a permissive,
  versioned out-of-process provider SDK boundary while preserving the current
  no-license-granted repository state until legal and contributor preparation
  is complete.
- Added an isolated candidate-research harness that checks the pinned ZIPA
  dependency/artifact boundary, requires licensed external audio, rejects
  sequence-only output without phone timestamps, and records reproducibility
  and performance metadata.
- Added provider-neutral Milestone 2.0 domain contracts, schema v9 persistence,
  durable analysis jobs, detected-phone timelines, alignment findings, user
  feedback, API/events, and explicit model-management rejection paths.
- Added a deterministic research fixture that is disabled in normal builds,
  cannot be distributed as a model, never upgrades its low-confidence findings
  to `detected_in_audio`, and supports repeatable contract verification.
- Added desktop settings v8, current-sentence experimental analysis triggering,
  SSE progress refresh, detected-phone highlighting, and clearly labeled
  audio-detection results that remain hidden by default.
- Added focused widget coverage for the audio-analysis model/job center and
  distinct current-sentence and whole-track analysis triggers.
- Verified detected-phone highlighting across non-monotonic playback position
  changes and passed the existing packaged macOS build/runtime/signing smoke.
- Added `scripts/verify-m20.sh`, v8-to-v9 migration coverage, fake-provider
  idempotency checks, and low-confidence finding safety tests.
- Passed the complete M2.0 historical headless regression with 150 Rust tests,
  Flutter analysis, and 45 Flutter tests; the latest Flutter suite contains 46
  passing tests after the playback-position coverage increment.
- Passed the packaged macOS release build, bundled-runtime discovery, ad-hoc
  signing verification, extracted-package launch, video/audio smoke, and
  persistence checks.
- Milestone 2.0 remains incomplete: no real provider has passed the licensed
  evaluation, quality, performance, provenance, and distribution gates.
- Added an external evaluation-input manifest validator and preparation guide
  that check catalog membership, immutable audio checksums, explicit license
  decisions, bounded word/phone timelines, and independent human review before
  candidate development runs.
- Separated ZIPA code and model revisions and added a smoke-tested experimental
  CTC argmax frame-span projection, while retaining an explicit real-audio
  calibration gate before treating projected timestamps as stable.
- Added a research-only ZIPA CTC ONNX runner and explicit opt-in environment
  setup with pinned dependencies, separate code/model revisions, and
  checksum-verified external downloads.

## 0.7.1 - 2026-06-13

- Enabled whisper.cpp DTW (Dynamic Time Warping) token-level timestamps during
  ASR transcription so generated subtitle tracks produce `asr_reported` word
  timings instead of falling back to the weighted estimator.
- Added `-ojf` (JSON-full) and `-dtw <preset>` flags to the whisper-cli
  invocation. The JSON-full output carries per-token `t_dtw` cross-attention
  alignment timestamps in centiseconds.
- New `asr_timing` module merges whisper subword tokens into lexical words by
  leading-whitespace rules and produces `WordTiming` entries with
  `timing_source = asr_reported`.
- DTW is enabled only for `whisper`-family models; custom models skip the step.
- Every stage degrades safely: unavailable `t_dtw` values, segment count
  mismatches, word count mismatches, boundary violations, and non-monotonic
  timestamps all fall back to the existing deterministic weighted estimator on a
  per-sentence basis.
- The Flutter frontend, database schema, and `timing_priority` logic required
  zero changes — `AsrReported` (priority 3) already overrides `Estimated`
  (priority 1) in the existing word-timing pipeline.
- Established a unified testing workflow (`scripts/test.sh`) that consolidates
  `cargo fmt`, `clippy`, `test`, `flutter analyze`, `flutter test`, and contract
  validation into a single command with structured pass/fail summary output.
  Supports `--quick`/`--rust`/`--flutter`/`--full` modes, `--json` for
  machine-readable CI/AI output, `--verbose` for raw logs, `--debug` for
  internal tracing, and `--strict` to require `Cargo.lock`, deny Rust warnings,
  and make Flutter infos/warnings fatal. Successful-run logs are deleted;
  failed-run logs remain at the reported path while the terminal prints only
  the summary and key error lines.
- Extracted shared test utilities (`scripts/lib-testing.sh`) from the six
  `verify-m*.sh` acceptance scripts: cargo resolution, API lifecycle
  (start/stop/wait), curl helpers, and JSON assertion functions.
- Added the project's first Rust integration test
  (`crates/speech-analysis/tests/asr_timing_integration_test.rs`) with a
  real whisper `-ojf` JSON fixture covering subword merge, `t_dtw=-1` filter,
  special tokens, repeated DTW points, and boundary/segment-count mismatch
  fallback.
- Completed the ASR timing fix against real bundled whisper.cpp output:
  `[_BEG_]` / `[_TT_*]` special tokens and punctuation no longer corrupt the
  final lexical word, merged words are text-validated before mapping, repeated
  DTW points become deterministic non-empty intervals, and zero-duration word
  timings are rejected by the storage contract. Previously stored zero-length
  timing caches are detected as unusable and automatically fall back to the
  deterministic estimator.
- Updated CI to invoke `./scripts/test.sh --rust` and `--flutter` instead of
  individual `cargo`/`flutter` commands, keeping the same check coverage while
  producing more actionable failure logs.
- Migrated all 6 `verify-m*.sh` acceptance scripts to source `lib-testing.sh`,
  eliminating duplicated cargo resolution, API lifecycle, cleanup traps, and
  curl helpers. `setup_test_dir()` now registers cleanup automatically, API
  startup restores signal handling for graceful shutdown, and M1.7/M1.8 use
  the shared environment-aware `start_api()` path. Fixed schema drift (v6→v8)
  in verify-m17 and verify-m18 that accumulated across milestones.
- Added the project's second Rust integration test suite
  (`crates/persistence-sqlite/tests/persistence_integration_test.rs`) covering
  file persistence across reopen, migration backup creation, concurrent access
  safety, subtitle import/export, and media availability lifecycle (6 tests,
  25 total for the crate).
- Added `cargo-llvm-cov` coverage collection to CI (`lcov.info` artifact) for
  tracking coverage trends across PRs.
- Fixed the dictionary-provider parallel-test flake by replacing PID/time-based
  fixture paths with `tempfile::NamedTempFile`; 50 repeated parallel runs pass.
- Added 42 unit tests to the `application` crate (previously zero coverage)
  covering `require_text`, `clean_optional`, `normalize_american_english` (19
  irregular/suffix rules), `normalize_phrase`, `phrase_candidates` (including
  token boundary and non-word-token handling), `lexical_from_word`,
  `lexical_source_from_word`, and `timing_priority`. Total workspace tests
  increased from 58 to 100+.
- Fixed a boundary bug in `phrase_candidates` where sentences shorter than a
  phrase's word count could trigger an out-of-bounds index panic; corrected
  the window count formula.
- Set CI coverage gate at 50% line coverage (`--fail-under-lines 50` in the
  coverage job) to prevent coverage regressions, with a planned increase to
  55%+ as test coverage expands.
- Enhanced `./scripts/test.sh --quick` to include `cargo test --workspace
  --lib` (unit tests only, excluding integration/doc tests) while remaining
  under 30s. Quick mode now runs: fmt → clippy → lib unit tests → analyze.
- Added fuzz testing infrastructure with 3 fuzz targets:
  `crates/subtitle-core/fuzz/` (SRT and WebVTT parsing),
  `crates/speech-analysis/fuzz/` (ASR timing JSON extraction). The manifests
  are independent workspaces with committed lock files, the ASR target matches
  the current API, and CI runs every target for a 10-second nightly-Rust smoke
  test.
- Rewrote `testdata/README.md` as a comprehensive fixture catalog documenting
  every test data file, its purpose, and which tests consume it.
- Created `docs/features/testing-milestone.md` as the tracking document for
  the test system improvement initiative with P0/P1/P2 tiered goals and
  progress tracking.
- Added 16 unit tests to the `diagnosis-core` crate (2 → 18) covering all
  `diagnose` function branches: `MeaningBarrier`, `RecognitionBarrier`,
  `InsufficientInformation`, `OtherFactors`, mixed scenarios, non-word token
  filtering, `None` status handling, duplicate lemma dedup, and edge cases.
- Added `criterion` performance benchmarks for `subtitle-core` (SRT/VTT parse,
  tokenize, normalize) and `speech-analysis` (ASR timing extraction, word
  timing estimation). 10 benchmark cases in total covering small fixtures and
  large synthetic inputs (2k sentences, 500 segments). CI compiles all
  benchmarks with `cargo bench --workspace --no-run --locked`.
- Added `proptest` property-based testing with 10 property tests across
  `speech-analysis` (timing output count, monotonicity, bounds, start≤end)
  and `subtitle-core` (normalize idempotence, tokenize word normalization,
  SRT/VTT no-panic, SRT draft field validity). Total workspace tests: 132.
- Added API surface regression test (`openapi_version_snapshot`)
  in `api-http` that snapshots the OpenAPI 3.1.0 version, 51-path count, 18
  key schema definitions, and /v1/ prefix convention. Full semantic
  breaking-change detection remains future work.
- Added `scripts/test-infrastructure.sh` to test cleanup traps, API process
  teardown, quick/full mode selection, strict flags, JSON output, and retained
  failure logs. CI runs this self-test before desktop checks.
- Added `scripts/test.sh --low-memory` to limit Cargo, Rust-test, Rayon, and
  Flutter-test concurrency, reuse Flutter dependency resolution, and diagnose
  child exit code 137 as `SIGKILL` / external resource enforcement. Human
  output now emits a lightweight progress heartbeat before each check so quiet
  commands remain visible to external executors.
- Added a focused ASR word-timestamp handoff documenting the completed
  real-whisper validation, fallback/storage invariants, verification baseline,
  and the current environment's direct-script `SIGKILL` limitation.
- Prevented quick/full mode duplication: the Rust lib-test subset now runs only
  in `--quick`, while Rust/full modes execute the complete suite once.
- Fixed Rust test pass-through handling so arguments after the runner's `--`
  are forwarded after Cargo's test-harness separator.
- Added `.claude/worktrees/` to `.gitignore` so local product/refactor worktrees
  are not accidentally staged.

## 0.7.0 - 2026-06-13

- Integrated the modular Flutter controller/widget architecture while
  preserving Milestone 1.9 pronunciation and word-sync behavior.
- Fixed nullable controller state so media, subtitle, selection, diagnosis,
  and loop state can be cleared without retaining stale values.
- Provider-neutral pronunciation, phoneme, speech-rule, and word-timing
  contracts with schema v8.
- Pinned CMUdict canonical en-US pronunciation with deterministic fallback,
  lexical stress, ARPAbet, IPA display, variants, and token mapping.
- Deterministic bounded word timings for ordinary subtitles and local
  current-word highlighting that remains correct after seek, loop, and rate
  changes.
- Rule-based weak form, contraction, linking, flapping, deletion, and
  assimilation hints from a fixed 18-rule catalog that explicitly does not
  claim real-audio detection.
- Provider/version-isolated canonical pronunciation caching, explicit cache
  invalidation events, and non-blocking track jobs with cancellation and retry.
- Desktop settings v7, pronunciation diagnostics, API/event contracts, and
  Milestone 1.9 automated verification.
- Fixed current-word timing loading by reading the API contract fields
  `timing_source` and `provider_id`.
- Added background, scale-bounce, and glow current-word styles while keeping
  word-timing provenance in diagnostics instead of the playback overlay.
- Confirmed AV1 playback during collaborative functional acceptance.
- Removed the startup stall caused by re-hashing installed learning resources,
  added an explicit core-starting/error/retry screen, and fixed short-sentence
  ECDICT phrase scanning.
- Completed collaborative functional acceptance. Independent Developer ID
  distribution signing and notarization remain deferred release work.

## 0.6.0 - acceptance candidate

- Unified word and user-confirmed phrase learning assets with schema v7 and
  vocabulary asset bundle v3.
- Versioned lemma normalization, persistent corrections, and phrase candidates.
- Clickable phrase underlines in learning subtitles; confirmed phrases remain
  independent assets with their own status and source ranges.
- Explicit checksum-verified ECDICT and CMUdict resource manager.
- Provider-neutral OpenSubtitles title, filename, and media-hash workflows.
- Provider-supplied pronunciation audio in the unified word learning panel.
- Vocabulary asset v3 import preserves newer local state and independently
  merges learning content, history, and durable source encounters.

## 0.5.0 - 2026-06-10

Milestone 1.7 local ASR learning subtitle release.

- Provider-, runtime-, model-, and profile-neutral transcription contracts.
- Durable single-concurrency whole-media jobs with progress, cancellation,
  retry, restart interruption handling, provenance, and idempotent completion.
- whisper.cpp model catalog, explicit verified downloads, custom model
  registration, model management, and persistent job center.
- Generated subtitles become ordinary interactive learning tracks and support
  SRT export.
- Reproducible macOS arm64 whisper.cpp and LGPL-only FFmpeg runtime build,
  license validation, application bundling, and deterministic fake-runtime
  acceptance test.

## 0.4.1 - 2026-06-10

- Draggable viewport-relative subtitle placement, independent primary/secondary
  font controls, and a stable video viewport when subtitle visibility changes.
- Restored the media-kit video texture layout after the subtitle overlay
  refactor, fixing the black video screen regression.

## 0.4.0 - 2026-06-10

Milestone 1.6 desktop learning experience release.

- Responsive subtitle presets and automatic native-subtitle suppression.
- Simplified Chinese and English desktop localization.
- TXT/CSV existing vocabulary import with conflict-safe status initialization.
- Unified word learning panel with durable user definitions and notes.
- Provider-agnostic aggregated dictionary API and multi-source UI.

## 0.3.0 - 2026-06-10

Milestone 1.5 vocabulary learning asset release.

- Status-driven vocabulary books with user-selected status as the authority.
- Durable status history and source sentence snapshots.
- Missing-media recovery and independent vocabulary asset backup/restore.
- Latest-effective context observations with clear support.
- Schema v4 migration with legacy history and source backfill.

## 0.2.0 - 2026-06-09

Milestone 1 macOS Apple Silicon MVP.

### Added

- Local video/audio playback and complete subtitle-learning loop.
- SRT/WebVTT import, interactive transcript, sentence navigation and loop.
- Word status, dictionary lookup, context observations, and diagnosis.
- Dual text subtitles with independent offsets.
- Drag-and-drop import and configurable subtitle appearance/layout.
- Embedded text-subtitle extraction through optional ffprobe/ffmpeg.
- Online-media URL resolution through optional yt-dlp.
- Versioned local settings, progress recovery, diagnostics, and release package.

### Deferred

- Windows/Linux, OpenSubtitles, bitmap subtitle interaction, mobile, ASR, and
  translation.
