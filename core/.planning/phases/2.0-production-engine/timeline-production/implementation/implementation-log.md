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
