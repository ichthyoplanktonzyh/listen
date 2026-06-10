# Milestone 1.7: Local Whisper Subtitle Generation

## Objective

Make usable learning subtitles available when media has no transcript or timed
caption. The first release generates subtitles locally on macOS Apple Silicon,
persists them as ordinary interactive `SubtitleTrack` records, and keeps the
ASR engine behind a provider boundary.

## LLPlayer Reference Findings

The original LLPlayer implementation was studied for behavior and architecture
only; no source code is copied.

Useful patterns:

- A common ASR service contract isolates whisper.cpp and Faster-Whisper.
- Media audio is decoded separately from playback and converted to 16 kHz mono.
- A bounded producer/consumer queue separates audio extraction from inference.
- Results are emitted incrementally with media-relative timestamps.
- Jobs support cancellation, language detection, translation, model selection,
  and starting from the current playback position.
- Dual subtitle views can reuse one recognition run.
- Generated results can be exported to SRT.

Patterns LLPlayerNext should change:

- Generated subtitles must be persisted automatically, not remain primarily in
  player memory.
- Job state, errors, engine version, model identity, language, and generation
  settings must be durable and inspectable.
- The first release should prefer deterministic whole-file generation over
  live incremental replacement.
- Windows-specific Faster-Whisper executables must not enter the shared
  contract.

## Initial Architecture

### Provider boundary

Define a platform-neutral `TranscriptionProvider` contract:

- stable provider ID and display name;
- availability and capability inspection;
- supported languages and translation capability;
- model discovery and validation;
- start, cancel, and inspect transcription jobs;
- normalized timed-segment output;
- structured progress, warning, and error events.

The contract exposes integer milliseconds and normalized segments only. It does
not expose whisper.cpp command-line types or model-library objects.

### First provider

The first provider uses a separately installed or application-managed
`whisper-cli` from whisper.cpp:

1. Resolve and validate `ffmpeg`, `whisper-cli`, and the selected model.
2. Extract the selected audio track to a temporary 16 kHz mono WAV file.
3. Run whisper.cpp with the chosen language or automatic detection.
4. Parse a structured or SRT result into normalized timed segments.
5. Import the completed result through the existing subtitle core.
6. Delete temporary audio and output files after successful persistence.

whisper.cpp is a good macOS-first candidate because it supports Apple Silicon,
Metal, and Core ML and uses the MIT license. Bundling remains a separate release
and license review decision; the first implementation may discover a
user-installed executable.

### Durable job model

Add a durable `TranscriptionJob` with:

- job ID, media ID, provider ID, model ID, and selected audio track;
- requested and detected language;
- optional translate-to-English mode;
- status: queued, extracting, transcribing, importing, completed, cancelled,
  or failed;
- progress, created/started/completed timestamps, and structured error;
- generated subtitle track ID when completed;
- provider version and normalized generation settings.

Completed generated subtitles are ordinary interactive tracks. Media loss must
not remove vocabulary occurrence snapshots already captured from them.

## Desktop Experience

- Add **Generate subtitles** beside subtitle import actions.
- Show provider/model availability before starting.
- Offer language auto-detection or explicit language, model selection, and
  primary/secondary destination.
- Show extraction and transcription progress with cancel support.
- Keep playback usable while a background job runs.
- On completion, load the generated track as the selected learning subtitle.
- Expose generated-source metadata and allow SRT export.
- Allow retry after failure without duplicating a completed track.

## Scope Order

1. Whole-file local transcription and automatic persistence.
2. Model/executable management and diagnostics.
3. Progress, cancellation, retry, and generated SRT export.
4. Transcript import plus forced alignment.
5. Incremental generation from the current playback position.
6. Additional providers such as embedded whisper.cpp or Faster-Whisper.

## Explicit Boundaries

- No cloud transcription provider in the first release.
- No microphone or live-stream transcription.
- No speaker diarization.
- No word-level or phoneme-level timing contract yet.
- No automatic translation other than provider-supported translate-to-English.
- No silent background downloads without explicit user action.

## Verification Gate

- Generate English subtitles from local video and audio fixtures.
- Generated tracks survive restart and support seeking, looping, token clicks,
  vocabulary state, and source snapshots.
- Cancellation removes temporary files and leaves no partial active track.
- Repeating an identical completed job is idempotent.
- Missing executable, model, disk space, corrupt media, and provider failure
  produce structured recoverable errors.
- Playback remains responsive during background generation.
- A generated SRT export can be re-imported with equivalent timing and text.
- macOS Apple Silicon package smoke test passes with the provider absent and
  with a configured provider.
