# Current Data Model

Last updated: 2026-07-22, Phase 3.19.1 realtime conversation correction.

All persisted time values are non-negative integer milliseconds. Public IDs are
opaque SHA-256 strings generated from a namespace and stable fingerprint; they
do not contain database row numbers or player-library identifiers.

## Identity Strategy

| Record | Stable identity |
|---|---|
| Media | `sha256("media:" + content_fingerprint)` |
| Subtitle track | Track fingerprint, unique across imports |
| Subtitle sentence | Deterministic track/cue identity from subtitle-core |
| Lexical entry | `language + granularity + normalization + normalized_key` |
| Lexical occurrence | Lexical entry + durable source snapshot key |
| Lexical observation | Lexical entry + sentence (deterministic id via `domain::lexical_observation_id`; latest result wins) |
| Dictionary cache entry | Language + normalized form + provider |
| Timeline resource | Resource namespace + track/media/config fingerprint |
| Practice session | `sha256("practice-session:" + mode/media/track/timestamp)` |
| Practice item | `sha256("practice-item:" + kind/prompt/expected/timestamp)` |
| Practice attempt | `sha256("practice-attempt:" + item/input/timestamp)` |
| Review item | `sha256("review-item:" + source/prompt/timestamp)` |
| Learning event | `sha256("learning-event:" + kind/subject/timestamp)` |
| Listening Inbox item | `sha256("listening-inbox-item:" + session/target/timestamp)` |
| Recording asset | `sha256("recording-asset:" + audio SHA-256/target/source start/timestamp)` |
| User sentence pattern | Server-minted opaque ID at explicit user save; independent of source/canonical construction |
| User sentence pattern version | Pattern + append-only version number + creation fingerprint |
| Personal expression attempt | Pattern + immutable version + completed learner response/time |
| Writing feedback finding | Attempt + learner revision/hash + project category/span/message + provider/version |
| Writing finding disposition | Finding + accept/reject + resulting immutable attempt/revision + timestamp |
| Realtime conversation session | Local opaque session ID; provider lifecycle envelope only |
| Realtime conversation turn | Session + local monotonic sequence + role; provider item ID is correlation metadata |

Media path is mutable metadata, not identity. Registering the same media
fingerprint updates path/title metadata while retaining the media ID.

## Learning Assets

The authoritative learning asset is `LexicalEntry`.

`LexicalEntry.unit` is a `LexicalUnit`:

```text
language
  + granularity       # word, phrase, char, morpheme, ...
  + normalization     # provider/profile-specific normalization name
  + normalized_key    # opaque normalized key
```

Runtime through schema v21 still uses the language-agnostic `LearningStatus`:

```text
null
unknown_meaning
known_not_recognized
known_recognized
```

Phase 3.4.1 is the accepted transition to reading/listening/speaking/writing
capability assessments (`unassessed / not_acquired / acquired`) with evidence,
system projection, and user override kept separate. ADR 0015 is authoritative
for the target model. The domain contract, conservative legacy conversion and
schema v22 persistence now exist. Application/API/diagnosis/Flutter still use
the legacy status path, so the following old and transitional tables coexist
until the later authority-switch slice.

Lexical learning state is split by purpose:

| Table/model | Purpose |
|---|---|
| `lexical_entries` | Legacy current assessment compatibility field and durable notes |
| `lexical_status_history` | Status transition audit trail |
| `lexical_capability_states` | Per entry/sense/capability projection and optional user override |
| `lexical_capability_history` | Before/after capability state audit trail, including override clear |
| `lexical_occurrences` | Durable source sentence/media snapshot |
| `lexical_observations` | Sentence-specific heard/not-heard result |
| `production_corpus_documents` | Rebuildable final learner-response documents with attempt/rubric/source and factual assistance provenance |
| `production_corpus_entries` | Lemma-keyed token occurrences with surface form and Unicode-scalar span into one document |
| `production_corpus_documents_fts` | Trigger-maintained phrase-search companion over document text |

Updating a global status never rewrites historical observations. An observation
is the current per-(entry, sentence) verdict, not an append-only log: its id is
deterministic on those two axes and a newer observation replaces the stored
result under the same id, so durable references from practice attempts never
dangle. Diagnosis reads current lexical entries plus the latest relevant
lexical observation for the sentence; token forms are resolved to entry keys
through the language's normalization provider before matching, so inflected
forms ("went") classify against their lemma entry ("go").

## Learning Loop Foundation

Phase 3.0.1 introduces durable learning-behavior facts without replacing lexical
assets:

| Table/model | Purpose |
|---|---|
| `practice_sessions` | A study mode/session envelope such as intensive, extensive, review, or specialty |
| `practice_items` | A cloze, dictation, subtitle-fade, or shadowing prompt snapshot anchored to real content |
| `practice_attempts` | Historical user submission, evaluation, generated observations, and generated review links |
| `review_items` | A schedulable review target pointing to lexical entries, chunks, sentences, practice failures, or future sound cases |
| `review_attempts` | Historical review rating attempts |
| `review_schedules` | Current due projection per review item; v1 is explicitly `heuristic_proxy` and replaceable |
| `hunting_candidates` | Queryable lexical targets produced by failed reviews for later hunting-list consumption |
| `hunting_targets` | Learner-confirmed listening targets; independent of candidate generation and capped at five active targets |
| `recognition_evidence` | Successful listening-recognition evidence, unique per lexical entry + sentence/media context |
| `upgrade_suggestions` | Pending/resolved `known_not_recognized -> known_recognized` proposals with evidence snapshot and rejection cooldown |
| `learning_events` | Append-mostly analytics facts for practice/review/listening/status/stuck-point events |
| `content_difficulty_profiles` | Disposable fingerprinted Content Fit cache; v3 JSON embeds the material/learner feature snapshot, meaning/sound contributions, score, and explicit evidence coverage |
| `content_fit_calibrations` | Durable per-media comprehension/practice counters; survives profile recomputation and supplies online correction plus offline observed labels |
| `listening_inbox_items` | Queryable projection for extensive-listening soft interrupts, snapshots, expiry, and整理 outcomes |
| `recording_assets` | Local recording path plus transcription-ready audio metadata and durable target/source snapshots |
| `writing_feedback_findings` | Append-only provider/manual suggestions bound to one exact typed learner revision |
| `writing_finding_dispositions` | Append-only learner accept/reject facts; acceptance cites a later typed revision |
| `writing_drafts` | Mutable non-evidence scratch projection keyed by rubric; deleted after immutable submission |
| `user_sentence_patterns` | Durable user-owned asset with current searchable name/text and immutable source snapshot JSON |
| `user_sentence_pattern_versions` | Append-only user edits; old template text/slots/system ref remain unchanged |
| `personal_expression_attempts` | Immutable completed speaking or writing use of one exact pattern version |

`PracticeAttempt` owns what the user tried and how it was evaluated. It may create
`LexicalObservation` evidence, but it must not silently change global
`LearningStatus`.

Shadowing uses `PracticeResult::Completed` when a recording finishes without an
objective evaluator. This is an activity fact with `score = null`: it creates no
channelized observation, review item, recognition evidence, or content-fit feedback.

`UserSentencePattern` is a separate durable asset aggregate. Its source media,
track, sentence and semantic candidate IDs are optional navigation hints inside
the source snapshot JSON; no media/subtitle foreign key may cascade an asset.
`system_construction_id` is optional reference metadata on a version and never
replaces user-owned `pattern_text`.

Personal-expression attempts preserve the channel, assistance, learner response,
self-assessment and exact immutable version. Writing rejects recording/raw-ASR
facts; speaking requires a recording asset. Neither channel writes or implies the
other channel's capability, and these facts do not write learning observations,
projection proposals or confirmation decisions.

`ReviewItem` owns scheduling targets, not lexical identity. `LexicalEntry` remains
the authoritative vocabulary learning asset. Anki export or AnkiConnect should
adapt from `ReviewItem` later rather than define the internal model.

The four audio-first card kinds are not persisted on `review_items`.
`ReviewCard` is an application read model derived from `ReviewItem.source`,
anchors, and `prompt_snapshot`; presentation can evolve without rewriting
historical scheduling data.

Recognition evidence is a durable success fact, not a status write. Its context
key prefers `sentence:<id>` and falls back to `media:<id>`; facts without either
axis do not count toward the v1 threshold. Five distinct contexts produce a
`heuristic_proxy` `UpgradeSuggestion`. Only explicit confirmation updates the
lexical entry and `lexical_status_history`; rejection leaves status unchanged and
sets a 30-day cooldown. `upgrade_suggestions` retains the confirmation/rejection
history even after status history has advanced.

`learning_events` is the intended future source for dashboard aggregation. It is
not a substitute for status history, practice attempts, or review attempts.
Phase 3.2 also uses it for stuck-point facts and familiar-material markers:
`stuck_point_marked`, `stuck_point_skipped`, `diagnosis_viewed`,
`stuck_point_closed`, and `familiar_material_marked`. Stuck-point status is a
read-side derivation from events plus `PracticeAttempt` and `ReviewItem`; there
is no authoritative stuck-point state table in schema v21.

Phase 3.7 adds `hunting_check_answered` as a session-linked event. All three
answers are recorded for session statistics; `not_noticed` deliberately creates
no lexical observation or recognition evidence, while recognized/not-recognized
continue through the existing single observation write path. An extensive
`listening_completed` event may also carry a `hunting_summary` with prompted,
recognized, not-recognized, and not-noticed counts. The application validates
the five-prompt budget and answered-count relationship before ending the session;
these counters are presentation/aggregation facts and do not enter content-fit.

Phase 3.3 adds `ListeningInboxItem` for extensive-listening soft interrupts.
The item stores the target time range, subtitle/context snapshot, active vs
archived status, optional expiry time, and the processing outcome:
`review_item`, `micro_intensive`, `favorite`, `dismissed`, or `expired`.
Capture and processing also append `learning_events`
(`listening_inbox_captured`, `listening_inbox_processed`) so dashboard and fit
calibration can aggregate from durable facts later. The table is intentionally a
read/write projection for Inbox UX; it does not make Inbox a blocking task list.
`complete_listening_session` carries an optional `comprehension_report`
(`understood_all`, `got_the_gist`, `unclear`) for extensive sessions only.

## Deletion Semantics

Vocabulary learning assets outlive replaceable media and subtitles.

```text
media_items
  ├── playback_progress (cascade)
  └── subtitle_tracks (cascade)
        └── subtitle_sentences (cascade)

lexical_entries
  ├── lexical_status_history (cascade only when deleting the entry)
  ├── lexical_observations (cascade only when deleting the entry)
  └── lexical_occurrences
        ├── media_id nullable, ON DELETE SET NULL
        └── sentence_id nullable, ON DELETE SET NULL

practice_sessions
  ├── media_id nullable, ON DELETE SET NULL
  ├── track_id nullable, ON DELETE SET NULL
  └── practice_items
        └── practice_attempts

listening_inbox_items
  ├── session_id nullable, ON DELETE SET NULL
  ├── media_id nullable, ON DELETE SET NULL
  └── track_id nullable, ON DELETE SET NULL

review_items
  ├── review_attempts
  ├── review_schedules (one current due projection per item)
  └── hunting_candidates (failed lexical targets, source snapshots, counts)

lexical_entries (logical reference; no delete cascade)
  ├── recognition_evidence (unique lexical entry + context key)
  ├── upgrade_suggestions (pending/resolved proposal history)
  └── hunting_targets (confirmed listening targets; cascade only on explicit lexical deletion)

learning_events
  └── session_id nullable, ON DELETE SET NULL

recording_assets
  ├── practice_attempt_id nullable, ON DELETE SET NULL
  └── media_id nullable, ON DELETE SET NULL

semantic_task_attempts (authoritative immutable facts)
  └── production_corpus_documents (rebuildable projection; cascade on attempt deletion)
        └── production_corpus_entries (rebuildable lemma occurrences)
```

`ProductionGapReview` is an ephemeral read model over the last two branches. It
has no identity, table, lifecycle, writer, cascade, or export semantics. Absence
from `production_corpus_entries` is only a corpus fact; even a `ready` review does
not become speaking/writing observation or capability projection without the
separate Phase 3.17 confirmation path.

## Realtime Conversation Facts

`realtime_conversation_sessions` stores free (`open_chat`) and topic-anchored
session envelopes. `realtime_conversation_turns` stores every learner and assistant
turn ordered by a local monotonic `sequence`; provider item IDs never define order
or identity. Provider transcripts are live/correlation facts. Only a finalized
learner turn with its own local WAV, recording asset, completed local transcription
job and `LocalLearnerTranscript` is authoritative learner output.

Conversation History reads both roles. The rebuildable Production Corpus projects
only finalized local learner turns, so assistant turns and failed/interrupted
learner turns cannot affect Gap Review. A single learner ASR failure is a turn-level
failure and does not change an otherwise completed session into failed.

Losing or deleting media/subtitle rows preserves lexical occurrence snapshots and
status history. Media availability changes should archive replaceable content;
permanent lexical deletion is an explicit learning-asset operation.

## Timeline Resources

Word, chunk, and phone timelines share the same resource lifecycle:

```text
candidate -> active -> archived
```

`SyntacticAnalysis` is currently an ephemeral, rebuildable analysis artifact,
not a timeline or user asset. Its identity isolates the source text/token
snapshot, language, contract, provider, runtime, model checksum, and profile
configuration. Phase 3.9.1 adds no SQLite row and grants no deletion/cascade or
learning-evidence semantics.

The Phase 3.9.2 HTTP batch returns one independently validated artifact per
source sentence. Reference B evidence, syntax-aware SenseGroup spans, and
dependency matches carry/reference that same artifact ID. The batch is still
ephemeral: no new SQLite authority, cascade, or canonical identity is created.
Invalid/missing sentences contain an explicit fallback reason and no artifact.

Phase 3.9.3 persists only capability lifecycle JSON and rebuildable track-cache JSON in Application Support,
not SQLite. Capability status is `not_installed/downloading/ready/partial/failed/stale/disabled`. Track-cache
identity covers subtitle text and token snapshot, language, analysis profile and the combined provider/runtime/
model/requirements/sidecar delivery checksum. Subtitle or delivery changes therefore expose stale and require
rebuild; uninstall may delete every syntax cache without deleting a user or learning asset.

`SenseGroupAnalysis` retains its existing independent candidate/active/archive
lifecycle. `rule-based-sense-group/v1` and `syntax-aware-sense-group/v1` are
different provider runs rather than in-place upgrades. A syntax-aware run stores
the source syntactic artifact ID/provider descriptor in `metrics_json`, while
`chunk_timeline_dependency=false` makes the non-relationship explicit.

Schema v50 adds `llm_sense_group_sentence_checkpoints`, a rebuildable cache for
successful provider boundary drafts. Its SHA-256 key length-prefixes the
provider-profile scope, local prompt-contract version, and complete immutable
partition request snapshot (language, text, tokens, protected spans and
candidate boundaries). It is not a timeline, learning asset, observation or
capability fact. Cancellation may leave successful sentence checkpoints but
must not create a complete `SenseGroupAnalysis` containing unprocessed
fallbacks; a later batch reads checkpoints and dispatches only missing or
invalid sentences.

`DependencyMatchCandidate` is an ephemeral query result over a validated,
qualified syntactic artifact. Its matcher-local key, subtitle token span and
bindings are diagnostics for a later curated layer; they are not a
`ConstructionId`, canonical key, durable occurrence, capability fact, or user
asset.

SQLite enforces one active resource per track/resource kind with partial unique
indexes. `created_by`, parent IDs, publication markers, and model/provider
metadata are provenance/revision metadata, not lifecycle state.

The partial unique indexes for `word_timeline_runs`, `chunk_timeline_runs`, and
`phone_timeline_runs` are defined as `WHERE status = '"active"'`: the JSON quotes
are intentional because `TimelineResourceStatus` is serde-serialized before
storage. Changing that serialization would silently invalidate the active-run
guard unless the migrations and schema tests are updated together.

`metrics_json` and `evidence_json` remain object-shaped JSON at the API/storage
boundary, but the Rust and Flutter models now wrap them in typed envelopes:

| Field | Domain type | Notes |
|---|---|---|
| `WordTimeline.metrics_json` | `TimelineMetrics` | lifecycle/provenance metrics |
| `ChunkTimeline.metrics_json` | `TimelineMetrics` | partitioner and parent timing metrics |
| `PhoneTimeline.metrics_json` | `TimelineMetrics` | phonetic analysis provenance metrics |
| `SenseGroupAnalysis.metrics_json` | `TimelineMetrics` | optional source syntactic artifact/provider provenance; never a ChunkTimeline parent |
| `ChunkTimelineChunk.evidence_json` | `ChunkEvidence` | boundary/evidence payload |
| `PhoneTimeline.sound_analysis.rhythm_frame` | `RhythmFrame` | audible-structure map: A/B/C references, prominence anchors, phrase-scoped nuclei, weak groups, compression spans, phrase boundaries, connected-speech refs, hotspots, and signal-source quality |
| `LLTimelineDocument.rhythm_frames[].rhythm_frame` | `RhythmFrame` | first-class WordTimeline-derived rhythm resource keyed by sentence for WordTimeline-only imports/exports |

### Word Timing Authority

`word_timeline_runs` is the authoritative word-timing store: it versions complete
WordTimeline resources and uses the active-run lifecycle to select the current
timeline for a subtitle track. The legacy `word_timings` table is a sentence-keyed
fallback cache for older API paths such as `trackWordTimings()`.

Retire `word_timings` only after all consumers read active WordTimeline resources
and the transcription pipeline no longer writes the legacy
`stored_legacy_word_timings` path.

### Rhythm Frame Authority

`LLTimelineDocument.rhythm_frames` is the authoritative document-level rhythm
resource for WordTimeline-first exports/imports.
`PhoneTimeline.sound_analysis.rhythm_frame` is transitional compatibility data
for phone-timeline-backed consumers and older resources.

Retire `PhoneTimeline.sound_analysis.rhythm_frame` only after Flutter consumes
document-level rhythm frames exclusively and phonetic-analysis no longer wraps
rhythm frames inside `SoundAnalysis`. Removing that field is a contract change
and needs its own planned migration.

Non-object metrics/evidence input is normalized to an empty object.
`SoundAnalysis.rhythm_frame` is optional for older PhoneTimeline resources. Active
Phase 2.21 fixtures use the provenance-bearing audible-structure shape rather
than the Phase 2.20 v0 shape, and LLTimeline export can now include
document-level `rhythm_frames` generated directly from the active WordTimeline.
Missing rhythm data should degrade to the existing sound-line/phone evidence UI
or the compact unavailable state in rhythm mode. L1-L3 rhythm structure can be
present even when observed phone evidence coverage is `0.0`; in that case
`RhythmFrame.quality.timing_source = "word_timeline"` and claim provenance comes
from timing/energy cues rather than `phone_segmental`.

`RhythmFrame.references.default_connected` is Reference B. For English it is
generated by `english_connected_speech_rules_v1`: text-side weak forms,
phrase reductions, linking, t/d weakening, assimilation, contraction, and
flapping candidates. `RhythmConnectedSpeechRef.divergence = teachable_rule`
means the actual or predicted connected form matches B; `clip_specific` means
the C-side audio evidence goes beyond B. Pure B predictions use
`signal_sources = ["text_prior"]` and `claim_status = "predicted"`.

Phase 3.9's resumed A/B/C rework adds optional `citation_structure`,
`predicted_structure`, and `actual_structure` to each connected-speech ref.
Each structure contains perceptual groups, IPA, a compact learner cue, and the
written token indices contributing sound to each group. This makes a linking
boundary shift explicit (`pick up`: A `/pɪk | ʌp/`, B `/pɪ.kʌp/`, cue
`pɪ-kʌp`). B is rule-predicted; C is emitted only from audio-backed observed
phones. Timing/prosody may support C grouping but cannot invent a segmental C.

Production LLTimeline artifacts may include `kind = "rhythm_word_acoustic_cues"`
with a flat `payload.cues[]` list keyed by `sentence_id` and `token_index`.
When the artifact `timeline_id` matches the active WordTimeline, application
export converts each cue into `RhythmWordAcousticCue.energy_prominence`; generated
RhythmFrames then include `energy` in prominence provenance.

Reference A citation forms use dictionary stress when available. For OOV English
words, `fallback-v2` supplies deterministic grapheme-to-phoneme phones and a
single primary fallback stress so RhythmFrame text priors do not silently treat
every fallback vowel as equally stressed.

RhythmFrame prominence also has a conservative information-structure text prior:
repeated content words are slightly backgrounded and phrase-final content words
receive a small focus boost. This changes prominence/confidence only within
`TextPrior`; it does not change `claim_status` without measured evidence.

## Desktop Settings

Flutter persists desktop preferences in the versioned `settings-v8.json` file.
Phase 2.21 uses `sound_pattern_display_mode` for the three Rhythm references:

| Value | Meaning |
|---|---|
| `citation` | Reference A: dictionary/citation pronunciation and lexical stress |
| `connected` | Reference B: rule-predicted default connected form and A → B pronunciation change |
| `actual` | Reference C (default): current-audio `RhythmFrame`; phone evidence can expand inside this view |

Legacy v8 values `rhythm` and `phones` both migrate to `actual`. Phone evidence
expansion is ephemeral overlay state, not a fourth persisted Rhythm mode.

## Transactions And Migration

- Every migration runs in a transaction and advances `PRAGMA user_version`.
- Existing databases are copied to `<database>.pre-migration.bak` before an
  upgrade, but Phase 2.18 does not preserve historical schema compatibility.
- Schema v16 destructively rebuilds the lexical/learning-resource tables to the
  authoritative `LexicalEntry + LexicalUnit + LexicalObservation` shape when
  upgrading older local databases; old lexical learning data is intentionally
  discarded under the Phase 2.18 compatibility policy.
- Schema v17 drops the unused `learning_resources` table. Downloadable learning
  resources are served by the API resource manager, not SQLite persistence.
- Schema v18 adds `listening_inbox_items` for extensive-listening Inbox
  capture, expiry, and processing outcomes.
- Subtitle replacement deletes and inserts its sentence timeline in one
  transaction.
- Unique constraints enforce idempotent media, subtitle, lexical, dictionary
  cache, active timeline identities, and learning-loop IDs.
- Vocabulary export/import is currently version 5 and contains only lexical
  assets plus phonetic finding feedback; Phase 3.4.1 will make the next bundle
  version decision before capability data is exported.
- Schema v22 adds `lexical_capability_states` and `lexical_capability_history`,
  backfills v21 legacy status as sourced projection, and deliberately keeps
  `lexical_entries.status` in place for compatibility.
- Schema v28 adds the rebuildable `corpus_occurrences` search projection
  (lemma-keyed word tokens, sentence-level phrase rows, active-chunk-timeline
  chunk rows). It is deliberately separate from durable `lexical_occurrences`
  and never authoritative: subtitle import, track-language changes, chunk
  timeline lifecycle hooks, and the manual `POST /v1/corpus/reindex` rebuild it.
- Schema v29 adds the `corpus_occurrences_fts` FTS5 companion (rowid-mirrored,
  trigger-maintained; `delete_track` clears its rows explicitly before the FK
  cascade so coherence never depends on cascade-fired triggers). Multi-word
  corpus queries are FTS phrase matches over sentence/chunk text; single-word
  queries are exact lemma-key lookups normalized through the same
  user-override → provider → baseline path as lexical entries.
- Schema v32 adds `hunting_targets`. One durable row exists per lexical entry;
  archive/reactivate preserves identity and creation time. Candidate source IDs
  are provenance only: `hunting_candidates` remain unconfirmed until promoted.
- Schema v33 adds `recording_assets`; mutable file paths are metadata, while byte
  length and SHA-256 support later integrity checks and the language/format/sample
  fields are the explicit Phase 3.14 recording-transcription seam.
- Schema v38 adds Writing finding/disposition facts with UPDATE/DELETE triggers.
  A suggestion is never a learner response; only a later typed `AttemptResponse`
  in a new immutable attempt can be cited as the result of acceptance. The same
  migration adds mutable `writing_drafts`, isolated from every evidence writer.
- Schema v39 adds `production_corpus_documents`, `production_corpus_entries`,
  and `production_corpus_documents_fts`. Full response text is stored once per
  document; token rows cite half-open Unicode-scalar spans. Incremental rubric
  replacement and full replacement are transactional. The projection writes no
  lexical observation, capability state/history, or template identity and can
  be deleted/rebuilt from immutable semantic attempts.
- Schema v43 adds `user_sentence_patterns`, append-only
  `user_sentence_pattern_versions`, and immutable `personal_expression_attempts`.
  Only explicit pattern deletion cascades within this aggregate. Source media
  deletion cannot cascade because source identity lives only in the immutable
  JSON snapshot. Attempts are read-only handoff facts for 3.17, not projection
  or proposal rows.
- Schema v44 adds append-only `projection_proposals` and `projection_decisions`.
  A proposal stores channel, algorithm version, conclusion, evidence window,
  exact evidence references and an immutable fallback snapshot. Decisions never
  rewrite proposals. Confirmation atomically updates the existing projection
  slot and `lexical_capability_history`; rejection does not touch capability
  state. Override remains separate and wins in the effective read model.
- Rebuild/backfill for v44 is explicit replay, not migration-time inference:
  v43 capability state/history and observations migrate byte-for-byte, proposal
  tables start empty, and replay appends/supersedes by algorithm/evidence version.
- Schema v45 is an explicit product-subtraction migration: it removes every
  `role_reply` rubric/attempt and directly traceable judgment, review, recording,
  speaking observation and projection proposal. A still-current confirmed Role
  Reply projection is withdrawn while any user override is preserved. The
  retired enum is removed from the domain, so no legacy Role Reply JSON remains
  readable or creatable after migration.
- Review scheduling v1 is recorded as `listen_review_v1_heuristic_proxy`: `again` returns in
  10 minutes, `hard` in one day, and successful intervals grow from 3 to 7 days before doubling.
  The durable attempts remain the evidence history; the schedule row is a replaceable read model.
# Phase 3.15.8 / schema v42 delta (2026-07-16)

- `semantic_embedding_index` is a rebuildable read model: `(model_fingerprint, source_kind, source_id)`
  primary key, language/channel filters, source-text SHA-256, dimension, float32 little-endian BLOB, and
  `indexed_at_ms`.
- The table contains no authoritative text, attempt, learning observation/evidence, capability/proposal,
  review, or portable asset identity. Full delete/rebuild is always valid.
- A vector is readable only when descriptor fingerprint, dimension, source identity, and current source
  text hash match. Model/runtime/purpose/index changes and source edits are stale, never migrated in place.
- `production_lexeme` rows are distinct read sources derived from production entries and scoped by
  language/channel. They enrich an existing gap target but do not create one.
