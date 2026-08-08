# ASR Runtime Build And Redistribution

Milestone 1.7 packaged three macOS Apple Silicon command-line runtimes inside
`LLPlayerNext.app/Contents/Resources/runtime`:

- whisper.cpp `whisper-cli` v1.7.6, source commit
  `a8d002cfd879315632a579e73f0148d06959de36`, MIT license.
- FFmpeg and ffprobe 8.0.1, official source archive SHA-256
  `05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41`,
  LGPL-2.1-or-later configuration.

`scripts/build-asr-runtime.sh` performs the reproducible source build.
`scripts/verify-asr-runtime.sh` blocks packaging unless every executable is
arm64, uses only macOS system dynamic libraries, and FFmpeg reports both
`--disable-gpl` and `--disable-nonfree`.

Built binaries are deliberately excluded from Git. The release package carries
the versioned `third_party/runtime/manifest.json`. Transcription models are not
redistributed; users explicitly download checksum-pinned model files from the
Model Manager or register their own compatible model.

Current ownership: `whisper-cli` is consumed by Core's learner-recording
transcription (`/v1/recording-transcriptions*`) and realtime model selection.
`ffmpeg`/`ffprobe` remain shared because SoundLine and other Core media paths
still consume them. Whole-media transcription jobs were removed from Core; the
reusable whole-media producer lives in `listen-gen`.

The application does not expose whisper.cpp command flags through its public
domain or HTTP contracts.
