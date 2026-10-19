-- Phase 3.11 semantic task fact layer (ADR 0021).
--
-- Append-only by construction: every table forbids UPDATE and DELETE via
-- triggers. Rubric revisions insert a new (id, version) row; re-judging
-- inserts a new judgment; adjudication inserts a correction row and never
-- touches the original judgment. There is intentionally NO foreign key to
-- media: rubric/attempt/judgment snapshots must keep explaining history after
-- the source media is deleted.
--
-- In-progress attempt persistence (e.g. saving dictogloss draft 1 before
-- draft 2 exists) is deferred to the first Studio consumer that needs it; the
-- additive path is a new status value plus a response-append table, not
-- relaxing these guards.

CREATE TABLE IF NOT EXISTS semantic_rubrics (
  id TEXT NOT NULL,
  version INTEGER NOT NULL,
  purpose TEXT NOT NULL,
  media_id TEXT,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  source_language TEXT NOT NULL,
  response_language TEXT NOT NULL,
  source_sha256 TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  rubric_json TEXT NOT NULL,
  PRIMARY KEY (id, version)
);

CREATE INDEX IF NOT EXISTS semantic_rubrics_media_idx
  ON semantic_rubrics(media_id, start_ms);

CREATE TABLE IF NOT EXISTS semantic_task_attempts (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  rubric_id TEXT NOT NULL,
  rubric_version INTEGER NOT NULL,
  status TEXT NOT NULL,
  started_at_ms INTEGER NOT NULL,
  attempt_json TEXT NOT NULL,
  FOREIGN KEY (rubric_id, rubric_version)
    REFERENCES semantic_rubrics(id, version)
);

CREATE INDEX IF NOT EXISTS semantic_task_attempts_rubric_idx
  ON semantic_task_attempts(rubric_id, rubric_version, started_at_ms DESC);

CREATE INDEX IF NOT EXISTS semantic_task_attempts_kind_idx
  ON semantic_task_attempts(kind, started_at_ms DESC);

CREATE TABLE IF NOT EXISTS semantic_judgments (
  id TEXT PRIMARY KEY,
  attempt_id TEXT NOT NULL REFERENCES semantic_task_attempts(id),
  response_revision INTEGER NOT NULL,
  rubric_id TEXT NOT NULL,
  rubric_version INTEGER NOT NULL,
  abstained INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  judgment_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS semantic_judgments_attempt_idx
  ON semantic_judgments(attempt_id, created_at_ms);

CREATE TABLE IF NOT EXISTS judgment_adjudications (
  id TEXT PRIMARY KEY,
  judgment_id TEXT NOT NULL REFERENCES semantic_judgments(id),
  point_id TEXT NOT NULL,
  occurred_at_ms INTEGER NOT NULL,
  adjudication_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS judgment_adjudications_judgment_idx
  ON judgment_adjudications(judgment_id, occurred_at_ms);

CREATE TRIGGER IF NOT EXISTS semantic_rubrics_append_only_update
BEFORE UPDATE ON semantic_rubrics
BEGIN
  SELECT RAISE(ABORT, 'semantic_rubrics is append-only');
END;

CREATE TRIGGER IF NOT EXISTS semantic_rubrics_append_only_delete
BEFORE DELETE ON semantic_rubrics
BEGIN
  SELECT RAISE(ABORT, 'semantic_rubrics is append-only');
END;

CREATE TRIGGER IF NOT EXISTS semantic_task_attempts_append_only_update
BEFORE UPDATE ON semantic_task_attempts
BEGIN
  SELECT RAISE(ABORT, 'semantic_task_attempts is append-only');
END;

CREATE TRIGGER IF NOT EXISTS semantic_task_attempts_append_only_delete
BEFORE DELETE ON semantic_task_attempts
BEGIN
  SELECT RAISE(ABORT, 'semantic_task_attempts is append-only');
END;

CREATE TRIGGER IF NOT EXISTS semantic_judgments_append_only_update
BEFORE UPDATE ON semantic_judgments
BEGIN
  SELECT RAISE(ABORT, 'semantic_judgments is append-only');
END;

CREATE TRIGGER IF NOT EXISTS semantic_judgments_append_only_delete
BEFORE DELETE ON semantic_judgments
BEGIN
  SELECT RAISE(ABORT, 'semantic_judgments is append-only');
END;

CREATE TRIGGER IF NOT EXISTS judgment_adjudications_append_only_update
BEFORE UPDATE ON judgment_adjudications
BEGIN
  SELECT RAISE(ABORT, 'judgment_adjudications is append-only');
END;

CREATE TRIGGER IF NOT EXISTS judgment_adjudications_append_only_delete
BEFORE DELETE ON judgment_adjudications
BEGIN
  SELECT RAISE(ABORT, 'judgment_adjudications is append-only');
END;
