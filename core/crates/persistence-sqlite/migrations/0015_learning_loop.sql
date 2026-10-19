CREATE TABLE practice_sessions (
  id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  track_id TEXT REFERENCES subtitle_tracks(id) ON DELETE SET NULL,
  started_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER,
  session_json TEXT NOT NULL
);

CREATE INDEX practice_sessions_started_idx
  ON practice_sessions(started_at_ms DESC);

CREATE INDEX practice_sessions_media_idx
  ON practice_sessions(media_id, started_at_ms DESC);

CREATE TABLE practice_items (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES practice_sessions(id) ON DELETE SET NULL,
  kind TEXT NOT NULL,
  target_kind TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  item_json TEXT NOT NULL
);

CREATE INDEX practice_items_session_idx
  ON practice_items(session_id, created_at_ms DESC);

CREATE INDEX practice_items_kind_idx
  ON practice_items(kind, created_at_ms DESC);

CREATE TABLE practice_attempts (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES practice_items(id) ON DELETE CASCADE,
  result TEXT NOT NULL,
  submitted_at_ms INTEGER NOT NULL,
  attempt_json TEXT NOT NULL
);

CREATE INDEX practice_attempts_item_idx
  ON practice_attempts(item_id, submitted_at_ms DESC);

CREATE INDEX practice_attempts_result_idx
  ON practice_attempts(result, submitted_at_ms DESC);

CREATE TABLE review_items (
  id TEXT PRIMARY KEY,
  source_kind TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  item_json TEXT NOT NULL
);

CREATE INDEX review_items_status_idx
  ON review_items(status, updated_at_ms DESC);

CREATE INDEX review_items_source_idx
  ON review_items(source_kind, created_at_ms DESC);

CREATE TABLE review_attempts (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES review_items(id) ON DELETE CASCADE,
  reviewed_at_ms INTEGER NOT NULL,
  rating TEXT NOT NULL,
  attempt_json TEXT NOT NULL
);

CREATE INDEX review_attempts_item_idx
  ON review_attempts(item_id, reviewed_at_ms DESC);

CREATE TABLE learning_events (
  id TEXT PRIMARY KEY,
  occurred_at_ms INTEGER NOT NULL,
  kind TEXT NOT NULL,
  subject_kind TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  session_id TEXT REFERENCES practice_sessions(id) ON DELETE SET NULL,
  event_json TEXT NOT NULL
);

CREATE INDEX learning_events_occurred_idx
  ON learning_events(occurred_at_ms DESC);

CREATE INDEX learning_events_kind_idx
  ON learning_events(kind, occurred_at_ms DESC);

CREATE INDEX learning_events_subject_idx
  ON learning_events(subject_kind, subject_id, occurred_at_ms DESC);
