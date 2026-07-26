use application::{ApplicationError, SemanticTaskRepository};
use domain::{
    JudgmentAdjudication, LanguageCode, MediaId, SemanticJudgment, SemanticJudgmentId,
    SemanticRubric, SemanticRubricId, SemanticTaskAttempt, SemanticTaskAttemptId, SemanticTaskKind,
    WritingDraft, WritingFeedbackFinding, WritingFeedbackFindingId, WritingFindingDisposition,
    WritingFindingDispositionId, transcript_sha256,
};
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

fn writing_finding_from_row(row: &Row<'_>) -> rusqlite::Result<WritingFeedbackFinding> {
    from_json(&row.get::<_, String>(0)?)
}

fn writing_disposition_from_row(row: &Row<'_>) -> rusqlite::Result<WritingFindingDisposition> {
    from_json(&row.get::<_, String>(0)?)
}

impl SemanticTaskRepository for SqliteRepository {
    fn save_semantic_rubric(
        &self,
        rubric: &SemanticRubric,
    ) -> Result<SemanticRubric, ApplicationError> {
        self.connection
            .lock()
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
            .query_row(
                "SELECT rubric_json FROM semantic_rubrics
                 WHERE id=?1 ORDER BY version DESC LIMIT 1",
                [id.as_str()],
                rubric_from_row,
            )
            .optional()
            .map_err(repo)
    }

    fn find_semantic_rubric_by_source(
        &self,
        media_id: Option<&MediaId>,
        start_ms: u64,
        end_ms: u64,
        purpose: SemanticTaskKind,
        response_language: &LanguageCode,
        source_sha256: &str,
    ) -> Result<Option<SemanticRubric>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                // `purpose` is stored JSON-encoded (with quotes) by
                // save_semantic_rubric; encode the probe the same way.
                "SELECT rubric_json FROM semantic_rubrics
                 WHERE media_id IS ?1 AND start_ms=?2 AND end_ms=?3
                   AND purpose=?4 AND response_language=?5 AND source_sha256=?6
                 ORDER BY version DESC LIMIT 1",
                params![
                    media_id.map(MediaId::as_str),
                    start_ms,
                    end_ms,
                    json(&purpose)?,
                    response_language.as_str(),
                    source_sha256,
                ],
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
        let connection = self.connection.lock();
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

    fn list_semantic_attempts_by_kinds(
        &self,
        kinds: &[SemanticTaskKind],
    ) -> Result<Vec<SemanticTaskAttempt>, ApplicationError> {
        let connection = self.connection.lock();
        let placeholders = (1..=kinds.len())
            .map(|index| format!("?{index}"))
            .collect::<Vec<_>>()
            .join(",");
        let mut statement = connection
            .prepare(&format!(
                "SELECT attempt_json FROM semantic_task_attempts
                 WHERE kind IN ({placeholders}) ORDER BY started_at_ms ASC, id ASC",
            ))
            .map_err(repo)?;
        let kind_keys = kinds.iter().map(json).collect::<Result<Vec<_>, _>>()?;
        let attempts = statement
            .query_map(
                rusqlite::params_from_iter(kind_keys.iter()),
                attempt_from_row,
            )
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
        let connection = self.connection.lock();
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
        let connection = self.connection.lock();
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

    fn save_writing_feedback_finding(
        &self,
        finding: &WritingFeedbackFinding,
    ) -> Result<WritingFeedbackFinding, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO writing_feedback_findings
                 (id,attempt_id,response_revision,layer,provider_id,created_at_ms,finding_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)",
                params![
                    finding.id.as_str(),
                    finding.attempt_id.as_str(),
                    finding.response_revision,
                    json(&finding.layer)?,
                    finding.provenance.provider_id,
                    finding.created_at_ms,
                    json(finding)?,
                ],
            )
            .map_err(repo)?;
        Ok(finding.clone())
    }

    fn get_writing_feedback_finding(
        &self,
        id: &WritingFeedbackFindingId,
    ) -> Result<Option<WritingFeedbackFinding>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT finding_json FROM writing_feedback_findings WHERE id=?1",
                [id.as_str()],
                writing_finding_from_row,
            )
            .optional()
            .map_err(repo)
    }

    fn list_writing_feedback_findings(
        &self,
        attempt_id: &SemanticTaskAttemptId,
    ) -> Result<Vec<WritingFeedbackFinding>, ApplicationError> {
        let connection = self.connection.lock();
        let mut statement = connection
            .prepare(
                "SELECT finding_json FROM writing_feedback_findings
                 WHERE attempt_id=?1 ORDER BY response_revision, created_at_ms, id",
            )
            .map_err(repo)?;
        statement
            .query_map([attempt_id.as_str()], writing_finding_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn save_writing_finding_disposition(
        &self,
        disposition: &WritingFindingDisposition,
    ) -> Result<WritingFindingDisposition, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO writing_finding_dispositions
                 (id,finding_id,decision,occurred_at_ms,disposition_json)
                 VALUES (?1,?2,?3,?4,?5)",
                params![
                    disposition.id.as_str(),
                    disposition.finding_id.as_str(),
                    json(&disposition.decision)?,
                    disposition.occurred_at_ms,
                    json(disposition)?,
                ],
            )
            .map_err(repo)?;
        Ok(disposition.clone())
    }

    fn get_writing_finding_disposition(
        &self,
        id: &WritingFindingDispositionId,
    ) -> Result<Option<WritingFindingDisposition>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT disposition_json FROM writing_finding_dispositions WHERE id=?1",
                [id.as_str()],
                writing_disposition_from_row,
            )
            .optional()
            .map_err(repo)
    }

    fn list_writing_finding_dispositions(
        &self,
        finding_id: &WritingFeedbackFindingId,
    ) -> Result<Vec<WritingFindingDisposition>, ApplicationError> {
        let connection = self.connection.lock();
        let mut statement = connection
            .prepare(
                "SELECT disposition_json FROM writing_finding_dispositions
                 WHERE finding_id=?1 ORDER BY occurred_at_ms, id",
            )
            .map_err(repo)?;
        statement
            .query_map([finding_id.as_str()], writing_disposition_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn upsert_writing_draft(&self, draft: &WritingDraft) -> Result<WritingDraft, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO writing_drafts (rubric_id,updated_at_ms,draft_json)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(rubric_id) DO UPDATE SET
                   updated_at_ms=excluded.updated_at_ms,
                   draft_json=excluded.draft_json",
                params![draft.rubric_id.as_str(), draft.updated_at_ms, json(draft)?],
            )
            .map_err(repo)?;
        Ok(draft.clone())
    }

    fn get_writing_draft(
        &self,
        rubric_id: &SemanticRubricId,
    ) -> Result<Option<WritingDraft>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT draft_json FROM writing_drafts WHERE rubric_id=?1",
                [rubric_id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn delete_writing_draft(&self, rubric_id: &SemanticRubricId) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "DELETE FROM writing_drafts WHERE rubric_id=?1",
                [rubric_id.as_str()],
            )
            .map_err(repo)?;
        Ok(())
    }
}
