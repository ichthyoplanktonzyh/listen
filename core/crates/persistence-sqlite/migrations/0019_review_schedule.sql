CREATE TABLE review_schedules (
  item_id TEXT PRIMARY KEY REFERENCES review_items(id) ON DELETE CASCADE,
  due_at_ms INTEGER NOT NULL,
  algorithm TEXT NOT NULL,
  schedule_json TEXT NOT NULL
);

CREATE INDEX review_schedules_due_idx
  ON review_schedules(due_at_ms ASC);

-- Review items created before Phase 3.4 are immediately eligible.  Keeping the
-- backfill in the migration makes the queue independently useful after upgrade.
INSERT INTO review_schedules (item_id, due_at_ms, algorithm, schedule_json)
SELECT id,
       created_at_ms,
       'listen_review_v1_heuristic_proxy',
       json_object(
         'item_id', id,
         'algorithm', 'listen_review_v1_heuristic_proxy',
         'due_at_ms', created_at_ms,
         'stability', NULL,
         'difficulty', NULL,
         'interval_days', NULL,
         'lapse_count', 0
       )
FROM review_items;
