# Milestone 1.5: Vocabulary Learning Assets

> Status: completed in version 0.3.0 on 2026-06-10.

## Objective

Make the variable-state vocabulary collection the product's primary durable
asset. User-selected status is authoritative. Media and subtitle files improve
the experience, but their absence must not destroy learning records.

## Asset Priority

```text
vocabulary state and history
  > source sentence snapshots
  > live subtitle and media relationships
  > replaceable media files
```

## In Scope

- Dynamic vocabulary books for `UnknownMeaning`, `KnownNotRecognized`, and
  `KnownRecognized`.
- Status changes that move a profile between books without duplicating it.
- Durable source occurrences captured when a user deliberately sets a status.
- Status history linked to the source occurrence that motivated the change.
- Latest-effective context observations, including clearing an observation.
- Word detail with current status, history, source sentences, and return to
  playback when media remains available.
- Missing and relocated media states with fingerprint-based relinking.
- Independent export, backup, restore, and migration of vocabulary assets.

## Planned Data Model

`word_occurrences` stores a durable source snapshot:

- `id`, `word_profile_id`
- nullable `sentence_id` and `media_id`
- `original_form`, optional `token_index`
- `sentence_text_snapshot`, `media_title_snapshot`
- `start_ms_snapshot`, `end_ms_snapshot`
- `first_seen_at_ms`, `last_seen_at_ms`, `encounter_count`

`word_status_history` stores:

- `word_profile_id`, `previous_status`, `new_status`
- nullable `source_occurrence_id`
- `changed_at_ms`, `change_source`

Live media and sentence foreign keys use `ON DELETE SET NULL`; snapshots remain.
Context observations may retain history, but queries and diagnosis use only the
latest effective value for a word and sentence.

## Work Packages

1. **M1.5-A Durable model and migration**
   Add occurrences, status history, media availability, nullable links, and
   migration tests.
2. **M1.5-B Vocabulary books and word detail**
   Add status-driven lists, search/filter/sort, source snapshots, and history.
3. **M1.5-C Return to source and missing-media recovery**
   Add seek/loop from source, unavailable states, and fingerprint relinking.
4. **M1.5-D Portability and acceptance**
   Add independent export/restore, performance checks, and end-to-end UAT.

## Exit Gate

Even if every original media and subtitle file is unavailable, the user can
still completely view, search, back up, restore, and migrate vocabulary states,
status history, and source sentence snapshots.

## Deferred

- Automatic status inference
- Spaced repetition and daily review scheduling
- Separate status per word sense
- Cloud sync and Anki integration
- Mobile validation
