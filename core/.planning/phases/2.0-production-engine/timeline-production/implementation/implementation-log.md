# Timeline Production Implementation Log

## 2026-06-18 15:11:06 CST

- Created `docs/timeline-production/` as the long-lived documentation root for
  the production-engine timeline resource work.
- Started Phase 1 with `LLTimeline JSON v1` as the first implementation target.
- Added Rust domain contracts for `LLTimelineDocument`, metadata, segments,
  phone/chunk extension slots, and artifacts.
- Added `GET /v1/subtitles/{track_id}/lltimeline/export` to export existing
  subtitle segments and `WordTimeline` resources as a v1 document.
- Added an HTTP behavior test that creates an active word timeline and verifies
  the exported LLTimeline document.

## 2026-06-18 15:21:41 CST

- Added `POST /v1/lltimeline/import` to import a v1 document into existing
  media, subtitle, and word timeline persistence.
- Extended HTTP coverage to export a document and import it back as a basic
  round-trip.
- Added `testdata/lltimeline/v1-minimal.lltimeline.json` as the first stable
  contract fixture and a domain deserialization smoke test.

## 2026-06-18 15:36:01 CST

- Added OpenAPI schemas for `WordTiming`, `WordTimeline`, `CreateWordTimeline`,
  and `LLTimelineDocument`.
- Added handwritten local API client methods for word timeline lifecycle and
  LLTimeline import/export.
- Added `scripts/lltimeline-resource.py` for local file validation plus API
  import/export.
- Extended `scripts/validate-contracts.sh` to compile the LLTimeline utility,
  validate the fixture, and assert OpenAPI/client coverage.
- Marked Phase 1 complete; Phase 2 now starts with timeline resource lifecycle.

## 2026-06-18 15:53:09 CST

- Added `WordTimelineSummary` and lifecycle stage reporting for algorithm
  candidate, user-adjusted, and published resources.
- Added word timeline lifecycle APIs:
  `GET /v1/subtitles/{track_id}/word-timelines/summary`,
  `POST /v1/word-timelines/{timeline_id}/publish`, and
  `DELETE /v1/word-timelines/{timeline_id}`.
- Changed active timeline archive semantics to archive the resource and clear
  legacy `word_timings` compatibility cache.
- Added delete semantics that remove the timeline and clear compatibility cache
  when the deleted resource was active.
- Extended OpenAPI, handwritten TS client, contract validation, persistence
  tests, and HTTP behavior coverage.
- Extended `scripts/lltimeline-resource.py` with summary, publish, archive, and
  delete commands.
- Marked Phase 2 complete; Phase 3 now starts with the production pipeline.

## 2026-06-18 15:57:18 CST

- Started Phase 3 with `scripts/timeline-production/` as the research-only
  local production sidecar directory.
- Added `production_pipeline.py` with `doctor`, `prepare-audio`, and
  `from-whisperx-json` commands.
- Added a research venv setup script and heavy dependency requirements file.
- Added `testdata/timeline-production/whisperx-sample.json`.
- Extended contract validation to convert the WhisperX fixture into
  `LLTimeline JSON v1` and validate the generated resource.

## 2026-06-18 16:02:53 CST

- Added `prepare-media` to produce normalized raw audio plus
  `preprocessing-artifacts.json`.
- Added optional external vocal-isolation command support via
  `--vocal-isolation-command`, with `{input}`, `{output}`, and `{output_dir}`
  placeholders.
- Added preprocessing artifact embedding to `from-whisperx-json`.
- Extended contract validation to smoke-test `prepare-media` and verify the
  generated LLTimeline remains valid when preprocessing artifacts are attached.

## 2026-06-18 16:06:35 CST

- Added `run-whisperx` to execute WhisperX on prepared audio.
- Supported default WhisperX CLI resolution, `--whisperx-bin`, and custom
  `--whisperx-command` templates.
- Added `--dry-run` coverage to contract validation so command generation is
  tested without requiring torch/whisperx in the default development shell.
- Added `whisperx-run-report.json` generation and output JSON discovery for the
  downstream `from-whisperx-json` conversion step.

## 2026-06-18 16:08:50 CST

- Added `produce-whisperx` as a one-command production entrypoint.
- The command orchestrates media preparation, optional vocal isolation,
  WhisperX execution, and LLTimeline conversion.
- Added dry-run validation so the orchestration plan is covered without
  requiring the heavy WhisperX runtime in default tests.

## 2026-06-18 19:30:22 CST

- Completed Phase 3 Production Pipeline V1.
- Added `report` to generate `production-report.json` from any
  `.lltimeline.json` production output.
- The report records word coverage, overlap/gap diagnostics, confidence
  availability, provider ids, and whether the resource is ready for manual
  review.
- Updated `produce-whisperx` to emit `production-report.json` automatically
  after LLTimeline conversion.
- Extended contract validation to cover WhisperX fixture conversion plus the
  production quality report.

## 2026-06-18 19:37:24 CST

- Started Phase 4 Evaluation System implementation.
- Added `compare-lltimeline` to compare baseline/candidate/gold word timelines
  directly inside one `.lltimeline.json` resource.
- Extended evaluation reports with P95 absolute offsets and sentence-tail lag
  metrics for the fast-speech highlight-lag problem.
- Added a multi-candidate LLTimeline fixture with DTW baseline, WhisperX
  candidate, and manual gold timelines.
- Extended contract validation to cover the document-level evaluation report
  and the new evaluation fixture.

## 2026-06-18 19:47:03 CST

- Reordered Phase 4 gold benchmark work to use existing high-quality corpora
  before building CNN10/NBC news gold samples.
- Added `gold-dataset-strategy.md` with the evaluation order: TIMIT first,
  Buckeye second, LibriSpeech alignments as scale/pressure support, and news
  gold samples later for domain calibration.
- Added `scripts/benchmark-datasets.py timit-to-lltimeline` to convert local
  TIMIT `.WRD/.PHN/.TXT` files into `LLTimeline JSON v1`.
- Added a synthetic TIMIT-style smoke fixture under
  `testdata/benchmark-datasets/timit-smoke/`.
- Extended contract validation to compile the benchmark converter, convert the
  smoke fixture, and validate the resulting LLTimeline document.

## 2026-06-18 20:15:11 CST

- Validated the converter against the local authorized TIMIT corpus at
  `/Users/shadow/data/lisa/data/timit/raw`.
- Converted TIMIT TEST full into local LLTimeline gold: 1680 utterances,
  14552 word timings, and 64145 phone timings.
- Converted TIMIT TRAIN full into local LLTimeline gold: 4620 utterances,
  39825 word timings, and 177080 phone timings.
- Added converter handling for real TIMIT quirks: overlapping adjacent word
  rows, non-positive-duration word rows, transcript-unmapped word rows, and
  leading/trailing apostrophe words.
- Extended the synthetic TIMIT smoke fixture and contract validation to cover
  overlap repair, skipped word rows, and apostrophe tokenization.

## 2026-06-18 20:23:44 CST

- Added `prepare-alignment-bundle` to build benchmark audio and aligner request
  files from LLTimeline gold resources.
- Added `add-alignment-candidate` to append aligned sidecar output as a
  candidate word timeline.
- Updated the MMS_FA sidecar for torchaudio 2.9 compatibility: `soundfile`
  audio-load fallback and list-of-words tokenizer grouping.
- Ran the first real TIMIT candidate evaluation on TEST 20:
  MMS_FA matched 171/171 words, start MAE 56.38ms, start P95 128ms, end MAE
  33.71ms, and end P95 81.5ms.
- Extended contract validation to cover benchmark bundle generation, candidate
  timeline import, and document-level evaluation.

## 2026-06-18 20:45:41 CST

- Fixed `scripts/timeline-production/setup-venv.sh` to install dependencies
  with `uv pip install`, because the uv-created research venv does not
  guarantee `python -m pip` is available.
- Downloaded and smoke-loaded the local timeline-production WhisperX stack:
  `Systran/faster-whisper-large-v3` for ASR and torchaudio's English
  `wav2vec2_fairseq_base_ls960_asr_ls960.pth` alignment model.
- Added `scripts/timeline-production/whisperx-align-request.py` to run
  WhisperX known-transcript alignment against an existing benchmark
  `alignment-request.json`, emitting the same `timings[]` shape consumed by
  `add-alignment-candidate`.
- Ran the first TIMIT TEST 20 WhisperX known-transcript alignment evaluation:
  171/171 matched words, start MAE 65.50ms, start P95 141.5ms, end MAE
  45.02ms, end P95 151ms, and tail lag mean -142.55ms.
- Recorded that this first WhisperX alignment-only result is weaker than the
  MMS_FA TEST 20 result, so Phase 4 should next compare full WhisperX CLI,
  MFA, and larger TIMIT samples before choosing the production aligner.

## 2026-06-19 11:44:19 CST

- Expanded the benchmark comparison to TIMIT TEST 100:
  MMS_FA + TIMIT transcript matched 881/881 words with start MAE 47.53ms,
  end MAE 27.16ms, and tail mean abs 32.15ms.
- Ran full WhisperX CLI on the same TEST 100 bundle:
  876/881 matched words, start MAE 56.81ms, end MAE 31.06ms, tail mean abs
  57.06ms, and 15 normalized text mismatches.
- Ran a hybrid WhisperX CLI + MMS_FA post-align experiment:
  start MAE improved to 49.53ms, but end MAE regressed to 33.22ms and tail
  mean abs regressed to 66.50ms after repairing 24 word overlaps.
- Added the MFA research sidecar scaffold:
  `scripts/forced-align/setup-mfa-research.sh` prepares a research-only Conda
  environment and downloads MFA models, while
  `scripts/forced-align/mfa-align-cli.py` bridges `alignment-request.json` to
  MFA corpus/TextGrid output and back to top-level `timings[]` JSON.
- Added TextGrid parser contract coverage for MFA output without requiring MFA
  to be installed in default contract validation.

## 2026-06-19 15:19:15 CST

- Installed the local research-only MFA runtime through Homebrew `micromamba`
  and created the isolated MFA 3.3.9 environment under
  `~/Library/Caches/LLPlayerNext/research/mfa/env`.
- Downloaded MFA `english_mfa` and `english_us_arpa` dictionary/acoustic model
  files into the research cache.
- Confirmed that batch `mfa align` can complete first-pass alignment on TIMIT
  TEST 100, but fails during MFA's SQLite interval collection/export path with
  empty `word_intervals.csv` / `phone_intervals.csv` and missing
  `word_interval_temp`.
- Added the parallel `align-one` strategy to `mfa-align-cli.py`:
  each segment runs through MFA `align_one`, the sidecar resolves saved
  dictionary files and pre-extracted acoustic model directories before launch,
  and each child process receives an isolated `MFA_ROOT_DIR` to avoid MFA model
  cache and command-history write races.
- Ran MFA English US ARPA `align-one` against TIMIT TEST 100:
  881/881 matched words, start MAE 14.46ms, start P95 48.0ms, end MAE 18.20ms,
  end P95 53.0ms, tail mean abs 34.12ms, tail P95 112.05ms, 0 normalized text
  mismatches, and 5 suspicious words.
- Updated the Phase 4 conclusion: MFA is now the best observed word-boundary
  aligner under a high-quality transcript/utterance-anchor condition; the next
  realistic production test is WhisperX transcript + MFA.

## 2026-06-19 15:41:28 CST

- Paused further benchmark expansion and recorded the deferred aligner research
  directions in `research/deferred-aligner-directions.md`: Qwen3-ForcedAligner,
  BFA/easytranscriber/CTC, and MMS_FA remain later candidates, while the current
  production mainline is WhisperX transcript generation plus MFA `align-one`
  post-alignment.
- Extended `scripts/timeline-production/production_pipeline.py` with MFA
  post-alignment orchestration:
  `produce-whisperx --post-aligner mfa` now plans/runs the existing MFA sidecar
  after WhisperX conversion, appends an MFA WordTimeline, and preserves the
  WhisperX timeline as a candidate fallback.
- Added `apply-mfa-alignment` so an existing `.lltimeline.json` and its prepared
  audio can receive an MFA WordTimeline without rerunning WhisperX.
- Updated production dry-run contract validation to cover both the one-command
  MFA post-aligner plan and the standalone MFA application command.

## 2026-06-19 15:51:14 CST

- Generalized the production post-alignment stage into a selectable degradation
  strategy: `produce-whisperx --post-aligner auto|mfa|mms-fa|none`.
- `auto` and `mfa` now plan/run MFA first, then MMS_FA, and finally preserve the
  original WhisperX WordTimeline if every post-aligner fails. Each failed
  aligner attempt records a `post_alignment_failure` artifact in the
  `.lltimeline.json` resource.
- Added `apply-mms-fa-alignment` for appending a torchaudio MMS_FA WordTimeline
  to an existing `.lltimeline.json`, matching the existing MFA standalone path.
- Updated `doctor` and contract dry-runs so the local production environment
  exposes both the MFA runtime and MMS_FA research venv path.

## 2026-06-19 15:55:21 CST

- Marked the timeline-production and aligner-evaluation work as temporarily
  closed for the current push. It remains a long-running research and production
  maintenance area rather than the active implementation phase.
- Prepared Phase 2.2 under `.planning/phases/2.2-app-timeline-resource-ui/` to
  align the app UI with reusable LLTimeline resources: import visibility,
  WordTimeline candidate summaries, active timeline selection, playback binding,
  and a later manual-review entry point.
- Updated project state so Phase 2.2 is ready to start after Phase 2.1 closes,
  without continuing benchmark expansion first.
