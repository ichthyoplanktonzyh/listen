use application::{ApplicationError, BackgroundJobStore, BackgroundJobTransition};
use domain::{BackgroundJob, BackgroundJobId, BackgroundJobKind, BackgroundJobStatus};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl BackgroundJobStore for SqliteRepository {
    fn create(&self, job: &BackgroundJob) -> Result<BackgroundJob, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO background_jobs
                 (id,kind,status,job_json,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6)",
                params![
                    job.id.as_str(),
                    json(&job.kind)?,
                    json(&job.status)?,
                    json(job)?,
                    job.created_at_ms,
                    job.updated_at_ms,
                ],
            )
            .map_err(repo)?;
        Ok(job.clone())
    }

    fn get(&self, id: &BackgroundJobId) -> Result<Option<BackgroundJob>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT job_json FROM background_jobs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list(&self, kind: BackgroundJobKind) -> Result<Vec<BackgroundJob>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare(
                "SELECT job_json FROM background_jobs
                 WHERE kind=?1 ORDER BY created_at_ms,id",
            )
            .map_err(repo)?;
        query
            .query_map([json(&kind)?], |row| {
                from_json::<BackgroundJob>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn transition(
        &self,
        expected: BackgroundJobStatus,
        job: &BackgroundJob,
    ) -> Result<BackgroundJobTransition, ApplicationError> {
        let conn = self.connection.lock();
        let updated = conn
            .execute(
                "UPDATE background_jobs
                 SET status=?3,job_json=?4,updated_at_ms=?5
                 WHERE id=?1 AND status=?2",
                params![
                    job.id.as_str(),
                    json(&expected)?,
                    json(&job.status)?,
                    json(job)?,
                    job.updated_at_ms,
                ],
            )
            .map_err(repo)?;
        if updated == 1 {
            return Ok(BackgroundJobTransition::Applied(job.clone()));
        }
        let current = conn
            .query_row(
                "SELECT job_json FROM background_jobs WHERE id=?1",
                [job.id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("background job"))?;
        Ok(BackgroundJobTransition::Rejected(current))
    }

    fn recover_startup(
        &self,
        kind: BackgroundJobKind,
        now_ms: u64,
    ) -> Result<Vec<BackgroundJob>, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let kind_json = json(&kind)?;
        let mut query = tx
            .prepare(
                "SELECT job_json FROM background_jobs
                 WHERE kind=?1
                   AND status IN ('\"queued\"','\"running\"','\"cancelling\"')
                 ORDER BY created_at_ms,id",
            )
            .map_err(repo)?;
        let jobs = query
            .query_map([kind_json], |row| {
                from_json::<BackgroundJob>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        drop(query);

        let mut queued = Vec::new();
        for mut job in jobs {
            if job.status == BackgroundJobStatus::Queued {
                queued.push(job);
                continue;
            }
            job.status = BackgroundJobStatus::Interrupted;
            job.error = Some("The local service stopped before this job completed.".into());
            job.updated_at_ms = now_ms;
            tx.execute(
                "UPDATE background_jobs
                 SET status=?2,job_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![job.id.as_str(), json(&job.status)?, json(&job)?, now_ms,],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        Ok(queued)
    }
}
