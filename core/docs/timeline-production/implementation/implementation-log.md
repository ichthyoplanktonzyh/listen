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
