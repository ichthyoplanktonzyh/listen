-- R5 legacy retirement: drop the retired ChunkTimeline persistence family.
--
-- Migration 0013 (immutable history) created `chunk_timeline_runs` and its
-- indexes for the legacy ChunkTimeline domain. The family was retired in R5
-- and is no longer read or written by any code path; this forward migration
-- removes its storage from upgraded databases. The table held replaceable
-- analysis artifacts only and never referenced learner history, so dropping
-- it never cascades to durable learning records.
DROP INDEX IF EXISTS chunk_timeline_runs_track_idx;
DROP INDEX IF EXISTS chunk_timeline_runs_track_status_idx;
DROP INDEX IF EXISTS chunk_timeline_runs_one_active_per_track_idx;
DROP INDEX IF EXISTS chunk_timeline_runs_parent_word_timeline_idx;
DROP TABLE IF EXISTS chunk_timeline_runs;
