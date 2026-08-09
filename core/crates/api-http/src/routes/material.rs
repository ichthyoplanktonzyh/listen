//! Learning-material HTTP surface (contract `3.2.0`).
//!
//! This module contains wire adaptation only: typed request DTOs, explicit
//! response DTOs, and handlers that parse path ids and optional language
//! values into typed domain values before delegating every policy decision to
//! [`application::MaterialUseCases`] through `AppServices`. Response assets
//! are explicit HTTP DTOs (flat `asset_type` discriminator) and are never the
//! externally-tagged domain [`domain::MaterialAsset`] serialization. No
//! material, revision, or asset response contains a path; package
//! installation, learning-edition adoption, generation, activation, and
//! filesystem behavior are later intents and are deliberately absent here.

use application::{AppendMaterialRevision, CreateLearningMaterial, MaterialAssetInput};
use axum::Json;
use axum::extract::{Path, State};
use domain::{LanguageCode, LearningMaterialId, MaterialAsset, MaterialRevisionId, MediaId};
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
    assets: Vec<MaterialAssetResponse>,
    created_at_ms: u64,
}

/// Explicit wire shape for material assets. The `asset_type` discriminator is
/// flat (`{"asset_type": "document_text", ...}`), unlike the domain
/// externally-tagged serialization, and no variant carries a path.
#[derive(Debug, Serialize)]
#[serde(tag = "asset_type", rename_all = "snake_case")]
pub(crate) enum MaterialAssetResponse {
    DocumentText {
        id: String,
        text: String,
        sha256_digest: String,
        byte_size: u64,
        language: Option<String>,
    },
    MediaRendition {
        id: String,
        media_id: String,
        media_kind: String,
        fingerprint: String,
        availability: String,
    },
}

#[derive(Debug, Deserialize)]
#[serde(tag = "asset_type", rename_all = "snake_case")]
pub(crate) enum MaterialAssetInputRequest {
    DocumentText {
        text: String,
        language: Option<String>,
    },
    MediaRendition {
        media_id: String,
    },
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateMaterialRequest {
    title: String,
    assets: Vec<MaterialAssetInputRequest>,
    /// Personal Library membership choice. Omitted (or null) means retained;
    /// explicit false creates Temporary Material.
    retain: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct AppendMaterialRevisionRequest {
    title: String,
    assets: Vec<MaterialAssetInputRequest>,
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
        Self {
            id: value.id.as_str().to_owned(),
            material_id: value.material_id.as_str().to_owned(),
            title: value.title,
            assets: value
                .assets
                .iter()
                .map(MaterialAssetResponse::from)
                .collect(),
            created_at_ms: value.created_at_ms,
        }
    }
}

impl From<&domain::MaterialAsset> for MaterialAssetResponse {
    fn from(value: &domain::MaterialAsset) -> Self {
        match value {
            MaterialAsset::DocumentText(asset) => Self::DocumentText {
                id: asset.id.as_str().to_owned(),
                text: asset.text.clone(),
                sha256_digest: asset.sha256_digest.clone(),
                byte_size: asset.byte_size,
                language: asset
                    .language
                    .as_ref()
                    .map(|language| language.as_str().to_owned()),
            },
            MaterialAsset::MediaRendition(asset) => Self::MediaRendition {
                id: asset.id.as_str().to_owned(),
                media_id: asset.media_id.as_str().to_owned(),
                media_kind: media_kind_string(asset.kind).to_owned(),
                fingerprint: asset.fingerprint.clone(),
                availability: media_availability_string(asset.availability).to_owned(),
            },
        }
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

/// Converts wire asset inputs into typed application inputs, parsing every
/// language tag and media id into its domain value. Validation and all
/// policy stay in the application layer.
fn material_asset_inputs(
    assets: Vec<MaterialAssetInputRequest>,
) -> Result<Vec<MaterialAssetInput>, ApiError> {
    let mut inputs = Vec::with_capacity(assets.len());
    for asset in assets {
        inputs.push(match asset {
            MaterialAssetInputRequest::DocumentText { text, language } => {
                MaterialAssetInput::DocumentText {
                    text,
                    language: language
                        .map(LanguageCode::parse)
                        .transpose()
                        .map_err(ApplicationError::from)?,
                }
            }
            MaterialAssetInputRequest::MediaRendition { media_id } => {
                MaterialAssetInput::MediaRendition {
                    media_id: MediaId::parse(media_id).map_err(ApplicationError::from)?,
                }
            }
        });
    }
    Ok(inputs)
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
    let input = CreateLearningMaterial {
        title: request.title,
        assets: material_asset_inputs(request.assets)?,
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
    let input = AppendMaterialRevision {
        title: request.title,
        assets: material_asset_inputs(request.assets)?,
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
