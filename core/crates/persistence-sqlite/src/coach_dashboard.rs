use application::{ApplicationError, CoachDashboardFacts, CoachDashboardRepository};
use domain::{
    HuntingCandidateStatus, LearningEventKind, LexicalCapability, PracticeMode, PracticeResult,
    ReviewItemStatus, ReviewRating,
};
use rusqlite::params;

use super::{SqliteRepository, json, repo};

impl CoachDashboardRepository for SqliteRepository {
    fn coach_dashboard_facts(
        &self,
        start: u64,
        end: u64,
        as_of: u64,
    ) -> Result<CoachDashboardFacts, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let practice = conn.query_row(
            "SELECT COUNT(*), COALESCE(SUM(CASE WHEN result=?1 THEN 1 ELSE 0 END),0) FROM practice_attempts WHERE submitted_at_ms>=?2 AND submitted_at_ms<?3",
            params![json(&PracticeResult::Correct)?, start, end], |r| Ok((r.get::<_, u64>(0)?, r.get::<_, u64>(1)?))).map_err(repo)?;
        let review = conn.query_row(
            "SELECT COUNT(*), COALESCE(SUM(CASE WHEN rating IN (?1,?2) THEN 1 ELSE 0 END),0) FROM review_attempts WHERE reviewed_at_ms>=?3 AND reviewed_at_ms<?4",
            params![json(&ReviewRating::Good)?, json(&ReviewRating::Easy)?, start, end], |r| Ok((r.get::<_, u64>(0)?, r.get::<_, u64>(1)?))).map_err(repo)?;
        let listening = conn.query_row(
            "SELECT COUNT(*), COALESCE(SUM(CASE WHEN ended_at_ms IS NOT NULL THEN MAX(0,ended_at_ms-started_at_ms) ELSE 0 END),0) FROM practice_sessions WHERE mode=?1 AND started_at_ms>=?2 AND started_at_ms<?3",
            params![json(&PracticeMode::Extensive)?, start, end], |r| Ok((r.get::<_, u64>(0)?, r.get::<_, u64>(1)?))).map_err(repo)?;
        let due = conn.query_row(
            "SELECT COUNT(*) FROM review_schedules s JOIN review_items i ON i.id=s.item_id WHERE i.status=?1 AND s.due_at_ms<=?2",
            params![json(&ReviewItemStatus::Active)?, as_of], |r| r.get::<_, u64>(0)).map_err(repo)?;
        let hunting = conn
            .query_row(
                "SELECT COUNT(*) FROM hunting_candidates WHERE status=?1",
                [json(&HuntingCandidateStatus::Active)?],
                |r| r.get::<_, u64>(0),
            )
            .map_err(repo)?;
        let l1 = conn.query_row("SELECT COUNT(*) FROM learning_events WHERE kind=?1 AND occurred_at_ms>=?2 AND occurred_at_ms<?3", params![json(&LearningEventKind::L1DifficultyHit)?, start, end], |r| r.get::<_, u64>(0)).map_err(repo)?;
        let capability = conn.query_row("SELECT COUNT(*) FROM lexical_capability_history WHERE capability=?1 AND changed_at_ms>=?2 AND changed_at_ms<?3", params![json(&LexicalCapability::Listening)?, start, end], |r| r.get::<_, u64>(0)).map_err(repo)?;
        let mut material_query = conn.prepare(
            "WITH reports AS (
               SELECT ps.media_id, m.title, e.occurred_at_ms,
                      json_extract(e.event_json,'$.payload.comprehension_report') report,
                      ROW_NUMBER() OVER (PARTITION BY ps.media_id ORDER BY e.occurred_at_ms ASC) first_rank,
                      ROW_NUMBER() OVER (PARTITION BY ps.media_id ORDER BY e.occurred_at_ms DESC) last_rank
               FROM learning_events e
               JOIN practice_sessions ps ON ps.id=e.session_id
               JOIN media_items m ON m.id=ps.media_id
               WHERE e.kind=?1 AND e.occurred_at_ms>=?2 AND e.occurred_at_ms<?3
                 AND json_extract(e.event_json,'$.payload.comprehension_report') IS NOT NULL
             )
             SELECT r.media_id, r.title, COUNT(*),
                    MAX(CASE WHEN first_rank=1 THEN report END),
                    MAX(CASE WHEN last_rank=1 THEN report END),
                    SUM(report='understood_all'), SUM(report='got_the_gist'), SUM(report='unclear'),
                    COALESCE(json_extract(c.calibration_json,'$.practice_attempts'),0),
                    COALESCE(json_extract(c.calibration_json,'$.practice_correct'),0), json_extract(i.intent,'$')
             FROM reports r
             LEFT JOIN content_fit_calibrations c ON c.subject_kind='media' AND c.subject_id=r.media_id
             LEFT JOIN media_triage_intents i ON i.media_id=r.media_id
             GROUP BY r.media_id, r.title
             ORDER BY COUNT(*) DESC, r.title ASC LIMIT 50"
        ).map_err(repo)?;
        let materials = material_query
            .query_map(
                params![json(&LearningEventKind::ListeningCompleted)?, start, end],
                |row| {
                    Ok(application::CoachMaterialFact {
                        media_id: row.get(0)?,
                        title: row.get(1)?,
                        report_count: row.get(2)?,
                        first_report: row.get(3)?,
                        latest_report: row.get(4)?,
                        reports_understood_all: row.get(5)?,
                        reports_got_the_gist: row.get(6)?,
                        reports_unclear: row.get(7)?,
                        practice_attempts: row.get(8)?,
                        practice_correct: row.get(9)?,
                        triage_intent: row.get(10)?,
                    })
                },
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(CoachDashboardFacts {
            practice_attempts: practice.0,
            correct_practice_attempts: practice.1,
            review_attempts: review.0,
            successful_review_attempts: review.1,
            extensive_sessions: listening.0,
            extensive_listening_ms: listening.1,
            due_review_items: due,
            active_hunting_candidates: hunting,
            l1_difficulty_hits: l1,
            listening_capability_changes: capability,
            materials,
        })
    }

    fn coach_evidence(
        &self,
        metric: &str,
        start: u64,
        end: u64,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<application::CoachEvidenceFact>, ApplicationError> {
        let (sql, filter) = match metric {
            "practice_attempts" => (
                "SELECT id,submitted_at_ms,result FROM practice_attempts WHERE submitted_at_ms>=?1 AND submitted_at_ms<?2 ORDER BY submitted_at_ms DESC LIMIT ?3 OFFSET ?4",
                None,
            ),
            "correct_practice_attempts" => (
                "SELECT id,submitted_at_ms,result FROM practice_attempts WHERE submitted_at_ms>=?1 AND submitted_at_ms<?2 AND result=?5 ORDER BY submitted_at_ms DESC LIMIT ?3 OFFSET ?4",
                Some(json(&PracticeResult::Correct)?),
            ),
            "review_attempts" => (
                "SELECT id,reviewed_at_ms,rating FROM review_attempts WHERE reviewed_at_ms>=?1 AND reviewed_at_ms<?2 ORDER BY reviewed_at_ms DESC LIMIT ?3 OFFSET ?4",
                None,
            ),
            "successful_review_attempts" => (
                "SELECT id,reviewed_at_ms,rating FROM review_attempts WHERE reviewed_at_ms>=?1 AND reviewed_at_ms<?2 AND rating IN (?5,?6) ORDER BY reviewed_at_ms DESC LIMIT ?3 OFFSET ?4",
                Some(json(&ReviewRating::Good)?),
            ),
            "extensive_sessions" | "extensive_listening_ms" => (
                "SELECT id,started_at_ms,CASE WHEN ended_at_ms IS NULL THEN 'active' ELSE 'completed' END FROM practice_sessions WHERE started_at_ms>=?1 AND started_at_ms<?2 AND mode=?5 ORDER BY started_at_ms DESC LIMIT ?3 OFFSET ?4",
                Some(json(&PracticeMode::Extensive)?),
            ),
            "listening_capability_changes" => (
                "SELECT id,changed_at_ms,change_kind FROM lexical_capability_history WHERE changed_at_ms>=?1 AND changed_at_ms<?2 AND capability=?5 ORDER BY changed_at_ms DESC LIMIT ?3 OFFSET ?4",
                Some(json(&LexicalCapability::Listening)?),
            ),
            "l1_difficulty_hits" => (
                "SELECT id,occurred_at_ms,subject_id FROM learning_events WHERE occurred_at_ms>=?1 AND occurred_at_ms<?2 AND kind=?5 ORDER BY occurred_at_ms DESC LIMIT ?3 OFFSET ?4",
                Some(json(&LearningEventKind::L1DifficultyHit)?),
            ),
            _ => return Err(ApplicationError::Validation("unsupported coach metric")),
        };
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn.prepare(sql).map_err(repo)?;
        let rows = if metric == "successful_review_attempts" {
            statement
                .query_map(
                    params![
                        start,
                        end,
                        limit.min(100),
                        offset,
                        filter,
                        json(&ReviewRating::Easy)?
                    ],
                    map_evidence,
                )
                .map_err(repo)?
        } else if let Some(filter) = filter {
            statement
                .query_map(
                    params![start, end, limit.min(100), offset, filter],
                    map_evidence,
                )
                .map_err(repo)?
        } else {
            statement
                .query_map(params![start, end, limit.min(100), offset], map_evidence)
                .map_err(repo)?
        };
        rows.collect::<Result<Vec<_>, _>>().map_err(repo)
    }
}

fn map_evidence(row: &rusqlite::Row<'_>) -> rusqlite::Result<application::CoachEvidenceFact> {
    Ok(application::CoachEvidenceFact {
        id: row.get(0)?,
        occurred_at_ms: row.get(1)?,
        result: row.get(2)?,
    })
}
