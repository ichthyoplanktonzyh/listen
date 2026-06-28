# LLPlayerNext System Architecture

Last updated: 2026-06-27. Reflects the Phase 2.18 code architecture refactor.

## Overview

```text
Flutter desktop app
  UI + fvp player + local timeline cursor
        |
        | HTTP REST + SSE on localhost
        v
api-http
  Axum transport, auth, route composition, event stream
        |
        v
application
  use-case orchestration, repository/provider traits, DTO mapping
        |
        +--> domain              # stable domain types
        +--> subtitle-core       # subtitle import/tokenization
        +--> diagnosis-core      # pure learning diagnosis
        +--> speech-analysis     # ASR timing/chunk/phone analysis engines
        +--> dictionary-provider # dictionary + lexical normalization providers
        |
        v
persistence-sqlite
  SQLite repository implementation and migrations
```

Dependency direction is intentionally boring:

```text
domain <- core engines <- application <- api-http / persistence-sqlite
```

`api-http` does not call algorithm crates directly. Algorithms enter through
application use cases and provider/repository boundaries.

## Crate Responsibilities

### `domain`

- Leaf crate for stable data types and IDs.
- Owns `MediaItem`, subtitle models, `LexicalEntry`, `LexicalUnit`,
  `LearningStatus`, timeline resources, LLTimeline resources, dictionary,
  transcription, phonetic analysis, and diagnosis DTOs.
- `TimelineMetrics` and `ChunkEvidence` wrap timeline JSON extension objects
  while preserving object-shaped API/storage JSON.
- `DomainError` is the shared validation error type.

### `application`

- `AppServices` is the use-case facade.
- Repository boundaries are split by aggregate/resource:
  - `MediaRepository`
  - `SubtitleTrackRepository`
  - `PronunciationRepository`
  - `TimelineResourceRepository`
  - `LLTimelineResourceRepository`
  - `LearningAssetRepository`
  - transcription, phonetic analysis, dictionary cache, playback progress
- Application-owned DTOs sit in `application::dto`; algorithm crate structs are
  mapped at the boundary instead of re-exported.
- Learning assets use `LexicalEntry + LexicalUnit` as the authoritative model.

### `api-http`

- Axum loopback HTTP server with bearer-token auth.
- Root `lib.rs` is the composition root for route groups, middleware, SSE, and
  service construction.
- OpenAPI parity is tested bidirectionally: implemented `/v1` routes and
  documented OpenAPI paths must match.
- Lexical routes are the only learning-asset API surface:
  - `/v1/lexical-entries`
  - `/v1/lexical-entries/batch`
  - `/v1/lexical-entries/{id}`
  - `/v1/lexical-entries/{id}/learning-content`
  - `/v1/lexical-observations`

### `persistence-sqlite`

- Single local SQLite repository implementation.
- A single `SqliteRepository` may implement multiple repository traits; the
  narrow traits keep use cases from depending on a god interface.
- Schema is allowed to be destructively rebuilt during Phase 2.18.
- Partial unique indexes enforce one active word/chunk/phone timeline per track.
- Lexical export/import version 5 is lexical-only.

### `diagnosis-core`

- Pure deterministic diagnosis engine.
- Inputs: `SubtitleSentence`, `LexicalEntry[]`, and `LexicalObservation[]`.
- Outputs: meaning barrier, recognition barrier, insufficient evidence, and
  reason hints using lexical entry IDs.

### `speech-analysis`

Owns analysis engines, not application contracts:

| Module | Responsibility |
|---|---|
| `asr_timing` | ASR word timing extraction |
| `forced_align` | forced alignment integration |
| `pause_refinement` | silence-based boundary refinement |
| `chunk_partition` | word timeline to learning chunk partition |
| `phonetic_alignment` | phoneme sequence alignment |
| `phonetic_findings` | reductions, elision, linking findings |
| `learned_prosodic_provider` | rule-based prosodic analysis |
| `rich_acoustic_evidence` | acoustic evidence aggregation |

### Flutter Desktop

- `main.dart` remains the composition screen, but event parsing and learning
  workflows plus speech-enhancement/timeline-resource refresh have been pulled
  into controllers/coordinators.
- `LearningController` stores typed lexical entries, phrase candidates,
  selected lexical details, dictionary lookup, word pronunciation, language
  profile, and diagnosis.
- `SubtitleController` stores typed pronunciation providers, sentence
  pronunciation analyses, and phonetic analyses.
- `BackendEvent` parsing is typed; lexical change events update the typed
  learning cache.
- Timeline models use typed metrics/evidence envelopes.
- Dictionary, word pronunciation, sentence pronunciation, and phonetic-analysis
  payloads are parsed at API boundaries before entering controller/widget state.

## Main Data Flows

### Media And Subtitle Import

```text
file picker -> api-http -> application -> subtitle-core -> SQLite -> typed track
```

### Learning Lookup And Status

```text
token click -> lexical entry lookup/upsert -> dictionary/pronunciation lookup
  -> LearningController typed state -> WordLearningPanel
```

### Diagnosis

```text
cue change -> LearningWorkflowController generation guard
  -> /v1/sentences/{id}/diagnosis
  -> diagnosis-core over lexical entries + observations
  -> typed Diagnosis state
```

### Timeline Resources

```text
subtitle track -> word timeline -> chunk timeline / phone timeline
  -> SpeechEnhancementWorkflowController -> Flutter timeline/pronunciation model
```

### LLTimeline Import/Export

```text
.lltimeline.json -> api-http -> application validation/fingerprint handling
  -> persisted LLTimeline metadata/artifacts + generated timeline resources
```

## Current Guardrails

- `cargo test -p api-http openapi` verifies route/OpenAPI parity.
- `scripts/validate-contracts.sh` verifies contract smoke paths, event schema,
  generated client methods, and route drift.
- Flutter `LearningController` tests cover typed selection/clearing.
- Persistence tests cover active timeline resource behavior and lexical asset
  import/export.

## Remaining Architecture Debt

1. `main.dart` is still large. Phase 2.18 moved event parsing, core learning
   workflows, and speech-enhancement/timeline refresh out first; remaining
   media/session/resource action wiring can be extracted later.
2. `speech-analysis` still contains several subdomains in one crate. This is
   acceptable until APIs stabilize, but it should not leak public DTO shapes.
3. Route strings still live in the Axum router chain. The parity test is the
   current guardrail; a manifest can be added later if route growth continues.
