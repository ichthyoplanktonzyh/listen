CREATE TABLE learning_preparation_runs (
  id TEXT PRIMARY KEY NOT NULL,
  target_key TEXT NOT NULL,
  input_fingerprint TEXT NOT NULL,
  plan_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL
    CHECK (status IN ('queued','running','cancelling','completed','failed','cancelled')),
  revision INTEGER NOT NULL CHECK (revision >= 0),
  retry_of_run_id TEXT REFERENCES learning_preparation_runs(id),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  run_json TEXT NOT NULL
);

CREATE INDEX learning_preparation_runs_target_history
  ON learning_preparation_runs(target_key, created_at_ms DESC, id);

CREATE UNIQUE INDEX learning_preparation_runs_active_target
  ON learning_preparation_runs(target_key)
  WHERE status IN ('queued','running','cancelling');
