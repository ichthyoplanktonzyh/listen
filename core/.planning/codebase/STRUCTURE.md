# Structure

| Path | Current responsibility |
|---|---|
| `crates/domain` | stable domain records and invariants |
| `crates/content-package` | bounded inspection and typed decoding for `.listenpkg` exchange packages |
| `crates/application` | use cases, repositories, provider-neutral ports |
| `crates/api-http` | loopback composition, routes, handshake, health |
| `crates/api-events` | event envelopes |
| `crates/persistence-sqlite` | SQLite repositories and migrations |
| `crates/subtitle-core` | subtitle parsing/tokenization |
| `crates/diagnosis-core` | deterministic diagnosis |
| `crates/speech-analysis` | timing, speech, phonetic analysis |
| `crates/*-provider` | dictionary, embedding, LLM, realtime, syntax adapters |
| `crates/learning-resource-runtime` | authoritative installed-resource paths and file change signatures |
| `crates/local-runtime` | local capability/runtime lifecycle |
| `crates/writing-feedback` | writing feedback behavior |
| `contracts` | canonical HTTP/event/player/resource schemas |
| `contracts/content-package/v1` | canonical `.listenpkg` v1 manifest, typed content-resource schemas, and complete example package tree |
| `scripts/` | evaluation/research tooling; reusable offline production lives in `listen-gen` |
| `scripts/forced-align` | alignment research tooling |
| `scripts/syntactic-analysis` | syntax capability tooling |
| `scripts/release_artifacts.py` | deterministic release packaging/verification |
| `testdata` | committed license-clear fixtures |
| `docs/domain` | current domain maps and code/contract terminology mappings |
| `docs/decisions` | append-only ADRs |
| `.planning` | current core project memory |

Notable runtime seams:

- `application::BackgroundJobStore` owns durable generic job lifecycle
  semantics; `persistence-sqlite` supplies the production adapter.
- `application::LearningPreparationUseCases` owns the internal recommended
  foundation planner and typed state machine. Its dedicated SQLite repository
  owns revision CAS and target-level single-flight; it does not inherit
  `BackgroundJobStore`.
- `local_runtime::LearningPreparationCoordinator` adapts the fixed foundation
  plan to `AppServices`; it has no HTTP route, SoundLine dependency, or generic
  resource/job abstraction.
- `local_runtime::RecordingTranscriptionCoordinator` owns learner-recording
  transcription and the provider/model catalog. Its jobs are ephemeral,
  in-memory short-recording runs that consume existing `RecordingAsset`s and
  never import subtitle tracks; whole-media transcription jobs were removed in
  the R1 cutover. `whisper-cli` resolution is owned here; `ffmpeg`/`ffprobe`
  stay shared with sound-line and other Core paths.
- `SecretCleanupRepository` and atomic profile-mutation methods own the durable
  provider-credential cleanup outbox.
- `SemanticLlmRuntimeFactory` and `RealtimeConversationAdapterFactory` keep
  concrete provider selection out of HTTP route modules.
- `ForcedAlignProvider` keeps sidecar process and wire protocol details in
  `local-runtime`.
- `learning-resource-runtime` gives installers and dictionary readers one
  authoritative resource directory, opaque filename scheme, and replacement
  signature without exposing local paths through learner-facing contracts.
- `ManagedFastEmbedProvider` owns candidate isolation, artifact-integrity
  validation, atomic active-manifest publication, last-good retention, and
  failed-candidate provenance for the local embedding runtime.
- `LocalRealtimeCascadeRuntime` owns opt-in local speech-cascade spawn,
  pool-readiness, bounded diagnostics, and process-group shutdown; the
  `local_cascade_realtime` codec remains in `realtime-provider`.
- `SyntaxCapabilityManager` owns candidate-isolated syntax delivery, durable
  active-release publication, and atomic routing to the last validated provider.
- `SubtitleTrackRepository::save_track_and_replace_corpus` is the atomic
  subtitle/corpus unit of work.
- `LLTimelineImportRepository` is the import-only atomic boundary for a
  validated LLTimeline snapshot; resource families keep their independent
  lifecycle repositories after import.
- `application::prepare_content_package_document` converts a verified package
  into candidate-only Core projections and an explicit per-resource receipt.
- `ContentPackageImportRepository` is the dedicated atomic persistence seam for
  those projections. It is idempotent, never selects an active analysis, and
  does not call the legacy LLTimeline import operation.
- `api-http::routes::media::import_content_package` is the additive local-path
  HTTP adapter for that application seam. Its wire DTO preserves the nested
  receipt, exposes validated envelope provenance/review status, represents
  opaque-resource trust facts as unknown, and maps package failures to stable
  redacted error codes.

Paths under `.planning/archive/monorepo-baseline` are historical and never used
to infer current physical structure.
