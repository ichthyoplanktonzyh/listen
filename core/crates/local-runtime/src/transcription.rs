use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use api_events::{EventEnvelope, EventName};
use application::{AppServices, ApplicationError, TranscriptionRepository, now_ms};
use domain::{
    RecordingTranscriptProvenance, RecordingTranscriptionJob, RecordingTranscriptionJobId,
    RecordingTranscriptionStatus, TranscriptionModelDescriptor, TranscriptionModelId,
    TranscriptionModelState, TranscriptionProviderInfo, TranscriptionQuality, TranscriptionSegment,
};
use tokio::sync::{Semaphore, broadcast};

use crate::download::{ArtifactDownloader, DownloadProgress, ReqwestArtifactDownloader};
use crate::process::{CancellationProbe, ProcessRunner, ProcessSpec, TokioProcessRunner};
use crate::runtime_support::{file_id, hash_file, io_error, resolve_tool, support_dir};

/// Coordinates transcription of short microphone recordings, which consume an
/// existing `RecordingAsset` and never import subtitle tracks. Whole-media
/// transcription jobs have been removed; the model catalog methods retained
/// here (and exposed over HTTP) serve recording and realtime model selection.
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
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct CreateRecordingTranscriptionRequest {
    pub recording_id: String,
    pub model_id: String,
    pub language: Option<String>,
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
        let value = Self {
            services,
            repository,
            events,
            queue: Arc::new(Semaphore::new(1)),
            model_dir: support.join("models/transcription/whisper.cpp"),
            temp_dir: std::env::temp_dir().join("LLPlayerNext/transcription"),
            process_runner,
            downloader,
            recording_jobs: Arc::default(),
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

    pub async fn install_model(
        self: Arc<Self>,
        id: TranscriptionModelId,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        let mut model = self
            .repository
            .get_model(&id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;
        let url = model
            .download_url
            .clone()
            .ok_or(ApplicationError::Validation("model download URL"))?;
        tokio::fs::create_dir_all(&self.model_dir)
            .await
            .map_err(io_error)?;
        let path = self.model_dir.join(format!("{}.bin", file_id(id.as_str())));
        let partial = path.with_extension("bin.partial");
        model.state = TranscriptionModelState::Installing;
        model.error = None;
        model.updated_at_ms = now_ms();
        self.repository.upsert_model(&model)?;
        self.emit(EventName::TranscriptionModelChanged, &model);

        let result = async {
            self.downloader
                .download(
                    &url,
                    &partial,
                    Arc::new(TranscriptionDownloadProgress {
                        repository: self.repository.clone(),
                        events: self.events.clone(),
                        model_id: id.clone(),
                    }),
                )
                .await?;
            let checksum = hash_file(&partial)?;
            if checksum != model.checksum_sha256 {
                return Err(ApplicationError::Repository(
                    "model checksum mismatch".into(),
                ));
            }
            tokio::fs::rename(&partial, &path).await.map_err(io_error)?;
            Ok::<_, ApplicationError>(())
        }
        .await;

        match result {
            Ok(()) => {
                model.state = TranscriptionModelState::Installed;
                model.local_path = Some(path.to_string_lossy().into_owned());
                model.installed_bytes = model.size_bytes;
            }
            Err(error) => {
                let _ = tokio::fs::remove_file(&partial).await;
                if let Some(current) = self.repository.get_model(&id)?
                    && current.state == TranscriptionModelState::Downloadable
                {
                    return Ok(current);
                }
                model.state = TranscriptionModelState::Failed;
                model.error = Some(error.to_string());
            }
        }
        model.updated_at_ms = now_ms();
        let model = self.repository.upsert_model(&model)?;
        self.emit(EventName::TranscriptionModelChanged, &model);
        Ok(model)
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
        if let Some(mut model) = self.repository.get_model(id)?
            && model.state == TranscriptionModelState::Installed
            && let Some(path) = model.local_path.clone()
        {
            let _ = tokio::fs::remove_file(path).await;
            model.local_path = None;
            model.installed_bytes = 0;
            model.state = TranscriptionModelState::Downloadable;
            model.error = None;
            model.updated_at_ms = now_ms();
            self.repository.upsert_model(&model)?;
            self.emit(EventName::TranscriptionModelChanged, &model);
            return Ok(());
        }
        self.repository.delete_model(id)
    }

    pub fn cancel_model_install(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        let mut model = self
            .repository
            .get_model(id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;
        if model.state == TranscriptionModelState::Installing {
            model.state = TranscriptionModelState::Downloadable;
            model.installed_bytes = 0;
            model.error = Some("Installation cancelled by user.".into());
            model.updated_at_ms = now_ms();
            self.repository.upsert_model(&model)?;
            self.emit(EventName::TranscriptionModelChanged, &model);
        }
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
        for model in catalog() {
            if existing.iter().any(|value| value.id == model.id) {
                continue;
            }
            self.repository.upsert_model(&model)?;
        }
        Ok(())
    }
}

struct RecordingTranscriptionCancellation {
    jobs: Arc<Mutex<HashMap<RecordingTranscriptionJobId, RecordingTranscriptionJob>>>,
    job_id: RecordingTranscriptionJobId,
}

struct TranscriptionDownloadProgress {
    repository: Arc<dyn TranscriptionRepository>,
    events: broadcast::Sender<EventEnvelope>,
    model_id: TranscriptionModelId,
}

impl DownloadProgress for TranscriptionDownloadProgress {
    fn is_cancelled(&self) -> Result<bool, ApplicationError> {
        Ok(self
            .repository
            .get_model(&self.model_id)?
            .is_some_and(|model| model.state != TranscriptionModelState::Installing))
    }

    fn downloaded(&self, bytes: u64) -> Result<(), ApplicationError> {
        let mut model = self
            .repository
            .get_model(&self.model_id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;
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
}
