CREATE TABLE lltimeline_resources (
  track_id TEXT PRIMARY KEY REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  metadata_json TEXT NOT NULL,
  artifacts_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
