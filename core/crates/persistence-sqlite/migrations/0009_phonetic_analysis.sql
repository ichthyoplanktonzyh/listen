CREATE TABLE phonetic_analysis_models (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  descriptor_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE phonetic_analysis_jobs (
  id TEXT PRIMARY KEY,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id),
  sentence_id TEXT REFERENCES subtitle_sentences(id),
  input_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL,
  job_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
CREATE INDEX phonetic_analysis_jobs_status_idx
  ON phonetic_analysis_jobs(status, updated_at_ms);
CREATE INDEX phonetic_analysis_jobs_input_idx
  ON phonetic_analysis_jobs(input_fingerprint, status);

CREATE TABLE phonetic_analyses (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL REFERENCES phonetic_analysis_jobs(id),
  media_id TEXT NOT NULL,
  track_id TEXT NOT NULL,
  sentence_id TEXT,
  provider_id TEXT NOT NULL,
  model_id TEXT NOT NULL,
  analysis_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL
);
CREATE INDEX phonetic_analyses_track_idx
  ON phonetic_analyses(track_id, created_at_ms DESC);
CREATE INDEX phonetic_analyses_sentence_idx
  ON phonetic_analyses(sentence_id, created_at_ms DESC);

CREATE TABLE phonetic_finding_feedback (
  finding_id TEXT PRIMARY KEY,
  feedback_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
