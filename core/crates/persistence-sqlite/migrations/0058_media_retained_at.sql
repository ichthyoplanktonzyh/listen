-- Phase 1 material retention: explicit Personal Library membership.
--
-- Media registration previously conflated identity/resource attachment with
-- Personal Library membership: every registered row appeared in
-- `listMediaLibrary`. This migration adds nullable membership evidence and
-- backfills every preexisting row as retained so an upgrade never empties the
-- learner's current library.
--
-- `retained_at_ms` is the deterministic membership time (non-null = library
-- member). The migration chooses the row's creation time so the backfill is
-- deterministic and stable across re-runs. New rows registered as Temporary
-- Material (explicit `retain: false`) start with NULL; membership is set once
-- at first retention and never silently rewritten or cleared by repeated
-- registration or retention.
ALTER TABLE media_items ADD COLUMN retained_at_ms INTEGER;

UPDATE media_items SET retained_at_ms = created_at_ms WHERE retained_at_ms IS NULL;
