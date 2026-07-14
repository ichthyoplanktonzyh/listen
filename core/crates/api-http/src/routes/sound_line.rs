use crate::*;

pub(crate) async fn sound_line_jobs(
    State(state): State<ApiState>,
) -> Result<Json<Vec<local_runtime::SoundLineJob>>, ApiError> {
    state.sound_line.list().map(Json).map_err(ApiError::from)
}

pub(crate) async fn create_sound_line_job(
    State(state): State<ApiState>,
    Json(request): Json<CreateSoundLineJob>,
) -> Result<Json<local_runtime::SoundLineJob>, ApiError> {
    state
        .sound_line
        .clone()
        .create(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn sound_line_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<local_runtime::SoundLineJob>, ApiError> {
    state
        .sound_line
        .get(&job_id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("sound line job"))
}

pub(crate) async fn cancel_sound_line_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<local_runtime::SoundLineJob>, ApiError> {
    state
        .sound_line
        .cancel(&job_id)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn retry_sound_line_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<local_runtime::SoundLineJob>, ApiError> {
    state
        .sound_line
        .clone()
        .retry(&job_id)
        .map(Json)
        .map_err(ApiError::from)
}
