-- Phase 3.19.1 product subtraction: Role Reply was a misleading fixed-answer
-- subtitle exercise, not realtime conversation. The product no longer creates
-- or decodes this kind, so remove its facts and directly traceable projections.

CREATE TEMP TABLE role_reply_attempts AS
SELECT id, rubric_id, rubric_version
FROM semantic_task_attempts
WHERE kind = '"role_reply"';

CREATE TEMP TABLE role_reply_recordings AS
SELECT DISTINCT json_extract(response.value, '$.recording_asset_id') AS id
FROM semantic_task_attempts AS attempt,
     json_each(attempt.attempt_json, '$.responses') AS response
WHERE attempt.kind = '"role_reply"'
  AND json_extract(response.value, '$.recording_asset_id') IS NOT NULL;

CREATE TEMP TABLE role_reply_observations AS
SELECT id, lexical_entry_id
FROM learning_observations
WHERE EXISTS (
  SELECT 1
  FROM role_reply_attempts AS attempt
  WHERE learning_observations.source_ref LIKE 'speaking:' || attempt.id || ':%'
);

CREATE TEMP TABLE role_reply_proposals AS
SELECT DISTINCT proposal.id, proposal.lexical_entry_id, proposal.capability
FROM projection_proposals AS proposal,
     json_each(proposal.proposal_json, '$.evidence') AS evidence
WHERE json_extract(evidence.value, '$.observation_id') IN (
  SELECT id FROM role_reply_observations
);

CREATE TEMP TABLE role_reply_confirmations AS
SELECT proposal.lexical_entry_id, proposal.capability, decision.decided_at_ms
FROM role_reply_proposals AS proposal
JOIN projection_decisions AS decision ON decision.proposal_id = proposal.id
WHERE json_extract(decision.decision_json, '$.decision') = 'confirm';

DROP TRIGGER IF EXISTS projection_decisions_no_delete;
DROP TRIGGER IF EXISTS projection_proposals_no_delete;
DROP TRIGGER IF EXISTS writing_finding_dispositions_append_only_delete;
DROP TRIGGER IF EXISTS writing_feedback_findings_append_only_delete;
DROP TRIGGER IF EXISTS judgment_adjudications_append_only_delete;
DROP TRIGGER IF EXISTS semantic_judgments_append_only_delete;
DROP TRIGGER IF EXISTS semantic_task_attempts_append_only_delete;
DROP TRIGGER IF EXISTS semantic_rubrics_append_only_delete;

DELETE FROM projection_decisions
WHERE proposal_id IN (SELECT id FROM role_reply_proposals);
DELETE FROM projection_proposals
WHERE id IN (SELECT id FROM role_reply_proposals);

-- A confirmed proposal copies its conclusion into the current projection slot.
-- Withdraw that slot only when it has not since been replaced. User overrides
-- remain authoritative and are preserved.
DELETE FROM lexical_capability_states
WHERE override_json IS NULL
  AND EXISTS (
    SELECT 1 FROM role_reply_confirmations AS confirmation
    WHERE confirmation.lexical_entry_id = lexical_capability_states.lexical_entry_id
      AND confirmation.capability = lexical_capability_states.capability
      AND confirmation.decided_at_ms = lexical_capability_states.updated_at_ms
  );
UPDATE lexical_capability_states
SET projection_json = NULL
WHERE override_json IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM role_reply_confirmations AS confirmation
    WHERE confirmation.lexical_entry_id = lexical_capability_states.lexical_entry_id
      AND confirmation.capability = lexical_capability_states.capability
      AND confirmation.decided_at_ms = lexical_capability_states.updated_at_ms
  );
DELETE FROM lexical_capability_history
WHERE EXISTS (
  SELECT 1 FROM role_reply_confirmations AS confirmation
  WHERE confirmation.lexical_entry_id = lexical_capability_history.lexical_entry_id
    AND confirmation.capability = lexical_capability_history.capability
    AND confirmation.decided_at_ms = lexical_capability_history.changed_at_ms
);

DELETE FROM learning_observations
WHERE id IN (SELECT id FROM role_reply_observations);

DELETE FROM production_corpus_documents
WHERE attempt_id IN (SELECT id FROM role_reply_attempts);

DELETE FROM writing_finding_dispositions
WHERE finding_id IN (
  SELECT id FROM writing_feedback_findings
  WHERE attempt_id IN (SELECT id FROM role_reply_attempts)
);
DELETE FROM writing_feedback_findings
WHERE attempt_id IN (SELECT id FROM role_reply_attempts);

DELETE FROM judgment_adjudications
WHERE judgment_id IN (
  SELECT id FROM semantic_judgments
  WHERE attempt_id IN (SELECT id FROM role_reply_attempts)
);
DELETE FROM semantic_judgments
WHERE attempt_id IN (SELECT id FROM role_reply_attempts);
DELETE FROM semantic_task_attempts
WHERE id IN (SELECT id FROM role_reply_attempts);
DELETE FROM semantic_rubrics
WHERE purpose = '"role_reply"';
DELETE FROM recording_assets
WHERE id IN (SELECT id FROM role_reply_recordings);

CREATE TRIGGER projection_proposals_no_delete
BEFORE DELETE ON projection_proposals BEGIN
    SELECT RAISE(ABORT, 'projection proposals are append-only');
END;
CREATE TRIGGER projection_decisions_no_delete
BEFORE DELETE ON projection_decisions BEGIN
    SELECT RAISE(ABORT, 'projection decisions are append-only');
END;
CREATE TRIGGER writing_feedback_findings_append_only_delete
BEFORE DELETE ON writing_feedback_findings BEGIN
  SELECT RAISE(ABORT, 'writing_feedback_findings is append-only');
END;
CREATE TRIGGER writing_finding_dispositions_append_only_delete
BEFORE DELETE ON writing_finding_dispositions BEGIN
  SELECT RAISE(ABORT, 'writing_finding_dispositions is append-only');
END;
CREATE TRIGGER semantic_rubrics_append_only_delete
BEFORE DELETE ON semantic_rubrics BEGIN
  SELECT RAISE(ABORT, 'semantic_rubrics is append-only');
END;
CREATE TRIGGER semantic_task_attempts_append_only_delete
BEFORE DELETE ON semantic_task_attempts BEGIN
  SELECT RAISE(ABORT, 'semantic_task_attempts is append-only');
END;
CREATE TRIGGER semantic_judgments_append_only_delete
BEFORE DELETE ON semantic_judgments BEGIN
  SELECT RAISE(ABORT, 'semantic_judgments is append-only');
END;
CREATE TRIGGER judgment_adjudications_append_only_delete
BEFORE DELETE ON judgment_adjudications BEGIN
  SELECT RAISE(ABORT, 'judgment_adjudications is append-only');
END;

DROP TABLE role_reply_confirmations;
DROP TABLE role_reply_proposals;
DROP TABLE role_reply_observations;
DROP TABLE role_reply_recordings;
DROP TABLE role_reply_attempts;
