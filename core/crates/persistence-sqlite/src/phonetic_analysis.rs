use application::{ApplicationError, PhoneticAnalysisRepository};
use domain::{
    PhoneticAnalysis, PhoneticAnalysisId, PhoneticAnalysisJob, PhoneticAnalysisJobId,
    PhoneticAnalysisJobStatus, PhoneticAnalysisModelDescriptor, PhoneticAnalysisModelId,
    PhoneticFindingFeedback, PhoneticFindingId, SubtitleSentenceId, SubtitleTrackId,
};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl PhoneticAnalysisRepository for SqliteRepository {
    fn upsert_phonetic_model(
        &self,
        model: &PhoneticAnalysisModelDescriptor,
    ) -> Result<PhoneticAnalysisModelDescriptor, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO phonetic_analysis_models(id,provider_id,descriptor_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4)
                 ON CONFLICT(id) DO UPDATE SET provider_id=excluded.provider_id,
                   descriptor_json=excluded.descriptor_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    model.id.as_str(),
                    model.provider_id,
                    json(model)?,
                    model.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(model.clone())
    }

    fn list_phonetic_models(
        &self,
    ) -> Result<Vec<PhoneticAnalysisModelDescriptor>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare("SELECT descriptor_json FROM phonetic_analysis_models ORDER BY provider_id,id")
            .map_err(repo)?;
        query
            .query_map([], |row| from_json(&row.get::<_, String>(0)?))
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_phonetic_model(
        &self,
        id: &PhoneticAnalysisModelId,
    ) -> Result<Option<PhoneticAnalysisModelDescriptor>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT descriptor_json FROM phonetic_analysis_models WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn delete_phonetic_model(&self, id: &PhoneticAnalysisModelId) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "DELETE FROM phonetic_analysis_models WHERE id=?1",
                [id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn create_phonetic_job(
        &self,
        job: &PhoneticAnalysisJob,
    ) -> Result<PhoneticAnalysisJob, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO phonetic_analysis_jobs
                 (id,media_id,track_id,sentence_id,input_fingerprint,status,job_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
                params![
                    job.id.as_str(),
                    job.media_id.as_str(),
                    job.track_id.as_str(),
                    job.sentence_id.as_ref().map(SubtitleSentenceId::as_str),
                    job.input_fingerprint,
                    json(&job.status)?,
                    json(job)?,
                    job.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(job.clone())
    }

    fn update_phonetic_job(
        &self,
        job: &PhoneticAnalysisJob,
    ) -> Result<PhoneticAnalysisJob, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "UPDATE phonetic_analysis_jobs SET status=?2,job_json=?3,updated_at_ms=?4
                 WHERE id=?1",
                params![
                    job.id.as_str(),
                    json(&job.status)?,
                    json(job)?,
                    job.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(job.clone())
    }

    fn get_phonetic_job(
        &self,
        id: &PhoneticAnalysisJobId,
    ) -> Result<Option<PhoneticAnalysisJob>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT job_json FROM phonetic_analysis_jobs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_phonetic_jobs(&self) -> Result<Vec<PhoneticAnalysisJob>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare("SELECT job_json FROM phonetic_analysis_jobs ORDER BY updated_at_ms DESC")
            .map_err(repo)?;
        query
            .query_map([], |row| from_json(&row.get::<_, String>(0)?))
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn find_completed_phonetic_job(
        &self,
        input_fingerprint: &str,
    ) -> Result<Option<PhoneticAnalysisJob>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT job_json FROM phonetic_analysis_jobs
                 WHERE input_fingerprint=?1 AND status='\"completed\"'
                 ORDER BY updated_at_ms DESC LIMIT 1",
                [input_fingerprint],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn delete_phonetic_job(&self, id: &PhoneticAnalysisJobId) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "DELETE FROM phonetic_analysis_jobs WHERE id=?1",
                params![id.as_str()],
            )
            .map_err(repo)?;
        Ok(())
    }

    fn delete_terminal_phonetic_jobs(&self) -> Result<u64, ApplicationError> {
        let terminal = ["completed", "cancelled", "failed", "interrupted"];
        let count = self
            .connection
            .lock()
            .execute(
                "DELETE FROM phonetic_analysis_jobs WHERE status IN (?1,?2,?3,?4)",
                params![terminal[0], terminal[1], terminal[2], terminal[3]],
            )
            .map_err(repo)? as u64;
        Ok(count)
    }

    fn interrupt_active_phonetic_jobs(&self, updated_at_ms: u64) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let active = [
            PhoneticAnalysisJobStatus::Queued,
            PhoneticAnalysisJobStatus::Extracting,
            PhoneticAnalysisJobStatus::RecognizingPhones,
            PhoneticAnalysisJobStatus::Aligning,
            PhoneticAnalysisJobStatus::Analyzing,
        ]
        .into_iter()
        .map(|status| json(&status))
        .collect::<Result<Vec<_>, _>>()?;
        let mut query = tx
            .prepare(
                "SELECT id,job_json FROM phonetic_analysis_jobs
                 WHERE status IN (?1,?2,?3,?4,?5)",
            )
            .map_err(repo)?;
        let jobs = query
            .query_map(
                params![active[0], active[1], active[2], active[3], active[4]],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        from_json(&row.get::<_, String>(1)?)?,
                    ))
                },
            )
            .map_err(repo)?
            .collect::<Result<Vec<(String, PhoneticAnalysisJob)>, _>>()
            .map_err(repo)?;
        drop(query);
        for (id, mut job) in jobs {
            job.status = PhoneticAnalysisJobStatus::Interrupted;
            job.error_code = Some("interrupted".into());
            job.error_message =
                Some("The local service stopped before this analysis completed.".into());
            job.completed_at_ms = Some(updated_at_ms);
            job.updated_at_ms = updated_at_ms;
            tx.execute(
                "UPDATE phonetic_analysis_jobs SET status=?2,job_json=?3,updated_at_ms=?4
                 WHERE id=?1",
                params![id, json(&job.status)?, json(&job)?, updated_at_ms],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn save_phonetic_analysis(
        &self,
        analysis: &PhoneticAnalysis,
    ) -> Result<PhoneticAnalysis, ApplicationError> {
        analysis.validate().map_err(ApplicationError::from)?;
        self.connection
            .lock()
            .execute(
                "INSERT INTO phonetic_analyses
                 (id,job_id,media_id,track_id,sentence_id,provider_id,model_id,analysis_json,created_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
                params![
                    analysis.id.as_str(),
                    analysis.job_id.as_str(),
                    analysis.media_id.as_str(),
                    analysis.track_id.as_str(),
                    analysis.sentence_id.as_ref().map(SubtitleSentenceId::as_str),
                    analysis.provider_id,
                    analysis.model_id.as_str(),
                    json(analysis)?,
                    analysis.created_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(analysis.clone())
    }

    fn get_phonetic_analysis(
        &self,
        id: &PhoneticAnalysisId,
    ) -> Result<Option<PhoneticAnalysis>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT analysis_json FROM phonetic_analyses WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_track_phonetic_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneticAnalysis>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare(
                "SELECT analysis_json FROM phonetic_analyses
                 WHERE track_id=?1 ORDER BY created_at_ms DESC,rowid DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn save_phonetic_feedback(
        &self,
        feedback: &PhoneticFindingFeedback,
    ) -> Result<PhoneticFindingFeedback, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO phonetic_finding_feedback(finding_id,feedback_json,updated_at_ms)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(finding_id) DO UPDATE SET
                   feedback_json=excluded.feedback_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    feedback.finding_id.as_str(),
                    json(feedback)?,
                    feedback.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(feedback.clone())
    }

    fn get_phonetic_feedback(
        &self,
        finding_id: &PhoneticFindingId,
    ) -> Result<Option<PhoneticFindingFeedback>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT feedback_json FROM phonetic_finding_feedback WHERE finding_id=?1",
                [finding_id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }
}
