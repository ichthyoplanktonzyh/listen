CREATE TABLE lexical_entries (
  id TEXT PRIMARY KEY NOT NULL,
  language TEXT NOT NULL,
  kind TEXT NOT NULL,
  canonical_form TEXT NOT NULL,
  normalized_form TEXT NOT NULL,
  display_form TEXT NOT NULL,
  status TEXT,
  user_definition TEXT,
  personal_note TEXT,
  normalization_provider TEXT NOT NULL,
  normalization_version TEXT NOT NULL,
  user_corrected INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL,
  learning_updated_at_ms INTEGER NOT NULL DEFAULT 0,
  UNIQUE(language, kind, normalized_form)
);

CREATE INDEX idx_lexical_entries_status
  ON lexical_entries(language, kind, status, normalized_form);

CREATE TABLE lexical_occurrences (
  id TEXT PRIMARY KEY NOT NULL,
  source_key TEXT NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  original_form TEXT NOT NULL,
  sentence_text_snapshot TEXT NOT NULL,
  media_title_snapshot TEXT NOT NULL,
  media_fingerprint_snapshot TEXT NOT NULL,
  start_ms_snapshot INTEGER NOT NULL,
  end_ms_snapshot INTEGER NOT NULL,
  token_start INTEGER,
  token_end INTEGER,
  first_seen_at_ms INTEGER NOT NULL,
  last_seen_at_ms INTEGER NOT NULL,
  encounter_count INTEGER NOT NULL,
  UNIQUE(lexical_entry_id, source_key)
);

CREATE INDEX idx_lexical_occurrences_recent
  ON lexical_occurrences(lexical_entry_id, last_seen_at_ms DESC);

CREATE TABLE lexical_status_history (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  previous_status TEXT,
  new_status TEXT,
  changed_at_ms INTEGER NOT NULL,
  change_source TEXT NOT NULL
);

CREATE TABLE lemma_overrides (
  language TEXT NOT NULL,
  original_normalized TEXT NOT NULL,
  corrected_normalized TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(language, original_normalized)
);

CREATE TABLE learning_resources (
  id TEXT PRIMARY KEY NOT NULL,
  descriptor_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

INSERT INTO lexical_entries
  (id, language, kind, canonical_form, normalized_form, display_form, status,
   user_definition, personal_note, normalization_provider, normalization_version,
   user_corrected, updated_at_ms, learning_updated_at_ms)
SELECT id, language, '"word"', lemma, normalized_lemma, display_form, status,
       user_definition, personal_note, 'legacy', 'v1', 0, updated_at_ms,
       learning_updated_at_ms
FROM word_profiles;

INSERT INTO lexical_occurrences
  (id, source_key, lexical_entry_id, media_id, sentence_id, original_form,
   sentence_text_snapshot, media_title_snapshot, media_fingerprint_snapshot,
   start_ms_snapshot, end_ms_snapshot, token_start, token_end, first_seen_at_ms,
   last_seen_at_ms, encounter_count)
SELECT id, source_key, word_profile_id, media_id, sentence_id, original_form,
       sentence_text_snapshot, media_title_snapshot, media_fingerprint_snapshot,
       start_ms_snapshot, end_ms_snapshot, NULL, NULL, first_seen_at_ms,
       last_seen_at_ms, encounter_count
FROM word_occurrences;

INSERT INTO lexical_status_history
  (id, lexical_entry_id, previous_status, new_status, changed_at_ms, change_source)
SELECT id, word_profile_id, previous_status, new_status, changed_at_ms, change_source
FROM word_status_history;
