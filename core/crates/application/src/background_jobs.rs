use std::collections::HashMap;
use std::sync::Mutex;

use domain::{BackgroundJob, BackgroundJobId, BackgroundJobKind, BackgroundJobStatus};

use crate::ApplicationError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BackgroundJobTransition {
    Applied(BackgroundJob),
    Rejected(BackgroundJob),
}

/// Durable lifecycle seam shared by local background workflows.
///
/// `transition` is compare-and-swap on status, so cancellation, completion,
/// and failure cannot overwrite one another. `recover_startup` atomically
/// retains queued work for resumption and marks process-owned active work as
/// interrupted before returning the queued records to restart.
pub trait BackgroundJobStore: Send + Sync {
    fn create(&self, job: &BackgroundJob) -> Result<BackgroundJob, ApplicationError>;
    fn get(&self, id: &BackgroundJobId) -> Result<Option<BackgroundJob>, ApplicationError>;
    fn list(&self, kind: BackgroundJobKind) -> Result<Vec<BackgroundJob>, ApplicationError>;
    fn transition(
        &self,
        expected: BackgroundJobStatus,
        job: &BackgroundJob,
    ) -> Result<BackgroundJobTransition, ApplicationError>;
    fn recover_startup(
        &self,
        kind: BackgroundJobKind,
        now_ms: u64,
    ) -> Result<Vec<BackgroundJob>, ApplicationError>;
}

#[derive(Default)]
pub struct InMemoryBackgroundJobStore {
    jobs: Mutex<HashMap<BackgroundJobId, BackgroundJob>>,
}

impl BackgroundJobStore for InMemoryBackgroundJobStore {
    fn create(&self, job: &BackgroundJob) -> Result<BackgroundJob, ApplicationError> {
        let mut jobs = self
            .jobs
            .lock()
            .map_err(|_| ApplicationError::Repository("background job lock poisoned".into()))?;
        if jobs.contains_key(&job.id) {
            return Err(ApplicationError::Conflict(
                "background job identifier already exists",
            ));
        }
        jobs.insert(job.id.clone(), job.clone());
        Ok(job.clone())
    }

    fn get(&self, id: &BackgroundJobId) -> Result<Option<BackgroundJob>, ApplicationError> {
        Ok(self
            .jobs
            .lock()
            .map_err(|_| ApplicationError::Repository("background job lock poisoned".into()))?
            .get(id)
            .cloned())
    }

    fn list(&self, kind: BackgroundJobKind) -> Result<Vec<BackgroundJob>, ApplicationError> {
        let mut jobs = self
            .jobs
            .lock()
            .map_err(|_| ApplicationError::Repository("background job lock poisoned".into()))?
            .values()
            .filter(|job| job.kind == kind)
            .cloned()
            .collect::<Vec<_>>();
        jobs.sort_by_key(|job| (job.created_at_ms, job.id.as_str().to_owned()));
        Ok(jobs)
    }

    fn transition(
        &self,
        expected: BackgroundJobStatus,
        job: &BackgroundJob,
    ) -> Result<BackgroundJobTransition, ApplicationError> {
        let mut jobs = self
            .jobs
            .lock()
            .map_err(|_| ApplicationError::Repository("background job lock poisoned".into()))?;
        let current = jobs
            .get(&job.id)
            .cloned()
            .ok_or(ApplicationError::NotFound("background job"))?;
        if current.status != expected {
            return Ok(BackgroundJobTransition::Rejected(current));
        }
        jobs.insert(job.id.clone(), job.clone());
        Ok(BackgroundJobTransition::Applied(job.clone()))
    }

    fn recover_startup(
        &self,
        kind: BackgroundJobKind,
        now_ms: u64,
    ) -> Result<Vec<BackgroundJob>, ApplicationError> {
        let mut jobs = self
            .jobs
            .lock()
            .map_err(|_| ApplicationError::Repository("background job lock poisoned".into()))?;
        let mut queued = Vec::new();
        for job in jobs.values_mut().filter(|job| job.kind == kind) {
            match job.status {
                BackgroundJobStatus::Queued => queued.push(job.clone()),
                BackgroundJobStatus::Running | BackgroundJobStatus::Cancelling => {
                    job.status = BackgroundJobStatus::Interrupted;
                    job.error = Some("The local service stopped before this job completed.".into());
                    job.updated_at_ms = now_ms;
                }
                _ => {}
            }
        }
        queued.sort_by_key(|job| (job.created_at_ms, job.id.as_str().to_owned()));
        Ok(queued)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn job(id: &str, status: BackgroundJobStatus) -> BackgroundJob {
        BackgroundJob {
            id: BackgroundJobId::parse(id).unwrap(),
            kind: BackgroundJobKind::SpeechBatch,
            status,
            payload_json: "{}".into(),
            completed_units: 0,
            total_units: 1,
            error: None,
            retry_of_job_id: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        }
    }

    #[test]
    fn cancellation_and_completion_are_compare_and_swap() {
        let store = InMemoryBackgroundJobStore::default();
        let running = store
            .create(&job("job", BackgroundJobStatus::Running))
            .unwrap();
        let mut cancelled = running.clone();
        cancelled.status = BackgroundJobStatus::Cancelled;
        assert!(matches!(
            store
                .transition(BackgroundJobStatus::Running, &cancelled)
                .unwrap(),
            BackgroundJobTransition::Applied(_)
        ));
        let mut completed = running;
        completed.status = BackgroundJobStatus::Completed;
        assert_eq!(
            store
                .transition(BackgroundJobStatus::Running, &completed)
                .unwrap(),
            BackgroundJobTransition::Rejected(cancelled)
        );
    }

    #[test]
    fn startup_resumes_queued_and_interrupts_running() {
        let store = InMemoryBackgroundJobStore::default();
        store
            .create(&job("queued", BackgroundJobStatus::Queued))
            .unwrap();
        store
            .create(&job("running", BackgroundJobStatus::Running))
            .unwrap();
        let queued = store
            .recover_startup(BackgroundJobKind::SpeechBatch, 20)
            .unwrap();
        assert_eq!(queued.len(), 1);
        assert_eq!(queued[0].id.as_str(), "queued");
        assert_eq!(
            store
                .get(&BackgroundJobId::parse("running").unwrap())
                .unwrap()
                .unwrap()
                .status,
            BackgroundJobStatus::Interrupted
        );
    }
}
