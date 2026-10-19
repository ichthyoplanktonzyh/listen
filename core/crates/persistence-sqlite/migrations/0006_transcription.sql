CREATE TABLE transcription_models (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  descriptor_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE transcription_jobs (
  id TEXT PRIMARY KEY,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  input_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL,
  job_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX transcription_jobs_status_idx ON transcription_jobs(status, updated_at_ms);
CREATE INDEX transcription_jobs_input_idx ON transcription_jobs(input_fingerprint, status);

CREATE TABLE subtitle_track_provenance (
  track_id TEXT PRIMARY KEY REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  transcription_job_id TEXT NOT NULL REFERENCES transcription_jobs(id),
  provenance_json TEXT NOT NULL
);
