use domain::ReadingPosition;

use crate::{ApiError, ApiState, Deserialize, Json, Path, State};

pub(crate) async fn reading_position(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Option<ReadingPosition>>, ApiError> {
    state
        .services
        .reading()
        .reading_position(&track_id)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct SaveReadingPositionRequest {
    pub media_id: Option<String>,
    pub anchor_cue_id: String,
    pub paragraph_index: u32,
}

pub(crate) async fn save_reading_position(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    Json(request): Json<SaveReadingPositionRequest>,
) -> Result<Json<ReadingPosition>, ApiError> {
    state
        .services
        .reading()
        .save_reading_position(
            &track_id,
            request.media_id.as_deref(),
            &request.anchor_cue_id,
            request.paragraph_index,
        )
        .map(Json)
        .map_err(ApiError::from)
}
