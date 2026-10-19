CREATE TABLE lexical_entries (
  id TEXT PRIMARY KEY NOT NULL,
  language TEXT NOT NULL,
  kind TEXT NOT NULL,
  granularity TEXT NOT NULL,
  normalization TEXT NOT NULL,
  normalized_key TEXT NOT NULL,
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
  UNIQUE(language, granularity, normalization, normalized_key)
);

CREATE INDEX idx_lexical_entries_status
  ON lexical_entries(language, granularity, status, normalized_key);

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

CREATE TABLE lexical_observations (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  sentence_id_snapshot TEXT NOT NULL,
  original_form TEXT NOT NULL,
  result TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  cleared_at_ms INTEGER,
  UNIQUE(lexical_entry_id, sentence_id)
);

CREATE INDEX idx_lexical_observation_sentence
  ON lexical_observations(sentence_id);
CREATE INDEX idx_lexical_observation_entry
  ON lexical_observations(lexical_entry_id);

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
