# Current Data Model

Last updated: 2026-06-27, Phase 2.18.

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
| Lexical observation | Lexical entry + sentence + original form |
| Dictionary cache entry | Language + normalized form + provider |
| Timeline resource | Resource namespace + track/media/config fingerprint |

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

Updating a global status never rewrites historical observations. Diagnosis reads
current lexical entries plus the latest relevant lexical observation for the
sentence.

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

Non-object metrics/evidence input is normalized to an empty object.

## Transactions And Migration

- Every migration runs in a transaction and advances `PRAGMA user_version`.
- Existing databases are copied to `<database>.pre-migration.bak` before an
  upgrade, but Phase 2.18 does not preserve historical schema compatibility.
- Subtitle replacement deletes and inserts its sentence timeline in one
  transaction.
- Unique constraints enforce idempotent media, subtitle, lexical, dictionary
  cache, and active timeline identities.
- Vocabulary export/import is version 5 and contains only lexical assets plus
  phonetic finding feedback.
