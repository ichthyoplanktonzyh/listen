# Phase 3 Production Pipeline V1

更新时间：2026-06-18 19:30:22 CST

Phase 3 的第一步不是把 WhisperX、Demucs、MFA 等重依赖塞进应用，而是建立本地
生产端的稳定边界：

```text
media file
  -> prepare-media
  -> optional external vocal isolation
  -> run-whisperx
  -> from-whisperx-json
  -> .lltimeline.json
  -> production-report.json
  -> lltimeline-resource.py import
  -> LLPlayerNext resource store
```

## Implemented Slice

- `scripts/timeline-production/setup-venv.sh`
- `scripts/timeline-production/requirements.txt`
- `scripts/timeline-production/production_pipeline.py`
- `testdata/timeline-production/whisperx-sample.json`

## Commands

```sh
scripts/timeline-production/production_pipeline.py doctor

scripts/timeline-production/production_pipeline.py prepare-audio \
  --input input.mp4 \
  --output-dir /tmp/llplayer-production

scripts/timeline-production/production_pipeline.py prepare-media \
  --input input.mp4 \
  --output-dir /tmp/llplayer-production \
  --vocal-isolation-command 'my-isolator --input {input} --output {output}'

scripts/timeline-production/production_pipeline.py run-whisperx \
  --input /tmp/llplayer-production/vocals-16k-mono.wav \
  --output-dir /tmp/llplayer-production/whisperx \
  --model large-v3 \
  --language en \
  --device cpu \
  --compute-type float32

scripts/timeline-production/production_pipeline.py from-whisperx-json \
  --input /tmp/llplayer-production/whisperx/vocals-16k-mono.json \
  --output output.lltimeline.json \
  --media-fingerprint <fingerprint> \
  --media-title "CNN10 sample" \
  --media-path /path/to/video.mp4 \
  --preprocessing-artifacts /tmp/llplayer-production/preprocessing-artifacts.json

scripts/timeline-production/production_pipeline.py produce-whisperx \
  --input input.mp4 \
  --output-dir /tmp/llplayer-production \
  --output output.lltimeline.json \
  --media-fingerprint <fingerprint> \
  --media-title "CNN10 sample" \
  --model large-v3 \
  --language en

scripts/timeline-production/production_pipeline.py report \
  --input output.lltimeline.json \
  --output production-report.json
```

## Current Boundary

Phase 3 is complete as the first local heavy production pipeline boundary. The
default development contract tests verify command construction, JSON conversion,
LLTimeline validation, and production report generation. A real production run
still requires the separate timeline-production venv and model cache.

`production-report.json` is not the full Phase 4 benchmark report. It is the
per-run production quality artifact that records whether the generated
`.lltimeline.json` is structurally ready for manual review:

- word timeline coverage against transcript word tokens;
- overlap and large-gap diagnostics inside each sentence;
- confidence availability and average confidence;
- provider ids and artifact kinds attached to the resource;
- `ready_for_manual_review` as the handoff flag into correction/evaluation.

Next production steps:

- replace external vocal-isolation command templates with first-class Demucs/UVR presets;
- add VAD artifacts;
- build Phase 4 candidate comparison reports;
- add chunk timeline generation from the imported word timeline.
