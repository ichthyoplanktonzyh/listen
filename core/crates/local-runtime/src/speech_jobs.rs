use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, BackgroundJobStore, BackgroundJobTransition, now_ms,
};
use domain::{
    BackgroundJob, BackgroundJobId, BackgroundJobKind, BackgroundJobStatus, SubtitleTrackId,
};
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SpeechBatchPayload {
    track_id: String,
    kind: SpeechBatchKind,
    result_count: usize,
}

#[derive(Clone)]
pub struct SpeechBatchCoordinator {
    services: AppServices,
    events: broadcast::Sender<EventEnvelope>,
    jobs: Arc<dyn BackgroundJobStore>,
}

impl SpeechBatchCoordinator {
    pub fn new(
        services: AppServices,
        events: broadcast::Sender<EventEnvelope>,
        jobs: Arc<dyn BackgroundJobStore>,
    ) -> Result<Arc<Self>, ApplicationError> {
        let queued = jobs.recover_startup(BackgroundJobKind::SpeechBatch, now_ms())?;
        let coordinator = Arc::new(Self {
            services,
            events,
            jobs,
        });
        for job in queued {
            coordinator.clone().start(job.id.as_str().to_owned());
        }
        Ok(coordinator)
    }

    pub fn list(&self) -> Result<Vec<SpeechBatchJob>, ApplicationError> {
        self.jobs
            .list(BackgroundJobKind::SpeechBatch)?
            .into_iter()
            .map(speech_job)
            .collect()
    }

    pub fn get(&self, id: &str) -> Result<Option<SpeechBatchJob>, ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        match self.jobs.get(&id)? {
            Some(job) if job.kind == BackgroundJobKind::SpeechBatch => speech_job(job).map(Some),
            _ => Ok(None),
        }
    }

    pub fn create(
        self: Arc<Self>,
        request: CreateSpeechBatchJob,
    ) -> Result<SpeechBatchJob, ApplicationError> {
        self.create_with_retry(request, None)
    }

    fn create_with_retry(
        self: Arc<Self>,
        request: CreateSpeechBatchJob,
        retry_of_job_id: Option<BackgroundJobId>,
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
        let id = BackgroundJobId::parse(format!(
            "speech-job-{}-{}",
            created_at_ms,
            JOB_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ))?;
        let record = BackgroundJob {
            id,
            kind: BackgroundJobKind::SpeechBatch,
            status: BackgroundJobStatus::Queued,
            payload_json: serde_json::to_string(&SpeechBatchPayload {
                track_id: track_id.as_str().into(),
                kind: request.kind,
                result_count: 0,
            })
            .map_err(|error| ApplicationError::Repository(error.to_string()))?,
            completed_units: 0,
            total_units: total as u64,
            error: None,
            retry_of_job_id,
            created_at_ms,
            updated_at_ms: created_at_ms,
        };
        let job = speech_job(self.jobs.create(&record)?)?;
        self.start(job.id.clone());
        Ok(job)
    }

    pub fn cancel(&self, id: &str) -> Result<SpeechBatchJob, ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let mut record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if record.kind != BackgroundJobKind::SpeechBatch {
            return Err(ApplicationError::NotFound("speech batch job"));
        }
        loop {
            if !matches!(
                record.status,
                BackgroundJobStatus::Queued | BackgroundJobStatus::Running
            ) {
                return speech_job(record);
            }
            let expected = record.status;
            let mut cancelled = record.clone();
            cancelled.status = BackgroundJobStatus::Cancelled;
            cancelled.updated_at_ms = now_ms();
            match self.jobs.transition(expected, &cancelled)? {
                BackgroundJobTransition::Applied(job) => return speech_job(job),
                BackgroundJobTransition::Rejected(current) => record = current,
            }
        }
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
        let retry_of = BackgroundJobId::parse(old.id)?;
        self.clone().create_with_retry(
            CreateSpeechBatchJob {
                track_id: old.track_id,
                kind: old.kind,
            },
            Some(retry_of),
        )
    }

    fn start(self: &Arc<Self>, id: String) {
        let coordinator = self.clone();
        tokio::task::spawn_blocking(move || coordinator.run(&id));
    }

    fn run(&self, id: &str) {
        if !matches!(self.set_running(id), Ok(true)) {
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

    fn set_running(&self, id: &str) -> Result<bool, ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if record.status != BackgroundJobStatus::Queued {
            return Ok(false);
        }
        let mut running = record;
        running.status = BackgroundJobStatus::Running;
        running.updated_at_ms = now_ms();
        Ok(matches!(
            self.jobs
                .transition(BackgroundJobStatus::Queued, &running)?,
            BackgroundJobTransition::Applied(_)
        ))
    }

    fn progress(
        &self,
        id: &str,
        processed: usize,
        result_count: usize,
    ) -> Result<(), ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if record.status != BackgroundJobStatus::Running {
            return Ok(());
        }
        let mut updated = record;
        let mut payload = speech_payload(&updated)?;
        payload.result_count = result_count;
        updated.payload_json = serde_json::to_string(&payload)
            .map_err(|error| ApplicationError::Repository(error.to_string()))?;
        updated.completed_units = processed as u64;
        updated.updated_at_ms = now_ms();
        if let BackgroundJobTransition::Applied(updated) = self
            .jobs
            .transition(BackgroundJobStatus::Running, &updated)?
        {
            let job = speech_job(updated)?;
            if processed == job.total || processed.is_multiple_of(100) {
                self.emit_progress(&job);
            }
        }
        Ok(())
    }

    fn complete(&self, id: &str, result_count: usize) -> Result<(), ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if record.status != BackgroundJobStatus::Running {
            return Ok(());
        }
        let mut completed = record;
        let mut payload = speech_payload(&completed)?;
        payload.result_count = result_count;
        completed.payload_json = serde_json::to_string(&payload)
            .map_err(|error| ApplicationError::Repository(error.to_string()))?;
        completed.status = BackgroundJobStatus::Completed;
        completed.completed_units = completed.total_units;
        completed.updated_at_ms = now_ms();
        let BackgroundJobTransition::Applied(completed) = self
            .jobs
            .transition(BackgroundJobStatus::Running, &completed)?
        else {
            return Ok(());
        };
        let job = speech_job(completed)?;
        self.emit_progress(&job);
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
        let id = BackgroundJobId::parse(id)?;
        let record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("speech batch job"))?;
        if record.status != BackgroundJobStatus::Running {
            return Ok(());
        }
        let mut failed = record;
        failed.status = BackgroundJobStatus::Failed;
        failed.error = Some(error);
        failed.updated_at_ms = now_ms();
        let _ = self
            .jobs
            .transition(BackgroundJobStatus::Running, &failed)?;
        Ok(())
    }

    fn is_cancelled(&self, id: &str) -> Result<bool, ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        Ok(self
            .jobs
            .get(&id)?
            .is_some_and(|job| job.status == BackgroundJobStatus::Cancelled))
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
}

fn speech_payload(job: &BackgroundJob) -> Result<SpeechBatchPayload, ApplicationError> {
    serde_json::from_str(&job.payload_json)
        .map_err(|error| ApplicationError::Repository(error.to_string()))
}

fn speech_job(job: BackgroundJob) -> Result<SpeechBatchJob, ApplicationError> {
    if job.kind != BackgroundJobKind::SpeechBatch {
        return Err(ApplicationError::NotFound("speech batch job"));
    }
    let payload = speech_payload(&job)?;
    Ok(SpeechBatchJob {
        id: job.id.as_str().into(),
        track_id: payload.track_id,
        kind: payload.kind,
        status: match job.status {
            BackgroundJobStatus::Queued => SpeechBatchStatus::Queued,
            BackgroundJobStatus::Running | BackgroundJobStatus::Cancelling => {
                SpeechBatchStatus::Running
            }
            BackgroundJobStatus::Completed => SpeechBatchStatus::Completed,
            BackgroundJobStatus::Cancelled => SpeechBatchStatus::Cancelled,
            BackgroundJobStatus::Failed | BackgroundJobStatus::Interrupted => {
                SpeechBatchStatus::Failed
            }
        },
        processed: job.completed_units as usize,
        total: job.total_units as usize,
        result_count: payload.result_count,
        error: job.error,
        retry_of_job_id: job.retry_of_job_id.map(|id| id.as_str().into()),
        created_at_ms: job.created_at_ms,
        updated_at_ms: job.updated_at_ms,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn another_job_kind_cannot_be_deserialized_as_speech_batch() {
        let job = BackgroundJob {
            id: BackgroundJobId::parse("sound-id").unwrap(),
            kind: BackgroundJobKind::SoundLine,
            status: BackgroundJobStatus::Running,
            payload_json: "{}".into(),
            completed_units: 0,
            total_units: 0,
            error: None,
            retry_of_job_id: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        assert!(matches!(
            speech_job(job),
            Err(ApplicationError::NotFound("speech batch job"))
        ));
    }
}
