use axum::Json;
use axum::extract::{Query, State};
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
    let language = query.language.unwrap_or_else(|| "en".to_owned());
    let text = query.query;
    let limit = query.limit.unwrap_or(50);
    let offset = query.offset.unwrap_or(0);
    state
        .application
        .execute("production_corpus.search", move |services| {
            services
                .production_corpus()
                .search_production_corpus(&language, &text, limit, offset)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn reindex_production_corpus(
    State(state): State<ApiState>,
) -> Result<Json<ProductionCorpusReindexResult>, ApiError> {
    state
        .application
        .execute("production_corpus.reindex", move |services| {
            services.production_corpus().rebuild_production_corpus()
        })
        .await
        .map(|indexed_rubrics| Json(ProductionCorpusReindexResult { indexed_rubrics }))
        .map_err(ApiError::from)
}
