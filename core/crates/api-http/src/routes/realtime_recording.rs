use crate::{ApiError, ApiState, ApplicationError, Json, Path, State};

pub(crate) async fn create_recording_asset(
    State(state): State<ApiState>,
    Json(input): Json<application::CreateRecordingAsset>,
) -> Result<Json<domain::RecordingAsset>, ApiError> {
    state
        .application
        .execute("realtime.recording.create", move |services| {
            services.recordings().create_recording_asset(input)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_recording_asset(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<axum::http::StatusCode, ApiError> {
    let id = domain::RecordingAssetId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("realtime.recording.delete", move |services| {
            services.recordings().delete_recording_asset(&id)
        })
        .await?
        .ok_or_else(|| ApiError::not_found("recording asset"))?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}
