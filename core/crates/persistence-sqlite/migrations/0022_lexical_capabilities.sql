CREATE TABLE lexical_capability_states (
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  sense_id TEXT NOT NULL DEFAULT '',
  capability TEXT NOT NULL,
  projection_json TEXT,
  override_json TEXT,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(lexical_entry_id, sense_id, capability),
  CHECK(projection_json IS NOT NULL OR override_json IS NOT NULL)
);

CREATE INDEX lexical_capability_states_capability_idx
  ON lexical_capability_states(capability, updated_at_ms DESC);

CREATE TABLE lexical_capability_history (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  sense_id TEXT NOT NULL DEFAULT '',
  capability TEXT NOT NULL,
  previous_state_json TEXT NOT NULL,
  new_state_json TEXT NOT NULL,
  change_kind TEXT NOT NULL,
  changed_at_ms INTEGER NOT NULL
);

CREATE INDEX lexical_capability_history_entry_idx
  ON lexical_capability_history(lexical_entry_id, sense_id, changed_at_ms DESC);
