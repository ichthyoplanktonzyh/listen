use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, ForcedAlignSidecar, ImportSubtitle, TranscriptionRepository,
    now_ms,
};
use domain::{
    MediaId, SubtitleTrackProvenance, TranscriptionDestination, TranscriptionJob,
    TranscriptionJobId, TranscriptionJobStatus, TranscriptionModelDescriptor, TranscriptionModelId,
    TranscriptionModelState, TranscriptionProviderInfo, TranscriptionPurpose, TranscriptionQuality,
};
use sha2::{Digest, Sha256};
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::sync::{Semaphore, broadcast};

#[derive(Clone)]
pub struct TranscriptionCoordinator {
    services: AppServices,
    repository: Arc<dyn TranscriptionRepository>,
    events: broadcast::Sender<EventEnvelope>,
    queue: Arc<Semaphore>,
    model_dir: PathBuf,
    temp_dir: PathBuf,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct CreateJobRequest {
    pub media_id: String,
    pub model_id: String,
    pub destination: TranscriptionDestination,
    pub purpose: TranscriptionPurpose,
    pub language: Option<String>,
    pub audio_track: Option<u32>,
    #[serde(default)]
    pub force: bool,
}

impl TranscriptionCoordinator {
    pub fn new(
        services: AppServices,
        repository: Arc<dyn TranscriptionRepository>,
        events: broadcast::Sender<EventEnvelope>,
    ) -> Result<Self, ApplicationError> {
        let support = support_dir();
        let value = Self {
            services,
            repository,
            events,
            queue: Arc::new(Semaphore::new(1)),
            model_dir: support.join("models/transcription/whisper.cpp"),
            temp_dir: std::env::temp_dir().join("LLPlayerNext/transcription"),
        };
        value.repository.interrupt_active_jobs(now_ms())?;
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

    pub fn jobs(&self) -> Result<Vec<TranscriptionJob>, ApplicationError> {
        self.repository.list_jobs()
    }

    pub fn job(
        &self,
        id: &TranscriptionJobId,
    ) -> Result<Option<TranscriptionJob>, ApplicationError> {
        self.repository.get_job(id)
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
            let mut response = reqwest::get(url)
                .await
                .map_err(|error| ApplicationError::Repository(error.to_string()))?
                .error_for_status()
                .map_err(|error| ApplicationError::Repository(error.to_string()))?;
            let mut file = tokio::fs::File::create(&partial).await.map_err(io_error)?;
            let mut downloaded = 0_u64;
            while let Some(chunk) = response
                .chunk()
                .await
                .map_err(|error| ApplicationError::Repository(error.to_string()))?
            {
                if self
                    .repository
                    .get_model(&id)?
                    .is_some_and(|value| value.state != TranscriptionModelState::Installing)
                {
                    return Err(ApplicationError::Repository(
                        "model installation cancelled".into(),
                    ));
                }
                file.write_all(&chunk).await.map_err(io_error)?;
                downloaded += chunk.len() as u64;
                model.installed_bytes = downloaded;
                model.updated_at_ms = now_ms();
                self.repository.upsert_model(&model)?;
                self.emit(EventName::TranscriptionModelChanged, &model);
            }
            file.flush().await.map_err(io_error)?;
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
            english_only: false,
            supports_translation: true,
            state: TranscriptionModelState::Custom,
            installed_bytes: metadata.len(),
            error: None,
            license: "User supplied".into(),
            updated_at_ms: now_ms(),
        })
    }

    pub async fn delete_model(&self, id: &TranscriptionModelId) -> Result<(), ApplicationError> {
        if self.repository.list_jobs()?.iter().any(|job| {
            job.model_id == *id
                && matches!(
                    job.status,
                    TranscriptionJobStatus::Queued
                        | TranscriptionJobStatus::Extracting
                        | TranscriptionJobStatus::Transcribing
                        | TranscriptionJobStatus::Importing
                )
        }) {
            return Err(ApplicationError::Validation(
                "model is used by an active job",
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

    pub fn create_job(
        self: Arc<Self>,
        request: CreateJobRequest,
    ) -> Result<TranscriptionJob, ApplicationError> {
        let media_id = MediaId::parse(request.media_id)?;
        let media = self
            .services
            .read_media(&media_id)?
            .ok_or(ApplicationError::NotFound("media"))?;
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
        let provider = self.providers().into_iter().next().expect("first provider");
        if !provider.available {
            return Err(ApplicationError::Validation("transcription runtime"));
        }
        if request.purpose == TranscriptionPurpose::TranslateToEnglish && model.english_only {
            return Err(ApplicationError::Validation(
                "multilingual translation model",
            ));
        }
        let settings_json = serde_json::json!({
            "destination": request.destination,
            "purpose": request.purpose,
            "language": request.language,
            "audio_track": request.audio_track
        })
        .to_string();
        let input_fingerprint = hex::encode(Sha256::digest(format!(
            "{}:{}:{}:{}",
            media.fingerprint,
            model.id.as_str(),
            model.checksum_sha256,
            settings_json
        )));
        if !request.force
            && let Some(job) = self.repository.find_completed_job(&input_fingerprint)?
        {
            return Ok(job);
        }
        let created_at_ms = now_ms();
        let job = TranscriptionJob {
            id: TranscriptionJobId::from_fingerprint(
                "transcription-job",
                &format!("{input_fingerprint}:{created_at_ms}"),
            ),
            media_id,
            media_title: media.title,
            media_fingerprint: media.fingerprint,
            provider_id: provider.id,
            provider_version: provider.runtime_version.clone(),
            runtime_id: provider.runtime_id,
            runtime_version: provider.runtime_version,
            model_id: model.id,
            model_revision: model.revision,
            model_checksum_sha256: model.checksum_sha256,
            destination: request.destination,
            purpose: request.purpose,
            requested_language: request.language,
            detected_language: None,
            audio_track: request.audio_track,
            settings_json,
            input_fingerprint,
            status: TranscriptionJobStatus::Queued,
            phase_progress: 0,
            error_code: None,
            error_message: None,
            retry_of_job_id: None,
            generated_track_id: None,
            created_at_ms,
            started_at_ms: None,
            completed_at_ms: None,
            updated_at_ms: created_at_ms,
            archived_at_ms: None,
        };
        let job = self.repository.create_job(&job)?;
        self.emit(EventName::TranscriptionJobChanged, &job);
        let coordinator = self.clone();
        let id = job.id.clone();
        tokio::spawn(async move { coordinator.run_job(id).await });
        Ok(job)
    }

    pub fn cancel_job(
        &self,
        id: &TranscriptionJobId,
    ) -> Result<TranscriptionJob, ApplicationError> {
        let mut job = self
            .repository
            .get_job(id)?
            .ok_or(ApplicationError::NotFound("transcription job"))?;
        if job.status != TranscriptionJobStatus::Completed {
            job.status = TranscriptionJobStatus::Cancelled;
            job.completed_at_ms = Some(now_ms());
            job.updated_at_ms = now_ms();
            self.repository.update_job(&job)?;
            self.emit(EventName::TranscriptionJobChanged, &job);
        }
        Ok(job)
    }

    pub fn retry_job(
        self: Arc<Self>,
        id: &TranscriptionJobId,
    ) -> Result<TranscriptionJob, ApplicationError> {
        let old = self
            .repository
            .get_job(id)?
            .ok_or(ApplicationError::NotFound("transcription job"))?;
        let mut job = self.clone().create_job(CreateJobRequest {
            media_id: old.media_id.as_str().into(),
            model_id: old.model_id.as_str().into(),
            destination: old.destination,
            purpose: old.purpose,
            language: old.requested_language,
            audio_track: old.audio_track,
            force: true,
        })?;
        if job.id != old.id && job.status == TranscriptionJobStatus::Queued {
            job.retry_of_job_id = Some(old.id);
            job.updated_at_ms = now_ms();
            self.repository.update_job(&job)?;
            self.emit(EventName::TranscriptionJobChanged, &job);
        }
        Ok(job)
    }

    pub fn archive_job(
        &self,
        id: &TranscriptionJobId,
    ) -> Result<TranscriptionJob, ApplicationError> {
        let mut job = self
            .repository
            .get_job(id)?
            .ok_or(ApplicationError::NotFound("transcription job"))?;
        if matches!(
            job.status,
            TranscriptionJobStatus::Queued
                | TranscriptionJobStatus::Extracting
                | TranscriptionJobStatus::Transcribing
                | TranscriptionJobStatus::Importing
        ) {
            return Err(ApplicationError::Validation(
                "active transcription job cannot be archived",
            ));
        }
        job.archived_at_ms = Some(now_ms());
        job.updated_at_ms = now_ms();
        self.repository.update_job(&job)?;
        self.emit(EventName::TranscriptionJobChanged, &job);
        Ok(job)
    }

    async fn run_job(self: Arc<Self>, id: TranscriptionJobId) {
        let _permit = match self.queue.acquire().await {
            Ok(value) => value,
            Err(_) => return,
        };
        let result = self.execute_job(&id).await;
        let _ = tokio::fs::remove_dir_all(self.temp_dir.join(id.as_str())).await;
        if let Err(error) = result
            && let Ok(Some(mut job)) = self.repository.get_job(&id)
            && job.status != TranscriptionJobStatus::Cancelled
        {
            job.status = TranscriptionJobStatus::Failed;
            job.error_code = Some("transcription_failed".into());
            job.error_message = Some(error.to_string());
            job.completed_at_ms = Some(now_ms());
            job.updated_at_ms = now_ms();
            let _ = self.repository.update_job(&job);
            self.emit(EventName::TranscriptionJobChanged, &job);
        }
    }

    async fn execute_job(&self, id: &TranscriptionJobId) -> Result<(), ApplicationError> {
        let mut job = self
            .repository
            .get_job(id)?
            .ok_or(ApplicationError::NotFound("transcription job"))?;
        if job.status == TranscriptionJobStatus::Cancelled {
            return Ok(());
        }
        job.started_at_ms = Some(now_ms());
        self.transition(&mut job, TranscriptionJobStatus::Extracting, 5)?;
        let media = self
            .services
            .read_media(&job.media_id)?
            .ok_or(ApplicationError::NotFound("media"))?;
        let model = self
            .repository
            .get_model(&job.model_id)?
            .ok_or(ApplicationError::NotFound("transcription model"))?;
        let model_path = model
            .local_path
            .ok_or(ApplicationError::Validation("model path"))?;
        let ffmpeg = resolve_tool("LLPLAYERNEXT_FFMPEG", "ffmpeg")
            .ok_or(ApplicationError::Validation("ffmpeg runtime"))?;
        let whisper = resolve_tool("LLPLAYERNEXT_WHISPER_CLI", "whisper-cli")
            .ok_or(ApplicationError::Validation("whisper runtime"))?;
        let work = self.temp_dir.join(id.as_str());
        tokio::fs::create_dir_all(&work).await.map_err(io_error)?;
        let wav = work.join("audio.wav");
        let mut ffmpeg_args = vec!["-y".into(), "-i".into(), media.path, "-vn".into()];
        if let Some(track) = job.audio_track {
            ffmpeg_args.extend(["-map".into(), format!("0:a:{track}")]);
        }
        ffmpeg_args.extend([
            "-ac".into(),
            "1".into(),
            "-ar".into(),
            "16000".into(),
            "-c:a".into(),
            "pcm_s16le".into(),
            wav.to_string_lossy().into_owned(),
        ]);
        self.run_command(&job.id, &ffmpeg, &ffmpeg_args).await?;
        self.transition(&mut job, TranscriptionJobStatus::Transcribing, 35)?;
        let output = work.join("result");
        let mut whisper_args = vec![
            "-m".into(),
            model_path.clone(),
            "-f".into(),
            wav.to_string_lossy().into_owned(),
            "-osrt".into(),
            "-ojf".into(),
            "-of".into(),
            output.to_string_lossy().into_owned(),
        ];
        let enable_dtw = model.family == "whisper";
        if enable_dtw {
            whisper_args.push("-dtw".into());
            whisper_args.push(model.display_name.clone());
        }
        whisper_args.extend([
            "-l".into(),
            job.requested_language
                .clone()
                .unwrap_or_else(|| "auto".into()),
        ]);
        if job.purpose == TranscriptionPurpose::TranslateToEnglish {
            whisper_args.push("-tr".into());
        }
        self.run_command(&job.id, &whisper, &whisper_args).await?;
        job.detected_language = tokio::fs::read(output.with_extension("json"))
            .await
            .ok()
            .and_then(|bytes| serde_json::from_slice::<serde_json::Value>(&bytes).ok())
            .and_then(|value| {
                value
                    .pointer("/result/language")
                    .and_then(serde_json::Value::as_str)
                    .map(str::to_owned)
            })
            .or_else(|| job.requested_language.clone());
        self.transition(&mut job, TranscriptionJobStatus::Importing, 90)?;
        let srt = tokio::fs::read(output.with_extension("srt"))
            .await
            .map_err(io_error)?;
        let track = self.services.import_subtitle(ImportSubtitle {
            media_id: job.media_id.clone(),
            source_name: format!("ASR-{}.srt", file_id(&model.display_name)),
            content: srt,
            language: if job.purpose == TranscriptionPurpose::TranslateToEnglish {
                Some("en".into())
            } else {
                job.requested_language.clone()
            },
            identity_salt: Some(format!(
                "{}:{}:{}",
                job.provider_id,
                job.model_id.as_str(),
                job.model_revision
            )),
        })?;
        // Extract ASR word-level timings from JSON-full output when DTW was enabled.
        if enable_dtw {
            let json_path = output.with_extension("json");
            if let Ok(json_bytes) = tokio::fs::read(&json_path).await
                && let Ok(track) = self.services.read_subtitle_track(&track.id)
                && let Some(track) = track
            {
                let _ = self
                    .services
                    .refine_transcription_word_timelines(
                        &track.id,
                        &json_bytes,
                        &wav,
                        resolve_forced_align_sidecar(),
                    )
                    .await;
            }
        }
        self.repository.save_provenance(&SubtitleTrackProvenance {
            track_id: track.id.clone(),
            transcription_job_id: job.id.clone(),
            provider_id: job.provider_id.clone(),
            runtime_version: job.runtime_version.clone(),
            model_id: job.model_id.clone(),
            model_revision: job.model_revision.clone(),
            model_checksum_sha256: job.model_checksum_sha256.clone(),
            settings_json: job.settings_json.clone(),
            created_at_ms: now_ms(),
        })?;
        job.generated_track_id = Some(track.id);
        job.status = TranscriptionJobStatus::Completed;
        job.phase_progress = 100;
        job.completed_at_ms = Some(now_ms());
        job.updated_at_ms = now_ms();
        self.repository.update_job(&job)?;
        self.emit(EventName::TranscriptionJobChanged, &job);
        let _ = tokio::fs::remove_dir_all(work).await;
        Ok(())
    }

    async fn run_command(
        &self,
        job_id: &TranscriptionJobId,
        executable: &Path,
        args: &[String],
    ) -> Result<(), ApplicationError> {
        let mut child = Command::new(executable)
            .args(args)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(io_error)?;
        loop {
            tokio::select! {
                status = child.wait() => {
                    let status = status.map_err(io_error)?;
                    return status.success().then_some(()).ok_or_else(|| ApplicationError::Repository(format!("{} exited with {status}", executable.display())));
                }
                _ = tokio::time::sleep(std::time::Duration::from_millis(250)) => {
                    if self.repository.get_job(job_id)?.is_some_and(|job| job.status == TranscriptionJobStatus::Cancelled) {
                        child.kill().await.map_err(io_error)?;
                        return Err(ApplicationError::Repository("job cancelled".into()));
                    }
                }
            }
        }
    }

    fn transition(
        &self,
        job: &mut TranscriptionJob,
        status: TranscriptionJobStatus,
        progress: u8,
    ) -> Result<(), ApplicationError> {
        if job.status == TranscriptionJobStatus::Cancelled {
            return Err(ApplicationError::Repository("job cancelled".into()));
        }
        job.status = status;
        job.phase_progress = progress;
        job.updated_at_ms = now_ms();
        self.repository.update_job(job)?;
        self.emit(EventName::TranscriptionJobChanged, job);
        Ok(())
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

fn support_dir() -> PathBuf {
    std::env::var_os("LLPLAYERNEXT_SUPPORT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").expect("HOME is required"))
                .join("Library/Application Support/LLPlayerNext")
        })
}

fn resolve_tool(env_name: &str, name: &str) -> Option<PathBuf> {
    if let Some(path) = std::env::var_os(env_name)
        .map(PathBuf::from)
        .filter(|path| path.is_file())
    {
        return Some(path);
    }
    let executable = std::env::current_exe().ok()?;
    resolve_bundled_tool(name, &executable, &std::env::current_dir().ok()?)
}

fn resolve_forced_align_sidecar() -> Option<ForcedAlignSidecar> {
    let research_root = std::env::var_os("LLPLAYERNEXT_FA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").expect("HOME is required"))
                .join("Library/Caches/LLPlayerNext/research/forced-align")
        });
    let python = research_root.join("venv/bin/python");
    if !python.is_file() {
        return None;
    }
    let script = resolve_forced_align_script()?;
    Some(ForcedAlignSidecar { python, script })
}

fn resolve_forced_align_script() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("LLPLAYERNEXT_FA_SCRIPT")
        .map(PathBuf::from)
        .filter(|path| path.is_file())
    {
        return Some(path);
    }
    let mut roots = Vec::new();
    if let Ok(current_dir) = std::env::current_dir() {
        roots.push(current_dir);
    }
    if let Ok(executable) = std::env::current_exe()
        && let Some(parent) = executable.parent()
    {
        roots.push(parent.to_path_buf());
    }
    for root in roots {
        let mut directory = Some(root.as_path());
        while let Some(path) = directory {
            let candidate = path.join("scripts/forced-align/align-cli.py");
            if candidate.is_file() {
                return Some(candidate);
            }
            directory = path.parent();
        }
    }
    None
}

fn resolve_bundled_tool(name: &str, executable: &Path, current_dir: &Path) -> Option<PathBuf> {
    let executable_parent = executable.parent()?;
    let mut candidates = vec![
        executable_parent.join(name),
        executable_parent.join("../Resources/runtime").join(name),
        PathBuf::from(format!("/opt/homebrew/bin/{name}")),
        PathBuf::from(format!("/usr/local/bin/{name}")),
    ];
    candidates.extend(runtime_candidates_from(executable_parent, name));
    candidates.extend(runtime_candidates_from(current_dir, name));
    candidates.into_iter().find(|path| path.is_file())
}

fn runtime_candidates_from(start: &Path, name: &str) -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    let mut directory = start;
    loop {
        candidates.push(directory.join("third_party/runtime/macos-arm64").join(name));
        let Some(parent) = directory.parent() else {
            break;
        };
        if parent == directory {
            break;
        }
        directory = parent;
    }
    candidates
}

fn file_id(value: &str) -> String {
    value
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}
fn io_error(error: std::io::Error) -> ApplicationError {
    ApplicationError::Repository(error.to_string())
}
fn hash_file(path: &Path) -> Result<String, ApplicationError> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)
        .map_err(|error| ApplicationError::Repository(error.to_string()))?;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 1024 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|error| ApplicationError::Repository(error.to_string()))?;
        if read == 0 {
            break;
        }
        digest.update(&buffer[..read]);
    }
    Ok(hex::encode(digest.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_development_runtime_from_repository_root() {
        let root = std::env::temp_dir().join(format!(
            "llplayernext-runtime-test-{}",
            application::now_ms()
        ));
        let runtime = root.join("third_party/runtime/macos-arm64");
        std::fs::create_dir_all(&runtime).unwrap();
        let whisper = runtime.join("whisper-cli");
        std::fs::write(&whisper, b"#!/bin/sh\n").unwrap();

        let executable = root.join("target/debug/api-http");
        let resolved =
            resolve_bundled_tool("whisper-cli", &executable, &root.join("apps/desktop")).unwrap();
        assert_eq!(resolved, whisper);

        let _ = std::fs::remove_dir_all(root);
    }
}
