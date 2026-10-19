CREATE TABLE phone_timeline_runs (
  id TEXT PRIMARY KEY,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  parent_word_timeline_id TEXT REFERENCES word_timeline_runs(id) ON DELETE SET NULL,
  parent_phonetic_analysis_id TEXT,
  status TEXT NOT NULL,
  timeline_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE INDEX phone_timeline_runs_track_idx
  ON phone_timeline_runs(track_id, created_at_ms DESC);

CREATE INDEX phone_timeline_runs_track_status_idx
  ON phone_timeline_runs(track_id, status, updated_at_ms DESC);

CREATE UNIQUE INDEX phone_timeline_runs_one_active_per_track_idx
  ON phone_timeline_runs(track_id)
  WHERE status = '"active"';

CREATE INDEX phone_timeline_runs_sentence_idx
  ON phone_timeline_runs(sentence_id, created_at_ms DESC);

CREATE INDEX phone_timeline_runs_parent_word_timeline_idx
  ON phone_timeline_runs(parent_word_timeline_id, created_at_ms DESC);

CREATE INDEX phone_timeline_runs_parent_phonetic_analysis_idx
  ON phone_timeline_runs(parent_phonetic_analysis_id, created_at_ms DESC);
