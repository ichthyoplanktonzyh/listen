-- Preserve the progress of schedules produced by the old heuristic while
-- materializing the FSRS fields. The application refines this conservative
-- seed with FSRS::memory_state_from_sm2 on the next review.
UPDATE review_schedules
SET algorithm = 'fsrs_6_default_v1',
    schedule_json = json_set(
      schedule_json,
      '$.algorithm', 'fsrs_6_default_v1',
      '$.stability',
        CASE
          WHEN json_extract(schedule_json, '$.stability') IS NOT NULL
            THEN json_extract(schedule_json, '$.stability')
          WHEN json_extract(schedule_json, '$.interval_days') IS NOT NULL
            THEN MAX(0.1, json_extract(schedule_json, '$.interval_days'))
          ELSE NULL
        END,
      '$.difficulty',
        CASE
          WHEN json_extract(schedule_json, '$.difficulty') IS NOT NULL
            THEN json_extract(schedule_json, '$.difficulty')
          WHEN json_extract(schedule_json, '$.interval_days') IS NOT NULL
            THEN MIN(
              10.0,
              5.0 + COALESCE(json_extract(schedule_json, '$.lapse_count'), 0) * 0.5
            )
          ELSE NULL
        END,
      '$.last_reviewed_at_ms',
        CASE
          WHEN json_extract(schedule_json, '$.last_reviewed_at_ms') IS NOT NULL
            THEN json_extract(schedule_json, '$.last_reviewed_at_ms')
          WHEN json_extract(schedule_json, '$.interval_days') > 0
            THEN MAX(
              0,
              due_at_ms - CAST(json_extract(schedule_json, '$.interval_days') * 86400000 AS INTEGER)
            )
          WHEN json_extract(schedule_json, '$.interval_days') IS NOT NULL
            THEN MAX(0, due_at_ms - 600000)
          ELSE NULL
        END,
      '$.review_count',
        CASE
          WHEN COALESCE(json_extract(schedule_json, '$.review_count'), 0) > 0
            THEN json_extract(schedule_json, '$.review_count')
          WHEN json_extract(schedule_json, '$.interval_days') IS NOT NULL
            THEN 1
          ELSE 0
        END
    );
