# ADR 0006: Transcription Provider And Model Boundaries

- Status: Proposed for Milestone 1.7
- Date: 2026-06-10

## Context

Local subtitle generation begins with whisper.cpp on macOS Apple Silicon, but
speech-recognition engines and models change quickly. A public contract tied to
Whisper model names, GGML files, or whisper-cli flags would make later model
families and providers expensive to adopt.

The same model may also run through different runtimes, while similarly named
model revisions may have different formats, checksums, capabilities, licenses,
or hardware requirements.

## Decision

Keep four identities independent:

- `TranscriptionProvider`: adapter implementing the shared application
  contract.
- `TranscriptionRuntime`: concrete executable, library, or service version.
- `TranscriptionModel`: immutable model revision and asset identity.
- `TranscriptionProfile`: user preference expressed through shared
  capabilities and quality tiers.

Providers register runtime and model descriptors. Compatibility is negotiated
from stable IDs, version constraints, model formats, hardware requirements, and
capability declarations. A job snapshots the exact provider, runtime, model
revision/checksum, and normalized settings used.

The shared result remains normalized timed text. Optional capabilities such as
word timing, translation, streaming, VAD, and diarization are declared and
stored as optional metadata. No base domain or HTTP API type exposes
Whisper-specific command-line flags or model-library objects.

Model installation and model selection are separate operations. Changing a
default model affects only future jobs. Regeneration with another model creates
a new subtitle track and never rewrites an existing generated track.

## Consequences

- The first whisper.cpp provider requires more descriptor and compatibility
  code than a direct command wrapper.
- Future local, embedded, cloud, or non-Whisper providers can reuse the same
  job, UI, persistence, and subtitle-import pipeline.
- Removed runtimes or models do not make historical jobs unintelligible because
  their immutable identities and settings remain recorded.
- Remote model catalogs require signing, checksum verification, explicit
  download consent, provenance, and license review before adoption.
