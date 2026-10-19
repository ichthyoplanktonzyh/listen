CREATE TABLE listening_inbox_items (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES practice_sessions(id) ON DELETE SET NULL,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  track_id TEXT REFERENCES subtitle_tracks(id) ON DELETE SET NULL,
  status TEXT NOT NULL,
  captured_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER,
  item_json TEXT NOT NULL
);

CREATE INDEX listening_inbox_items_status_idx
  ON listening_inbox_items(status, updated_at_ms DESC);

CREATE INDEX listening_inbox_items_session_idx
  ON listening_inbox_items(session_id, captured_at_ms DESC);

CREATE INDEX listening_inbox_items_media_idx
  ON listening_inbox_items(media_id, captured_at_ms DESC);
