use api_events::{EventEnvelope, EventName};
use application::{
    ApplicationError, CreateLexicalObservation, LexicalSourceContext, UpsertLexicalEntry,
};
use axum::Json;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use domain::{
    LearningResourceDescriptor, LearningResourceId, LearningStatus, LexicalEntry,
    LexicalEntryDetails, LexicalEntryId, LexicalEntryKind, ObservationResult, PhraseCandidate,
    SubtitleSearchResult, SubtitleSentenceId,
};
use serde::Deserialize;

use local_runtime::{
    SubtitleDownloadRequest, SubtitleOperation, SubtitleProviderError, SubtitleSearchRequest,
};

use crate::{ApiError, ApiState};

fn subtitle_provider_api_error(error: SubtitleProviderError) -> ApiError {
    match error {
        SubtitleProviderError::ProviderNotFound => ApiError::not_found("subtitle search provider"),
        SubtitleProviderError::CredentialsRequired => ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_credentials_required",
            "subtitle provider credentials are required",
            false,
        ),
        SubtitleProviderError::QueryRequired => ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_search_query_required",
            "a title, filename, or media hash is required",
            false,
        ),
        SubtitleProviderError::Authentication => ApiError::new(
            StatusCode::UNAUTHORIZED,
            "subtitle_authentication_failed",
            "subtitle provider rejected the configured credentials",
            false,
        ),
        SubtitleProviderError::RateLimited => ApiError::new(
            StatusCode::TOO_MANY_REQUESTS,
            "subtitle_rate_limited",
            "subtitle provider rate limit reached",
            true,
        ),
        SubtitleProviderError::Unavailable(operation) => ApiError::gateway(
            "subtitle_service_unavailable",
            format!("subtitle provider {} is unavailable", operation.wire_name()),
        ),
        SubtitleProviderError::Rejected(operation) => ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_request_rejected",
            format!(
                "subtitle provider rejected the {} request",
                operation.wire_name()
            ),
            false,
        ),
        SubtitleProviderError::Network { operation, detail } => ApiError::gateway(
            match operation {
                SubtitleOperation::Search => "subtitle_search_failed",
                SubtitleOperation::Download => "subtitle_download_failed",
            },
            detail,
        ),
        SubtitleProviderError::MissingDownloadLink => {
            ApiError::gateway("subtitle_download_failed", "missing download link")
        }
    }
}

fn learning_resource_api_error(error: local_runtime::LearningResourceError) -> ApiError {
    match error {
        local_runtime::LearningResourceError::NotFound => ApiError::not_found("learning resource"),
        local_runtime::LearningResourceError::ChecksumMismatch => ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "checksum_mismatch",
            "learning resource checksum mismatch",
            false,
        ),
        local_runtime::LearningResourceError::Download(detail) => {
            ApiError::gateway("resource_download_failed", detail)
        }
        local_runtime::LearningResourceError::Storage(error) => ApiError::from(error),
    }
}

#[derive(Debug, Deserialize)]
pub struct LexicalQuery {
    language: Option<String>,
    kind: Option<LexicalEntryKind>,
    status: Option<LearningStatus>,
    search: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub async fn list_lexical_entries(
    State(state): State<ApiState>,
    Query(query): Query<LexicalQuery>,
) -> Result<Json<Vec<LexicalEntryDetails>>, ApiError> {
    state
        .services
        .list_lexical_entries(
            query.language.as_deref().unwrap_or("en"),
            query.kind,
            query.status,
            query.search.as_deref().unwrap_or(""),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub struct BatchLexicalRequest {
    language: String,
    kind: LexicalEntryKind,
    forms: Vec<String>,
}

pub async fn read_lexical_entries(
    State(state): State<ApiState>,
    Json(request): Json<BatchLexicalRequest>,
) -> Result<Json<Vec<LexicalEntry>>, ApiError> {
    state
        .services
        .read_lexical_entries_by_forms(&request.language, request.kind, &request.forms)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub struct LexicalSourceRequest {
    media_id: Option<String>,
    sentence_id: Option<String>,
    original_form: String,
    sentence_text: String,
    media_title: String,
    media_fingerprint: String,
    start_ms: u64,
    end_ms: u64,
    token_start: Option<u32>,
    token_end: Option<u32>,
}

impl LexicalSourceRequest {
    fn into_context(self) -> Result<LexicalSourceContext, ApplicationError> {
        Ok(LexicalSourceContext {
            media_id: self.media_id.map(domain::MediaId::parse).transpose()?,
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
            token_start: self.token_start,
            token_end: self.token_end,
        })
    }
}

#[derive(Debug, Deserialize)]
pub struct UpsertLexicalRequest {
    language: String,
    kind: LexicalEntryKind,
    canonical_form: String,
    display_form: String,
    status: Option<LearningStatus>,
    user_definition: Option<String>,
    personal_note: Option<String>,
    source: Option<LexicalSourceRequest>,
}

pub async fn upsert_lexical_entry(
    State(state): State<ApiState>,
    Json(request): Json<UpsertLexicalRequest>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let details = state
        .services
        .create_lexical_entry(UpsertLexicalEntry {
            language: request.language,
            kind: request.kind,
            canonical_form: request.canonical_form,
            display_form: request.display_form,
            status: request.status,
            user_definition: request.user_definition,
            personal_note: request.personal_note,
            source: request
                .source
                .map(LexicalSourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::LexicalEntryChanged,
        serde_json::to_value(&details).expect("lexical details serializes"),
    ));
    Ok(Json(details))
}

pub async fn lexical_details(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    state
        .services
        .lexical_details(&LexicalEntryId::parse(id).map_err(ApplicationError::from)?)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("lexical entry"))
}

#[derive(Debug, Deserialize)]
pub struct UpdateLearningContentRequest {
    user_definition: Option<String>,
    personal_note: Option<String>,
}

pub async fn update_lexical_learning_content(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<UpdateLearningContentRequest>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let details = state
        .services
        .update_lexical_learning_content(
            &LexicalEntryId::parse(id).map_err(ApplicationError::from)?,
            request.user_definition,
            request.personal_note,
        )
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::LexicalEntryChanged,
        serde_json::to_value(&details).expect("lexical details serializes"),
    ));
    Ok(Json(details))
}

#[derive(Debug, Deserialize)]
pub struct CreateLexicalObservationRequest {
    lexical_entry_id: String,
    sentence_id: String,
    original_form: String,
    result: Option<ObservationResult>,
    clear: Option<bool>,
    source: Option<LexicalSourceRequest>,
}

pub async fn create_lexical_observation(
    State(state): State<ApiState>,
    Json(request): Json<CreateLexicalObservationRequest>,
) -> Result<Response, ApiError> {
    let lexical_entry_id =
        LexicalEntryId::parse(request.lexical_entry_id).map_err(ApplicationError::from)?;
    let sentence_id =
        SubtitleSentenceId::parse(request.sentence_id).map_err(ApplicationError::from)?;
    if request.clear.unwrap_or(false) {
        state
            .services
            .clear_lexical_observation(&lexical_entry_id, &sentence_id)?;
        let _ = state.events.send(
            crate::event_payloads::LexicalObservationClearedPayload {
                lexical_entry_id: lexical_entry_id.as_str().to_owned(),
                sentence_id: sentence_id.as_str().to_owned(),
            }
            .envelope(),
        );
        return Ok(StatusCode::NO_CONTENT.into_response());
    }
    let observation = state
        .services
        .create_lexical_observation(CreateLexicalObservation {
            lexical_entry_id,
            sentence_id,
            original_form: request.original_form,
            result: request
                .result
                .ok_or(ApplicationError::Validation("result"))?,
            source: request
                .source
                .map(LexicalSourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::LexicalObservationCreated,
        serde_json::to_value(&observation).expect("lexical observation serializes"),
    ));
    Ok(Json(observation).into_response())
}

#[derive(Debug, Deserialize)]
pub struct NormalizeRequest {
    language: String,
    value: String,
}

pub async fn normalize_lexical(
    State(state): State<ApiState>,
    Json(request): Json<NormalizeRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let value = state
        .services
        .normalize_lexical_form(&request.language, &request.value)?;
    Ok(Json(serde_json::json!({
        "original": value.original,
        "normalized": value.normalized,
        "provider": value.provider,
        "version": value.version,
        "user_corrected": value.user_corrected
    })))
}

#[derive(Debug, Deserialize)]
pub struct CorrectLemmaRequest {
    language: String,
    original: String,
    corrected: String,
}

pub async fn correct_lemma(
    State(state): State<ApiState>,
    Json(request): Json<CorrectLemmaRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let value =
        state
            .services
            .correct_lemma(&request.language, &request.original, &request.corrected)?;
    Ok(Json(serde_json::json!({
        "original": value.original,
        "normalized": value.normalized,
        "provider": value.provider,
        "version": value.version,
        "user_corrected": value.user_corrected
    })))
}

pub async fn phrase_candidates(
    State(state): State<ApiState>,
    Path(sentence_id): Path<String>,
) -> Result<Json<Vec<PhraseCandidate>>, ApiError> {
    state
        .services
        .phrase_candidates(&SubtitleSentenceId::parse(sentence_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub async fn resources(State(state): State<ApiState>) -> Json<Vec<LearningResourceDescriptor>> {
    Json(state.learning_resources.list())
}

pub async fn install_resource(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LearningResourceDescriptor>, ApiError> {
    state
        .learning_resources
        .install(&LearningResourceId::parse(id).map_err(ApplicationError::from)?)
        .await
        .map(Json)
        .map_err(learning_resource_api_error)
}

pub async fn remove_resource(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LearningResourceDescriptor>, ApiError> {
    state
        .learning_resources
        .remove(&LearningResourceId::parse(id).map_err(ApplicationError::from)?)
        .await
        .map(Json)
        .map_err(learning_resource_api_error)
}

pub async fn search_subtitles(
    State(state): State<ApiState>,
    Json(request): Json<SubtitleSearchRequest>,
) -> Result<Json<Vec<SubtitleSearchResult>>, ApiError> {
    state
        .subtitle_search
        .search(&request)
        .await
        .map(Json)
        .map_err(subtitle_provider_api_error)
}

pub async fn download_subtitle(
    State(state): State<ApiState>,
    Json(request): Json<SubtitleDownloadRequest>,
) -> Result<Response, ApiError> {
    state
        .subtitle_search
        .download(&request)
        .await
        .map_err(subtitle_provider_api_error)
        .map(|bytes| {
            (
                [(axum::http::header::CONTENT_TYPE, "application/x-subrip")],
                bytes,
            )
                .into_response()
        })
}
