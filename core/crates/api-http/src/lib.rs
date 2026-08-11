use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, DictionaryProvider, EnglishPronunciationProvider,
    ImportSubtitle, InMemorySecretStore, RecordSpeakingProduction, RegisterMedia, SecretStore,
    SyntacticAnalysisProvider, SyntacticConsumerOrchestrator, SyntacticProductQualification,
};
use axum::body::Body;
use axum::extract::{MatchedPath, Path, Query, State};
use axum::http::{HeaderMap, HeaderValue, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use dictionary_provider::{
    ChineseDictionaryProvider, ChinesePronunciationProvider, EcdictProvider,
    FreeDictionaryProvider, JapaneseDictionaryProvider,
};
use domain::{
    HuntingCandidate, HuntingCandidateStatus, HuntingOccurrenceQueryResult, HuntingTarget,
    HuntingTargetId, HuntingTargetStatus, LanguageCode, LearningStatus, LexicalEntryId,
    ListeningInboxItem, ListeningInboxItemId, ListeningInboxStatus, MediaAvailability, MediaId,
    MediaKind, MediaTriageIntent, PracticeAttempt, PracticeAttemptId, PracticeItem,
    PracticeSession, PracticeSessionId, ReviewItem, ReviewItemId, SubtitleSentenceId,
    SubtitleTrackId, UpgradeSuggestion, UpgradeSuggestionId, UpgradeSuggestionStatus,
    VocabularyAssetBundle,
};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;

mod application_executor;
mod event_payloads {
    pub use local_runtime::events::*;
}
mod event_stream;
mod routes;
mod secret_store_keychain;
use application_executor::ApplicationExecutor;
use local_runtime::{
    CreatePhoneticJobRequest, CreateSoundLineJob, CreateSpeechBatchJob,
    LearningPreparationCoordinator, LearningResourceManager, PhoneticAnalysisCoordinator,
    RecordingTranscriptionCoordinator, SoundLineCoordinator, SpeechBatchCoordinator,
    SpeechSynthesisManager, SubtitleSearchCoordinator,
};
pub use local_runtime::{SyntaxCapabilityManager, SyntaxCapabilityStatus, SyntaxCapabilityView};
pub use secret_store_keychain::KeychainSecretStore;

static ERROR_SEQUENCE: AtomicU64 = AtomicU64::new(1);

pub const API_VERSION: u16 = 1;
/// Contract `3.3.0` adds the durable package lifecycle HTTP surface on top of
/// the learning-material `3.2.0` (itself an additive minor over the
/// material-retention `3.1.0`, which was an additive minor over the R5
/// breaking `3.0.0`, which removed the published `/v1/*chunk-timelines*`
/// operations and the retired ChunkTimeline LLTimeline fields). The minor
/// bump is purely additive and backward-compatible: the fixed
/// `/v1/materials/{material_id}/package-installations`,
/// `/v1/materials/{material_id}/editions`, and
/// `/v1/materials/{material_id}/edition-adoption` operations expose the
/// application-owned Package Installation (candidate-only), Edition Listing,
/// and Learning Edition Adoption (explicit, idempotent) intents behind
/// path-free, privacy-redacted DTOs, while every previously published
/// endpoint stays compatible. API generation stays `1`, the runtime/workspace
/// version stays `0.7.0`, the SQLite schema stays v60 with no new migration,
/// and the Content Package v1/v2 schema versions are unchanged; `3.3.0` is
/// the current unreleased contract.
pub const CONTRACT_VERSION: &str = "3.3.0";

fn next_correlation_id() -> String {
    format!("api-{}", ERROR_SEQUENCE.fetch_add(1, Ordering::Relaxed))
}

#[derive(Clone)]
pub struct AnalysisRuntime {
    pub transcription: Arc<RecordingTranscriptionCoordinator>,
    pub phonetic_analysis: Arc<PhoneticAnalysisCoordinator>,
    pub speech_jobs: Arc<SpeechBatchCoordinator>,
    pub sound_line: Arc<SoundLineCoordinator>,
    pub foundation_preparation: Arc<LearningPreparationCoordinator>,
}

#[derive(Clone)]
pub struct LanguageRuntime {
    pub dictionaries: Arc<Vec<Arc<dyn DictionaryProvider>>>,
    pub learning_resources: Arc<LearningResourceManager>,
    pub subtitle_search: Arc<SubtitleSearchCoordinator>,
    pub syntactic_consumers: Arc<SyntacticConsumerOrchestrator>,
    pub syntax_capability: Arc<SyntaxCapabilityManager>,
    pub syntax_analysis_lock: Arc<tokio::sync::Mutex<()>>,
}

#[derive(Clone)]
pub struct GenerativeRuntime {
    /// Provider-neutral local-first TTS. It owns synthesis/cache lifecycle and
    /// deliberately has no learning repository, so playback cannot become
    /// evidence or personal-production data.
    pub speech_synthesis: Arc<SpeechSynthesisManager>,
    /// Explicit opt-in model lifecycle. It has no learning repositories and
    /// cannot write corpus/evidence/projection facts.
    pub semantic_embedding: Arc<embedding_provider::ManagedFastEmbedProvider>,
    /// Provider/account-scoped LLM batch governors plus explicit batch
    /// cancellation and progress lifecycle.
    pub llm_batches: application::batch_governor::LlmBatchCoordinator,
    /// Builds protocol-neutral semantic runtimes from persisted profiles.
    /// Concrete protocol selection stays in the adapter crate.
    pub llm_runtime_factory: Arc<dyn application::SemanticLlmRuntimeFactory>,
    /// Assembles native realtime protocol adapters behind the
    /// application-owned provider-neutral seam.
    pub realtime_adapter_factory: Arc<dyn application::RealtimeConversationAdapterFactory>,
}

#[derive(Clone)]
pub struct ApiInfrastructure {
    pub token: Arc<str>,
    pub events: broadcast::Sender<EventEnvelope>,
    pub secret_store: Arc<dyn SecretStore>,
}

#[derive(Clone)]
pub struct ApiState {
    pub(crate) application: ApplicationExecutor,
    pub analysis: AnalysisRuntime,
    pub language: LanguageRuntime,
    pub generative: GenerativeRuntime,
    pub infrastructure: ApiInfrastructure,
}

impl ApiState {
    pub fn new<R>(services: AppServices, repository: Arc<R>, token: impl Into<Arc<str>>) -> Self
    where
        R: application::TranscriptionRepository
            + application::PhoneticAnalysisRepository
            + application::BackgroundJobStore
            + application::LearningPreparationRunRepository
            + 'static,
    {
        let (events, _) = broadcast::channel(128);
        let ecdict = Arc::new(EcdictProvider::new());
        let services = services
            .with_lexical_normalizers(vec![ecdict.clone()])
            .with_pronunciation_providers(vec![
                Arc::new(EnglishPronunciationProvider),
                Arc::new(ChinesePronunciationProvider::new()),
            ]);
        let transcription = Arc::new(
            RecordingTranscriptionCoordinator::new(
                services.clone(),
                repository.clone(),
                events.clone(),
            )
            .expect("recording transcription coordinator must initialize"),
        );
        #[cfg(test)]
        let phonetic_analysis = Arc::new(
            PhoneticAnalysisCoordinator::new_with_test_provider(
                services.clone(),
                repository.clone(),
                events.clone(),
            )
            .expect("phonetic analysis coordinator must initialize"),
        );
        #[cfg(not(test))]
        let phonetic_analysis = Arc::new(
            PhoneticAnalysisCoordinator::new(services.clone(), repository.clone(), events.clone())
                .expect("phonetic analysis coordinator must initialize"),
        );
        let speech_jobs =
            SpeechBatchCoordinator::new(services.clone(), events.clone(), repository.clone())
                .expect("speech batch coordinator must initialize");
        let sound_line = SoundLineCoordinator::new(
            services.clone(),
            events.clone(),
            repository.clone(),
            local_runtime::resolved_forced_align_provider(),
        )
        .expect("sound line coordinator must initialize");
        let foundation_preparation =
            LearningPreparationCoordinator::new(services.clone(), repository.clone())
                .expect("learning preparation coordinator must initialize");
        Self {
            application: ApplicationExecutor::new(services.clone()),
            analysis: AnalysisRuntime {
                transcription,
                phonetic_analysis,
                speech_jobs,
                sound_line,
                foundation_preparation,
            },
            language: LanguageRuntime {
                dictionaries: Arc::new(vec![
                    ecdict,
                    Arc::new(ChineseDictionaryProvider::new()),
                    Arc::new(JapaneseDictionaryProvider::new()),
                    Arc::new(
                        FreeDictionaryProvider::new()
                            .expect("dictionary HTTP client must initialize"),
                    ),
                ]),
                learning_resources: Arc::new(LearningResourceManager::new()),
                subtitle_search: Arc::new(SubtitleSearchCoordinator::new()),
                syntactic_consumers: Arc::new(SyntacticConsumerOrchestrator::new(
                    None,
                    SyntacticProductQualification::corrected_v2(),
                )),
                syntax_capability: SyntaxCapabilityManager::unmanaged(),
                syntax_analysis_lock: Arc::new(tokio::sync::Mutex::new(())),
            },
            generative: GenerativeRuntime {
                speech_synthesis: SpeechSynthesisManager::new(
                    std::env::temp_dir()
                        .join(format!("llplayer-tts-unmanaged-{}", std::process::id())),
                    Vec::new(),
                ),
                semantic_embedding: Arc::new(embedding_provider::ManagedFastEmbedProvider::new(
                    std::env::temp_dir().join(format!(
                        "llplayer-embedding-unmanaged-{}",
                        std::process::id()
                    )),
                )),
                llm_batches: application::batch_governor::LlmBatchCoordinator::new(repository)
                    .expect("LLM batch coordinator must initialize"),
                llm_runtime_factory: Arc::new(llm_provider::LlmSemanticRuntimeFactory::new()),
                realtime_adapter_factory: Arc::new(
                    realtime_provider::NativeRealtimeAdapterFactory::new(),
                ),
            },
            infrastructure: ApiInfrastructure {
                token: token.into(),
                events,
                secret_store: Arc::new(InMemorySecretStore::new()),
            },
        }
    }

    /// Injects the platform secret store (OS keychain in production).
    pub fn with_secret_store(mut self, secret_store: Arc<dyn SecretStore>) -> Self {
        self.infrastructure.secret_store = secret_store;
        self
    }

    pub fn with_llm_runtime_factory(
        mut self,
        factory: Arc<dyn application::SemanticLlmRuntimeFactory>,
    ) -> Self {
        self.generative.llm_runtime_factory = factory;
        self
    }

    pub fn with_realtime_adapter_factory(
        mut self,
        factory: Arc<dyn application::RealtimeConversationAdapterFactory>,
    ) -> Self {
        self.generative.realtime_adapter_factory = factory;
        self
    }

    pub fn with_syntactic_provider(mut self, provider: Arc<dyn SyntacticAnalysisProvider>) -> Self {
        self.language.syntactic_consumers = Arc::new(SyntacticConsumerOrchestrator::new(
            Some(provider),
            SyntacticProductQualification::corrected_v2(),
        ));
        self
    }

    pub fn with_syntax_capability(
        mut self,
        manager: Arc<SyntaxCapabilityManager>,
        provider: Arc<dyn SyntacticAnalysisProvider>,
    ) -> Self {
        self.language.syntax_capability = manager;
        self.language.syntactic_consumers = Arc::new(SyntacticConsumerOrchestrator::new(
            Some(provider),
            SyntacticProductQualification::corrected_v2(),
        ));
        self
    }

    pub fn with_speech_synthesis(mut self, manager: Arc<SpeechSynthesisManager>) -> Self {
        self.generative.speech_synthesis = manager;
        self
    }

    pub fn with_semantic_embedding_manager(
        mut self,
        manager: Arc<embedding_provider::ManagedFastEmbedProvider>,
    ) -> Self {
        self.generative.semantic_embedding = manager;
        self
    }
}

pub fn router(state: ApiState) -> Router {
    let protected = routes::router::protected_router(&state);

    Router::new()
        .route("/v1/health", get(health))
        .merge(protected)
        .layer(middleware::from_fn(observe_request))
        .with_state(state)
}

async fn observe_request(request: Request<Body>, next: Next) -> Response {
    let request_correlation_id = next_correlation_id();
    let method = request.method().clone();
    let route = request.extensions().get::<MatchedPath>().map_or_else(
        || request.uri().path().to_owned(),
        |path| path.as_str().to_owned(),
    );
    let started = Instant::now();
    let mut response = next.run(request).await;
    let correlation_id = response
        .extensions()
        .get::<ErrorCorrelationId>()
        .map_or(request_correlation_id, |value| value.0.clone());
    if let Ok(value) = HeaderValue::from_str(&correlation_id) {
        response.headers_mut().insert("x-correlation-id", value);
    }
    tracing::info!(
        event = "api.request.completed",
        correlation_id,
        method = %method,
        route,
        status = response.status().as_u16(),
        duration_ms = started.elapsed().as_millis() as u64,
        "local API request completed"
    );
    response
}

async fn authorize(
    State(state): State<ApiState>,
    headers: HeaderMap,
    request: Request<Body>,
    next: Next,
) -> Result<Response, ApiError> {
    let expected = format!("Bearer {}", state.infrastructure.token);
    if headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v == expected)
    {
        Ok(next.run(request).await)
    } else {
        Err(ApiError::unauthorized())
    }
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
    api_version: u16,
    contract_version: &'static str,
    runtime_version: &'static str,
}

async fn health() -> Json<Health> {
    Json(Health {
        status: "ok",
        api_version: API_VERSION,
        contract_version: CONTRACT_VERSION,
        runtime_version: env!("CARGO_PKG_VERSION"),
    })
}

#[derive(Debug, Serialize)]
pub struct ErrorBody {
    pub code: &'static str,
    pub message: String,
    pub correlation_id: String,
    pub retryable: bool,
}

#[derive(Debug)]
pub struct ApiError {
    status: StatusCode,
    body: ErrorBody,
    internal_message: Option<String>,
}

#[derive(Clone)]
struct ErrorCorrelationId(String);

impl ApiError {
    pub(crate) fn new(
        status: StatusCode,
        code: &'static str,
        message: impl Into<String>,
        retryable: bool,
    ) -> Self {
        Self {
            status,
            body: ErrorBody {
                code,
                message: message.into(),
                correlation_id: next_correlation_id(),
                retryable,
            },
            internal_message: None,
        }
    }

    pub(crate) fn internal(
        status: StatusCode,
        code: &'static str,
        public_message: &'static str,
        internal_message: impl Into<String>,
        retryable: bool,
    ) -> Self {
        let mut error = Self::new(status, code, public_message, retryable);
        error.internal_message = Some(internal_message.into());
        error
    }

    fn unauthorized() -> Self {
        Self::new(
            StatusCode::UNAUTHORIZED,
            "unauthorized",
            "invalid local API token",
            false,
        )
    }

    pub(crate) fn not_found(entity: &'static str) -> Self {
        Self::new(
            StatusCode::NOT_FOUND,
            "not_found",
            format!("{entity} was not found"),
            false,
        )
    }

    pub(crate) fn gateway(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_GATEWAY, code, message, true)
    }
}

impl From<ApplicationError> for ApiError {
    fn from(value: ApplicationError) -> Self {
        match value {
            ApplicationError::NotFound(entity) => Self::not_found(entity),
            ApplicationError::Validation(field) => Self::new(
                StatusCode::BAD_REQUEST,
                "validation_error",
                format!("{field} must not be empty"),
                false,
            ),
            ApplicationError::Invalid(message) => {
                Self::new(StatusCode::BAD_REQUEST, "invalid_input", message, false)
            }
            ApplicationError::Domain(error) => Self::new(
                StatusCode::BAD_REQUEST,
                "domain_error",
                error.to_string(),
                false,
            ),
            ApplicationError::Repository(error) => Self::internal(
                StatusCode::INTERNAL_SERVER_ERROR,
                "repository_error",
                "local data operation failed",
                error,
                true,
            ),
            ApplicationError::Subtitle(error) => Self::new(
                StatusCode::BAD_REQUEST,
                "subtitle_parse_error",
                error.to_string(),
                false,
            ),
            ApplicationError::DictionaryProvider(error) => Self::new(
                StatusCode::BAD_GATEWAY,
                "dictionary_provider_error",
                error.to_string(),
                true,
            ),
            ApplicationError::LexicalNormalizationProvider(error) => Self::new(
                StatusCode::BAD_GATEWAY,
                "lexical_normalization_provider_error",
                error.to_string(),
                true,
            ),
            ApplicationError::Conflict(message) => {
                Self::new(StatusCode::CONFLICT, "asset_conflict", message, false)
            }
            ApplicationError::Cancelled(operation) => Self::new(
                StatusCode::CONFLICT,
                "batch_cancelled",
                format!("{operation} was cancelled"),
                false,
            ),
            ApplicationError::ExternalProcess(message) => Self::internal(
                StatusCode::BAD_GATEWAY,
                "external_process_error",
                "local processing tool failed",
                message,
                true,
            ),
            // Phase 3.12: the standardized provider taxonomy. `to_string()` is
            // secret-free by construction (auth carries no payload), so this
            // never echoes a credential to the client.
            ApplicationError::Provider(error) => {
                use domain::LlmProviderError as E;
                let (status, retryable) = match &error {
                    E::RateLimit { .. } => (StatusCode::TOO_MANY_REQUESTS, true),
                    E::Timeout => (StatusCode::GATEWAY_TIMEOUT, true),
                    E::Offline => (StatusCode::BAD_GATEWAY, true),
                    E::UnsupportedCapability { .. } => (StatusCode::BAD_REQUEST, false),
                    _ => (StatusCode::BAD_GATEWAY, false),
                };
                Self::new(status, "llm_provider_error", error.to_string(), retryable)
            }
            ApplicationError::RealtimeProvider(error) => {
                use domain::RealtimeProviderError as E;
                if matches!(error, E::Auth) {
                    Self::new(
                        StatusCode::BAD_REQUEST,
                        "realtime_credential_missing",
                        "realtime provider credential is missing",
                        false,
                    )
                } else {
                    let (status, retryable) = match &error {
                        E::RateLimit { .. } => (StatusCode::TOO_MANY_REQUESTS, true),
                        E::Timeout => (StatusCode::GATEWAY_TIMEOUT, true),
                        E::Offline | E::Disconnected => (StatusCode::BAD_GATEWAY, true),
                        E::UnsupportedCapability { .. } => (StatusCode::BAD_REQUEST, false),
                        E::Protocol { .. } | E::Auth => (StatusCode::BAD_GATEWAY, false),
                    };
                    Self::new(
                        status,
                        "realtime_provider_error",
                        error.to_string(),
                        retryable,
                    )
                }
            }
            ApplicationError::SecretStore(error) => Self::internal(
                StatusCode::INTERNAL_SERVER_ERROR,
                "secret_store_error",
                "secure credential storage failed",
                error.to_string(),
                true,
            ),
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let correlation_id = self.body.correlation_id.clone();
        tracing::error!(
            event = "api.error",
            status = self.status.as_u16(),
            code = self.body.code,
            correlation_id = self.body.correlation_id,
            retryable = self.body.retryable,
            public_message = self.body.message,
            internal_message = self.internal_message.as_deref().unwrap_or(""),
            "local API request failed"
        );
        let mut response = (self.status, Json(self.body)).into_response();
        response
            .extensions_mut()
            .insert(ErrorCorrelationId(correlation_id));
        response
    }
}

#[cfg(test)]
mod tests;
