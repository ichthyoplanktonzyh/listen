use std::convert::Infallible;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, CreateWordObservation, DictionaryProvider, ImportSubtitle,
    RegisterMedia, SourceContext, UpdateWordProfile,
};
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post, put};
use axum::{Json, Router};
use dictionary_provider::FreeDictionaryProvider;
use domain::{
    LanguageCode, MediaAvailability, MediaId, MediaKind, ObservationResult, SubtitleSentenceId,
    SubtitleTrackId, VocabularyAssetBundle, WordProfileId, WordStatus,
};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;

mod transcription;
use transcription::{CreateJobRequest, TranscriptionCoordinator};

static ERROR_SEQUENCE: AtomicU64 = AtomicU64::new(1);

#[derive(Clone)]
pub struct ApiState {
    pub services: AppServices,
    pub token: Arc<str>,
    pub events: broadcast::Sender<EventEnvelope>,
    pub dictionaries: Arc<Vec<Arc<dyn DictionaryProvider>>>,
    pub transcription: Arc<TranscriptionCoordinator>,
}

impl ApiState {
    pub fn new(
        services: AppServices,
        transcription_repository: Arc<dyn application::TranscriptionRepository>,
        token: impl Into<Arc<str>>,
    ) -> Self {
        let (events, _) = broadcast::channel(128);
        let transcription = Arc::new(
            TranscriptionCoordinator::new(
                services.clone(),
                transcription_repository,
                events.clone(),
            )
            .expect("transcription coordinator must initialize"),
        );
        Self {
            services,
            token: token.into(),
            events,
            dictionaries: Arc::new(vec![Arc::new(
                FreeDictionaryProvider::new().expect("dictionary HTTP client must initialize"),
            )]),
            transcription,
        }
    }
}

pub fn router(state: ApiState) -> Router {
    let protected = Router::new()
        .route("/v1/media", post(register_media))
        .route("/v1/media/{media_id}", get(read_media))
        .route("/v1/media/{media_id}/subtitles", post(import_subtitle))
        .route("/v1/subtitles/{track_id}", get(read_subtitle))
        .route("/v1/subtitles/{track_id}/export", get(export_subtitle))
        .route("/v1/word-profiles/batch", post(read_words))
        .route(
            "/v1/media/{media_id}/progress",
            get(read_progress).put(update_progress),
        )
        .route("/v1/word-profiles", get(read_word).put(update_word))
        .route("/v1/word-observations", post(create_observation))
        .route("/v1/vocabulary", get(list_vocabulary))
        .route("/v1/vocabulary/export", get(export_vocabulary))
        .route("/v1/vocabulary/import", post(import_vocabulary))
        .route("/v1/word-profiles/{profile_id}/details", get(word_details))
        .route(
            "/v1/word-profiles/{profile_id}/learning-content",
            put(update_learning_content),
        )
        .route(
            "/v1/vocabulary/import-external",
            post(import_external_vocabulary),
        )
        .route(
            "/v1/media/{media_id}/availability",
            axum::routing::put(update_media_availability),
        )
        .route("/v1/events", get(events))
        .route("/v1/dictionary", get(dictionary_lookup))
        .route("/v1/transcription/providers", get(transcription_providers))
        .route("/v1/transcription/models", get(transcription_models))
        .route(
            "/v1/transcription/models/install",
            post(install_transcription_model),
        )
        .route(
            "/v1/transcription/models/register-custom",
            post(register_custom_transcription_model),
        )
        .route(
            "/v1/transcription/models/{model_id}/cancel-install",
            post(cancel_transcription_model_install),
        )
        .route(
            "/v1/transcription/models/{model_id}",
            axum::routing::delete(delete_transcription_model),
        )
        .route(
            "/v1/transcription/jobs",
            get(transcription_jobs).post(create_transcription_job),
        )
        .route("/v1/transcription/jobs/{job_id}", get(transcription_job))
        .route(
            "/v1/transcription/jobs/{job_id}/cancel",
            post(cancel_transcription_job),
        )
        .route(
            "/v1/transcription/jobs/{job_id}/retry",
            post(retry_transcription_job),
        )
        .route(
            "/v1/sentences/{sentence_id}/diagnosis",
            get(diagnose_sentence),
        )
        .route_layer(middleware::from_fn_with_state(state.clone(), authorize));

    Router::new()
        .route("/v1/health", get(health))
        .merge(protected)
        .with_state(state)
}

async fn events(
    State(state): State<ApiState>,
) -> Sse<impl futures_core::Stream<Item = Result<Event, Infallible>>> {
    let mut receiver = state.events.subscribe();
    let stream = async_stream::stream! {
        while let Ok(envelope) = receiver.recv().await {
            yield Ok(Event::default().json_data(envelope).expect("event envelope serializes"));
        }
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

async fn authorize(
    State(state): State<ApiState>,
    headers: HeaderMap,
    request: Request<Body>,
    next: Next,
) -> Result<Response, ApiError> {
    let expected = format!("Bearer {}", state.token);
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
}

async fn health() -> Json<Health> {
    Json(Health {
        status: "ok",
        api_version: 1,
    })
}

#[derive(Debug, Deserialize)]
struct RegisterMediaRequest {
    path: String,
    fingerprint: String,
    title: String,
    kind: MediaKind,
    duration_ms: Option<u64>,
}

async fn register_media(
    State(state): State<ApiState>,
    Json(request): Json<RegisterMediaRequest>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    state
        .services
        .register_media(RegisterMedia {
            path: request.path,
            fingerprint: request.fingerprint,
            title: request.title,
            kind: request.kind,
            duration_ms: request.duration_ms,
        })
        .map(Json)
        .map_err(ApiError::from)
}

async fn read_media(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .services
        .read_media(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("media"))
}

#[derive(Debug, Deserialize)]
struct ImportSubtitleRequest {
    path: String,
    language: Option<String>,
}

async fn import_subtitle(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<ImportSubtitleRequest>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    let content = tokio::fs::read(&request.path).await.map_err(|error| {
        ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_read_error",
            error.to_string(),
            false,
        )
    })?;
    let source_name = std::path::Path::new(&request.path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(&request.path)
        .to_owned();
    state
        .services
        .import_subtitle(ImportSubtitle {
            media_id,
            source_name,
            content,
            language: request.language,
        })
        .map(Json)
        .map_err(ApiError::from)
}

async fn read_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .services
        .read_subtitle_track(&track_id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("subtitle track"))
}

#[derive(Debug, Deserialize)]
struct SubtitleExportQuery {
    format: Option<String>,
}

async fn export_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    Query(query): Query<SubtitleExportQuery>,
) -> Result<Response, ApiError> {
    if query.format.as_deref().unwrap_or("srt") != "srt" {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "unsupported_export_format",
            "only SRT export is supported",
            false,
        ));
    }
    let track = state
        .services
        .read_subtitle_track(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)?
        .ok_or_else(|| ApiError::not_found("subtitle track"))?;
    let mut output = String::new();
    for sentence in track.sentences {
        output.push_str(&format!(
            "{}\n{} --> {}\n{}\n\n",
            sentence.index + 1,
            srt_time(sentence.start.get()),
            srt_time(sentence.end.get()),
            sentence.display_text
        ));
    }
    Ok((
        [(
            axum::http::header::CONTENT_TYPE,
            "application/x-subrip; charset=utf-8",
        )],
        output,
    )
        .into_response())
}

fn srt_time(value: u64) -> String {
    let hours = value / 3_600_000;
    let minutes = value / 60_000 % 60;
    let seconds = value / 1_000 % 60;
    let milliseconds = value % 1_000;
    format!("{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}")
}

async fn transcription_providers(
    State(state): State<ApiState>,
) -> Json<Vec<domain::TranscriptionProviderInfo>> {
    Json(state.transcription.providers())
}

async fn transcription_models(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::TranscriptionModelDescriptor>>, ApiError> {
    state
        .transcription
        .models()
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
struct ModelIdRequest {
    model_id: String,
}

async fn install_transcription_model(
    State(state): State<ApiState>,
    Json(request): Json<ModelIdRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let id =
        domain::TranscriptionModelId::parse(request.model_id).map_err(ApplicationError::from)?;
    let coordinator = state.transcription.clone();
    tokio::spawn(async move {
        let _ = coordinator.install_model(id).await;
    });
    Ok(Json(serde_json::json!({"installation_started": true})))
}

#[derive(Debug, Deserialize)]
struct RegisterCustomModelRequest {
    path: String,
}

async fn register_custom_transcription_model(
    State(state): State<ApiState>,
    Json(request): Json<RegisterCustomModelRequest>,
) -> Result<Json<domain::TranscriptionModelDescriptor>, ApiError> {
    state
        .transcription
        .register_custom_model(request.path)
        .map(Json)
        .map_err(ApiError::from)
}

async fn cancel_transcription_model_install(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<Json<domain::TranscriptionModelDescriptor>, ApiError> {
    state
        .transcription
        .cancel_model_install(
            &domain::TranscriptionModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn delete_transcription_model(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    state
        .transcription
        .delete_model(
            &domain::TranscriptionModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn transcription_jobs(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::TranscriptionJob>>, ApiError> {
    state.transcription.jobs().map(Json).map_err(ApiError::from)
}

async fn create_transcription_job(
    State(state): State<ApiState>,
    Json(request): Json<CreateJobRequest>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .clone()
        .create_job(request)
        .map(Json)
        .map_err(ApiError::from)
}

async fn transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("transcription job"))
}

async fn cancel_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .cancel_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn retry_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .clone()
        .retry_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn read_progress(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<ProgressResponse>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    Ok(Json(ProgressResponse {
        position_ms: state.services.read_progress(&id)?.map(domain::TimeMs::get),
    }))
}

#[derive(Debug, Deserialize)]
struct UpdateProgressRequest {
    position_ms: u64,
}

#[derive(Debug, Serialize)]
struct ProgressResponse {
    position_ms: Option<u64>,
}

async fn update_progress(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<UpdateProgressRequest>,
) -> Result<Json<ProgressResponse>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    let position = state.services.update_progress(&id, request.position_ms)?;
    Ok(Json(ProgressResponse {
        position_ms: Some(position.get()),
    }))
}

#[derive(Debug, Deserialize)]
struct WordQuery {
    language: String,
    lemma: String,
}

#[derive(Debug, Deserialize)]
struct BatchWordRequest {
    language: String,
    lemmas: Vec<String>,
}

async fn read_words(
    State(state): State<ApiState>,
    Json(request): Json<BatchWordRequest>,
) -> Result<Json<Vec<domain::WordProfile>>, ApiError> {
    state
        .services
        .read_word_profiles(&request.language, &request.lemmas)
        .map(Json)
        .map_err(ApiError::from)
}

async fn read_word(
    State(state): State<ApiState>,
    Query(query): Query<WordQuery>,
) -> Result<Json<Option<domain::WordProfile>>, ApiError> {
    state
        .services
        .read_word_profile(&query.language, &query.lemma)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
struct UpdateWordRequest {
    language: String,
    lemma: String,
    display_form: String,
    status: Option<WordStatus>,
    source: Option<SourceRequest>,
}

async fn update_word(
    State(state): State<ApiState>,
    Json(request): Json<UpdateWordRequest>,
) -> Result<Json<domain::WordProfile>, ApiError> {
    let profile = state
        .services
        .update_word_profile(UpdateWordProfile {
            language: request.language,
            lemma: request.lemma,
            display_form: request.display_form,
            status: request.status,
            source: request
                .source
                .map(SourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordProfileChanged,
        serde_json::to_value(&profile).expect("word profile serializes"),
    ));
    Ok(Json(profile))
}

#[derive(Debug, Deserialize)]
struct CreateObservationRequest {
    word_profile_id: String,
    sentence_id: String,
    original_form: String,
    result: Option<ObservationResult>,
    clear: Option<bool>,
    source: Option<SourceRequest>,
}

#[derive(Debug, Deserialize)]
struct SourceRequest {
    language: String,
    normalized_lemma: String,
    media_id: Option<String>,
    sentence_id: Option<String>,
    original_form: String,
    sentence_text: String,
    media_title: String,
    media_fingerprint: String,
    start_ms: u64,
    end_ms: u64,
}

impl SourceRequest {
    fn into_context(self) -> Result<SourceContext, ApplicationError> {
        Ok(SourceContext {
            language: LanguageCode::parse(self.language)?,
            normalized_lemma: self.normalized_lemma,
            media_id: self.media_id.map(MediaId::parse).transpose()?,
            sentence_id: self
                .sentence_id
                .map(SubtitleSentenceId::parse)
                .transpose()?,
            original_form: self.original_form,
            sentence_text: self.sentence_text,
            media_title: self.media_title,
            media_fingerprint: self.media_fingerprint,
            start_ms: self.start_ms,
            end_ms: self.end_ms,
        })
    }
}

async fn create_observation(
    State(state): State<ApiState>,
    Json(request): Json<CreateObservationRequest>,
) -> Result<Response, ApiError> {
    let word_profile_id =
        WordProfileId::parse(request.word_profile_id).map_err(ApplicationError::from)?;
    let sentence_id =
        SubtitleSentenceId::parse(request.sentence_id).map_err(ApplicationError::from)?;
    if request.clear.unwrap_or(false) {
        state
            .services
            .clear_observation(&word_profile_id, &sentence_id)?;
        let _ = state.events.send(EventEnvelope::v1(
            EventName::WordObservationCleared,
            serde_json::json!({
                "word_profile_id": word_profile_id,
                "sentence_id": sentence_id,
            }),
        ));
        return Ok(StatusCode::NO_CONTENT.into_response());
    }
    let observation = state
        .services
        .create_observation(CreateWordObservation {
            word_profile_id,
            sentence_id,
            original_form: request.original_form,
            result: request
                .result
                .ok_or(ApplicationError::Validation("result"))?,
            source: request
                .source
                .map(SourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordObservationCreated,
        serde_json::to_value(&observation).expect("word observation serializes"),
    ));
    Ok(Json(observation).into_response())
}

#[derive(Debug, Deserialize)]
struct VocabularyQuery {
    language: Option<String>,
    status: WordStatus,
    search: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

async fn list_vocabulary(
    State(state): State<ApiState>,
    Query(query): Query<VocabularyQuery>,
) -> Result<Json<Vec<domain::WordDetails>>, ApiError> {
    state
        .services
        .list_vocabulary(
            query.language.as_deref().unwrap_or("en"),
            query.status,
            query.search.as_deref().unwrap_or(""),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn word_details(
    State(state): State<ApiState>,
    Path(profile_id): Path<String>,
) -> Result<Json<domain::WordDetails>, ApiError> {
    let id = WordProfileId::parse(profile_id).map_err(ApplicationError::from)?;
    state
        .services
        .word_details(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("word profile"))
}

#[derive(Debug, Deserialize)]
struct UpdateLearningContentRequest {
    user_definition: Option<String>,
    personal_note: Option<String>,
}

async fn update_learning_content(
    State(state): State<ApiState>,
    Path(profile_id): Path<String>,
    Json(request): Json<UpdateLearningContentRequest>,
) -> Result<Json<domain::WordDetails>, ApiError> {
    state
        .services
        .update_word_learning_content(
            &WordProfileId::parse(profile_id).map_err(ApplicationError::from)?,
            request.user_definition,
            request.personal_note,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn import_external_vocabulary(
    State(state): State<ApiState>,
    Json(request): Json<domain::ExternalVocabularyImport>,
) -> Result<Json<domain::ExternalVocabularyImportSummary>, ApiError> {
    state
        .services
        .import_external_vocabulary(&request)
        .map(Json)
        .map_err(ApiError::from)
}

async fn export_vocabulary(
    State(state): State<ApiState>,
) -> Result<Json<VocabularyAssetBundle>, ApiError> {
    state
        .services
        .export_vocabulary()
        .map(Json)
        .map_err(ApiError::from)
}

async fn import_vocabulary(
    State(state): State<ApiState>,
    Json(bundle): Json<VocabularyAssetBundle>,
) -> Result<Json<serde_json::Value>, ApiError> {
    state.services.import_vocabulary(&bundle)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::VocabularyAssetsImported,
        serde_json::json!({"profiles": bundle.profiles.len()}),
    ));
    Ok(Json(serde_json::json!({"imported": true})))
}

#[derive(Debug, Deserialize)]
struct UpdateAvailabilityRequest {
    availability: MediaAvailability,
}

async fn update_media_availability(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<UpdateAvailabilityRequest>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let media = state
        .services
        .set_media_availability(
            &MediaId::parse(media_id).map_err(ApplicationError::from)?,
            request.availability,
        )
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::MediaAvailabilityChanged,
        serde_json::to_value(&media).expect("media serializes"),
    ));
    Ok(Json(media))
}

#[derive(Debug, Deserialize)]
struct DictionaryQuery {
    language: String,
    lemma: String,
}

async fn dictionary_lookup(
    State(state): State<ApiState>,
    Query(query): Query<DictionaryQuery>,
) -> Result<Json<domain::DictionaryLookupBundle>, ApiError> {
    state
        .services
        .lookup_dictionary(state.dictionaries.as_ref(), &query.language, &query.lemma)
        .await
        .map(Json)
        .map_err(ApiError::from)
}

async fn diagnose_sentence(
    State(state): State<ApiState>,
    Path(sentence_id): Path<String>,
) -> Result<Json<domain::SentenceDiagnosis>, ApiError> {
    let sentence_id = SubtitleSentenceId::parse(sentence_id).map_err(ApplicationError::from)?;
    state
        .services
        .diagnose_sentence(&sentence_id)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Serialize)]
pub struct ErrorBody {
    pub code: &'static str,
    pub message: String,
    pub correlation_id: String,
    pub retryable: bool,
}

pub struct ApiError {
    status: StatusCode,
    body: ErrorBody,
}

impl ApiError {
    fn new(
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
                correlation_id: format!("api-{}", ERROR_SEQUENCE.fetch_add(1, Ordering::Relaxed)),
                retryable,
            },
        }
    }

    fn unauthorized() -> Self {
        Self::new(
            StatusCode::UNAUTHORIZED,
            "unauthorized",
            "invalid local API token",
            false,
        )
    }

    fn not_found(entity: &'static str) -> Self {
        Self::new(
            StatusCode::NOT_FOUND,
            "not_found",
            format!("{entity} was not found"),
            false,
        )
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
            ApplicationError::Domain(error) => Self::new(
                StatusCode::BAD_REQUEST,
                "domain_error",
                error.to_string(),
                false,
            ),
            ApplicationError::Repository(error) => Self::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "repository_error",
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
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        eprintln!(
            "{}",
            serde_json::json!({
                "event": "api.error",
                "status": self.status.as_u16(),
                "code": self.body.code,
                "message": self.body.message,
                "correlation_id": self.body.correlation_id,
                "retryable": self.body.retryable,
            })
        );
        (self.status, Json(self.body)).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
    use persistence_sqlite::SqliteRepository;
    use tower::ServiceExt;

    fn test_app() -> Router {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        router(ApiState::new(
            AppServices::new(
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
            ),
            repo,
            "secret",
        ))
    }

    #[tokio::test]
    async fn health_is_public_and_versioned() {
        let response = test_app()
            .oneshot(Request::get("/v1/health").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn protected_routes_require_token() {
        let response = test_app()
            .oneshot(Request::post("/v1/media").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn media_registration_is_idempotent_over_http() {
        let app = test_app();
        let body = serde_json::json!({
            "path": "/tmp/a.mp4",
            "fingerprint": "abc",
            "title": "A",
            "kind": "video",
            "duration_ms": 1000
        })
        .to_string();
        let request = || {
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(body.clone()))
                .unwrap()
        };
        let first = app.clone().oneshot(request()).await.unwrap();
        assert_eq!(first.status(), StatusCode::OK);
        let first_body = to_bytes(first.into_body(), usize::MAX).await.unwrap();
        let second = app.oneshot(request()).await.unwrap();
        assert_eq!(second.status(), StatusCode::OK);
        let second_body = to_bytes(second.into_body(), usize::MAX).await.unwrap();
        let first: serde_json::Value = serde_json::from_slice(&first_body).unwrap();
        let second: serde_json::Value = serde_json::from_slice(&second_body).unwrap();
        assert_eq!(first["id"], second["id"]);
    }

    #[tokio::test]
    async fn imports_and_reads_complete_subtitle_timeline() {
        let app = test_app();
        let media = serde_json::json!({
            "path": "/tmp/a.mp4",
            "fingerprint": "subtitle-media",
            "title": "A",
            "kind": "video"
        })
        .to_string();
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/media")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(media))
                    .unwrap(),
            )
            .await
            .unwrap();
        let media: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let fixture = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../testdata/subtitles/timeline.srt"
        );
        let request = serde_json::json!({"path": fixture, "language": "en"}).to_string();
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/media/{}/subtitles",
                    media["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(request))
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let track: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(track["sentences"].as_array().unwrap().len(), 4);
        let response = app
            .oneshot(
                Request::get(format!("/v1/subtitles/{}", track["id"].as_str().unwrap()))
                    .header(AUTHORIZATION, "Bearer secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[test]
    fn openapi_lists_implemented_routes() {
        let openapi = include_str!("../../../contracts/openapi/v1.yaml");
        for path in [
            "/v1/health",
            "/v1/media",
            "/v1/media/{media_id}",
            "/v1/media/{media_id}/subtitles",
            "/v1/media/{media_id}/progress",
            "/v1/subtitles/{track_id}",
            "/v1/subtitles/{track_id}/export",
            "/v1/word-profiles",
            "/v1/word-profiles/batch",
            "/v1/word-observations",
            "/v1/vocabulary",
            "/v1/vocabulary/export",
            "/v1/vocabulary/import",
            "/v1/word-profiles/{profile_id}/details",
            "/v1/word-profiles/{profile_id}/learning-content",
            "/v1/vocabulary/import-external",
            "/v1/media/{media_id}/availability",
            "/v1/events",
            "/v1/dictionary",
            "/v1/sentences/{sentence_id}/diagnosis",
            "/v1/transcription/providers",
            "/v1/transcription/models",
            "/v1/transcription/jobs",
        ] {
            assert!(openapi.contains(path), "OpenAPI missing {path}");
        }
    }
}
