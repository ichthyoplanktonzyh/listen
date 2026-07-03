# LLPlayerNext System Architecture

Last updated: 2026-07-02. Reflects Phase 3.0.1 plus Phase 2.23 documentation cleanup.

## Overview

```text
Flutter desktop app
  UI + fvp player + local timeline cursor
        |
        | HTTP REST + SSE on localhost
        v
api-http
  Axum transport, auth, route composition, event stream, adapter composition
        |
        +--> application
        |     use-case orchestration, repository/provider traits, DTO mapping
        |       |
        |       +--> domain              # stable domain types
        |       +--> subtitle-core       # subtitle import/tokenization
        |       +--> diagnosis-core      # pure learning diagnosis
        |       +--> speech-analysis     # ASR timing/chunk/phone analysis engines
        |
        +--> dictionary-provider         # application provider adapter
        +--> persistence-sqlite          # application repository adapter
```

Dependency direction is intentionally boring:

```text
domain <- core engines <- application <- api-http / persistence-sqlite / dictionary-provider
```

`api-http` does not call algorithm crates directly. Algorithms enter through
application use cases and provider/repository boundaries.

## Crate Responsibilities

### `domain`

- Leaf crate for stable data types and IDs.
- Owns `MediaItem`, subtitle models, `LexicalEntry`, `LexicalUnit`,
  `LearningStatus`, timeline resources, LLTimeline resources, dictionary,
  transcription, phonetic analysis, diagnosis DTOs, and Phase 3.0.1 learning-loop
  models.
- Learning-loop models include `PracticeSession`, `PracticeItem`, `PracticeAttempt`,
  `ReviewItem`, `ReviewAttempt`, `LearningEvent`, corpus/difficulty/learner-profile
  data shapes, and recording/shadowing metadata shapes.
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
  - `PracticeRepository`
  - `ReviewRepository`
  - `LearningEventRepository`
  - transcription, phonetic analysis, dictionary cache, playback progress
- Application-owned DTOs sit in `application::dto`; algorithm crate structs are
  mapped at the boundary instead of re-exported.
- Learning assets use `LexicalEntry + LexicalUnit` as the authoritative model.
- Phase 3.0.1 practice services can create practice sessions/items, evaluate
  text attempts, persist `PracticeAttempt`, write failed lexical anchors as
  `LexicalObservation`, optionally create `ReviewItem`, and append `LearningEvent`.

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
- Learning-loop foundation routes:
  - `/v1/practice/sessions`
  - `/v1/practice/items`
  - `/v1/practice/attempts`
  - `/v1/practice/attempts/{id}`
  - `/v1/review/items`
  - `/v1/review/items/{id}`

### `persistence-sqlite`

- Single local SQLite repository implementation.
- A single `SqliteRepository` may implement multiple repository traits; the
  narrow traits keep use cases from depending on a god interface.
- Schema is allowed to be destructively rebuilt during Phase 2.18.
- Partial unique indexes enforce one active word/chunk/phone timeline per track.
- Lexical export/import version 5 is lexical-only.
- Schema v15 adds `practice_sessions`, `practice_items`, `practice_attempts`,
  `review_items`, `review_attempts`, and `learning_events`.
- Schema v16 destructively resets lexical/learning-resource tables to the
  authoritative `LexicalEntry + LexicalUnit + LexicalObservation` shape for
  local databases that had already run the old v7 lexical migration.
- Schema v17 drops the unused SQLite `learning_resources` table; downloadable
  learning resources remain an API/filesystem resource-manager concern.
- Learning-loop persistence stores JSON snapshots plus query columns for kind,
  status, subject, result, and timestamps. Corpus/difficulty/recording persistence
  is not yet implemented.

### `diagnosis-core`

- Pure deterministic diagnosis engine.
- Inputs: `SubtitleSentence`, `LexicalEntry[]`, `LexicalObservation[]`, and a
  token→lexical-key map. Token normalization is surface-level lowercasing while
  entry keys come from the language's normalization provider; the caller
  (`AppServices::diagnose_sentence`) resolves each token through the provider
  chain and passes the mapping so inflected forms classify against their lemma
  entries.
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
| `connected_speech_rules` | text-side Reference B default connected-form prediction |
| `sound_analysis` | learning-phone, syllable, phrase, connected-speech and WordTimeline-first RhythmFrame generation with optional word acoustic prominence cues |
| `learned_prosodic_provider` | rule-based prosodic analysis |
| `rich_acoustic_evidence` | acoustic evidence aggregation |

The pronunciation provider uses CMUdict when available and a deterministic
`fallback-v2` G2P for OOV words. Fallback stress is intentionally conservative:
one primary fallback vowel, later fallback vowels unstressed.

### Flutter Desktop

- **UI state pattern (single track)**: `controller + Store<T>` is the only UI
  state model. Controllers (`PlayerController`, `SubtitleController`,
  `LearningController`, ...) wrap a `state/store.dart` `Store<T>` with
  fine-grained selectors; widgets rebuild via `ListenableBuilder`/
  `StoreBuilder`. `setState` in `main.dart` is reserved for genuinely local
  UI state (connect spinner, drag hover, task-status map) — 10 call sites
  after Phase 2.23 Step 3 (was 107). App-level status text lives in
  `PlayerController.status`; no duplicated host field.
- `main.dart` is a composition root (~1.46k lines after Phase 2.23 Step 3,
  was 3.6k): controller/coordinator construction and binding, top-level
  layout, dialog wrappers, and thin wiring only. Business workflows live in:
  - `controllers/resource_actions_coordinator.dart` — subtitle/timeline
    resource actions (activate/archive/restore/delete/export, word/chunk/
    phone timeline lifecycle, capability loading).
  - `controllers/media_session_coordinator.dart` — media open, subtitle and
    LLTimeline import, primary-track activation, generated tracks, speech
    enhancements.
  - `controllers/playback_actions_coordinator.dart` — chunk navigation and
    loops, source-loop ranges, occurrence playback with fingerprint
    resolution, vocabulary export/import, finding feedback.
  - Coordinators are context-free; hosts inject runtime hooks once via
    `bind(...)` (api handle, mounted check, dialogs, localization).
- Large layout regions are widgets under `widgets/layout/` (`PlayerStage`
  with ephemeral phone-evidence expansion state, `SidePanel`, `PlaybackBar`),
  and dialog-driven workflows are flow functions under `widgets/flows/`
  (media import, OpenSubtitles search, manual review) plus
  `widgets/settings/settings_flow.dart`.
- `LearningController` stores typed lexical entries, phrase candidates,
  selected lexical details, dictionary lookup, word pronunciation, language
  profile, and diagnosis.
- `SubtitleController` stores typed pronunciation providers, sentence
  pronunciation analyses, and phonetic analyses.
- `BackendEvent` parsing is typed; lexical change events update the typed
  learning cache.
- Timeline models use typed metrics/evidence envelopes.
- Sound analysis models include typed `RhythmFrame` data for audible-structure
  references, provenance-bearing prominence anchors, phrase-scoped nuclei, weak
  groups, compression spans, phrase boundaries, L4 connected-speech refs,
  listening hotspots, and signal-source quality.
- Reference B default connected forms are generated by
  `speech-analysis::connected_speech_rules`; B-matched audio is a
  `teachable_rule`, while C-side reductions beyond B remain `clip_specific`.
- LLTimeline documents can also carry document-level `rhythm_frames` generated
  from the active WordTimeline; Flutter resolves these by sentence before
  falling back to `PhoneTimeline.sound_analysis`.
- Bundled Rust `word_acoustics` analyzes the mono PCM transcription WAV before it
  is deleted and persists `rhythm_word_acoustic_cues`: per-word RMS prominence,
  F0 median/range, pitch prominence and pitch reset. Flutter remains DSP-free;
  Python production artifacts can replace/enrich the same cue contract.
- `AppSettings.soundPatternDisplayMode` selects Rhythm reference A (`citation`),
  B (`connected`), or C (`actual`). Phone-level detail is not a peer mode; it is
  an expandable L4 evidence surface inside C.
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

### Practice Attempt

```text
practice item request -> application::practice -> SQLite practice_items
practice attempt submit -> text evaluation -> SQLite practice_attempts
  -> failed lexical anchors create LexicalObservation
  -> optional ReviewItem
  -> LearningEvent append
```

### Timeline Resources

```text
subtitle track -> word timeline -> rhythm frames / chunk timeline / phone timeline
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
- Persistence and API tests cover the first learning-loop foundation slice:
  practice item/attempt, review item, and learning event persistence.

## Remaining Architecture Debt

1. `main.dart` is still large. Phase 2.18 moved event parsing, core learning
   workflows, and speech-enhancement/timeline refresh out first; remaining
   media/session/resource action wiring can be extracted later.
2. `speech-analysis` still contains several subdomains in one crate. This is
   acceptable until APIs stabilize, but it should not leak public DTO shapes.
3. Route strings still live in the Axum router chain. The parity test is the
   current guardrail; a manifest can be added later if route growth continues.
4. Phase 3.0.1 currently implements the practice/review/event foundation only.
   Corpus search, difficulty caching, learner-profile storage, recording metadata,
   Flutter practice controllers, and dashboard aggregation remain future work.
