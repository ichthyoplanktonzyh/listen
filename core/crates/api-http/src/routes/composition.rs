//! Adopted composition HTTP surface (contract `4.0.0`).
//!
//! This module is the single Core-owned composition interface: it resolves
//! the current adopted composition of a Material, lists the selected
//! resources and renditions, and reads typed content — resource payloads and
//! embedded Document/Media Rendition blobs. Wire adaptation only: every
//! policy decision and integrity fact lives in
//! [`application::CompositionUseCases`]. The App never re-parses a
//! `.listenpkg` to read adopted content, and no response ever exposes a local
//! path, manifest, or raw provider output. Missing or tampered selected
//! content is an explicit `composition_integrity_failure`; an unreachable
//! referenced Source Asset is an explicit `source_unavailable`.

use application::{
    AdoptedCompositionView, CompositionBinding, CompositionPayload, CompositionRenditionView,
    CompositionResourceView,
};
use axum::Json;
use axum::extract::{Path, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use domain::LearningMaterialId;
use serde::Serialize;

use crate::{ApiError, ApiState, ApplicationError};

#[derive(Debug, Serialize)]
pub(crate) struct AdoptedCompositionResponse {
    material_id: String,
    material_revision_id: String,
    release_id: String,
    edition_id: String,
    title: String,
    target_language: String,
    support_languages: Vec<String>,
    adopted_at_ms: u64,
    resources: Vec<CompositionResourceResponse>,
    renditions: Vec<CompositionRenditionResponse>,
}

#[derive(Debug, Serialize)]
pub(crate) struct CompositionResourceResponse {
    resource_id: String,
    kind: String,
    schema: String,
    role: &'static str,
    required: bool,
    availability: &'static str,
    content_language: Option<String>,
    support_languages: Vec<String>,
    payload_digest: String,
    payload_size_bytes: u64,
    review_status: &'static str,
}

#[derive(Debug, Serialize)]
pub(crate) struct CompositionRenditionResponse {
    rendition_id: String,
    kind: String,
    origin: &'static str,
    media_type: String,
    language: Option<String>,
    digest: String,
    byte_size: u64,
    blob_available: bool,
    binding: Option<CompositionBindingResponse>,
    producer_tool_id: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum CompositionBindingResponse {
    ManagedSourceAsset {
        source_asset_id: String,
    },
    ReferencedSourceAsset {
        source_asset_id: String,
        reference: String,
        available: bool,
    },
    Media {
        media_id: String,
    },
}

impl From<AdoptedCompositionView> for AdoptedCompositionResponse {
    fn from(value: AdoptedCompositionView) -> Self {
        Self {
            material_id: value.material_id.as_str().to_owned(),
            material_revision_id: value.material_revision_id.as_str().to_owned(),
            release_id: value.release_id.as_str().to_owned(),
            edition_id: value.edition_id.as_str().to_owned(),
            title: value.title,
            target_language: value.target_language.as_str().to_owned(),
            support_languages: value
                .support_languages
                .iter()
                .map(|language| language.as_str().to_owned())
                .collect(),
            adopted_at_ms: value.adopted_at_ms,
            resources: value
                .resources
                .into_iter()
                .map(CompositionResourceResponse::from)
                .collect(),
            renditions: value
                .renditions
                .into_iter()
                .map(CompositionRenditionResponse::from)
                .collect(),
        }
    }
}

impl From<CompositionResourceView> for CompositionResourceResponse {
    fn from(value: CompositionResourceView) -> Self {
        Self {
            resource_id: value.resource_id,
            kind: value.kind,
            schema: value.schema,
            role: resource_role_string(value.role),
            required: value.required,
            availability: resource_availability_string(value.availability),
            content_language: value
                .content_language
                .map(|language| language.as_str().to_owned()),
            support_languages: value
                .support_languages
                .iter()
                .map(|language| language.as_str().to_owned())
                .collect(),
            payload_digest: value.payload_digest,
            payload_size_bytes: value.payload_size_bytes,
            review_status: review_status_string(value.review_status),
        }
    }
}

impl From<CompositionRenditionView> for CompositionRenditionResponse {
    fn from(value: CompositionRenditionView) -> Self {
        Self {
            rendition_id: value.rendition_id,
            kind: value.kind,
            origin: origin_string(value.origin),
            media_type: value.media_type,
            language: value.language.map(|language| language.as_str().to_owned()),
            digest: value.digest,
            byte_size: value.byte_size,
            blob_available: value.blob_available,
            binding: value.binding.map(CompositionBindingResponse::from),
            producer_tool_id: value.producer_tool_id,
        }
    }
}

impl From<CompositionBinding> for CompositionBindingResponse {
    fn from(value: CompositionBinding) -> Self {
        match value {
            CompositionBinding::ManagedSourceAsset { source_asset_id } => {
                Self::ManagedSourceAsset { source_asset_id }
            }
            CompositionBinding::ReferencedSourceAsset {
                source_asset_id,
                reference,
                available,
            } => Self::ReferencedSourceAsset {
                source_asset_id,
                reference,
                available,
            },
            CompositionBinding::Media { media_id } => Self::Media {
                media_id: media_id.as_str().to_owned(),
            },
        }
    }
}

fn resource_role_string(role: domain::PackageResourceRole) -> &'static str {
    use domain::PackageResourceRole::{Assistance, Base};
    match role {
        Base => "base",
        Assistance => "assistance",
    }
}

fn resource_availability_string(availability: domain::PackageResourceAvailability) -> &'static str {
    use domain::PackageResourceAvailability::{Available, Missing, Opaque};
    match availability {
        Available => "available",
        Missing => "missing",
        Opaque => "opaque",
    }
}

fn review_status_string(status: domain::PackageReviewStatus) -> &'static str {
    use domain::PackageReviewStatus::{HumanReviewed, MachineChecked, Unreviewed};
    match status {
        Unreviewed => "unreviewed",
        MachineChecked => "machine_checked",
        HumanReviewed => "human_reviewed",
    }
}

fn origin_string(origin: domain::RenditionOrigin) -> &'static str {
    use domain::RenditionOrigin::{Derived, Source};
    match origin {
        Source => "source",
        Derived => "derived",
    }
}

/// GET /v1/materials/{material_id}/composition — the resolved current adopted
/// composition with every selected resource and rendition and their exact
/// bindings. `not_found` when the Material has no adopted composition.
pub(crate) async fn read_material_composition(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
) -> Result<Json<AdoptedCompositionResponse>, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("composition.resolve", move |services| {
            services
                .composition()
                .resolve(&material_id)
                .map_err(ApplicationError::from)
        })
        .await
        .map_err(composition_error)?
        .map(AdoptedCompositionResponse::from)
        .map(Json)
        .ok_or_else(|| ApiError::not_found("adopted composition"))
}

/// GET /v1/materials/{material_id}/composition/resources/{resource_id}/payload
/// — the exact durable payload bytes of one selected resource of the adopted
/// composition, re-verified by Core. Missing or tampered content is an
/// explicit `composition_integrity_failure`, never a silent fallback.
pub(crate) async fn read_composition_resource_payload(
    State(state): State<ApiState>,
    Path((material_id, resource_id)): Path<(String, String)>,
) -> Result<Response, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("composition.read_resource_payload", move |services| {
            services
                .composition()
                .read_resource_payload(&material_id, &resource_id)
                .map_err(ApplicationError::from)
        })
        .await
        .map(payload_response)
        .map_err(composition_error)
}

/// GET /v1/materials/{material_id}/composition/renditions/{rendition_id}/blob
/// — the exact durable embedded blob of one selected Document/Media Rendition
/// of the adopted composition, re-verified by Core. Missing or tampered
/// content is an explicit `composition_integrity_failure`; an unreachable
/// referenced Source Asset is an explicit `source_unavailable`.
pub(crate) async fn read_composition_rendition_blob(
    State(state): State<ApiState>,
    Path((material_id, rendition_id)): Path<(String, String)>,
) -> Result<Response, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("composition.read_rendition_blob", move |services| {
            services
                .composition()
                .read_rendition_blob(&material_id, &rendition_id)
                .map_err(ApplicationError::from)
        })
        .await
        .map(payload_response)
        .map_err(composition_error)
}

/// The raw typed content body. Resource payloads are JSON documents;
/// Document/Media rendition blobs are raw bytes.
fn payload_response(payload: CompositionPayload) -> Response {
    let content_type = match payload.kind.as_str() {
        "document" | "media" => "application/octet-stream".to_owned(),
        _ => "application/json".to_owned(),
    };
    ([(header::CONTENT_TYPE, content_type)], payload.bytes).into_response()
}

/// Maps composition failures into their stable wire errors. A missing or
/// tampered adopted selection is `composition_integrity_failure` (never a
/// silent fallback); an unreachable referenced Source Asset is
/// `source_unavailable` (never a Material or adoption deletion).
fn composition_error(error: ApplicationError) -> ApiError {
    match error {
        ApplicationError::NotFound(entity) => ApiError::not_found(entity),
        ApplicationError::CompositionIntegrity => ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "composition_integrity_failure",
            "adopted composition content is missing or fails integrity verification",
            false,
        ),
        ApplicationError::SourceUnavailable => ApiError::new(
            StatusCode::BAD_GATEWAY,
            "source_unavailable",
            "a referenced source asset is unavailable",
            true,
        ),
        other => ApiError::internal(
            StatusCode::INTERNAL_SERVER_ERROR,
            "composition_storage_failure",
            "adopted composition store failed",
            other.to_string(),
            false,
        ),
    }
}
