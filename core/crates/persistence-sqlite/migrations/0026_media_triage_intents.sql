-- Phase 3.5 Slice 5: explicit user triage intent per media (pin to a queue /
-- defer). One row per media with an active intent; clearing the intent
-- deletes the row. Queues themselves stay a derived view (ADR 0018 decision
-- 6) — this table stores only the user's explicit judgment.
--
-- Numbering note: v25 is reserved by Phase 3.4.2 (in flight on an independent
-- branch); per the "later lander renumbers" rule this migration deliberately
-- takes v26, leaving the v25 slot to 3.4.2.
CREATE TABLE media_triage_intents (
  media_id TEXT NOT NULL PRIMARY KEY,
  intent TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
