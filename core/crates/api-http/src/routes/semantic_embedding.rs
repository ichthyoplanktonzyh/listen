use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
};
use domain::SemanticEmbeddingSourceKind;
use serde::Deserialize;

use crate::{ApiError, ApiState};

#[derive(Debug, Deserialize)]
pub(crate) struct SemanticSearchQuery {
    query: String,
    language: Option<String>,
    source: Option<String>,
    limit: Option<u32>,
}

pub(crate) async fn capability(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .application
        .execute("semantic_embedding.capability", move |services| {
            services.semantic_embedding().capability()
        })
        .await
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn install(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .generative
        .semantic_embedding
        .install()
        .await
        .map_err(ApiError::from)?;
    state
        .application
        .execute(
            "semantic_embedding.capability_after_install",
            move |services| services.semantic_embedding().capability(),
        )
        .await
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn enable(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .generative
        .semantic_embedding
        .enable()
        .map_err(ApiError::from)?;
    state
        .application
        .execute(
            "semantic_embedding.capability_after_enable",
            move |services| services.semantic_embedding().capability(),
        )
        .await
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn disable(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state.generative.semantic_embedding.disable();
    state
        .application
        .execute(
            "semantic_embedding.capability_after_disable",
            move |services| services.semantic_embedding().capability(),
        )
        .await
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn uninstall(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .generative
        .semantic_embedding
        .uninstall()
        .map_err(ApiError::from)?;
    state
        .application
        .execute("semantic_embedding.uninstall_index", move |services| {
            services.semantic_embedding().delete_index()
        })
        .await
        .map(Json)
        .map_err(Into::into)
}

pub(crate) async fn rebuild(
    State(state): State<ApiState>,
) -> Result<Json<domain::SemanticEmbeddingCapability>, ApiError> {
    state
        .application
        .execute_async("semantic_embedding.rebuild", move |services| async move {
            services.semantic_embedding().rebuild().await
        })
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
        Some(_) => {
            return Err(bad_request(
                "invalid_source",
                "source must be all or media_corpus",
            ));
        }
    };
    let text = query.query;
    let language = query.language;
    let limit = query.limit.unwrap_or(20);
    state
        .application
        .execute_async("semantic_embedding.search", move |services| async move {
            services
                .semantic_embedding()
                .search(&text, language.as_deref(), source, limit)
                .await
        })
        .await
        .map(Json)
        .map_err(Into::into)
}

fn bad_request(code: &'static str, message: &'static str) -> ApiError {
    ApiError::new(StatusCode::BAD_REQUEST, code, message, false)
}
