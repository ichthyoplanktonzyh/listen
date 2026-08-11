//! Package lifecycle HTTP surface (contract `3.3.0`): Package Installation,
//! Edition Listing, and Learning Edition Adoption.
//!
//! This module contains wire adaptation only: explicit request/response DTOs
//! and handlers that parse path ids into typed domain values before delegating
//! every policy decision to [`application::PackageLifecycleUseCases`] through
//! `AppServices`. The three learner intents stay distinct: installation is
//! candidate-only and never adopts; listing surfaces the installed Editions of
//! the Material's actual current revision; adoption is an explicit, idempotent
//! commit. No response ever exposes a package path, media path, manifest or
//! release JSON, payload bytes, blob path, digest, size, dependency edges,
//! internal persistence facts, or provider/model raw output, and the handler
//! never inspects carriers, reads repositories, builds adoption plans, or
//! changes Material membership itself.

use std::path::PathBuf;

use application::{PackageEditionView, PackageRenditionView, PackageResourceView};
use axum::Json;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use domain::LearningMaterialId;
use serde::{Deserialize, Serialize};

use crate::{ApiError, ApiState, ApplicationError};

/// POST /v1/materials/{material_id}/package-installations — one local Content
/// Package v2 carrier path.
#[derive(Debug, Deserialize)]
pub(crate) struct InstallMaterialPackageRequest {
    /// Local absolute path to a Content Package v2 carrier. Required; the
    /// empty/whitespace string is rejected. The path itself never appears in
    /// any response or public error text.
    pub package_path: String,
}

/// PUT /v1/materials/{material_id}/edition-adoption — the immutable release
/// identity of an installed Package Release.
#[derive(Debug, Deserialize)]
pub(crate) struct AdoptLearningEditionRequest {
    pub release_id: String,
}

/// Learner-facing installed Learning Edition. Contains only facts the learner
/// journey needs: identities, title, languages, timestamps, adoption
/// evidence, and capability availability. Manifests, dependency edges, source
/// paths, payloads, and producer raw output are never exposed.
#[derive(Debug, Serialize)]
pub(crate) struct LearningEditionDetails {
    pub material_id: String,
    pub material_revision_id: String,
    pub edition_id: String,
    pub release_id: String,
    pub title: String,
    pub target_language: String,
    pub support_languages: Vec<String>,
    pub installed_at_ms: u64,
    /// Required but nullable adoption evidence: the original adoption time
    /// when this release is currently adopted, null otherwise.
    pub adopted_at_ms: Option<u64>,
    pub adopted: bool,
    pub resources: Vec<LearningEditionResource>,
    pub renditions: Vec<LearningEditionRendition>,
}

/// One resource-kind capability fact of the installed Edition.
#[derive(Debug, Serialize)]
pub(crate) struct LearningEditionResource {
    pub resource_id: String,
    pub kind: String,
    pub role: &'static str,
    pub required: bool,
    pub availability: &'static str,
    pub review_status: &'static str,
    /// Required but nullable content-language tag.
    pub content_language: Option<String>,
    pub support_languages: Vec<String>,
}

/// One media rendition availability fact of the installed Edition.
#[derive(Debug, Serialize)]
pub(crate) struct LearningEditionRendition {
    pub rendition_id: String,
    pub kind: String,
    pub available: bool,
}

impl From<PackageEditionView> for LearningEditionDetails {
    fn from(value: PackageEditionView) -> Self {
        Self {
            material_id: value.material_id.as_str().to_owned(),
            material_revision_id: value.material_revision_id.as_str().to_owned(),
            edition_id: value.edition_id.as_str().to_owned(),
            release_id: value.release_id.as_str().to_owned(),
            title: value.title,
            target_language: value.target_language.as_str().to_owned(),
            support_languages: value
                .support_languages
                .iter()
                .map(|language| language.as_str().to_owned())
                .collect(),
            installed_at_ms: value.installed_at_ms,
            adopted_at_ms: value.adopted_at_ms,
            adopted: value.adopted,
            resources: value
                .resources
                .into_iter()
                .map(LearningEditionResource::from)
                .collect(),
            renditions: value
                .renditions
                .into_iter()
                .map(LearningEditionRendition::from)
                .collect(),
        }
    }
}

impl From<PackageResourceView> for LearningEditionResource {
    fn from(value: PackageResourceView) -> Self {
        Self {
            resource_id: value.resource_id,
            kind: value.kind,
            role: resource_role_string(value.role),
            required: value.required,
            availability: resource_availability_string(value.availability),
            review_status: review_status_string(value.review_status),
            content_language: value
                .content_language
                .map(|language| language.as_str().to_owned()),
            support_languages: value
                .support_languages
                .iter()
                .map(|language| language.as_str().to_owned())
                .collect(),
        }
    }
}

impl From<PackageRenditionView> for LearningEditionRendition {
    fn from(value: PackageRenditionView) -> Self {
        Self {
            rendition_id: value.rendition_id,
            kind: value.kind,
            available: value.available,
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

/// POST /v1/materials/{material_id}/package-installations — install one local
/// Content Package v2 release for the Material's current revision. Candidate
/// only: the release is validated, prepared, and durably persisted as
/// candidate Learning Resources; nothing is adopted. A fresh install and an
/// equal retry both return 200 with the LearningEditionDetails.
pub(crate) async fn install_material_package(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
    Json(request): Json<InstallMaterialPackageRequest>,
) -> Result<Json<LearningEditionDetails>, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    if request.package_path.trim().is_empty() {
        return Err(package_installation_invalid(
            "package path must not be empty",
        ));
    }
    let package_path = PathBuf::from(request.package_path);
    state
        .application
        .execute("package_lifecycle.install", move |services| {
            services
                .package_lifecycle()
                .install_for_material(&material_id, &package_path)
        })
        .await
        .map(LearningEditionDetails::from)
        .map(Json)
        .map_err(package_installation_error)
}

/// GET /v1/materials/{material_id}/editions — every installed Learning
/// Edition of the Material's actual current revision, ordered by release id
/// with current-adoption evidence.
pub(crate) async fn list_learning_editions(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
) -> Result<Json<Vec<LearningEditionDetails>>, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("package_lifecycle.list_editions", move |services| {
            services.package_lifecycle().list_editions(&material_id)
        })
        .await
        .map(|views| {
            views
                .into_iter()
                .map(LearningEditionDetails::from)
                .collect()
        })
        .map(Json)
        .map_err(package_lifecycle_error)
}

/// PUT /v1/materials/{material_id}/edition-adoption — explicitly adopts one
/// installed Package Release for the Material's current revision. Idempotent:
/// re-adopting the current release preserves the original `adopted_at_ms`.
pub(crate) async fn adopt_learning_edition(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
    Json(request): Json<AdoptLearningEditionRequest>,
) -> Result<Json<LearningEditionDetails>, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    let release_id =
        domain::PackageReleaseId::parse(request.release_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("package_lifecycle.adopt", move |services| {
            services
                .package_lifecycle()
                .adopt_for_material(&material_id, &release_id)
        })
        .await
        .map(LearningEditionDetails::from)
        .map(Json)
        .map_err(package_adoption_error)
}

/// Maps Package Installation failures. Invalid carriers, unreadable or
/// malformed packages, incompatibility, and Material/Revision mismatches are
/// typed 422 `package_installation_invalid` with a stable public message; the
/// application error text (and thus the diagnostic log) carries no package
/// path, payload, manifest, or resource identity.
fn package_installation_error(error: ApplicationError) -> ApiError {
    match error {
        ApplicationError::NotFound(entity) => ApiError::not_found(entity),
        ApplicationError::Invalid(message) => package_installation_invalid(message),
        other => package_lifecycle_failed(other),
    }
}

/// Maps Learning Edition Adoption failures. Unadoptable states — stale
/// revision, missing required resource, broken closure, exclusive ambiguity —
/// are typed 409 `edition_adoption_conflict` with a stable public message; the
/// application error text never exposes resource ids or the internal
/// selection plan. Unknown material or release installation stays a typed
/// 404.
fn package_adoption_error(error: ApplicationError) -> ApiError {
    match error {
        ApplicationError::NotFound(entity) => ApiError::not_found(entity),
        ApplicationError::Invalid(message) => ApiError::internal(
            StatusCode::CONFLICT,
            "edition_adoption_conflict",
            "learning edition cannot be adopted",
            message,
            false,
        ),
        other => package_lifecycle_failed(other),
    }
}

/// Maps shared Package lifecycle repository/internal failures to typed 500
/// `package_lifecycle_failed`; the public message is stable and repository
/// details stay in the diagnostic log.
fn package_lifecycle_error(error: ApplicationError) -> ApiError {
    match error {
        ApplicationError::NotFound(entity) => ApiError::not_found(entity),
        other => package_lifecycle_failed(other),
    }
}

fn package_lifecycle_failed(error: ApplicationError) -> ApiError {
    ApiError::internal(
        StatusCode::INTERNAL_SERVER_ERROR,
        "package_lifecycle_failed",
        "local package lifecycle operation failed",
        error.to_string(),
        true,
    )
}

fn package_installation_invalid(internal_message: impl Into<String>) -> ApiError {
    ApiError::internal(
        StatusCode::UNPROCESSABLE_ENTITY,
        "package_installation_invalid",
        "package release is invalid or incompatible",
        internal_message,
        false,
    )
}
