use application::{
    ApplicationError, HuntingRepository, ImportedDeckSchedule, LearningEventRepository,
    ListeningInboxRepository, PracticeRepository, RecognitionUpgradeRepository, ReviewDailyLimits,
    ReviewQueueRepository,
};
use domain::{
    HuntingCandidate, HuntingCandidateId, HuntingCandidateStatus, HuntingTarget, HuntingTargetId,
    HuntingTargetStatus, LearningEvent, LearningEventKind, LearningEventSubjectKind,
    LexicalEntryId, ListeningInboxItem, ListeningInboxItemId, ListeningInboxStatus,
    PracticeAttempt, PracticeAttemptId, PracticeItem, PracticeItemId, PracticeSession,
    PracticeSessionId, RecognitionEvidence, ReviewAttempt, ReviewAttemptId, ReviewItem,
    ReviewItemId, ReviewItemStatus, ReviewSchedule, UpgradeSuggestion, UpgradeSuggestionId,
    UpgradeSuggestionStatus,
};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl PracticeRepository for SqliteRepository {
    fn create_practice_session(
        &self,
        session: &PracticeSession,
    ) -> Result<PracticeSession, ApplicationError> {
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT session_json FROM practice_sessions WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn create_practice_item(&self, item: &PracticeItem) -> Result<PracticeItem, ApplicationError> {
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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

impl ReviewQueueRepository for SqliteRepository {
    fn create_review_item(&self, item: &ReviewItem) -> Result<ReviewItem, ApplicationError> {
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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

    fn list_review_items_with_schedules(
        &self,
        limit: u32,
    ) -> Result<Vec<(ReviewItem, ReviewSchedule)>, ApplicationError> {
        let conn = self.connection.lock();
        let mut statement = conn
            .prepare(
                "SELECT i.item_json, s.schedule_json
                 FROM review_schedules s
                 JOIN review_items i ON i.id=s.item_id
                 WHERE i.status=?1
                 ORDER BY s.due_at_ms ASC, i.created_at_ms ASC
                 LIMIT ?2",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![json(&ReviewItemStatus::Active)?, limit.min(10_000)],
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

    fn review_attempt_counts_between(
        &self,
        start_ms: u64,
        end_ms: u64,
    ) -> Result<(u32, u32), ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT
               COALESCE(SUM(CASE
                 WHEN json_extract(attempt_json, '$.previous_state')='new' THEN 1 ELSE 0 END), 0),
               COALESCE(SUM(CASE
                 WHEN json_extract(attempt_json, '$.previous_state')='review'
                   OR json_extract(attempt_json, '$.previous_state') IS NULL
                 THEN 1 ELSE 0 END), 0)
             FROM review_attempts
             WHERE reviewed_at_ms>=?1 AND reviewed_at_ms<?2
               AND COALESCE(json_extract(attempt_json, '$.advances_schedule'), 1)=1",
            params![start_ms, end_ms],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .map_err(repo)
    }

    fn get_review_daily_limits(&self) -> Result<ReviewDailyLimits, ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT new_cards_per_day,reviews_per_day
             FROM review_settings WHERE singleton=1",
            [],
            |row| {
                Ok(ReviewDailyLimits {
                    new_cards: row.get(0)?,
                    reviews: row.get(1)?,
                })
            },
        )
        .map_err(repo)
    }

    fn save_review_daily_limits(
        &self,
        limits: ReviewDailyLimits,
    ) -> Result<ReviewDailyLimits, ApplicationError> {
        let conn = self.connection.lock();
        conn.execute(
            "UPDATE review_settings
             SET new_cards_per_day=?1,reviews_per_day=?2
             WHERE singleton=1",
            params![limits.new_cards, limits.reviews],
        )
        .map_err(repo)?;
        Ok(limits)
    }

    fn list_imported_deck_schedules(&self) -> Result<Vec<ImportedDeckSchedule>, ApplicationError> {
        let conn = self.connection.lock();
        let mut statement = conn
            .prepare(
                "SELECT imported.item_id,imported.guid,deck.deck_id,deck.name,deck.parent_deck_id,
                        schedule.schedule_json
                 FROM anki_review_items imported
                 JOIN anki_decks deck ON deck.deck_id=imported.deck_id
                 JOIN review_schedules schedule ON schedule.item_id=imported.item_id
                 JOIN review_items item ON item.id=imported.item_id
                 WHERE item.status=?1
                 ORDER BY deck.name, schedule.due_at_ms",
            )
            .map_err(repo)?;
        statement
            .query_map(params![json(&ReviewItemStatus::Active)?], |row| {
                Ok(ImportedDeckSchedule {
                    item_id: ReviewItemId::parse(row.get::<_, String>(0)?)
                        .map_err(super::domain_sql)?,
                    anki_guid: row.get(1)?,
                    deck_id: row.get(2)?,
                    name: row.get(3)?,
                    parent_deck_id: row.get(4)?,
                    schedule: from_json(&row.get::<_, String>(5)?)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn import_anki_package(
        &self,
        request: &application::AnkiPackageImportRequest,
    ) -> Result<application::AnkiPackageImportSummary, ApplicationError> {
        super::anki::import_package(self, request)
    }

    fn export_anki_package(
        &self,
        request: &application::AnkiPackageExportRequest,
    ) -> Result<application::AnkiPackageExportSummary, ApplicationError> {
        super::anki::export_package(self, request)
    }
}

impl HuntingRepository for SqliteRepository {
    fn upsert_hunting_candidate(
        &self,
        candidate: &HuntingCandidate,
    ) -> Result<HuntingCandidate, ApplicationError> {
        let conn = self.connection.lock();
        conn.execute(
            "INSERT INTO hunting_candidates
             (id,lexical_entry_id,review_item_id,status,failure_count,last_failed_at_ms,candidate_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7)
             ON CONFLICT(lexical_entry_id,review_item_id) DO UPDATE SET
               id=excluded.id,
               status=excluded.status,
               failure_count=excluded.failure_count,
               last_failed_at_ms=excluded.last_failed_at_ms,
               candidate_json=excluded.candidate_json",
            params![
                candidate.id.as_str(),
                candidate.lexical_entry_id.as_str(),
                candidate.review_item_id.as_str(),
                json(&candidate.status)?,
                candidate.failure_count,
                candidate.last_failed_at_ms,
                json(candidate)?,
            ],
        )
        .map_err(repo)?;
        Ok(candidate.clone())
    }

    fn get_hunting_candidate(
        &self,
        id: &HuntingCandidateId,
    ) -> Result<Option<HuntingCandidate>, ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT candidate_json FROM hunting_candidates WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_hunting_candidates(
        &self,
        status: Option<HuntingCandidateStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<HuntingCandidate>, ApplicationError> {
        let conn = self.connection.lock();
        if let Some(status) = status {
            let mut statement = conn
                .prepare(
                    "SELECT candidate_json FROM hunting_candidates
                     WHERE status=?1
                     ORDER BY last_failed_at_ms DESC
                     LIMIT ?2 OFFSET ?3",
                )
                .map_err(repo)?;
            statement
                .query_map(params![json(&status)?, limit.min(500), offset], |row| {
                    from_json(&row.get::<_, String>(0)?)
                })
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        } else {
            let mut statement = conn
                .prepare(
                    "SELECT candidate_json FROM hunting_candidates
                     ORDER BY last_failed_at_ms DESC
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
    }

    fn upsert_hunting_target(
        &self,
        target: &HuntingTarget,
    ) -> Result<HuntingTarget, ApplicationError> {
        let conn = self.connection.lock();
        conn.execute(
            "INSERT INTO hunting_targets
             (id,lexical_entry_id,status,created_at_ms,updated_at_ms,target_json)
             VALUES (?1,?2,?3,?4,?5,?6)
             ON CONFLICT(lexical_entry_id) DO UPDATE SET
               id=excluded.id,
               status=excluded.status,
               updated_at_ms=excluded.updated_at_ms,
               target_json=excluded.target_json",
            params![
                target.id.as_str(),
                target.lexical_entry_id.as_str(),
                json(&target.status)?,
                target.created_at_ms,
                target.updated_at_ms,
                json(target)?,
            ],
        )
        .map_err(repo)?;
        Ok(target.clone())
    }

    fn get_hunting_target(
        &self,
        id: &HuntingTargetId,
    ) -> Result<Option<HuntingTarget>, ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT target_json FROM hunting_targets WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_hunting_targets(
        &self,
        status: Option<HuntingTargetStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<HuntingTarget>, ApplicationError> {
        let conn = self.connection.lock();
        if let Some(status) = status {
            let mut statement = conn
                .prepare(
                    "SELECT target_json FROM hunting_targets
                     WHERE status=?1
                     ORDER BY updated_at_ms DESC, id ASC
                     LIMIT ?2 OFFSET ?3",
                )
                .map_err(repo)?;
            statement
                .query_map(params![json(&status)?, limit.min(100), offset], |row| {
                    from_json(&row.get::<_, String>(0)?)
                })
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        } else {
            let mut statement = conn
                .prepare(
                    "SELECT target_json FROM hunting_targets
                     ORDER BY updated_at_ms DESC, id ASC
                     LIMIT ?1 OFFSET ?2",
                )
                .map_err(repo)?;
            statement
                .query_map(params![limit.min(100), offset], |row| {
                    from_json(&row.get::<_, String>(0)?)
                })
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        }
    }
}

impl RecognitionUpgradeRepository for SqliteRepository {
    fn upsert_recognition_evidence(
        &self,
        evidence: &RecognitionEvidence,
    ) -> Result<RecognitionEvidence, ApplicationError> {
        let conn = self.connection.lock();
        conn.execute(
            "INSERT INTO recognition_evidence
             (id,lexical_entry_id,context_key,source_kind,occurred_at_ms,evidence_json)
             VALUES (?1,?2,?3,?4,?5,?6)
             ON CONFLICT(lexical_entry_id,context_key) DO UPDATE SET
               id=CASE WHEN excluded.occurred_at_ms>=occurred_at_ms
                       THEN excluded.id ELSE id END,
               source_kind=CASE WHEN excluded.occurred_at_ms>=occurred_at_ms
                                THEN excluded.source_kind ELSE source_kind END,
               occurred_at_ms=MAX(occurred_at_ms,excluded.occurred_at_ms),
               evidence_json=CASE WHEN excluded.occurred_at_ms>=occurred_at_ms
                                  THEN excluded.evidence_json ELSE evidence_json END",
            params![
                evidence.id.as_str(),
                evidence.lexical_entry_id.as_str(),
                evidence.context_key,
                json(&evidence.source_kind)?,
                evidence.occurred_at_ms,
                json(evidence)?,
            ],
        )
        .map_err(repo)?;
        conn.query_row(
            "SELECT evidence_json FROM recognition_evidence
             WHERE lexical_entry_id=?1 AND context_key=?2",
            params![evidence.lexical_entry_id.as_str(), evidence.context_key],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .map_err(repo)
    }

    fn list_recognition_evidence(
        &self,
        lexical_entry_id: &LexicalEntryId,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<RecognitionEvidence>, ApplicationError> {
        let conn = self.connection.lock();
        let mut statement = conn
            .prepare(
                "SELECT evidence_json FROM recognition_evidence
                 WHERE lexical_entry_id=?1
                 ORDER BY occurred_at_ms DESC
                 LIMIT ?2 OFFSET ?3",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![lexical_entry_id.as_str(), limit.min(1000), offset],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn save_upgrade_suggestion(
        &self,
        suggestion: &UpgradeSuggestion,
    ) -> Result<UpgradeSuggestion, ApplicationError> {
        let conn = self.connection.lock();
        conn.execute(
            "INSERT INTO upgrade_suggestions
             (id,lexical_entry_id,status,created_at_ms,resolved_at_ms,cooldown_until_ms,suggestion_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7)
             ON CONFLICT(id) DO UPDATE SET
               status=excluded.status,
               resolved_at_ms=excluded.resolved_at_ms,
               cooldown_until_ms=excluded.cooldown_until_ms,
               suggestion_json=excluded.suggestion_json",
            params![
                suggestion.id.as_str(),
                suggestion.lexical_entry_id.as_str(),
                json(&suggestion.status)?,
                suggestion.created_at_ms,
                suggestion.resolved_at_ms,
                suggestion.cooldown_until_ms,
                json(suggestion)?,
            ],
        )
        .map_err(repo)?;
        Ok(suggestion.clone())
    }

    fn get_upgrade_suggestion(
        &self,
        id: &UpgradeSuggestionId,
    ) -> Result<Option<UpgradeSuggestion>, ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT suggestion_json FROM upgrade_suggestions WHERE id=?1",
            [id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_upgrade_suggestions(
        &self,
        lexical_entry_id: Option<&LexicalEntryId>,
        status: Option<UpgradeSuggestionStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<UpgradeSuggestion>, ApplicationError> {
        let conn = self.connection.lock();
        let status = status.map(|value| json(&value)).transpose()?;
        let mut statement = conn
            .prepare(
                "SELECT suggestion_json FROM upgrade_suggestions
                 WHERE (?1 IS NULL OR lexical_entry_id=?1)
                   AND (?2 IS NULL OR status=?2)
                 ORDER BY created_at_ms DESC
                 LIMIT ?3 OFFSET ?4",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![
                    lexical_entry_id.map(LexicalEntryId::as_str),
                    status,
                    limit.min(500),
                    offset
                ],
                |row| from_json(&row.get::<_, String>(0)?),
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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

    fn list_event_subject_ids(
        &self,
        kind: LearningEventKind,
        subject_kind: LearningEventSubjectKind,
    ) -> Result<Vec<String>, ApplicationError> {
        let conn = self.connection.lock();
        // The kind/subject_kind columns store the serde JSON encoding
        // (quoted strings), matching append_learning_event above.
        let mut statement = conn
            .prepare(
                "SELECT DISTINCT subject_id FROM learning_events
                 WHERE kind=?1 AND subject_kind=?2",
            )
            .map_err(repo)?;
        statement
            .query_map(params![json(&kind)?, json(&subject_kind)?], |row| {
                row.get::<_, String>(0)
            })
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
