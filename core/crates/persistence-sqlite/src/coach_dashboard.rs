use application::{
    ApplicationError, CoachDashboardFacts, CoachDashboardRepository, CoachEvidenceFact,
    CoachMaterialFact,
};
use domain::{
    HuntingCandidateStatus, LearningEventKind, LexicalCapability, PracticeMode, PracticeResult,
    ReviewItemStatus, ReviewRating,
};
use rusqlite::{Connection, params, params_from_iter, types::Value};

use super::{SqliteRepository, json, repo};

impl CoachDashboardRepository for SqliteRepository {
    fn coach_dashboard_facts(
        &self,
        start: u64,
        end: u64,
        as_of: u64,
    ) -> Result<CoachDashboardFacts, ApplicationError> {
        let conn = self.connection.lock();
        let practice = conn
            .query_row(
                "SELECT COUNT(*), COALESCE(SUM(CASE WHEN result=?1 THEN 1 ELSE 0 END),0)
                 FROM practice_attempts WHERE submitted_at_ms>=?2 AND submitted_at_ms<?3",
                params![json(&PracticeResult::Correct)?, start, end],
                |row| Ok((row.get::<_, u64>(0)?, row.get::<_, u64>(1)?)),
            )
            .map_err(repo)?;
        let review = conn
            .query_row(
                "SELECT COUNT(*), COALESCE(SUM(CASE WHEN rating IN (?1,?2) THEN 1 ELSE 0 END),0)
                 FROM review_attempts WHERE reviewed_at_ms>=?3 AND reviewed_at_ms<?4",
                params![
                    json(&ReviewRating::Good)?,
                    json(&ReviewRating::Easy)?,
                    start,
                    end
                ],
                |row| Ok((row.get::<_, u64>(0)?, row.get::<_, u64>(1)?)),
            )
            .map_err(repo)?;
        let listening = conn
            .query_row(
                "SELECT COUNT(*), COALESCE(SUM(CASE WHEN ended_at_ms IS NOT NULL
                    THEN MAX(0,ended_at_ms-started_at_ms) ELSE 0 END),0)
                 FROM practice_sessions
                 WHERE mode=?1 AND started_at_ms>=?2 AND started_at_ms<?3",
                params![json(&PracticeMode::Extensive)?, start, end],
                |row| Ok((row.get::<_, u64>(0)?, row.get::<_, u64>(1)?)),
            )
            .map_err(repo)?;
        let due = conn
            .query_row(
                "SELECT COUNT(*) FROM review_schedules s
                 JOIN review_items i ON i.id=s.item_id
                 WHERE i.status=?1 AND s.due_at_ms<=?2",
                params![json(&ReviewItemStatus::Active)?, as_of],
                |row| row.get::<_, u64>(0),
            )
            .map_err(repo)?;
        let candidates = conn
            .query_row(
                "SELECT COUNT(*) FROM hunting_candidates WHERE status=?1",
                [json(&HuntingCandidateStatus::Active)?],
                |row| row.get::<_, u64>(0),
            )
            .map_err(repo)?;
        let l1 = conn
            .query_row(
                "SELECT COUNT(*) FROM learning_events
                 WHERE kind=?1 AND occurred_at_ms>=?2 AND occurred_at_ms<?3",
                params![json(&LearningEventKind::L1DifficultyHit)?, start, end],
                |row| row.get::<_, u64>(0),
            )
            .map_err(repo)?;
        let capability = conn
            .query_row(
                "SELECT COUNT(*) FROM lexical_capability_history
                 WHERE capability=?1 AND changed_at_ms>=?2 AND changed_at_ms<?3",
                params![json(&LexicalCapability::Listening)?, start, end],
                |row| row.get::<_, u64>(0),
            )
            .map_err(repo)?;
        // Material trajectory and graduation eligibility are lifetime facts;
        // the dashboard action must agree with the explicit graduation call.
        let materials = material_facts(&conn, 0, end)?;

        Ok(CoachDashboardFacts {
            practice_attempts: practice.0,
            correct_practice_attempts: practice.1,
            review_attempts: review.0,
            successful_review_attempts: review.1,
            extensive_sessions: listening.0,
            extensive_listening_ms: listening.1,
            due_review_items: due,
            active_hunting_candidates: candidates,
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
    ) -> Result<Vec<CoachEvidenceFact>, ApplicationError> {
        let conn = self.connection.lock();
        evidence_for_metric(&conn, metric, start, end, limit.min(100), offset)
    }
}

fn material_facts(
    conn: &Connection,
    start: u64,
    end: u64,
) -> Result<Vec<CoachMaterialFact>, ApplicationError> {
    let mut query = conn
        .prepare(
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
                    COALESCE(json_extract(c.calibration_json,'$.practice_correct'),0),
                    json_extract(i.intent,'$')
             FROM reports r
             LEFT JOIN content_fit_calibrations c ON c.subject_kind='media' AND c.subject_id=r.media_id
             LEFT JOIN media_triage_intents i ON i.media_id=r.media_id
             GROUP BY r.media_id, r.title
             ORDER BY COUNT(*) DESC, r.title ASC LIMIT 50",
        )
        .map_err(repo)?;
    query
        .query_map(
            params![json(&LearningEventKind::ListeningCompleted)?, start, end],
            |row| {
                Ok(CoachMaterialFact {
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
        .map_err(repo)
}

fn evidence_for_metric(
    conn: &Connection,
    metric: &str,
    start: u64,
    end: u64,
    limit: u32,
    offset: u32,
) -> Result<Vec<CoachEvidenceFact>, ApplicationError> {
    let (sql, mut query_params, source_kind) = match metric {
        "practice_attempts" => (
            "SELECT id,submitted_at_ms,result FROM practice_attempts
             WHERE submitted_at_ms>=?1 AND submitted_at_ms<?2
             ORDER BY submitted_at_ms DESC LIMIT ?3 OFFSET ?4",
            vec![],
            "practice_attempt",
        ),
        "correct_practice_attempts" => (
            "SELECT id,submitted_at_ms,result FROM practice_attempts
             WHERE submitted_at_ms>=?1 AND submitted_at_ms<?2 AND result=?5
             ORDER BY submitted_at_ms DESC LIMIT ?3 OFFSET ?4",
            vec![Value::Text(json(&PracticeResult::Correct)?)],
            "practice_attempt",
        ),
        "review_attempts" => (
            "SELECT id,reviewed_at_ms,rating FROM review_attempts
             WHERE reviewed_at_ms>=?1 AND reviewed_at_ms<?2
             ORDER BY reviewed_at_ms DESC LIMIT ?3 OFFSET ?4",
            vec![],
            "review_attempt",
        ),
        "successful_review_attempts" => (
            "SELECT id,reviewed_at_ms,rating FROM review_attempts
             WHERE reviewed_at_ms>=?1 AND reviewed_at_ms<?2 AND rating IN (?5,?6)
             ORDER BY reviewed_at_ms DESC LIMIT ?3 OFFSET ?4",
            vec![
                Value::Text(json(&ReviewRating::Good)?),
                Value::Text(json(&ReviewRating::Easy)?),
            ],
            "review_attempt",
        ),
        "extensive_sessions" | "extensive_listening_ms" => (
            "SELECT id,started_at_ms,mode FROM practice_sessions
             WHERE mode=?5 AND started_at_ms>=?1 AND started_at_ms<?2
             ORDER BY started_at_ms DESC LIMIT ?3 OFFSET ?4",
            vec![Value::Text(json(&PracticeMode::Extensive)?)],
            "listening_session",
        ),
        "listening_capability_changes" => (
            "SELECT id,changed_at_ms,change_kind FROM lexical_capability_history
             WHERE capability=?5 AND changed_at_ms>=?1 AND changed_at_ms<?2
             ORDER BY changed_at_ms DESC LIMIT ?3 OFFSET ?4",
            vec![Value::Text(json(&LexicalCapability::Listening)?)],
            "capability_history",
        ),
        "l1_difficulty_hits" => (
            "SELECT id,occurred_at_ms,event_json FROM learning_events
             WHERE kind=?5 AND occurred_at_ms>=?1 AND occurred_at_ms<?2
             ORDER BY occurred_at_ms DESC LIMIT ?3 OFFSET ?4",
            vec![Value::Text(json(&LearningEventKind::L1DifficultyHit)?)],
            "learning_event",
        ),
        _ => {
            return Err(ApplicationError::Validation(
                "unknown listening coach metric",
            ));
        }
    };
    let mut parameters = vec![
        Value::Integer(start as i64),
        Value::Integer(end as i64),
        Value::Integer(i64::from(limit)),
        Value::Integer(i64::from(offset)),
    ];
    parameters.append(&mut query_params);
    let mut statement = conn.prepare(sql).map_err(repo)?;
    let mut rows = statement
        .query(params_from_iter(parameters))
        .map_err(repo)?;
    let mut result = Vec::new();
    while let Some(row) = rows.next().map_err(repo)? {
        let (id, occurred_at_ms, value) = (
            row.get::<_, String>(0).map_err(repo)?,
            row.get::<_, u64>(1).map_err(repo)?,
            row.get::<_, String>(2).map_err(repo)?,
        );
        let snapshot = if source_kind == "learning_event" {
            value.clone()
        } else {
            String::new()
        };
        result.push(CoachEvidenceFact {
            id,
            occurred_at_ms,
            result: value,
            source_kind: source_kind.into(),
            snapshot,
            source_available: true,
            unavailable_reason: None,
        });
    }
    Ok(result)
}
