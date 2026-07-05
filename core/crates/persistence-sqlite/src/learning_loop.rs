use application::{
    ApplicationError, LearningEventRepository, ListeningInboxRepository, PracticeRepository,
    ReviewRepository,
};
use domain::*;
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl PracticeRepository for SqliteRepository {
    fn create_practice_session(
        &self,
        session: &PracticeSession,
    ) -> Result<PracticeSession, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            // Query columns are projections of the JSON snapshot; every upsert
            // must rewrite all of them together or column-filtered queries
            // diverge from the stored document.
            "INSERT INTO practice_sessions
             (id,mode,media_id,track_id,started_at_ms,ended_at_ms,session_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7)
             ON CONFLICT(id) DO UPDATE SET
               mode=excluded.mode,
               media_id=excluded.media_id,
               track_id=excluded.track_id,
               started_at_ms=excluded.started_at_ms,
               ended_at_ms=excluded.ended_at_ms,
               session_json=excluded.session_json",
            params![
                session.id.as_str(),
                json(&session.mode)?,
                session.media_id.as_ref().map(|value| value.as_str()),
                session.track_id.as_ref().map(|value| value.as_str()),
                session.started_at_ms,
                session.ended_at_ms,
                json(session)?,
            ],
        )
        .map_err(repo)?;
        Ok(session.clone())
    }

    fn get_practice_session(
        &self,
        id: &PracticeSessionId,
    ) -> Result<Option<PracticeSession>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT session_json FROM practice_sessions WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn create_practice_item(&self, item: &PracticeItem) -> Result<PracticeItem, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            "INSERT INTO practice_items
             (id,session_id,kind,target_kind,created_at_ms,item_json)
             VALUES (?1,?2,?3,?4,?5,?6)
             ON CONFLICT(id) DO UPDATE SET
               session_id=excluded.session_id,
               kind=excluded.kind,
               target_kind=excluded.target_kind,
               created_at_ms=excluded.created_at_ms,
               item_json=excluded.item_json",
            params![
                item.id.as_str(),
                item.session_id.as_ref().map(|value| value.as_str()),
                json(&item.kind)?,
                json(&item.target.kind)?,
                item.created_at_ms,
                json(item)?,
            ],
        )
        .map_err(repo)?;
        Ok(item.clone())
    }

    fn get_practice_item(
        &self,
        id: &PracticeItemId,
    ) -> Result<Option<PracticeItem>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT item_json FROM practice_items WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_practice_items_for_session(
        &self,
        session_id: &PracticeSessionId,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<PracticeItem>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT item_json FROM practice_items
                 WHERE session_id=?1
                 ORDER BY created_at_ms ASC
                 LIMIT ?2 OFFSET ?3",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![session_id.as_str(), limit.min(500), offset],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn create_practice_attempt(
        &self,
        attempt: &PracticeAttempt,
    ) -> Result<PracticeAttempt, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            "INSERT INTO practice_attempts
             (id,item_id,result,submitted_at_ms,attempt_json)
             VALUES (?1,?2,?3,?4,?5)
             ON CONFLICT(id) DO UPDATE SET
               item_id=excluded.item_id,
               result=excluded.result,
               submitted_at_ms=excluded.submitted_at_ms,
               attempt_json=excluded.attempt_json",
            params![
                attempt.id.as_str(),
                attempt.item_id.as_str(),
                json(&attempt.result)?,
                attempt.submitted_at_ms,
                json(attempt)?,
            ],
        )
        .map_err(repo)?;
        Ok(attempt.clone())
    }

    fn get_practice_attempt(
        &self,
        id: &PracticeAttemptId,
    ) -> Result<Option<PracticeAttempt>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT attempt_json FROM practice_attempts WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_practice_attempts_for_item(
        &self,
        item_id: &PracticeItemId,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<PracticeAttempt>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT attempt_json FROM practice_attempts
                 WHERE item_id=?1
                 ORDER BY submitted_at_ms ASC
                 LIMIT ?2 OFFSET ?3",
            )
            .map_err(repo)?;
        statement
            .query_map(params![item_id.as_str(), limit.min(500), offset], |row| {
                from_json(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
}

impl ReviewRepository for SqliteRepository {
    fn create_review_item(&self, item: &ReviewItem) -> Result<ReviewItem, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            "INSERT INTO review_items
             (id,source_kind,status,created_at_ms,updated_at_ms,item_json)
             VALUES (?1,?2,?3,?4,?5,?6)
             ON CONFLICT(id) DO UPDATE SET
               source_kind=excluded.source_kind,
               status=excluded.status,
               created_at_ms=excluded.created_at_ms,
               updated_at_ms=excluded.updated_at_ms,
               item_json=excluded.item_json",
            params![
                item.id.as_str(),
                json(&item.source.kind)?,
                json(&item.status)?,
                item.created_at_ms,
                item.updated_at_ms,
                json(item)?,
            ],
        )
        .map_err(repo)?;
        Ok(item.clone())
    }

    fn get_review_item(&self, id: &ReviewItemId) -> Result<Option<ReviewItem>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT item_json FROM review_items WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_review_items(
        &self,
        status: Option<ReviewItemStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ReviewItem>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        if let Some(status) = status {
            let mut statement = conn
                .prepare(
                    "SELECT item_json FROM review_items
                     WHERE status=?1
                     ORDER BY updated_at_ms DESC
                     LIMIT ?2 OFFSET ?3",
                )
                .map_err(repo)?;
            statement
                .query_map(params![json(&status)?, limit.min(200), offset], |row| {
                    from_json(&row.get::<_, String>(0)?)
                })
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        } else {
            let mut statement = conn
                .prepare(
                    "SELECT item_json FROM review_items
                     ORDER BY updated_at_ms DESC
                     LIMIT ?1 OFFSET ?2",
                )
                .map_err(repo)?;
            statement
                .query_map(params![limit.min(200), offset], |row| {
                    from_json(&row.get::<_, String>(0)?)
                })
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        }
    }

    fn create_review_attempt(
        &self,
        attempt: &ReviewAttempt,
    ) -> Result<ReviewAttempt, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            "INSERT INTO review_attempts
             (id,item_id,reviewed_at_ms,rating,attempt_json)
             VALUES (?1,?2,?3,?4,?5)
             ON CONFLICT(id) DO UPDATE SET
               item_id=excluded.item_id,
               reviewed_at_ms=excluded.reviewed_at_ms,
               rating=excluded.rating,
               attempt_json=excluded.attempt_json",
            params![
                attempt.id.as_str(),
                attempt.item_id.as_str(),
                attempt.reviewed_at_ms,
                json(&attempt.rating)?,
                json(attempt)?,
            ],
        )
        .map_err(repo)?;
        Ok(attempt.clone())
    }

    fn get_review_attempt(
        &self,
        id: &ReviewAttemptId,
    ) -> Result<Option<ReviewAttempt>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT attempt_json FROM review_attempts WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn save_review_schedule(
        &self,
        schedule: &ReviewSchedule,
    ) -> Result<ReviewSchedule, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            "INSERT INTO review_schedules (item_id,due_at_ms,algorithm,schedule_json)
             VALUES (?1,?2,?3,?4)
             ON CONFLICT(item_id) DO UPDATE SET
               due_at_ms=excluded.due_at_ms,
               algorithm=excluded.algorithm,
               schedule_json=excluded.schedule_json",
            params![
                schedule.item_id.as_str(),
                schedule.due_at_ms,
                schedule.algorithm,
                json(schedule)?,
            ],
        )
        .map_err(repo)?;
        Ok(schedule.clone())
    }

    fn get_review_schedule(
        &self,
        item_id: &ReviewItemId,
    ) -> Result<Option<ReviewSchedule>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT schedule_json FROM review_schedules WHERE item_id=?1",
            [item_id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_due_review_items(
        &self,
        due_at_or_before_ms: u64,
        limit: u32,
    ) -> Result<Vec<(ReviewItem, ReviewSchedule)>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT i.item_json, s.schedule_json
                 FROM review_schedules s
                 JOIN review_items i ON i.id=s.item_id
                 WHERE i.status=?1 AND s.due_at_ms<=?2
                 ORDER BY s.due_at_ms ASC, i.created_at_ms ASC
                 LIMIT ?3",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![
                    json(&ReviewItemStatus::Active)?,
                    due_at_or_before_ms,
                    limit.min(100)
                ],
                |row| {
                    Ok((
                        from_json(&row.get::<_, String>(0)?)?,
                        from_json(&row.get::<_, String>(1)?)?,
                    ))
                },
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
}

impl LearningEventRepository for SqliteRepository {
    fn append_learning_event(
        &self,
        event: &LearningEvent,
    ) -> Result<LearningEvent, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            "INSERT OR IGNORE INTO learning_events
             (id,occurred_at_ms,kind,subject_kind,subject_id,session_id,event_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7)",
            params![
                event.id.as_str(),
                event.occurred_at_ms,
                json(&event.kind)?,
                json(&event.subject.kind)?,
                event.subject.id.as_str(),
                event.session_id.as_ref().map(|value| value.as_str()),
                json(event)?,
            ],
        )
        .map_err(repo)?;
        Ok(event.clone())
    }

    fn list_learning_events(
        &self,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LearningEvent>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT event_json FROM learning_events
                 ORDER BY occurred_at_ms DESC
                 LIMIT ?1 OFFSET ?2",
            )
            .map_err(repo)?;
        statement
            .query_map(params![limit.min(500), offset], |row| {
                from_json(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn list_learning_events_for_session(
        &self,
        session_id: &PracticeSessionId,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LearningEvent>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT event_json FROM learning_events
                 WHERE session_id=?1
                 ORDER BY occurred_at_ms ASC
                 LIMIT ?2 OFFSET ?3",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![session_id.as_str(), limit.min(1000), offset],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
}

impl ListeningInboxRepository for SqliteRepository {
    fn upsert_listening_inbox_item(
        &self,
        item: &ListeningInboxItem,
    ) -> Result<ListeningInboxItem, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            "INSERT INTO listening_inbox_items
             (id,session_id,media_id,track_id,status,captured_at_ms,updated_at_ms,expires_at_ms,item_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)
             ON CONFLICT(id) DO UPDATE SET
               session_id=excluded.session_id,
               media_id=excluded.media_id,
               track_id=excluded.track_id,
               status=excluded.status,
               captured_at_ms=excluded.captured_at_ms,
               updated_at_ms=excluded.updated_at_ms,
               expires_at_ms=excluded.expires_at_ms,
               item_json=excluded.item_json",
            params![
                item.id.as_str(),
                item.session_id.as_ref().map(|value| value.as_str()),
                item.media_id.as_ref().map(|value| value.as_str()),
                item.track_id.as_ref().map(|value| value.as_str()),
                json(&item.status)?,
                item.captured_at_ms,
                item.updated_at_ms,
                item.expires_at_ms,
                json(item)?,
            ],
        )
        .map_err(repo)?;
        Ok(item.clone())
    }

    fn get_listening_inbox_item(
        &self,
        id: &ListeningInboxItemId,
    ) -> Result<Option<ListeningInboxItem>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT item_json FROM listening_inbox_items WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_listening_inbox_items(
        &self,
        status: Option<ListeningInboxStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ListeningInboxItem>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        if let Some(status) = status {
            let mut statement = conn
                .prepare(
                    "SELECT item_json FROM listening_inbox_items
                     WHERE status=?1
                     ORDER BY captured_at_ms DESC
                     LIMIT ?2 OFFSET ?3",
                )
                .map_err(repo)?;
            statement
                .query_map(params![json(&status)?, limit.min(200), offset], |row| {
                    from_json(&row.get::<_, String>(0)?)
                })
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        } else {
            let mut statement = conn
                .prepare(
                    "SELECT item_json FROM listening_inbox_items
                     ORDER BY captured_at_ms DESC
                     LIMIT ?1 OFFSET ?2",
                )
                .map_err(repo)?;
            statement
                .query_map(params![limit.min(200), offset], |row| {
                    from_json(&row.get::<_, String>(0)?)
                })
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        }
    }
}
