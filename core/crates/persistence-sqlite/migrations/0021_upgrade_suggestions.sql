CREATE TABLE recognition_evidence (
  id TEXT PRIMARY KEY,
  lexical_entry_id TEXT NOT NULL,
  context_key TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  occurred_at_ms INTEGER NOT NULL,
  evidence_json TEXT NOT NULL,
  UNIQUE(lexical_entry_id, context_key)
);

CREATE INDEX recognition_evidence_lexical_idx
  ON recognition_evidence(lexical_entry_id, occurred_at_ms DESC);

CREATE TABLE upgrade_suggestions (
  id TEXT PRIMARY KEY,
  lexical_entry_id TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  resolved_at_ms INTEGER,
  cooldown_until_ms INTEGER,
  suggestion_json TEXT NOT NULL
);

CREATE INDEX upgrade_suggestions_status_idx
  ON upgrade_suggestions(status, created_at_ms DESC);

CREATE INDEX upgrade_suggestions_lexical_idx
  ON upgrade_suggestions(lexical_entry_id, created_at_ms DESC);
