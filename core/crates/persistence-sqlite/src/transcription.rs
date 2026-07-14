use application::{ApplicationError, TranscriptionRepository};
use domain::{
    SubtitleTrackProvenance, TranscriptionJob, TranscriptionJobId, TranscriptionJobStatus,
    TranscriptionModelDescriptor, TranscriptionModelId,
};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl TranscriptionRepository for SqliteRepository {
    fn upsert_model(
        &self,
        model: &TranscriptionModelDescriptor,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO transcription_models(id,provider_id,descriptor_json,updated_at_ms)
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

    fn list_models(&self) -> Result<Vec<TranscriptionModelDescriptor>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare("SELECT descriptor_json FROM transcription_models ORDER BY provider_id,id")
            .map_err(repo)?;
        query
            .query_map([], |row| {
                from_json::<TranscriptionModelDescriptor>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_model(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<Option<TranscriptionModelDescriptor>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT descriptor_json FROM transcription_models WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn delete_model(&self, id: &TranscriptionModelId) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "DELETE FROM transcription_models WHERE id=?1",
                [id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn create_job(&self, job: &TranscriptionJob) -> Result<TranscriptionJob, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO transcription_jobs(id,media_id,input_fingerprint,status,job_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6)",
                params![
                    job.id.as_str(),
                    job.media_id.as_str(),
                    job.input_fingerprint,
                    json(&job.status)?,
                    json(job)?,
                    job.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(job.clone())
    }

    fn update_job(&self, job: &TranscriptionJob) -> Result<TranscriptionJob, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE transcription_jobs SET status=?2,job_json=?3,updated_at_ms=?4 WHERE id=?1",
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

    fn get_job(
        &self,
        id: &TranscriptionJobId,
    ) -> Result<Option<TranscriptionJob>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT job_json FROM transcription_jobs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_jobs(&self) -> Result<Vec<TranscriptionJob>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare("SELECT job_json FROM transcription_jobs ORDER BY updated_at_ms DESC")
            .map_err(repo)?;
        query
            .query_map([], |row| {
                from_json::<TranscriptionJob>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map(|jobs| {
                jobs.into_iter()
                    .filter(|job| job.archived_at_ms.is_none())
                    .collect()
            })
            .map_err(repo)
    }

    fn find_completed_job(
        &self,
        input_fingerprint: &str,
    ) -> Result<Option<TranscriptionJob>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT job_json FROM transcription_jobs
                 WHERE input_fingerprint=?1 AND status='\"completed\"'
                 ORDER BY updated_at_ms DESC LIMIT 1",
                [input_fingerprint],
                |row| from_json::<TranscriptionJob>(&row.get::<_, String>(0)?),
            )
            .optional()
            .map(|job| job.filter(|job| job.archived_at_ms.is_none()))
            .map_err(repo)
    }

    fn interrupt_active_jobs(&self, updated_at_ms: u64) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let mut query = tx
            .prepare(
                "SELECT id,job_json FROM transcription_jobs
                 WHERE status IN ('\"queued\"','\"extracting\"','\"transcribing\"','\"importing\"')",
            )
            .map_err(repo)?;
        let jobs = query
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    from_json(&row.get::<_, String>(1)?)?,
                ))
            })
            .map_err(repo)?
            .collect::<Result<Vec<(String, TranscriptionJob)>, _>>()
            .map_err(repo)?;
        drop(query);
        for (id, mut job) in jobs {
            job.status = TranscriptionJobStatus::Failed;
            job.error_code = Some("interrupted".into());
            job.error_message = Some("The local service stopped before this job completed.".into());
            job.completed_at_ms = Some(updated_at_ms);
            job.updated_at_ms = updated_at_ms;
            tx.execute(
                "UPDATE transcription_jobs SET status=?2,job_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![id, json(&job.status)?, json(&job)?, updated_at_ms],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn save_provenance(
        &self,
        provenance: &SubtitleTrackProvenance,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO subtitle_track_provenance(track_id,transcription_job_id,provenance_json)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(track_id) DO UPDATE SET provenance_json=excluded.provenance_json",
                params![
                    provenance.track_id.as_str(),
                    provenance.transcription_job_id.as_str(),
                    json(provenance)?
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }
}
