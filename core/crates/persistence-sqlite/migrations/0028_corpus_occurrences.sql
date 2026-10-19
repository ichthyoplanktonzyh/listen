-- Rebuildable, local-only search projection. It is deliberately separate from
-- lexical_occurrences: this table indexes every imported subtitle context,
-- including contexts the learner has not saved as an asset.
CREATE TABLE corpus_occurrences (
  id TEXT PRIMARY KEY,
  language TEXT NOT NULL,
  kind TEXT NOT NULL,
  normalized_key TEXT,
  display_text TEXT NOT NULL,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE CASCADE,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  source_snapshot TEXT NOT NULL
);

CREATE INDEX corpus_occurrences_language_key_idx
  ON corpus_occurrences(language, normalized_key);
CREATE INDEX corpus_occurrences_track_idx
  ON corpus_occurrences(track_id, start_ms);
