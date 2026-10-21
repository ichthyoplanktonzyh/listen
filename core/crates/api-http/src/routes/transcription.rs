use crate::{ApiError, ApiState, ApplicationError, Deserialize, Json, Path, Query, State};

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

#[derive(Debug, Deserialize)]
pub(crate) struct ModelIdRequest {
    pub(crate) model_id: String,
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

pub(crate) async fn install_transcription_model(
    State(state): State<ApiState>,
    Json(request): Json<ModelIdRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let id =
        domain::TranscriptionModelId::parse(request.model_id).map_err(ApplicationError::from)?;
    let installation_started = state
        .analysis
        .transcription
        .clone()
        .request_model_install(id)
        .map_err(ApiError::from)?;
    Ok(Json(
        serde_json::json!({"installation_started": installation_started}),
    ))
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
) -> Result<axum::http::StatusCode, ApiError> {
    state
        .analysis
        .transcription
        .delete_model(
            &domain::TranscriptionModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .await?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}

pub(crate) async fn create_recording_transcription(
    State(state): State<ApiState>,
    Json(request): Json<application::CreateRecordingTranscriptionRequest>,
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
