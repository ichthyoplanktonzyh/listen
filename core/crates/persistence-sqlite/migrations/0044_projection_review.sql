CREATE TABLE IF NOT EXISTS projection_proposals (
    id TEXT PRIMARY KEY NOT NULL,
    lexical_entry_id TEXT NOT NULL,
    capability TEXT NOT NULL,
    algorithm_version TEXT NOT NULL,
    evidence_as_of_ms INTEGER NOT NULL,
    proposal_json TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    FOREIGN KEY (lexical_entry_id) REFERENCES lexical_entries(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_projection_proposals_target
ON projection_proposals(lexical_entry_id, capability, created_at_ms DESC);

CREATE TABLE IF NOT EXISTS projection_decisions (
    id TEXT PRIMARY KEY NOT NULL,
    proposal_id TEXT NOT NULL UNIQUE,
    decision_json TEXT NOT NULL,
    decided_at_ms INTEGER NOT NULL,
    FOREIGN KEY (proposal_id) REFERENCES projection_proposals(id) ON DELETE RESTRICT
);

CREATE TRIGGER IF NOT EXISTS projection_proposals_no_update
BEFORE UPDATE ON projection_proposals BEGIN
    SELECT RAISE(ABORT, 'projection proposals are append-only');
END;
CREATE TRIGGER IF NOT EXISTS projection_proposals_no_delete
BEFORE DELETE ON projection_proposals BEGIN
    SELECT RAISE(ABORT, 'projection proposals are append-only');
END;
CREATE TRIGGER IF NOT EXISTS projection_decisions_no_update
BEFORE UPDATE ON projection_decisions BEGIN
    SELECT RAISE(ABORT, 'projection decisions are append-only');
END;
CREATE TRIGGER IF NOT EXISTS projection_decisions_no_delete
BEFORE DELETE ON projection_decisions BEGIN
    SELECT RAISE(ABORT, 'projection decisions are append-only');
END;
