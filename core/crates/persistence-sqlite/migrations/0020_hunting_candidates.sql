CREATE TABLE hunting_candidates (
  id TEXT PRIMARY KEY,
  lexical_entry_id TEXT NOT NULL,
  review_item_id TEXT NOT NULL REFERENCES review_items(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  failure_count INTEGER NOT NULL,
  last_failed_at_ms INTEGER NOT NULL,
  candidate_json TEXT NOT NULL,
  UNIQUE(lexical_entry_id, review_item_id)
);

CREATE INDEX hunting_candidates_status_idx
  ON hunting_candidates(status, last_failed_at_ms DESC);

CREATE INDEX hunting_candidates_lexical_idx
  ON hunting_candidates(lexical_entry_id, last_failed_at_ms DESC);
