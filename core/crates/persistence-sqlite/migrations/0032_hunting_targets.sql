CREATE TABLE IF NOT EXISTS hunting_targets (
  id TEXT PRIMARY KEY,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  target_json TEXT NOT NULL,
  UNIQUE(lexical_entry_id)
);

CREATE INDEX IF NOT EXISTS hunting_targets_status_idx
  ON hunting_targets(status, updated_at_ms DESC);
