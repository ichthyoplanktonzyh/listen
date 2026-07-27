# LLPlayerNext System Architecture

Last updated: 2026-07-26. Reflects Phase 3.19.2 backend runtime hardening.

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
        +--> local-runtime
        |     local process/download/filesystem/network job and resource lifecycles
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
domain <- core engines <- application <- local-runtime / api-http / persistence adapters
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
- Phase 3.15 adds Writing-specific feedback facts around the semantic task core:
  provider findings bind one exact learner revision hash, while accept/reject
  dispositions append separately and acceptance must cite a new immutable
  attempt that preserves the reviewed text and adds a later typed revision.
  Provider suggestions never become authoritative learner text by mutation.
- Phase 3.16 adds the independent `UserSentencePattern` aggregate: user-owned
  template identity, immutable source snapshot and versions, plus channel-specific
  completed attempts. It is not a construction, corpus projection or embedding hit.

### `application`

- `AppServices` is composition-only: focused module accessors plus construction
  builders, with no cross-domain use-case methods. `MediaAnalysisUseCases`,
  `LexicalLearningUseCases`, and `PracticeUseCases` own the three broad caller
  clusters; `SemanticUseCases`, `PersonalExpressionUseCases`, `LlmProviderUseCases`, `LearnerProfileUseCases`,
  `DictionaryUseCases`, `RecordingUseCases`, and `PronunciationUseCases` remain
  narrow specialist modules. Each module holds only its required ports or an
  explicit collaborating module.
- Repository boundaries are split by aggregate/resource:
  - `MediaRepository`
  - `SubtitleTrackRepository`
  - `PronunciationRepository`
  - `WordTimelineRepository`, `ChunkTimelineRepository`,
    `SenseGroupRepository`, `PhoneTimelineRepository`
  - `LLTimelineResourceRepository`
  - `LexicalCapabilityRepository`, `LexicalEntryRepository`,
    `LearningObservationRepository`, `LexicalContentRepository`,
    `VocabularyAssetRepository`
  - `PracticeRepository`
  - `ReviewQueueRepository`, `HuntingRepository`,
    `RecognitionUpgradeRepository`
  - `LearningEventRepository`
  - `RecordingRepository`
  - `ProductionCorpusRepository`
  - `PersonalExpressionRepository`
  - transcription, phonetic analysis, dictionary cache, playback progress
- Application-owned DTOs sit in `application::dto`; algorithm crate structs are
  mapped at the boundary instead of re-exported.
- `PersonalExpressionUseCases` owns explicit create/revise/delete, immutable
  version/attempt history, and typed export. It has no observation, capability,
  projection, proposal or confirmation repository dependency.
- `RealtimeConversationUseCases` owns provider profiles and durable session/turn
  facts. Local sequence is the ordering authority; the production-corpus collaborator
  accepts only finalized local learner turns. Session/turn history queries are read-only.
- `ProjectionReviewUseCases` is the Phase 3.17 authority boundary. Channel-local
  algorithms read immutable observations and append versioned proposals; one
  repository transaction is the only evidence path that can append confirmation,
  update a projection and append capability history. It never mutates overrides.
  Cross-modal gaps are read models and keep unassessed distinct from failure.
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
- Cross-modal review candidates cite the exact observation/source reference plus
  an immutable text snapshot. Missing media disables navigation but does not
  manufacture a failure or erase the review explanation.
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
- `SyntacticConsumerOrchestrator` probes once and analyzes a subtitle track in
  one batch, then finalises each sentence independently. B, SenseGroup, and the
  dependency matcher share the same per-sentence artifact; a bad sentence
  falls back without invalidating its siblings.

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
- Root `lib.rs` is the small composition root for public health, protected-route
  merge, auth, request diagnostics and state construction. Protected endpoints
  live in coherent media-analysis, learning, generative and provider/event route
  groups under `routes/router.rs`.
- `ApplicationExecutor` is the only async-transport to synchronous-application
  seam. It drives repository-bearing use cases on Tokio's blocking pool, including
  mixed provider futures whose synchronous repository sections must not occupy an
  async worker. Route modules cannot access `AppServices` or dispatch their own
  `spawn_blocking`.
- `ApiState` groups change by lifecycle: `AnalysisRuntime`, `LanguageRuntime`,
  `GenerativeRuntime` and `ApiInfrastructure`; use-case ownership remains in
  `AppServices`.
- JSON diagnostics emit one completion record per request with method, matched
  route, status, duration and correlation ID. Generic failures retain internal
  diagnostics while returning path/SQL/secret-free public messages.
- SSE is a notification channel, not a durable log. Lag is logged, lost
  notifications are skipped, retained events continue, and authoritative GET
  endpoints remain the recovery source.
- OpenAPI parity is tested bidirectionally: implemented `/v1` routes and
  documented OpenAPI paths must match.
- Route modules own only HTTP extraction, response/error mapping and event
  adaptation. Lexical entries, downloadable learning resources, and subtitle
  search use explicitly named route modules; milestone-coded `m18.rs` no longer
  exists.

### `persistence-sqlite`

- One bundled-rusqlite connection preserves transaction locality and deterministic
  synchronous application tests. HTTP concurrency is provided above the adapter
  by `ApplicationExecutor`, not by splitting transactions across a pool.
- File databases use a five-second busy timeout, migration-before-use and a
  pre-migration backup. The single-connection design retains SQLite's default
  journal and synchronous durability modes; WAL would not add useful intra-process
  writer concurrency here and is therefore not enabled implicitly.
- The connection uses a non-poisoning mutex. A panic cannot permanently turn all
  later repository calls into mutex-poison panics; ordinary SQLite failures still
  return typed repository errors.

### `local-runtime`

- Owns transcription, phonetic-analysis, speech-batch and sound-line job
  lifecycles plus syntax capability, downloadable learning resources and
  subtitle provider coordination.
- Realtime learner audio is segmented by the macOS audio bridge per provider VAD
  boundary with a short PCM pre-roll. Each learner turn enters the existing recording
  transcription runtime independently; the whole-session WAV is cleanup-only.
- `ProcessRunner` and `ArtifactDownloader` are real seams with production and
  deterministic fake adapters. Runtime modules do not depend on Axum, HTTP
  status codes or `ApiState`.
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
- Schema v38 adds append-only `writing_feedback_findings` and
  `writing_finding_dispositions`; both retain JSON facts plus query columns and
  have database triggers forbidding update/delete. `writing_drafts` is the
  explicitly mutable crash-recovery projection and is never an evidence input.
- Schema v39 adds the rebuildable personal production corpus. Writing attempts
  remain authoritative; `ProductionCorpusUseCases` derives one response document
  plus lemma-keyed token spans, refreshes one rubric best-effort after attempt
  creation, and atomically replaces the full projection on reindex. Assistance
  values are factual provenance, not autonomous/non-autonomous judgments.
- Phase 3.15.6 adds no table or writer. `ProductionCorpusUseCases` joins the v39
  projection with receptive capability/observation/recognition facts, asks the
  installed lexical provider for an optional BNC rank, and returns a top-K
  `ProductionGapReview`. Ranking and empty/starter/ready degradation stay in
  application; SQLite returns raw aggregate facts and Flutter only presents them.
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

### Optional syntax capability (Phase 3.9.3)

- `SyntaxCapabilityManager` in `local-runtime` owns a filesystem-backed seven-state lifecycle,
  staging install, delivery validation and cache deletion. It does not enter application/domain authority.
- spaCy runs behind one lazy resident JSONL sidecar. Probe and analyze serialize through the same process;
  the adapter releases it after idle, stops it on disable/uninstall and restarts once after a crash.
- `/v1/subtitles/{track}/syntax-analysis` performs one whole-track batch with per-sentence validation and
  a single-flight, rebuildable cache. Fingerprints bind subtitle/token/language/profile and complete delivery
  identity; stale results are observable and never promoted to learning evidence.
- Flutter settings own the explicit install lifecycle. Ready capability plus an active uncached track triggers
  non-blocking background analysis; absent capability produces no prompt and leaves all fallback paths intact.

### Flutter Desktop

- Vocabulary details opt into the personal production read model. The client
  queries the open lexical form, shows occurrence count and deduplicated response
  documents, and opens the authoritative semantic attempt/revision chain.
  Loading, honest zero-result, and projection-unavailable states stay distinct.

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

### Content Fit v3

```text
subtitle + active Word/Chunk/SenseGroup resources
  + word/phrase lexical capability profile
  + syntax metrics persisted by validated sense-group generation
  -> ContentFitFeatureSnapshot
  -> weighted meaning/sound scores + per-signal contributions
  -> FeatureCoverage (explicit missing evidence)
  -> fingerprinted SQLite ContentDifficultyProfile cache

comprehension reports + scored practice calibration
  -> online one-band correction
  -> /v1/content-fit/calibration-samples (label kept out of prediction)
  -> domain content_fit_calibrate threshold search + frozen-v2 comparison
```

Replay and dictionary-lookup features remain absent until those actions carry
an authoritative media identity; unrelated learning events are not proxies.
See ADR 0030.

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

### Shared Syntactic Analysis (Phases 3.9.1–3.9.2)

```text
SubtitleSentence + SubtitleToken snapshot
  -> SyntacticAnalysisProvider draft
  -> application identity + domain validator
  -> validated rebuildable artifact + separate provider qualification gate
       -> Reference B / syntax-aware SenseGroup / dependency matcher
provider missing, unqualified, or artifact not activatable
  -> existing conservative B + punctuation_length_rule_v1
```

Phase 3.9.2 exposes this composition through
`POST /v1/subtitles/{track_id}/syntactic-consumers`. Phase 3.9.3 replaces the
developer environment-variable activation with an App-managed optional install
under Application Support plus `/v1/syntax/capability/*` lifecycle routes;
absent or disabled capability never starts Python.
Qualification is per consumer query: spaCy artifacts, B going-to/used-to/have-to,
SenseGroup, and matcher are activated, while B want-to stays on its exact text
fallback because basic dependencies do not resolve its wh ambiguity reliably.

The syntactic artifact is not a learning asset,
does not replace ChunkTimeline, and cannot supply audio-backed Reference C.
Phase 3.9.3 may persist it only in a deletable fingerprint cache; it never gains
SQLite, learning-evidence, or canonical identity authority.
Syntax-aware SenseGroup is a distinct `syntax-aware-sense-group/v1` analysis
run: dependency subtrees propose boundaries/head/NP-PP-clause labels, while
punctuation, protected phrases, min/max words and target teaching granularity
remain authoritative. Rule and syntax runs coexist under the existing lifecycle.
The dependency matcher is likewise provider-neutral and returns only rebuildable
subtitle-span candidates with matcher/artifact provenance and token bindings. It
has no Construction canonical ID, occurrence ID, capability projection, or
persistence authority; a later curated Construction layer must review and link
any candidate.

### LLTimeline Import/Export

```text
.lltimeline.json -> api-http -> application validation/fingerprint handling
  -> persisted LLTimeline metadata/artifacts + generated timeline resources
```

### Local-first Speech Synthesis (Phase 3.15.9)

```text
dictionary / personal corpus / Writing surface
  -> Flutter AuxiliaryAudioController (single auxiliary decoder + focus)
  -> /v1/speech-synthesis
  -> local-runtime SpeechSynthesisManager
       -> application SpeechSynthesisProvider port
       -> macOS system speech adapter (/usr/bin/say)
       -> provider/version/voice/language/rate/text keyed rebuildable cache
```

The manager owns validation, voice selection, single-flight synthesis, atomic
file publication, cache statistics, and clearing. It has no learning repository:
synthetic audio cannot become an attempt, observation, evidence, projection,
review item, production-corpus row, or authoritative learning asset. Dictionary
provider audio and TTS share playback/resource lifecycle, while each product
scene keeps its own surface. Real dictionary audio and real media slices remain
preferred; online providers require a future explicit privacy/credential/cost
surface before entering production composition.

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
# Phase 3.15.8 semantic embedding delta (2026-07-16)

- `application::SemanticEmbeddingUseCases` is the deep module for capability, atomic rebuild, semantic
  search, and additive gap enrichment. HTTP/Dart/UI never compute cosine or infer stale state.
- `application::EmbeddingProvider` is the narrow provider port: descriptor/status plus batched
  `embed(purpose, texts)`. `embedding-provider` hides FastEmbed/ONNX/HF cache and OpenAI-compatible JSON.
- `persistence-sqlite::SemanticEmbeddingIndexRepository` stores only disposable vectors keyed by source
  identity and exact model fingerprint. Media/production repositories remain source owners.
- Current vocabulary-book dialog is one consumer surface, not a domain anchor; future conversation,
  corpus, or review surfaces may reuse the same module without inheriting this layout.
