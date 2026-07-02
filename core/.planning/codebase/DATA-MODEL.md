# Current Data Model

Last updated: 2026-06-28, Phase 3.0.1.

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

`LearningStatus` is language-agnostic and applies to every lexical granularity:

```text
null
unknown_meaning
known_not_recognized
known_recognized
```

Lexical learning state is split by purpose:

| Table/model | Purpose |
|---|---|
| `lexical_entries` | Current durable user assessment and notes |
| `lexical_status_history` | Status transition audit trail |
| `lexical_occurrences` | Durable source sentence/media snapshot |
| `lexical_observations` | Sentence-specific heard/not-heard result |

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
| `learning_events` | Append-mostly analytics facts for practice/review/listening/status events |

`PracticeAttempt` owns what the user tried and how it was evaluated. It may create
`LexicalObservation` evidence, but it must not silently change global
`LearningStatus`.

`ReviewItem` owns scheduling targets, not lexical identity. `LexicalEntry` remains
the authoritative vocabulary learning asset. Anki export or AnkiConnect should
adapt from `ReviewItem` later rather than define the internal model.

`learning_events` is the intended future source for dashboard aggregation. It is
not a substitute for status history, practice attempts, or review attempts.

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

review_items
  └── review_attempts

learning_events
  └── session_id nullable, ON DELETE SET NULL
```

Losing or deleting media/subtitle rows preserves lexical occurrence snapshots and
status history. Media availability changes should archive replaceable content;
permanent lexical deletion is an explicit learning-asset operation.

## Timeline Resources

Word, chunk, and phone timelines share the same resource lifecycle:

```text
candidate -> active -> archived
```

SQLite enforces one active resource per track/resource kind with partial unique
indexes. `created_by`, parent IDs, publication markers, and model/provider
metadata are provenance/revision metadata, not lifecycle state.

`metrics_json` and `evidence_json` remain object-shaped JSON at the API/storage
boundary, but the Rust and Flutter models now wrap them in typed envelopes:

| Field | Domain type | Notes |
|---|---|---|
| `WordTimeline.metrics_json` | `TimelineMetrics` | lifecycle/provenance metrics |
| `ChunkTimeline.metrics_json` | `TimelineMetrics` | partitioner and parent timing metrics |
| `PhoneTimeline.metrics_json` | `TimelineMetrics` | phonetic analysis provenance metrics |
| `ChunkTimelineChunk.evidence_json` | `ChunkEvidence` | boundary/evidence payload |
| `PhoneTimeline.sound_analysis.rhythm_frame` | `RhythmFrame` | audible-structure map: A/B/C references, prominence anchors, phrase-scoped nuclei, weak groups, compression spans, phrase boundaries, connected-speech refs, hotspots, and signal-source quality |
| `LLTimelineDocument.rhythm_frames[].rhythm_frame` | `RhythmFrame` | first-class WordTimeline-derived rhythm resource keyed by sentence for WordTimeline-only imports/exports |

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
- Subtitle replacement deletes and inserts its sentence timeline in one
  transaction.
- Unique constraints enforce idempotent media, subtitle, lexical, dictionary
  cache, active timeline identities, and learning-loop IDs.
- Vocabulary export/import is version 5 and contains only lexical assets plus
  phonetic finding feedback.
- SQLite schema version is 16 after the destructive lexical schema repair.
