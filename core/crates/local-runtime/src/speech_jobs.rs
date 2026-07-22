use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use api_events::{EventEnvelope, EventName};
use application::{AppServices, ApplicationError, now_ms};
use domain::SubtitleTrackId;
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;

static JOB_SEQUENCE: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpeechBatchKind {
    PronunciationAnalysis,
    WordTimings,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpeechBatchStatus {
    Queued,
    Running,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeechBatchJob {
    pub id: String,
    pub track_id: String,
    pub kind: SpeechBatchKind,
    pub status: SpeechBatchStatus,
    pub processed: usize,
    pub total: usize,
    pub result_count: usize,
    pub error: Option<String>,
    pub retry_of_job_id: Option<String>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateSpeechBatchJob {
    pub track_id: String,
    pub kind: SpeechBatchKind,
}

#[derive(Clone)]
pub struct SpeechBatchCoordinator {
    services: AppServices,
    events: broadcast::Sender<EventEnvelope>,
    jobs: Arc<Mutex<HashMap<String, SpeechBatchJob>>>,
}

impl SpeechBatchCoordinator {
    pub fn new(services: AppServices, events: broadcast::Sender<EventEnvelope>) -> Self {
        Self {
            services,
            events,
            jobs: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn list(&self) -> Result<Vec<SpeechBatchJob>, ApplicationError> {
        let mut values = self.lock_jobs()?.values().cloned().collect::<Vec<_>>();
        values.sort_by_key(|job| job.created_at_ms);
        Ok(values)
    }

    pub fn get(&self, id: &str) -> Result<Option<SpeechBatchJob>, ApplicationError> {
        Ok(self.lock_jobs()?.get(id).cloned())
    }

    pub fn create(
        self: Arc<Self>,
        request: CreateSpeechBatchJob,
    ) -> Result<SpeechBatchJob, ApplicationError> {
        let track_id = SubtitleTrackId::parse(request.track_id)?;
        let total = self
            .services
            .media_analysis()
            .read_subtitle_track(&track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?
            .sentences
            .len();
        let created_at_ms = now_ms();
        let job = SpeechBatchJob {
            id: format!(
                "speech-job-{}-{}",
                created_at_ms,
                JOB_SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ),
            track_id: track_id.as_str().into(),
            kind: request.kind,
            status: SpeechBatchStatus::Queued,
            processed: 0,
            total,
            result_count: 0,
            error: None,
            retry_of_job_id: None,
            created_at_ms,
            updated_at_ms: created_at_ms,
        };
        self.lock_jobs()?.insert(job.id.clone(), job.clone());
        self.start(job.id.clone());
        Ok(job)
    }

    pub fn cancel(&self, id: &str) -> Result<SpeechBatchJob, ApplicationError> {
        let mut jobs = self.lock_jobs()?;
        let job = jobs
            .get_mut(id)
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if matches!(
            job.status,
            SpeechBatchStatus::Queued | SpeechBatchStatus::Running
        ) {
            job.status = SpeechBatchStatus::Cancelled;
            job.updated_at_ms = now_ms();
        }
        Ok(job.clone())
    }

    pub fn retry(self: Arc<Self>, id: &str) -> Result<SpeechBatchJob, ApplicationError> {
        let old = self
            .get(id)?
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if matches!(
            old.status,
            SpeechBatchStatus::Queued | SpeechBatchStatus::Running
        ) {
            return Err(ApplicationError::Conflict("speech batch job is active"));
        }
        let mut job = self.clone().create(CreateSpeechBatchJob {
            track_id: old.track_id,
            kind: old.kind,
        })?;
        job.retry_of_job_id = Some(old.id);
        self.lock_jobs()?.insert(job.id.clone(), job.clone());
        Ok(job)
    }

    fn start(self: &Arc<Self>, id: String) {
        let coordinator = self.clone();
        tokio::task::spawn_blocking(move || coordinator.run(&id));
    }

    fn run(&self, id: &str) {
        if self.set_running(id).is_err() {
            return;
        }
        let result = self.execute(id);
        if let Err(error) = result {
            let _ = self.fail(id, error.to_string());
        }
    }

    fn execute(&self, id: &str) -> Result<(), ApplicationError> {
        let job = self
            .get(id)?
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        let track_id = SubtitleTrackId::parse(job.track_id.clone())?;
        let track = self
            .services
            .media_analysis()
            .read_subtitle_track(&track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let mut result_count = 0;
        for (index, sentence) in track.sentences.iter().enumerate() {
            if self.is_cancelled(id)? {
                return Ok(());
            }
            result_count += match job.kind {
                SpeechBatchKind::PronunciationAnalysis => {
                    if self
                        .services
                        .pronunciation()
                        .pronunciation_cache_state(&sentence.id)?
                        == Some(false)
                    {
                        self.emit_cache_invalidated(&job, sentence.id.as_str());
                    }
                    self.services
                        .pronunciation()
                        .analyze_pronunciation(&sentence.id)?;
                    1
                }
                SpeechBatchKind::WordTimings => {
                    if self
                        .services
                        .pronunciation()
                        .word_timing_cache_state(&sentence.id)?
                        == Some(false)
                    {
                        self.emit_cache_invalidated(&job, sentence.id.as_str());
                    }
                    self.services
                        .pronunciation()
                        .word_timings(&sentence.id)?
                        .len()
                }
            };
            self.progress(id, index + 1, result_count)?;
        }
        self.complete(id, result_count)
    }

    fn set_running(&self, id: &str) -> Result<(), ApplicationError> {
        let mut jobs = self.lock_jobs()?;
        let job = jobs
            .get_mut(id)
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if job.status == SpeechBatchStatus::Cancelled {
            return Ok(());
        }
        job.status = SpeechBatchStatus::Running;
        job.updated_at_ms = now_ms();
        Ok(())
    }

    fn progress(
        &self,
        id: &str,
        processed: usize,
        result_count: usize,
    ) -> Result<(), ApplicationError> {
        let mut jobs = self.lock_jobs()?;
        let job = jobs
            .get_mut(id)
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        job.processed = processed;
        job.result_count = result_count;
        job.updated_at_ms = now_ms();
        if processed == job.total || processed.is_multiple_of(100) {
            self.emit_progress(job);
        }
        Ok(())
    }

    fn complete(&self, id: &str, result_count: usize) -> Result<(), ApplicationError> {
        let mut jobs = self.lock_jobs()?;
        let job = jobs
            .get_mut(id)
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if job.status == SpeechBatchStatus::Cancelled {
            return Ok(());
        }
        job.status = SpeechBatchStatus::Completed;
        job.processed = job.total;
        job.result_count = result_count;
        job.updated_at_ms = now_ms();
        self.emit_progress(job);
        match job.kind {
            SpeechBatchKind::PronunciationAnalysis => {
                let _ = self.events.send(
                    crate::events::PronunciationAnalysisCompletedPayload {
                        job_id: Some(job.id.clone()),
                        track_id: Some(job.track_id.clone()),
                        sentence_id: None,
                        count: Some(result_count),
                    }
                    .envelope(),
                );
            }
            SpeechBatchKind::WordTimings => {
                let _ = self.events.send(
                    crate::events::WordTimingsCompletedPayload {
                        job_id: Some(job.id.clone()),
                        track_id: job.track_id.clone(),
                        line: None,
                        count: result_count,
                        timeline_id: None,
                    }
                    .envelope(),
                );
            }
        }
        Ok(())
    }

    fn fail(&self, id: &str, error: String) -> Result<(), ApplicationError> {
        let mut jobs = self.lock_jobs()?;
        let job = jobs
            .get_mut(id)
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if job.status != SpeechBatchStatus::Cancelled {
            job.status = SpeechBatchStatus::Failed;
            job.error = Some(error);
            job.updated_at_ms = now_ms();
        }
        Ok(())
    }

    fn is_cancelled(&self, id: &str) -> Result<bool, ApplicationError> {
        Ok(self
            .lock_jobs()?
            .get(id)
            .is_some_and(|job| job.status == SpeechBatchStatus::Cancelled))
    }

    fn emit_progress(&self, job: &SpeechBatchJob) {
        let event = match job.kind {
            SpeechBatchKind::PronunciationAnalysis => EventName::PronunciationAnalysisProgress,
            SpeechBatchKind::WordTimings => EventName::WordTimingsProgress,
        };
        let _ = self.events.send(
            crate::events::SpeechBatchProgressPayload {
                job_id: Some(job.id.clone()),
                track_id: job.track_id.clone(),
                processed: job.processed,
                total: job.total,
            }
            .envelope(event),
        );
    }

    fn emit_cache_invalidated(&self, job: &SpeechBatchJob, sentence_id: &str) {
        let _ = self.events.send(
            crate::events::SpeechCacheInvalidatedPayload {
                job_id: Some(job.id.clone()),
                track_id: Some(job.track_id.clone()),
                kind: job.kind,
                sentence_id: sentence_id.to_owned(),
            }
            .envelope(),
        );
    }

    fn lock_jobs(
        &self,
    ) -> Result<std::sync::MutexGuard<'_, HashMap<String, SpeechBatchJob>>, ApplicationError> {
        self.jobs
            .lock()
            .map_err(|_| ApplicationError::Repository("speech batch job lock poisoned".into()))
    }
}
