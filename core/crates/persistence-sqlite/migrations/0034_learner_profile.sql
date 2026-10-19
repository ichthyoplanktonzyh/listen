-- Learner profile (Phase 3.9): persists the learner's L1 (native language)
-- alongside a client-reported UI-language snapshot. Learning language stays
-- per-track (Phase 2.11) and UI language authority stays in client settings;
-- this row is the durable L1 setting plus the unified read surface for the
-- diagnosis layer and the coach dashboard.
CREATE TABLE IF NOT EXISTS learner_profiles (
  id TEXT PRIMARY KEY,
  ui_language TEXT NOT NULL,
  l1_language TEXT,
  active_l2_language TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
