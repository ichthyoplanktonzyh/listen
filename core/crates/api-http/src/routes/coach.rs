use axum::extract::{Path, Query, State};
use serde::Deserialize;

use crate::{ApiError, ApiState, ApplicationError, Json, MediaId};

#[derive(Debug, Deserialize)]
pub(crate) struct CoachDashboardQuery {
    days: Option<u32>,
}

pub(crate) async fn coach_dashboard(
    State(state): State<ApiState>,
    Query(query): Query<CoachDashboardQuery>,
) -> Result<Json<application::CoachDashboard>, ApiError> {
    let days = query.days.unwrap_or(7);
    state
        .application
        .execute("coach.dashboard", move |services| {
            services.media_analysis().coach_dashboard(days)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn coach_evidence(
    State(state): State<ApiState>,
    Query(query): Query<CoachEvidenceQuery>,
) -> Result<Json<Vec<application::CoachEvidenceItem>>, ApiError> {
    let metric = query.metric;
    let days = query.days.unwrap_or(7);
    let limit = query.limit.unwrap_or(50);
    let offset = query.offset.unwrap_or(0);
    state
        .application
        .execute("coach.evidence", move |services| {
            services
                .media_analysis()
                .coach_evidence(&metric, days, limit, offset)
        })
        .await
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

pub(crate) async fn graduate_coach_material(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<application::MediaLibraryEntry>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("coach.graduate_material", move |services| {
            services.media_analysis().graduate_coach_material(&media_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}
