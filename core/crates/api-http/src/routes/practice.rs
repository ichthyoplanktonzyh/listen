use crate::*;
use domain::{RecordingAsset, RecordingAssetId, ShadowingComparison};

#[derive(Debug, Deserialize)]
pub(crate) struct CoachDashboardQuery {
    days: Option<u32>,
}

pub(crate) async fn coach_dashboard(
    State(state): State<ApiState>,
    Query(query): Query<CoachDashboardQuery>,
) -> Result<Json<application::CoachDashboard>, ApiError> {
    state
        .services.media_analysis().coach_dashboard(query.days.unwrap_or(7))
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn graduate_coach_material(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<application::MediaLibraryEntry>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .services.media_analysis().graduate_coach_material(&media_id)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct CoachEvidenceQuery {
    metric: String,
    days: Option<u32>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn coach_evidence(
    State(state): State<ApiState>,
    Query(query): Query<CoachEvidenceQuery>,
) -> Result<Json<Vec<application::CoachEvidenceItem>>, ApiError> {
    state
        .services.media_analysis().coach_evidence(
            &query.metric,
            query.days.unwrap_or(7),
            query.limit.unwrap_or(50),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_practice_session(
    State(state): State<ApiState>,
    Json(request): Json<application::CreatePracticeSession>,
) -> Result<Json<PracticeSession>, ApiError> {
    state
        .services.practice_learning().create_practice_session(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_practice_item(
    State(state): State<ApiState>,
    Json(request): Json<application::CreatePracticeItem>,
) -> Result<Json<PracticeItem>, ApiError> {
    state
        .services.practice_learning().create_practice_item(request)
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
        .services.practice_learning().complete_listening_session(&id, request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_practice_attempt(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitPracticeAttempt>,
) -> Result<Json<PracticeAttempt>, ApiError> {
    state
        .services.practice_learning().submit_practice_attempt(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn practice_attempt(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<PracticeAttempt>, ApiError> {
    let id = PracticeAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .services.practice_learning().practice_attempt(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("practice attempt"))
}

pub(crate) async fn create_recording_asset(
    State(state): State<ApiState>,
    Json(request): Json<application::CreateRecordingAsset>,
) -> Result<Json<RecordingAsset>, ApiError> {
    state
        .services
        .recordings()
        .create_recording_asset(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn recording_asset(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<RecordingAsset>, ApiError> {
    let id = RecordingAssetId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .recordings()
        .recording_asset(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("recording asset"))
}

pub(crate) async fn delete_recording_asset(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<RecordingAsset>, ApiError> {
    let id = RecordingAssetId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .recordings()
        .delete_recording_asset(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("recording asset"))
}

pub(crate) async fn complete_shadowing_attempt(
    State(state): State<ApiState>,
    Json(request): Json<application::CompleteShadowingAttempt>,
) -> Result<Json<PracticeAttempt>, ApiError> {
    state
        .services
        .recordings()
        .complete_shadowing_attempt(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn compare_shadowing(
    State(state): State<ApiState>,
    Json(request): Json<application::CreateShadowingComparison>,
) -> Result<Json<ShadowingComparison>, ApiError> {
    state
        .services
        .recordings()
        .compare_shadowing(request)
        .map(Json)
        .map_err(ApiError::from)
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
        .services.practice_learning().list_listening_inbox_items(
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
        .services.practice_learning().capture_listening_inbox_item(request)
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
        .services.practice_learning().process_listening_inbox_item(&id, request)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct HuntingCandidateQuery {
    status: Option<HuntingCandidateStatus>,
    limit: Option<u32>,
    offset: Option<u32>,
}

pub(crate) async fn list_hunting_candidates(
    State(state): State<ApiState>,
    Query(query): Query<HuntingCandidateQuery>,
) -> Result<Json<Vec<HuntingCandidate>>, ApiError> {
    state
        .services.practice_learning().list_hunting_candidates(
            Some(query.status.unwrap_or(HuntingCandidateStatus::Active)),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
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
    state
        .services.practice_learning().list_hunting_targets(
            Some(query.status.unwrap_or(HuntingTargetStatus::Active)),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_hunting_target(
    State(state): State<ApiState>,
    Json(request): Json<application::CreateHuntingTargetInput>,
) -> Result<Json<HuntingTarget>, ApiError> {
    state
        .services.practice_learning().create_hunting_target(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_hunting_target(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<HuntingTarget>, ApiError> {
    let id = HuntingTargetId::parse(id).map_err(ApplicationError::from)?;
    state
        .services.practice_learning().archive_hunting_target(&id)
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
        .services.practice_learning().hunting_occurrences(&media_id, track_id.as_ref())
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_hunting_check(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitHuntingCheckInput>,
) -> Result<Json<application::HuntingCheckResult>, ApiError> {
    state
        .services.practice_learning().submit_hunting_check(request)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn create_review_item(
    State(state): State<ApiState>,
    Json(request): Json<application::CreateReviewItem>,
) -> Result<Json<ReviewItem>, ApiError> {
    state
        .services.practice_learning().create_review_item(request)
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
        .services.practice_learning().due_review_items(query.at_ms, query.limit.unwrap_or(20))
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn submit_review_attempt(
    State(state): State<ApiState>,
    Json(request): Json<application::SubmitReviewAttempt>,
) -> Result<Json<application::ReviewSubmission>, ApiError> {
    state
        .services.practice_learning().submit_review_attempt(request)
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
        .lexical_learning()
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
        .lexical_learning()
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
        .lexical_learning()
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
        .lexical_learning()
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
        .services.practice_learning().review_item(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("review item"))
}
