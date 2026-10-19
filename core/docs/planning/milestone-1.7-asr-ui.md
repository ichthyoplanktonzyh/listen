# Milestone 1.7 ASR Desktop UI Contract

## Goal

Match the useful ASR workflow of LLPlayer while presenting engine-independent
choices first. Provider-specific expert controls remain available without
making the normal subtitle-generation flow depend on Whisper terminology.

## Reference Experience

The original LLPlayer ASR UI was studied for interaction behavior only; no
source code or visual assets are copied.

Useful behaviors to retain:

- primary and secondary subtitle menus each expose an ASR action;
- the current language and ASR state are visible at the action point;
- language detection and translate-to-English are shared choices;
- engine and model selection are separate;
- model download, cancellation, deletion, installed size, and model folder are
  visible in one management flow;
- larger and English-only models are explained before selection;
- generation shows an active loading indicator;
- generated subtitles can be exported;
- advanced engine and hardware controls are available to expert users.

## Navigation

### Quick action

Add **Generate subtitles** to the primary and secondary subtitle actions.
Opening it shows a generation sheet instead of starting immediately.

The action displays one of:

- `Generate subtitles`
- `Generating · 42%`
- `Generated · Model name`
- `Configuration required`
- `Generation failed`

Selecting a running action opens job progress. Selecting a completed action
opens generated-track details and regeneration options.

### Generate subtitles sheet

The initial sheet contains:

- destination: primary or secondary;
- audio track;
- language: automatic or explicit;
- purpose: transcription or provider-supported translate-to-English;
- quality preference: fast, balanced, accurate, or explicit model;
- compatible model selector;
- estimated model size, memory need, and expected relative speed;
- **Generate whole media** primary action;
- **Generate from current position** action when the provider supports
  incremental generation;
- configuration warning and direct link to Model Manager when no compatible
  model is ready.

The sheet remembers a `TranscriptionProfile`, not a provider-specific model
name. If the preferred model disappears, the UI asks for a compatible
replacement rather than silently choosing one.

## Model Manager

The Model Manager is a full settings page with provider and runtime filters.
Each model row shows:

- display name, family, immutable revision, and provider;
- installed/downloadable/custom/unavailable state;
- language coverage and English-only marker;
- capabilities such as translation, word timing, streaming, VAD, and
  diarization;
- quality tier, file size, approximate memory need, and hardware compatibility;
- tested, unverified, update available, or incompatible status;
- license/provenance summary.

Available actions:

- install with explicit destination and download size;
- cancel installation;
- retry failed installation;
- verify checksum;
- set as preferred for a quality tier;
- remove an unused model;
- reveal model file;
- register a custom model path;
- inspect which historical jobs used a model.

Removing a model never removes generated subtitle tracks or job history. Active
jobs prevent removal of their runtime or model.

## Settings

### General transcription settings

- preferred provider or automatic compatible provider selection;
- fast, balanced, and accurate preferred models;
- automatic language detection default;
- explicit fallback language;
- translate-to-English default when supported;
- default destination and audio track behavior;
- temporary-file location and cleanup policy;
- maximum concurrent jobs and playback-protection resource policy.

### Advanced provider settings

Advanced controls are grouped by provider and rendered from provider
descriptors. They may include:

- thread or compute-device selection;
- segmentation length and token limits;
- prompt or vocabulary hints;
- silence threshold, VAD, context, and word splitting;
- process priority and custom runtime/model paths;
- provider-specific extra arguments.

Unsupported settings are hidden or disabled with an explanation. Raw arguments
are explicitly marked unverified and stored only in provider-specific job
metadata, never in the shared contract.

## Job Progress And Results

A persistent job center shows queued, extracting, transcribing, importing,
completed, cancelled, and failed jobs.

For a running job, show:

- media title, destination, provider/runtime/model;
- current phase and progress;
- elapsed time and provider-supplied estimate when available;
- pause only when declared by the provider;
- cancel and reveal diagnostics.

For a completed job, show:

- generated subtitle track and detected language;
- model/runtime/settings provenance;
- load as primary or secondary;
- export SRT;
- regenerate with another model;
- compare tracks;
- archive or remove the generated track without removing job history.

Partial segments may appear in the player only after incremental generation is
implemented. They must be visually marked as provisional and must not create
durable vocabulary occurrences until finalized.

## Error And Safety Rules

- Missing runtime, model, disk space, permissions, incompatible hardware, and
  corrupt media have distinct actionable messages.
- Downloads require explicit user confirmation and show provenance and license.
- Cancelling or failing a job cleans temporary files and never publishes a
  partial active subtitle track.
- Provider-specific failure never blocks local playback or imported subtitles.
- A setting unsupported by the selected runtime/model is never silently
  ignored.

## UI Acceptance

- A first-time user can install a compatible model and generate a learning
  subtitle without opening advanced settings.
- An expert can select a runtime, model revision, device, segmentation, prompt,
  and provider-specific settings.
- Switching models clearly creates a new generated track.
- Primary and secondary destinations are clear and never overwrite one another.
- Model installation, cancellation, removal, compatibility, and historical-use
  states are understandable without reading logs.
- The normal flow remains provider-neutral when a non-Whisper mock provider is
  registered.
