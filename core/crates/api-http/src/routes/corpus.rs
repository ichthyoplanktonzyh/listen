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
        .application
        .execute("corpus.reindex", move |services| {
            services.media_analysis().rebuild_corpus_index()
        })
        .await
        .map(|indexed_tracks| Json(CorpusReindexResult { indexed_tracks }))
        .map_err(ApiError::from)
}

/// Local-only corpus retrieval over rebuildable subtitle-derived occurrences.
pub(crate) async fn search_corpus(
    State(state): State<ApiState>,
    Query(query): Query<CorpusSearchQuery>,
) -> Result<Json<Vec<domain::CorpusOccurrence>>, ApiError> {
    let language = query.language.unwrap_or_else(|| "en".to_owned());
    let text = query.query;
    let limit = query.limit.unwrap_or(50);
    let offset = query.offset.unwrap_or(0);
    state
        .application
        .execute("corpus.search", move |services| {
            services
                .media_analysis()
                .search_corpus(&language, &text, limit, offset)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}
