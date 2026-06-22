use std::sync::Arc;

use api_events::{EventEnvelope, EventName};
use application::{AppServices, ApplicationError, PhoneticAnalysisRepository, now_ms};
use domain::{
    PhoneticAnalysis, PhoneticAnalysisId, PhoneticAnalysisJob, PhoneticAnalysisJobId,
    PhoneticAnalysisJobStatus, PhoneticAnalysisModelDescriptor, PhoneticAnalysisModelId,
    PhoneticAnalysisProviderInfo, PhoneticAnalysisScope, PhoneticFindingFeedback,
    PhoneticFindingId, PhoneticModelState, SubtitleSentenceId, SubtitleTrackId, TimelineStatus,
};
use tokio::sync::{Semaphore, broadcast};

const FAKE_PROVIDER_ID: &str = "research-fixture";
const FAKE_MODEL_ID: &str = "research-fixture:deterministic@v1";

#[derive(Debug, Clone, serde::Deserialize)]
pub struct CreatePhoneticJobRequest {
    pub track_id: String,
    pub sentence_id: Option<String>,
    pub model_id: String,
    pub audio_start_ms: Option<u64>,
    pub audio_end_ms: Option<u64>,
    pub research_mode: Option<String>,
}

#[derive(Clone)]
pub struct PhoneticAnalysisCoordinator {
    services: AppServices,
    repository: Arc<dyn PhoneticAnalysisRepository>,
    events: broadcast::Sender<EventEnvelope>,
    queue: Arc<Semaphore>,
}

impl PhoneticAnalysisCoordinator {
    pub fn new(
        services: AppServices,
        repository: Arc<dyn PhoneticAnalysisRepository>,
        events: broadcast::Sender<EventEnvelope>,
    ) -> Result<Self, ApplicationError> {
        let value = Self {
            services,
            repository,
            events,
            queue: Arc::new(Semaphore::new(1)),
        };
        value.repository.interrupt_active_phonetic_jobs(now_ms())?;
        value.seed_research_model()?;
        Ok(value)
    }

    pub fn providers(&self) -> Vec<PhoneticAnalysisProviderInfo> {
        let enabled = fake_enabled();
        vec![PhoneticAnalysisProviderInfo {
            id: FAKE_PROVIDER_ID.into(),
            display_name: "Deterministic research fixture".into(),
            runtime_id: "built-in-test-runtime".into(),
            runtime_version: env!("CARGO_PKG_VERSION").into(),
            available: enabled,
            experimental: true,
            supports_timestamps: true,
            supports_confidence: true,
            supported_languages: vec!["en".into()],
            supported_dialects: vec!["en-US".into()],
            phone_sets: vec!["arpabet".into()],
            diagnostic: (!enabled).then_some(
                "No release phonetic provider is selected. The deterministic research fixture is disabled."
                    .into(),
            ),
        }]
    }

    pub fn models(&self) -> Result<Vec<PhoneticAnalysisModelDescriptor>, ApplicationError> {
        self.repository.list_phonetic_models()
    }

    pub fn install_model(
        &self,
        id: &PhoneticAnalysisModelId,
    ) -> Result<PhoneticAnalysisModelDescriptor, ApplicationError> {
        let model = self
            .repository
            .get_phonetic_model(id)?
            .ok_or(ApplicationError::NotFound("phonetic analysis model"))?;
        if !model.distribution_allowed || !model.application_verified {
            return Err(ApplicationError::Conflict(
                "phonetic analysis model is not approved for installation",
            ));
        }
        Err(ApplicationError::Conflict(
            "no release phonetic provider supports model installation",
        ))
    }

    pub fn register_custom_model(
        &self,
        _path: String,
    ) -> Result<PhoneticAnalysisModelDescriptor, ApplicationError> {
        Err(ApplicationError::Conflict(
            "no release phonetic provider supports custom models",
        ))
    }

    pub fn cancel_model_install(
        &self,
        id: &PhoneticAnalysisModelId,
    ) -> Result<PhoneticAnalysisModelDescriptor, ApplicationError> {
        let mut model = self
            .repository
            .get_phonetic_model(id)?
            .ok_or(ApplicationError::NotFound("phonetic analysis model"))?;
        if model.state != PhoneticModelState::Installing {
            return Err(ApplicationError::Conflict(
                "phonetic analysis model is not installing",
            ));
        }
        model.state = PhoneticModelState::Failed;
        model.error = Some("installation cancelled".into());
        model.updated_at_ms = now_ms();
        let model = self.repository.upsert_phonetic_model(&model)?;
        self.emit_model(&model);
        Ok(model)
    }

    pub fn delete_model(&self, id: &PhoneticAnalysisModelId) -> Result<(), ApplicationError> {
        if id.as_str() == FAKE_MODEL_ID {
            return Err(ApplicationError::Conflict(
                "the deterministic research fixture cannot be deleted",
            ));
        }
        if self.repository.get_phonetic_model(id)?.is_none() {
            return Err(ApplicationError::NotFound("phonetic analysis model"));
        }
        self.repository.delete_phonetic_model(id)
    }

    pub fn jobs(&self) -> Result<Vec<PhoneticAnalysisJob>, ApplicationError> {
        self.repository.list_phonetic_jobs()
    }

    pub fn job(
        &self,
        id: &PhoneticAnalysisJobId,
    ) -> Result<Option<PhoneticAnalysisJob>, ApplicationError> {
        self.repository.get_phonetic_job(id)
    }

    pub fn analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneticAnalysis>, ApplicationError> {
        self.repository.list_track_phonetic_analyses(track_id)
    }

    pub fn analysis(
        &self,
        id: &PhoneticAnalysisId,
    ) -> Result<Option<PhoneticAnalysis>, ApplicationError> {
        self.repository.get_phonetic_analysis(id)
    }

    pub fn save_feedback(
        &self,
        feedback: &PhoneticFindingFeedback,
    ) -> Result<PhoneticFindingFeedback, ApplicationError> {
        let exists = self
            .repository
            .list_phonetic_jobs()?
            .into_iter()
            .filter_map(|job| job.analysis_id)
            .map(|id| self.repository.get_phonetic_analysis(&id))
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .flatten()
            .any(|analysis| {
                analysis
                    .findings
                    .iter()
                    .any(|finding| finding.id == feedback.finding_id)
            });
        if !exists {
            return Err(ApplicationError::NotFound("phonetic finding"));
        }
        self.repository.save_phonetic_feedback(feedback)
    }

    pub fn create_job(
        self: Arc<Self>,
        request: CreatePhoneticJobRequest,
    ) -> Result<PhoneticAnalysisJob, ApplicationError> {
        if !fake_enabled() {
            return Err(ApplicationError::Conflict(
                "no phonetic analysis provider is available",
            ));
        }
        let track_id = SubtitleTrackId::parse(request.track_id)?;
        let track = self
            .services
            .read_subtitle_track(&track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let model_id = PhoneticAnalysisModelId::parse(request.model_id)?;
        let model = self
            .repository
            .get_phonetic_model(&model_id)?
            .ok_or(ApplicationError::NotFound("phonetic analysis model"))?;
        if model.state != PhoneticModelState::Custom {
            return Err(ApplicationError::Conflict(
                "phonetic analysis model is not available",
            ));
        }
        let sentence_id = request
            .sentence_id
            .map(SubtitleSentenceId::parse)
            .transpose()?;
        let sentence = sentence_id
            .as_ref()
            .map(|id| {
                track
                    .sentences
                    .iter()
                    .find(|sentence| &sentence.id == id)
                    .cloned()
                    .ok_or(ApplicationError::NotFound("subtitle sentence"))
            })
            .transpose()?;
        let start_ms = request
            .audio_start_ms
            .or_else(|| sentence.as_ref().map(|value| value.start.get()))
            .or_else(|| track.sentences.first().map(|value| value.start.get()))
            .ok_or(ApplicationError::Validation("audio start"))?;
        let end_ms = request
            .audio_end_ms
            .or_else(|| sentence.as_ref().map(|value| value.end.get()))
            .or_else(|| track.sentences.last().map(|value| value.end.get()))
            .ok_or(ApplicationError::Validation("audio end"))?;
        if start_ms >= end_ms {
            return Err(ApplicationError::Domain(
                domain::DomainError::InvalidAudioRange,
            ));
        }
        let created_at_ms = now_ms();
        let research_mode = research_mode(request.research_mode.as_deref())?;
        let fingerprint = format!(
            "{}:{}:{}:{}:{}:{}",
            track.fingerprint,
            sentence_id
                .as_ref()
                .map(SubtitleSentenceId::as_str)
                .unwrap_or("track"),
            model.id.as_str(),
            start_ms,
            end_ms,
            research_mode
        );
        if let Some(existing) = self.repository.find_completed_phonetic_job(&fingerprint)? {
            return Ok(existing);
        }
        let job = PhoneticAnalysisJob {
            id: PhoneticAnalysisJobId::from_fingerprint(
                "phonetic-analysis-job",
                &format!("{fingerprint}:{created_at_ms}"),
            ),
            media_id: track.media_id,
            track_id,
            sentence_id,
            scope: if sentence.is_some() {
                PhoneticAnalysisScope::Sentence
            } else {
                PhoneticAnalysisScope::Track
            },
            audio_start_ms: start_ms,
            audio_end_ms: end_ms,
            provider_id: FAKE_PROVIDER_ID.into(),
            provider_version: "v1".into(),
            runtime_id: "built-in-test-runtime".into(),
            runtime_version: env!("CARGO_PKG_VERSION").into(),
            model_id: model.id,
            model_revision: model.revision,
            model_checksum_sha256: model.checksum_sha256,
            requested_phone_set: "arpabet".into(),
            settings_json: serde_json::json!({"research_mode": research_mode}).to_string(),
            input_fingerprint: fingerprint,
            status: PhoneticAnalysisJobStatus::Queued,
            phase_progress: 0,
            error_code: None,
            error_message: None,
            retry_of_job_id: None,
            analysis_id: None,
            created_at_ms,
            started_at_ms: None,
            completed_at_ms: None,
            updated_at_ms: created_at_ms,
        };
        let job = self.repository.create_phonetic_job(&job)?;
        self.emit_job(&job);
        self.start(job.id.clone());
        Ok(job)
    }

    pub fn cancel_job(
        &self,
        id: &PhoneticAnalysisJobId,
    ) -> Result<PhoneticAnalysisJob, ApplicationError> {
        let mut job = self
            .repository
            .get_phonetic_job(id)?
            .ok_or(ApplicationError::NotFound("phonetic analysis job"))?;
        if !matches!(
            job.status,
            PhoneticAnalysisJobStatus::Completed
                | PhoneticAnalysisJobStatus::Cancelled
                | PhoneticAnalysisJobStatus::Failed
                | PhoneticAnalysisJobStatus::Interrupted
        ) {
            job.status = PhoneticAnalysisJobStatus::Cancelled;
            job.completed_at_ms = Some(now_ms());
            job.updated_at_ms = now_ms();
            self.repository.update_phonetic_job(&job)?;
            self.emit_job(&job);
        }
        Ok(job)
    }

    pub fn retry_job(
        self: Arc<Self>,
        id: &PhoneticAnalysisJobId,
    ) -> Result<PhoneticAnalysisJob, ApplicationError> {
        let old = self
            .repository
            .get_phonetic_job(id)?
            .ok_or(ApplicationError::NotFound("phonetic analysis job"))?;
        if !matches!(
            old.status,
            PhoneticAnalysisJobStatus::Cancelled
                | PhoneticAnalysisJobStatus::Failed
                | PhoneticAnalysisJobStatus::Interrupted
        ) {
            return Err(ApplicationError::Conflict(
                "phonetic analysis job cannot be retried",
            ));
        }
        let mut job = self.clone().create_job(CreatePhoneticJobRequest {
            track_id: old.track_id.as_str().into(),
            sentence_id: old.sentence_id.as_ref().map(|id| id.as_str().into()),
            model_id: old.model_id.as_str().into(),
            audio_start_ms: Some(old.audio_start_ms),
            audio_end_ms: Some(old.audio_end_ms),
            research_mode: job_research_mode(&old),
        })?;
        job.retry_of_job_id = Some(old.id);
        self.repository.update_phonetic_job(&job)?;
        Ok(job)
    }

    fn start(self: &Arc<Self>, id: PhoneticAnalysisJobId) {
        let coordinator = self.clone();
        tokio::spawn(async move {
            let _permit = coordinator.queue.acquire().await;
            if let Err(error) = coordinator.execute(&id).await {
                let _ = coordinator.fail(&id, error.to_string());
            }
        });
    }

    async fn execute(&self, id: &PhoneticAnalysisJobId) -> Result<(), ApplicationError> {
        let mut job = self
            .repository
            .get_phonetic_job(id)?
            .ok_or(ApplicationError::NotFound("phonetic analysis job"))?;
        if job.status == PhoneticAnalysisJobStatus::Cancelled {
            return Ok(());
        }
        job.started_at_ms = Some(now_ms());
        for (status, progress) in [
            (PhoneticAnalysisJobStatus::Extracting, 10),
            (PhoneticAnalysisJobStatus::RecognizingPhones, 45),
            (PhoneticAnalysisJobStatus::Aligning, 75),
            (PhoneticAnalysisJobStatus::Analyzing, 90),
        ] {
            if self
                .repository
                .get_phonetic_job(id)?
                .is_some_and(|value| value.status == PhoneticAnalysisJobStatus::Cancelled)
            {
                return Ok(());
            }
            job.status = status;
            job.phase_progress = progress;
            job.updated_at_ms = now_ms();
            self.repository.update_phonetic_job(&job)?;
            self.emit_job(&job);
            let delay_ms = if job_research_mode(&job).as_deref() == Some("slow") {
                200
            } else {
                10
            };
            tokio::time::sleep(std::time::Duration::from_millis(delay_ms)).await;
        }
        if job_research_mode(&job).as_deref() == Some("fail") {
            return Err(ApplicationError::Conflict(
                "deterministic research fixture failure",
            ));
        }
        let analyses = if job.scope == PhoneticAnalysisScope::Track {
            self.services
                .read_subtitle_track(&job.track_id)?
                .ok_or(ApplicationError::NotFound("subtitle track"))?
                .sentences
                .into_iter()
                .map(|sentence| {
                    let mut sentence_job = job.clone();
                    sentence_job.sentence_id = Some(sentence.id.clone());
                    sentence_job.scope = PhoneticAnalysisScope::Sentence;
                    sentence_job.audio_start_ms = sentence.start.get();
                    sentence_job.audio_end_ms = sentence.end.get();
                    self.services.build_research_fixture_phonetic_analysis(
                        &sentence_job,
                        Some(&sentence),
                        job_research_mode(&sentence_job).as_deref() == Some("partial"),
                    )
                })
                .collect::<Result<Vec<_>, _>>()?
        } else {
            let sentence = job
                .sentence_id
                .as_ref()
                .map(|id| self.services.read_sentence(id))
                .transpose()?
                .flatten();
            vec![self.services.build_research_fixture_phonetic_analysis(
                &job,
                sentence.as_ref(),
                job_research_mode(&job).as_deref() == Some("partial"),
            )?]
        };
        let mut phone_timeline_ids = Vec::new();
        for analysis in &analyses {
            self.repository.save_phonetic_analysis(analysis)?;
            let timeline = self
                .services
                .create_phone_timeline_from_analysis(analysis, Some(TimelineStatus::Candidate))?;
            phone_timeline_ids.push(timeline.id);
        }
        let _ = self.events.send(EventEnvelope::v1(
            EventName::PhoneticAnalysisCompleted,
            serde_json::json!({
                "job_id": job.id.as_str(),
                "track_id": job.track_id.as_str(),
                "analysis_ids": analyses.iter().map(|analysis| analysis.id.as_str()).collect::<Vec<_>>(),
                "phone_timeline_ids": phone_timeline_ids.iter().map(|timeline_id| timeline_id.as_str()).collect::<Vec<_>>(),
            }),
        ));
        job.status = PhoneticAnalysisJobStatus::Completed;
        job.phase_progress = 100;
        job.analysis_id = analyses.first().map(|analysis| analysis.id.clone());
        job.completed_at_ms = Some(now_ms());
        job.updated_at_ms = now_ms();
        self.repository.update_phonetic_job(&job)?;
        self.emit_job(&job);
        Ok(())
    }

    fn fail(&self, id: &PhoneticAnalysisJobId, message: String) -> Result<(), ApplicationError> {
        let mut job = self
            .repository
            .get_phonetic_job(id)?
            .ok_or(ApplicationError::NotFound("phonetic analysis job"))?;
        if job.status != PhoneticAnalysisJobStatus::Cancelled {
            job.status = PhoneticAnalysisJobStatus::Failed;
            job.error_code = Some("research_fixture_failed".into());
            job.error_message = Some(message);
            job.completed_at_ms = Some(now_ms());
            job.updated_at_ms = now_ms();
            self.repository.update_phonetic_job(&job)?;
            self.emit_job(&job);
        }
        Ok(())
    }

    fn seed_research_model(&self) -> Result<(), ApplicationError> {
        let id = PhoneticAnalysisModelId::parse(FAKE_MODEL_ID)?;
        if self.repository.get_phonetic_model(&id)?.is_none() {
            self.repository
                .upsert_phonetic_model(&PhoneticAnalysisModelDescriptor {
                    id,
                    provider_id: FAKE_PROVIDER_ID.into(),
                    display_name: "Deterministic research fixture".into(),
                    family: "synthetic-test-only".into(),
                    revision: "v1".into(),
                    checksum_sha256: "not-a-distributable-model".into(),
                    download_url: None,
                    local_path: None,
                    size_bytes: 0,
                    supported_languages: vec!["en".into()],
                    supported_dialects: vec!["en-US".into()],
                    phone_sets: vec!["arpabet".into()],
                    supports_timestamps: true,
                    expected_sample_rate_hz: 16_000,
                    context_window_ms: None,
                    state: PhoneticModelState::Custom,
                    installed_bytes: 0,
                    error: None,
                    license: "Synthetic test fixture".into(),
                    training_data_provenance: "No training data; deterministic fixture".into(),
                    distribution_allowed: false,
                    application_verified: false,
                    updated_at_ms: now_ms(),
                })?;
        }
        Ok(())
    }

    fn emit_job(&self, job: &PhoneticAnalysisJob) {
        let _ = self.events.send(EventEnvelope::v1(
            EventName::PhoneticAnalysisJobChanged,
            serde_json::to_value(job).expect("phonetic job serializes"),
        ));
    }

    fn emit_model(&self, model: &PhoneticAnalysisModelDescriptor) {
        let _ = self.events.send(EventEnvelope::v1(
            EventName::PhoneticAnalysisModelChanged,
            serde_json::to_value(model).expect("phonetic model serializes"),
        ));
    }
}

fn fake_enabled() -> bool {
    cfg!(test) || std::env::var("LLPLAYERNEXT_ENABLE_FAKE_PHONETIC_PROVIDER").as_deref() == Ok("1")
}

pub fn finding_id(value: String) -> Result<PhoneticFindingId, ApplicationError> {
    PhoneticFindingId::parse(value).map_err(ApplicationError::from)
}

fn research_mode(value: Option<&str>) -> Result<&str, ApplicationError> {
    match value.unwrap_or("success") {
        value @ ("success" | "partial" | "fail" | "slow") => Ok(value),
        _ => Err(ApplicationError::Validation("research mode")),
    }
}

fn job_research_mode(job: &PhoneticAnalysisJob) -> Option<String> {
    serde_json::from_str::<serde_json::Value>(&job.settings_json)
        .ok()?
        .get("research_mode")?
        .as_str()
        .map(str::to_owned)
}
