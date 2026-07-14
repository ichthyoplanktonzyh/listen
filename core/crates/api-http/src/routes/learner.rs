use application::{L1SpecialtyOccurrences, LearnerProfileView};

use crate::*;

pub(crate) async fn learner_profile(
    State(state): State<ApiState>,
) -> Result<Json<LearnerProfileView>, ApiError> {
    state
        .services
        .learner_profile()
        .learner_profile_view()
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpdateLearnerProfileRequest {
    /// `null`/absent clears the L1 setting.
    pub l1_language: Option<String>,
    /// Optional client UI-language snapshot; authority stays client-side.
    pub ui_language: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct L1SpecialtyQuery {
    difficulty_kind: String,
    language: String,
    track_id: Option<String>,
    limit: Option<u32>,
}

pub(crate) async fn l1_specialty_occurrences(
    State(state): State<ApiState>,
    Query(query): Query<L1SpecialtyQuery>,
) -> Result<Json<L1SpecialtyOccurrences>, ApiError> {
    state
        .services
        .l1_specialty_occurrences(
            &query.difficulty_kind,
            &query.language,
            query.track_id.as_deref(),
            query.limit.unwrap_or(30),
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn update_learner_profile(
    State(state): State<ApiState>,
    Json(request): Json<UpdateLearnerProfileRequest>,
) -> Result<Json<LearnerProfileView>, ApiError> {
    state
        .services
        .learner_profile()
        .set_learner_l1(
            request.l1_language.as_deref(),
            request.ui_language.as_deref(),
        )
        .map(Json)
        .map_err(ApiError::from)
}
