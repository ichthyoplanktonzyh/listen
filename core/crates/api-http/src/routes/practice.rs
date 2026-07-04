use crate::*;

pub(crate) async fn create_practice_session(
    State(state): State<ApiState>,
    Json(request): Json<application::CreatePracticeSession>,
) -> Result<Json<PracticeSession>, ApiError> {
    state
        .services
        .create_practice_session(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_practice_item(
    State(state): State<ApiState>,
    Json(request): Json<application::CreatePracticeItem>,
) -> Result<Json<PracticeItem>, ApiError> {
    state
        .services
        .create_practice_item(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn practice_session_summary(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<application::PracticeSessionSummary>, ApiError> {
    let id = PracticeSessionId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .practice_session_summary(&id)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn complete_practice_session(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<application::CompletePracticeSessionInput>,
) -> Result<Json<application::PracticeSessionSummary>, ApiError> {
    let id = PracticeSessionId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .complete_practice_session(&id, request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_practice_attempt(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitPracticeAttempt>,
) -> Result<Json<PracticeAttempt>, ApiError> {
    state
        .services
        .submit_practice_attempt(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn practice_attempt(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<PracticeAttempt>, ApiError> {
    let id = PracticeAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .practice_attempt(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("practice attempt"))
}

pub(crate) async fn mark_stuck_point(
    State(state): State<ApiState>,
    Json(request): Json<application::RecordStuckPointInput>,
) -> Result<Json<LearningEvent>, ApiError> {
    state
        .services
        .mark_stuck_point(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn skip_stuck_point(
    State(state): State<ApiState>,
    Json(request): Json<application::RecordStuckPointInput>,
) -> Result<Json<LearningEvent>, ApiError> {
    state
        .services
        .skip_stuck_point(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn record_diagnosis_view(
    State(state): State<ApiState>,
    Json(request): Json<application::RecordDiagnosisViewInput>,
) -> Result<Json<LearningEvent>, ApiError> {
    state
        .services
        .record_diagnosis_view(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn close_stuck_point(
    State(state): State<ApiState>,
    Json(request): Json<application::CloseStuckPointInput>,
) -> Result<Json<LearningEvent>, ApiError> {
    state
        .services
        .close_stuck_point(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_review_item(
    State(state): State<ApiState>,
    Json(request): Json<application::CreateReviewItem>,
) -> Result<Json<ReviewItem>, ApiError> {
    state
        .services
        .create_review_item(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn review_item(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<ReviewItem>, ApiError> {
    let id = ReviewItemId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .review_item(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("review item"))
}
