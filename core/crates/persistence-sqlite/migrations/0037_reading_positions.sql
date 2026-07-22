-- Reading cursor (Phase 3.13): one overwritable row per subtitle track,
-- keyed by track id. This is deliberately NOT append-only: the position is a
-- cursor, not evidence. Reading history (attempts, judgments, adjudications)
-- lives in the v35 semantic-task family; observations in their own family.
-- anchor_cue_id is the derived paragraph's first cue id, which survives
-- paragraph re-derivation; paragraph_index is a display hint only.
CREATE TABLE IF NOT EXISTS reading_positions (
  track_id TEXT PRIMARY KEY,
  media_id TEXT,
  anchor_cue_id TEXT NOT NULL,
  paragraph_index INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
