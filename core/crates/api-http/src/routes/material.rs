//! Learning-material HTTP surface (contract `4.0.0`).
//!
//! This module contains wire adaptation only: typed request DTOs, explicit
//! response DTOs, and handlers that parse path ids and optional language
//! values into typed domain values before delegating every policy decision to
//! [`application::MaterialUseCases`] through `AppServices`. Response
//! components are explicit HTTP DTOs and are never the externally-tagged
//! domain serialization. No material, revision, rendition, or source asset
//! response contains a path; package installation, learning-edition adoption,
//! generation, activation, and filesystem behavior are later intents and are
//! deliberately absent here.

use application::{
    AppendMaterialRevision, CreateLearningMaterial, DocumentRenditionInput, MediaRenditionInput,
    SourceAssetInput,
};
use axum::Json;
use axum::extract::{Path, State};
use domain::{
    LanguageCode, LearningMaterialId, MaterialRevisionId, MediaId, Rendition, RenditionOrigin,
    SourceAssetAvailability, SourceAssetBinding,
};
use serde::{Deserialize, Serialize};

use crate::{ApiError, ApiState, ApplicationError};

#[derive(Debug, Serialize)]
pub(crate) struct MaterialDetailsResponse {
    material: LearningMaterialResponse,
    current_revision: MaterialRevisionResponse,
    shape: &'static str,
}

#[derive(Debug, Serialize)]
pub(crate) struct LearningMaterialResponse {
    id: String,
    current_revision_id: String,
    /// Required but nullable membership evidence: null means Temporary
    /// Material.
    retained_at_ms: Option<u64>,
    created_at_ms: u64,
    updated_at_ms: u64,
}

#[derive(Debug, Serialize)]
pub(crate) struct MaterialRevisionResponse {
    id: String,
    material_id: String,
    title: String,
    source_assets: Vec<SourceAssetResponse>,
    document_renditions: Vec<DocumentRenditionResponse>,
    media_renditions: Vec<MediaRenditionResponse>,
    created_at_ms: u64,
}

#[derive(Debug, Serialize)]
pub(crate) struct SourceAssetResponse {
    id: String,
    media_type: String,
    byte_length: u64,
    sha256_digest: String,
    binding: BindingResponse,
    availability: SourceAssetAvailabilityResponse,
    created_at_ms: u64,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum BindingResponse {
    Managed,
    Referenced { reference: String },
}

#[derive(Debug, Serialize)]
pub(crate) struct SourceAssetAvailabilityResponse {
    state: &'static str,
    reason: Option<&'static str>,
}

#[derive(Debug, Serialize)]
pub(crate) struct DocumentRenditionResponse {
    id: String,
    origin: &'static str,
    media_type: String,
    language: Option<String>,
    text: String,
    text_sha256: String,
    text_byte_size: u64,
    source_asset_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub(crate) struct MediaRenditionResponse {
    id: String,
    origin: &'static str,
    kind: &'static str,
    media_type: String,
    fingerprint: String,
    availability: &'static str,
    media_id: Option<String>,
    media_sha256: Option<String>,
    media_byte_size: Option<u64>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum BindingInputRequest {
    Managed,
    Referenced { reference: String },
}

#[derive(Debug, Deserialize)]
pub(crate) struct SourceAssetInputRequest {
    media_type: String,
    byte_length: u64,
    sha256_digest: String,
    binding: BindingInputRequest,
}

#[derive(Debug, Deserialize)]
pub(crate) struct DocumentRenditionInputRequest {
    media_type: String,
    language: Option<String>,
    text: String,
    source_asset_index: Option<usize>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct MediaRenditionInputRequest {
    media_id: String,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateMaterialRequest {
    title: String,
    source_assets: Vec<SourceAssetInputRequest>,
    document_renditions: Vec<DocumentRenditionInputRequest>,
    media_renditions: Vec<MediaRenditionInputRequest>,
    /// Personal Library membership choice. Omitted (or null) means retained;
    /// explicit false creates Temporary Material.
    retain: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct AppendMaterialRevisionRequest {
    title: String,
    source_assets: Vec<SourceAssetInputRequest>,
    document_renditions: Vec<DocumentRenditionInputRequest>,
    media_renditions: Vec<MediaRenditionInputRequest>,
}

/// PUT body for a Source Asset availability update.
#[derive(Debug, Deserialize)]
pub(crate) struct SourceAssetAvailabilityRequest {
    availability: SourceAssetAvailabilityInput,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "state", rename_all = "snake_case")]
pub(crate) enum SourceAssetAvailabilityInput {
    Available,
    Unavailable { reason: String },
}

impl From<application::MaterialDetails> for MaterialDetailsResponse {
    fn from(value: application::MaterialDetails) -> Self {
        let shape = shape_string(value.shape());
        Self {
            material: LearningMaterialResponse::from(value.material),
            current_revision: MaterialRevisionResponse::from(value.current_revision),
            shape,
        }
    }
}

impl From<domain::LearningMaterial> for LearningMaterialResponse {
    fn from(value: domain::LearningMaterial) -> Self {
        Self {
            id: value.id.as_str().to_owned(),
            current_revision_id: value.current_revision_id.as_str().to_owned(),
            retained_at_ms: value.retained_at_ms,
            created_at_ms: value.created_at_ms,
            updated_at_ms: value.updated_at_ms,
        }
    }
}

impl From<domain::MaterialRevision> for MaterialRevisionResponse {
    fn from(value: domain::MaterialRevision) -> Self {
        let mut document_renditions: Vec<DocumentRenditionResponse> = Vec::new();
        let mut media_renditions: Vec<MediaRenditionResponse> = Vec::new();
        for component in &value.renditions {
            match component {
                Rendition::Document(rendition) => {
                    document_renditions.push(DocumentRenditionResponse::from(rendition))
                }
                Rendition::Media(rendition) => {
                    media_renditions.push(MediaRenditionResponse::from(rendition))
                }
            }
        }
        Self {
            id: value.id.as_str().to_owned(),
            material_id: value.material_id.as_str().to_owned(),
            title: value.title,
            source_assets: value
                .source_assets
                .iter()
                .map(SourceAssetResponse::from)
                .collect(),
            document_renditions,
            media_renditions,
            created_at_ms: value.created_at_ms,
        }
    }
}

impl From<&domain::SourceAsset> for SourceAssetResponse {
    fn from(value: &domain::SourceAsset) -> Self {
        Self {
            id: value.id.as_str().to_owned(),
            media_type: value.media_type.clone(),
            byte_length: value.byte_length,
            sha256_digest: value.sha256_digest.clone(),
            binding: BindingResponse::from(&value.binding),
            availability: SourceAssetAvailabilityResponse::from(&value.availability),
            created_at_ms: value.created_at_ms,
        }
    }
}

impl From<&SourceAssetBinding> for BindingResponse {
    fn from(value: &SourceAssetBinding) -> Self {
        match value {
            SourceAssetBinding::Managed => Self::Managed,
            SourceAssetBinding::Referenced { reference } => Self::Referenced {
                reference: reference.clone(),
            },
        }
    }
}

impl From<&SourceAssetAvailability> for SourceAssetAvailabilityResponse {
    fn from(value: &SourceAssetAvailability) -> Self {
        match value {
            SourceAssetAvailability::Available => Self {
                state: "available",
                reason: None,
            },
            SourceAssetAvailability::Unavailable { reason } => Self {
                state: "unavailable",
                reason: Some(match reason {
                    domain::SourceAssetUnavailableReason::FileMissing => "file_missing",
                    domain::SourceAssetUnavailableReason::IntegrityMismatch => "integrity_mismatch",
                }),
            },
        }
    }
}

impl From<&domain::DocumentRendition> for DocumentRenditionResponse {
    fn from(value: &domain::DocumentRendition) -> Self {
        Self {
            id: value.id.as_str().to_owned(),
            origin: origin_string(value.origin),
            media_type: value.media_type.clone(),
            language: value
                .language
                .as_ref()
                .map(|language| language.as_str().to_owned()),
            text: value.text.clone(),
            text_sha256: value.text_sha256.clone(),
            text_byte_size: value.text_byte_size,
            source_asset_id: value
                .source_asset_id
                .as_ref()
                .map(domain::SourceAssetId::as_str)
                .map(str::to_owned),
        }
    }
}

impl From<&domain::MediaRendition> for MediaRenditionResponse {
    fn from(value: &domain::MediaRendition) -> Self {
        Self {
            id: value.id.as_str().to_owned(),
            origin: origin_string(value.origin),
            kind: media_kind_string(value.kind),
            media_type: value.media_type.clone(),
            fingerprint: value.fingerprint.clone(),
            availability: media_availability_string(value.availability),
            media_id: value
                .media_id
                .as_ref()
                .map(MediaId::as_str)
                .map(str::to_owned),
            media_sha256: value.media_sha256.clone(),
            media_byte_size: value.media_byte_size,
        }
    }
}

fn origin_string(origin: RenditionOrigin) -> &'static str {
    match origin {
        RenditionOrigin::Source => "source",
        RenditionOrigin::Derived => "derived",
    }
}

fn shape_string(shape: domain::MaterialShape) -> &'static str {
    use domain::MaterialShape::{Audio, Mixed, Text, Video};
    match shape {
        Text => "text",
        Audio => "audio",
        Video => "video",
        Mixed => "mixed",
    }
}

fn media_kind_string(kind: domain::MediaKind) -> &'static str {
    use domain::MediaKind::{Audio, Video};
    match kind {
        Video => "video",
        Audio => "audio",
    }
}

fn media_availability_string(availability: domain::MediaAvailability) -> &'static str {
    use domain::MediaAvailability::{Archived, Available, Missing};
    match availability {
        Available => "available",
        Missing => "missing",
        Archived => "archived",
    }
}

/// Converts wire component inputs into typed application inputs, parsing
/// every language tag, media id, and binding into its domain value.
/// Validation and all policy stay in the application layer.
fn component_inputs(
    source_assets: Vec<SourceAssetInputRequest>,
    document_renditions: Vec<DocumentRenditionInputRequest>,
    media_renditions: Vec<MediaRenditionInputRequest>,
) -> Result<
    (
        Vec<SourceAssetInput>,
        Vec<DocumentRenditionInput>,
        Vec<MediaRenditionInput>,
    ),
    ApiError,
> {
    let source_assets = source_assets
        .into_iter()
        .map(|asset| {
            let binding = match asset.binding {
                BindingInputRequest::Managed => SourceAssetBinding::Managed,
                BindingInputRequest::Referenced { reference } => {
                    if reference.trim().is_empty() {
                        return Err(ApiError::new(
                            axum::http::StatusCode::BAD_REQUEST,
                            "invalid_input",
                            "referenced binding requires a reference",
                            false,
                        ));
                    }
                    SourceAssetBinding::Referenced { reference }
                }
            };
            Ok(SourceAssetInput {
                media_type: asset.media_type,
                byte_length: asset.byte_length,
                sha256_digest: asset.sha256_digest,
                binding,
            })
        })
        .collect::<Result<Vec<_>, ApiError>>()?;
    let document_renditions = document_renditions
        .into_iter()
        .map(|rendition| {
            Ok(DocumentRenditionInput {
                media_type: rendition.media_type,
                language: rendition
                    .language
                    .map(LanguageCode::parse)
                    .transpose()
                    .map_err(ApplicationError::from)?,
                text: rendition.text,
                source_asset_index: rendition.source_asset_index,
            })
        })
        .collect::<Result<Vec<_>, ApiError>>()?;
    let media_renditions = media_renditions
        .into_iter()
        .map(|rendition| {
            Ok(MediaRenditionInput {
                media_id: MediaId::parse(rendition.media_id).map_err(ApplicationError::from)?,
            })
        })
        .collect::<Result<Vec<_>, ApiError>>()?;
    Ok((source_assets, document_renditions, media_renditions))
}

fn source_asset_availability(
    request: SourceAssetAvailabilityInput,
) -> Result<SourceAssetAvailability, ApiError> {
    Ok(match request {
        SourceAssetAvailabilityInput::Available => SourceAssetAvailability::Available,
        SourceAssetAvailabilityInput::Unavailable { reason } => {
            let reason = match reason.as_str() {
                "file_missing" => domain::SourceAssetUnavailableReason::FileMissing,
                "integrity_mismatch" => domain::SourceAssetUnavailableReason::IntegrityMismatch,
                _ => {
                    return Err(ApiError::new(
                        axum::http::StatusCode::BAD_REQUEST,
                        "invalid_input",
                        "unavailable reason must be file_missing or integrity_mismatch",
                        false,
                    ));
                }
            };
            SourceAssetAvailability::Unavailable { reason }
        }
    })
}

/// GET /v1/materials — retained Personal Library materials only.
pub(crate) async fn list_learning_materials(
    State(state): State<ApiState>,
) -> Result<Json<Vec<MaterialDetailsResponse>>, ApiError> {
    state
        .application
        .execute("material.list", move |services| {
            services.materials().list_retained()
        })
        .await
        .map(|details| {
            details
                .into_iter()
                .map(MaterialDetailsResponse::from)
                .collect()
        })
        .map(Json)
        .map_err(ApiError::from)
}

/// POST /v1/materials — create (or converge on) a learning material.
pub(crate) async fn create_learning_material(
    State(state): State<ApiState>,
    Json(request): Json<CreateMaterialRequest>,
) -> Result<Json<MaterialDetailsResponse>, ApiError> {
    let (source_assets, document_renditions, media_renditions) = component_inputs(
        request.source_assets,
        request.document_renditions,
        request.media_renditions,
    )?;
    let input = CreateLearningMaterial {
        title: request.title,
        source_assets,
        document_renditions,
        media_renditions,
        retain: request.retain,
    };
    state
        .application
        .execute("material.create", move |services| {
            services.materials().create(input)
        })
        .await
        .map(MaterialDetailsResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}

/// GET /v1/materials/{material_id} — a material with its actual current
/// revision.
pub(crate) async fn read_learning_material(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
) -> Result<Json<MaterialDetailsResponse>, ApiError> {
    let id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("material.read", move |services| {
            services.materials().read(&id)
        })
        .await?
        .map(MaterialDetailsResponse::from)
        .map(Json)
        .ok_or_else(|| ApiError::not_found("material"))
}

/// POST /v1/materials/{material_id}/revisions — append an immutable revision.
pub(crate) async fn append_learning_material_revision(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
    Json(request): Json<AppendMaterialRevisionRequest>,
) -> Result<Json<MaterialDetailsResponse>, ApiError> {
    let id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    let (source_assets, document_renditions, media_renditions) = component_inputs(
        request.source_assets,
        request.document_renditions,
        request.media_renditions,
    )?;
    let input = AppendMaterialRevision {
        title: request.title,
        source_assets,
        document_renditions,
        media_renditions,
    };
    state
        .application
        .execute("material.append_revision", move |services| {
            services.materials().append_revision(&id, input)
        })
        .await
        .map(MaterialDetailsResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}

/// GET /v1/materials/{material_id}/revisions/{revision_id} — one historical
/// or current revision, only when it belongs to the material.
pub(crate) async fn read_learning_material_revision(
    State(state): State<ApiState>,
    Path((material_id, revision_id)): Path<(String, String)>,
) -> Result<Json<MaterialRevisionResponse>, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    let revision_id = MaterialRevisionId::parse(revision_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("material.read_revision", move |services| {
            services
                .materials()
                .read_revision(&material_id, &revision_id)
        })
        .await
        .map(MaterialRevisionResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}

/// PUT /v1/materials/{material_id}/source-assets/{source_asset_id}/availability
/// — update the stored availability fact of one Source Asset. A missing
/// referenced asset is reported unavailable, never deleted.
pub(crate) async fn update_source_asset_availability(
    State(state): State<ApiState>,
    Path((material_id, source_asset_id)): Path<(String, String)>,
    Json(request): Json<SourceAssetAvailabilityRequest>,
) -> Result<Json<MaterialRevisionResponse>, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    let source_asset_id =
        domain::SourceAssetId::parse(source_asset_id).map_err(ApplicationError::from)?;
    let availability = source_asset_availability(request.availability)?;
    state
        .application
        .execute(
            "material.update_source_asset_availability",
            move |services| {
                services.materials().update_source_asset_availability(
                    &material_id,
                    &source_asset_id,
                    availability,
                )
            },
        )
        .await
        .map(MaterialRevisionResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}

/// PUT /v1/materials/{material_id}/library-membership — idempotent retain.
pub(crate) async fn retain_learning_material(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
) -> Result<Json<MaterialDetailsResponse>, ApiError> {
    let id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("material.retain", move |services| {
            services.materials().retain(&id)
        })
        .await
        .map(MaterialDetailsResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}

/// DELETE /v1/materials/{material_id}/library-membership — idempotent
/// unretain that preserves the material, its revisions, media bindings,
/// resources, and learner state.
pub(crate) async fn unretain_learning_material(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
) -> Result<Json<MaterialDetailsResponse>, ApiError> {
    let id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("material.unretain", move |services| {
            services.materials().unretain(&id)
        })
        .await
        .map(MaterialDetailsResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}

/// GET /v1/media/{media_id}/material — resolve the material bound to a media
/// source, or typed not-found.
pub(crate) async fn resolve_learning_material_for_media(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<MaterialDetailsResponse>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("material.resolve_for_media", move |services| {
            services.materials().resolve_for_media(&media_id)
        })
        .await?
        .map(MaterialDetailsResponse::from)
        .map(Json)
        .ok_or_else(|| ApiError::not_found("material"))
}
