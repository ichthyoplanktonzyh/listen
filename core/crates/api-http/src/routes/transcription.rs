use crate::*;

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
) -> Json<serde_json::Value> {
    Json(state.services.pronunciation_rules(&query.language))
}

pub(crate) async fn transcription_providers(
    State(state): State<ApiState>,
) -> Json<Vec<domain::TranscriptionProviderInfo>> {
    Json(state.transcription.providers())
}

pub(crate) async fn transcription_models(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::TranscriptionModelDescriptor>>, ApiError> {
    state
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
    let coordinator = state.transcription.clone();
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
    state.transcription.jobs().map(Json).map_err(ApiError::from)
}

pub(crate) async fn create_transcription_job(
    State(state): State<ApiState>,
    Json(request): Json<CreateJobRequest>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
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
        .transcription
        .job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("transcription job"))
}

pub(crate) async fn cancel_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
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
        .transcription
        .archive_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}
