# Phase 3 Production Pipeline V1

更新时间：2026-06-18 16:06:35 CST

Phase 3 的第一步不是把 WhisperX、Demucs、MFA 等重依赖塞进应用，而是建立本地
生产端的稳定边界：

```text
media file
  -> prepare-media
  -> optional external vocal isolation
  -> run-whisperx
  -> from-whisperx-json
  -> .lltimeline.json
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
```

## Current Boundary

The production pipeline can now invoke WhisperX, but the default development
contract tests only verify command construction and JSON conversion. A real
production run still requires the separate timeline-production venv and model
cache.

Next production steps:

- replace external vocal-isolation command templates with first-class Demucs/UVR presets;
- add VAD artifacts;
- add candidate comparison reports;
- add chunk timeline generation from the imported word timeline.
