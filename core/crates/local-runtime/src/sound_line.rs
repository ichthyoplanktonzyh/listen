use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, BackgroundJobStore, BackgroundJobTransition,
    ForcedAlignProvider, now_ms,
};
use domain::{
    BackgroundJob, BackgroundJobId, BackgroundJobKind, BackgroundJobStatus, LanguageCode,
    SubtitleTrackId,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::{Semaphore, broadcast};

use crate::process::{CancellationProbe, ProcessRunner, ProcessSpec, TokioProcessRunner};
use crate::runtime_support::{ffmpeg_wav_args, io_error, resolve_tool};

static JOB_SEQUENCE: AtomicU64 = AtomicU64::new(1);

/// The sound line is a fully independent, best-effort background workflow that
/// enriches an already-transcribed track with listening-structure resources
/// (pause/acoustic evidence). It never writes or activates the text-line
/// timeline, and its failures never propagate back to transcription.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SoundLineStatus {
    Queued,
    Running,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SoundLineJob {
    pub id: String,
    pub track_id: String,
    pub status: SoundLineStatus,
    pub timeline_id: Option<String>,
    pub acoustic_cue_count: usize,
    pub error: Option<String>,
    pub retry_of_job_id: Option<String>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateSoundLineJob {
    pub track_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SoundLinePayload {
    track_id: String,
    timeline_id: Option<String>,
    acoustic_cue_count: usize,
}

#[derive(Default)]
struct SoundLineOutcome {
    timeline_id: Option<String>,
    acoustic_cue_count: usize,
}

#[derive(Clone)]
pub struct SoundLineCoordinator {
    services: AppServices,
    events: broadcast::Sender<EventEnvelope>,
    jobs: Arc<dyn BackgroundJobStore>,
    enqueue_lock: Arc<Mutex<()>>,
    queue: Arc<Semaphore>,
    temp_dir: PathBuf,
    process_runner: Arc<dyn ProcessRunner>,
    forced_aligner: Option<Arc<dyn ForcedAlignProvider>>,
}

impl SoundLineCoordinator {
    pub fn new(
        services: AppServices,
        events: broadcast::Sender<EventEnvelope>,
        jobs: Arc<dyn BackgroundJobStore>,
        forced_aligner: Option<Arc<dyn ForcedAlignProvider>>,
    ) -> Result<Arc<Self>, ApplicationError> {
        Self::new_with_process_runner(
            services,
            events,
            jobs,
            forced_aligner,
            Arc::new(TokioProcessRunner),
        )
    }

    pub fn new_with_process_runner(
        services: AppServices,
        events: broadcast::Sender<EventEnvelope>,
        jobs: Arc<dyn BackgroundJobStore>,
        forced_aligner: Option<Arc<dyn ForcedAlignProvider>>,
        process_runner: Arc<dyn ProcessRunner>,
    ) -> Result<Arc<Self>, ApplicationError> {
        let temp_dir = std::env::temp_dir().join("LLPlayerNext/sound-line");
        // Best-effort cleanup of stale work dirs from a previous run.
        let _ = std::fs::remove_dir_all(&temp_dir);
        let queued = jobs.recover_startup(BackgroundJobKind::SoundLine, now_ms())?;
        let coordinator = Arc::new(Self {
            services,
            events,
            jobs,
            enqueue_lock: Arc::default(),
            queue: Arc::new(Semaphore::new(1)),
            temp_dir,
            process_runner,
            forced_aligner,
        });
        // Auto-trigger: subscribe to transcription completions and enqueue a
        // sound-line job for the freshly generated track. Guarded so that
        // constructing outside a Tokio runtime never panics.
        if tokio::runtime::Handle::try_current().is_ok() {
            coordinator.clone().spawn_transcription_listener();
            for job in queued {
                coordinator.clone().start(job.id.as_str().to_owned());
            }
        }
        Ok(coordinator)
    }

    pub fn list(&self) -> Result<Vec<SoundLineJob>, ApplicationError> {
        self.jobs
            .list(BackgroundJobKind::SoundLine)?
            .into_iter()
            .map(sound_line_job)
            .collect()
    }

    pub fn get(&self, id: &str) -> Result<Option<SoundLineJob>, ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        self.jobs.get(&id)?.map(sound_line_job).transpose()
    }

    /// Enqueue a sound-line job for a track. Idempotent: if an active job for the
    /// same track already exists, that job is returned instead of a duplicate.
    pub fn create(
        self: &Arc<Self>,
        request: CreateSoundLineJob,
    ) -> Result<SoundLineJob, ApplicationError> {
        let track_id = SubtitleTrackId::parse(request.track_id)?;
        self.services
            .media_analysis()
            .read_subtitle_track(&track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        self.enqueue(track_id, None)
    }

    pub fn cancel(&self, id: &str) -> Result<SoundLineJob, ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let mut record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("sound line job"))?;
        loop {
            if !matches!(
                record.status,
                BackgroundJobStatus::Queued | BackgroundJobStatus::Running
            ) {
                return sound_line_job(record);
            }
            let expected = record.status;
            let mut cancelled = record.clone();
            cancelled.status = BackgroundJobStatus::Cancelled;
            cancelled.updated_at_ms = now_ms();
            match self.jobs.transition(expected, &cancelled)? {
                BackgroundJobTransition::Applied(cancelled) => {
                    let job = sound_line_job(cancelled)?;
                    self.emit_changed(&job);
                    return Ok(job);
                }
                BackgroundJobTransition::Rejected(current) => record = current,
            }
        }
    }

    pub fn retry(self: &Arc<Self>, id: &str) -> Result<SoundLineJob, ApplicationError> {
        let old = self
            .get(id)?
            .ok_or(ApplicationError::NotFound("sound line job"))?;
        if matches!(
            old.status,
            SoundLineStatus::Queued | SoundLineStatus::Running
        ) {
            return Err(ApplicationError::Conflict("sound line job is active"));
        }
        let track_id = SubtitleTrackId::parse(old.track_id)?;
        self.enqueue(track_id, Some(BackgroundJobId::parse(old.id)?))
    }

    fn enqueue(
        self: &Arc<Self>,
        track_id: SubtitleTrackId,
        retry_of_job_id: Option<BackgroundJobId>,
    ) -> Result<SoundLineJob, ApplicationError> {
        let enqueue_guard = self
            .enqueue_lock
            .lock()
            .map_err(|_| ApplicationError::Repository("sound line enqueue lock poisoned".into()))?;
        let created_at_ms = now_ms();
        if retry_of_job_id.is_none()
            && let Some(existing) = self.list()?.into_iter().find(|job| {
                job.track_id == track_id.as_str()
                    && matches!(
                        job.status,
                        SoundLineStatus::Queued | SoundLineStatus::Running
                    )
            })
        {
            return Ok(existing);
        }
        let id = BackgroundJobId::parse(format!(
            "sound-line-{}-{}",
            created_at_ms,
            JOB_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ))?;
        let record = BackgroundJob {
            id,
            kind: BackgroundJobKind::SoundLine,
            status: BackgroundJobStatus::Queued,
            payload_json: serde_json::to_string(&SoundLinePayload {
                track_id: track_id.as_str().into(),
                timeline_id: None,
                acoustic_cue_count: 0,
            })
            .map_err(|error| ApplicationError::Repository(error.to_string()))?,
            completed_units: 0,
            total_units: 1,
            error: None,
            retry_of_job_id,
            created_at_ms,
            updated_at_ms: created_at_ms,
        };
        let job = sound_line_job(self.jobs.create(&record)?)?;
        drop(enqueue_guard);
        self.emit_changed(&job);
        self.clone().start(job.id.clone());
        Ok(job)
    }

    fn start(self: Arc<Self>, id: String) {
        tokio::spawn(async move { self.run(&id).await });
    }

    async fn run(&self, id: &str) {
        if !matches!(self.set_running(id), Ok(true)) {
            return;
        }
        match self.execute(id).await {
            Ok(outcome) => {
                let _ = self.complete(id, outcome);
            }
            Err(error) => {
                let _ = self.fail(id, error.to_string());
            }
        }
    }

    async fn execute(&self, id: &str) -> Result<SoundLineOutcome, ApplicationError> {
        let _permit = self
            .queue
            .acquire()
            .await
            .map_err(|_| ApplicationError::Repository("sound line queue closed".into()))?;
        if self.is_cancelled(id)? {
            return Ok(SoundLineOutcome::default());
        }
        let job = self
            .get(id)?
            .ok_or(ApplicationError::NotFound("sound line job"))?;
        let track_id = SubtitleTrackId::parse(job.track_id.clone())?;
        let track = self
            .services
            .media_analysis()
            .read_subtitle_track(&track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let media = self
            .services
            .media_analysis()
            .read_media(&track.media_id)?
            .ok_or(ApplicationError::NotFound("media"))?;
        let job_dir = self.temp_dir.join(&job.id);
        tokio::fs::create_dir_all(&job_dir)
            .await
            .map_err(io_error)?;
        let wav = job_dir.join("audio.wav");
        let outcome = self
            .build(id, &track_id, media.path, track.language, &wav)
            .await;
        let _ = tokio::fs::remove_dir_all(&job_dir).await;
        outcome
    }

    async fn build(
        &self,
        job_id: &str,
        track_id: &SubtitleTrackId,
        media_path: String,
        language: Option<LanguageCode>,
        wav: &Path,
    ) -> Result<SoundLineOutcome, ApplicationError> {
        let ffmpeg = resolve_tool("LLPLAYERNEXT_FFMPEG", "ffmpeg")
            .ok_or(ApplicationError::Validation("ffmpeg runtime"))?;
        // The sound line re-extracts audio independently of transcription's
        // work dir. It has no record of the original audio track index, so it
        // uses the default track — an acceptable degradation for enrichment.
        let args = ffmpeg_wav_args(media_path, None, wav);
        self.process_runner
            .run(
                ProcessSpec::new(ffmpeg, args),
                Arc::new(SoundLineCancellation {
                    jobs: self.jobs.clone(),
                    job_id: BackgroundJobId::parse(job_id)?,
                }),
            )
            .await?;
        if self.is_cancelled(job_id)? {
            return Ok(SoundLineOutcome::default());
        }
        let language = language.as_ref().map(LanguageCode::as_str);
        // whisper JSON is intentionally empty: the sound line derives its word
        // baseline from the already-persisted active text timeline.
        let result = self
            .services
            .media_analysis()
            .build_transcription_sound_line_resources(
                track_id,
                b"",
                wav,
                self.forced_aligner.as_deref(),
                language,
            )
            .await?;
        Ok(match result {
            Some(result) => SoundLineOutcome {
                timeline_id: result.final_timeline_id.map(|id| id.as_str().to_owned()),
                acoustic_cue_count: result.acoustic_cue_count,
            },
            None => SoundLineOutcome::default(),
        })
    }

    fn spawn_transcription_listener(self: Arc<Self>) {
        let mut receiver = self.events.subscribe();
        tokio::spawn(async move {
            loop {
                match receiver.recv().await {
                    Ok(envelope) => {
                        if envelope.event != EventName::TranscriptionJobChanged {
                            continue;
                        }
                        if let Some(track_id) = completed_track_id(&envelope.payload) {
                            let _ = self.enqueue(track_id, None);
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(broadcast::error::RecvError::Closed) => break,
                }
            }
        });
    }

    fn set_running(&self, id: &str) -> Result<bool, ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("sound line job"))?;
        if record.status != BackgroundJobStatus::Queued {
            return Ok(false);
        }
        let mut running = record;
        running.status = BackgroundJobStatus::Running;
        running.updated_at_ms = now_ms();
        let BackgroundJobTransition::Applied(running) = self
            .jobs
            .transition(BackgroundJobStatus::Queued, &running)?
        else {
            return Ok(false);
        };
        self.emit_changed(&sound_line_job(running)?);
        Ok(true)
    }

    fn complete(&self, id: &str, outcome: SoundLineOutcome) -> Result<(), ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("sound line job"))?;
        if record.status != BackgroundJobStatus::Running {
            return Ok(());
        }
        let mut completed = record;
        let mut payload = sound_line_payload(&completed)?;
        payload.timeline_id = outcome.timeline_id;
        payload.acoustic_cue_count = outcome.acoustic_cue_count;
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
        let job = sound_line_job(completed)?;
        self.emit_changed(&job);
        let _ = self.events.send(
            crate::events::SoundLineCompletedPayload {
                job_id: job.id.clone(),
                track_id: job.track_id.clone(),
                timeline_id: job.timeline_id.clone(),
                acoustic_cue_count: job.acoustic_cue_count,
            }
            .envelope(),
        );
        Ok(())
    }

    fn fail(&self, id: &str, error: String) -> Result<(), ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("sound line job"))?;
        if record.status != BackgroundJobStatus::Running {
            return Ok(());
        }
        let mut failed = record;
        failed.status = BackgroundJobStatus::Failed;
        failed.error = Some(error);
        failed.updated_at_ms = now_ms();
        if let BackgroundJobTransition::Applied(failed) = self
            .jobs
            .transition(BackgroundJobStatus::Running, &failed)?
        {
            self.emit_changed(&sound_line_job(failed)?);
        }
        Ok(())
    }

    fn is_cancelled(&self, id: &str) -> Result<bool, ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        Ok(self
            .jobs
            .get(&id)?
            .is_some_and(|job| job.status == BackgroundJobStatus::Cancelled))
    }

    fn emit_changed(&self, job: &SoundLineJob) {
        let _ = self.events.send(EventEnvelope::v1(
            EventName::SoundLineChanged,
            serde_json::to_value(job).expect("sound line job serializes"),
        ));
    }
}

struct SoundLineCancellation {
    jobs: Arc<dyn BackgroundJobStore>,
    job_id: BackgroundJobId,
}

impl CancellationProbe for SoundLineCancellation {
    fn is_cancelled(&self) -> Result<bool, ApplicationError> {
        Ok(self
            .jobs
            .get(&self.job_id)?
            .is_some_and(|job| job.status == BackgroundJobStatus::Cancelled))
    }
}

fn sound_line_payload(job: &BackgroundJob) -> Result<SoundLinePayload, ApplicationError> {
    serde_json::from_str(&job.payload_json)
        .map_err(|error| ApplicationError::Repository(error.to_string()))
}

fn sound_line_job(job: BackgroundJob) -> Result<SoundLineJob, ApplicationError> {
    let payload = sound_line_payload(&job)?;
    Ok(SoundLineJob {
        id: job.id.as_str().into(),
        track_id: payload.track_id,
        status: match job.status {
            BackgroundJobStatus::Queued => SoundLineStatus::Queued,
            BackgroundJobStatus::Running | BackgroundJobStatus::Cancelling => {
                SoundLineStatus::Running
            }
            BackgroundJobStatus::Completed => SoundLineStatus::Completed,
            BackgroundJobStatus::Cancelled => SoundLineStatus::Cancelled,
            BackgroundJobStatus::Failed | BackgroundJobStatus::Interrupted => {
                SoundLineStatus::Failed
            }
        },
        timeline_id: payload.timeline_id,
        acoustic_cue_count: payload.acoustic_cue_count,
        error: job.error,
        retry_of_job_id: job.retry_of_job_id.map(|id| id.as_str().into()),
        created_at_ms: job.created_at_ms,
        updated_at_ms: job.updated_at_ms,
    })
}

fn completed_track_id(payload: &Value) -> Option<SubtitleTrackId> {
    if payload.get("status")?.as_str()? != "completed" {
        return None;
    }
    // Archiving emits another transcription-job-changed snapshot while the
    // status remains completed. That is not a new sound-line trigger.
    if payload
        .get("archived_at_ms")
        .is_some_and(|value| !value.is_null())
    {
        return None;
    }
    let track_id = payload.get("generated_track_id")?.as_str()?;
    SubtitleTrackId::parse(track_id.to_owned()).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fresh_transcription_completion_exposes_track_id() {
        let payload = serde_json::json!({
            "status": "completed",
            "generated_track_id": "track-1",
            "archived_at_ms": null,
        });

        assert_eq!(
            completed_track_id(&payload).map(|id| id.as_str().to_owned()),
            Some("track-1".into())
        );
    }

    #[test]
    fn archived_completion_does_not_retrigger_sound_line() {
        let payload = serde_json::json!({
            "status": "completed",
            "generated_track_id": "track-1",
            "archived_at_ms": 123,
        });

        assert!(completed_track_id(&payload).is_none());
    }
}
