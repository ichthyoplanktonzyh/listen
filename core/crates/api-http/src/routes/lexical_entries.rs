use api_events::{EventEnvelope, EventName};
use application::{
    ApplicationError, CreateLexicalObservation, LexicalSourceContext, UpsertLexicalEntry,
};
use axum::Json;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use domain::{
    LearningStatus, LexicalEntry, LexicalEntryDetails, LexicalEntryId, LexicalEntryKind,
    ObservationResult, PhraseCandidate, SubtitleSentenceId,
};
use serde::Deserialize;

use crate::{ApiError, ApiState};

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
    let language = query.language.unwrap_or_else(|| "en".to_owned());
    let search = query.search.unwrap_or_default();
    let kind = query.kind;
    let status = query.status;
    let limit = query.limit.unwrap_or(100);
    let offset = query.offset.unwrap_or(0);
    state
        .application
        .execute("lexical.list", move |services| {
            services
                .lexical_learning()
                .list_lexical_entries(&language, kind, status, &search, limit, offset)
        })
        .await
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
    let language = request.language;
    let kind = request.kind;
    let forms = request.forms;
    state
        .application
        .execute("lexical.read_batch", move |services| {
            services
                .lexical_learning()
                .read_lexical_entries_by_forms(&language, kind, &forms)
        })
        .await
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
    let input = UpsertLexicalEntry {
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
    };
    let details = state
        .application
        .execute("lexical.upsert", move |services| {
            services.lexical_learning().create_lexical_entry(input)
        })
        .await
        .map_err(ApiError::from)?;
    let _ = state.infrastructure.events.send(EventEnvelope::v1(
        EventName::LexicalEntryChanged,
        serde_json::to_value(&details).expect("lexical details serializes"),
    ));
    Ok(Json(details))
}

pub async fn lexical_details(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LexicalEntryDetails>, ApiError> {
    let id = LexicalEntryId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("lexical.details", move |services| {
            services.lexical_learning().lexical_details(&id)
        })
        .await?
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
    let id = LexicalEntryId::parse(id).map_err(ApplicationError::from)?;
    let details = state
        .application
        .execute("lexical.update_content", move |services| {
            services.lexical_learning().update_lexical_learning_content(
                &id,
                request.user_definition,
                request.personal_note,
            )
        })
        .await
        .map_err(ApiError::from)?;
    let _ = state.infrastructure.events.send(EventEnvelope::v1(
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
            .application
            .execute("lexical.clear_observation", {
                let lexical_entry_id = lexical_entry_id.clone();
                let sentence_id = sentence_id.clone();
                move |services| {
                    services
                        .lexical_learning()
                        .clear_lexical_observation(&lexical_entry_id, &sentence_id)
                }
            })
            .await?;
        let _ = state.infrastructure.events.send(
            crate::event_payloads::LexicalObservationClearedPayload {
                lexical_entry_id: lexical_entry_id.as_str().to_owned(),
                sentence_id: sentence_id.as_str().to_owned(),
            }
            .envelope(),
        );
        return Ok(StatusCode::NO_CONTENT.into_response());
    }
    let input = CreateLexicalObservation {
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
    };
    let observation = state
        .application
        .execute("lexical.create_observation", move |services| {
            services
                .lexical_learning()
                .create_lexical_observation(input)
        })
        .await
        .map_err(ApiError::from)?;
    let _ = state.infrastructure.events.send(EventEnvelope::v1(
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
    let language = request.language;
    let input = request.value;
    let value = state
        .application
        .execute("lexical.normalize", move |services| {
            services
                .lexical_learning()
                .normalize_lexical_form(&language, &input)
        })
        .await?;
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
    let value = state
        .application
        .execute("lexical.correct_lemma", move |services| {
            services.lexical_learning().correct_lemma(
                &request.language,
                &request.original,
                &request.corrected,
            )
        })
        .await?;
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
    let sentence_id = SubtitleSentenceId::parse(sentence_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("lexical.phrase_candidates", move |services| {
            services.lexical_learning().phrase_candidates(&sentence_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}
