use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, HuntingOccurrenceQueryResult, HuntingTarget,
    HuntingTargetId, HuntingTargetStatus, Json, ListeningInboxItem, ListeningInboxItemId,
    ListeningInboxStatus, MediaId, Path, PracticeAttempt, PracticeAttemptId, PracticeItem,
    PracticeSession, PracticeSessionId, Query, ReviewItem, ReviewItemId, State, SubtitleTrackId,
};

pub(crate) async fn create_practice_session(
    State(state): State<ApiState>,
    Json(request): Json<application::CreatePracticeSession>,
) -> Result<Json<PracticeSession>, ApiError> {
    state
        .application
        .execute("practice.create_session", move |services| {
            services
                .practice_learning()
                .create_practice_session(request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_practice_item(
    State(state): State<ApiState>,
    Json(request): Json<application::CreatePracticeItem>,
) -> Result<Json<PracticeItem>, ApiError> {
    state
        .application
        .execute("practice.create_item", move |services| {
            services.practice_learning().create_practice_item(request)
        })
        .await
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
        .application
        .execute("practice.complete_listening", move |services| {
            services
                .practice_learning()
                .complete_listening_session(&id, request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_practice_attempt(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitPracticeAttempt>,
) -> Result<Json<PracticeAttempt>, ApiError> {
    state
        .application
        .execute("practice.submit_attempt", move |services| {
            services
                .practice_learning()
                .submit_practice_attempt(request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn practice_attempt(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<PracticeAttempt>, ApiError> {
    let id = PracticeAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("practice.attempt", move |services| {
            services.practice_learning().practice_attempt(&id)
        })
        .await?
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
    let status = Some(query.status.unwrap_or(ListeningInboxStatus::Active));
    let limit = query.limit.unwrap_or(100);
    let offset = query.offset.unwrap_or(0);
    state
        .application
        .execute("practice.list_inbox", move |services| {
            services
                .practice_learning()
                .list_listening_inbox_items(status, limit, offset)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn capture_listening_inbox_item(
    State(state): State<ApiState>,
    Json(request): Json<application::CaptureListeningInboxItemInput>,
) -> Result<Json<ListeningInboxItem>, ApiError> {
    state
        .application
        .execute("practice.capture_inbox", move |services| {
            services
                .practice_learning()
                .capture_listening_inbox_item(request)
        })
        .await
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
        .application
        .execute("practice.process_inbox", move |services| {
            services
                .practice_learning()
                .process_listening_inbox_item(&id, request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct HuntingTargetQuery {
    status: Option<HuntingTargetStatus>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn list_hunting_targets(
    State(state): State<ApiState>,
    Query(query): Query<HuntingTargetQuery>,
) -> Result<Json<Vec<HuntingTarget>>, ApiError> {
    let status = Some(query.status.unwrap_or(HuntingTargetStatus::Active));
    let limit = query.limit.unwrap_or(100);
    let offset = query.offset.unwrap_or(0);
    state
        .application
        .execute("hunting.list_targets", move |services| {
            services
                .practice_learning()
                .list_hunting_targets(status, limit, offset)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_hunting_target(
    State(state): State<ApiState>,
    Json(request): Json<application::CreateHuntingTargetInput>,
) -> Result<Json<HuntingTarget>, ApiError> {
    state
        .application
        .execute("hunting.create_target", move |services| {
            services.practice_learning().create_hunting_target(request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_hunting_target(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<HuntingTarget>, ApiError> {
    let id = HuntingTargetId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("hunting.archive_target", move |services| {
            services.practice_learning().archive_hunting_target(&id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct HuntingOccurrenceQuery {
    media_id: String,
    track_id: Option<String>,
}

pub(crate) async fn list_hunting_occurrences(
    State(state): State<ApiState>,
    Query(query): Query<HuntingOccurrenceQuery>,
) -> Result<Json<HuntingOccurrenceQueryResult>, ApiError> {
    let media_id = MediaId::parse(query.media_id).map_err(ApplicationError::from)?;
    let track_id = query
        .track_id
        .map(SubtitleTrackId::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    state
        .application
        .execute("hunting.occurrences", move |services| {
            services
                .practice_learning()
                .hunting_occurrences(&media_id, track_id.as_ref())
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_hunting_check(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitHuntingCheckInput>,
) -> Result<Json<application::HuntingCheckResult>, ApiError> {
    state
        .application
        .execute("hunting.submit_check", move |services| {
            services.practice_learning().submit_hunting_check(request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_review_item(
    State(state): State<ApiState>,
    Json(request): Json<application::CreateReviewItem>,
) -> Result<Json<ReviewItem>, ApiError> {
    state
        .application
        .execute("review.create_item", move |services| {
            services.practice_learning().create_review_item(request)
        })
        .await
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
    let at_ms = query.at_ms;
    let limit = query.limit.unwrap_or(20);
    state
        .application
        .execute("review.list_due", move |services| {
            services.practice_learning().due_review_items(at_ms, limit)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn review_queue(
    State(state): State<ApiState>,
    Query(query): Query<ReviewQueueQuery>,
) -> Result<Json<application::ReviewQueue>, ApiError> {
    let at_ms = query.at_ms;
    let limit = query.limit.unwrap_or(20);
    state
        .application
        .execute("review.queue", move |services| {
            services.practice_learning().review_queue(at_ms, limit)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct ReviewOverviewQuery {
    at_ms: Option<u64>,
}

pub(crate) async fn review_deck_overview(
    State(state): State<ApiState>,
    Query(query): Query<ReviewOverviewQuery>,
) -> Result<Json<application::ReviewDeckOverview>, ApiError> {
    state
        .application
        .execute("review.deck_overview", move |services| {
            services
                .practice_learning()
                .review_deck_overview(query.at_ms)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn review_daily_limits(
    State(state): State<ApiState>,
) -> Result<Json<application::ReviewDailyLimits>, ApiError> {
    state
        .application
        .execute("review.daily_limits", move |services| {
            services.practice_learning().review_daily_limits()
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn update_review_daily_limits(
    State(state): State<ApiState>,
    Json(request): Json<application::ReviewDailyLimits>,
) -> Result<Json<application::ReviewDailyLimits>, ApiError> {
    state
        .application
        .execute("review.update_daily_limits", move |services| {
            services
                .practice_learning()
                .update_review_daily_limits(request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn custom_study(
    State(state): State<ApiState>,
    Json(request): Json<application::CustomStudyRequest>,
) -> Result<Json<application::CustomStudyQueue>, ApiError> {
    state
        .application
        .execute("review.custom_study", move |services| {
            services.practice_learning().custom_study(request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_custom_study_attempt(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitCustomStudyAttempt>,
) -> Result<Json<application::ReviewSubmission>, ApiError> {
    state
        .application
        .execute("review.submit_custom_study", move |services| {
            services
                .practice_learning()
                .submit_custom_study_attempt(request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_review_attempt(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitReviewAttempt>,
) -> Result<Json<application::ReviewSubmission>, ApiError> {
    state
        .application
        .execute("review.submit_attempt", move |services| {
            services.practice_learning().submit_review_attempt(request)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct ReviewPreviewQuery {
    at_ms: Option<u64>,
}

pub(crate) async fn review_interval_preview(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Query(query): Query<ReviewPreviewQuery>,
) -> Result<Json<Vec<application::ReviewIntervalPreview>>, ApiError> {
    let id = ReviewItemId::parse(id).map_err(ApplicationError::from)?;
    let at_ms = query.at_ms;
    state
        .application
        .execute("review.interval_preview", move |services| {
            services
                .practice_learning()
                .review_interval_preview(&id, at_ms)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn review_item(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<ReviewItem>, ApiError> {
    let id = ReviewItemId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("review.item", move |services| {
            services.practice_learning().review_item(&id)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("review item"))
}
