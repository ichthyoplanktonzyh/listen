use application::{L1SpecialtyOccurrences, LearnerProfileView};

use crate::{ApiError, ApiState, Deserialize, Json, Query, State};

pub(crate) async fn learner_profile(
    State(state): State<ApiState>,
) -> Result<Json<LearnerProfileView>, ApiError> {
    state
        .application
        .execute("learner.profile", move |services| {
            services.learner_profile().learner_profile_view()
        })
        .await
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
    let difficulty_kind = query.difficulty_kind;
    let language = query.language;
    let track_id = query.track_id;
    let limit = query.limit.unwrap_or(30);
    state
        .application
        .execute("learner.l1_specialty", move |services| {
            services.media_analysis().l1_specialty_occurrences(
                &difficulty_kind,
                &language,
                track_id.as_deref(),
                limit,
            )
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn update_learner_profile(
    State(state): State<ApiState>,
    Json(request): Json<UpdateLearnerProfileRequest>,
) -> Result<Json<LearnerProfileView>, ApiError> {
    let l1_language = request.l1_language;
    let ui_language = request.ui_language;
    state
        .application
        .execute("learner.update_profile", move |services| {
            services
                .learner_profile()
                .set_learner_l1(l1_language.as_deref(), ui_language.as_deref())
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}
