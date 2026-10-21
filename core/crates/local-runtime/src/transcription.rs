use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::Duration;

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, CreateRecordingTranscriptionRequest, TranscriptionRepository,
    now_ms,
};
use domain::{
    RecordingTranscriptProvenance, RecordingTranscriptionJob, RecordingTranscriptionJobId,
    RecordingTranscriptionStatus, TranscriptionModelDescriptor, TranscriptionModelId,
    TranscriptionModelState, TranscriptionProviderInfo, TranscriptionQuality, TranscriptionSegment,
};
use fs2::FileExt;
use tokio::sync::{Semaphore, broadcast};

use crate::download::{ArtifactDownloader, DownloadProgress, ReqwestArtifactDownloader};
use crate::process::{CancellationProbe, ProcessRunner, ProcessSpec, TokioProcessRunner};
use crate::runtime_support::{file_id, hash_file, io_error, resolve_tool, support_dir};

/// Coordinates transcription of short microphone recordings, which consume an
/// existing `RecordingAsset` and never import subtitle tracks. Whole-media
/// transcription jobs have been removed; the model catalog methods retained
/// here (and exposed over HTTP) serve recording-based shadowing and speaking.
#[derive(Clone)]
pub struct RecordingTranscriptionCoordinator {
    services: AppServices,
    repository: Arc<dyn TranscriptionRepository>,
    events: broadcast::Sender<EventEnvelope>,
    queue: Arc<Semaphore>,
    model_dir: PathBuf,
    temp_dir: PathBuf,
    process_runner: Arc<dyn ProcessRunner>,
    downloader: Arc<dyn ArtifactDownloader>,
    recording_jobs: Arc<Mutex<HashMap<RecordingTranscriptionJobId, RecordingTranscriptionJob>>>,
    model_installs: Arc<Mutex<ModelInstallRegistry>>,
}

pub type TranscriptionModelInstallFuture = Pin<
    Box<
        dyn Future<Output = Result<TranscriptionModelDescriptor, ApplicationError>>
            + Send
            + 'static,
    >,
>;

#[derive(Default)]
struct ModelInstallRegistry {
    active: HashMap<String, ActiveModelInstall>,
}

struct ActiveModelInstall {
    generation: u64,
    cancelled: Arc<AtomicBool>,
    _owner_lock: Arc<File>,
}

struct ModelInstallTicket {
    id: TranscriptionModelId,
    generation: u64,
    cancelled: Arc<AtomicBool>,
    model: TranscriptionModelDescriptor,
    url: String,
    path: PathBuf,
    partial: PathBuf,
}

enum ModelInstallReservation {
    Existing { installation_started: bool },
    Started(Box<ModelInstallTicket>),
}

pub struct TranscriptionModelInstallStart {
    /// True when this request started an install or found a live owner already
    /// running it. False means no background install was accepted.
    pub installation_started: bool,
    /// Present only when this coordinator owns the install task and must spawn
    /// or await it.
    pub future: Option<TranscriptionModelInstallFuture>,
}

static NEXT_MODEL_INSTALL_GENERATION: AtomicU64 = AtomicU64::new(1);

fn shared_model_install_registry(model_dir: &Path) -> Arc<Mutex<ModelInstallRegistry>> {
    static REGISTRIES: OnceLock<Mutex<HashMap<PathBuf, Weak<Mutex<ModelInstallRegistry>>>>> =
        OnceLock::new();
    let mut suffix = Vec::new();
    let mut ancestor = model_dir;
    while !ancestor.exists() {
        let Some(name) = ancestor.file_name() else {
            break;
        };
        suffix.push(name.to_os_string());
        let Some(parent) = ancestor.parent() else {
            break;
        };
        ancestor = parent;
    }
    let mut key = std::fs::canonicalize(ancestor).unwrap_or_else(|_| {
        if ancestor.is_absolute() {
            ancestor.to_path_buf()
        } else {
            std::env::current_dir().unwrap_or_default().join(ancestor)
        }
    });
    for segment in suffix.into_iter().rev() {
        key.push(segment);
    }
    let registries = REGISTRIES.get_or_init(|| Mutex::new(HashMap::new()));
    let mut registries = registries
        .lock()
        .expect("transcription model registry map mutex poisoned");
    registries.retain(|_, registry| registry.strong_count() > 0);
    if let Some(registry) = registries.get(&key).and_then(Weak::upgrade) {
        return registry;
    }
    let registry = Arc::new(Mutex::new(ModelInstallRegistry::default()));
    registries.insert(key, Arc::downgrade(&registry));
    registry
}

impl RecordingTranscriptionCoordinator {
    pub fn new(
        services: AppServices,
        repository: Arc<dyn TranscriptionRepository>,
        events: broadcast::Sender<EventEnvelope>,
    ) -> Result<Self, ApplicationError> {
        Self::new_with_adapters(
            services,
            repository,
            events,
            Arc::new(TokioProcessRunner),
            Arc::new(ReqwestArtifactDownloader),
        )
    }

    pub fn new_with_process_runner(
        services: AppServices,
        repository: Arc<dyn TranscriptionRepository>,
        events: broadcast::Sender<EventEnvelope>,
        process_runner: Arc<dyn ProcessRunner>,
    ) -> Result<Self, ApplicationError> {
        Self::new_with_adapters(
            services,
            repository,
            events,
            process_runner,
            Arc::new(ReqwestArtifactDownloader),
        )
    }

    pub fn new_with_adapters(
        services: AppServices,
        repository: Arc<dyn TranscriptionRepository>,
        events: broadcast::Sender<EventEnvelope>,
        process_runner: Arc<dyn ProcessRunner>,
        downloader: Arc<dyn ArtifactDownloader>,
    ) -> Result<Self, ApplicationError> {
        let support = support_dir();
        Self::new_with_adapters_and_dirs(
            services,
            repository,
            events,
            process_runner,
            downloader,
            support.join("models/transcription/whisper.cpp"),
            std::env::temp_dir().join("LLPlayerNext/transcription"),
        )
    }

    fn new_with_adapters_and_dirs(
        services: AppServices,
        repository: Arc<dyn TranscriptionRepository>,
        events: broadcast::Sender<EventEnvelope>,
        process_runner: Arc<dyn ProcessRunner>,
        downloader: Arc<dyn ArtifactDownloader>,
        model_dir: PathBuf,
        temp_dir: PathBuf,
    ) -> Result<Self, ApplicationError> {
        let model_installs = shared_model_install_registry(&model_dir);
        let value = Self {
            services,
            repository,
            events,
            queue: Arc::new(Semaphore::new(1)),
            model_dir,
            temp_dir,
            process_runner,
            downloader,
            recording_jobs: Arc::default(),
            model_installs,
        };
        // Best-effort cleanup of stale work directories left behind when a
        // previous run exited before the detached recording task could remove
        // them. Safe at startup because no jobs are running yet.
        let _ = std::fs::remove_dir_all(&value.temp_dir);
        value.seed_catalog()?;
        Ok(value)
    }

    pub fn providers(&self) -> Vec<TranscriptionProviderInfo> {
        let runtime = resolve_tool("LLPLAYERNEXT_WHISPER_CLI", "whisper-cli");
        vec![TranscriptionProviderInfo {
            id: "whisper.cpp".into(),
            display_name: "whisper.cpp".into(),
            runtime_id: "whisper.cpp-cli".into(),
            runtime_version: runtime
                .as_ref()
                .and_then(|path| path.file_name())
                .and_then(|name| name.to_str())
                .unwrap_or("unavailable")
                .into(),
            available: runtime.is_some(),
            supports_translation: true,
            supported_languages: vec!["auto".into(), "en".into(), "multilingual".into()],
            diagnostic: runtime
                .is_none()
                .then_some("Bundled whisper-cli was not found.".into()),
        }]
    }

    pub fn models(&self) -> Result<Vec<TranscriptionModelDescriptor>, ApplicationError> {
        self.repository.list_models()
    }

    pub fn recording_transcription_job(
        &self,
        id: &RecordingTranscriptionJobId,
    ) -> Option<RecordingTranscriptionJob> {
        self.recording_jobs
            .lock()
            .expect("recording transcription jobs mutex poisoned")
            .get(id)
            .cloned()
    }

    pub fn create_recording_transcription(
        self: Arc<Self>,
        request: CreateRecordingTranscriptionRequest,
    ) -> Result<RecordingTranscriptionJob, ApplicationError> {
        let recording_id = domain::RecordingAssetId::parse(request.recording_id)?;
        let recording = self
            .services
            .recordings()
            .recording_asset(&recording_id)?
            .ok_or(ApplicationError::NotFound("recording asset"))?;
        validate_recording_input(&recording)?;
        let model_id = TranscriptionModelId::parse(request.model_id)?;
        let model = self
            .repository
            .get_model(&model_id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;
        if !matches!(
            model.state,
            TranscriptionModelState::Installed | TranscriptionModelState::Custom
        ) {
            return Err(ApplicationError::Validation(
                "installed transcription model",
            ));
        }
        let requested_language = request
            .language
            .map(|value| value.trim().to_ascii_lowercase())
            .filter(|value| !value.is_empty())
            .or_else(|| Some(recording.language.as_str().to_owned()));
        if model.english_only
            && requested_language
                .as_deref()
                .is_some_and(|value| value != "en" && value != "auto")
        {
            return Err(ApplicationError::Validation(
                "English recording language for English-only model",
            ));
        }
        let provider = self.providers().into_iter().next().expect("first provider");
        if !provider.available {
            return Err(ApplicationError::Validation("transcription runtime"));
        }
        let created_at_ms = now_ms();
        let id = RecordingTranscriptionJobId::from_fingerprint(
            "recording-transcription-job",
            &format!(
                "{}:{}:{}:{created_at_ms}",
                recording.id.as_str(),
                model.id.as_str(),
                requested_language.as_deref().unwrap_or("auto")
            ),
        );
        let job = RecordingTranscriptionJob {
            id: id.clone(),
            recording_asset_id: recording.id,
            status: RecordingTranscriptionStatus::Queued,
            raw_transcript: None,
            segments: Vec::new(),
            provenance: RecordingTranscriptProvenance {
                provider_id: provider.id,
                provider_version: provider.runtime_version.clone(),
                runtime_id: provider.runtime_id,
                runtime_version: provider.runtime_version,
                model_id: model.id,
                model_revision: model.revision,
                model_checksum_sha256: model.checksum_sha256,
                recording_content_sha256: recording.audio.content_sha256,
                requested_language,
                detected_language: None,
            },
            error_code: None,
            error_message: None,
            created_at_ms,
            started_at_ms: None,
            completed_at_ms: None,
            latency_ms: None,
        };
        self.recording_jobs
            .lock()
            .expect("recording transcription jobs mutex poisoned")
            .insert(id.clone(), job.clone());
        tokio::spawn(async move { self.run_recording_transcription(id).await });
        Ok(job)
    }

    pub fn cancel_recording_transcription(
        &self,
        id: &RecordingTranscriptionJobId,
    ) -> Result<RecordingTranscriptionJob, ApplicationError> {
        let mut jobs = self
            .recording_jobs
            .lock()
            .expect("recording transcription jobs mutex poisoned");
        let job = jobs
            .get_mut(id)
            .ok_or(ApplicationError::NotFound("recording transcription job"))?;
        if !matches!(
            job.status,
            RecordingTranscriptionStatus::Completed
                | RecordingTranscriptionStatus::Failed
                | RecordingTranscriptionStatus::Cancelled
        ) {
            let completed_at_ms = now_ms();
            job.status = RecordingTranscriptionStatus::Cancelled;
            job.completed_at_ms = Some(completed_at_ms);
            job.latency_ms = Some(completed_at_ms.saturating_sub(job.created_at_ms));
        }
        Ok(job.clone())
    }

    /// Reserves the model synchronously, then returns the background install
    /// future. The reservation must happen before the HTTP handler responds so
    /// an immediate cancel cannot overtake the task's first poll.
    pub fn start_model_install(
        self: &Arc<Self>,
        id: TranscriptionModelId,
    ) -> Result<TranscriptionModelInstallStart, ApplicationError> {
        let reservation = self.reserve_model_install(id)?;
        let coordinator = self.clone();
        Ok(match reservation {
            ModelInstallReservation::Existing {
                installation_started,
            } => TranscriptionModelInstallStart {
                installation_started,
                future: None,
            },
            ModelInstallReservation::Started(ticket) => TranscriptionModelInstallStart {
                installation_started: true,
                future: Some(Box::pin(async move {
                    coordinator.run_model_install(*ticket).await
                })),
            },
        })
    }

    /// Compatibility wrapper for callers that want to await an install
    /// directly. HTTP callers should use `start_model_install` to reserve the
    /// work before acknowledging the request.
    pub async fn install_model(
        self: Arc<Self>,
        id: TranscriptionModelId,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        let start = RecordingTranscriptionCoordinator::start_model_install(&self, id.clone())?;
        match start.future {
            Some(future) => future.await,
            None => self.current_model(&id),
        }
    }

    fn reserve_model_install(
        &self,
        id: TranscriptionModelId,
    ) -> Result<ModelInstallReservation, ApplicationError> {
        let key = id.as_str().to_owned();
        let mut registry = self
            .model_installs
            .lock()
            .expect("transcription model installs mutex poisoned");
        let mut model = self
            .repository
            .get_model(&id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;

        if let Some(active) = registry.active.get(&key)
            && model.state == TranscriptionModelState::Installing
            && !active.cancelled.load(Ordering::SeqCst)
        {
            return Ok(ModelInstallReservation::Existing {
                installation_started: true,
            });
        }
        if let Some(stale) = registry.active.remove(&key) {
            stale.cancelled.store(true, Ordering::SeqCst);
        }
        if matches!(
            model.state,
            TranscriptionModelState::Installed | TranscriptionModelState::Custom
        ) {
            return Ok(ModelInstallReservation::Existing {
                installation_started: false,
            });
        }

        let url = model
            .download_url
            .clone()
            .ok_or(ApplicationError::Validation("model download URL"))?;
        std::fs::create_dir_all(&self.model_dir).map_err(io_error)?;
        let Some(owner_lock) = self.try_model_owner_lock(&id)? else {
            let _state_lock = self.lock_model_state(&id)?;
            let model = self.current_model(&id)?;
            return Ok(ModelInstallReservation::Existing {
                installation_started: model.state == TranscriptionModelState::Installing,
            });
        };
        let state_lock = self.lock_model_state(&id)?;
        model = self
            .repository
            .get_model(&id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;
        if model.state == TranscriptionModelState::Installing {
            self.recover_interrupted_install(&mut model)?;
            model = self
                .repository
                .get_model(&id)?
                .ok_or(ApplicationError::NotFound("transcription model"))?;
        }
        if matches!(
            model.state,
            TranscriptionModelState::Installed | TranscriptionModelState::Custom
        ) {
            return Ok(ModelInstallReservation::Existing {
                installation_started: false,
            });
        }
        self.remove_stale_install_partials(&id);

        let generation = NEXT_MODEL_INSTALL_GENERATION.fetch_add(1, Ordering::Relaxed);
        let cancelled = Arc::new(AtomicBool::new(false));
        let path = self.model_dir.join(format!("{}.bin", file_id(id.as_str())));
        let partial = self.model_dir.join(format!(
            "{}.{}.{}.bin.partial",
            file_id(id.as_str()),
            std::process::id(),
            generation
        ));
        model.state = TranscriptionModelState::Installing;
        model.installed_bytes = 0;
        model.error = None;
        model.updated_at_ms = now_ms();
        let model = self.repository.upsert_model(&model)?;
        registry.active.insert(
            key,
            ActiveModelInstall {
                generation,
                cancelled: cancelled.clone(),
                _owner_lock: owner_lock,
            },
        );
        drop(state_lock);
        self.emit(EventName::TranscriptionModelChanged, &model);

        Ok(ModelInstallReservation::Started(Box::new(
            ModelInstallTicket {
                id,
                generation,
                cancelled,
                model,
                url,
                path,
                partial,
            },
        )))
    }

    async fn run_model_install(
        &self,
        ticket: ModelInstallTicket,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        let progress = Arc::new(TranscriptionDownloadProgress {
            repository: self.repository.clone(),
            events: self.events.clone(),
            active_installs: self.model_installs.clone(),
            model_dir: self.model_dir.clone(),
            model_id: ticket.id.clone(),
            generation: ticket.generation,
            cancelled: ticket.cancelled.clone(),
            expected_bytes: ticket.model.size_bytes,
        });
        let result = async {
            if progress.is_cancelled()? {
                return Err(model_install_cancelled());
            }
            let download = self
                .downloader
                .download(&ticket.url, &ticket.partial, progress.clone());
            tokio::pin!(download);
            loop {
                tokio::select! {
                    result = &mut download => {
                        result?;
                        break;
                    }
                    _ = tokio::time::sleep(Duration::from_millis(200)) => {
                        if progress.is_cancelled()? {
                            return Err(model_install_cancelled());
                        }
                    }
                }
            }
            if progress.is_cancelled()? {
                return Err(model_install_cancelled());
            }
            let downloaded_bytes = std::fs::metadata(&ticket.partial).map_err(io_error)?.len();
            if downloaded_bytes != ticket.model.size_bytes {
                return Err(ApplicationError::Repository(
                    "model size does not match catalog size".into(),
                ));
            }
            let checksum = hash_file(&ticket.partial)?;
            if checksum != ticket.model.checksum_sha256 {
                return Err(ApplicationError::Repository(
                    "model checksum mismatch".into(),
                ));
            }
            if progress.is_cancelled()? {
                return Err(model_install_cancelled());
            }
            Ok::<_, ApplicationError>(())
        }
        .await;

        match result {
            Ok(()) => self.publish_model_install(ticket).await,
            Err(error) => self.fail_model_install(ticket, error).await,
        }
    }

    async fn publish_model_install(
        &self,
        ticket: ModelInstallTicket,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        enum PublishResult {
            Stale,
            Missing,
            Current(TranscriptionModelDescriptor),
            RenameFailed(ApplicationError),
            Persisted(Result<TranscriptionModelDescriptor, ApplicationError>),
        }

        let outcome = {
            let mut registry = self
                .model_installs
                .lock()
                .expect("transcription model installs mutex poisoned");
            if !install_is_current(&registry, &ticket) {
                PublishResult::Stale
            } else {
                let _state_lock = self.lock_model_state(&ticket.id)?;
                if let Some(mut model) = self.repository.get_model(&ticket.id)? {
                    if model.state != TranscriptionModelState::Installing {
                        registry.active.remove(ticket.id.as_str());
                        PublishResult::Current(model)
                    } else if let Err(error) = std::fs::rename(&ticket.partial, &ticket.path) {
                        PublishResult::RenameFailed(io_error(error))
                    } else {
                        model.state = TranscriptionModelState::Installed;
                        model.local_path = Some(ticket.path.to_string_lossy().into_owned());
                        model.installed_bytes = model.size_bytes;
                        model.error = None;
                        model.updated_at_ms = now_ms();
                        let persisted = self.repository.upsert_model(&model);
                        registry.active.remove(ticket.id.as_str());
                        PublishResult::Persisted(persisted)
                    }
                } else {
                    registry.active.remove(ticket.id.as_str());
                    PublishResult::Missing
                }
            }
        };

        match outcome {
            PublishResult::Stale => {
                let _ = tokio::fs::remove_file(&ticket.partial).await;
                self.current_model(&ticket.id)
            }
            PublishResult::Missing => {
                let _ = tokio::fs::remove_file(&ticket.partial).await;
                Err(ApplicationError::NotFound("transcription model"))
            }
            PublishResult::Current(model) => {
                let _ = tokio::fs::remove_file(&ticket.partial).await;
                Ok(model)
            }
            PublishResult::RenameFailed(error) => self.fail_model_install(ticket, error).await,
            PublishResult::Persisted(persisted) => {
                let model = persisted?;
                self.emit(EventName::TranscriptionModelChanged, &model);
                Ok(model)
            }
        }
    }

    async fn fail_model_install(
        &self,
        ticket: ModelInstallTicket,
        error: ApplicationError,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        let _ = tokio::fs::remove_file(&ticket.partial).await;
        let mut registry = self
            .model_installs
            .lock()
            .expect("transcription model installs mutex poisoned");
        if !install_is_current(&registry, &ticket) {
            drop(registry);
            return self.current_model(&ticket.id);
        }
        let _state_lock = self.lock_model_state(&ticket.id)?;
        let Some(mut model) = self.repository.get_model(&ticket.id)? else {
            registry.active.remove(ticket.id.as_str());
            return Err(ApplicationError::NotFound("transcription model"));
        };
        if model.state != TranscriptionModelState::Installing {
            registry.active.remove(ticket.id.as_str());
            return Ok(model);
        }
        model.state = TranscriptionModelState::Failed;
        model.installed_bytes = 0;
        model.error = Some(error.to_string());
        model.updated_at_ms = now_ms();
        let persisted = self.repository.upsert_model(&model);
        registry.active.remove(ticket.id.as_str());
        drop(registry);
        let model = persisted?;
        self.emit(EventName::TranscriptionModelChanged, &model);
        Ok(model)
    }

    fn current_model(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        self.repository
            .get_model(id)?
            .ok_or(ApplicationError::NotFound("transcription model"))
    }

    fn try_model_owner_lock(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<Option<Arc<File>>, ApplicationError> {
        std::fs::create_dir_all(&self.model_dir).map_err(io_error)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(model_owner_lock_path(&self.model_dir, id))
            .map_err(io_error)?;
        match lock.try_lock_exclusive() {
            Ok(()) => Ok(Some(Arc::new(lock))),
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => Ok(None),
            Err(error) => Err(io_error(error)),
        }
    }

    fn lock_model_state(&self, id: &TranscriptionModelId) -> Result<File, ApplicationError> {
        open_model_state_lock(&self.model_dir, id)
    }

    pub fn register_custom_model(
        &self,
        path: String,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        let metadata = std::fs::metadata(&path)
            .map_err(|error| ApplicationError::Repository(error.to_string()))?;
        let checksum = hash_file(Path::new(&path))?;
        let id = TranscriptionModelId::from_fingerprint("custom-transcription-model", &checksum);
        let english_only = Path::new(&path)
            .file_name()
            .and_then(|value| value.to_str())
            .is_some_and(english_only_model_name);
        self.repository.upsert_model(&TranscriptionModelDescriptor {
            id,
            provider_id: "whisper.cpp".into(),
            display_name: Path::new(&path)
                .file_name()
                .and_then(|v| v.to_str())
                .unwrap_or("Custom model")
                .into(),
            family: "custom".into(),
            revision: checksum.clone(),
            checksum_sha256: checksum,
            download_url: None,
            local_path: Some(path),
            size_bytes: metadata.len(),
            quality: TranscriptionQuality::Balanced,
            english_only,
            supports_translation: !english_only,
            state: TranscriptionModelState::Custom,
            installed_bytes: metadata.len(),
            error: None,
            license: "User supplied".into(),
            updated_at_ms: now_ms(),
        })
    }

    pub async fn delete_model(&self, id: &TranscriptionModelId) -> Result<(), ApplicationError> {
        let in_flight_recording = self
            .recording_jobs
            .lock()
            .expect("recording transcription jobs mutex poisoned")
            .values()
            .any(|job| {
                job.provenance.model_id == *id
                    && matches!(
                        job.status,
                        RecordingTranscriptionStatus::Queued
                            | RecordingTranscriptionStatus::Transcribing
                    )
            });
        if in_flight_recording {
            return Err(ApplicationError::Validation(
                "model is used by an active recording transcription",
            ));
        }
        let mut registry = self
            .model_installs
            .lock()
            .expect("transcription model installs mutex poisoned");
        let state_lock = self.lock_model_state(id)?;
        let Some(mut model) = self.repository.get_model(id)? else {
            self.repository.delete_model(id)?;
            return Ok(());
        };
        let active = registry.active.remove(id.as_str());
        if let Some(active) = &active {
            active.cancelled.store(true, Ordering::SeqCst);
        }
        if model.state == TranscriptionModelState::Installing {
            self.repository.delete_model(id)?;
            drop(state_lock);
            drop(active);
            return Ok(());
        }
        if model.state == TranscriptionModelState::Installed
            && let Some(path) = model.local_path.clone()
        {
            if let Err(error) = std::fs::remove_file(path)
                && error.kind() != std::io::ErrorKind::NotFound
            {
                return Err(io_error(error));
            }
            model.local_path = None;
            model.installed_bytes = 0;
            model.state = TranscriptionModelState::Downloadable;
            model.error = None;
            model.updated_at_ms = now_ms();
            self.repository.upsert_model(&model)?;
            self.emit(EventName::TranscriptionModelChanged, &model);
            drop(state_lock);
            drop(active);
            return Ok(());
        }
        self.repository.delete_model(id)?;
        drop(state_lock);
        drop(active);
        Ok(())
    }

    pub fn cancel_model_install(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        let mut registry = self
            .model_installs
            .lock()
            .expect("transcription model installs mutex poisoned");
        let state_lock = self.lock_model_state(id)?;
        let mut model = self
            .repository
            .get_model(id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;
        let active = if model.state == TranscriptionModelState::Installing {
            registry.active.remove(id.as_str())
        } else {
            None
        };
        if model.state == TranscriptionModelState::Installing {
            if let Some(active) = &active {
                active.cancelled.store(true, Ordering::SeqCst);
            }
            model.state = TranscriptionModelState::Downloadable;
            model.installed_bytes = 0;
            model.error = Some("Installation cancelled by user.".into());
            model.updated_at_ms = now_ms();
            model = self.repository.upsert_model(&model)?;
            self.emit(EventName::TranscriptionModelChanged, &model);
        }
        drop(state_lock);
        drop(active);
        Ok(model)
    }

    async fn run_recording_transcription(self: Arc<Self>, id: RecordingTranscriptionJobId) {
        let _permit = match self.queue.acquire().await {
            Ok(value) => value,
            Err(_) => return,
        };
        let result = self.execute_recording_transcription(&id).await;
        let _ = tokio::fs::remove_dir_all(self.temp_dir.join("recordings").join(id.as_str())).await;
        if let Err(error) = result {
            let mut jobs = self
                .recording_jobs
                .lock()
                .expect("recording transcription jobs mutex poisoned");
            if let Some(job) = jobs.get_mut(&id)
                && job.status != RecordingTranscriptionStatus::Cancelled
            {
                let completed_at_ms = now_ms();
                job.status = RecordingTranscriptionStatus::Failed;
                job.error_code = Some("recording_transcription_failed".into());
                job.error_message = Some(error.to_string());
                job.completed_at_ms = Some(completed_at_ms);
                job.latency_ms = Some(completed_at_ms.saturating_sub(job.created_at_ms));
            }
        }
    }

    async fn execute_recording_transcription(
        &self,
        id: &RecordingTranscriptionJobId,
    ) -> Result<(), ApplicationError> {
        let mut job = self
            .recording_transcription_job(id)
            .ok_or(ApplicationError::NotFound("recording transcription job"))?;
        if job.status == RecordingTranscriptionStatus::Cancelled {
            return Ok(());
        }
        let recording = self
            .services
            .recordings()
            .recording_asset(&job.recording_asset_id)?
            .ok_or(ApplicationError::NotFound("recording asset"))?;
        validate_recording_input(&recording)?;
        if hash_file(Path::new(&recording.file_path))? != recording.audio.content_sha256 {
            return Err(ApplicationError::Validation("recording file integrity"));
        }
        let model = self
            .repository
            .get_model(&job.provenance.model_id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;
        let model_path = model
            .local_path
            .ok_or(ApplicationError::Validation("model path"))?;
        let whisper = resolve_tool("LLPLAYERNEXT_WHISPER_CLI", "whisper-cli")
            .ok_or(ApplicationError::Validation("whisper runtime"))?;
        let work = self.temp_dir.join("recordings").join(id.as_str());
        tokio::fs::create_dir_all(&work).await.map_err(io_error)?;
        let output = work.join("result");
        let started_at_ms = now_ms();
        job.status = RecordingTranscriptionStatus::Transcribing;
        job.started_at_ms = Some(started_at_ms);
        self.update_recording_job(job);
        let args = vec![
            "-m".into(),
            model_path,
            "-f".into(),
            recording.file_path,
            // Standard JSON carries segment offsets/text without the token
            // dump. whisper.cpp full JSON can contain split non-ASCII token
            // bytes (not valid UTF-8 JSON) for Mandarin recordings.
            "-oj".into(),
            "-of".into(),
            output.to_string_lossy().into_owned(),
            "-l".into(),
            self.recording_transcription_job(id)
                .and_then(|value| value.provenance.requested_language)
                .unwrap_or_else(|| "auto".into()),
        ];
        self.process_runner
            .run(
                ProcessSpec::new(whisper, args),
                Arc::new(RecordingTranscriptionCancellation {
                    jobs: self.recording_jobs.clone(),
                    job_id: id.clone(),
                }),
            )
            .await?;
        let bytes = tokio::fs::read(output.with_extension("json"))
            .await
            .map_err(io_error)?;
        let result = parse_recording_transcription_json(&bytes)?;
        let completed_at_ms = now_ms();
        let mut job = self
            .recording_transcription_job(id)
            .ok_or(ApplicationError::NotFound("recording transcription job"))?;
        if job.status == RecordingTranscriptionStatus::Cancelled {
            return Ok(());
        }
        job.status = RecordingTranscriptionStatus::Completed;
        job.raw_transcript = Some(
            result
                .segments
                .iter()
                .map(|segment| segment.text.trim())
                .filter(|text| !text.is_empty())
                .collect::<Vec<_>>()
                .join(" "),
        );
        job.segments = result.segments;
        job.provenance.detected_language = result.detected_language;
        job.completed_at_ms = Some(completed_at_ms);
        job.latency_ms = Some(completed_at_ms.saturating_sub(started_at_ms));
        self.update_recording_job(job);
        Ok(())
    }

    fn update_recording_job(&self, job: RecordingTranscriptionJob) {
        self.recording_jobs
            .lock()
            .expect("recording transcription jobs mutex poisoned")
            .insert(job.id.clone(), job);
    }

    fn emit<T: serde::Serialize>(&self, event: EventName, value: &T) {
        let _ = self.events.send(EventEnvelope::v1(
            event,
            serde_json::to_value(value).expect("transcription event serializes"),
        ));
    }

    fn seed_catalog(&self) -> Result<(), ApplicationError> {
        let existing = self.repository.list_models()?;
        let catalog = catalog();
        {
            // This method is called during coordinator construction. Keeping
            // the in-process registry and cross-process owner lease makes an
            // accidental later call safe: active models are skipped, and no
            // new installation can be reserved midway through recovery.
            let registry = self
                .model_installs
                .lock()
                .expect("transcription model installs mutex poisoned");
            let mut partial_models = existing.clone();
            partial_models.extend(
                catalog
                    .iter()
                    .filter(|model| !existing.iter().any(|value| value.id == model.id))
                    .cloned(),
            );
            for known_model in partial_models {
                if registry.active.contains_key(known_model.id.as_str()) {
                    continue;
                }
                let Some(_owner_lock) = self.try_model_owner_lock(&known_model.id)? else {
                    // A different Core process still owns the live download.
                    // Leave both its database state and partial untouched.
                    continue;
                };
                let _state_lock = self.lock_model_state(&known_model.id)?;
                if let Some(mut current) = self.repository.get_model(&known_model.id)?
                    && current.state == TranscriptionModelState::Installing
                    && !registry.active.contains_key(current.id.as_str())
                {
                    self.recover_interrupted_install(&mut current)?;
                }
                self.remove_stale_install_partials(&known_model.id);
            }
        }
        for model in catalog {
            if existing.iter().any(|value| value.id == model.id) {
                continue;
            }
            self.repository.upsert_model(&model)?;
        }
        Ok(())
    }

    fn recover_interrupted_install(
        &self,
        model: &mut TranscriptionModelDescriptor,
    ) -> Result<(), ApplicationError> {
        let canonical_path = self
            .model_dir
            .join(format!("{}.bin", file_id(model.id.as_str())));
        let recovered_path = model
            .local_path
            .as_deref()
            .map(PathBuf::from)
            .filter(|path| model_file_matches(path, &model.checksum_sha256))
            .or_else(|| {
                model_file_matches(&canonical_path, &model.checksum_sha256)
                    .then_some(canonical_path)
            });

        if let Some(path) = recovered_path {
            model.state = TranscriptionModelState::Installed;
            model.local_path = Some(path.to_string_lossy().into_owned());
            model.installed_bytes = std::fs::metadata(path).map_err(io_error)?.len();
            model.error = None;
        } else {
            model.state = TranscriptionModelState::Downloadable;
            model.local_path = None;
            model.installed_bytes = 0;
            model.error = Some(
                "Installation was interrupted before the model was verified. Retry the download."
                    .into(),
            );
        }
        model.updated_at_ms = now_ms();
        let model = self.repository.upsert_model(model)?;
        self.emit(EventName::TranscriptionModelChanged, &model);
        Ok(())
    }

    fn remove_stale_install_partials(&self, id: &TranscriptionModelId) {
        let Ok(entries) = std::fs::read_dir(&self.model_dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_symlink() || !path.is_file() {
                continue;
            }
            let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
                continue;
            };
            if generation_partial_identity(name, id).is_some() {
                let _ = std::fs::remove_file(&path);
            }
        }
    }
}

#[async_trait::async_trait]
impl application::RecordingTranscriptionService for RecordingTranscriptionCoordinator {
    fn providers(&self) -> Vec<TranscriptionProviderInfo> {
        RecordingTranscriptionCoordinator::providers(self)
    }

    fn models(&self) -> Result<Vec<TranscriptionModelDescriptor>, ApplicationError> {
        RecordingTranscriptionCoordinator::models(self)
    }

    fn request_model_install(
        self: Arc<Self>,
        id: TranscriptionModelId,
    ) -> Result<bool, ApplicationError> {
        let start = RecordingTranscriptionCoordinator::start_model_install(&self, id)?;
        if let Some(install) = start.future {
            tokio::spawn(async move {
                let _ = install.await;
            });
        }
        Ok(start.installation_started)
    }

    fn register_custom_model(
        &self,
        path: String,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        RecordingTranscriptionCoordinator::register_custom_model(self, path)
    }

    fn cancel_model_install(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        RecordingTranscriptionCoordinator::cancel_model_install(self, id)
    }

    async fn delete_model(&self, id: &TranscriptionModelId) -> Result<(), ApplicationError> {
        RecordingTranscriptionCoordinator::delete_model(self, id).await
    }

    fn create_recording_transcription(
        self: Arc<Self>,
        request: CreateRecordingTranscriptionRequest,
    ) -> Result<RecordingTranscriptionJob, ApplicationError> {
        RecordingTranscriptionCoordinator::create_recording_transcription(self, request)
    }

    fn recording_transcription_job(
        &self,
        id: &RecordingTranscriptionJobId,
    ) -> Option<RecordingTranscriptionJob> {
        RecordingTranscriptionCoordinator::recording_transcription_job(self, id)
    }

    fn cancel_recording_transcription(
        &self,
        id: &RecordingTranscriptionJobId,
    ) -> Result<RecordingTranscriptionJob, ApplicationError> {
        RecordingTranscriptionCoordinator::cancel_recording_transcription(self, id)
    }
}

fn model_file_matches(path: &Path, checksum_sha256: &str) -> bool {
    path.is_file() && hash_file(path).is_ok_and(|checksum| checksum == checksum_sha256)
}

fn model_owner_lock_path(model_dir: &Path, id: &TranscriptionModelId) -> PathBuf {
    model_dir.join(format!("{}.install.lock", file_id(id.as_str())))
}

fn model_state_lock_path(model_dir: &Path, id: &TranscriptionModelId) -> PathBuf {
    model_dir.join(format!("{}.state.lock", file_id(id.as_str())))
}

fn open_model_state_lock(
    model_dir: &Path,
    id: &TranscriptionModelId,
) -> Result<File, ApplicationError> {
    std::fs::create_dir_all(model_dir).map_err(io_error)?;
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(model_state_lock_path(model_dir, id))
        .map_err(io_error)?;
    lock.lock_exclusive().map_err(io_error)?;
    Ok(lock)
}

fn model_install_cancelled() -> ApplicationError {
    ApplicationError::Repository("model installation cancelled".into())
}

fn generation_partial_identity(filename: &str, id: &TranscriptionModelId) -> Option<(u32, u64)> {
    let prefix = format!("{}.", file_id(id.as_str()));
    let suffix = ".bin.partial";
    let identity = filename.strip_prefix(&prefix)?.strip_suffix(suffix)?;
    let (process_id, generation) = identity.split_once('.')?;
    if generation.contains('.') {
        return None;
    }
    let process_id = process_id.parse::<u32>().ok()?;
    let generation = generation.parse::<u64>().ok()?;
    (process_id != 0 && generation != 0).then_some((process_id, generation))
}

struct RecordingTranscriptionCancellation {
    jobs: Arc<Mutex<HashMap<RecordingTranscriptionJobId, RecordingTranscriptionJob>>>,
    job_id: RecordingTranscriptionJobId,
}

struct TranscriptionDownloadProgress {
    repository: Arc<dyn TranscriptionRepository>,
    events: broadcast::Sender<EventEnvelope>,
    active_installs: Arc<Mutex<ModelInstallRegistry>>,
    model_dir: PathBuf,
    model_id: TranscriptionModelId,
    generation: u64,
    cancelled: Arc<AtomicBool>,
    expected_bytes: u64,
}

impl DownloadProgress for TranscriptionDownloadProgress {
    fn is_cancelled(&self) -> Result<bool, ApplicationError> {
        if self.cancelled.load(Ordering::SeqCst) {
            return Ok(true);
        }
        let registry = self
            .active_installs
            .lock()
            .expect("transcription model installs mutex poisoned");
        if registry
            .active
            .get(self.model_id.as_str())
            .is_none_or(|active| active.generation != self.generation)
        {
            return Ok(true);
        }
        let _state_lock = open_model_state_lock(&self.model_dir, &self.model_id)?;
        Ok(self
            .repository
            .get_model(&self.model_id)?
            .is_none_or(|model| model.state != TranscriptionModelState::Installing))
    }

    fn downloaded(&self, bytes: u64) -> Result<(), ApplicationError> {
        let registry = self
            .active_installs
            .lock()
            .expect("transcription model installs mutex poisoned");
        if self.cancelled.load(Ordering::SeqCst)
            || registry
                .active
                .get(self.model_id.as_str())
                .is_none_or(|active| active.generation != self.generation)
        {
            return Ok(());
        }
        if bytes > self.expected_bytes {
            return Err(ApplicationError::Repository(
                "model download exceeded catalog size".into(),
            ));
        }
        let _state_lock = open_model_state_lock(&self.model_dir, &self.model_id)?;
        let Some(mut model) = self.repository.get_model(&self.model_id)? else {
            return Ok(());
        };
        if model.state != TranscriptionModelState::Installing {
            return Ok(());
        }
        model.installed_bytes = bytes;
        model.updated_at_ms = now_ms();
        let model = self.repository.upsert_model(&model)?;
        let _ = self.events.send(EventEnvelope::v1(
            EventName::TranscriptionModelChanged,
            serde_json::to_value(model).expect("transcription model serializes"),
        ));
        Ok(())
    }
}

fn install_is_current(registry: &ModelInstallRegistry, ticket: &ModelInstallTicket) -> bool {
    !ticket.cancelled.load(Ordering::SeqCst)
        && registry
            .active
            .get(ticket.id.as_str())
            .is_some_and(|active| {
                active.generation == ticket.generation && !active.cancelled.load(Ordering::SeqCst)
            })
}

impl CancellationProbe for RecordingTranscriptionCancellation {
    fn is_cancelled(&self) -> Result<bool, ApplicationError> {
        Ok(self
            .jobs
            .lock()
            .expect("recording transcription jobs mutex poisoned")
            .get(&self.job_id)
            .is_some_and(|job| job.status == RecordingTranscriptionStatus::Cancelled))
    }
}

fn validate_recording_input(recording: &domain::RecordingAsset) -> Result<(), ApplicationError> {
    if recording.duration_ms > 120_000
        || recording.audio.container != "wav"
        || recording.audio.codec != "pcm_s16le"
        || recording.audio.sample_rate_hz != 16_000
        || recording.audio.channels != 1
        || recording.audio.sample_format != "s16"
    {
        return Err(ApplicationError::Validation(
            "16 kHz mono PCM s16 WAV recording",
        ));
    }
    let metadata = std::fs::metadata(&recording.file_path)
        .map_err(|_| ApplicationError::Validation("available recording file"))?;
    if metadata.len() != recording.audio.byte_length {
        return Err(ApplicationError::Validation("recording file byte length"));
    }
    Ok(())
}

fn parse_recording_transcription_json(
    bytes: &[u8],
) -> Result<domain::TranscriptionResult, ApplicationError> {
    let value: serde_json::Value = serde_json::from_slice(bytes)
        .map_err(|error| ApplicationError::Repository(error.to_string()))?;
    let detected_language = value
        .pointer("/result/language")
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned);
    let segments = value
        .get("transcription")
        .and_then(serde_json::Value::as_array)
        .ok_or(ApplicationError::Validation(
            "whisper.cpp recording transcription JSON",
        ))?
        .iter()
        .filter_map(|segment| {
            let offsets = segment.get("offsets")?;
            Some(TranscriptionSegment {
                start_ms: offsets.get("from")?.as_u64()?,
                end_ms: offsets.get("to")?.as_u64()?,
                text: segment.get("text")?.as_str()?.trim().to_owned(),
            })
        })
        .collect::<Vec<_>>();
    if segments.is_empty() {
        return Err(ApplicationError::Validation(
            "non-empty recording transcript",
        ));
    }
    Ok(domain::TranscriptionResult {
        detected_language,
        segments,
    })
}

fn catalog() -> Vec<TranscriptionModelDescriptor> {
    [
        (
            "base.en",
            147964211,
            "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
            TranscriptionQuality::Fast,
            true,
        ),
        (
            "base",
            147951465,
            "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            TranscriptionQuality::Fast,
            false,
        ),
        (
            "small.en",
            487614201,
            "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d",
            TranscriptionQuality::Balanced,
            true,
        ),
        (
            "small",
            487601967,
            "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
            TranscriptionQuality::Balanced,
            false,
        ),
        (
            "medium.en",
            1533774781,
            "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356",
            TranscriptionQuality::Accurate,
            true,
        ),
        (
            "medium",
            1533763059,
            "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
            TranscriptionQuality::Accurate,
            false,
        ),
    ]
    .into_iter()
    .map(
        |(name, size, checksum, quality, english_only)| TranscriptionModelDescriptor {
            id: TranscriptionModelId::parse(format!("whisper.cpp:{name}@main"))
                .expect("catalog ID"),
            provider_id: "whisper.cpp".into(),
            display_name: name.into(),
            family: "whisper".into(),
            revision: "main-80da2d8".into(),
            checksum_sha256: checksum.into(),
            download_url: Some(format!(
                "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{name}.bin"
            )),
            local_path: None,
            size_bytes: size,
            quality,
            english_only,
            supports_translation: !english_only,
            state: TranscriptionModelState::Downloadable,
            installed_bytes: 0,
            error: None,
            license: "MIT".into(),
            updated_at_ms: now_ms(),
        },
    )
    .collect()
}

fn dtw_preset_from_name(name: &str) -> Option<String> {
    let mut normalized = name.trim().to_ascii_lowercase();
    if normalized.is_empty() {
        return None;
    }
    if let Some(file_name) = Path::new(&normalized)
        .file_name()
        .and_then(|value| value.to_str())
    {
        normalized = file_name.to_string();
    }
    if let Some(stripped) = normalized.strip_suffix(".bin") {
        normalized = stripped.to_string();
    }
    normalized = normalized.replace('_', "-");
    for prefix in ["ggml-", "whisper-"] {
        if let Some(stripped) = normalized.strip_prefix(prefix) {
            normalized = stripped.to_string();
        }
    }
    if let Some(index) = normalized.find("-q") {
        normalized.truncate(index);
    }
    if let Some(index) = normalized.find(".q") {
        normalized.truncate(index);
    }
    let preset = match normalized.as_str() {
        "tiny" | "tiny.en" | "base" | "base.en" | "small" | "small.en" | "medium" | "medium.en" => {
            normalized
        }
        "large-v1" | "large.v1" => "large.v1".into(),
        "large-v2" | "large.v2" => "large.v2".into(),
        "large-v3" | "large.v3" => "large.v3".into(),
        "large-v3-turbo" | "large.v3.turbo" => "large.v3.turbo".into(),
        _ => return None,
    };
    Some(preset)
}

fn english_only_model_name(name: &str) -> bool {
    if dtw_preset_from_name(name).is_some_and(|preset| preset.ends_with(".en")) {
        return true;
    }
    let normalized = name.trim().to_ascii_lowercase().replace('_', "-");
    ["tiny", "base", "small", "medium"]
        .iter()
        .any(|family| normalized.contains(&format!("-{family}-en-")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::runtime_support::resolve_bundled_tool;
    use async_trait::async_trait;
    use fs2::FileExt;
    use persistence_sqlite::SqliteRepository;
    use sha2::{Digest, Sha256};
    use std::process::{Child, Command, Stdio};
    use std::thread;
    use std::time::Instant;
    use tokio::sync::{mpsc, oneshot};

    type StartedDownload = (PathBuf, oneshot::Sender<()>);
    const OWNER_LOCK_PATH_ENV: &str = "LISTEN_TEST_MODEL_OWNER_LOCK_PATH";
    const OWNER_LOCK_READY_ENV: &str = "LISTEN_TEST_MODEL_OWNER_LOCK_READY";
    const OWNER_LOCK_RELEASE_ENV: &str = "LISTEN_TEST_MODEL_OWNER_LOCK_RELEASE";

    struct SubprocessLockHolder {
        child: Option<Child>,
        release_path: PathBuf,
    }

    impl SubprocessLockHolder {
        fn start(directory: &Path, lock_path: &Path) -> Self {
            let ready_path = directory.join("owner-lock-ready");
            let release_path = directory.join("owner-lock-release");
            let child = Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "transcription::tests::subprocess_holds_model_owner_lock",
                    "--nocapture",
                ])
                .env(OWNER_LOCK_PATH_ENV, lock_path)
                .env(OWNER_LOCK_READY_ENV, &ready_path)
                .env(OWNER_LOCK_RELEASE_ENV, &release_path)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .unwrap();
            let mut holder = Self {
                child: Some(child),
                release_path,
            };
            let ready_deadline = Instant::now() + Duration::from_secs(10);
            while !ready_path.exists() {
                if let Some(status) = holder.child.as_mut().unwrap().try_wait().unwrap() {
                    panic!("owner-lock subprocess exited before locking: {status}");
                }
                if Instant::now() >= ready_deadline {
                    panic!("owner-lock subprocess did not acquire its lock in time");
                }
                thread::sleep(Duration::from_millis(10));
            }
            holder
        }

        fn terminate(mut self) {
            let mut child = self.child.take().unwrap();
            child.kill().unwrap();
            let status = child.wait().unwrap();
            assert!(
                !status.success(),
                "terminated owner should not exit cleanly"
            );
        }
    }

    impl Drop for SubprocessLockHolder {
        fn drop(&mut self) {
            let _ = std::fs::write(&self.release_path, b"release");
            if let Some(mut child) = self.child.take() {
                let _ = child.wait();
            }
        }
    }

    #[test]
    fn subprocess_holds_model_owner_lock() {
        let Some(lock_path) = std::env::var_os(OWNER_LOCK_PATH_ENV).map(PathBuf::from) else {
            return;
        };
        let ready_path = PathBuf::from(std::env::var_os(OWNER_LOCK_READY_ENV).unwrap());
        let release_path = PathBuf::from(std::env::var_os(OWNER_LOCK_RELEASE_ENV).unwrap());
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(lock_path)
            .unwrap();
        lock.lock_exclusive().unwrap();
        std::fs::write(ready_path, b"locked").unwrap();
        while !release_path.exists() {
            thread::sleep(Duration::from_millis(10));
        }
    }

    struct GatedArtifactDownloader {
        bytes: Vec<u8>,
        started: mpsc::UnboundedSender<StartedDownload>,
    }

    #[async_trait]
    impl ArtifactDownloader for GatedArtifactDownloader {
        async fn download(
            &self,
            _source: &str,
            destination: &Path,
            progress: Arc<dyn DownloadProgress>,
        ) -> Result<(), ApplicationError> {
            let (release, wait) = oneshot::channel();
            self.started
                .send((destination.to_path_buf(), release))
                .map_err(|_| ApplicationError::Repository("test gate was dropped".into()))?;
            // Deliberately finish even after cancellation. This models a
            // response that completed just as cancel arrived and verifies the
            // coordinator, rather than the transport adapter, owns publication.
            let _ = wait.await;
            tokio::fs::write(destination, &self.bytes)
                .await
                .map_err(io_error)?;
            progress.downloaded(self.bytes.len() as u64)
        }
    }

    fn model_install_fixture(
        downloader: Arc<dyn ArtifactDownloader>,
    ) -> (
        Arc<RecordingTranscriptionCoordinator>,
        Arc<SqliteRepository>,
        TranscriptionModelId,
        tempfile::TempDir,
    ) {
        let repository = Arc::new(SqliteRepository::in_memory().unwrap());
        let temp = tempfile::tempdir().unwrap();
        let coordinator = coordinator_with_dirs(
            &repository,
            downloader,
            temp.path().join("models"),
            temp.path().join("runtime-temp"),
        );
        let id = TranscriptionModelId::parse("whisper.cpp:base@main").unwrap();
        let mut model = repository.get_model(&id).unwrap().unwrap();
        model.checksum_sha256 = hex::encode(Sha256::digest(b"verified model bytes"));
        model.size_bytes = b"verified model bytes".len() as u64;
        repository.upsert_model(&model).unwrap();
        (coordinator, repository, id, temp)
    }

    fn coordinator_with_dirs(
        repository: &Arc<SqliteRepository>,
        downloader: Arc<dyn ArtifactDownloader>,
        model_dir: PathBuf,
        temp_dir: PathBuf,
    ) -> Arc<RecordingTranscriptionCoordinator> {
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
        let (events, _) = broadcast::channel(32);
        Arc::new(
            RecordingTranscriptionCoordinator::new_with_adapters_and_dirs(
                services,
                repository.clone(),
                events,
                Arc::new(TokioProcessRunner),
                downloader,
                model_dir,
                temp_dir,
            )
            .unwrap(),
        )
    }

    fn gated_downloader() -> (
        Arc<dyn ArtifactDownloader>,
        mpsc::UnboundedReceiver<StartedDownload>,
    ) {
        let (started, receiver) = mpsc::unbounded_channel();
        (
            Arc::new(GatedArtifactDownloader {
                bytes: b"verified model bytes".to_vec(),
                started,
            }),
            receiver,
        )
    }

    #[test]
    fn resolves_development_runtime_from_repository_root() {
        let root = std::env::temp_dir().join(format!(
            "llplayernext-runtime-test-{}",
            application::now_ms()
        ));
        let runtime = root.join("third_party/runtime/macos-arm64");
        std::fs::create_dir_all(&runtime).unwrap();
        // A unique tool name keeps this deterministic: the global
        // `/opt/homebrew/bin` and `/usr/local/bin` fallback candidates can never
        // shadow the bundled tool, so the test does not depend on which
        // `whisper-cli` happens to be installed on the developer machine.
        let tool_name = format!("whisper-cli-test-{}", application::now_ms());
        let whisper = runtime.join(&tool_name);
        std::fs::write(&whisper, b"#!/bin/sh\n").unwrap();

        let executable = root.join("target/debug/api-http");
        let resolved =
            resolve_bundled_tool(&tool_name, &executable, &root.join("apps/desktop")).unwrap();
        assert_eq!(resolved, whisper);

        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn resolves_dtw_presets_for_whisper_cpp_models() {
        assert_eq!(dtw_preset_from_name("base.en").as_deref(), Some("base.en"));
        assert_eq!(
            dtw_preset_from_name("ggml-large-v3.bin").as_deref(),
            Some("large.v3")
        );
        assert_eq!(
            dtw_preset_from_name("ggml-small.en-q5_0.bin").as_deref(),
            Some("small.en")
        );
        assert_eq!(
            dtw_preset_from_name("ggml-large-v3-turbo-q8_0.bin").as_deref(),
            Some("large.v3.turbo")
        );
        assert!(dtw_preset_from_name("not-a-whisper-model.bin").is_none());
    }

    #[test]
    fn recognizes_english_only_custom_model_names() {
        assert!(english_only_model_name("ggml-base.en.bin"));
        assert!(english_only_model_name("whisper-cpp-base-en-main.bin"));
        assert!(!english_only_model_name("whisper-cpp-base-main.bin"));
    }

    #[test]
    fn parses_short_recording_json_with_language_and_offsets() {
        let result = parse_recording_transcription_json(
            r#"{
                "result": {"language": "zh"},
                "transcription": [
                    {"offsets": {"from": 120, "to": 840}, "text": " 你好 "},
                    {"offsets": {"from": 840, "to": 1600}, "text": "世界"}
                ]
            }"#
            .as_bytes(),
        )
        .unwrap();
        assert_eq!(result.detected_language.as_deref(), Some("zh"));
        assert_eq!(result.segments.len(), 2);
        assert_eq!(result.segments[0].start_ms, 120);
        assert_eq!(result.segments[0].text, "你好");
        assert_eq!(result.segments[1].end_ms, 1600);
    }

    #[test]
    fn rejects_short_recording_json_without_readable_segments() {
        let error = parse_recording_transcription_json(
            br#"{"result":{"language":"en"},"transcription":[]}"#,
        )
        .unwrap_err();
        assert!(error.to_string().contains("non-empty recording transcript"));
    }

    #[tokio::test]
    async fn install_reservation_precedes_first_poll_and_cancel_stays_terminal() {
        let (downloader, mut started) = gated_downloader();
        let (coordinator, repository, id, temp) = model_install_fixture(downloader);

        // This is the ordering used by the HTTP handler: reserve synchronously,
        // then acknowledge/spawn. Cancellation can therefore win before the
        // returned future receives its first poll.
        let install = coordinator
            .start_model_install(id.clone())
            .unwrap()
            .future
            .unwrap();
        assert_eq!(
            repository.get_model(&id).unwrap().unwrap().state,
            TranscriptionModelState::Installing
        );
        let cancelled = coordinator.cancel_model_install(&id).unwrap();
        assert_eq!(cancelled.state, TranscriptionModelState::Downloadable);

        let task = tokio::spawn(install);
        let result = task.await.unwrap().unwrap();

        assert_eq!(result.state, TranscriptionModelState::Downloadable);
        assert_eq!(result.installed_bytes, 0);
        assert!(result.local_path.is_none());
        assert!(started.try_recv().is_err());
        let final_name = format!("{}.bin", file_id(id.as_str()));
        assert!(
            std::fs::read_dir(temp.path().join("models"))
                .unwrap()
                .all(|entry| {
                    let path = entry.unwrap().path();
                    path.extension()
                        .is_none_or(|extension| extension != "partial")
                        && path.file_name().and_then(|name| name.to_str())
                            != Some(final_name.as_str())
                })
        );
    }

    #[tokio::test]
    async fn cancelled_install_cannot_clobber_immediate_retry_progress_or_result() {
        let (downloader, mut started) = gated_downloader();
        let (coordinator, repository, id, _) = model_install_fixture(downloader);

        let first = tokio::spawn(
            coordinator
                .start_model_install(id.clone())
                .unwrap()
                .future
                .unwrap(),
        );
        let (first_partial, release_first) = started.recv().await.unwrap();
        let cancelled = coordinator.cancel_model_install(&id).unwrap();
        assert_eq!(cancelled.state, TranscriptionModelState::Downloadable);

        let second = tokio::spawn(
            coordinator
                .start_model_install(id.clone())
                .unwrap()
                .future
                .unwrap(),
        );
        let (second_partial, release_second) = started.recv().await.unwrap();
        assert_ne!(first_partial, second_partial);

        let _ = release_first.send(());
        assert_eq!(
            first.await.unwrap().unwrap().state,
            TranscriptionModelState::Installing
        );
        let after_stale_completion = repository.get_model(&id).unwrap().unwrap();
        assert_eq!(
            after_stale_completion.state,
            TranscriptionModelState::Installing
        );
        assert_eq!(after_stale_completion.installed_bytes, 0);
        assert!(!first_partial.exists());

        release_second.send(()).unwrap();
        let installed = second.await.unwrap().unwrap();
        assert_eq!(installed.state, TranscriptionModelState::Installed);
        assert_eq!(installed.installed_bytes, installed.size_bytes);
        let final_path = installed.local_path.unwrap();
        assert_eq!(std::fs::read(final_path).unwrap(), b"verified model bytes");
        assert!(!second_partial.exists());
    }

    #[tokio::test]
    async fn cancellation_releases_a_stalled_downloader_promptly() {
        let (downloader, mut started) = gated_downloader();
        let (coordinator, _, id, _) = model_install_fixture(downloader);
        let start = coordinator.start_model_install(id.clone()).unwrap();
        let task = tokio::spawn(start.future.unwrap());
        let (partial, release) = started.recv().await.unwrap();

        assert_eq!(
            coordinator.cancel_model_install(&id).unwrap().state,
            TranscriptionModelState::Downloadable
        );
        let result = tokio::time::timeout(Duration::from_secs(2), task)
            .await
            .expect("cancellation should abort a stalled download")
            .unwrap()
            .unwrap();
        assert_eq!(result.state, TranscriptionModelState::Downloadable);
        assert!(!partial.exists());
        assert!(release.send(()).is_err());
    }

    #[tokio::test]
    async fn duplicate_install_request_does_not_start_a_second_download() {
        let (downloader, mut started) = gated_downloader();
        let (coordinator, repository, id, _) = model_install_fixture(downloader);

        let first = tokio::spawn(
            coordinator
                .start_model_install(id.clone())
                .unwrap()
                .future
                .unwrap(),
        );
        let (partial, release) = started.recv().await.unwrap();
        let duplicate = coordinator.start_model_install(id.clone()).unwrap();
        assert!(duplicate.installation_started);
        assert!(duplicate.future.is_none());
        assert_eq!(
            repository.get_model(&id).unwrap().unwrap().state,
            TranscriptionModelState::Installing
        );

        release.send(()).unwrap();
        assert_eq!(
            first.await.unwrap().unwrap().state,
            TranscriptionModelState::Installed
        );
        assert!(!partial.exists());
        assert!(started.try_recv().is_err());
    }

    #[tokio::test]
    async fn checksum_failure_preserves_preexisting_model_file() {
        let downloader: Arc<dyn ArtifactDownloader> = Arc::new(crate::FakeArtifactDownloader::new(
            b"wrong model payload!".to_vec(),
        ));
        let (coordinator, repository, id, temp) = model_install_fixture(downloader);
        let final_path = temp
            .path()
            .join("models")
            .join(format!("{}.bin", file_id(id.as_str())));
        std::fs::create_dir_all(final_path.parent().unwrap()).unwrap();
        std::fs::write(&final_path, b"previous valid model").unwrap();
        let mut model = repository.get_model(&id).unwrap().unwrap();
        model.state = TranscriptionModelState::Failed;
        model.local_path = Some(final_path.to_string_lossy().into_owned());
        model.installed_bytes = b"previous valid model".len() as u64;
        repository.upsert_model(&model).unwrap();

        let failed = coordinator.clone().install_model(id).await.unwrap();

        assert_eq!(failed.state, TranscriptionModelState::Failed);
        assert_eq!(std::fs::read(final_path).unwrap(), b"previous valid model");
        assert!(
            failed
                .error
                .as_deref()
                .unwrap()
                .contains("checksum mismatch")
        );
        assert!(
            std::fs::read_dir(temp.path().join("models"))
                .unwrap()
                .all(|entry| entry
                    .unwrap()
                    .path()
                    .extension()
                    .is_none_or(|ext| ext != "partial"))
        );
    }

    #[tokio::test]
    async fn oversized_download_is_rejected_at_progress_and_preserves_final_file() {
        let downloader: Arc<dyn ArtifactDownloader> = Arc::new(crate::FakeArtifactDownloader::new(
            b"verified model bytes plus overflow".to_vec(),
        ));
        let (coordinator, repository, id, temp) = model_install_fixture(downloader);
        let final_path = temp
            .path()
            .join("models")
            .join(format!("{}.bin", file_id(id.as_str())));
        std::fs::write(&final_path, b"previous valid model").unwrap();
        let mut model = repository.get_model(&id).unwrap().unwrap();
        model.state = TranscriptionModelState::Failed;
        model.local_path = Some(final_path.to_string_lossy().into_owned());
        model.installed_bytes = b"previous valid model".len() as u64;
        repository.upsert_model(&model).unwrap();

        let failed = coordinator.clone().install_model(id).await.unwrap();

        assert_eq!(failed.state, TranscriptionModelState::Failed);
        assert_eq!(failed.installed_bytes, 0);
        assert!(
            failed
                .error
                .as_deref()
                .unwrap()
                .contains("exceeded catalog size")
        );
        assert_eq!(std::fs::read(final_path).unwrap(), b"previous valid model");
        assert!(
            std::fs::read_dir(temp.path().join("models"))
                .unwrap()
                .all(|entry| entry
                    .unwrap()
                    .path()
                    .extension()
                    .is_none_or(|ext| ext != "partial"))
        );
    }

    #[tokio::test]
    async fn undersized_download_is_rejected_before_checksum_and_preserves_final_file() {
        let downloader: Arc<dyn ArtifactDownloader> =
            Arc::new(crate::FakeArtifactDownloader::new(b"short".to_vec()));
        let (coordinator, repository, id, temp) = model_install_fixture(downloader);
        let final_path = temp
            .path()
            .join("models")
            .join(format!("{}.bin", file_id(id.as_str())));
        std::fs::write(&final_path, b"previous valid model").unwrap();
        let mut model = repository.get_model(&id).unwrap().unwrap();
        model.state = TranscriptionModelState::Failed;
        model.local_path = Some(final_path.to_string_lossy().into_owned());
        model.installed_bytes = b"previous valid model".len() as u64;
        repository.upsert_model(&model).unwrap();

        let failed = coordinator.clone().install_model(id).await.unwrap();

        assert_eq!(failed.state, TranscriptionModelState::Failed);
        assert_eq!(failed.installed_bytes, 0);
        assert!(
            failed
                .error
                .as_deref()
                .unwrap()
                .contains("size does not match catalog size")
        );
        assert_eq!(std::fs::read(final_path).unwrap(), b"previous valid model");
        assert!(
            std::fs::read_dir(temp.path().join("models"))
                .unwrap()
                .all(|entry| entry
                    .unwrap()
                    .path()
                    .extension()
                    .is_none_or(|ext| ext != "partial"))
        );
    }

    #[tokio::test]
    async fn startup_recovers_orphaned_install_and_allows_retry() {
        let downloader: Arc<dyn ArtifactDownloader> = Arc::new(crate::FakeArtifactDownloader::new(
            b"verified model bytes".to_vec(),
        ));
        let (coordinator, repository, id, temp) = model_install_fixture(downloader);
        let model_dir = temp.path().join("models");
        std::fs::create_dir_all(&model_dir).unwrap();
        let mut interrupted = repository.get_model(&id).unwrap().unwrap();
        interrupted.state = TranscriptionModelState::Installing;
        interrupted.installed_bytes = 8;
        interrupted.error = None;
        repository.upsert_model(&interrupted).unwrap();

        let installed_id = TranscriptionModelId::parse("whisper.cpp:small@main").unwrap();
        let installed_path = model_dir.join(format!("{}.bin", file_id(installed_id.as_str())));
        let installed_bytes = b"already installed model";
        std::fs::write(&installed_path, installed_bytes).unwrap();
        let mut installed = repository.get_model(&installed_id).unwrap().unwrap();
        installed.state = TranscriptionModelState::Installed;
        installed.checksum_sha256 = hex::encode(Sha256::digest(installed_bytes));
        installed.size_bytes = installed_bytes.len() as u64;
        installed.installed_bytes = installed_bytes.len() as u64;
        installed.local_path = Some(installed_path.to_string_lossy().into_owned());
        repository.upsert_model(&installed).unwrap();

        let custom_path = temp.path().join("custom-model.bin");
        let custom_bytes = b"user custom model";
        std::fs::write(&custom_path, custom_bytes).unwrap();
        let custom = coordinator
            .register_custom_model(custom_path.to_string_lossy().into_owned())
            .unwrap();
        let stale_partial =
            model_dir.join(format!("{}.424242.7.bin.partial", file_id(id.as_str())));
        std::fs::write(&stale_partial, b"partial download").unwrap();
        let unrelated_file = model_dir.join("unrelated.424242.7.bin.partial.backup");
        std::fs::write(&unrelated_file, b"keep").unwrap();
        let retry_downloader: Arc<dyn ArtifactDownloader> = Arc::new(
            crate::FakeArtifactDownloader::new(b"verified model bytes".to_vec()),
        );

        drop(coordinator);
        let recovered = coordinator_with_dirs(
            &repository,
            retry_downloader,
            model_dir.clone(),
            temp.path().join("runtime-temp"),
        );

        let recovered_model = repository.get_model(&id).unwrap().unwrap();
        assert_eq!(recovered_model.state, TranscriptionModelState::Downloadable);
        assert_eq!(recovered_model.installed_bytes, 0);
        assert!(recovered_model.local_path.is_none());
        assert!(
            recovered_model
                .error
                .as_deref()
                .unwrap()
                .contains("interrupted")
        );
        assert!(!stale_partial.exists());
        assert_eq!(std::fs::read(unrelated_file).unwrap(), b"keep");
        assert_eq!(
            repository.get_model(&installed_id).unwrap().unwrap().state,
            TranscriptionModelState::Installed
        );
        assert_eq!(std::fs::read(installed_path).unwrap(), installed_bytes);
        assert_eq!(
            repository.get_model(&custom.id).unwrap().unwrap().state,
            TranscriptionModelState::Custom
        );
        assert_eq!(std::fs::read(custom_path).unwrap(), custom_bytes);

        let retried = recovered.clone().install_model(id).await.unwrap();
        assert_eq!(retried.state, TranscriptionModelState::Installed);
        assert_eq!(
            std::fs::read(retried.local_path.unwrap()).unwrap(),
            b"verified model bytes"
        );
    }

    #[tokio::test]
    async fn startup_preserves_live_cross_process_owner_then_recovers_after_release() {
        let initial_downloader: Arc<dyn ArtifactDownloader> = Arc::new(
            crate::FakeArtifactDownloader::new(b"verified model bytes".to_vec()),
        );
        let (_coordinator, repository, id, temp) = model_install_fixture(initial_downloader);
        let model_dir = temp.path().join("models");
        let mut interrupted = repository.get_model(&id).unwrap().unwrap();
        interrupted.state = TranscriptionModelState::Installing;
        interrupted.installed_bytes = 9;
        repository.upsert_model(&interrupted).unwrap();
        let partial = model_dir.join(format!("{}.424242.12.bin.partial", file_id(id.as_str())));
        std::fs::write(&partial, b"live partial").unwrap();

        let owner =
            SubprocessLockHolder::start(temp.path(), &model_owner_lock_path(&model_dir, &id));
        let live = coordinator_with_dirs(
            &repository,
            Arc::new(crate::FakeArtifactDownloader::new(
                b"verified model bytes".to_vec(),
            )),
            model_dir.clone(),
            temp.path().join("runtime-temp-live").to_path_buf(),
        );
        let model = repository.get_model(&id).unwrap().unwrap();
        assert_eq!(model.state, TranscriptionModelState::Installing);
        assert_eq!(model.installed_bytes, 9);
        assert!(partial.exists());
        let busy = live.start_model_install(id.clone()).unwrap();
        assert!(busy.installation_started);
        assert!(busy.future.is_none());

        owner.terminate();
        let recovered = coordinator_with_dirs(
            &repository,
            Arc::new(crate::FakeArtifactDownloader::new(
                b"verified model bytes".to_vec(),
            )),
            model_dir,
            temp.path().join("runtime-temp-recovered"),
        );
        let model = repository.get_model(&id).unwrap().unwrap();
        assert_eq!(model.state, TranscriptionModelState::Downloadable);
        assert_eq!(model.installed_bytes, 0);
        assert!(model.error.as_deref().unwrap().contains("interrupted"));
        assert!(!partial.exists());

        let retry = recovered.start_model_install(id).unwrap();
        assert!(retry.installation_started);
        let installed = retry.future.unwrap().await.unwrap();
        assert_eq!(installed.state, TranscriptionModelState::Installed);
    }

    #[tokio::test]
    async fn retry_after_cross_process_cancel_is_not_claimed_while_owner_is_stopping() {
        let downloader: Arc<dyn ArtifactDownloader> = Arc::new(crate::FakeArtifactDownloader::new(
            b"verified model bytes".to_vec(),
        ));
        let (coordinator, repository, id, temp) = model_install_fixture(downloader);
        let model_dir = temp.path().join("models");
        let mut installing = repository.get_model(&id).unwrap().unwrap();
        installing.state = TranscriptionModelState::Installing;
        repository.upsert_model(&installing).unwrap();
        let partial = model_dir.join(format!("{}.424242.13.bin.partial", file_id(id.as_str())));
        std::fs::write(&partial, b"cancelled live partial").unwrap();

        let owner =
            SubprocessLockHolder::start(temp.path(), &model_owner_lock_path(&model_dir, &id));
        assert_eq!(
            coordinator.cancel_model_install(&id).unwrap().state,
            TranscriptionModelState::Downloadable
        );
        let retry_while_owner_stops = coordinator.start_model_install(id.clone()).unwrap();
        assert!(!retry_while_owner_stops.installation_started);
        assert!(retry_while_owner_stops.future.is_none());
        assert!(partial.exists());

        owner.terminate();
        let retry = coordinator.start_model_install(id).unwrap();
        assert!(retry.installation_started);
        let installed = retry.future.unwrap().await.unwrap();
        assert_eq!(installed.state, TranscriptionModelState::Installed);
        assert!(!partial.exists());
    }

    #[tokio::test]
    async fn startup_recovery_keeps_active_install_when_catalog_is_reseeded() {
        let (downloader, _) = gated_downloader();
        let (coordinator, repository, id, temp) = model_install_fixture(downloader);
        let install = coordinator
            .start_model_install(id.clone())
            .unwrap()
            .future
            .unwrap();

        coordinator.seed_catalog().unwrap();
        let second_coordinator = coordinator_with_dirs(
            &repository,
            Arc::new(crate::FakeArtifactDownloader::new(
                b"verified model bytes".to_vec(),
            )),
            temp.path().join("models"),
            temp.path().join("runtime-temp-second"),
        );
        assert!(Arc::ptr_eq(
            &coordinator.model_installs,
            &second_coordinator.model_installs
        ));

        assert_eq!(
            repository.get_model(&id).unwrap().unwrap().state,
            TranscriptionModelState::Installing
        );
        assert_eq!(
            second_coordinator.cancel_model_install(&id).unwrap().state,
            TranscriptionModelState::Downloadable
        );
        drop(install);
    }

    #[tokio::test]
    async fn startup_recovers_installing_descriptor_when_final_bytes_are_valid() {
        let downloader: Arc<dyn ArtifactDownloader> = Arc::new(crate::FakeArtifactDownloader::new(
            b"verified model bytes".to_vec(),
        ));
        let (coordinator, repository, id, temp) = model_install_fixture(downloader);
        let model_dir = temp.path().join("models");
        std::fs::create_dir_all(&model_dir).unwrap();
        let final_path = model_dir.join(format!("{}.bin", file_id(id.as_str())));
        std::fs::write(&final_path, b"verified model bytes").unwrap();
        let mut interrupted = repository.get_model(&id).unwrap().unwrap();
        interrupted.state = TranscriptionModelState::Installing;
        interrupted.local_path = Some(final_path.to_string_lossy().into_owned());
        interrupted.installed_bytes = 5;
        repository.upsert_model(&interrupted).unwrap();

        drop(coordinator);
        let recovered = coordinator_with_dirs(
            &repository,
            Arc::new(crate::FakeArtifactDownloader::new(
                b"verified model bytes".to_vec(),
            )),
            model_dir,
            temp.path().join("runtime-temp"),
        );

        let model = recovered
            .models()
            .unwrap()
            .into_iter()
            .find(|model| model.id == id)
            .unwrap();
        assert_eq!(model.state, TranscriptionModelState::Installed);
        assert_eq!(model.installed_bytes, b"verified model bytes".len() as u64);
        assert_eq!(
            model.local_path.as_deref(),
            Some(final_path.to_str().unwrap())
        );
        assert!(model.error.is_none());
        assert_eq!(std::fs::read(final_path).unwrap(), b"verified model bytes");
    }
}
