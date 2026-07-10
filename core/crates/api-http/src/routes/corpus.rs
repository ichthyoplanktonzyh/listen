use axum::{
    Json,
    extract::{Query, State},
};
use serde::{Deserialize, Serialize};

use crate::{ApiError, ApiState};

#[derive(Debug, Deserialize)]
pub(crate) struct CorpusSearchQuery {
    language: Option<String>,
    query: String,
    limit: Option<u32>,
    offset: Option<u32>,
}

#[derive(Debug, Serialize)]
pub(crate) struct CorpusReindexResult {
    indexed_tracks: u32,
}

/// Manual full rebuild of the corpus projection — the recovery entry for
/// subtitle tracks imported before the projection existed (schema < v28) or
/// after any suspected drift; the projection is always safe to regenerate.
pub(crate) async fn reindex_corpus(
    State(state): State<ApiState>,
) -> Result<Json<CorpusReindexResult>, ApiError> {
    state
        .services
        .rebuild_corpus_index()
        .map(|indexed_tracks| Json(CorpusReindexResult { indexed_tracks }))
        .map_err(ApiError::from)
}

/// Local-only corpus retrieval over rebuildable subtitle-derived occurrences.
pub(crate) async fn search_corpus(
    State(state): State<ApiState>,
    Query(query): Query<CorpusSearchQuery>,
) -> Result<Json<Vec<domain::CorpusOccurrence>>, ApiError> {
    state
        .services
        .search_corpus(
            query.language.as_deref().unwrap_or("en"),
            &query.query,
            query.limit.unwrap_or(50),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}
