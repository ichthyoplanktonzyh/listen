CREATE TABLE IF NOT EXISTS recording_assets (
  id TEXT PRIMARY KEY,
  practice_attempt_id TEXT REFERENCES practice_attempts(id) ON DELETE SET NULL,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  language TEXT NOT NULL,
  file_path TEXT NOT NULL,
  duration_ms INTEGER NOT NULL CHECK (duration_ms > 0),
  created_at_ms INTEGER NOT NULL,
  asset_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS recording_assets_attempt_idx
  ON recording_assets(practice_attempt_id);

CREATE INDEX IF NOT EXISTS recording_assets_media_created_idx
  ON recording_assets(media_id, created_at_ms DESC);
