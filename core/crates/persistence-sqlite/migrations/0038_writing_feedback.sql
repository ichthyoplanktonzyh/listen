-- Phase 3.15 Writing Studio feedback facts.
-- Findings never rewrite learner text. Accept/reject decisions append a
-- disposition and accepted suggestions cite a later learner revision stored
-- in the immutable semantic attempt snapshot.

CREATE TABLE IF NOT EXISTS writing_feedback_findings (
  id TEXT PRIMARY KEY,
  attempt_id TEXT NOT NULL REFERENCES semantic_task_attempts(id),
  response_revision INTEGER NOT NULL,
  layer TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  finding_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS writing_feedback_findings_attempt_idx
  ON writing_feedback_findings(attempt_id, response_revision, created_at_ms, id);

CREATE TABLE IF NOT EXISTS writing_finding_dispositions (
  id TEXT PRIMARY KEY,
  finding_id TEXT NOT NULL REFERENCES writing_feedback_findings(id),
  decision TEXT NOT NULL,
  occurred_at_ms INTEGER NOT NULL,
  disposition_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS writing_finding_dispositions_finding_idx
  ON writing_finding_dispositions(finding_id, occurred_at_ms, id);

-- Mutable scratch only: never consumed as an attempt, judgment, observation,
-- or projection. Submission deletes it after the immutable attempt is saved.
CREATE TABLE IF NOT EXISTS writing_drafts (
  rubric_id TEXT PRIMARY KEY,
  updated_at_ms INTEGER NOT NULL,
  draft_json TEXT NOT NULL
);

CREATE TRIGGER IF NOT EXISTS writing_feedback_findings_append_only_update
BEFORE UPDATE ON writing_feedback_findings
BEGIN
  SELECT RAISE(ABORT, 'writing_feedback_findings is append-only');
END;

CREATE TRIGGER IF NOT EXISTS writing_feedback_findings_append_only_delete
BEFORE DELETE ON writing_feedback_findings
BEGIN
  SELECT RAISE(ABORT, 'writing_feedback_findings is append-only');
END;

CREATE TRIGGER IF NOT EXISTS writing_finding_dispositions_append_only_update
BEFORE UPDATE ON writing_finding_dispositions
BEGIN
  SELECT RAISE(ABORT, 'writing_finding_dispositions is append-only');
END;

CREATE TRIGGER IF NOT EXISTS writing_finding_dispositions_append_only_delete
BEFORE DELETE ON writing_finding_dispositions
BEGIN
  SELECT RAISE(ABORT, 'writing_finding_dispositions is append-only');
END;
