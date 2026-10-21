//! Core-owned adopted composition deep module (Phase 1 contract 4.0.0).
//!
//! The adopted composition is the single Core-owned composition authority
//! for a Material: this module resolves the current adoption, lists the
//! selected resources and renditions, reads selected resource payloads, and
//! returns media bindings without ever leaking a local path.
//!
//! The App never re-parses a `.listenpkg` to read adopted content: Core
//! parses the carrier inside installation, persists every present payload
//! body and rendition blob atomically, and exposes selected resource content
//! here. A missing or tampered selected body is an honest
//! [`CompositionError::IntegrityFailure`], never a silent fallback to an App
//! cache.

use std::sync::Arc;

use domain::{
    AdoptedComposition, AdoptionCommitPlan, LanguageCode, LearningEditionId, LearningMaterialId,
    MediaId, PackageReleaseId, PackageResourceAvailability, PackageResourceRole,
    PackageReviewStatus, RenditionOrigin,
};

use crate::{ApplicationError, MaterialRepository, MediaRepository, PackageLifecycleRepository};

/// Deterministic Core identity for a package-owned derived audio/video
/// rendition. The identity is derived only from the immutable rendition
/// digest and media type; it is not persisted in package facts or invented by
/// the App.
pub(crate) fn package_derived_media_id(media_digest: &str, media_type: &str) -> MediaId {
    MediaId::from_fingerprint(
        "package-derived-media",
        &format!("{media_digest}:{media_type}"),
    )
}

/// Typed failure semantics of adopted composition reads. Raw repository
/// details never appear in these messages.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CompositionError {
    /// The Material does not exist.
    MaterialNotFound,
    /// The Material has no adopted composition.
    NoAdoptedComposition,
    /// The requested resource/rendition is not selected by the adopted
    /// composition.
    NotSelected,
    /// The adopted selected content is missing or its bytes no longer verify
    /// (tampered digest or size). Never a silent fallback.
    IntegrityFailure,
    /// The durable composition store failed (for example unconfigured).
    StorageFailure,
}

impl std::fmt::Display for CompositionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let message = match self {
            CompositionError::MaterialNotFound => "material was not found",
            CompositionError::NoAdoptedComposition => "material has no adopted composition",
            CompositionError::NotSelected => {
                "resource or rendition is not selected by the adopted composition"
            }
            CompositionError::IntegrityFailure => {
                "adopted composition content is missing or fails integrity verification"
            }
            CompositionError::StorageFailure => "adopted composition store failed",
        };
        f.write_str(message)
    }
}

impl From<CompositionError> for ApplicationError {
    fn from(error: CompositionError) -> Self {
        match error {
            CompositionError::MaterialNotFound => ApplicationError::NotFound("material"),
            CompositionError::NoAdoptedComposition => {
                ApplicationError::NotFound("adopted composition")
            }
            CompositionError::NotSelected => {
                ApplicationError::NotFound("composition resource or rendition")
            }
            CompositionError::IntegrityFailure => ApplicationError::CompositionIntegrity,
            other => ApplicationError::Repository(other.to_string()),
        }
    }
}

/// One learner-facing selected resource of the adopted composition. The
/// digest and size are the exact facts the App can verify a downloaded or
/// cached body against; raw bytes are never embedded in this view.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompositionResourceView {
    pub resource_id: String,
    pub kind: String,
    pub schema: String,
    pub role: PackageResourceRole,
    pub required: bool,
    pub availability: PackageResourceAvailability,
    pub content_language: Option<LanguageCode>,
    pub support_languages: Vec<LanguageCode>,
    pub payload_digest: String,
    pub payload_size_bytes: u64,
    pub review_status: PackageReviewStatus,
}

/// The Media binding behind a rendition, never a local path.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CompositionBinding {
    /// A Source Media Rendition bound to a registered media source.
    Media { media_id: MediaId },
}

/// One selected media rendition of the adopted composition, with its exact
/// blob facts and media binding when a local media item is available.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompositionRenditionView {
    pub rendition_id: String,
    pub kind: String,
    pub origin: RenditionOrigin,
    pub media_type: String,
    /// Lowercase hex SHA-256 of the exact rendition bytes.
    pub digest: String,
    pub byte_size: u64,
    /// Whether the exact blob is durably stored by Core (available without
    /// the source carrier).
    pub blob_available: bool,
    pub binding: Option<CompositionBinding>,
    pub producer_tool_id: Option<String>,
}

/// The resolved adopted composition of one Material.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdoptedCompositionView {
    pub material_id: LearningMaterialId,
    pub material_revision_id: domain::MaterialRevisionId,
    pub release_id: PackageReleaseId,
    pub edition_id: LearningEditionId,
    pub title: String,
    pub target_language: LanguageCode,
    pub support_languages: Vec<LanguageCode>,
    pub adopted_at_ms: u64,
    pub resources: Vec<CompositionResourceView>,
    pub renditions: Vec<CompositionRenditionView>,
}

/// The exact typed content body of one selected resource payload. The
/// digest and size are the verified facts of the body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompositionPayload {
    pub kind: String,
    pub digest: String,
    pub size_bytes: u64,
    /// The exact bytes, re-verified by the repository before return.
    pub bytes: Vec<u8>,
}

/// The Core-owned adopted composition use cases.
#[derive(Clone)]
pub struct CompositionUseCases {
    materials: Arc<dyn MaterialRepository>,
    media: Arc<dyn MediaRepository>,
    package_lifecycle: Arc<dyn PackageLifecycleRepository>,
}

impl CompositionUseCases {
    pub fn new(
        materials: Arc<dyn MaterialRepository>,
        media: Arc<dyn MediaRepository>,
        package_lifecycle: Arc<dyn PackageLifecycleRepository>,
    ) -> Self {
        Self {
            materials,
            media,
            package_lifecycle,
        }
    }

    /// Resolves the Material's current adopted composition, or `None` when
    /// the Material has no adoption. A Material that does not exist is a
    /// [`CompositionError::MaterialNotFound`].
    pub fn resolve(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Option<AdoptedCompositionView>, CompositionError> {
        let material = self
            .materials
            .get_material(material_id)
            .map_err(|_| CompositionError::StorageFailure)?
            .ok_or(CompositionError::MaterialNotFound)?;
        let revision = self
            .materials
            .get_revision(&material.current_revision_id)
            .map_err(|_| CompositionError::StorageFailure)?
            .ok_or(CompositionError::IntegrityFailure)?;
        let plan = self
            .package_lifecycle
            .get_adoption(material_id)
            .map_err(|_| CompositionError::StorageFailure)?;
        let Some(plan) = plan else {
            return Ok(None);
        };
        let installation = self
            .package_lifecycle
            .get_installation(material_id, &plan.release_id)
            .map_err(|_| CompositionError::StorageFailure)?
            .ok_or(CompositionError::IntegrityFailure)?;
        if installation.material_revision_id != revision.id {
            return Err(CompositionError::IntegrityFailure);
        }
        let composition = domain::adopted_composition_for(&installation, &plan);
        Ok(Some(self.view(&plan, &composition)?))
    }

    /// Reads the exact durable payload of one selected resource of the
    /// adopted composition. Missing or tampered bytes are an explicit
    /// [`CompositionError::IntegrityFailure`].
    pub fn read_resource_payload(
        &self,
        material_id: &LearningMaterialId,
        resource_id: &str,
    ) -> Result<CompositionPayload, CompositionError> {
        let (release_id, resource) = self.selected_resource(material_id, resource_id)?;
        let bytes = self
            .package_lifecycle
            .read_resource_payload(material_id, &release_id, resource_id)
            .map_err(|_| CompositionError::IntegrityFailure)?
            .ok_or(CompositionError::IntegrityFailure)?;
        Ok(CompositionPayload {
            kind: resource.kind.clone(),
            digest: resource.payload_digest.clone(),
            size_bytes: resource.payload_size_bytes,
            bytes,
        })
    }

    /// Loads one selected resource of the adopted composition with its
    /// release identity.
    fn selected_resource(
        &self,
        material_id: &LearningMaterialId,
        resource_id: &str,
    ) -> Result<(PackageReleaseId, domain::PackageResourceFact), CompositionError> {
        let (release_id, composition) = self.load_adopted(material_id)?;
        let resource = composition
            .resources
            .into_iter()
            .find(|resource| resource.resource_id == resource_id)
            .ok_or(CompositionError::NotSelected)?;
        Ok((release_id, resource))
    }

    fn load_adopted(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<(PackageReleaseId, AdoptedComposition), CompositionError> {
        let plan = self
            .package_lifecycle
            .get_adoption(material_id)
            .map_err(|_| CompositionError::StorageFailure)?;
        let Some(plan) = plan else {
            return Err(CompositionError::NoAdoptedComposition);
        };
        let installation = self
            .package_lifecycle
            .get_installation(material_id, &plan.release_id)
            .map_err(|_| CompositionError::StorageFailure)?
            .ok_or(CompositionError::IntegrityFailure)?;
        Ok((
            plan.release_id.clone(),
            domain::adopted_composition_for(&installation, &plan),
        ))
    }

    /// Assembles the learner-facing view of the adopted composition. Every
    /// binding is returned without a local path.
    fn view(
        &self,
        plan: &AdoptionCommitPlan,
        composition: &AdoptedComposition,
    ) -> Result<AdoptedCompositionView, CompositionError> {
        let renditions: Vec<CompositionRenditionView> = composition
            .renditions
            .iter()
            .map(
                |rendition| -> Result<CompositionRenditionView, CompositionError> {
                    let binding = match rendition.origin {
                        RenditionOrigin::Derived if rendition.kind == "media" => {
                            self.derived_media_binding(rendition)?
                        }
                        RenditionOrigin::Derived => None,
                        RenditionOrigin::Source if rendition.kind == "media" => rendition
                            .media_id
                            .clone()
                            .map(|media_id| CompositionBinding::Media { media_id }),
                        RenditionOrigin::Source => None,
                    };
                    Ok(CompositionRenditionView {
                        rendition_id: rendition.rendition_id.clone(),
                        kind: rendition.kind.clone(),
                        origin: rendition.origin,
                        media_type: rendition.media_type.clone(),
                        digest: rendition
                            .media_digest
                            .trim_start_matches("sha256:")
                            .to_owned(),
                        byte_size: rendition.media_size_bytes,
                        blob_available: rendition.available,
                        binding,
                        producer_tool_id: rendition
                            .producer
                            .as_ref()
                            .map(|producer| producer.tool_id.clone()),
                    })
                },
            )
            .collect::<Result<_, _>>()?;
        Ok(AdoptedCompositionView {
            material_id: plan.material_id.clone(),
            material_revision_id: plan.material_revision_id.clone(),
            release_id: plan.release_id.clone(),
            edition_id: plan.edition.edition_id.clone(),
            title: plan.edition.title.clone(),
            target_language: plan.edition.target_language.clone(),
            support_languages: plan.edition.support_languages.clone(),
            adopted_at_ms: plan.adopted_at_ms,
            resources: composition
                .resources
                .iter()
                .map(|resource| CompositionResourceView {
                    resource_id: resource.resource_id.clone(),
                    kind: resource.kind.clone(),
                    schema: resource.schema.clone(),
                    role: resource.role,
                    required: resource.required,
                    availability: resource.availability,
                    content_language: resource.content_language.clone(),
                    support_languages: resource.support_languages.clone(),
                    payload_digest: resource.payload_digest.clone(),
                    payload_size_bytes: resource.payload_size_bytes,
                    review_status: resource.review_status,
                })
                .collect(),
            renditions,
        })
    }

    /// Returns the Core-owned binding for a selected package-derived media
    /// rendition only after its deterministic MediaItem has been materialized.
    /// A missing item is represented as an absent binding; storage failures
    /// remain explicit composition failures rather than silently producing an
    /// App-local detached identity.
    fn derived_media_binding(
        &self,
        rendition: &domain::PackageRenditionFact,
    ) -> Result<Option<CompositionBinding>, CompositionError> {
        if !(rendition.media_type.starts_with("audio/")
            || rendition.media_type.starts_with("video/"))
        {
            return Ok(None);
        }
        let media_id = rendition.media_id.clone().unwrap_or_else(|| {
            package_derived_media_id(&rendition.media_digest, &rendition.media_type)
        });
        let exists = self
            .media
            .get(&media_id)
            .map_err(|_| CompositionError::StorageFailure)?
            .is_some();
        Ok(exists.then_some(CompositionBinding::Media { media_id }))
    }
}

/// Application-level error mapping helper for composition failures.
pub fn composition_error(error: CompositionError) -> ApplicationError {
    ApplicationError::from(error)
}
