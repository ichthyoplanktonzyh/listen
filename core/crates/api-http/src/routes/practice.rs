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

pub(crate) async fn complete_listening_session(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<application::CompleteListeningSessionInput>,
) -> Result<Json<PracticeSession>, ApiError> {
    let id = PracticeSessionId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .complete_listening_session(&id, request)
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

#[derive(Debug, Deserialize)]
pub(crate) struct ListeningInboxQuery {
    status: Option<ListeningInboxStatus>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn list_listening_inbox_items(
    State(state): State<ApiState>,
    Query(query): Query<ListeningInboxQuery>,
) -> Result<Json<Vec<ListeningInboxItem>>, ApiError> {
    state
        .services
        .list_listening_inbox_items(
            Some(query.status.unwrap_or(ListeningInboxStatus::Active)),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn capture_listening_inbox_item(
    State(state): State<ApiState>,
    Json(request): Json<application::CaptureListeningInboxItemInput>,
) -> Result<Json<ListeningInboxItem>, ApiError> {
    state
        .services
        .capture_listening_inbox_item(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn process_listening_inbox_item(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<application::ProcessListeningInboxItemInput>,
) -> Result<Json<ListeningInboxItem>, ApiError> {
    let id = ListeningInboxItemId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .process_listening_inbox_item(&id, request)
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

#[derive(Debug, Deserialize)]
pub(crate) struct ReviewQueueQuery {
    at_ms: Option<u64>,
    limit: Option<u32>,
}

pub(crate) async fn list_due_review_items(
    State(state): State<ApiState>,
    Query(query): Query<ReviewQueueQuery>,
) -> Result<Json<Vec<application::ReviewQueueEntry>>, ApiError> {
    state
        .services
        .due_review_items(query.at_ms, query.limit.unwrap_or(20))
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_review_attempt(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitReviewAttempt>,
) -> Result<Json<application::ReviewSubmission>, ApiError> {
    state
        .services
        .submit_review_attempt(request)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpgradeSuggestionQuery {
    lexical_entry_id: Option<String>,
    status: Option<UpgradeSuggestionStatus>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn list_upgrade_suggestions(
    State(state): State<ApiState>,
    Query(query): Query<UpgradeSuggestionQuery>,
) -> Result<Json<Vec<UpgradeSuggestion>>, ApiError> {
    let lexical_entry_id = query
        .lexical_entry_id
        .map(LexicalEntryId::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    state
        .services
        .upgrade_suggestions(
            lexical_entry_id.as_ref(),
            Some(query.status.unwrap_or(UpgradeSuggestionStatus::Pending)),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpgradeSuggestionHistoryQuery {
    lexical_entry_id: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn upgrade_suggestion_history(
    State(state): State<ApiState>,
    Query(query): Query<UpgradeSuggestionHistoryQuery>,
) -> Result<Json<Vec<UpgradeSuggestion>>, ApiError> {
    let lexical_entry_id = query
        .lexical_entry_id
        .map(LexicalEntryId::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    state
        .services
        .upgrade_suggestions(
            lexical_entry_id.as_ref(),
            None,
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn confirm_upgrade_suggestion(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<UpgradeSuggestion>, ApiError> {
    state
        .services
        .confirm_upgrade_suggestion(
            &UpgradeSuggestionId::parse(id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn reject_upgrade_suggestion(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<UpgradeSuggestion>, ApiError> {
    state
        .services
        .reject_upgrade_suggestion(&UpgradeSuggestionId::parse(id).map_err(ApplicationError::from)?)
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
