CREATE TABLE word_timeline_runs (
  id TEXT PRIMARY KEY,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  status TEXT NOT NULL,
  timeline_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE INDEX word_timeline_runs_track_idx
  ON word_timeline_runs(track_id, created_at_ms DESC);

CREATE INDEX word_timeline_runs_track_status_idx
  ON word_timeline_runs(track_id, status, updated_at_ms DESC);

CREATE UNIQUE INDEX word_timeline_runs_one_active_per_track_idx
  ON word_timeline_runs(track_id)
  WHERE status = '"active"';
