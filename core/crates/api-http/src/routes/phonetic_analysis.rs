use super::transcription::{ModelIdRequest, RegisterCustomModelRequest};
use crate::*;

pub(crate) async fn phonetic_analysis_providers(
    State(state): State<ApiState>,
) -> Json<Vec<domain::PhoneticAnalysisProviderInfo>> {
    Json(state.phonetic_analysis.providers())
}

pub(crate) async fn phonetic_analysis_models(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::PhoneticAnalysisModelDescriptor>>, ApiError> {
    state
        .phonetic_analysis
        .models()
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn install_phonetic_analysis_model(
    State(state): State<ApiState>,
    Json(request): Json<ModelIdRequest>,
) -> Result<Json<domain::PhoneticAnalysisModelDescriptor>, ApiError> {
    let id =
        domain::PhoneticAnalysisModelId::parse(request.model_id).map_err(ApplicationError::from)?;
    let model = state
        .phonetic_analysis
        .models()?
        .into_iter()
        .find(|m| m.id == id)
        .ok_or(ApplicationError::NotFound("phonetic analysis model"))?;
    if !model.distribution_allowed || !model.application_verified {
        return Err(ApiError::from(ApplicationError::Conflict(
            "phonetic analysis model is not approved for installation",
        )));
    }
    if model.state == domain::PhoneticModelState::Installing {
        return Ok(Json(model));
    }
    let coordinator = state.phonetic_analysis.clone();
    tokio::spawn(async move {
        let _ = coordinator.install_model(id).await;
    });
    let updated = state
        .phonetic_analysis
        .models()?
        .into_iter()
        .find(|m| m.id == model.id)
        .unwrap_or(model);
    Ok(Json(updated))
}

pub(crate) async fn register_custom_phonetic_analysis_model(
    State(state): State<ApiState>,
    Json(request): Json<RegisterCustomModelRequest>,
) -> Result<Json<domain::PhoneticAnalysisModelDescriptor>, ApiError> {
    state
        .phonetic_analysis
        .register_custom_model(request.path)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn cancel_phonetic_analysis_model_install(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<Json<domain::PhoneticAnalysisModelDescriptor>, ApiError> {
    state
        .phonetic_analysis
        .cancel_model_install(
            &domain::PhoneticAnalysisModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_phonetic_analysis_model(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    state.phonetic_analysis.delete_model(
        &domain::PhoneticAnalysisModelId::parse(model_id).map_err(ApplicationError::from)?,
    )?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn phonetic_analysis_jobs(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::PhoneticAnalysisJob>>, ApiError> {
    state
        .phonetic_analysis
        .jobs()
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_phonetic_analysis_job(
    State(state): State<ApiState>,
    Json(request): Json<CreatePhoneticJobRequest>,
) -> Result<Json<domain::PhoneticAnalysisJob>, ApiError> {
    state
        .phonetic_analysis
        .clone()
        .create_job(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn phonetic_analysis_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::PhoneticAnalysisJob>, ApiError> {
    state
        .phonetic_analysis
        .job(&domain::PhoneticAnalysisJobId::parse(job_id).map_err(ApplicationError::from)?)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("phonetic analysis job"))
}

pub(crate) async fn cancel_phonetic_analysis_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::PhoneticAnalysisJob>, ApiError> {
    state
        .phonetic_analysis
        .cancel_job(&domain::PhoneticAnalysisJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_phonetic_analysis_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    state.phonetic_analysis.delete_job(
        &domain::PhoneticAnalysisJobId::parse(job_id).map_err(ApplicationError::from)?,
    )?;
    Ok(StatusCode::NO_CONTENT)
}

pub(crate) async fn clear_terminal_phonetic_analysis_jobs(
    State(state): State<ApiState>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let deleted = state.phonetic_analysis.clear_terminal_jobs()?;
    Ok(Json(serde_json::json!({ "deleted": deleted })))
}

pub(crate) async fn retry_phonetic_analysis_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::PhoneticAnalysisJob>, ApiError> {
    state
        .phonetic_analysis
        .clone()
        .retry_job(&domain::PhoneticAnalysisJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_phonetic_analyses(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::PhoneticAnalysis>>, ApiError> {
    state
        .phonetic_analysis
        .analyses(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn phonetic_analysis_findings(
    State(state): State<ApiState>,
    Path(analysis_id): Path<String>,
) -> Result<Json<Vec<domain::PhoneticFinding>>, ApiError> {
    state
        .phonetic_analysis
        .analysis(&domain::PhoneticAnalysisId::parse(analysis_id).map_err(ApplicationError::from)?)?
        .map(|analysis| Json(analysis.findings))
        .ok_or_else(|| ApiError::not_found("phonetic analysis"))
}

#[derive(Debug, Deserialize)]
pub(crate) struct PhoneticFindingFeedbackRequest {
    value: domain::PhoneticFindingFeedbackValue,
    note: Option<String>,
}

pub(crate) async fn update_phonetic_finding_feedback(
    State(state): State<ApiState>,
    Path(finding_id): Path<String>,
    Json(request): Json<PhoneticFindingFeedbackRequest>,
) -> Result<Json<domain::PhoneticFindingFeedback>, ApiError> {
    let feedback = domain::PhoneticFindingFeedback {
        finding_id: local_runtime::finding_id(finding_id)?,
        value: request.value,
        note: request.note,
        updated_at_ms: application::now_ms(),
    };
    let feedback = state.phonetic_analysis.save_feedback(&feedback)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PhoneticAnalysisFeedbackChanged,
        serde_json::to_value(&feedback).expect("phonetic feedback serializes"),
    ));
    Ok(Json(feedback))
}
