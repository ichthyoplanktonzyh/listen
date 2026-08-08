use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, BackgroundJobStore, BackgroundJobTransition,
    ForcedAlignCancellation, ForcedAlignProvider, SoundLineSourceProvenance, now_ms,
};
use domain::{
    BackgroundJob, BackgroundJobId, BackgroundJobKind, BackgroundJobStatus, LanguageCode,
    SubtitleTrackId,
};
use serde::{Deserialize, Serialize};
use tokio::sync::{Semaphore, broadcast};

use crate::process::{
    CancellationProbe, ProcessOutputObserver, ProcessRunner, ProcessSpec, TokioProcessRunner,
};
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
    pub audio_track: Option<u32>,
    pub status: SoundLineStatus,
    pub timeline_id: Option<String>,
    pub acoustic_cue_count: usize,
    pub error_code: Option<String>,
    pub error: Option<String>,
    pub retry_of_job_id: Option<String>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateSoundLineJob {
    pub track_id: String,
    #[serde(default)]
    pub audio_track: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SoundLinePayload {
    track_id: String,
    #[serde(default)]
    audio_track: Option<u32>,
    timeline_id: Option<String>,
    acoustic_cue_count: usize,
    #[serde(default)]
    error_code: Option<String>,
}

#[derive(Default)]
struct SoundLineOutcome {
    audio_track: Option<u32>,
    timeline_id: Option<String>,
    acoustic_cue_count: usize,
}

#[derive(Debug)]
struct SoundLineFailure {
    error_code: &'static str,
    message: String,
}

impl SoundLineFailure {
    fn new(error_code: &'static str, message: impl Into<String>) -> Self {
        Self {
            error_code,
            message: message.into(),
        }
    }

    fn runtime(error: ApplicationError) -> Self {
        Self::new("sound_line_failed", error.to_string())
    }
}

#[derive(Clone)]
struct SoundLineTools {
    ffmpeg: Option<PathBuf>,
    ffprobe: Option<PathBuf>,
}

impl SoundLineTools {
    fn discover() -> Self {
        Self {
            ffmpeg: resolve_tool("LLPLAYERNEXT_FFMPEG", "ffmpeg"),
            ffprobe: resolve_tool("LLPLAYERNEXT_FFPROBE", "ffprobe"),
        }
    }
}

#[derive(Clone)]
pub struct SoundLineCoordinator {
    services: AppServices,
    events: broadcast::Sender<EventEnvelope>,
    jobs: Arc<dyn BackgroundJobStore>,
    enqueue_lock: Arc<Mutex<()>>,
    commit_lock: Arc<Mutex<()>>,
    queue: Arc<Semaphore>,
    temp_dir: PathBuf,
    process_runner: Arc<dyn ProcessRunner>,
    tools: SoundLineTools,
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
        Self::new_with_runtime_tools(
            services,
            events,
            jobs,
            forced_aligner,
            process_runner,
            SoundLineTools::discover(),
            std::env::temp_dir().join("LLPlayerNext/sound-line"),
        )
    }

    fn new_with_runtime_tools(
        services: AppServices,
        events: broadcast::Sender<EventEnvelope>,
        jobs: Arc<dyn BackgroundJobStore>,
        forced_aligner: Option<Arc<dyn ForcedAlignProvider>>,
        process_runner: Arc<dyn ProcessRunner>,
        tools: SoundLineTools,
        temp_dir: PathBuf,
    ) -> Result<Arc<Self>, ApplicationError> {
        // Best-effort cleanup of stale work dirs from a previous run.
        let _ = std::fs::remove_dir_all(&temp_dir);
        let queued = jobs.recover_startup(BackgroundJobKind::SoundLine, now_ms())?;
        let coordinator = Arc::new(Self {
            services,
            events,
            jobs,
            enqueue_lock: Arc::default(),
            commit_lock: Arc::default(),
            queue: Arc::new(Semaphore::new(1)),
            temp_dir,
            process_runner,
            tools,
            forced_aligner,
        });
        // Recover interrupted jobs from a previous run. Guarded so that
        // constructing outside a Tokio runtime never panics.
        if tokio::runtime::Handle::try_current().is_ok() {
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
        match self.jobs.get(&id)? {
            Some(job) if job.kind == BackgroundJobKind::SoundLine => sound_line_job(job).map(Some),
            _ => Ok(None),
        }
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
        self.enqueue(track_id, request.audio_track, None)
    }

    pub fn cancel(&self, id: &str) -> Result<SoundLineJob, ApplicationError> {
        let _commit_guard = self
            .commit_lock
            .lock()
            .map_err(|_| ApplicationError::Repository("sound line commit lock poisoned".into()))?;
        let id = BackgroundJobId::parse(id)?;
        let mut record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("sound line job"))?;
        if record.kind != BackgroundJobKind::SoundLine {
            return Err(ApplicationError::NotFound("sound line job"));
        }
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
        self.enqueue(
            track_id,
            old.audio_track,
            Some(BackgroundJobId::parse(old.id)?),
        )
    }

    fn enqueue(
        self: &Arc<Self>,
        track_id: SubtitleTrackId,
        audio_track: Option<u32>,
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
                    && job.audio_track == audio_track
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
                audio_track,
                timeline_id: None,
                acoustic_cue_count: 0,
                error_code: None,
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
            Err(failure) => {
                let _ = self.fail(id, failure.error_code, failure.message);
            }
        }
    }

    async fn execute(&self, id: &str) -> Result<SoundLineOutcome, SoundLineFailure> {
        let _permit = self.queue.acquire().await.map_err(|_| {
            SoundLineFailure::runtime(ApplicationError::Repository(
                "sound line queue closed".into(),
            ))
        })?;
        if self.is_cancelled(id).map_err(SoundLineFailure::runtime)? {
            return Ok(SoundLineOutcome::default());
        }
        let job = self
            .get(id)
            .map_err(SoundLineFailure::runtime)?
            .ok_or(ApplicationError::NotFound("sound line job"))
            .map_err(SoundLineFailure::runtime)?;
        let track_id = SubtitleTrackId::parse(job.track_id.clone())
            .map_err(|error| SoundLineFailure::runtime(error.into()))?;
        let track = self
            .services
            .media_analysis()
            .read_subtitle_track(&track_id)
            .map_err(SoundLineFailure::runtime)?
            .ok_or(ApplicationError::NotFound("subtitle track"))
            .map_err(SoundLineFailure::runtime)?;
        let media = self
            .services
            .media_analysis()
            .read_media(&track.media_id)
            .map_err(SoundLineFailure::runtime)?
            .ok_or(ApplicationError::NotFound("media"))
            .map_err(SoundLineFailure::runtime)?;
        let job_dir = self.temp_dir.join(&job.id);
        tokio::fs::create_dir_all(&job_dir)
            .await
            .map_err(io_error)
            .map_err(SoundLineFailure::runtime)?;
        let wav = job_dir.join("audio.wav");
        let outcome = self
            .build(
                id,
                &track_id,
                media.path,
                track.language,
                job.audio_track,
                &wav,
            )
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
        requested_audio_track: Option<u32>,
        wav: &Path,
    ) -> Result<SoundLineOutcome, SoundLineFailure> {
        let cancellation = SoundLineCancellation {
            jobs: self.jobs.clone(),
            job_id: BackgroundJobId::parse(job_id)
                .map_err(|error| SoundLineFailure::runtime(error.into()))?,
            commit_lock: self.commit_lock.clone(),
        };
        let audio_track = self
            .resolve_audio_track(&media_path, requested_audio_track, &cancellation)
            .await?;
        let ffmpeg = self
            .tools
            .ffmpeg
            .clone()
            .ok_or(ApplicationError::Validation("ffmpeg runtime"))
            .map_err(SoundLineFailure::runtime)?;
        let args = ffmpeg_wav_args(media_path, Some(audio_track), wav);
        self.process_runner
            .run(
                ProcessSpec::new(ffmpeg, args),
                Arc::new(cancellation.clone()),
            )
            .await
            .map_err(SoundLineFailure::runtime)?;
        if self
            .is_cancelled(job_id)
            .map_err(SoundLineFailure::runtime)?
        {
            return Ok(SoundLineOutcome::default());
        }
        let language = language.as_ref().map(LanguageCode::as_str);
        // whisper JSON is intentionally empty: the sound line derives its word
        // baseline from the already-persisted active text timeline.
        let result = self
            .services
            .media_analysis()
            .build_transcription_sound_line_resources_cancellable(
                track_id,
                b"",
                wav,
                self.forced_aligner.as_deref(),
                Some(&cancellation),
                SoundLineSourceProvenance {
                    language: language.map(str::to_owned),
                    audio_track: Some(audio_track),
                },
            )
            .await
            .map_err(SoundLineFailure::runtime)?;
        if self
            .is_cancelled(job_id)
            .map_err(SoundLineFailure::runtime)?
        {
            return Ok(SoundLineOutcome::default());
        }
        let result = result.ok_or_else(|| {
            SoundLineFailure::new(
                "sound_line_source_unavailable",
                "sound-line source timings are unavailable",
            )
        })?;
        let timeline_id = result.final_timeline_id.ok_or_else(|| {
            SoundLineFailure::new(
                "sound_line_source_unavailable",
                "sound-line candidate timeline could not be created",
            )
        })?;
        Ok(SoundLineOutcome {
            audio_track: Some(audio_track),
            timeline_id: Some(timeline_id.as_str().to_owned()),
            acoustic_cue_count: result.acoustic_cue_count,
        })
    }

    async fn resolve_audio_track(
        &self,
        media_path: &str,
        requested_audio_track: Option<u32>,
        cancellation: &SoundLineCancellation,
    ) -> Result<u32, SoundLineFailure> {
        let ffprobe = self.tools.ffprobe.clone().ok_or_else(|| {
            SoundLineFailure::new("audio_track_probe_failed", "ffprobe runtime is unavailable")
        })?;
        let counter = Arc::new(AudioTrackCounter::default());
        self.process_runner
            .run_streaming(
                ProcessSpec::new(
                    ffprobe,
                    vec![
                        "-v".into(),
                        "error".into(),
                        "-select_streams".into(),
                        "a".into(),
                        "-show_entries".into(),
                        "stream=index".into(),
                        "-of".into(),
                        "csv=p=0".into(),
                        media_path.into(),
                    ],
                ),
                Arc::new(cancellation.clone()),
                counter.clone(),
            )
            .await
            .map_err(|error| {
                SoundLineFailure::new("audio_track_probe_failed", error.to_string())
            })?;
        select_audio_track(counter.count(), requested_audio_track)
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
        payload.audio_track = outcome.audio_track;
        payload.timeline_id = outcome.timeline_id;
        payload.acoustic_cue_count = outcome.acoustic_cue_count;
        payload.error_code = None;
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
                audio_track: job.audio_track,
                timeline_id: job.timeline_id.clone(),
                acoustic_cue_count: job.acoustic_cue_count,
            }
            .envelope(),
        );
        Ok(())
    }

    fn fail(&self, id: &str, error_code: &str, error: String) -> Result<(), ApplicationError> {
        let id = BackgroundJobId::parse(id)?;
        let record = self
            .jobs
            .get(&id)?
            .ok_or(ApplicationError::NotFound("sound line job"))?;
        if record.status != BackgroundJobStatus::Running {
            return Ok(());
        }
        let mut failed = record;
        let mut payload = sound_line_payload(&failed)?;
        payload.error_code = Some(error_code.into());
        failed.payload_json = serde_json::to_string(&payload)
            .map_err(|error| ApplicationError::Repository(error.to_string()))?;
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

#[derive(Clone)]
struct SoundLineCancellation {
    jobs: Arc<dyn BackgroundJobStore>,
    job_id: BackgroundJobId,
    commit_lock: Arc<Mutex<()>>,
}

impl SoundLineCancellation {
    fn durable_cancelled(&self) -> Result<bool, ApplicationError> {
        Ok(self
            .jobs
            .get(&self.job_id)?
            .is_some_and(|job| job.status == BackgroundJobStatus::Cancelled))
    }
}

impl CancellationProbe for SoundLineCancellation {
    fn is_cancelled(&self) -> Result<bool, ApplicationError> {
        self.durable_cancelled()
    }
}

impl ForcedAlignCancellation for SoundLineCancellation {
    fn is_cancelled(&self) -> bool {
        self.durable_cancelled().unwrap_or(true)
    }

    fn commit_if_active(&self, commit: &mut dyn FnMut()) -> bool {
        let Ok(_guard) = self.commit_lock.lock() else {
            return false;
        };
        if self.durable_cancelled().unwrap_or(true) {
            return false;
        }
        commit();
        true
    }
}

fn sound_line_payload(job: &BackgroundJob) -> Result<SoundLinePayload, ApplicationError> {
    serde_json::from_str(&job.payload_json)
        .map_err(|error| ApplicationError::Repository(error.to_string()))
}

fn sound_line_job(job: BackgroundJob) -> Result<SoundLineJob, ApplicationError> {
    if job.kind != BackgroundJobKind::SoundLine {
        return Err(ApplicationError::NotFound("sound line job"));
    }
    let payload = sound_line_payload(&job)?;
    Ok(SoundLineJob {
        id: job.id.as_str().into(),
        track_id: payload.track_id,
        audio_track: payload.audio_track,
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
        error_code: payload.error_code,
        error: job.error,
        retry_of_job_id: job.retry_of_job_id.map(|id| id.as_str().into()),
        created_at_ms: job.created_at_ms,
        updated_at_ms: job.updated_at_ms,
    })
}

#[derive(Default)]
struct AudioTrackCounter {
    count: AtomicUsize,
}

impl AudioTrackCounter {
    fn count(&self) -> usize {
        self.count.load(Ordering::Relaxed)
    }
}

impl ProcessOutputObserver for AudioTrackCounter {
    fn stdout_line(&self, line: &str) -> Result<(), ApplicationError> {
        let line = line.trim();
        if line.is_empty() {
            return Ok(());
        }
        line.parse::<u32>().map_err(|_| {
            ApplicationError::ExternalProcess(
                "ffprobe returned an invalid audio stream index".into(),
            )
        })?;
        self.count.fetch_add(1, Ordering::Relaxed);
        Ok(())
    }
}

fn select_audio_track(
    audio_track_count: usize,
    requested_audio_track: Option<u32>,
) -> Result<u32, SoundLineFailure> {
    match (audio_track_count, requested_audio_track) {
        (0, _) => Err(SoundLineFailure::new(
            "audio_track_not_found",
            "media has no audio track",
        )),
        (1, None) => Ok(0),
        (count, None) if count > 1 => Err(SoundLineFailure::new(
            "audio_track_required",
            "media has multiple audio tracks; select one explicitly",
        )),
        (count, Some(track)) if (track as usize) < count => Ok(track),
        (_, Some(_)) => Err(SoundLineFailure::new(
            "audio_track_not_found",
            "selected audio track is no longer available",
        )),
        _ => unreachable!("all audio track selection states are covered"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::process::{FakeProcessRunner, IgnoreProcessOutput};
    use application::{CreateWordTimeline, ImportSubtitle, RegisterMedia};
    use domain::{
        MediaKind, TimelineCreator, TimelineMetrics, TimelineStatus, TimingSource, WordTiming,
    };
    use persistence_sqlite::SqliteRepository;
    use serde_json::Value;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::mpsc;
    use std::thread;
    use std::time::Duration;

    fn coordinator_fixture(
        audio_streams: impl IntoIterator<Item = &'static str>,
        with_text_timeline: bool,
    ) -> (
        Arc<SoundLineCoordinator>,
        AppServices,
        Arc<FakeProcessRunner>,
        broadcast::Receiver<EventEnvelope>,
        SubtitleTrackId,
        tempfile::TempDir,
    ) {
        let runner = Arc::new(FakeProcessRunner::with_stdout_lines(
            audio_streams.into_iter().map(str::to_owned),
        ));
        let (coordinator, services, receiver, track_id, temp_dir) =
            coordinator_fixture_with_runner(runner.clone(), with_text_timeline);
        (coordinator, services, runner, receiver, track_id, temp_dir)
    }

    fn coordinator_fixture_with_runner(
        process_runner: Arc<dyn ProcessRunner>,
        with_text_timeline: bool,
    ) -> (
        Arc<SoundLineCoordinator>,
        AppServices,
        broadcast::Receiver<EventEnvelope>,
        SubtitleTrackId,
        tempfile::TempDir,
    ) {
        let repository = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repository.clone(),
            repository.clone(),
            repository.clone(),
            repository.clone(),
            repository.clone(),
            repository.clone(),
            repository.clone(),
            repository.clone(),
        );
        let media = services
            .media_analysis()
            .register_media(RegisterMedia {
                path: "/test/media.mkv".into(),
                fingerprint: "sound-line-test-media".into(),
                title: "Sound Line Test".into(),
                kind: MediaKind::Video,
                duration_ms: Some(2_000),
            })
            .unwrap();
        let track = services
            .media_analysis()
            .import_subtitle(ImportSubtitle {
                media_id: media.id,
                source_name: "sound-line-test.srt".into(),
                content: b"1\n00:00:00,000 --> 00:00:01,500\nHello sound line.\n".to_vec(),
                language: Some("en".into()),
                identity_salt: None,
            })
            .unwrap();
        if with_text_timeline {
            let words = track.sentences[0]
                .tokens
                .iter()
                .filter(|token| token.kind == domain::SubtitleTokenKind::Word)
                .enumerate()
                .map(|(position, token)| WordTiming {
                    sentence_id: track.sentences[0].id.clone(),
                    token_index: token.index,
                    text: token.text.clone(),
                    start_ms: 100 + position as u64 * 300,
                    end_ms: 300 + position as u64 * 300,
                    confidence: Some(0.9),
                    timing_source: TimingSource::AsrAligned,
                    provider_id: "test-text-line".into(),
                    provider_version: "v1".into(),
                })
                .collect();
            services
                .media_analysis()
                .create_word_timeline(
                    &track.id,
                    CreateWordTimeline {
                        algorithm_id: Some("test-text-line".into()),
                        algorithm_version: Some("v1".into()),
                        config_hash: Some("test".into()),
                        parent_timeline_id: None,
                        created_by: Some(TimelineCreator::Algorithm),
                        status: Some(TimelineStatus::Active),
                        metrics_json: Some(TimelineMetrics::from_value(serde_json::json!({
                            "line": "text"
                        }))),
                        words,
                    },
                )
                .unwrap();
        }
        let (events, receiver) = broadcast::channel(64);
        let temp_dir = tempfile::tempdir().unwrap();
        let coordinator = SoundLineCoordinator::new_with_runtime_tools(
            services.clone(),
            events,
            repository,
            None,
            process_runner,
            SoundLineTools {
                ffmpeg: Some(PathBuf::from("/test/ffmpeg")),
                ffprobe: Some(PathBuf::from("/test/ffprobe")),
            },
            temp_dir.path().join("sound-line"),
        )
        .unwrap();
        (coordinator, services, receiver, track.id, temp_dir)
    }

    async fn wait_for_terminal(coordinator: &SoundLineCoordinator, job_id: &str) -> SoundLineJob {
        for _ in 0..200 {
            let job = coordinator.get(job_id).unwrap().unwrap();
            if matches!(
                job.status,
                SoundLineStatus::Completed | SoundLineStatus::Cancelled | SoundLineStatus::Failed
            ) {
                return job;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        panic!("sound-line job did not become terminal");
    }

    #[derive(Clone, Default)]
    struct BlockingFfmpegRunner {
        calls: Arc<Mutex<Vec<ProcessSpec>>>,
        ffmpeg_started: Arc<tokio::sync::Notify>,
    }

    #[async_trait::async_trait]
    impl ProcessRunner for BlockingFfmpegRunner {
        async fn run(
            &self,
            process: ProcessSpec,
            cancellation: Arc<dyn CancellationProbe>,
        ) -> Result<(), ApplicationError> {
            self.run_streaming(process, cancellation, Arc::new(IgnoreProcessOutput))
                .await
        }

        async fn run_streaming(
            &self,
            process: ProcessSpec,
            cancellation: Arc<dyn CancellationProbe>,
            output: Arc<dyn ProcessOutputObserver>,
        ) -> Result<(), ApplicationError> {
            self.calls.lock().unwrap().push(process.clone());
            if process.executable == Path::new("/test/ffprobe") {
                output.stdout_line("0")?;
                return Ok(());
            }
            self.ffmpeg_started.notify_waiters();
            loop {
                if cancellation.is_cancelled()? {
                    return Err(ApplicationError::Repository("job cancelled".into()));
                }
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        }
    }

    #[test]
    fn another_job_kind_cannot_be_deserialized_as_sound_line() {
        let mut job = BackgroundJob {
            id: BackgroundJobId::parse("speech-id").unwrap(),
            kind: BackgroundJobKind::SpeechBatch,
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
            sound_line_job(job.clone()),
            Err(ApplicationError::NotFound("sound line job"))
        ));
        job.kind = BackgroundJobKind::LlmBatch;
        assert!(sound_line_job(job).is_err());
    }

    #[test]
    fn cancellation_waits_for_an_in_flight_commit_and_blocks_later_writes() {
        let jobs = Arc::new(application::InMemoryBackgroundJobStore::default());
        let id = BackgroundJobId::parse("sound-line-race").unwrap();
        let running = BackgroundJob {
            id: id.clone(),
            kind: BackgroundJobKind::SoundLine,
            status: BackgroundJobStatus::Running,
            payload_json: r#"{"track_id":"track-1","audio_track":1,"timeline_id":null,"acoustic_cue_count":0,"error_code":null}"#.into(),
            completed_units: 0,
            total_units: 1,
            error: None,
            retry_of_job_id: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        jobs.create(&running).unwrap();
        let commit_lock = Arc::new(Mutex::new(()));
        let cancellation = Arc::new(SoundLineCancellation {
            jobs: jobs.clone(),
            job_id: id,
            commit_lock: commit_lock.clone(),
        });
        let writes = Arc::new(AtomicUsize::new(0));
        let (entered_tx, entered_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let committing = {
            let cancellation = cancellation.clone();
            let writes = writes.clone();
            thread::spawn(move || {
                cancellation.commit_if_active(&mut || {
                    entered_tx.send(()).unwrap();
                    release_rx.recv().unwrap();
                    writes.fetch_add(1, Ordering::SeqCst);
                })
            })
        };
        entered_rx.recv().unwrap();

        let (cancelled_tx, cancelled_rx) = mpsc::channel();
        let cancelling = thread::spawn(move || {
            let _guard = commit_lock.lock().unwrap();
            let mut cancelled = running;
            cancelled.status = BackgroundJobStatus::Cancelled;
            jobs.transition(BackgroundJobStatus::Running, &cancelled)
                .unwrap();
            cancelled_tx.send(()).unwrap();
        });
        assert!(cancelled_rx.try_recv().is_err());
        release_tx.send(()).unwrap();
        assert!(committing.join().unwrap());
        cancelled_rx.recv().unwrap();
        cancelling.join().unwrap();

        assert_eq!(writes.load(Ordering::SeqCst), 1);
        assert!(!cancellation.commit_if_active(&mut || {
            writes.fetch_add(1, Ordering::SeqCst);
        }));
        assert_eq!(writes.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn one_audio_track_is_selected_deterministically() {
        assert_eq!(select_audio_track(1, None).unwrap(), 0);
    }

    #[test]
    fn explicit_audio_track_is_preserved_for_multitrack_media() {
        assert_eq!(select_audio_track(3, Some(2)).unwrap(), 2);
    }

    #[test]
    fn create_request_accepts_an_optional_ffmpeg_relative_audio_track() {
        let explicit: CreateSoundLineJob =
            serde_json::from_value(serde_json::json!({"track_id": "track-1", "audio_track": 2}))
                .unwrap();
        let implicit: CreateSoundLineJob =
            serde_json::from_value(serde_json::json!({"track_id": "track-1"})).unwrap();

        assert_eq!(explicit.audio_track, Some(2));
        assert_eq!(implicit.audio_track, None);
    }

    #[test]
    fn multitrack_media_requires_an_explicit_selection() {
        let failure = select_audio_track(2, None).unwrap_err();
        assert_eq!(failure.error_code, "audio_track_required");
    }

    #[test]
    fn missing_or_changed_audio_track_is_rejected() {
        for (count, requested) in [(0, None), (1, Some(1)), (2, Some(2))] {
            let failure = select_audio_track(count, requested).unwrap_err();
            assert_eq!(failure.error_code, "audio_track_not_found");
        }
    }

    #[test]
    fn legacy_payloads_without_audio_provenance_remain_readable() {
        let job = BackgroundJob {
            id: BackgroundJobId::parse("sound-line-legacy").unwrap(),
            kind: BackgroundJobKind::SoundLine,
            status: BackgroundJobStatus::Completed,
            payload_json: r#"{"track_id":"track-1","timeline_id":null,"acoustic_cue_count":0}"#
                .into(),
            completed_units: 1,
            total_units: 1,
            error: None,
            retry_of_job_id: None,
            created_at_ms: 1,
            updated_at_ms: 2,
        };

        let parsed = sound_line_job(job).unwrap();
        assert_eq!(parsed.audio_track, None);
        assert_eq!(parsed.error_code, None);
    }

    #[test]
    fn failed_job_exposes_audio_selection_and_stable_error_code() {
        let job = BackgroundJob {
            id: BackgroundJobId::parse("sound-line-failed").unwrap(),
            kind: BackgroundJobKind::SoundLine,
            status: BackgroundJobStatus::Failed,
            payload_json: r#"{"track_id":"track-1","audio_track":3,"timeline_id":null,"acoustic_cue_count":0,"error_code":"audio_track_not_found"}"#.into(),
            completed_units: 0,
            total_units: 1,
            error: Some("selected audio track is no longer available".into()),
            retry_of_job_id: None,
            created_at_ms: 1,
            updated_at_ms: 2,
        };

        let parsed = sound_line_job(job).unwrap();
        assert_eq!(parsed.audio_track, Some(3));
        assert_eq!(parsed.error_code.as_deref(), Some("audio_track_not_found"));
    }

    #[test]
    fn malformed_ffprobe_output_is_rejected() {
        let counter = AudioTrackCounter::default();

        assert!(counter.stdout_line("not-an-index").is_err());
        assert_eq!(counter.count(), 0);
    }

    #[tokio::test]
    async fn coordinator_uses_selected_stream_and_persists_timeline_provenance() {
        let (coordinator, services, runner, mut events, track_id, _temp_dir) =
            coordinator_fixture(["0", "1"], true);

        let created = coordinator
            .create(CreateSoundLineJob {
                track_id: track_id.as_str().into(),
                audio_track: Some(1),
            })
            .unwrap();
        let completed = wait_for_terminal(&coordinator, &created.id).await;

        assert_eq!(completed.status, SoundLineStatus::Completed);
        assert_eq!(completed.audio_track, Some(1));
        assert!(completed.timeline_id.is_some());
        let calls = runner.calls();
        assert_eq!(calls.len(), 2);
        assert_eq!(calls[0].executable, PathBuf::from("/test/ffprobe"));
        assert!(
            calls[0]
                .args
                .windows(2)
                .any(|args| args == ["-select_streams", "a"])
        );
        assert_eq!(calls[1].executable, PathBuf::from("/test/ffmpeg"));
        assert!(
            calls[1]
                .args
                .windows(2)
                .any(|args| args == ["-map", "0:a:1"])
        );

        let candidate = services
            .media_analysis()
            .list_word_timelines(&track_id)
            .unwrap()
            .into_iter()
            .find(|timeline| {
                timeline.status == TimelineStatus::Candidate
                    && timeline.metrics_json.as_object().get("line")
                        == Some(&Value::String("sound".into()))
            })
            .expect("sound-line candidate timeline");
        assert_eq!(
            candidate.metrics_json.as_object().get("audio_track"),
            Some(&Value::from(1))
        );

        let mut completion_audio_track = None;
        while let Ok(event) = events.try_recv() {
            if event.event == EventName::SoundLineCompleted {
                completion_audio_track = event.payload.get("audio_track").and_then(Value::as_u64);
            }
        }
        assert_eq!(completion_audio_track, Some(1));
    }

    #[tokio::test]
    async fn unavailable_pipeline_source_fails_without_completion_event() {
        let (coordinator, services, runner, mut events, track_id, _temp_dir) =
            coordinator_fixture(["0"], false);

        let created = coordinator
            .create(CreateSoundLineJob {
                track_id: track_id.as_str().into(),
                audio_track: None,
            })
            .unwrap();
        let failed = wait_for_terminal(&coordinator, &created.id).await;

        assert_eq!(failed.status, SoundLineStatus::Failed);
        assert_eq!(failed.audio_track, None);
        assert_eq!(
            failed.error_code.as_deref(),
            Some("sound_line_source_unavailable")
        );
        assert_eq!(runner.calls().len(), 2, "probe then extraction");
        assert!(
            services
                .media_analysis()
                .list_word_timelines(&track_id)
                .unwrap()
                .is_empty()
        );
        while let Ok(event) = events.try_recv() {
            assert_ne!(event.event, EventName::SoundLineCompleted);
        }
    }

    #[tokio::test]
    async fn multitrack_failure_is_idempotent_and_retry_keeps_provenance() {
        let (coordinator, _services, runner, mut events, track_id, _temp_dir) =
            coordinator_fixture(["0", "1"], true);
        let request = || CreateSoundLineJob {
            track_id: track_id.as_str().into(),
            audio_track: None,
        };

        let first = coordinator.create(request()).unwrap();
        let duplicate = coordinator.create(request()).unwrap();
        assert_eq!(duplicate.id, first.id);
        let failed = wait_for_terminal(&coordinator, &first.id).await;
        assert_eq!(failed.status, SoundLineStatus::Failed);
        assert_eq!(failed.error_code.as_deref(), Some("audio_track_required"));
        assert_eq!(runner.calls().len(), 1, "ffmpeg must not run");

        let retried = coordinator.retry(&first.id).unwrap();
        assert_eq!(retried.retry_of_job_id.as_deref(), Some(first.id.as_str()));
        assert_eq!(retried.audio_track, None);
        let retried = wait_for_terminal(&coordinator, &retried.id).await;
        assert_eq!(retried.status, SoundLineStatus::Failed);
        assert_eq!(retried.error_code.as_deref(), Some("audio_track_required"));
        assert_eq!(runner.calls().len(), 2, "each attempt probes exactly once");
        while let Ok(event) = events.try_recv() {
            assert_ne!(event.event, EventName::SoundLineCompleted);
        }
    }

    #[tokio::test]
    async fn coordinator_cancel_stays_cancelled_and_emits_no_completion() {
        let runner = Arc::new(BlockingFfmpegRunner::default());
        let ffmpeg_started = runner.ffmpeg_started.clone();
        let (coordinator, _services, mut events, track_id, _temp_dir) =
            coordinator_fixture_with_runner(runner.clone(), true);
        let started = ffmpeg_started.notified();
        let created = coordinator
            .create(CreateSoundLineJob {
                track_id: track_id.as_str().into(),
                audio_track: None,
            })
            .unwrap();
        started.await;

        let cancelled = coordinator.cancel(&created.id).unwrap();
        assert_eq!(cancelled.status, SoundLineStatus::Cancelled);
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert_eq!(
            coordinator.get(&created.id).unwrap().unwrap().status,
            SoundLineStatus::Cancelled
        );
        assert_eq!(runner.calls.lock().unwrap().len(), 2);
        while let Ok(event) = events.try_recv() {
            assert_ne!(event.event, EventName::SoundLineCompleted);
        }
    }
}
