use crate::{ApiError, ApiState, CreateSpeechBatchJob, Json, Path, State};

pub(crate) async fn speech_jobs(
    State(state): State<ApiState>,
) -> Result<Json<Vec<local_runtime::SpeechBatchJob>>, ApiError> {
    state
        .analysis
        .speech_jobs
        .list()
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_speech_job(
    State(state): State<ApiState>,
    Json(request): Json<CreateSpeechBatchJob>,
) -> Result<Json<local_runtime::SpeechBatchJob>, ApiError> {
    state
        .analysis
        .speech_jobs
        .clone()
        .create(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn speech_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<local_runtime::SpeechBatchJob>, ApiError> {
    state
        .analysis
        .speech_jobs
        .get(&job_id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("speech batch job"))
}

pub(crate) async fn cancel_speech_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<local_runtime::SpeechBatchJob>, ApiError> {
    state
        .analysis
        .speech_jobs
        .cancel(&job_id)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn retry_speech_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<local_runtime::SpeechBatchJob>, ApiError> {
    state
        .analysis
        .speech_jobs
        .clone()
        .retry(&job_id)
        .map(Json)
        .map_err(ApiError::from)
}
