use application::{
    ApplicationError, CoachChannelFacts, CoachDashboardFacts, CoachDashboardRepository,
};
use domain::{
    HuntingCandidateStatus, LanguageCode, LearningEventKind, LexicalCapability, PracticeMode,
    PracticeResult, ReviewItemStatus, ReviewRating,
};
use rusqlite::{Connection, params};

use super::{SqliteRepository, json, repo};

impl CoachDashboardRepository for SqliteRepository {
    fn coach_dashboard_facts(
        &self,
        language: &LanguageCode,
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
        let materials = material_facts(&conn, start, end)?;
        let channels = ["listening", "reading", "speaking", "writing"]
            .into_iter()
            .map(|channel| channel_facts(&conn, language, channel, start, end))
            .collect::<Result<Vec<_>, _>>()?;
        let cross_modal_gap_count = cross_modal_gap_count(&conn, language)?;
        let personal_expression_asset_count = conn
            .query_row(
                "SELECT COUNT(*) FROM user_sentence_patterns WHERE language=?1",
                [language.as_str()],
                |row| row.get::<_, u64>(0),
            )
            .map_err(repo)?;
        let llm_provider_profile_count = conn
            .query_row("SELECT COUNT(*) FROM llm_provider_profiles", [], |row| {
                row.get::<_, u64>(0)
            })
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
            channels,
            cross_modal_gap_count,
            personal_expression_asset_count,
            llm_provider_profile_count,
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
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        if let Some((channel, fact)) = metric.split_once('_')
            && matches!(channel, "listening" | "reading" | "speaking" | "writing")
        {
            return channel_evidence(&conn, channel, fact, start, end, limit, offset);
        }
        basic_evidence(&conn, metric, start, end, limit, offset)
    }
}

fn material_facts(
    conn: &Connection,
    start: u64,
    end: u64,
) -> Result<Vec<application::CoachMaterialFact>, ApplicationError> {
    let mut query = conn.prepare(
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
         ORDER BY COUNT(*) DESC, r.title ASC LIMIT 50",
    ).map_err(repo)?;
    query
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
        .map_err(repo)
}

fn task_kind_sql(channel: &str) -> &'static str {
    match channel {
        "listening" => "'\"l1_retelling\"'",
        "reading" => "'\"reading_comprehension\"'",
        "speaking" => "'\"l2_retelling\"','\"role_reply\"'",
        "writing" => {
            "'\"dictogloss\"','\"one_sentence_summary\"','\"summary\"','\"opinion_response\"'"
        }
        _ => "''",
    }
}

fn channel_facts(
    conn: &Connection,
    language: &LanguageCode,
    channel: &str,
    start: u64,
    end: u64,
) -> Result<CoachChannelFacts, ApplicationError> {
    let kinds = task_kind_sql(channel);
    let attempts = conn.query_row(
        &format!("SELECT COUNT(*) FROM semantic_task_attempts WHERE kind IN ({kinds}) AND status='\"completed\"' AND started_at_ms>=?1 AND started_at_ms<?2"),
        params![start, end], |row| row.get::<_, u64>(0)).map_err(repo)?;
    let judgments = conn.query_row(
        &format!("SELECT COUNT(*) FROM semantic_judgments j JOIN semantic_task_attempts a ON a.id=j.attempt_id WHERE a.kind IN ({kinds}) AND j.created_at_ms>=?1 AND j.created_at_ms<?2"),
        params![start, end], |row| row.get::<_, u64>(0)).map_err(repo)?;
    let adjudications = conn.query_row(
        &format!("SELECT COUNT(*) FROM judgment_adjudications d JOIN semantic_judgments j ON j.id=d.judgment_id JOIN semantic_task_attempts a ON a.id=j.attempt_id WHERE a.kind IN ({kinds}) AND d.occurred_at_ms>=?1 AND d.occurred_at_ms<?2"),
        params![start, end], |row| row.get::<_, u64>(0)).map_err(repo)?;
    let capability = format!("\"{channel}\"");
    let observations = conn.query_row(
        "SELECT COUNT(*) FROM learning_observations WHERE capability=?1 AND occurred_at_ms>=?2 AND occurred_at_ms<?3",
        params![capability, start, end], |row| row.get::<_, u64>(0)).map_err(repo)?;
    let proposals = conn.query_row(
        "SELECT COUNT(*) FROM projection_proposals WHERE capability=?1 AND created_at_ms>=?2 AND created_at_ms<?3",
        params![capability, start, end], |row| row.get::<_, u64>(0)).map_err(repo)?;
    let confirmed = conn.query_row(
        "SELECT COUNT(*) FROM projection_decisions d JOIN projection_proposals p ON p.id=d.proposal_id WHERE p.capability=?1 AND d.decided_at_ms>=?2 AND d.decided_at_ms<?3 AND json_extract(d.decision_json,'$.decision')='confirm'",
        params![capability, start, end], |row| row.get::<_, u64>(0)).map_err(repo)?;
    let changes = conn.query_row(
        "SELECT COUNT(*) FROM lexical_capability_history WHERE capability=?1 AND changed_at_ms>=?2 AND changed_at_ms<?3",
        params![capability, start, end], |row| row.get::<_, u64>(0)).map_err(repo)?;
    let personal_attempts = if matches!(channel, "speaking" | "writing") {
        conn.query_row(
            "SELECT COUNT(*) FROM personal_expression_attempts WHERE channel=?1 AND completed_at_ms>=?2 AND completed_at_ms<?3",
            params![channel, start, end], |row| row.get::<_, u64>(0)).map_err(repo)?
    } else {
        0
    };
    let assessments = conn.query_row(
        "SELECT COALESCE(SUM(effective='acquired'),0), COALESCE(SUM(effective='not_acquired'),0), COALESCE(SUM(effective IS NULL),0)
         FROM (
           SELECT e.id, COALESCE(json_extract(s.override_json,'$.conclusion'), json_extract(s.projection_json,'$.conclusion')) effective
           FROM lexical_entries e
           LEFT JOIN lexical_capability_states s ON s.lexical_entry_id=e.id AND s.sense_id='' AND s.capability=?1
           WHERE e.language=?2 AND e.kind='\"word\"'
         )",
        params![capability, language.as_str()],
        |row| Ok((row.get::<_, u64>(0)?, row.get::<_, u64>(1)?, row.get::<_, u64>(2)?)),
    ).map_err(repo)?;
    Ok(CoachChannelFacts {
        channel: channel.into(),
        completed_attempts: attempts,
        supporting_judgments: judgments,
        adjudications,
        observations,
        projection_proposals: proposals,
        confirmed_projections: confirmed,
        capability_changes: changes,
        personal_expression_attempts: personal_attempts,
        acquired_entries: assessments.0,
        not_acquired_entries: assessments.1,
        unassessed_entries: assessments.2,
    })
}

fn cross_modal_gap_count(
    conn: &Connection,
    language: &LanguageCode,
) -> Result<u64, ApplicationError> {
    conn.query_row(
        "WITH states AS (
           SELECT e.id,
             MAX(CASE WHEN s.capability='\"reading\"' THEN COALESCE(json_extract(s.override_json,'$.conclusion'),json_extract(s.projection_json,'$.conclusion')) END) reading,
             MAX(CASE WHEN s.capability='\"listening\"' THEN COALESCE(json_extract(s.override_json,'$.conclusion'),json_extract(s.projection_json,'$.conclusion')) END) listening,
             MAX(CASE WHEN s.capability='\"speaking\"' THEN COALESCE(json_extract(s.override_json,'$.conclusion'),json_extract(s.projection_json,'$.conclusion')) END) speaking,
             MAX(CASE WHEN s.capability='\"writing\"' THEN COALESCE(json_extract(s.override_json,'$.conclusion'),json_extract(s.projection_json,'$.conclusion')) END) writing
           FROM lexical_entries e LEFT JOIN lexical_capability_states s ON s.lexical_entry_id=e.id AND s.sense_id=''
           WHERE e.language=?1 AND e.kind='\"word\"' GROUP BY e.id
         )
         SELECT COUNT(*) FROM states
         WHERE (reading='acquired' AND listening='acquired' AND speaking='not_acquired'
                AND EXISTS (SELECT 1 FROM learning_observations o WHERE o.lexical_entry_id=states.id AND o.capability='\"speaking\"'))
            OR (reading='acquired' AND listening='acquired' AND speaking IS NOT 'not_acquired' AND writing='not_acquired'
                AND EXISTS (SELECT 1 FROM learning_observations o WHERE o.lexical_entry_id=states.id AND o.capability='\"writing\"'))
            OR (reading='acquired' AND listening='not_acquired'
                AND EXISTS (SELECT 1 FROM learning_observations o WHERE o.lexical_entry_id=states.id AND o.capability='\"listening\"'))
            OR (reading='not_acquired'
                AND EXISTS (SELECT 1 FROM learning_observations o WHERE o.lexical_entry_id=states.id AND o.capability='\"reading\"'))",
        [language.as_str()],
        |row| row.get::<_, u64>(0),
    ).map_err(repo)
}

fn basic_evidence(
    conn: &Connection,
    metric: &str,
    start: u64,
    end: u64,
    limit: u32,
    offset: u32,
) -> Result<Vec<application::CoachEvidenceFact>, ApplicationError> {
    let (sql, filter, source_kind) = match metric {
        "practice_attempts" => (
            "SELECT id,submitted_at_ms,result FROM practice_attempts WHERE submitted_at_ms>=?1 AND submitted_at_ms<?2 ORDER BY submitted_at_ms DESC LIMIT ?3 OFFSET ?4",
            None,
            "practice_attempt",
        ),
        "correct_practice_attempts" => (
            "SELECT id,submitted_at_ms,result FROM practice_attempts WHERE submitted_at_ms>=?1 AND submitted_at_ms<?2 AND result=?5 ORDER BY submitted_at_ms DESC LIMIT ?3 OFFSET ?4",
            Some(json(&PracticeResult::Correct)?),
            "practice_attempt",
        ),
        "review_attempts" => (
            "SELECT id,reviewed_at_ms,rating FROM review_attempts WHERE reviewed_at_ms>=?1 AND reviewed_at_ms<?2 ORDER BY reviewed_at_ms DESC LIMIT ?3 OFFSET ?4",
            None,
            "review_attempt",
        ),
        "successful_review_attempts" => (
            "SELECT id,reviewed_at_ms,rating FROM review_attempts WHERE reviewed_at_ms>=?1 AND reviewed_at_ms<?2 AND rating IN (?5,?6) ORDER BY reviewed_at_ms DESC LIMIT ?3 OFFSET ?4",
            Some(json(&ReviewRating::Good)?),
            "review_attempt",
        ),
        "extensive_sessions" | "extensive_listening_ms" => (
            "SELECT id,started_at_ms,CASE WHEN ended_at_ms IS NULL THEN 'active' ELSE 'completed' END FROM practice_sessions WHERE started_at_ms>=?1 AND started_at_ms<?2 AND mode=?5 ORDER BY started_at_ms DESC LIMIT ?3 OFFSET ?4",
            Some(json(&PracticeMode::Extensive)?),
            "practice_session",
        ),
        "listening_capability_changes" => (
            "SELECT id,changed_at_ms,change_kind FROM lexical_capability_history WHERE changed_at_ms>=?1 AND changed_at_ms<?2 AND capability=?5 ORDER BY changed_at_ms DESC LIMIT ?3 OFFSET ?4",
            Some(json(&LexicalCapability::Listening)?),
            "capability_history",
        ),
        "l1_difficulty_hits" => (
            "SELECT id,occurred_at_ms,subject_id FROM learning_events WHERE occurred_at_ms>=?1 AND occurred_at_ms<?2 AND kind=?5 ORDER BY occurred_at_ms DESC LIMIT ?3 OFFSET ?4",
            Some(json(&LearningEventKind::L1DifficultyHit)?),
            "learning_event",
        ),
        _ => return Err(ApplicationError::Validation("unsupported coach metric")),
    };
    let mut statement = conn.prepare(sql).map_err(repo)?;
    let map = |row: &rusqlite::Row<'_>| map_basic_evidence(row, source_kind);
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
                map,
            )
            .map_err(repo)?
    } else if let Some(filter) = filter {
        statement
            .query_map(params![start, end, limit.min(100), offset, filter], map)
            .map_err(repo)?
    } else {
        statement
            .query_map(params![start, end, limit.min(100), offset], map)
            .map_err(repo)?
    };
    rows.collect::<Result<Vec<_>, _>>().map_err(repo)
}

fn channel_evidence(
    conn: &Connection,
    channel: &str,
    fact: &str,
    start: u64,
    end: u64,
    limit: u32,
    offset: u32,
) -> Result<Vec<application::CoachEvidenceFact>, ApplicationError> {
    let capability = format!("\"{channel}\"");
    let kinds = task_kind_sql(channel);
    let sql = match fact {
        "completed_attempts" => format!("SELECT a.id,a.started_at_ms,a.kind,COALESCE(json_extract(r.rubric_json,'$.source.transcript_snapshot'),a.kind),CASE WHEN r.media_id IS NULL OR m.id IS NOT NULL THEN 1 ELSE 0 END,CASE WHEN r.media_id IS NOT NULL AND m.id IS NULL THEN 'source_media_unavailable' END FROM semantic_task_attempts a JOIN semantic_rubrics r ON r.id=a.rubric_id AND r.version=a.rubric_version LEFT JOIN media_items m ON m.id=r.media_id WHERE a.kind IN ({kinds}) AND a.status='\"completed\"' AND a.started_at_ms>=?1 AND a.started_at_ms<?2 ORDER BY a.started_at_ms DESC LIMIT ?3 OFFSET ?4"),
        "supporting_judgments" => format!("SELECT j.id,j.created_at_ms,CASE WHEN j.abstained=1 THEN 'abstained' ELSE 'supporting_judgment' END,COALESCE(json_extract(r.rubric_json,'$.source.transcript_snapshot'),a.kind),CASE WHEN r.media_id IS NULL OR m.id IS NOT NULL THEN 1 ELSE 0 END,CASE WHEN r.media_id IS NOT NULL AND m.id IS NULL THEN 'source_media_unavailable' END FROM semantic_judgments j JOIN semantic_task_attempts a ON a.id=j.attempt_id JOIN semantic_rubrics r ON r.id=j.rubric_id AND r.version=j.rubric_version LEFT JOIN media_items m ON m.id=r.media_id WHERE a.kind IN ({kinds}) AND j.created_at_ms>=?1 AND j.created_at_ms<?2 ORDER BY j.created_at_ms DESC LIMIT ?3 OFFSET ?4"),
        "adjudications" => format!("SELECT d.id,d.occurred_at_ms,'user_adjudication',COALESCE(json_extract(r.rubric_json,'$.source.transcript_snapshot'),a.kind),CASE WHEN r.media_id IS NULL OR m.id IS NOT NULL THEN 1 ELSE 0 END,CASE WHEN r.media_id IS NOT NULL AND m.id IS NULL THEN 'source_media_unavailable' END FROM judgment_adjudications d JOIN semantic_judgments j ON j.id=d.judgment_id JOIN semantic_task_attempts a ON a.id=j.attempt_id JOIN semantic_rubrics r ON r.id=j.rubric_id AND r.version=j.rubric_version LEFT JOIN media_items m ON m.id=r.media_id WHERE a.kind IN ({kinds}) AND d.occurred_at_ms>=?1 AND d.occurred_at_ms<?2 ORDER BY d.occurred_at_ms DESC LIMIT ?3 OFFSET ?4"),
        "observations" => "SELECT id,occurred_at_ms,outcome,COALESCE(surface_form,'learning observation'),1,NULL FROM learning_observations WHERE capability=?5 AND occurred_at_ms>=?1 AND occurred_at_ms<?2 ORDER BY occurred_at_ms DESC LIMIT ?3 OFFSET ?4".into(),
        "projection_proposals" => "SELECT id,created_at_ms,'proposal',COALESCE(json_extract(proposal_json,'$.rationale'),'projection proposal'),1,NULL FROM projection_proposals WHERE capability=?5 AND created_at_ms>=?1 AND created_at_ms<?2 ORDER BY created_at_ms DESC LIMIT ?3 OFFSET ?4".into(),
        "confirmed_projections" => "SELECT d.id,d.decided_at_ms,'confirmed',COALESCE(json_extract(p.proposal_json,'$.rationale'),'confirmed projection'),1,NULL FROM projection_decisions d JOIN projection_proposals p ON p.id=d.proposal_id WHERE p.capability=?5 AND json_extract(d.decision_json,'$.decision')='confirm' AND d.decided_at_ms>=?1 AND d.decided_at_ms<?2 ORDER BY d.decided_at_ms DESC LIMIT ?3 OFFSET ?4".into(),
        "capability_changes" => "SELECT id,changed_at_ms,change_kind,change_kind,1,NULL FROM lexical_capability_history WHERE capability=?5 AND changed_at_ms>=?1 AND changed_at_ms<?2 ORDER BY changed_at_ms DESC LIMIT ?3 OFFSET ?4".into(),
        "personal_expression_attempts" if matches!(channel, "speaking" | "writing") => "SELECT id,completed_at_ms,'personal_expression_attempt',COALESCE(json_extract(attempt_json,'$.response_text'),'personal expression attempt'),1,NULL FROM personal_expression_attempts WHERE channel=?5 AND completed_at_ms>=?1 AND completed_at_ms<?2 ORDER BY completed_at_ms DESC LIMIT ?3 OFFSET ?4".into(),
        _ => return Err(ApplicationError::Validation("unsupported coach metric")),
    };
    let source_kind = fact.trim_end_matches('s');
    let mut statement = conn.prepare(&sql).map_err(repo)?;
    let filter = if fact == "personal_expression_attempts" {
        channel
    } else {
        capability.as_str()
    };
    if matches!(
        fact,
        "completed_attempts" | "supporting_judgments" | "adjudications"
    ) {
        statement
            .query_map(params![start, end, limit.min(100), offset], |row| {
                map_typed_evidence(row, source_kind)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    } else {
        statement
            .query_map(params![start, end, limit.min(100), offset, filter], |row| {
                map_typed_evidence(row, source_kind)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
}

fn map_basic_evidence(
    row: &rusqlite::Row<'_>,
    source_kind: &str,
) -> rusqlite::Result<application::CoachEvidenceFact> {
    let result: String = row.get(2)?;
    Ok(application::CoachEvidenceFact {
        id: row.get(0)?,
        occurred_at_ms: row.get(1)?,
        snapshot: result.clone(),
        result,
        source_kind: source_kind.into(),
        source_available: true,
        unavailable_reason: None,
    })
}

fn map_typed_evidence(
    row: &rusqlite::Row<'_>,
    source_kind: &str,
) -> rusqlite::Result<application::CoachEvidenceFact> {
    Ok(application::CoachEvidenceFact {
        id: row.get(0)?,
        occurred_at_ms: row.get(1)?,
        result: row.get(2)?,
        snapshot: row.get(3)?,
        source_available: row.get::<_, i64>(4)? != 0,
        unavailable_reason: row.get(5)?,
        source_kind: source_kind.into(),
    })
}
