//! Source Identity HTTP surface (contract `4.0.0`).
//!
//! Wire adaptation only: mapping a discovered item's source-scoped canonical
//! key to an exact Material Revision and resolving it back. Feed GUIDs, URLs,
//! enclosure URLs, file hashes, and titles are typed evidence fields in the
//! request and the stored mapping; the canonical key is the only match
//! identity.

use axum::Json;
use axum::extract::{Path, Query, State};
use domain::{
    ContentSourceId, LearningMaterialId, MaterialRevisionId, SourceIdentityMapping,
    SourceItemEvidence, SourceItemId, SourceItemIdentity,
};
use serde::{Deserialize, Serialize};

use crate::{ApiError, ApiState, ApplicationError};

#[derive(Debug, Serialize)]
pub(crate) struct SourceIdentityMappingResponse {
    source_id: String,
    item_id: String,
    evidence: SourceItemEvidenceResponse,
    material_id: String,
    material_revision_id: String,
    mapped_at_ms: u64,
}

#[derive(Debug, Serialize)]
pub(crate) struct SourceItemEvidenceResponse {
    feed_item_id: Option<String>,
    entry_url: Option<String>,
    enclosure_urls: Vec<String>,
    file_sha256: Option<String>,
    title: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct SourceItemEvidenceRequest {
    feed_item_id: Option<String>,
    entry_url: Option<String>,
    enclosure_urls: Option<Vec<String>>,
    file_sha256: Option<String>,
    title: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct RegisterSourceIdentityMappingRequest {
    source_id: String,
    item_id: String,
    evidence: SourceItemEvidenceRequest,
    material_id: String,
    material_revision_id: String,
    mapped_at_ms: u64,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ResolveSourceIdentityQuery {
    source_id: String,
    item_id: String,
}

impl From<SourceIdentityMapping> for SourceIdentityMappingResponse {
    fn from(value: SourceIdentityMapping) -> Self {
        Self {
            source_id: value.source_item.source_id.as_str().to_owned(),
            item_id: value.source_item.item_id.as_str().to_owned(),
            evidence: SourceItemEvidenceResponse {
                feed_item_id: value.evidence.feed_item_id,
                entry_url: value.evidence.entry_url,
                enclosure_urls: value.evidence.enclosure_urls,
                file_sha256: value.evidence.file_sha256,
                title: value.evidence.title,
            },
            material_id: value.material_id.as_str().to_owned(),
            material_revision_id: value.material_revision_id.as_str().to_owned(),
            mapped_at_ms: value.mapped_at_ms,
        }
    }
}

/// POST /v1/source-identities/mappings — record (or update) the mapping of a
/// discovered item's canonical key to an exact Material Revision.
pub(crate) async fn register_source_identity_mapping(
    State(state): State<ApiState>,
    Json(request): Json<RegisterSourceIdentityMappingRequest>,
) -> Result<Json<SourceIdentityMappingResponse>, ApiError> {
    let mapping = SourceIdentityMapping {
        source_item: SourceItemIdentity {
            source_id: ContentSourceId::parse(request.source_id).map_err(ApplicationError::from)?,
            item_id: SourceItemId::parse(request.item_id).map_err(ApplicationError::from)?,
        },
        evidence: SourceItemEvidence {
            feed_item_id: request.evidence.feed_item_id,
            entry_url: request.evidence.entry_url,
            enclosure_urls: request.evidence.enclosure_urls.unwrap_or_default(),
            file_sha256: request.evidence.file_sha256,
            title: request.evidence.title,
        },
        material_id: LearningMaterialId::parse(request.material_id)
            .map_err(ApplicationError::from)?,
        material_revision_id: MaterialRevisionId::parse(request.material_revision_id)
            .map_err(ApplicationError::from)?,
        mapped_at_ms: request.mapped_at_ms,
    };
    state
        .application
        .execute("source_identity.register", move |services| {
            services.source_identity().register(mapping)
        })
        .await
        .map(SourceIdentityMappingResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}

/// GET /v1/source-identities/resolve — resolve a discovered item's canonical
/// key to its recorded mapping, or typed not-found.
pub(crate) async fn resolve_source_identity(
    State(state): State<ApiState>,
    Query(query): Query<ResolveSourceIdentityQuery>,
) -> Result<Json<SourceIdentityMappingResponse>, ApiError> {
    let source_item = SourceItemIdentity {
        source_id: ContentSourceId::parse(query.source_id).map_err(ApplicationError::from)?,
        item_id: SourceItemId::parse(query.item_id).map_err(ApplicationError::from)?,
    };
    state
        .application
        .execute("source_identity.resolve", move |services| {
            services.source_identity().resolve(&source_item)
        })
        .await?
        .map(SourceIdentityMappingResponse::from)
        .map(Json)
        .ok_or_else(|| ApiError::not_found("source identity mapping"))
}

/// GET /v1/source-identities/{source_id}/items/{item_id} — path form of
/// resolve, kept for typed resource navigation.
pub(crate) async fn resolve_source_identity_path(
    State(state): State<ApiState>,
    Path((source_id, item_id)): Path<(String, String)>,
) -> Result<Json<SourceIdentityMappingResponse>, ApiError> {
    let source_item = SourceItemIdentity {
        source_id: ContentSourceId::parse(source_id).map_err(ApplicationError::from)?,
        item_id: SourceItemId::parse(item_id).map_err(ApplicationError::from)?,
    };
    state
        .application
        .execute("source_identity.resolve_path", move |services| {
            services.source_identity().resolve(&source_item)
        })
        .await?
        .map(SourceIdentityMappingResponse::from)
        .map(Json)
        .ok_or_else(|| ApiError::not_found("source identity mapping"))
}
