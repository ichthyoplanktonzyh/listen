# M1 Data Model

All persisted time values are non-negative integer milliseconds. All IDs are
opaque lowercase SHA-256 strings generated from a namespace and stable
fingerprint. IDs never contain database row numbers or player-library values.

## Identity Strategy

| Record | Stable identity |
|---|---|
| Media | `sha256("media:" + content fingerprint)` |
| Subtitle track | Track fingerprint, unique across imports |
| Subtitle sentence | Deterministic track/cue identity supplied by subtitle core |
| Word profile | `sha256("word-profile:" + language + ":" + normalized lemma)` |
| Word observation | Profile, sentence, and creation time; observations are append-only |
| Word occurrence (M1.5) | Profile and durable source snapshot; live links are optional |
| Word status history (M1.5) | Profile, change time, and ordered status transition |
| Dictionary cache entry | Language, normalized lemma, and provider |

Schema v5 adds nullable user definition and personal note fields to each word
profile. Their independent learning-content timestamp prevents backup merges
from coupling personal edits to status changes.

Media path is mutable metadata, not identity. Registering the same fingerprint
updates its path and metadata while retaining its ID and creation timestamp.
Language codes are lowercase ASCII BCP-47-like values. Lemmas are trimmed and
lowercased for identity; the original and display forms remain available.

## Learning Semantics

`WordProfile.status` is the user's current global assessment of a word in one
language. A `WordObservation` is an append-only result for that word in one
specific subtitle sentence. Updating a global profile never rewrites historical
observations, and observations do not silently change the global status.

Milestone 1.5 makes user selection the authoritative source of global status.
Historical observations may remain append-only, but diagnosis reads only the
latest effective observation for a profile and sentence and supports clearing
that effective value.

The durable asset priority is:

```text
word profile and status history
  > source sentence snapshot
  > live sentence and media relationship
  > replaceable media file
```

When the user deliberately sets a status, a `word_occurrence` captures the
original form, full sentence text, media title, time range, and encounter
timestamps. It may also link to the current media and sentence for return to
playback. A `word_status_history` row records the transition and optional source
occurrence in the same transaction.

## Relationships And Deletion

```text
media_items
  ├── playback_progress (cascade)
  └── subtitle_tracks (cascade)
        └── subtitle_sentences (cascade)
              └── word_observations (cascade)

word_profiles
  └── word_observations (cascade)
```

Deleting a media record removes its progress, imported subtitle timeline, and
sentence observations. Deleting a word profile removes its observations.
There is no delete use case in M1; this documents the schema behavior before
such a use case is exposed.

Milestone 1.5 must migrate vocabulary learning assets away from this cascade:

```text
word_profiles
  ├── word_status_history (cascade only when explicitly deleting the profile)
  └── word_occurrences
        ├── media_id nullable, ON DELETE SET NULL
        └── sentence_id nullable, ON DELETE SET NULL
```

Deleting or losing media and subtitle records preserves occurrence snapshots
and status history. Default cleanup archives replaceable content; permanent
deletion of vocabulary assets requires an explicit user action.

## Transactions, Indexes, And Migration

- Every migration runs in a transaction and advances `PRAGMA user_version`.
- Existing databases are copied to `<database>.pre-migration.bak` before an
  upgrade. Manual recovery is replacing the database with that copy while the
  service is stopped.
- Subtitle track replacement deletes and inserts its sentence timeline in one
  transaction.
- Unique constraints enforce idempotent media, subtitle, word-profile, and
  dictionary-cache identities.
- Timeline and observation indexes support ordered subtitle reads and later
  diagnosis queries.

Milestone 1.6 schema version is `5`. Migration tests cover historical versions
1 through 4. Version 5 adds durable user definitions and personal notes.
