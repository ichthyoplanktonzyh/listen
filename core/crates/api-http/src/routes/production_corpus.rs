use axum::{
    Json,
    extract::{Query, State},
    http::StatusCode,
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

#[derive(Debug, Deserialize)]
pub(crate) struct ProductionGapQuery {
    language: Option<String>,
    channel: Option<String>,
    limit: Option<u32>,
}

pub(crate) async fn production_gap_review(
    State(state): State<ApiState>,
    Query(query): Query<ProductionGapQuery>,
) -> Result<Json<domain::ProductionGapReview>, ApiError> {
    let channel = match query.channel.as_deref().unwrap_or("written") {
        "written" => domain::ProductionChannel::Written,
        "spoken" => domain::ProductionChannel::Spoken,
        _ => {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "invalid_channel",
                "channel must be written or spoken",
                false,
            ));
        }
    };
    state
        .services
        .production_corpus()
        .production_gap_review(
            query.language.as_deref().unwrap_or("en"),
            channel,
            query.limit.unwrap_or(10),
        )
        .map(Json)
        .map_err(ApiError::from)
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
