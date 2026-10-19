-- Phase 3.5 Slice 7: recorded usage-feedback corrections per fit subject
-- (comprehension self-report and practice-accuracy counters). Durable
-- learner evidence, deliberately separate from the recomputable
-- content_difficulty_profiles cache: calibration must survive every fit
-- recompute (ADR 0018 decision 1 / feedback-calibration slice).
--
-- Numbering note: v25 stays reserved for Phase 3.4.2 (independent branch);
-- this repository continues past its own v26 per the "later lander
-- renumbers" rule.
CREATE TABLE content_fit_calibrations (
  subject_kind TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  calibration_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY (subject_kind, subject_id)
);
