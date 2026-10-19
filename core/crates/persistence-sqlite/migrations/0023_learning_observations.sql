-- ADR 0017: channelized, append-only learning evidence. No upsert path:
-- identity includes source attempt and timestamp, never (entry, sentence).
CREATE TABLE learning_observations (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  sense_id TEXT NOT NULL DEFAULT '',
  capability TEXT NOT NULL,
  task_type TEXT NOT NULL,
  outcome TEXT NOT NULL,
  assistance TEXT NOT NULL,
  surface_form TEXT,
  sentence_id TEXT,
  media_id TEXT,
  origin TEXT NOT NULL,
  source_ref TEXT,
  occurred_at_ms INTEGER NOT NULL
);

CREATE INDEX learning_observations_entry_capability_idx
  ON learning_observations(lexical_entry_id, capability, occurred_at_ms DESC);

CREATE INDEX learning_observations_occurred_idx
  ON learning_observations(occurred_at_ms DESC);
