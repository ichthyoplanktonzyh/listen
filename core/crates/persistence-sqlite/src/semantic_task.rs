use application::{ApplicationError, SemanticTaskRepository};
use domain::*;
use rusqlite::{OptionalExtension, Row, params};

use super::{SqliteRepository, from_json, json, repo};

fn rubric_from_row(row: &Row<'_>) -> rusqlite::Result<SemanticRubric> {
    from_json(&row.get::<_, String>(0)?)
}

fn attempt_from_row(row: &Row<'_>) -> rusqlite::Result<SemanticTaskAttempt> {
    from_json(&row.get::<_, String>(0)?)
}

fn judgment_from_row(row: &Row<'_>) -> rusqlite::Result<SemanticJudgment> {
    from_json(&row.get::<_, String>(0)?)
}

impl SemanticTaskRepository for SqliteRepository {
    fn save_semantic_rubric(
        &self,
        rubric: &SemanticRubric,
    ) -> Result<SemanticRubric, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO semantic_rubrics
                 (id,version,purpose,media_id,start_ms,end_ms,source_language,
                  response_language,source_sha256,created_at_ms,rubric_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)",
                params![
                    rubric.id.as_str(),
                    rubric.version,
                    json(&rubric.purpose)?,
                    rubric.source.media_id.as_ref().map(MediaId::as_str),
                    rubric.source.start_ms,
                    rubric.source.end_ms,
                    rubric.source.language.as_str(),
                    rubric.response_language.as_str(),
                    transcript_sha256(&rubric.source.transcript_snapshot),
                    rubric.created_at_ms,
                    json(rubric)?,
                ],
            )
            .map_err(repo)?;
        Ok(rubric.clone())
    }

    fn get_semantic_rubric(
        &self,
        id: &SemanticRubricId,
        version: u32,
    ) -> Result<Option<SemanticRubric>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT rubric_json FROM semantic_rubrics WHERE id=?1 AND version=?2",
                params![id.as_str(), version],
                rubric_from_row,
            )
            .optional()
            .map_err(repo)
    }

    fn latest_semantic_rubric(
        &self,
        id: &SemanticRubricId,
    ) -> Result<Option<SemanticRubric>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT rubric_json FROM semantic_rubrics
                 WHERE id=?1 ORDER BY version DESC LIMIT 1",
                [id.as_str()],
                rubric_from_row,
            )
            .optional()
            .map_err(repo)
    }

    fn save_semantic_attempt(
        &self,
        attempt: &SemanticTaskAttempt,
    ) -> Result<SemanticTaskAttempt, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO semantic_task_attempts
                 (id,kind,rubric_id,rubric_version,status,started_at_ms,attempt_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)",
                params![
                    attempt.id.as_str(),
                    json(&attempt.kind)?,
                    attempt.rubric_id.as_str(),
                    attempt.rubric_version,
                    json(&attempt.status)?,
                    attempt.started_at_ms,
                    json(attempt)?,
                ],
            )
            .map_err(repo)?;
        Ok(attempt.clone())
    }

    fn get_semantic_attempt(
        &self,
        id: &SemanticTaskAttemptId,
    ) -> Result<Option<SemanticTaskAttempt>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT attempt_json FROM semantic_task_attempts WHERE id=?1",
                [id.as_str()],
                attempt_from_row,
            )
            .optional()
            .map_err(repo)
    }

    fn list_semantic_attempts_for_rubric(
        &self,
        rubric_id: &SemanticRubricId,
    ) -> Result<Vec<SemanticTaskAttempt>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(
                "SELECT attempt_json FROM semantic_task_attempts
                 WHERE rubric_id=?1 ORDER BY started_at_ms ASC, id ASC",
            )
            .map_err(repo)?;
        let attempts = statement
            .query_map([rubric_id.as_str()], attempt_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(attempts)
    }

    fn save_semantic_judgment(
        &self,
        judgment: &SemanticJudgment,
    ) -> Result<SemanticJudgment, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO semantic_judgments
                 (id,attempt_id,response_revision,rubric_id,rubric_version,
                  abstained,created_at_ms,judgment_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
                params![
                    judgment.id.as_str(),
                    judgment.attempt_id.as_str(),
                    judgment.response_revision,
                    judgment.rubric_id.as_str(),
                    judgment.rubric_version,
                    judgment.abstain.is_some(),
                    judgment.created_at_ms,
                    json(judgment)?,
                ],
            )
            .map_err(repo)?;
        Ok(judgment.clone())
    }

    fn get_semantic_judgment(
        &self,
        id: &SemanticJudgmentId,
    ) -> Result<Option<SemanticJudgment>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT judgment_json FROM semantic_judgments WHERE id=?1",
                [id.as_str()],
                judgment_from_row,
            )
            .optional()
            .map_err(repo)
    }

    fn list_semantic_judgments_for_attempt(
        &self,
        attempt_id: &SemanticTaskAttemptId,
    ) -> Result<Vec<SemanticJudgment>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(
                "SELECT judgment_json FROM semantic_judgments
                 WHERE attempt_id=?1 ORDER BY created_at_ms ASC, id ASC",
            )
            .map_err(repo)?;
        let judgments = statement
            .query_map([attempt_id.as_str()], judgment_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(judgments)
    }

    fn save_judgment_adjudication(
        &self,
        adjudication: &JudgmentAdjudication,
    ) -> Result<JudgmentAdjudication, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO judgment_adjudications
                 (id,judgment_id,point_id,occurred_at_ms,adjudication_json)
                 VALUES (?1,?2,?3,?4,?5)",
                params![
                    adjudication.id.as_str(),
                    adjudication.judgment_id.as_str(),
                    adjudication.point_id,
                    adjudication.occurred_at_ms,
                    json(adjudication)?,
                ],
            )
            .map_err(repo)?;
        Ok(adjudication.clone())
    }

    fn list_judgment_adjudications(
        &self,
        judgment_id: &SemanticJudgmentId,
    ) -> Result<Vec<JudgmentAdjudication>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(
                "SELECT adjudication_json FROM judgment_adjudications
                 WHERE judgment_id=?1 ORDER BY occurred_at_ms ASC, id ASC",
            )
            .map_err(repo)?;
        let adjudications = statement
            .query_map([judgment_id.as_str()], |row| {
                from_json(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(adjudications)
    }
}
