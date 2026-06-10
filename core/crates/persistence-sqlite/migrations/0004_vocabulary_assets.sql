ALTER TABLE media_items ADD COLUMN availability TEXT NOT NULL DEFAULT '"available"';

CREATE TABLE word_occurrences (
  id TEXT PRIMARY KEY NOT NULL,
  source_key TEXT NOT NULL,
  word_profile_id TEXT NOT NULL REFERENCES word_profiles(id) ON DELETE CASCADE,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  original_form TEXT NOT NULL,
  sentence_text_snapshot TEXT NOT NULL,
  media_title_snapshot TEXT NOT NULL,
  media_fingerprint_snapshot TEXT NOT NULL,
  start_ms_snapshot INTEGER NOT NULL CHECK(start_ms_snapshot >= 0),
  end_ms_snapshot INTEGER NOT NULL CHECK(end_ms_snapshot >= start_ms_snapshot),
  first_seen_at_ms INTEGER NOT NULL,
  last_seen_at_ms INTEGER NOT NULL,
  encounter_count INTEGER NOT NULL CHECK(encounter_count > 0),
  UNIQUE(word_profile_id, source_key)
);

CREATE INDEX idx_occurrence_word_recent
  ON word_occurrences(word_profile_id, last_seen_at_ms DESC);
CREATE INDEX idx_occurrence_media_fingerprint
  ON word_occurrences(media_fingerprint_snapshot);

INSERT OR IGNORE INTO word_occurrences
  (id, source_key, word_profile_id, media_id, sentence_id, original_form,
   sentence_text_snapshot, media_title_snapshot, media_fingerprint_snapshot,
   start_ms_snapshot, end_ms_snapshot, first_seen_at_ms, last_seen_at_ms,
   encounter_count)
SELECT
  'legacy-occurrence-' || o.id,
  'legacy:' || o.word_profile_id || ':' || o.sentence_id,
  o.word_profile_id,
  m.id,
  s.id,
  o.original_form,
  s.display_text,
  m.title,
  m.fingerprint,
  s.start_ms,
  s.end_ms,
  o.created_at_ms,
  o.created_at_ms,
  1
FROM word_observations o
JOIN subtitle_sentences s ON s.id = o.sentence_id
JOIN subtitle_tracks t ON t.id = s.track_id
JOIN media_items m ON m.id = t.media_id;

CREATE TABLE word_status_history (
  id TEXT PRIMARY KEY NOT NULL,
  word_profile_id TEXT NOT NULL REFERENCES word_profiles(id) ON DELETE CASCADE,
  previous_status TEXT,
  new_status TEXT,
  source_occurrence_id TEXT REFERENCES word_occurrences(id) ON DELETE SET NULL,
  changed_at_ms INTEGER NOT NULL,
  change_source TEXT NOT NULL
);

CREATE INDEX idx_status_history_word_time
  ON word_status_history(word_profile_id, changed_at_ms DESC);

INSERT INTO word_status_history
  (id, word_profile_id, previous_status, new_status, source_occurrence_id,
   changed_at_ms, change_source)
SELECT
  'legacy-' || id, id, NULL, status, NULL, updated_at_ms, '"legacy_baseline"'
FROM word_profiles
WHERE status IS NOT NULL;

CREATE TABLE word_observations_v4 (
  id TEXT PRIMARY KEY NOT NULL,
  word_profile_id TEXT NOT NULL REFERENCES word_profiles(id) ON DELETE CASCADE,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  sentence_id_snapshot TEXT NOT NULL,
  original_form TEXT NOT NULL,
  result TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  cleared_at_ms INTEGER,
  UNIQUE(word_profile_id, sentence_id)
);

INSERT OR REPLACE INTO word_observations_v4
  (id, word_profile_id, sentence_id, sentence_id_snapshot, original_form, result, created_at_ms, cleared_at_ms)
SELECT id, word_profile_id, sentence_id, sentence_id, original_form, result, created_at_ms, NULL
FROM word_observations
ORDER BY created_at_ms;

DROP TABLE word_observations;
ALTER TABLE word_observations_v4 RENAME TO word_observations;
CREATE INDEX idx_observation_sentence ON word_observations(sentence_id);
CREATE INDEX idx_observation_word ON word_observations(word_profile_id);
