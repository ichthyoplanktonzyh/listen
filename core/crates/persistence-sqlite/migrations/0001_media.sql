CREATE TABLE media_items (
  id TEXT PRIMARY KEY NOT NULL,
  path TEXT NOT NULL,
  fingerprint TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  kind TEXT NOT NULL,
  duration_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE playback_progress (
  media_id TEXT PRIMARY KEY NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
  position_ms INTEGER NOT NULL CHECK(position_ms >= 0),
  updated_at_ms INTEGER NOT NULL
);

CREATE INDEX idx_media_path ON media_items(path);
