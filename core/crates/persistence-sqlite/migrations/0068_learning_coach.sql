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

CREATE TABLE content_difficulty_profiles (
  subject_kind TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  language TEXT NOT NULL,
  algorithm_version TEXT NOT NULL,
  input_fingerprint TEXT NOT NULL,
  computed_at_ms INTEGER NOT NULL,
  profile_json TEXT NOT NULL,
  PRIMARY KEY (subject_kind, subject_id)
);

CREATE TABLE content_fit_calibrations (
  subject_kind TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  calibration_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (subject_kind, subject_id)
);

CREATE TABLE projection_proposals (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL,
  capability TEXT NOT NULL,
  algorithm_version TEXT NOT NULL,
  evidence_as_of_ms INTEGER NOT NULL,
  proposal_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  FOREIGN KEY (lexical_entry_id) REFERENCES lexical_entries(id) ON DELETE CASCADE
);
CREATE INDEX idx_projection_proposals_target
  ON projection_proposals(lexical_entry_id, capability, created_at_ms DESC);

CREATE TABLE projection_decisions (
  id TEXT PRIMARY KEY NOT NULL,
  proposal_id TEXT NOT NULL UNIQUE,
  decision_json TEXT NOT NULL,
  decided_at_ms INTEGER NOT NULL,
  FOREIGN KEY (proposal_id) REFERENCES projection_proposals(id) ON DELETE RESTRICT
);
CREATE TRIGGER projection_proposals_no_update
BEFORE UPDATE ON projection_proposals BEGIN
  SELECT RAISE(ABORT, 'projection proposals are append-only');
END;
CREATE TRIGGER projection_proposals_no_delete
BEFORE DELETE ON projection_proposals BEGIN
  SELECT RAISE(ABORT, 'projection proposals are append-only');
END;
CREATE TRIGGER projection_decisions_no_update
BEFORE UPDATE ON projection_decisions BEGIN
  SELECT RAISE(ABORT, 'projection decisions are append-only');
END;
CREATE TRIGGER projection_decisions_no_delete
BEFORE DELETE ON projection_decisions BEGIN
  SELECT RAISE(ABORT, 'projection decisions are append-only');
END;
