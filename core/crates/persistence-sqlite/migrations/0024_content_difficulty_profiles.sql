-- ADR 0018: cached dual-dimension content fit profiles. One row per subject;
-- rows are a recomputable cache keyed by input_fingerprint, never evidence.
-- No foreign key to media: profiles may outlive re-registration and are
-- self-invalidating through fingerprint mismatch.
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
