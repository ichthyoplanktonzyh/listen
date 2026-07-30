# Structure

| Path | Current responsibility |
|---|---|
| `crates/domain` | stable domain records and invariants |
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
| `scripts/timeline-production` | production pipeline |
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
- `SecretCleanupRepository` and atomic profile-mutation methods own the durable
  provider-credential cleanup outbox.
- `SemanticLlmRuntimeFactory` and `RealtimeConversationAdapterFactory` keep
  concrete provider selection out of HTTP route modules.
- `ForcedAlignProvider` keeps sidecar process and wire protocol details in
  `local-runtime`.
- `learning-resource-runtime` gives installers and dictionary readers one
  authoritative resource directory, opaque filename scheme, and replacement
  signature without exposing local paths through learner-facing contracts.
- `LocalRealtimeCascadeRuntime` owns opt-in local speech-cascade spawn,
  pool-readiness, bounded diagnostics, and process-group shutdown; the
  `local_cascade_realtime` codec remains in `realtime-provider`.
- `SubtitleTrackRepository::save_track_and_replace_corpus` is the atomic
  subtitle/corpus unit of work.

Paths under `.planning/archive/monorepo-baseline` are historical and never used
to infer current physical structure.
