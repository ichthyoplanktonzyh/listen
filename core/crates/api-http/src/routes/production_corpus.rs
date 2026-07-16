use axum::{
    Json,
    extract::{Query, State},
};
use serde::{Deserialize, Serialize};

use crate::{ApiError, ApiState};

#[derive(Debug, Deserialize)]
pub(crate) struct ProductionCorpusSearchQuery {
    language: Option<String>,
    query: String,
    limit: Option<u32>,
    offset: Option<u32>,
}

#[derive(Debug, Serialize)]
pub(crate) struct ProductionCorpusReindexResult {
    indexed_rubrics: u32,
}

pub(crate) async fn search_production_corpus(
    State(state): State<ApiState>,
    Query(query): Query<ProductionCorpusSearchQuery>,
) -> Result<Json<Vec<domain::ProductionCorpusHit>>, ApiError> {
    state
        .services
        .production_corpus()
        .search_production_corpus(
            query.language.as_deref().unwrap_or("en"),
            &query.query,
            query.limit.unwrap_or(50),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn reindex_production_corpus(
    State(state): State<ApiState>,
) -> Result<Json<ProductionCorpusReindexResult>, ApiError> {
    state
        .services
        .production_corpus()
        .rebuild_production_corpus()
        .map(|indexed_rubrics| Json(ProductionCorpusReindexResult { indexed_rubrics }))
        .map_err(ApiError::from)
}
