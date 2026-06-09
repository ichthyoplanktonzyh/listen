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
| Dictionary cache entry | Language, normalized lemma, and provider |

Media path is mutable metadata, not identity. Registering the same fingerprint
updates its path and metadata while retaining its ID and creation timestamp.
Language codes are lowercase ASCII BCP-47-like values. Lemmas are trimmed and
lowercased for identity; the original and display forms remain available.

## Learning Semantics

`WordProfile.status` is the user's current global assessment of a word in one
language. A `WordObservation` is an append-only result for that word in one
specific subtitle sentence. Updating a global profile never rewrites historical
observations, and observations do not silently change the global status.

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

M1 schema version is `2`. Migration tests cover a new database and a historical
version-1 database.
