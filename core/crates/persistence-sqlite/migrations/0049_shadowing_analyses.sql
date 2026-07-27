CREATE TABLE IF NOT EXISTS shadowing_analyses (
  id TEXT PRIMARY KEY,
  recording_id TEXT NOT NULL REFERENCES recording_assets(id) ON DELETE CASCADE,
  attempt_id TEXT NOT NULL REFERENCES practice_attempts(id) ON DELETE CASCADE,
  provider_id TEXT NOT NULL,
  provider_version TEXT NOT NULL,
  reference_audio_sha256 TEXT NOT NULL CHECK (length(reference_audio_sha256) = 64),
  created_at_ms INTEGER NOT NULL,
  analysis_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS shadowing_analyses_recording_created_idx
  ON shadowing_analyses(recording_id, created_at_ms DESC);
