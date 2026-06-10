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

### Replaceable engine and model architecture

Treat these as four separate concepts:

1. `TranscriptionProvider`: integrates one execution family or service and
   translates its behavior into the shared contract.
2. `TranscriptionRuntime`: a concrete installed executable, embedded library,
   local service, or remote service version capable of running compatible
   models.
3. `TranscriptionModel`: a discoverable model asset with stable identity,
   revision, format, provenance, checksum, size, and capabilities.
4. `TranscriptionProfile`: user-selected runtime-independent defaults such as
   preferred language, quality tier, translation mode, and segmentation
   policy.

Model identity must not be a display name such as `small.en`. It uses a stable
namespaced ID plus an immutable revision and checksum. Jobs store the exact
provider, runtime, model revision, and normalized settings used, so results
remain reproducible after defaults or installed models change.

Each model exposes a provider-independent `TranscriptionModelDescriptor`:

- stable model ID, display name, family, revision, format, and provenance;
- installed, downloadable, remote-only, or unavailable state;
- file size and cryptographic checksum when locally managed;
- supported languages and English-only status;
- capabilities such as transcription, translation, timestamps, word timing,
  streaming, diarization, and VAD;
- quality tier and approximate memory/compute requirements;
- compatible provider IDs, runtime IDs, and version constraints;
- license and redistribution metadata.

Providers and runtimes expose capability descriptors independently. The
application selects only compatible runtime/model pairs and validates them
again when a job starts. Unsupported capabilities degrade explicitly rather
than being silently ignored.

Public job and subtitle contracts must remain model-family neutral. They may
record optional word timing or speaker labels as capability-gated metadata,
but the base timed-segment contract cannot require Whisper-specific tokens,
GGML/GGUF files, Core ML artifacts, or command-line flags.

Model discovery uses a registry assembled from provider manifests:

- bundled manifests describe models tested by the application;
- providers may discover manually installed compatible models;
- future signed remote catalogs may advertise new revisions without an
  application release;
- users may add custom model paths, but these remain explicitly unverified.

Changing the default model never mutates existing generated subtitle tracks or
jobs. Regenerating with another model creates a new track so users can compare
and choose results without losing the previous version.

### First provider

The first provider uses the application-bundled, version-pinned `whisper-cli`
from whisper.cpp:

1. Resolve and validate `ffmpeg`, `whisper-cli`, and the selected model.
2. Extract the selected audio track to a temporary 16 kHz mono WAV file.
3. Run whisper.cpp with the chosen language or automatic detection.
4. Parse a structured or SRT result into normalized timed segments.
5. Import the completed result through the existing subtitle core.
6. Delete temporary audio and output files after successful persistence.

whisper.cpp is the macOS-first provider because it supports Apple Silicon and
Metal and uses the MIT license. The release also bundles a pinned LGPL-only
FFmpeg/ffprobe build. Models are installed explicitly through Model Manager.

### Durable job model

Add a durable `TranscriptionJob` with:

- job ID, media ID, provider ID, runtime ID/version, model ID/revision/checksum,
  and selected audio track;
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
- Let users choose compatible installed models and remember a preferred
  quality tier without hard-coding one model name.
- Offer language auto-detection or explicit language, model selection, and
  primary/secondary destination.
- Show extraction and transcription progress with cancel support.
- Keep playback usable while a background job runs.
- On completion, load the generated track as the selected learning subtitle.
- Expose generated-source metadata and allow SRT export.
- Allow retry after failure without duplicating a completed track.

The detailed desktop interaction contract is defined in
`docs/planning/milestone-1.7-asr-ui.md`.

## LLPlayer Experience Parity

The architecture can support the complete useful LLPlayer ASR experience, but
the first implementation is intentionally staged.

Required parity before Milestone 1.7 is considered complete:

- start ASR independently for the primary or secondary subtitle destination;
- choose provider/runtime/model, language auto-detection or explicit language,
  and provider-supported translate-to-English;
- install, cancel installation, delete, inspect, and manually locate models;
- show model size, installation state, compatibility, and hardware guidance;
- show durable extraction/transcription/import progress and allow cancellation;
- keep completed generated subtitles after restart and export them as SRT;
- regenerate with a different model without replacing the previous track;
- expose provider/runtime diagnostics and actionable configuration errors.

Deferred parity:

- regenerate incrementally from the current playback position;
- display partial segments while recognition is still running;
- reuse one running recognition job simultaneously for primary and secondary;
- provider-specific expert knobs such as raw command arguments;
- runtime priority tuning and debug-command copying.

These deferred items remain compatible with the provider, runtime, model, and
durable-job contracts and do not require another public architecture rewrite.

## Scope Order

1. Provider/runtime/model registry and durable transcription jobs.
2. Whole-file local transcription and automatic persistence.
3. Model installation, selection, removal, validation, and diagnostics UI.
4. Progress, cancellation, retry, generated-track selection, and SRT export.
5. Incremental generation from the current playback position and partial
   segment display.
6. Shared running jobs for dual subtitle destinations.
7. Transcript import plus forced alignment.
8. Additional providers such as embedded whisper.cpp or Faster-Whisper.
9. Signed remote model catalogs and richer model-family capabilities.

## Explicit Boundaries

- No cloud transcription provider in the first release.
- No microphone or live-stream transcription.
- No speaker diarization.
- No word-level or phoneme-level timing contract yet.
- No transcript forced alignment in Milestone 1.7.
- No automatic translation other than provider-supported translate-to-English.
- No silent background downloads without explicit user action.
- No assumption that future providers or models belong to the Whisper family.

## Verification Gate

- Generate English subtitles from local video and audio fixtures.
- Generated tracks survive restart and support seeking, looping, token clicks,
  vocabulary state, and source snapshots.
- Cancellation removes temporary files and leaves no partial active track.
- Repeating an identical completed job is idempotent.
- Switching model or model revision creates a separate generated track and
  preserves the previous result.
- Mock providers with incompatible and partially supported models verify
  capability negotiation and explicit degradation.
- Jobs remain inspectable after their original runtime or model is removed.
- Missing executable, model, disk space, corrupt media, and provider failure
  produce structured recoverable errors.
- Playback remains responsive during background generation.
- A generated SRT export can be re-imported with equivalent timing and text.
- macOS Apple Silicon package smoke test passes with the provider absent and
  with a configured provider.
