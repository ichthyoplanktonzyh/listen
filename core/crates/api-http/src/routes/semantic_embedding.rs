use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use domain::{ProductionChannel, SemanticEmbeddingSourceKind};
use serde::Deserialize;

use crate::{ApiError, ApiState};

#[derive(Debug, Deserialize)]
pub(crate) struct SemanticSearchQuery {
    query: String,
    language: Option<String>,
    source: Option<String>,
    channel: Option<String>,
    limit: Option<u32>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct SemanticGapQuery {
    language: Option<String>,
    channel: Option<String>,
    limit: Option<u32>,
}

pub(crate) async fn capability(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .services
        .semantic_embedding()
        .capability()
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn install(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .semantic_embedding
        .install()
        .await
        .map_err(ApiError::from)?;
    state
        .services
        .semantic_embedding()
        .capability()
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn enable(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state.semantic_embedding.enable().map_err(ApiError::from)?;
    state
        .services
        .semantic_embedding()
        .capability()
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn disable(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state.semantic_embedding.disable();
    state
        .services
        .semantic_embedding()
        .capability()
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn uninstall(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .semantic_embedding
        .uninstall()
        .map_err(ApiError::from)?;
    state
        .services
        .semantic_embedding()
        .delete_index()
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn rebuild(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .services
        .semantic_embedding()
        .rebuild()
        .await
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn search(
    State(state): State<ApiState>,
    Query(query): Query<SemanticSearchQuery>,
) -> Result<Json<domain::SemanticSearchResult>, ApiError> {
    let source = match query.source.as_deref() {
        None | Some("all") => None,
        Some("media_corpus") => Some(SemanticEmbeddingSourceKind::MediaCorpus),
        Some("production_document") => Some(SemanticEmbeddingSourceKind::ProductionDocument),
        Some("production_lexeme") => Some(SemanticEmbeddingSourceKind::ProductionLexeme),
        Some(_) => {
            return Err(bad_request(
                "invalid_source",
                "source must be all, media_corpus, production_document, or production_lexeme",
            ));
        }
    };
    let channel = parse_channel(query.channel.as_deref())?;
    state
        .services
        .semantic_embedding()
        .search(
            &query.query,
            query.language.as_deref(),
            source,
            channel,
            query.limit.unwrap_or(20),
        )
        .await
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn enrich_gap_review(
    State(state): State<ApiState>,
    Query(query): Query<SemanticGapQuery>,
) -> Result<Json<domain::SemanticallyEnrichedProductionGapReview>, ApiError> {
    let channel = parse_channel(query.channel.as_deref())?.unwrap_or(ProductionChannel::Written);
    state
        .services
        .semantic_embedding()
        .enrich_gap_review(
            query.language.as_deref().unwrap_or("en"),
            channel,
            query.limit.unwrap_or(10),
        )
        .await
        .map(Json)
        .map_err(Into::into)
}

fn parse_channel(value: Option<&str>) -> Result<Option<ProductionChannel>, ApiError> {
    match value {
        None | Some("all") => Ok(None),
        Some("written") => Ok(Some(ProductionChannel::Written)),
        Some("spoken") => Ok(Some(ProductionChannel::Spoken)),
        Some(_) => Err(bad_request(
            "invalid_channel",
            "channel must be all, written, or spoken",
        )),
    }
}

fn bad_request(code: &'static str, message: &'static str) -> ApiError {
    ApiError::new(StatusCode::BAD_REQUEST, code, message, false)
}
