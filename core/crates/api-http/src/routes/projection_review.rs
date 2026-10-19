use axum::{
    Json,
    extract::{Path, Query, State},
};
use domain::{
    CrossModalReviewCandidate, LanguageCode, LexicalEntryId, ProjectionAudit,
    ProjectionDecisionKind, ProjectionProposal, ProjectionProposalId,
};
use serde::Deserialize;

use crate::{ApiError, ApiState};

fn domain_id<T>(value: Result<T, domain::DomainError>) -> Result<T, ApiError> {
    value
        .map_err(application::ApplicationError::from)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct DecisionRequest {
    decision: ProjectionDecisionKind,
    note: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct LanguageQuery {
    language: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct GapQuery {
    language: String,
    limit: Option<u32>,
}

pub(crate) async fn audit_projection(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<ProjectionAudit>, ApiError> {
    let id = domain_id(LexicalEntryId::parse(id))?;
    state
        .application
        .execute("projection.audit", move |services| {
            services.projection_review().audit_and_refresh(&id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn list_projection_proposals(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<ProjectionProposal>>, ApiError> {
    let id = domain_id(LexicalEntryId::parse(id))?;
    state
        .application
        .execute("projection.list", move |services| {
            services.projection_review().proposals(&id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn decide_projection(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<DecisionRequest>,
) -> Result<Json<ProjectionProposal>, ApiError> {
    let id = domain_id(ProjectionProposalId::parse(id))?;
    state
        .application
        .execute("projection.decide", move |services| {
            services
                .projection_review()
                .decide(&id, request.decision, request.note)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn rebuild_projections(
    State(state): State<ApiState>,
    Query(query): Query<LanguageQuery>,
) -> Result<Json<Vec<ProjectionAudit>>, ApiError> {
    let language = domain_id(LanguageCode::parse(query.language))?;
    state
        .application
        .execute("projection.rebuild", move |services| {
            services.projection_review().rebuild_language(&language)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn cross_modal_gaps(
    State(state): State<ApiState>,
    Query(query): Query<GapQuery>,
) -> Result<Json<Vec<CrossModalReviewCandidate>>, ApiError> {
    let language = domain_id(LanguageCode::parse(query.language))?;
    let limit = query.limit.unwrap_or(50).clamp(1, 200);
    state
        .application
        .execute("projection.cross_modal_gaps", move |services| {
            services
                .projection_review()
                .cross_modal_gaps(&language, limit)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}
