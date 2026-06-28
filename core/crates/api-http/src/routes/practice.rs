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
