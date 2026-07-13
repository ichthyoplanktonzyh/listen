# LLPlayerNext System Architecture

Last updated: 2026-07-13. Reflects Phase 3.9.1 provider-neutral syntactic contract.

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
        +--> syntactic-provider          # isolated Python JSONL syntax adapters
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
- Phase 3.9.1 adds a rebuildable `SyntacticAnalysis` artifact contract with
  provider/runtime/model provenance, Unicode-scalar char spans, explicit
  parser-token ↔ SubtitleToken many-to-many alignment, UD-compatible fields,
  tree validation, coverage gating, and provider/model/config-isolated identity.

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
  - `RecordingRepository`
  - transcription, phonetic analysis, dictionary cache, playback progress
- Application-owned DTOs sit in `application::dto`; algorithm crate structs are
  mapped at the boundary instead of re-exported.
- Learning assets use `LexicalEntry + LexicalUnit` as the authoritative model.
- Schema v22 persists the Phase 3.4.1 four-channel capability profile with
  evidence/projection/override separation under ADR 0015. The rollout is
  additive; old `LearningStatus` remains a physical compatibility field until
  application, API, diagnosis and Flutter consumers switch.
- Practice services can create practice sessions/items, evaluate text attempts,
  persist `PracticeAttempt`, write failed lexical anchors as `LexicalObservation`,
  optionally create `ReviewItem`, append `LearningEvent`, complete intensive
  sessions, and derive session summaries from events/attempts/review items.
- Due-review queries derive an application-owned `ReviewCard` read model from
  durable `ReviewItem` source/anchors. Card kind and cue/answer presentation are
  not persisted, so historical review rows remain compatible as card UX evolves.
- Recognition-upgrade services deduplicate successful practice/review/context
  observations by sentence (or media when no sentence exists), create a pending
  suggestion at five contexts, and keep status mutation behind explicit user
  confirmation. Rejection records a 30-day cooldown instead of mutating the
  lexical entry.
- Extensive-listening services capture soft-interrupt moments as
  `ListeningInboxItem`, list active/archived Inbox items, process them into
  review items / micro-intensive practice items / favorite or dismissed
  archival outcomes, and append durable listening events.
- `SyntacticAnalysisProvider` returns content/provenance drafts only. Application
  assigns artifact identity and validates the draft against the exact source
  sentence/token snapshot before a consumer may activate syntax-gated behavior.

### `syntactic-provider`

- Owns the provider-neutral process adapter for research Stanza and spaCy
  candidates; neither Python runtime nor model is linked into the consumer app.
- Uses a versioned one-request/one-response JSONL boundary with stdout reserved
  for protocol data and stderr reserved for diagnostics.
- Reports runtime/model/language capability honestly and maps closed failure
  classes without changing the existing Reference B or SenseGroup fallback.
- Produces application drafts only. It cannot populate Reference C, replace
  `ChunkTimeline`, or mint Construction canonical identity.

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
  - `/v1/practice/sessions/{id}/summary`
  - `/v1/practice/sessions/{id}/complete`
  - `/v1/practice/items`
  - `/v1/practice/attempts`
  - `/v1/practice/attempts/{id}`
  - `/v1/practice/stuck-points/mark`
  - `/v1/practice/stuck-points/skip`
  - `/v1/practice/stuck-points/close`
  - `/v1/practice/diagnosis-viewed`
  - `/v1/listening-inbox/items`
  - `/v1/listening-inbox/items/{id}/process`
  - `/v1/review/items`
  - `/v1/review/items/{id}`
- Phase 3.8 recording/shadowing foundation routes:
  - `/v1/recordings`
  - `/v1/recordings/{id}`
  - `/v1/practice/shadowing-attempts`

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
- Schema v18 adds `listening_inbox_items`, a queryable projection of泛听 soft
  interrupts and整理 outcomes. The durable event stream remains the analytics
  source; the table exists so UI does not reconstruct Inbox state from raw
  events on every render.
- Schema v19 adds `review_schedules`, the replaceable current-due projection for
  active review items.
- Schema v20 adds `hunting_candidates`, a queryable handoff pool for repeated
  lexical review failures. It preserves source snapshots and failure counts for
  Phase 3.7 without treating the pool as authoritative learning status.
- Schema v21 adds `recognition_evidence` and `upgrade_suggestions`. Evidence is
  deduplicated by lexical entry + context key; suggestions preserve pending,
  accepted, rejected, and obsolete history independently of lexical status
  history. Accepted suggestions still write the authoritative lexical status
  through `LearningAssetRepository`.
- Schema v32 adds `hunting_targets`, the learner-confirmed listening target asset.
  It is deliberately separate from v20 `hunting_candidates`: repeated review
  failures remain suggestions until an explicit user action promotes one, and
  at most five targets may be active through the application boundary.
- Schema v33 adds `recording_assets`. Audio stays in a local file while SQLite
  persists transcription-ready format/integrity metadata and durable prompt/source
  snapshots. Media and practice-attempt references use `ON DELETE SET NULL`.
- Learning-loop persistence stores JSON snapshots plus query columns for kind,
  status, subject, result, and timestamps. Corpus and recording persistence are
  implemented; learner-profile persistence remains future work.

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
| `connected_speech_rules` | Reference B prediction with explicit `text_heuristic` / `syntax_model` provenance; valid syntax is additionally gated by an external provider qualification decision, and missing/unqualified syntax is exact fallback |
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
- `ExtensiveListeningController` stores the active extensive session, active
  Listening Inbox items, and soft-interrupt/process busy/error state. It is
  separate from `PracticeController`; hard interrupts compose playback pause,
  diagnosis opening, and optional Inbox capture without changing the intensive
  practice state machine.
- `HuntingController` owns learner-confirmed hunting targets and review-failure
  candidates through `Store<HuntingState>`. The listening dictionary only hosts
  the toolbar/detail actions and panel; it does not treat candidates as active
  targets until the controller completes an explicit promotion request.
- `HuntingSessionController` is transient per extensive-listening session. It
  consumes media-scoped corpus matches from the backend and the local player
  position stream, enforcing a five-prompt total budget and two prompts per
  target. Priming/check presentation never pauses playback. Before completion,
  its counters are copied into the extensive-listening completion request; media
  switches and successful session completion then reset it completely.
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

### Intensive Practice / Extensive Completion

```text
practice attempts -> SQLite practice_attempts -> optional ReviewItem + LearningEvent
Flutter floating practice window is transient and closes without completing a session
complete extensive session -> PracticeSession.ended_at_ms
  + LearningEvent(listening_completed with comprehension self-report)
  + optional content-fit calibration feedback
```

### Extensive Listening Inbox

```text
start extensive session -> LearningEvent(listening_started)
soft interrupt -> ListeningInboxItem active projection
  + LearningEvent(listening_inbox_captured)
Inbox process -> ReviewItem / PracticeItem / favorite / dismissed / expired
  + ListeningInboxItem archived projection
  + LearningEvent(listening_inbox_processed)
complete extensive session -> LearningEvent(listening_completed with self report)
```

### Hunting Mode

```text
confirmed hunting targets + current media/track
  -> corpus lemma/FTS lookup -> sentence-linked HuntingOccurrence[]
  -> local position-driven priming/check with 5 total / 2 per-target budget
  -> yes/no: create_lexical_observation -> channelized evidence/projection
  -> not noticed: HuntingCheckAnswered event only
  -> extensive completion: optional validated counters -> ListeningCompleted payload
```

### Shadowing Recording

```text
Flutter microphone capture -> local audio file + RecordingAsset metadata
  -> /v1/recordings -> SQLite recording_assets
complete shadowing -> PracticeAttempt(result=completed, score=null)
  -> PracticeCompleted event only (no speaking observation/review/content-fit)
```

### Timeline Resources

```text
subtitle track -> word timeline -> rhythm frames / chunk timeline / phone timeline
  -> SpeechEnhancementWorkflowController -> Flutter timeline/pronunciation model
```

### Shared Syntactic Analysis (Phase 3.9.1)

```text
SubtitleSentence + SubtitleToken snapshot
  -> SyntacticAnalysisProvider draft
  -> application identity + domain validator
  -> validated rebuildable artifact + separate provider qualification gate
       -> Reference B / syntax-aware SenseGroup / dependency matcher
provider missing, unqualified, or artifact not activatable
  -> existing conservative B + punctuation_length_rule_v1
```

The syntactic artifact is not persisted by Slice 1, is not a learning asset,
does not replace ChunkTimeline, and cannot supply audio-backed Reference C.
Syntax-aware SenseGroup is a distinct `syntax-aware-sense-group/v1` analysis
run: dependency subtrees propose boundaries/head/NP-PP-clause labels, while
punctuation, protected phrases, min/max words and target teaching granularity
remain authoritative. Rule and syntax runs coexist under the existing lifecycle.

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
