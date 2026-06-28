use crate::*;

pub(crate) async fn read_progress(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<ProgressResponse>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    Ok(Json(ProgressResponse {
        position_ms: state.services.read_progress(&id)?.map(domain::TimeMs::get),
    }))
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpdateProgressRequest {
    position_ms: u64,
}

#[derive(Debug, Serialize)]
pub(crate) struct ProgressResponse {
    position_ms: Option<u64>,
}

pub(crate) async fn update_progress(
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
pub(crate) struct VocabularyQuery {
    language: Option<String>,
    status: LearningStatus,
    search: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn list_vocabulary(
    State(state): State<ApiState>,
    Query(query): Query<VocabularyQuery>,
) -> Result<Json<Vec<domain::LexicalEntryDetails>>, ApiError> {
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

pub(crate) async fn import_external_vocabulary(
    State(state): State<ApiState>,
    Json(request): Json<domain::ExternalVocabularyImport>,
) -> Result<Json<domain::ExternalVocabularyImportSummary>, ApiError> {
    state
        .services
        .import_external_vocabulary(&request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn export_vocabulary(
    State(state): State<ApiState>,
) -> Result<Json<VocabularyAssetBundle>, ApiError> {
    state
        .services
        .export_vocabulary()
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn import_vocabulary(
    State(state): State<ApiState>,
    Json(bundle): Json<VocabularyAssetBundle>,
) -> Result<Json<serde_json::Value>, ApiError> {
    state.services.import_vocabulary(&bundle)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::VocabularyAssetsImported,
        serde_json::json!({"lexical_entries": bundle.lexical_entries.len()}),
    ));
    Ok(Json(serde_json::json!({"imported": true})))
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpdateAvailabilityRequest {
    availability: MediaAvailability,
}

pub(crate) async fn update_media_availability(
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
