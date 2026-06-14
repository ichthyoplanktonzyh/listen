# Changelog

## Unreleased

- Started C2 acoustic-first partition quality with partitioner V2. Gap scoring
  now uses source-specific thresholds for ASR-reported, forced-aligned, and
  user-adjusted timings, while estimated timings remain excluded from acoustic
  evidence.
- Added moderate-gap evidence that can combine with punctuation support without
  overriding phrase protection on its own. Strong acoustic gaps remain able to
  split inside a text phrase.
- Treat punctuation from known ASR-generated subtitle tracks as inferred model
  output instead of a forced boundary. Inferred punctuation must combine with
  acoustic or product evidence before it changes the display partition.
- Reduced weak-evidence single-word fragments at chunk edges and added
  regression tests for ASR punctuation reliability, timing-source sensitivity,
  phrase protection, and fragment suppression.
- Added structured sentence chunk diagnostics containing selected and rejected
  boundary candidates, raw scores, thresholds, forcing state, primary source,
  and evidence. Product-facing partition responses remain unchanged.
- Added an initial golden calibration baseline covering ordinary short
  sentences, preferred-length splitting, single-word-tail suppression, and
  decisive acoustic gaps.
- Completed C2 acoustic-first partition quality. Readability scoring now
  favors supported boundaries near the preferred chunk length, weak evidence
  cannot create undersized fragments, soft/hard length limits prevent
  protected phrases from producing unreadably long chunks, and stronger
  phrase protection still yields to decisive acoustic gaps.
- Added a version-controlled V2 golden corpus covering fast speech, hesitation,
  moderate pauses, ASR-inferred versus trusted punctuation, fixed expressions,
  and long subtitles. The corpus enforces fragment and overlong-chunk quality
  bounds.
- Added `GET /v1/subtitles/{track_id}/chunk-diagnostics` for inspecting selected
  and rejected candidates using the same source-aware configuration as the
  product-facing track partition.
- Completed C3 rich acoustic evidence with partitioner V3. An independent
  pre-boundary-lengthening provider compares real word duration against a
  robust local baseline and can select meaningful boundaries without a pause.
- Added a conservative filled-pause hesitation provider that lowers boundary
  confidence around ASR-recognized `uh`, `um`, `erm`, `hmm`, and `mm` tokens.
  Ordinary hesitation gaps are suppressed while very large pauses remain
  eligible boundaries.
- Rich evidence is provider/version attributed, includes concrete measurement
  details, appears in existing chunk diagnostics, and is consumed as bounded
  signed score changes. Estimated timings and disabled/missing providers
  exactly degrade to C2 behavior.
- Added a C3 golden corpus covering no-pause lengthening, ordinary word
  durations, hesitation-gap suppression, and decisive pauses that survive the
  hesitation penalty.

## 0.7.2 - 2026-06-14

- Added the first user-visible chunk listening MVP. Primary subtitle sentences
  are rendered as complete, non-overlapping chunk groups and the active chunk
  follows playback using the existing local word-timing timeline.
- Added the stable `SentenceChunkPartition` display contract and V1
  acoustic-first rule partitioner. Real timing gaps, punctuation, phrase
  protection, and deterministic length fallback are resolved into one complete
  partition while estimated timings are excluded from acoustic evidence.
- Added `GET /v1/subtitles/{track_id}/chunk-partitions`, application-layer
  sentence and track partition methods, OpenAPI coverage, and independent
  fallback so chunk analysis failure never interrupts ordinary subtitles,
  word highlighting, or pronunciation enhancements.
- Added desktop chunk grouping and active-chunk highlighting settings. Chunk
  rendering preserves word clicks, vocabulary styles, and phrase interactions.
- Hardened text and acoustic chunk detection by rejecting invalid external
  phrase ranges, preventing phrase matches across punctuation, preserving
  empty-input sentence identity, and correcting gap-confidence interpolation.
- Added the staged C0-C4 chunk listening implementation plan. C0-C1 deliver the
  product loop; later milestones prioritize acoustic boundary quality and keep
  the display/API contract stable.
- Verified with workspace Rust tests, strict targeted clippy, Flutter analysis,
  Flutter tests, and whitespace checks.

## 0.7.1 - 2026-06-13

- Implemented text-level (lexical) chunk detection in the `speech-analysis` crate
  (`text_chunk_detection` module) as a companion to the existing acoustic
  (gap-based) chunk detection. The text detector partitions entire sentences
  into contiguous chunks where every word token belongs to exactly one chunk.
- Three data sources feed the text detector: (1) COCA n-gram collocations
  (MI ≥ 3.0, ~1K seed entries, compiled into the binary via `include_str!`),
  (2) PHRASE List (Martinez & Schmitt 2012, 505 pedagogically-selected
  functional phrases with category labels), and (3) existing ECDICT/built-in
  phrase candidates forwarded from the application layer.
- Sliding-window longest-match-first greedy overlap resolution ensures
  competing multi-word spans (e.g. "a lot of" vs "a lot") are resolved
  deterministically with longer spans taking priority.
- Cross-reference support between acoustic and text layers: new
  `BoundaryMarker::LexicalPhrase` variant, `CombinedChunkResult` type,
  `combine_chunks()` merging acoustic and text evidence with four-quadrant
  confidence logic (mutual-reinforcement, acoustic-only discount, text-only
  discount, no-signal), and `annotate_acoustic_with_text()` for decorating
  acoustic boundaries with lexical phrase markers.
- Added `AppServices::detect_text_chunks`, `detect_text_chunks_for_track`,
  and `detect_combined_sentence_chunks` methods.
- 18 new unit tests across `text_chunk_detection` covering empty/single-word
  input, COCA collocation matching, PHRASE List detection, external candidate
  forwarding, longest-match resolution, case-insensitive matching, partition
  coverage integrity, boundary count consistency, token order preservation,
  punctuation filtering, MI→confidence mapping, and source counts.

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
  internal tracing, and `--strict` to treat warnings as errors. Full logs are
  always preserved to disk; the terminal prints only the summary with key error
  lines on failure.
- Extracted shared test utilities (`scripts/lib-testing.sh`) from the six
  `verify-m*.sh` acceptance scripts: cargo resolution, API lifecycle
  (start/stop/wait), curl helpers, and JSON assertion functions.
- Added the project's first Rust integration test
  (`crates/speech-analysis/tests/asr_timing_integration_test.rs`) with a
  real whisper `-ojf` JSON fixture covering subword merge, `t_dtw=-1` filter,
  and boundary/segment-count mismatch fallback. The crate now has 13 tests
  (10 unit + 3 integration).
- Fixed a boundary edge case in `asr_timing` where single-token words (equal
  `start_t_dtw` and `end_t_dtw`) were incorrectly rejected by the `>=`
  validation; changed to `>` to accept zero-duration single-token words.
- Updated CI to invoke `./scripts/test.sh --rust` and `--flutter` instead of
  individual `cargo`/`flutter` commands, keeping the same check coverage while
  producing more actionable failure logs.
- Migrated all 6 `verify-m*.sh` acceptance scripts to source `lib-testing.sh`,
  eliminating duplicated cargo resolution, API lifecycle, cleanup traps, and
  curl helpers (607 → 533 lines, 12% reduction). Fixed schema drift (v6→v8)
  in verify-m17 and verify-m18 that accumulated across milestones.
- Added the project's second Rust integration test suite
  (`crates/persistence-sqlite/tests/persistence_integration_test.rs`) covering
  file persistence across reopen, migration backup creation, concurrent access
  safety, subtitle import/export, and media availability lifecycle (6 tests,
  25 total for the crate).
- Added `cargo-llvm-cov` coverage collection to CI (`lcov.info` artifact) for
  tracking coverage trends across PRs.
- Hardened the dictionary-provider flaky test by ensuring file metadata is
  synced to disk before constructing the ECDICT provider, preventing rare
  mtime-granularity cache misses.
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
  `crates/speech-analysis/fuzz/` (ASR timing JSON extraction). Install
  `cargo-fuzz` and run with `cargo fuzz run <target>`.
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
  large synthetic inputs (2k sentences, 500 segments).
- Added `proptest` property-based testing with 10 property tests across
  `speech-analysis` (timing output count, monotonicity, bounds, start≤end)
  and `subtitle-core` (normalize idempotence, tokenize word normalization,
  SRT/VTT no-panic, SRT draft field validity). Total workspace tests: 132.
- Added API version compatibility regression test (`openapi_version_snapshot`)
  in `api-http` that snapshots the OpenAPI 3.1.0 version, 51-path count, 18
  key schema definitions, and /v1/ prefix convention to catch accidental
  breaking changes.

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
