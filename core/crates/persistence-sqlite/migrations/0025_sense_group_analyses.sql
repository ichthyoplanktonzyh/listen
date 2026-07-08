CREATE TABLE sense_group_analysis_runs (
  id TEXT PRIMARY KEY,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  parent_word_timeline_id TEXT REFERENCES word_timeline_runs(id) ON DELETE SET NULL,
  status TEXT NOT NULL,
  analysis_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE INDEX sense_group_analysis_runs_track_idx
  ON sense_group_analysis_runs(track_id, created_at_ms DESC);

CREATE INDEX sense_group_analysis_runs_track_status_idx
  ON sense_group_analysis_runs(track_id, status, updated_at_ms DESC);

CREATE UNIQUE INDEX sense_group_analysis_runs_one_active_per_track_idx
  ON sense_group_analysis_runs(track_id)
  WHERE status = '"active"';

CREATE INDEX sense_group_analysis_runs_parent_word_timeline_idx
  ON sense_group_analysis_runs(parent_word_timeline_id, created_at_ms DESC);
