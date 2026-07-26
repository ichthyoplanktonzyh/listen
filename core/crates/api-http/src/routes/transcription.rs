use crate::{
    ApiError, ApiState, ApplicationError, CreateJobRequest, Deserialize, Json, Path, Query, State,
    StatusCode,
};

#[derive(Debug, Deserialize)]
pub(crate) struct PronunciationRulesQuery {
    #[serde(default = "default_language")]
    language: String,
}

fn default_language() -> String {
    "en".into()
}

pub(crate) async fn pronunciation_rules(
    State(state): State<ApiState>,
    Query(query): Query<PronunciationRulesQuery>,
) -> Result<Json<serde_json::Value>, ApiError> {
    state
        .application
        .execute("pronunciation.rules", move |services| {
            Ok(services
                .pronunciation()
                .pronunciation_rules(&query.language))
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn transcription_providers(
    State(state): State<ApiState>,
) -> Json<Vec<domain::TranscriptionProviderInfo>> {
    Json(state.analysis.transcription.providers())
}

pub(crate) async fn transcription_models(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::TranscriptionModelDescriptor>>, ApiError> {
    state
        .analysis
        .transcription
        .models()
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct ModelIdRequest {
    pub(crate) model_id: String,
}

pub(crate) async fn install_transcription_model(
    State(state): State<ApiState>,
    Json(request): Json<ModelIdRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let id =
        domain::TranscriptionModelId::parse(request.model_id).map_err(ApplicationError::from)?;
    let coordinator = state.analysis.transcription.clone();
    tokio::spawn(async move {
        let _ = coordinator.install_model(id).await;
    });
    Ok(Json(serde_json::json!({"installation_started": true})))
}

#[derive(Debug, Deserialize)]
pub(crate) struct RegisterCustomModelRequest {
    pub(crate) path: String,
}

pub(crate) async fn register_custom_transcription_model(
    State(state): State<ApiState>,
    Json(request): Json<RegisterCustomModelRequest>,
) -> Result<Json<domain::TranscriptionModelDescriptor>, ApiError> {
    state
        .analysis
        .transcription
        .register_custom_model(request.path)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn cancel_transcription_model_install(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<Json<domain::TranscriptionModelDescriptor>, ApiError> {
    state
        .analysis
        .transcription
        .cancel_model_install(
            &domain::TranscriptionModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_transcription_model(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    state
        .analysis
        .transcription
        .delete_model(
            &domain::TranscriptionModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn transcription_jobs(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::TranscriptionJob>>, ApiError> {
    state
        .analysis
        .transcription
        .jobs()
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_transcription_job(
    State(state): State<ApiState>,
    Json(request): Json<CreateJobRequest>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .analysis
        .transcription
        .clone()
        .create_job(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .analysis
        .transcription
        .job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("transcription job"))
}

pub(crate) async fn create_recording_transcription(
    State(state): State<ApiState>,
    Json(request): Json<local_runtime::CreateRecordingTranscriptionRequest>,
) -> Result<Json<domain::RecordingTranscriptionJob>, ApiError> {
    state
        .analysis
        .transcription
        .clone()
        .create_recording_transcription(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn recording_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::RecordingTranscriptionJob>, ApiError> {
    state
        .analysis
        .transcription
        .recording_transcription_job(
            &domain::RecordingTranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .ok_or_else(|| ApiError::not_found("recording transcription job"))
}

pub(crate) async fn cancel_recording_transcription(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::RecordingTranscriptionJob>, ApiError> {
    state
        .analysis
        .transcription
        .cancel_recording_transcription(
            &domain::RecordingTranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn cancel_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .analysis
        .transcription
        .cancel_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn retry_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .analysis
        .transcription
        .clone()
        .retry_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .analysis
        .transcription
        .archive_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}
