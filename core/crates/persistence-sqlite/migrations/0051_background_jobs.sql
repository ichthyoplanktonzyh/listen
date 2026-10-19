CREATE TABLE background_jobs (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    status TEXT NOT NULL,
    job_json TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE INDEX idx_background_jobs_kind_created
    ON background_jobs(kind, created_at_ms, id);

CREATE INDEX idx_background_jobs_kind_status
    ON background_jobs(kind, status);
