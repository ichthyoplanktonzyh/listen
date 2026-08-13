//! Package lifecycle use cases: Package Installation and Learning Edition
//! Adoption.
//!
//! This deep module exposes exactly three learner-intent operations:
//!
//! - [`PackageLifecycleUseCases::install_for_material`]: installs one local
//!   Content Package v2 release for an existing Learning Material. Candidate
//!   only: it validates the release against the Material's current revision,
//!   prepares the immutable installation facts together with the exact
//!   validated payload bytes of every present resource, and persists both
//!   durably as one atomic unit, but never adopts an Edition or changes any
//!   active selection.
//! - [`PackageLifecycleUseCases::list_editions`]: lists the installed
//!   Learning Edition candidates for the Material's current revision with
//!   adoption evidence.
//! - [`PackageLifecycleUseCases::adopt_for_material`]: explicitly adopts one
//!   installed release for the Material's current revision as one
//!   deterministic, dependency-closed commit. Adoption may assume every
//!   selected `Available` resource has durable stored payload backing.
//!
//! The v2 inspection, Installation Plan interpretation, dependency closure,
//! candidate classification, compatibility checks, coherent-selection
//! resolution, idempotency, and repository coordination are all hidden behind
//! this interface. The repository seam ([`PackageLifecycleRepository`]) must
//! persist the prepared installation facts together with every durable
//! payload body in one atomic operation and must commit the adoption and all
//! supported active-selection changes as one atomic unit; callers never
//! coordinate individual resource writes.

use std::collections::{HashMap, HashSet};
use std::path::Path;
use std::sync::Arc;

use content_package::v2::{PlanResource, ResourceDisposition, ResourceRole, ReviewStatus};
use content_package::v3::{
    PlanDocumentRendition, PlanMediaRendition, V3Error, V3Inspection, V3InstallationPlan,
    inspect_v3_path, installation_plan_v3,
};
use domain::{
    AdoptionCommitPlan, DocumentRendition, LanguageCode, LearningEdition, LearningMaterial,
    LearningMaterialId, MaterialRevision, MaterialRevisionId, MediaAvailability, MediaId,
    MediaKind, MediaRendition, PackageInstallation, PackageLifecycleError, PackageReleaseId,
    PackageRenditionFact, PackageResourceAvailability, PackageResourceFact,
    PackageResourceProvenance, PackageResourceRole, PackageReviewStatus, Rendition,
    RenditionOrigin, adoption_commit_plan,
};

use crate::{ApplicationError, MaterialRepository, now_ms};

/// The application-owned prepared installation input handed to the
/// persistence seam: the path-free [`PackageInstallation`] domain facts plus
/// the exact validated raw payload bytes of every present known and present
/// opaque resource. The repository must make facts and payloads durable
/// together in one atomic operation so an accepted installation never depends
/// on the source carrier. Raw bytes never enter domain entities or
/// learner-facing views.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedPackageInstallation {
    pub installation: PackageInstallation,
    /// Every present payload body, sorted by resource id. Missing resources
    /// have no entry and remain explicitly unavailable.
    pub payloads: Vec<PreparedResourcePayload>,
}

/// One exact validated payload body with the identity, schema, digest, and
/// size facts that let the repository verify the association with its
/// resource fact and durably store the body.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PreparedResourcePayload {
    pub resource_id: String,
    pub kind: String,
    pub schema: String,
    pub digest: String,
    pub size_bytes: u64,
    /// The exact raw bytes, verified against `digest` and `size_bytes` by the
    /// v2 inspection.
    pub bytes: Vec<u8>,
}

/// The persistence contract for durable package lifecycle state.
///
/// An adapter must persist a prepared installation — the immutable facts and
/// every durable payload body — as one atomic operation with
/// [`PackageLifecycleRepository::save_installation`], return the equal
/// existing installation idempotently, and commit an adoption with all
/// supported active-selection changes together in
/// [`PackageLifecycleRepository::commit_adoption`]: a failed commit must
/// preserve the previous adoption and selections.
pub trait PackageLifecycleRepository: Send + Sync {
    /// Atomically persists a prepared installation: the immutable facts and
    /// every durable payload body together. Success means facts and payloads
    /// are durable together; failure leaves no partial installation.
    ///
    /// An equal retry for the same `(material_id, release_id)` — identical
    /// immutable release facts and identical payload bytes — returns the
    /// equal existing installation without rewriting it and preserves the
    /// original installation timestamp (`installed_at_ms` is stamped by the
    /// adapter at first persist, so it is excluded from the equality). The
    /// same identity with unequal facts or bytes fails closed and changes
    /// nothing.
    fn save_installation(
        &self,
        prepared: &PreparedPackageInstallation,
    ) -> Result<PackageInstallation, ApplicationError>;

    /// Loads the installation of `release_id` for `material_id`, if any.
    fn get_installation(
        &self,
        material_id: &LearningMaterialId,
        release_id: &PackageReleaseId,
    ) -> Result<Option<PackageInstallation>, ApplicationError>;

    /// Lists every installed release for `material_id`, ordered by release
    /// id. Installations of any revision are returned; the use case filters
    /// to the Material's current revision.
    fn list_installations(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Vec<PackageInstallation>, ApplicationError>;

    /// Loads the Material's current adoption commit, if any.
    fn get_adoption(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Option<AdoptionCommitPlan>, ApplicationError>;

    /// Atomically commits the adoption and all supported active-selection
    /// changes carried by the plan.
    ///
    /// A first adoption writes the plan as one atomic unit. A switch to
    /// another installed release atomically replaces any previous adoption
    /// with the new plan. A same-release re-adopt must compare the complete
    /// stored [`AdoptionCommitPlan`] against the candidate, ignoring only the
    /// `adopted_at_ms` on both sides: when the stored plan is equal, the
    /// existing adoption is returned unchanged — the original
    /// `adopted_at_ms` is preserved and nothing is rewritten — and when any
    /// fact other than `adopted_at_ms` differs, the commit fails closed,
    /// preserving the previous adoption and selections without repairing the
    /// stored row.
    ///
    /// A returned `Err` guarantees the previous adoption and selections are
    /// preserved.
    ///
    /// Every selected `Available` resource may be assumed to have durable
    /// stored payload backing from its `save_installation`; if that invariant
    /// is violated the commit must fail atomically.
    fn commit_adoption(
        &self,
        commit: &AdoptionCommitPlan,
    ) -> Result<AdoptionCommitPlan, ApplicationError>;
}

/// Without configured persistence every package lifecycle operation errors
/// with the same not-configured message, so an unconfigured `AppServices`
/// can never silently accept or drop package state.
pub(crate) struct DisabledPackageLifecycleRepository;

impl PackageLifecycleRepository for DisabledPackageLifecycleRepository {
    fn save_installation(
        &self,
        _prepared: &PreparedPackageInstallation,
    ) -> Result<PackageInstallation, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_installation(
        &self,
        _material_id: &LearningMaterialId,
        _release_id: &PackageReleaseId,
    ) -> Result<Option<PackageInstallation>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_installations(
        &self,
        _material_id: &LearningMaterialId,
    ) -> Result<Vec<PackageInstallation>, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_adoption(
        &self,
        _material_id: &LearningMaterialId,
    ) -> Result<Option<AdoptionCommitPlan>, ApplicationError> {
        Err(Self::disabled())
    }

    fn commit_adoption(
        &self,
        _commit: &AdoptionCommitPlan,
    ) -> Result<AdoptionCommitPlan, ApplicationError> {
        Err(Self::disabled())
    }
}

impl DisabledPackageLifecycleRepository {
    fn disabled() -> ApplicationError {
        ApplicationError::Repository("package lifecycle repository is not configured".into())
    }
}

/// One resource-kind availability fact of an installed Edition, honest about
/// missing and opaque status.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageResourceView {
    pub resource_id: String,
    pub kind: String,
    pub role: PackageResourceRole,
    pub required: bool,
    pub availability: PackageResourceAvailability,
    pub review_status: PackageReviewStatus,
    pub content_language: Option<LanguageCode>,
    pub support_languages: Vec<LanguageCode>,
}

/// One media rendition availability fact of an installed Edition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageRenditionView {
    pub rendition_id: String,
    pub kind: String,
    pub available: bool,
}

/// A learner-facing installed Learning Edition view. Contains only necessary
/// facts: identities, title, languages, timestamps, current-adoption
/// evidence, and capability availability. Manifests, dependency edges, source
/// paths, and payloads are never exposed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageEditionView {
    pub material_id: LearningMaterialId,
    pub material_revision_id: MaterialRevisionId,
    pub edition_id: domain::LearningEditionId,
    pub release_id: PackageReleaseId,
    pub title: String,
    pub target_language: LanguageCode,
    pub support_languages: Vec<LanguageCode>,
    pub installed_at_ms: u64,
    /// When the release is currently adopted: the original adoption time.
    pub adopted_at_ms: Option<u64>,
    pub adopted: bool,
    pub resources: Vec<PackageResourceView>,
    pub renditions: Vec<PackageRenditionView>,
}

/// The deep package lifecycle use case module. Construct through
/// [`PackageLifecycleUseCases::new`] or `AppServices::package_lifecycle()`.
#[derive(Clone)]
pub struct PackageLifecycleUseCases {
    materials: Arc<dyn MaterialRepository>,
    package_lifecycle: Arc<dyn PackageLifecycleRepository>,
}

impl PackageLifecycleUseCases {
    pub fn new(
        materials: Arc<dyn MaterialRepository>,
        package_lifecycle: Arc<dyn PackageLifecycleRepository>,
    ) -> Self {
        Self {
            materials,
            package_lifecycle,
        }
    }

    /// Installs one local Content Package release for an existing Learning
    /// Material. Both the v2 and the v3 release schema are supported; the
    /// declared schema of the carrier selects the inspection.
    ///
    /// The carrier's `material_id` and `material_revision_id` must equal the
    /// Material's identity and current revision exactly. Declared media
    /// renditions must match a bound Material media asset by kind and
    /// normalized SHA-256 fingerprint, a document-text base resource must
    /// agree with the matching Material text asset, and every required known
    /// resource payload and its dependency closure must be available.
    /// Ambiguous bindings fail rather than guess.
    ///
    /// Installation is candidate-only: the Material's membership, revision,
    /// adoption, and active selections are never changed. The exact validated
    /// payload bytes of every present resource are prepared together with the
    /// facts and durably persisted by the repository in one atomic operation,
    /// so an accepted installation stays backed after the source carrier is
    /// deleted. The returned view carries no source path, blob path,
    /// manifest, payload, or learner media path. A fresh installation is
    /// never adopted; reinstalling an already adopted equal release reports
    /// its existing adoption evidence unchanged.
    pub fn install_for_material(
        &self,
        material_id: &LearningMaterialId,
        package_path: &Path,
    ) -> Result<PackageEditionView, ApplicationError> {
        let material = self
            .materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let current_revision = self.current_revision(&material)?;
        let inspection = inspect_v3_path(package_path).map_err(map_v3_inspection_error)?;
        let plan = installation_plan_v3(&inspection);
        let prepared =
            self.prepare_v3_installation(&material, &current_revision, &inspection, &plan)?;
        let persisted = self.package_lifecycle.save_installation(&prepared)?;
        let adoption = self.package_lifecycle.get_adoption(material_id)?;
        let adopted = adoption
            .as_ref()
            .filter(|plan| plan.release_id == persisted.release_id);
        Ok(edition_view(persisted, adopted))
    }

    /// Lists the installed Learning Edition candidates for the Material's
    /// current revision, ordered by release id, with current-adoption
    /// evidence. The actual current revision is loaded and ownership-verified
    /// before any installation is filtered: a missing or cross-material
    /// pointer fails closed instead of being trusted from the Material row.
    pub fn list_editions(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Vec<PackageEditionView>, ApplicationError> {
        let material = self
            .materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let current_revision = self.current_revision(&material)?;
        let installations = self.package_lifecycle.list_installations(material_id)?;
        let adoption = self.package_lifecycle.get_adoption(material_id)?;
        let mut views = Vec::new();
        for installation in installations {
            if installation.material_revision_id != current_revision.id {
                continue;
            }
            let adopted = adoption
                .as_ref()
                .filter(|plan| plan.release_id == installation.release_id);
            views.push(edition_view(installation, adopted));
        }
        views.sort_by(|a, b| a.release_id.as_str().cmp(b.release_id.as_str()));
        Ok(views)
    }

    /// Explicitly adopts one installed Package Release for the Material's
    /// current revision.
    ///
    /// The actual current revision is loaded and ownership-verified before any
    /// plan is generated or committed: a missing or cross-material pointer
    /// fails closed without touching the adoption, and the release must be
    /// installed for the verified revision. Adoption resolves one coherent,
    /// dependency-closed commit plan from the immutable installed facts and
    /// always commits it through the repository seam; the seam owns the
    /// idempotent retry (an equal same-release re-adopt returns the existing
    /// adoption and preserves its original timestamp) and the atomic
    /// replacement on a release switch, so a stored row that no longer
    /// matches the deterministic plan fails closed instead of being silently
    /// repaired. A failed commit leaves the previous adoption intact.
    pub fn adopt_for_material(
        &self,
        material_id: &LearningMaterialId,
        release_id: &PackageReleaseId,
    ) -> Result<PackageEditionView, ApplicationError> {
        let material = self
            .materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let current_revision = self.current_revision(&material)?;
        let installation = self
            .package_lifecycle
            .get_installation(material_id, release_id)?
            .ok_or(ApplicationError::NotFound("package release installation"))?;
        if installation.material_revision_id != current_revision.id {
            return Err(ApplicationError::Invalid(
                "package release is installed for a stale material revision".into(),
            ));
        }
        let plan = adoption_commit_plan(&installation, now_ms())?;
        let committed = self.package_lifecycle.commit_adoption(&plan)?;
        Ok(edition_view(installation, Some(&committed)))
    }

    /// Loads the Material's actual current revision from the repository and
    /// revalidates ownership, mirroring the Material use cases: a repository
    /// must never point a Material's current-revision pointer at a revision
    /// owned by another Material.
    fn current_revision(
        &self,
        material: &LearningMaterial,
    ) -> Result<MaterialRevision, ApplicationError> {
        let revision = self
            .materials
            .get_revision(&material.current_revision_id)?
            .ok_or_else(|| ApplicationError::Repository("current revision is missing".into()))?;
        if revision.material_id != material.id {
            return Err(ApplicationError::Repository(
                "current revision belongs to another material".into(),
            ));
        }
        Ok(revision)
    }

    /// Validates the inspected v3 release against the Material and projects it
    /// into the prepared installation. Source renditions must match the
    /// Material's own renditions; Derived renditions carry producer facts
    /// (already enforced by the v3 inspection) and are available only when
    /// their declared blob is present in the carrier.
    fn prepare_v3_installation(
        &self,
        material: &LearningMaterial,
        current_revision: &MaterialRevision,
        inspection: &V3Inspection,
        plan: &V3InstallationPlan,
    ) -> Result<PreparedPackageInstallation, ApplicationError> {
        if plan.material_id != material.id.as_str() {
            return Err(ApplicationError::Invalid(
                "content package v3 material id does not match the target material".into(),
            ));
        }
        if plan.material_revision_id != current_revision.id.as_str() {
            return Err(ApplicationError::Invalid(
                "content package v3 material revision does not match the material's current revision"
                    .into(),
            ));
        }
        let document_availability = validate_v3_document_sources(current_revision, inspection)?;
        let media_availability = validate_v3_media_sources(current_revision, inspection)?;
        verify_v3_required_closure(plan, inspection)?;
        let edition = LearningEdition {
            edition_id: domain::LearningEditionId::parse(&plan.edition_id)?,
            title: inspection.release.edition.title.clone(),
            target_language: LanguageCode::parse(&inspection.release.edition.target_language)?,
            support_languages: inspection
                .release
                .edition
                .support_languages
                .iter()
                .map(LanguageCode::parse)
                .collect::<Result<Vec<_>, _>>()?,
        };
        let resources = plan
            .resources
            .iter()
            .map(|resource| resource_fact_v3(resource, inspection))
            .collect::<Result<Vec<_>, _>>()?;
        let renditions = v3_rendition_facts(plan, &document_availability, &media_availability)?;
        let payloads = collect_prepared_payloads_v3(plan, inspection)?;
        Ok(PreparedPackageInstallation {
            installation: PackageInstallation {
                release_id: PackageReleaseId::parse(&plan.release_id)?,
                release_created_at_ms: inspection.release.created_at_ms,
                material_id: material.id.clone(),
                material_revision_id: current_revision.id.clone(),
                edition,
                resources,
                renditions,
                installed_at_ms: now_ms(),
            },
            payloads,
        })
    }
}

/// Validates every declared v3 Document Rendition against the bound Material
/// document renditions. A Source rendition must agree with exactly one
/// Material document rendition by exact text digest and must not contradict
/// its declared language; a Derived rendition is available when its declared
/// text blob is present in the carrier. Returns the per-rendition
/// availability fact.
fn validate_v3_document_sources(
    current_revision: &MaterialRevision,
    inspection: &V3Inspection,
) -> Result<HashMap<String, bool>, ApplicationError> {
    let mut availability = HashMap::with_capacity(inspection.document_renditions.len());
    for record in &inspection.document_renditions {
        let entry = &record.entry;
        let available = match entry.origin {
            content_package::v3::RenditionOrigin::Source => {
                let digest_hex = entry.text_blob.digest.trim_start_matches("sha256:");
                let matches: Vec<&DocumentRendition> = current_revision
                    .renditions
                    .iter()
                    .filter_map(|component| match component {
                        Rendition::Document(rendition) if rendition.text_sha256 == digest_hex => {
                            Some(rendition)
                        }
                        _ => None,
                    })
                    .collect();
                if matches.is_empty() {
                    return Err(ApplicationError::Invalid(
                        "content package v3 source document rendition does not match a bound material document rendition"
                            .into(),
                    ));
                }
                if matches.len() > 1 {
                    return Err(ApplicationError::Invalid(
                        "content package v3 source document rendition binding is ambiguous".into(),
                    ));
                }
                if let (Some(declared), Some(stored)) = (&entry.language, &matches[0].language)
                    && declared != stored.as_str()
                {
                    return Err(ApplicationError::Invalid(
                        "content package v3 source document rendition contradicts the material's declared language"
                            .into(),
                    ));
                }
                true
            }
            content_package::v3::RenditionOrigin::Derived => {
                debug_assert!(
                    entry.producer.is_some(),
                    "derived renditions carry producer facts by inspection"
                );
                record.text_present
            }
        };
        availability.insert(entry.rendition_id.clone(), available);
    }
    Ok(availability)
}

/// Validates every declared v3 Media Rendition against the bound Material
/// media renditions. A Source rendition must match exactly one bound asset by
/// kind and fingerprint; a Derived rendition records its own producer facts
/// and is available when its declared media blob is present in the carrier.
/// Returns the per-rendition availability fact.
fn validate_v3_media_sources(
    current_revision: &MaterialRevision,
    inspection: &V3Inspection,
) -> Result<HashMap<String, (bool, Option<MediaId>)>, ApplicationError> {
    let mut availability = HashMap::with_capacity(inspection.media_renditions.len());
    for record in &inspection.media_renditions {
        let entry = &record.entry;
        let fact = match entry.origin {
            content_package::v3::RenditionOrigin::Source => {
                let matches: Vec<&MediaRendition> = current_revision
                    .renditions
                    .iter()
                    .filter_map(|component| {
                        let Rendition::Media(media) = component else {
                            return None;
                        };
                        let kind_matches = match media.kind {
                            MediaKind::Audio => entry.kind == "audio",
                            MediaKind::Video => entry.kind == "video",
                        };
                        (kind_matches
                            && media_fingerprint_equals(&media.fingerprint, &entry.fingerprint))
                        .then_some(media)
                    })
                    .collect();
                if matches.is_empty() {
                    return Err(ApplicationError::Invalid(
                        "content package v3 media rendition does not match a bound material media rendition"
                            .into(),
                    ));
                }
                if matches.len() > 1 {
                    return Err(ApplicationError::Invalid(
                        "content package v3 media rendition binding is ambiguous".into(),
                    ));
                }
                (
                    matches[0].availability == MediaAvailability::Available,
                    matches[0].media_id.clone(),
                )
            }
            content_package::v3::RenditionOrigin::Derived => {
                debug_assert!(
                    entry.producer.is_some(),
                    "derived renditions carry producer facts by inspection"
                );
                (record.media_present, None)
            }
        };
        availability.insert(entry.rendition_id.clone(), fact);
    }
    Ok(availability)
}

/// Whether the Material's stored media fingerprint equals the declared v3
/// rendition fingerprint. Equal strings match; a `sha256:` prefix difference
/// over an otherwise equal 64-hex digest matches; anything else never
/// matches, so no cross-source equivalence is inferred.
fn media_fingerprint_equals(stored: &str, declared: &str) -> bool {
    if stored == declared {
        return true;
    }
    let stored_hex = stored.strip_prefix("sha256:").unwrap_or(stored);
    let declared_hex = declared.strip_prefix("sha256:").unwrap_or(declared);
    stored_hex == declared_hex && stored_hex.len() == 64
}

/// Every required known resource payload and its transitive dependency
/// closure must be available and verified; optional missing resources remain
/// explicit unavailable facts.
fn verify_v3_required_closure(
    plan: &V3InstallationPlan,
    inspection: &V3Inspection,
) -> Result<(), ApplicationError> {
    let dispositions: HashMap<&str, &PlanResource> = plan
        .resources
        .iter()
        .map(|resource| (resource.resource_id.as_str(), resource))
        .collect();
    let edges: HashMap<&str, Vec<&str>> = inspection
        .release
        .resources
        .iter()
        .map(|entry| {
            (
                entry.resource_id.as_str(),
                entry
                    .descriptor
                    .dependencies
                    .iter()
                    .map(|dependency| dependency.resource_id.as_str())
                    .collect(),
            )
        })
        .collect();
    for resource in plan.resources.iter().filter(|resource| resource.required) {
        if resource.disposition != ResourceDisposition::Candidate {
            return Err(ApplicationError::Invalid(
                "content package v3 required resource payload is unavailable".into(),
            ));
        }
        let mut pending = vec![resource.resource_id.as_str()];
        let mut seen = HashSet::new();
        while let Some(next) = pending.pop() {
            if !seen.insert(next) {
                continue;
            }
            let Some(dependencies) = edges.get(next) else {
                return Err(v3_closure_unavailable());
            };
            for dependency in dependencies {
                let available = dispositions
                    .get(dependency)
                    .is_some_and(|entry| entry.disposition == ResourceDisposition::Candidate);
                if !available {
                    return Err(v3_closure_unavailable());
                }
                pending.push(dependency);
            }
        }
    }
    Ok(())
}

fn v3_closure_unavailable() -> ApplicationError {
    ApplicationError::Invalid(
        "content package v3 required resource dependency closure is unavailable".into(),
    )
}

/// Collects the exact validated bytes of every present resource payload from
/// the v3 inspection: candidate payloads must be present, present opaque
/// payloads are preserved with their bytes, and missing resources contribute
/// no body.
fn collect_prepared_payloads_v3(
    plan: &V3InstallationPlan,
    inspection: &V3Inspection,
) -> Result<Vec<PreparedResourcePayload>, ApplicationError> {
    let mut payloads = Vec::new();
    for resource in &plan.resources {
        let present = inspection
            .payload_blobs
            .get(&resource.payload_digest)
            .map(|bytes| (bytes.len() as u64, bytes.clone()));
        match resource.disposition {
            ResourceDisposition::Candidate => {
                let (size_bytes, bytes) = present.ok_or_else(|| {
                    ApplicationError::Repository(
                        "package release candidate payload bytes are missing".into(),
                    )
                })?;
                payloads.push(PreparedResourcePayload {
                    resource_id: resource.resource_id.clone(),
                    kind: resource.kind.clone(),
                    schema: resource.schema.clone(),
                    digest: resource.payload_digest.clone(),
                    size_bytes,
                    bytes,
                });
            }
            ResourceDisposition::Opaque => {
                if let Some((size_bytes, bytes)) = present {
                    payloads.push(PreparedResourcePayload {
                        resource_id: resource.resource_id.clone(),
                        kind: resource.kind.clone(),
                        schema: resource.schema.clone(),
                        digest: resource.payload_digest.clone(),
                        size_bytes,
                        bytes,
                    });
                }
            }
            ResourceDisposition::Missing => {}
        }
    }
    payloads.sort_by(|a, b| a.resource_id.cmp(&b.resource_id));
    Ok(payloads)
}

/// Projects one v3 plan resource into the immutable domain fact, joining the
/// descriptor facts from the inspected release.
fn resource_fact_v3(
    plan_resource: &PlanResource,
    inspection: &V3Inspection,
) -> Result<PackageResourceFact, ApplicationError> {
    let entry = inspection
        .release
        .resources
        .iter()
        .find(|entry| entry.resource_id == plan_resource.resource_id)
        .ok_or_else(|| {
            ApplicationError::Repository("package release resource is missing".into())
        })?;
    let descriptor = &entry.descriptor;
    Ok(PackageResourceFact {
        resource_id: plan_resource.resource_id.clone(),
        kind: plan_resource.kind.clone(),
        schema: plan_resource.schema.clone(),
        role: match plan_resource.role {
            ResourceRole::Base => PackageResourceRole::Base,
            ResourceRole::Assistance => PackageResourceRole::Assistance,
        },
        required: plan_resource.required,
        availability: match plan_resource.disposition {
            ResourceDisposition::Candidate => PackageResourceAvailability::Available,
            ResourceDisposition::Opaque => PackageResourceAvailability::Opaque,
            ResourceDisposition::Missing => PackageResourceAvailability::Missing,
        },
        content_language: descriptor
            .content_language
            .as_deref()
            .map(LanguageCode::parse)
            .transpose()?,
        support_languages: descriptor
            .support_languages
            .iter()
            .map(LanguageCode::parse)
            .collect::<Result<Vec<_>, _>>()?,
        dependencies: descriptor
            .dependencies
            .iter()
            .map(|dependency| dependency.resource_id.clone())
            .collect(),
        payload_digest: descriptor.payload_blob.digest.clone(),
        payload_size_bytes: descriptor.payload_blob.size_bytes,
        provenance: PackageResourceProvenance {
            created_at_ms: descriptor.provenance.created_at_ms,
            tool_id: descriptor.provenance.tool.id.clone(),
            tool_version: descriptor.provenance.tool.version.clone(),
            provider_id: descriptor
                .provenance
                .provider
                .as_ref()
                .map(|producer| producer.id.clone()),
            provider_version: descriptor
                .provenance
                .provider
                .as_ref()
                .map(|producer| producer.version.clone()),
            model_id: descriptor
                .provenance
                .model
                .as_ref()
                .map(|producer| producer.id.clone()),
            model_version: descriptor
                .provenance
                .model
                .as_ref()
                .map(|producer| producer.version.clone()),
            config_sha256: descriptor.provenance.config_sha256.clone(),
        },
        review_status: match descriptor.quality.review_status {
            ReviewStatus::Unreviewed => PackageReviewStatus::Unreviewed,
            ReviewStatus::MachineChecked => PackageReviewStatus::MachineChecked,
            ReviewStatus::HumanReviewed => PackageReviewStatus::HumanReviewed,
        },
        quality_warnings: descriptor.quality.warnings.clone(),
    })
}

/// Projects every v3 rendition into the immutable domain facts: document
/// renditions carry kind `document` and media renditions kind `media`, both
/// with their exact origin, availability, digest, and size snapshot.
fn v3_rendition_facts(
    plan: &V3InstallationPlan,
    document_availability: &HashMap<String, bool>,
    media_availability: &HashMap<String, (bool, Option<MediaId>)>,
) -> Result<Vec<PackageRenditionFact>, ApplicationError> {
    let mut facts =
        Vec::with_capacity(plan.document_renditions.len() + plan.media_renditions.len());
    for rendition in &plan.document_renditions {
        facts.push(document_rendition_fact(rendition, document_availability)?);
    }
    for rendition in &plan.media_renditions {
        facts.push(media_rendition_fact(rendition, media_availability)?);
    }
    Ok(facts)
}

fn document_rendition_fact(
    plan_rendition: &PlanDocumentRendition,
    availability: &HashMap<String, bool>,
) -> Result<PackageRenditionFact, ApplicationError> {
    let available = availability
        .get(&plan_rendition.rendition_id)
        .copied()
        .ok_or_else(|| {
            ApplicationError::Repository("package release document rendition is missing".into())
        })?;
    Ok(PackageRenditionFact {
        rendition_id: plan_rendition.rendition_id.clone(),
        kind: "document".to_owned(),
        origin: match plan_rendition.origin {
            content_package::v3::RenditionOrigin::Source => RenditionOrigin::Source,
            content_package::v3::RenditionOrigin::Derived => RenditionOrigin::Derived,
        },
        media_type: plan_rendition.media_type.clone(),
        available,
        media_digest: plan_rendition.text_digest.clone(),
        media_size_bytes: plan_rendition.text_size_bytes,
        media_id: None,
        producer: plan_rendition
            .producer
            .as_ref()
            .map(|producer| PackageResourceProvenance {
                created_at_ms: producer.created_at_ms,
                tool_id: producer.tool_id.clone(),
                tool_version: producer.tool_version.clone(),
                provider_id: producer.provider_id.clone(),
                provider_version: producer.provider_version.clone(),
                model_id: producer.model_id.clone(),
                model_version: producer.model_version.clone(),
                config_sha256: producer.config_sha256.clone(),
            }),
    })
}

fn media_rendition_fact(
    plan_rendition: &PlanMediaRendition,
    availability: &HashMap<String, (bool, Option<MediaId>)>,
) -> Result<PackageRenditionFact, ApplicationError> {
    let (available, media_id) = availability
        .get(&plan_rendition.rendition_id)
        .cloned()
        .ok_or_else(|| {
            ApplicationError::Repository("package release media rendition is missing".into())
        })?;
    Ok(PackageRenditionFact {
        rendition_id: plan_rendition.rendition_id.clone(),
        kind: "media".to_owned(),
        origin: match plan_rendition.origin {
            content_package::v3::RenditionOrigin::Source => RenditionOrigin::Source,
            content_package::v3::RenditionOrigin::Derived => RenditionOrigin::Derived,
        },
        media_type: plan_rendition.media_type.clone(),
        available,
        media_digest: plan_rendition.media_digest.clone(),
        media_size_bytes: plan_rendition.media_size_bytes,
        media_id,
        producer: plan_rendition
            .producer
            .as_ref()
            .map(|producer| PackageResourceProvenance {
                created_at_ms: producer.created_at_ms,
                tool_id: producer.tool_id.clone(),
                tool_version: producer.tool_version.clone(),
                provider_id: producer.provider_id.clone(),
                provider_version: producer.provider_version.clone(),
                model_id: producer.model_id.clone(),
                model_version: producer.model_version.clone(),
                config_sha256: producer.config_sha256.clone(),
            }),
    })
}

/// Maps bounded v3 inspection failures into stable application errors. Local
/// package paths, payloads, and raw validation text never leak into the
/// error surface.
fn map_v3_inspection_error(error: V3Error) -> ApplicationError {
    let message = match error {
        V3Error::Io(_) | V3Error::Zip(_) => "content package v3 could not be read",
        V3Error::Limit(_) => "content package v3 exceeds inspection limits",
        V3Error::UnsafePath(_) => "content package v3 contains an unsafe entry path",
        V3Error::Symlink(_) => "content package v3 contains a symbolic link",
        V3Error::DuplicatePath(_) => "content package v3 contains duplicate entries",
        V3Error::MissingRelease => "content package v3 is missing release.json",
        V3Error::ReleaseJson(_) => "content package v3 release.json is not valid JSON",
        V3Error::PayloadJson { .. } => "content package v3 resource payload is not valid JSON",
        V3Error::Invalid { .. } => "content package v3 carrier is invalid",
        V3Error::Incompatible { .. } => "content package v3 release is incompatible",
    };
    ApplicationError::Invalid(message.into())
}

fn edition_view(
    installation: PackageInstallation,
    adoption: Option<&AdoptionCommitPlan>,
) -> PackageEditionView {
    PackageEditionView {
        material_id: installation.material_id,
        material_revision_id: installation.material_revision_id,
        edition_id: installation.edition.edition_id,
        release_id: installation.release_id,
        title: installation.edition.title,
        target_language: installation.edition.target_language,
        support_languages: installation.edition.support_languages,
        installed_at_ms: installation.installed_at_ms,
        adopted_at_ms: adoption.map(|plan| plan.adopted_at_ms),
        adopted: adoption.is_some(),
        resources: installation
            .resources
            .iter()
            .map(|resource| PackageResourceView {
                resource_id: resource.resource_id.clone(),
                kind: resource.kind.clone(),
                role: resource.role,
                required: resource.required,
                availability: resource.availability,
                review_status: resource.review_status,
                content_language: resource.content_language.clone(),
                support_languages: resource.support_languages.clone(),
            })
            .collect(),
        renditions: installation
            .renditions
            .iter()
            .map(|rendition| PackageRenditionView {
                rendition_id: rendition.rendition_id.clone(),
                kind: rendition.kind.clone(),
                available: rendition.available,
            })
            .collect(),
    }
}

/// Maps pure adoption-rule failures into stable application errors. The
/// messages never expose resource ids, payloads, or internal facts; the HTTP
/// stage later maps them to its own status codes.
impl From<PackageLifecycleError> for ApplicationError {
    fn from(error: PackageLifecycleError) -> Self {
        let message = match error {
            PackageLifecycleError::MissingRequiredResource { .. } => {
                "package release is missing a required resource"
            }
            PackageLifecycleError::BrokenDependencyClosure { .. } => {
                "package release resource dependency closure is broken"
            }
            PackageLifecycleError::AmbiguousExclusiveFamily { .. } => {
                "package release has multiple candidates in an exclusive resource family"
            }
        };
        ApplicationError::Invalid(message.into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use content_package::v2::serialize_canonical;
    use content_package::v3::RELEASE_SCHEMA_V3;
    use domain::{LearningMaterial, MaterialRevision, MediaId, initial_material_id};
    use serde_json::{Value, json};
    use sha2::{Digest as _, Sha256};

    const EDITION_TITLE: &str = "Fixture Edition";
    const TEXT: &str = "Hello world.";
    /// Deterministic media fixture bytes; the rendition digest is their
    /// SHA-256, so carriers stay content-honest.
    const MEDIA_BYTES: &[u8] = b"listen fixture media payload";

    // ---------------------------------------------------------------------
    // Test double state
    // ---------------------------------------------------------------------

    #[derive(Clone, Default)]
    struct FakeMaterialState {
        materials: HashMap<String, LearningMaterial>,
        revisions: HashMap<String, MaterialRevision>,
        membership_calls: u64,
    }

    #[derive(Clone, Default)]
    struct FakeMaterialRepository {
        state: Arc<Mutex<FakeMaterialState>>,
    }

    impl FakeMaterialRepository {
        fn seed_material(&self, material: LearningMaterial, revision: MaterialRevision) {
            let mut state = self.state.lock().unwrap();
            state
                .materials
                .insert(material.id.as_str().to_owned(), material);
            state
                .revisions
                .insert(revision.id.as_str().to_owned(), revision);
        }

        fn membership_calls(&self) -> u64 {
            self.state.lock().unwrap().membership_calls
        }

        fn append_revision_fake(&self, revision: MaterialRevision, updated_at_ms: u64) {
            let mut state = self.state.lock().unwrap();
            state
                .revisions
                .insert(revision.id.as_str().to_owned(), revision.clone());
            let material = state
                .materials
                .get_mut(revision.material_id.as_str())
                .expect("material exists");
            material.current_revision_id = revision.id;
            material.updated_at_ms = updated_at_ms;
        }

        /// Test-only pointer corruption: points the Material's
        /// current-revision pointer at `pointer` without touching the
        /// revisions table, so the authoritative `current_revision` guard
        /// must catch the missing or cross-material case.
        fn corrupt_current_revision(
            &self,
            material_id: &LearningMaterialId,
            pointer: MaterialRevisionId,
        ) {
            let mut state = self.state.lock().unwrap();
            let material = state
                .materials
                .get_mut(material_id.as_str())
                .expect("material exists");
            material.current_revision_id = pointer;
        }
    }

    impl MaterialRepository for FakeMaterialRepository {
        fn create_material(
            &self,
            material: &LearningMaterial,
            revision: &MaterialRevision,
        ) -> Result<LearningMaterial, ApplicationError> {
            self.seed_material(material.clone(), revision.clone());
            Ok(material.clone())
        }

        fn append_revision(
            &self,
            material_id: &LearningMaterialId,
            revision: &MaterialRevision,
            updated_at_ms: u64,
        ) -> Result<LearningMaterial, ApplicationError> {
            self.append_revision_fake(revision.clone(), updated_at_ms);
            Ok(self
                .state
                .lock()
                .unwrap()
                .materials
                .get(material_id.as_str())
                .cloned()
                .expect("material exists"))
        }

        fn get_material(
            &self,
            material_id: &LearningMaterialId,
        ) -> Result<Option<LearningMaterial>, ApplicationError> {
            Ok(self
                .state
                .lock()
                .unwrap()
                .materials
                .get(material_id.as_str())
                .cloned())
        }

        fn get_revision(
            &self,
            revision_id: &MaterialRevisionId,
        ) -> Result<Option<MaterialRevision>, ApplicationError> {
            Ok(self
                .state
                .lock()
                .unwrap()
                .revisions
                .get(revision_id.as_str())
                .cloned())
        }

        fn list_retained_materials(&self) -> Result<Vec<LearningMaterial>, ApplicationError> {
            Ok(Vec::new())
        }

        fn set_library_membership(
            &self,
            material_id: &LearningMaterialId,
            retained_at_ms: Option<u64>,
            updated_at_ms: u64,
        ) -> Result<LearningMaterial, ApplicationError> {
            let mut state = self.state.lock().unwrap();
            state.membership_calls += 1;
            let material = state
                .materials
                .get_mut(material_id.as_str())
                .ok_or_else(|| ApplicationError::Repository("material not found".into()))?;
            material.retained_at_ms = retained_at_ms;
            material.updated_at_ms = updated_at_ms;
            Ok(material.clone())
        }

        fn material_for_media(
            &self,
            _media_id: &MediaId,
        ) -> Result<Option<LearningMaterial>, ApplicationError> {
            Ok(None)
        }

        fn set_source_asset_availability(
            &self,
            _material_id: &LearningMaterialId,
            _source_asset_id: &domain::SourceAssetId,
            _availability: domain::SourceAssetAvailability,
        ) -> Result<Option<MaterialRevision>, ApplicationError> {
            Ok(None)
        }
    }

    #[derive(Clone)]
    struct StoredInstallation {
        installation: PackageInstallation,
        payloads: BTreeMap<String, PreparedResourcePayload>,
    }

    #[derive(Clone, Default)]
    struct FakePackageLifecycleState {
        installations: HashMap<(String, String), StoredInstallation>,
        adoptions: HashMap<String, AdoptionCommitPlan>,
        save_calls: u64,
        commit_calls: u64,
        fail_commit_adoption: bool,
        /// When true, `save_installation` drops the payload bodies and stores
        /// only the facts, simulating a misbehaving adapter so tests can
        /// exercise the commit-time backing invariant.
        drop_payloads: bool,
    }

    #[derive(Clone, Default)]
    struct FakePackageLifecycleRepository {
        state: Arc<Mutex<FakePackageLifecycleState>>,
    }

    impl FakePackageLifecycleRepository {
        fn save_calls(&self) -> u64 {
            self.state.lock().unwrap().save_calls
        }

        fn commit_calls(&self) -> u64 {
            self.state.lock().unwrap().commit_calls
        }

        fn installation_count(&self) -> usize {
            self.state.lock().unwrap().installations.len()
        }

        /// Every stored installation for one material, in insertion order.
        fn stored_installations(
            &self,
            material_id: &LearningMaterialId,
        ) -> Vec<PackageInstallation> {
            let mut stored: Vec<PackageInstallation> = self
                .state
                .lock()
                .unwrap()
                .installations
                .values()
                .filter(|entry| entry.installation.material_id == *material_id)
                .map(|entry| entry.installation.clone())
                .collect();
            stored.sort_by(|a, b| a.release_id.as_str().cmp(b.release_id.as_str()));
            stored
        }

        fn set_fail_commit_adoption(&self, fail: bool) {
            self.state.lock().unwrap().fail_commit_adoption = fail;
        }

        fn set_drop_payloads(&self, drop: bool) {
            self.state.lock().unwrap().drop_payloads = drop;
        }

        fn adoption_count(&self) -> usize {
            self.state.lock().unwrap().adoptions.len()
        }

        /// Test-only corruption: replaces the stored adoption plan of one
        /// material with another plan, simulating a tampered adoption row.
        fn tamper_adoption(&self, material_id: &LearningMaterialId, plan: AdoptionCommitPlan) {
            self.state
                .lock()
                .unwrap()
                .adoptions
                .insert(material_id.as_str().to_owned(), plan);
        }

        /// The durable payload bodies stored for one installation, sorted by
        /// resource id, or `None` when the installation is absent.
        fn stored_payloads(
            &self,
            material_id: &LearningMaterialId,
            release_id: &PackageReleaseId,
        ) -> Option<Vec<PreparedResourcePayload>> {
            self.state
                .lock()
                .unwrap()
                .installations
                .get(&(
                    material_id.as_str().to_owned(),
                    release_id.as_str().to_owned(),
                ))
                .map(|stored| stored.payloads.values().cloned().collect())
        }
    }

    fn payload_map(
        prepared: &PreparedPackageInstallation,
    ) -> BTreeMap<String, PreparedResourcePayload> {
        prepared
            .payloads
            .iter()
            .map(|payload| (payload.resource_id.clone(), payload.clone()))
            .collect()
    }

    /// The seam's retry equality: identical immutable release facts with the
    /// adapter-stamped `installed_at_ms` excluded.
    fn immutable_facts_equal(first: &PackageInstallation, second: &PackageInstallation) -> bool {
        let mut first = first.clone();
        let mut second = second.clone();
        first.installed_at_ms = 0;
        second.installed_at_ms = 0;
        first == second
    }

    impl PackageLifecycleRepository for FakePackageLifecycleRepository {
        fn save_installation(
            &self,
            prepared: &PreparedPackageInstallation,
        ) -> Result<PackageInstallation, ApplicationError> {
            let mut state = self.state.lock().unwrap();
            state.save_calls += 1;
            let key = (
                prepared.installation.material_id.as_str().to_owned(),
                prepared.installation.release_id.as_str().to_owned(),
            );
            if let Some(existing) = state.installations.get(&key) {
                if immutable_facts_equal(&existing.installation, &prepared.installation)
                    && existing.payloads == payload_map(prepared)
                {
                    return Ok(existing.installation.clone());
                }
                return Err(ApplicationError::Repository(
                    "package release installation identity conflicts with an unequal existing installation"
                        .into(),
                ));
            }
            let drop_payloads = state.drop_payloads;
            state.installations.insert(
                key,
                StoredInstallation {
                    installation: prepared.installation.clone(),
                    payloads: if drop_payloads {
                        BTreeMap::new()
                    } else {
                        payload_map(prepared)
                    },
                },
            );
            Ok(prepared.installation.clone())
        }

        fn get_installation(
            &self,
            material_id: &LearningMaterialId,
            release_id: &PackageReleaseId,
        ) -> Result<Option<PackageInstallation>, ApplicationError> {
            Ok(self
                .state
                .lock()
                .unwrap()
                .installations
                .get(&(
                    material_id.as_str().to_owned(),
                    release_id.as_str().to_owned(),
                ))
                .map(|stored| stored.installation.clone()))
        }

        fn list_installations(
            &self,
            material_id: &LearningMaterialId,
        ) -> Result<Vec<PackageInstallation>, ApplicationError> {
            let state = self.state.lock().unwrap();
            let mut installations: Vec<PackageInstallation> = state
                .installations
                .values()
                .filter(|stored| stored.installation.material_id == *material_id)
                .map(|stored| stored.installation.clone())
                .collect();
            installations.sort_by(|a, b| a.release_id.as_str().cmp(b.release_id.as_str()));
            Ok(installations)
        }

        fn get_adoption(
            &self,
            material_id: &LearningMaterialId,
        ) -> Result<Option<AdoptionCommitPlan>, ApplicationError> {
            Ok(self
                .state
                .lock()
                .unwrap()
                .adoptions
                .get(material_id.as_str())
                .cloned())
        }

        fn commit_adoption(
            &self,
            commit: &AdoptionCommitPlan,
        ) -> Result<AdoptionCommitPlan, ApplicationError> {
            let mut state = self.state.lock().unwrap();
            state.commit_calls += 1;
            if state.fail_commit_adoption {
                return Err(ApplicationError::Repository(
                    "injected adoption commit failure".into(),
                ));
            }
            // Every selected available resource must have durable payload
            // backing from its save_installation; a violation fails the
            // commit atomically, preserving any previous adoption.
            let backing = state.installations.get(&(
                commit.material_id.as_str().to_owned(),
                commit.release_id.as_str().to_owned(),
            ));
            let lacks_backing = match backing {
                Some(stored) => commit
                    .selected_resource_ids
                    .iter()
                    .any(|resource_id| !stored.payloads.contains_key(resource_id)),
                None => true,
            };
            if lacks_backing {
                return Err(ApplicationError::Repository(
                    "package release selected resources lack durable payload backing".into(),
                ));
            }
            // Same-release re-adopt: the seam compares the complete stored
            // plan with the candidate, ignoring adopted_at_ms on both sides.
            // An equal retry returns the existing adoption and preserves the
            // original timestamp; a stored row that differs in any other fact
            // is corruption and fails closed without overwriting or repairing
            // it. A different release replaces the adoption atomically.
            if let Some(existing) = state.adoptions.get(commit.material_id.as_str())
                && existing.release_id == commit.release_id
            {
                let mut stored_plan = existing.clone();
                stored_plan.adopted_at_ms = 0;
                let mut candidate = commit.clone();
                candidate.adopted_at_ms = 0;
                if stored_plan != candidate {
                    return Err(ApplicationError::Repository(
                        "package adoption plan conflicts with the stored adoption row".into(),
                    ));
                }
                return Ok(existing.clone());
            }
            state
                .adoptions
                .insert(commit.material_id.as_str().to_owned(), commit.clone());
            Ok(commit.clone())
        }
    }

    // ---------------------------------------------------------------------
    // Carrier fixture helpers (programmatic canonical v2 carriers)
    // ---------------------------------------------------------------------

    struct TestDirectory(PathBuf);

    static NEXT_TEST_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    impl TestDirectory {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let sequence = NEXT_TEST_DIRECTORY.fetch_add(1, Ordering::Relaxed);
            let process = std::process::id();
            let path = std::env::temp_dir().join(format!(
                "listen-package-lifecycle-{process}-{sequence}-{nonce}"
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn sha256_id(bytes: &[u8]) -> String {
        format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
    }

    fn canonical_bytes(value: &Value) -> Vec<u8> {
        serialize_canonical(value).unwrap()
    }

    fn blob_path(digest: &str) -> String {
        format!("blobs/sha256/{}", digest.strip_prefix("sha256:").unwrap())
    }

    fn language(code: &str) -> LanguageCode {
        LanguageCode::parse(code).unwrap()
    }

    fn media_hex() -> String {
        hex::encode(Sha256::digest(MEDIA_BYTES))
    }

    fn resource_entry(descriptor: &Value, required: bool) -> Value {
        json!({
            "resource_id": sha256_id(&canonical_bytes(descriptor)),
            "required": required,
            "descriptor": descriptor.clone(),
        })
    }

    fn document_payload(text: &str, language: &str) -> (Value, Vec<u8>) {
        let end = text.chars().count() as u32;
        let payload = json!({
            "language": language,
            "text": text,
            "segments": [{"id": "s1", "index": 0, "language": language, "start_char": 0, "end_char": end, "extensions": {}}],
            "extensions": {},
        });
        let bytes = serde_json::to_vec(&payload).unwrap();
        (payload, bytes)
    }

    fn translation_payload(
        support_language: &str,
        base_resource_id: &str,
        text: &str,
    ) -> (Value, Vec<u8>) {
        let payload = json!({
            "support_language": support_language,
            "base_resource_id": base_resource_id,
            "segments": [{"id": "tr-1", "index": 0, "text": text, "source_segment_id": "s1", "extensions": {}}],
            "extensions": {},
        });
        let bytes = serde_json::to_vec(&payload).unwrap();
        (payload, bytes)
    }

    struct FixtureIds {
        material_id: String,
        revision_id: String,
    }

    fn write_carrier(files: &BTreeMap<String, Vec<u8>>) -> (TestDirectory, PathBuf) {
        let directory = TestDirectory::new();
        for (name, bytes) in files {
            let path = directory.path().join(name);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, bytes).unwrap();
        }
        // The fixture directory itself is the package carrier.
        let path = directory.path().to_path_buf();
        (directory, path)
    }

    /// Inserts the canonical `release.json` into a carrier file map.
    fn carrier_with_release(
        release: &Value,
        mut blobs: BTreeMap<String, Vec<u8>>,
    ) -> BTreeMap<String, Vec<u8>> {
        blobs.insert("release.json".into(), canonical_bytes(release));
        blobs
    }

    fn v3_assistance_descriptor(
        kind: &str,
        schema: &str,
        support: &[&str],
        dependencies: &[&str],
        digest: &str,
        size: u64,
        revision_id: &str,
    ) -> Value {
        json!({
            "schema": schema,
            "kind": kind,
            "role": "assistance",
            "support_languages": support,
            "subject": {"material_revision_id": revision_id, "rendition_ids": [], "anchor_resource_ids": []},
            "dependencies": dependencies.iter().map(|dep| json!({"resource_id": dep})).collect::<Vec<_>>(),
            "provenance": {"created_at_ms": 1, "tool": {"id": "listen-gen", "version": "0.4.0"}, "input_resource_ids": [], "extensions": {}},
            "quality": {"review_status": "machine_checked", "warnings": [], "extensions": {}},
            "payload_blob": v3_blob_declaration(digest, size, false),
            "extensions": {},
        })
    }

    // ---------------------------------------------------------------------
    // Material fixture helpers
    // ---------------------------------------------------------------------

    struct Setup {
        use_cases: PackageLifecycleUseCases,
        materials: FakeMaterialRepository,
        package_lifecycle: FakePackageLifecycleRepository,
    }

    fn setup() -> Setup {
        let materials = FakeMaterialRepository::default();
        let package_lifecycle = FakePackageLifecycleRepository::default();
        let use_cases = PackageLifecycleUseCases::new(
            Arc::new(materials.clone()),
            Arc::new(package_lifecycle.clone()),
        );
        Setup {
            use_cases,
            materials,
            package_lifecycle,
        }
    }

    fn seed_text_material(setup: &Setup, retained: bool) -> (LearningMaterial, MaterialRevision) {
        seed_text_material_with_text(setup, retained, TEXT)
    }

    fn seed_text_material_with_text(
        setup: &Setup,
        retained: bool,
        text: &str,
    ) -> (LearningMaterial, MaterialRevision) {
        let rendition = domain::Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                Some(language("en")),
                text,
                None,
                None,
                None,
            )
            .expect("valid document rendition"),
        );
        let material_id =
            initial_material_id(&[], std::slice::from_ref(&rendition)).expect("deterministic id");
        let revision = MaterialRevision::new(
            material_id.clone(),
            "Material",
            Vec::new(),
            vec![rendition],
            1,
        )
        .expect("valid revision");
        let material =
            LearningMaterial::new(&revision, retained.then_some(1), 1, 1).expect("valid material");
        setup
            .materials
            .create_material(&material, &revision)
            .expect("material persists");
        (material, revision)
    }

    /// A mixed text + audio material whose media fingerprint is the given
    /// full fingerprint string (either `sha256:<hex>` or bare `<hex>`) and
    /// whose media asset carries the given availability snapshot.
    fn seed_mixed_media_material(
        setup: &Setup,
        fingerprint: &str,
        media_availability: MediaAvailability,
    ) -> (LearningMaterial, MaterialRevision) {
        let text_rendition = domain::Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                Some(language("en")),
                TEXT,
                None,
                None,
                None,
            )
            .expect("valid document rendition"),
        );
        let media_rendition = domain::Rendition::Media(
            MediaRendition::new(
                RenditionOrigin::Source,
                MediaKind::Audio,
                "audio/mpeg",
                fingerprint,
                media_availability,
                Some(MediaId::parse("media-1").expect("valid media id")),
                None,
                None,
                None,
                None,
            )
            .expect("valid media rendition"),
        );
        let material_id =
            initial_material_id(&[], &[text_rendition.clone(), media_rendition.clone()])
                .expect("deterministic id");
        let revision = MaterialRevision::new(
            material_id.clone(),
            "Material",
            Vec::new(),
            vec![text_rendition, media_rendition],
            1,
        )
        .expect("valid revision");
        let material = LearningMaterial::new(&revision, None, 1, 1).expect("valid material");
        setup
            .materials
            .create_material(&material, &revision)
            .expect("material persists");
        (material, revision)
    }

    fn ids_of(material: &LearningMaterial, revision: &MaterialRevision) -> FixtureIds {
        FixtureIds {
            material_id: material.id.as_str().to_owned(),
            revision_id: revision.id.as_str().to_owned(),
        }
    }

    fn install(
        setup: &Setup,
        material_id: &LearningMaterialId,
        files: &BTreeMap<String, Vec<u8>>,
    ) -> Result<PackageEditionView, ApplicationError> {
        let (_directory, path) = write_carrier(files);
        setup.use_cases.install_for_material(material_id, &path)
    }

    fn install_ok(
        setup: &Setup,
        material_id: &LearningMaterialId,
        files: &BTreeMap<String, Vec<u8>>,
    ) -> PackageEditionView {
        install(setup, material_id, files).expect("installation succeeds")
    }

    fn install_err(
        setup: &Setup,
        material_id: &LearningMaterialId,
        files: &BTreeMap<String, Vec<u8>>,
    ) -> ApplicationError {
        install(setup, material_id, files).expect_err("installation fails")
    }

    // ---------------------------------------------------------------------
    // v3 release fixtures
    // ---------------------------------------------------------------------

    fn v3_blob_declaration(digest: &str, size: u64, embedded: bool) -> Value {
        json!({"digest": digest, "size_bytes": size, "embedded": embedded})
    }

    /// A v3 Document Rendition with the identity derived from the canonical
    /// `{media_type, language, text_blob}` descriptor.
    fn v3_document_rendition(
        origin: &str,
        media_type: &str,
        language: Option<&str>,
        text_blob: &Value,
        source_asset_id: Option<&str>,
        producer: Option<&Value>,
        compatibility: Option<&Value>,
    ) -> Value {
        let identity = json!({
            "media_type": media_type,
            "language": language,
            "text_blob": text_blob,
        });
        let rendition_id = sha256_id(&canonical_bytes(&identity));
        json!({
            "rendition_id": rendition_id,
            "origin": origin,
            "media_type": media_type,
            "language": language,
            "text_blob": text_blob.clone(),
            "source_asset_id": source_asset_id,
            "producer": producer,
            "compatibility": compatibility,
            "extensions": {},
        })
    }

    /// A v3 Media Rendition with the identity derived from the canonical
    /// `{kind, media_type, media_blob, media_id, fingerprint}` descriptor.
    #[allow(clippy::too_many_arguments)]
    fn v3_media_rendition(
        origin: &str,
        kind: &str,
        media_type: &str,
        media_blob: &Value,
        media_id: Option<&str>,
        fingerprint: &str,
        producer: Option<&Value>,
        compatibility: Option<&Value>,
    ) -> Value {
        let identity = json!({
            "kind": kind,
            "media_type": media_type,
            "media_blob": media_blob,
            "media_id": media_id,
            "fingerprint": fingerprint,
        });
        let rendition_id = sha256_id(&canonical_bytes(&identity));
        json!({
            "rendition_id": rendition_id,
            "origin": origin,
            "kind": kind,
            "media_type": media_type,
            "media_blob": media_blob.clone(),
            "media_id": media_id,
            "fingerprint": fingerprint,
            "producer": producer,
            "compatibility": compatibility,
            "extensions": {},
        })
    }

    fn v3_producer() -> Value {
        json!({
            "created_at_ms": 1,
            "tool": {"id": "listen-gen", "version": "0.4.0"},
            "provider": null,
            "model": null,
            "config_sha256": null,
        })
    }

    fn v3_compatibility() -> Value {
        json!({
            "verified_inputs": [],
            "checks": ["exact_text_match"],
        })
    }

    fn v3_base_descriptor(
        kind: &str,
        schema: &str,
        language: &str,
        dependencies: &[&str],
        digest: &str,
        size: u64,
        revision_id: &str,
    ) -> Value {
        json!({
            "schema": schema,
            "kind": kind,
            "role": "base",
            "content_language": language,
            "support_languages": [],
            "subject": {"material_revision_id": revision_id, "rendition_ids": [], "anchor_resource_ids": []},
            "dependencies": dependencies.iter().map(|dep| json!({"resource_id": dep})).collect::<Vec<_>>(),
            "provenance": {"created_at_ms": 1, "tool": {"id": "listen-gen", "version": "0.4.0"}, "input_resource_ids": [], "extensions": {}},
            "quality": {"review_status": "human_reviewed", "warnings": [], "extensions": {}},
            "payload_blob": v3_blob_declaration(digest, size, true),
            "extensions": {},
        })
    }

    fn v3_release(
        ids: &FixtureIds,
        edition_id: &str,
        document_renditions: Vec<Value>,
        media_renditions: Vec<Value>,
        resources: Vec<Value>,
    ) -> Value {
        json!({
            "schema": RELEASE_SCHEMA_V3,
            "created_at_ms": 1u64,
            "edition": {
                "edition_id": edition_id,
                "title": EDITION_TITLE,
                "target_language": "en",
                "support_languages": ["zh-Hans"],
            },
            "material": {
                "material_id": ids.material_id,
                "material_revision_id": ids.revision_id,
                "title": "Fixture Material",
            },
            "document_renditions": document_renditions,
            "media_renditions": media_renditions,
            "resources": resources,
            "extensions": {},
        })
    }

    /// A release with one embedded base document_text resource.
    fn text_only_release(ids: &FixtureIds, edition_id: &str) -> (Value, BTreeMap<String, Vec<u8>>) {
        text_only_release_with_text(ids, edition_id, TEXT)
    }

    fn text_only_release_with_text(
        ids: &FixtureIds,
        edition_id: &str,
        text: &str,
    ) -> (Value, BTreeMap<String, Vec<u8>>) {
        let text_bytes = text.as_bytes().to_vec();
        let text_digest = sha256_id(&text_bytes);
        let text_blob = v3_blob_declaration(&text_digest, text_bytes.len() as u64, true);
        let document = v3_document_rendition(
            "source",
            "text/plain",
            Some("en"),
            &text_blob,
            Some("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            None,
            None,
        );
        let (_, payload_bytes) = document_payload(text, "en");
        let payload_digest = sha256_id(&payload_bytes);
        let descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &payload_digest,
            payload_bytes.len() as u64,
            &ids.revision_id,
        );
        let resource = resource_entry(&descriptor, true);
        let release = v3_release(ids, edition_id, vec![document], vec![], vec![resource]);
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);
        blobs.insert(blob_path(&payload_digest), payload_bytes);

        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    /// A release whose base document text differs from the Material's text.
    fn mismatched_text_release(ids: &FixtureIds) -> (Value, BTreeMap<String, Vec<u8>>) {
        let text_bytes = "Different text entirely.".as_bytes().to_vec();
        let text_digest = sha256_id(&text_bytes);
        let text_blob = v3_blob_declaration(&text_digest, text_bytes.len() as u64, true);
        let document = v3_document_rendition(
            "source",
            "text/plain",
            Some("en"),
            &text_blob,
            Some("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            None,
            None,
        );
        let (_, payload_bytes) = document_payload("Different text entirely.", "en");
        let payload_digest = sha256_id(&payload_bytes);
        let descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &payload_digest,
            payload_bytes.len() as u64,
            &ids.revision_id,
        );
        let resource = resource_entry(&descriptor, true);
        let release = v3_release(
            ids,
            "edition-mismatch",
            vec![document],
            vec![],
            vec![resource],
        );
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);
        blobs.insert(blob_path(&payload_digest), payload_bytes);

        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    /// A release whose base document text declares a different language.
    fn mismatched_text_language_release(ids: &FixtureIds) -> (Value, BTreeMap<String, Vec<u8>>) {
        let text_bytes = TEXT.as_bytes().to_vec();
        let text_digest = sha256_id(&text_bytes);
        let text_blob = v3_blob_declaration(&text_digest, text_bytes.len() as u64, true);
        let document = v3_document_rendition(
            "source",
            "text/plain",
            Some("zh-Hans"),
            &text_blob,
            Some("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            None,
            None,
        );
        let (_, payload_bytes) = document_payload(TEXT, "zh-Hans");
        let payload_digest = sha256_id(&payload_bytes);
        let descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "zh-Hans",
            &[],
            &payload_digest,
            payload_bytes.len() as u64,
            &ids.revision_id,
        );
        let resource = resource_entry(&descriptor, true);
        let release = v3_release(
            ids,
            "edition-language-mismatch",
            vec![document],
            vec![],
            vec![resource],
        );
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);
        blobs.insert(blob_path(&payload_digest), payload_bytes);
        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    /// A mixed media + text release: an audio rendition, a base document
    /// text, and an optional translation assistance. The rendition digest is
    /// the real SHA-256 of [`MEDIA_BYTES`]; `embed_media` controls whether
    /// the media blob is carried or satisfied by the local Material asset.
    fn media_text_translation_release(
        ids: &FixtureIds,
        embed_media: bool,
        edition_id: &str,
    ) -> (Value, BTreeMap<String, Vec<u8>>) {
        let text_bytes = TEXT.as_bytes().to_vec();
        let text_digest = sha256_id(&text_bytes);
        let text_blob = v3_blob_declaration(&text_digest, text_bytes.len() as u64, true);
        let document = v3_document_rendition(
            "source",
            "text/plain",
            Some("en"),
            &text_blob,
            Some("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            None,
            None,
        );
        let (_, text_payload_bytes) = document_payload(TEXT, "en");
        let text_payload_digest = sha256_id(&text_payload_bytes);
        let text_descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &text_payload_digest,
            text_payload_bytes.len() as u64,
            &ids.revision_id,
        );
        let text_resource = resource_entry(&text_descriptor, true);
        let text_resource_id = text_resource["resource_id"].as_str().unwrap().to_owned();

        let (_, translation_bytes) = translation_payload("zh-Hans", &text_resource_id, "译文。");
        let translation_digest = sha256_id(&translation_bytes);
        let translation_descriptor = v3_assistance_descriptor(
            "translation",
            "listen.payload.translation.v1",
            &["zh-Hans"],
            &[&text_resource_id],
            &translation_digest,
            translation_bytes.len() as u64,
            &ids.revision_id,
        );
        let translation_resource = resource_entry(&translation_descriptor, false);

        let media_digest = format!("sha256:{}", media_hex());
        let media_blob = v3_blob_declaration(&media_digest, MEDIA_BYTES.len() as u64, embed_media);
        let media = v3_media_rendition(
            "source",
            "audio",
            "audio/mpeg",
            &media_blob,
            Some("media-1"),
            &media_hex(),
            None,
            None,
        );
        let release = v3_release(
            ids,
            edition_id,
            vec![document],
            vec![media],
            vec![text_resource, translation_resource],
        );
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);
        blobs.insert(blob_path(&text_payload_digest), text_payload_bytes);
        blobs.insert(blob_path(&translation_digest), translation_bytes);
        if embed_media {
            blobs.insert(blob_path(&media_digest), MEDIA_BYTES.to_vec());
        }

        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    /// A rendition-only carrier whose audio rendition uses the real media
    /// digest and embeds the media bytes.
    fn audio_rendition_carrier(ids: &FixtureIds, edition_id: &str) -> BTreeMap<String, Vec<u8>> {
        let media_digest = format!("sha256:{}", media_hex());
        let media_blob = v3_blob_declaration(&media_digest, MEDIA_BYTES.len() as u64, true);
        let media = v3_media_rendition(
            "source",
            "audio",
            "audio/mpeg",
            &media_blob,
            Some("media-1"),
            &media_hex(),
            None,
            None,
        );
        let release = v3_release(ids, edition_id, vec![], vec![media], vec![]);
        let mut blobs = BTreeMap::new();
        blobs.insert("release.json".into(), canonical_bytes(&release));
        blobs.insert(blob_path(&media_digest), MEDIA_BYTES.to_vec());
        blobs
    }

    /// A rendition-only carrier whose rendition kind is `video` and whose
    /// media digest is the real media digest.
    fn video_rendition_carrier(ids: &FixtureIds, edition_id: &str) -> BTreeMap<String, Vec<u8>> {
        let media_digest = format!("sha256:{}", media_hex());
        let media_blob = v3_blob_declaration(&media_digest, MEDIA_BYTES.len() as u64, true);
        let media = v3_media_rendition(
            "source",
            "video",
            "video/mp4",
            &media_blob,
            Some("media-1"),
            &media_hex(),
            None,
            None,
        );
        let release = v3_release(ids, edition_id, vec![], vec![media], vec![]);
        let mut blobs = BTreeMap::new();
        blobs.insert("release.json".into(), canonical_bytes(&release));
        blobs.insert(blob_path(&media_digest), MEDIA_BYTES.to_vec());
        blobs
    }

    /// A release with a required document-text resource whose payload blob is
    /// absent from the carrier.
    fn missing_required_release(ids: &FixtureIds) -> (Value, BTreeMap<String, Vec<u8>>) {
        let mut descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &format!("sha256:{}", "3".repeat(64)),
            9,
            &ids.revision_id,
        );
        descriptor["payload_blob"]["embedded"] = json!(false);
        let resource = resource_entry(&descriptor, true);
        let release = v3_release(
            ids,
            "edition-missing-required",
            vec![],
            vec![],
            vec![resource],
        );
        let files = carrier_with_release(&release, BTreeMap::new());
        (release, files)
    }

    /// A release with a required base resource that depends on a declared
    /// optional resource whose payload is absent.
    fn broken_closure_release(ids: &FixtureIds) -> (Value, BTreeMap<String, Vec<u8>>) {
        let (_, text_bytes) = document_payload(TEXT, "en");
        let text_digest = sha256_id(&text_bytes);
        let missing_digest = format!("sha256:{}", "0".repeat(64));
        let mut missing_descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &missing_digest,
            42,
            &ids.revision_id,
        );
        missing_descriptor["payload_blob"]["embedded"] = json!(false);
        let missing_resource = resource_entry(&missing_descriptor, false);
        let missing_resource_id = missing_resource["resource_id"].as_str().unwrap().to_owned();

        let dependent_descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[&missing_resource_id],
            &text_digest,
            text_bytes.len() as u64,
            &ids.revision_id,
        );
        let dependent = resource_entry(&dependent_descriptor, true);
        let release = v3_release(
            ids,
            "edition-broken-closure",
            vec![],
            vec![],
            vec![dependent, missing_resource],
        );
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);

        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    /// A release with an optional known resource whose payload is absent.
    fn optional_missing_release(ids: &FixtureIds) -> (Value, BTreeMap<String, Vec<u8>>) {
        let (_, text_bytes) = document_payload(TEXT, "en");
        let text_digest = sha256_id(&text_bytes);
        let text_descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &text_digest,
            text_bytes.len() as u64,
            &ids.revision_id,
        );
        let text_resource = resource_entry(&text_descriptor, true);
        let text_resource_id = text_resource["resource_id"].as_str().unwrap().to_owned();

        let missing_descriptor = v3_assistance_descriptor(
            "translation",
            "listen.payload.translation.v1",
            &["zh-Hans"],
            &[&text_resource_id],
            &format!("sha256:{}", "1".repeat(64)),
            42,
            &ids.revision_id,
        );
        let missing_resource = resource_entry(&missing_descriptor, false);
        let release = v3_release(
            ids,
            "edition-optional-missing",
            vec![],
            vec![],
            vec![text_resource, missing_resource],
        );
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);

        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    /// A release with an optional unknown-kind opaque resource whose payload
    /// blob is absent from the carrier, or embedded when `present` is set.
    fn optional_opaque_release(
        ids: &FixtureIds,
        present: bool,
    ) -> (Value, BTreeMap<String, Vec<u8>>) {
        let (_, text_bytes) = document_payload(TEXT, "en");
        let text_digest = sha256_id(&text_bytes);
        let text_descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &text_digest,
            text_bytes.len() as u64,
            &ids.revision_id,
        );
        let text_resource = resource_entry(&text_descriptor, true);

        let opaque_bytes = b"opaque payload body".to_vec();
        let opaque_digest = if present {
            sha256_id(&opaque_bytes)
        } else {
            format!("sha256:{}", "2".repeat(64))
        };
        let opaque_descriptor = v3_assistance_descriptor(
            "future_analysis",
            "listen.payload.future-analysis.v1",
            &["zh-Hans"],
            &[],
            &opaque_digest,
            opaque_bytes.len() as u64,
            &ids.revision_id,
        );
        let opaque_resource = resource_entry(&opaque_descriptor, false);
        let release = v3_release(
            ids,
            "edition-opaque",
            vec![],
            vec![],
            vec![text_resource, opaque_resource],
        );
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);
        if present {
            blobs.insert(blob_path(&opaque_digest), opaque_bytes);
        }
        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    /// A release with two candidate translations for the same support
    /// language, distinguished by distinct payload content.
    fn ambiguous_translation_release(ids: &FixtureIds) -> (Value, BTreeMap<String, Vec<u8>>) {
        let (_, text_bytes) = document_payload(TEXT, "en");
        let text_digest = sha256_id(&text_bytes);
        let text_descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &text_digest,
            text_bytes.len() as u64,
            &ids.revision_id,
        );
        let text_resource = resource_entry(&text_descriptor, true);
        let text_resource_id = text_resource["resource_id"].as_str().unwrap().to_owned();

        let mut resources = vec![text_resource];
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);
        for text in ["第一版译文。", "第二版译文。"] {
            let (_, translation_bytes) = translation_payload("zh-Hans", &text_resource_id, text);
            let translation_digest = sha256_id(&translation_bytes);
            let translation_descriptor = v3_assistance_descriptor(
                "translation",
                "listen.payload.translation.v1",
                &["zh-Hans"],
                &[&text_resource_id],
                &translation_digest,
                translation_bytes.len() as u64,
                &ids.revision_id,
            );
            resources.push(resource_entry(&translation_descriptor, false));
            blobs.insert(blob_path(&translation_digest), translation_bytes);
        }
        let release = v3_release(ids, "edition-ambiguous", vec![], vec![], resources);

        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    /// A release with an optional translation candidate whose dependency is a
    /// declared optional resource with an absent payload.
    fn optional_broken_closure_release(ids: &FixtureIds) -> (Value, BTreeMap<String, Vec<u8>>) {
        let (_, text_bytes) = document_payload(TEXT, "en");
        let text_digest = sha256_id(&text_bytes);
        let text_descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &text_digest,
            text_bytes.len() as u64,
            &ids.revision_id,
        );
        let text_resource = resource_entry(&text_descriptor, true);
        let text_resource_id = text_resource["resource_id"].as_str().unwrap().to_owned();

        let missing_digest = format!("sha256:{}", "0".repeat(64));
        let mut missing_descriptor = v3_base_descriptor(
            "document_text",
            "listen.payload.document-text.v1",
            "en",
            &[],
            &missing_digest,
            42,
            &ids.revision_id,
        );
        missing_descriptor["payload_blob"]["embedded"] = json!(false);
        let missing_resource = resource_entry(&missing_descriptor, false);
        let missing_resource_id = missing_resource["resource_id"].as_str().unwrap().to_owned();

        let (_, translation_bytes) = translation_payload("zh-Hans", &text_resource_id, "译文。");
        let translation_digest = sha256_id(&translation_bytes);
        let translation_descriptor = v3_assistance_descriptor(
            "translation",
            "listen.payload.translation.v1",
            &["zh-Hans"],
            &[&text_resource_id, &missing_resource_id],
            &translation_digest,
            translation_bytes.len() as u64,
            &ids.revision_id,
        );
        let translation_resource = resource_entry(&translation_descriptor, false);
        let release = v3_release(
            ids,
            "edition-broken-optional-closure",
            vec![],
            vec![],
            vec![text_resource, missing_resource, translation_resource],
        );
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&text_digest), text_bytes);
        blobs.insert(blob_path(&translation_digest), translation_bytes);

        let files = carrier_with_release(&release, blobs);
        (release, files)
    }

    fn v3_composed_release(
        ids: &FixtureIds,
        edition_id: &str,
    ) -> (Value, BTreeMap<String, Vec<u8>>) {
        let (release, mut files) = text_only_release(ids, edition_id);

        let media_digest = format!("sha256:{}", media_hex());
        let source_media_blob = v3_blob_declaration(&media_digest, MEDIA_BYTES.len() as u64, false);
        let source_media = v3_media_rendition(
            "source",
            "audio",
            "audio/mpeg",
            &source_media_blob,
            Some("media-1"),
            &media_hex(),
            None,
            None,
        );

        let derived_bytes = b"listen fixture derived media".to_vec();
        let derived_digest = sha256_id(&derived_bytes);
        let derived_blob = v3_blob_declaration(&derived_digest, derived_bytes.len() as u64, true);
        let derived_media = v3_media_rendition(
            "derived",
            "audio",
            "audio/mpeg",
            &derived_blob,
            None,
            "fp-derived",
            Some(&v3_producer()),
            Some(&v3_compatibility()),
        );

        let mut release = release;
        release["media_renditions"] = json!([source_media, derived_media]);
        files.insert(blob_path(&derived_digest), derived_bytes);
        let files = carrier_with_release(&release, {
            files.remove("release.json");
            files
        });
        (release, files)
    }

    // ---------------------------------------------------------------------
    // v3 installation
    // ---------------------------------------------------------------------

    #[test]
    fn v3_install_prepares_candidate_only_edition() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, files) = text_only_release(&ids, "edition-v3-text");

        let view = install_ok(&setup, &material.id, &files);
        assert_eq!(view.release_id.as_str().len(), 71);
        assert_eq!(view.edition_id.as_str(), "edition-v3-text");
        assert!(!view.adopted);
        assert_eq!(view.resources.len(), 1);
        assert_eq!(
            view.resources[0].availability,
            PackageResourceAvailability::Available
        );
        assert_eq!(view.renditions.len(), 1);
        assert_eq!(view.renditions[0].kind, "document");
        assert!(view.renditions[0].available);
        assert_eq!(setup.package_lifecycle.installation_count(), 1);
        // Candidate-only: membership is never touched.
        assert_eq!(setup.materials.membership_calls(), 0);
    }

    #[test]
    fn v3_install_supports_source_and_derived_renditions() {
        let setup = setup();
        let (material, revision) = seed_mixed_media_material(
            &setup,
            &format!("sha256:{}", media_hex()),
            MediaAvailability::Available,
        );
        let ids = ids_of(&material, &revision);
        let (release, files) = v3_composed_release(&ids, "edition-v3-composed");

        let view = install_ok(&setup, &material.id, &files);
        assert_eq!(view.renditions.len(), 3);
        let document = view
            .renditions
            .iter()
            .find(|rendition| rendition.kind == "document")
            .expect("document rendition");
        assert!(document.available);
        // The source media blob is referenced, not embedded: availability
        // comes from the bound Material media asset, which is available.
        let source_media_id = release["media_renditions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|entry| entry["origin"] == "source")
            .unwrap()["rendition_id"]
            .as_str()
            .unwrap()
            .to_owned();
        let source_media = view
            .renditions
            .iter()
            .find(|rendition| rendition.rendition_id.as_str() == source_media_id)
            .expect("source media rendition");
        assert!(source_media.available);
        // The installed facts keep the origin and producer snapshot.
        let stored = setup
            .package_lifecycle
            .stored_installations(&material.id)
            .pop()
            .expect("stored installation");
        let derived = stored
            .renditions
            .iter()
            .find(|rendition| rendition.origin == RenditionOrigin::Derived)
            .expect("derived rendition fact");
        assert_eq!(derived.kind, "media");
        assert_eq!(
            derived.producer.as_ref().expect("producer").tool_id,
            "listen-gen"
        );
        let source = stored
            .renditions
            .iter()
            .find(|rendition| {
                rendition.origin == RenditionOrigin::Source && rendition.kind == "media"
            })
            .expect("source media rendition fact");
        assert_eq!(
            source.media_id.as_ref().expect("media id").as_str(),
            "media-1"
        );
    }

    #[test]
    fn v3_install_rejects_unmatched_source_document_rendition() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, files) = text_only_release(&ids, "edition-v3-text");
        // Swap in a document rendition that does not match the Material text.
        // The blob is referenced (not embedded) so inspection passes and the
        // install-time binding check is the one that rejects the release.
        let other_bytes = b"unrelated text".to_vec();
        let other_digest = sha256_id(&other_bytes);
        let other_blob = v3_blob_declaration(&other_digest, other_bytes.len() as u64, false);
        let document = v3_document_rendition(
            "source",
            "text/plain",
            Some("en"),
            &other_blob,
            Some("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            None,
            None,
        );
        let mut release: Value = serde_json::from_slice(&files["release.json"]).unwrap();
        release["document_renditions"] = json!([document]);
        // The original text blob is no longer referenced by any rendition or
        // resource; drop it so the carrier inventory stays exact.
        let mut files = files;
        files.remove(&blob_path(&sha256_id(TEXT.as_bytes())));
        files.insert("release.json".to_owned(), canonical_bytes(&release));

        let error = install_err(&setup, &material.id, &files);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 source document rendition does not match a bound material document rendition"
        ));
    }

    #[test]
    fn v3_install_rejects_source_document_language_contradiction() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, mut files) = text_only_release(&ids, "edition-v3-text");
        let mut release: Value = serde_json::from_slice(&files["release.json"]).unwrap();
        let entry = release["document_renditions"][0].clone();
        let identity = json!({
            "media_type": entry["media_type"],
            "language": "zh-Hans",
            "text_blob": entry["text_blob"],
        });
        release["document_renditions"][0]["language"] = json!("zh-Hans");
        release["document_renditions"][0]["rendition_id"] =
            json!(sha256_id(&canonical_bytes(&identity)));
        files.insert("release.json".to_owned(), canonical_bytes(&release));

        let error = install_err(&setup, &material.id, &files);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 source document rendition contradicts the material's declared language"
        ));
    }

    #[test]
    fn v3_install_rejects_unmatched_source_media_rendition() {
        let setup = setup();
        let (material, revision) =
            seed_mixed_media_material(&setup, &media_hex(), MediaAvailability::Available);
        let ids = ids_of(&material, &revision);
        let (release, mut files) = text_only_release(&ids, "edition-v3-text");
        let mut release = release;
        let media_blob = v3_blob_declaration(&format!("sha256:{}", "c".repeat(64)), 100, false);
        let media = v3_media_rendition(
            "source",
            "audio",
            "audio/mpeg",
            &media_blob,
            Some("media-1"),
            "unrelated-fingerprint",
            None,
            None,
        );
        release["media_renditions"] = json!([media]);
        files.insert("release.json".to_owned(), canonical_bytes(&release));
        let error = install_err(&setup, &material.id, &files);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 media rendition does not match a bound material media rendition"
        ));
    }

    #[test]
    fn v3_install_rejects_derived_media_without_producer_facts() {
        let setup = setup();
        let (material, revision) =
            seed_mixed_media_material(&setup, &media_hex(), MediaAvailability::Available);
        let ids = ids_of(&material, &revision);
        let (release, _) = text_only_release(&ids, "edition-v3-text");
        let mut release = release;
        let derived_bytes = b"listen fixture derived media".to_vec();
        let derived_digest = sha256_id(&derived_bytes);
        let derived_blob = v3_blob_declaration(&derived_digest, derived_bytes.len() as u64, true);
        let derived = v3_media_rendition(
            "derived",
            "audio",
            "audio/mpeg",
            &derived_blob,
            None,
            "fp-derived",
            None,
            None,
        );
        release["media_renditions"] = json!([derived]);
        let mut blobs = BTreeMap::new();
        blobs.insert(blob_path(&derived_digest), derived_bytes);
        let files = carrier_with_release(&release, blobs);

        let error = install_err(&setup, &material.id, &files);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 carrier is invalid"
        ));
    }

    #[test]
    fn v3_install_rejects_stale_material_revision() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = FixtureIds {
            material_id: material.id.as_str().to_owned(),
            revision_id: revision.id.as_str().to_owned(),
        };
        let (_, files) = text_only_release(&ids, "edition-v3-text");
        // Append a newer revision to the same Material so the package binds
        // the stale revision.
        let second = domain::Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                Some(language("en")),
                "Second revision text.",
                None,
                None,
                None,
            )
            .expect("valid document rendition"),
        );
        let appended =
            MaterialRevision::new(material.id.clone(), "Material", Vec::new(), vec![second], 2)
                .expect("valid revision");
        setup.materials.append_revision_fake(appended, 2);
        let error = install_err(&setup, &material.id, &files);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 material revision does not match the material's current revision"
        ));
    }

    // ---------------------------------------------------------------------
    // Installation tests
    // ---------------------------------------------------------------------

    #[test]
    fn install_prepares_candidate_only_edition() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (release, blobs) = text_only_release(&ids, "edition-1");
        assert_eq!(release["schema"], RELEASE_SCHEMA_V3);

        let view = install_ok(&setup, &material.id, &blobs);

        assert_eq!(view.material_id, material.id);
        assert_eq!(view.material_revision_id, revision.id);
        assert_eq!(view.edition_id.as_str(), "edition-1");
        assert_eq!(view.title, EDITION_TITLE);
        assert_eq!(view.target_language, language("en"));
        assert_eq!(view.support_languages, vec![language("zh-Hans")]);
        assert!(!view.adopted);
        assert!(view.adopted_at_ms.is_none());
        assert_eq!(view.resources.len(), 1);
        let resource = &view.resources[0];
        assert_eq!(resource.kind, "document_text");
        assert_eq!(resource.role, PackageResourceRole::Base);
        assert!(resource.required);
        assert_eq!(
            resource.availability,
            PackageResourceAvailability::Available
        );
        assert_eq!(resource.review_status, PackageReviewStatus::HumanReviewed);
        assert_eq!(resource.content_language, Some(language("en")));
        assert_eq!(view.renditions.len(), 1);
        assert_eq!(view.renditions[0].kind, "document");
        assert!(view.renditions[0].available);

        assert_eq!(setup.package_lifecycle.installation_count(), 1);
        assert_eq!(
            setup.package_lifecycle.get_adoption(&material.id).unwrap(),
            None,
            "installation must not adopt"
        );
    }

    #[test]
    fn install_persists_exact_known_payload_bytes_at_the_repository_seam() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");
        let view = install_ok(&setup, &material.id, &blobs);

        let (_, expected_bytes) = document_payload(TEXT, "en");
        let stored = setup
            .package_lifecycle
            .stored_payloads(&material.id, &view.release_id)
            .expect("payloads are stored durably");
        assert_eq!(stored.len(), 1);
        let payload = &stored[0];
        assert_eq!(payload.resource_id, view.resources[0].resource_id);
        assert_eq!(payload.kind, "document_text");
        assert_eq!(payload.schema, "listen.payload.document-text.v1");
        assert_eq!(payload.digest, sha256_id(&expected_bytes));
        assert_eq!(payload.size_bytes, expected_bytes.len() as u64);
        assert_eq!(
            payload.bytes, expected_bytes,
            "the exact validated carrier bytes reach the seam and are retained"
        );
    }

    #[test]
    fn install_preserves_retained_and_temporary_material_membership() {
        let setup = setup();
        let (retained_material, retained_revision) =
            seed_text_material_with_text(&setup, true, "Retained material text.");
        let (temporary_material, temporary_revision) =
            seed_text_material_with_text(&setup, false, "Temporary material text.");
        let retained_ids = ids_of(&retained_material, &retained_revision);
        let temporary_ids = ids_of(&temporary_material, &temporary_revision);
        assert_ne!(
            retained_material.id, temporary_material.id,
            "distinct content yields distinct materials"
        );

        let (retained_release, retained_blobs) = text_only_release_with_text(
            &retained_ids,
            "edition-retained",
            "Retained material text.",
        );
        let (temporary_release, temporary_blobs) =
            text_only_release_with_text(&temporary_ids, "edition-temp", "Temporary material text.");
        assert_ne!(
            retained_release["edition"]["edition_id"],
            temporary_release["edition"]["edition_id"]
        );

        install_ok(&setup, &retained_material.id, &retained_blobs);
        install_ok(&setup, &temporary_material.id, &temporary_blobs);

        let retained_after = setup
            .materials
            .get_material(&retained_material.id)
            .unwrap()
            .expect("material exists");
        let temporary_after = setup
            .materials
            .get_material(&temporary_material.id)
            .unwrap()
            .expect("material exists");
        assert!(retained_after.retained_at_ms.is_some());
        assert!(temporary_after.retained_at_ms.is_none());
        assert_eq!(retained_after, retained_material);
        assert_eq!(temporary_after, temporary_material);
        assert_eq!(
            setup.materials.membership_calls(),
            0,
            "installation never touches material membership"
        );
    }

    #[test]
    fn install_never_mutates_adoption_or_active_selection() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");

        install_ok(&setup, &material.id, &blobs);

        assert_eq!(
            setup.package_lifecycle.get_adoption(&material.id).unwrap(),
            None
        );
        assert_eq!(setup.package_lifecycle.commit_calls(), 0);
        assert_eq!(setup.package_lifecycle.adoption_count(), 0);
        let after = setup
            .materials
            .get_material(&material.id)
            .unwrap()
            .expect("material exists");
        assert_eq!(after.current_revision_id, revision.id);
    }

    #[test]
    fn install_rejects_exact_material_id_mismatch() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let mut ids = ids_of(&material, &revision);
        ids.material_id = "some-other-material".into();
        let (_, blobs) = text_only_release(&ids, "edition-1");

        let error = install_err(&setup, &material.id, &blobs);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 material id does not match the target material"
        ));
        assert_eq!(setup.package_lifecycle.installation_count(), 0);
    }

    #[test]
    fn install_rejects_stale_material_revision_mismatch() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let mut ids = ids_of(&material, &revision);
        ids.revision_id = "stale-revision".into();
        let (_, blobs) = text_only_release(&ids, "edition-1");

        let error = install_err(&setup, &material.id, &blobs);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message
                    == "content package v3 material revision does not match the material's current revision"
        ));
    }

    #[test]
    fn install_rejects_media_kind_mismatch() {
        let setup = setup();
        let (material, revision) = seed_mixed_media_material(
            &setup,
            &format!("sha256:{}", media_hex()),
            MediaAvailability::Available,
        );
        let ids = ids_of(&material, &revision);
        let files = video_rendition_carrier(&ids, "edition-video");

        let error = install_err(&setup, &material.id, &files);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message
                    == "content package v3 media rendition does not match a bound material media rendition"
        ));
    }

    #[test]
    fn install_rejects_media_fingerprint_mismatch() {
        let setup = setup();
        let (material, revision) = seed_mixed_media_material(
            &setup,
            &format!("sha256:{}", "b".repeat(64)),
            MediaAvailability::Available,
        );
        let ids = ids_of(&material, &revision);
        let files = audio_rendition_carrier(&ids, "edition-media");

        let error = install_err(&setup, &material.id, &files);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message
                    == "content package v3 media rendition does not match a bound material media rendition"
        ));
    }

    #[test]
    fn install_accepts_referenced_media_satisfied_by_local_material_asset() {
        let setup = setup();
        let (material, revision) = seed_mixed_media_material(
            &setup,
            &format!("sha256:{}", media_hex()),
            MediaAvailability::Available,
        );
        let ids = ids_of(&material, &revision);
        let (_, blobs) = media_text_translation_release(&ids, false, "edition-media");
        let view = install_ok(&setup, &material.id, &blobs);
        let media = view
            .renditions
            .iter()
            .find(|rendition| rendition.kind == "media")
            .expect("media rendition present");
        assert!(media.available);
    }

    #[test]
    fn install_accepts_embedded_media_with_matching_fingerprint() {
        let setup = setup();
        let (material, revision) = seed_mixed_media_material(
            &setup,
            &format!("sha256:{}", media_hex()),
            MediaAvailability::Available,
        );
        let ids = ids_of(&material, &revision);
        let (_, blobs) = media_text_translation_release(&ids, true, "edition-media");
        let view = install_ok(&setup, &material.id, &blobs);
        let media = view
            .renditions
            .iter()
            .find(|rendition| rendition.kind == "media")
            .expect("media rendition present");
        assert!(media.available);
    }

    #[test]
    fn install_accepts_bare_hex_material_fingerprint_as_normalized_match() {
        let setup = setup();
        let (material, revision) =
            seed_mixed_media_material(&setup, &media_hex(), MediaAvailability::Available);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = media_text_translation_release(&ids, true, "edition-media");
        let view = install_ok(&setup, &material.id, &blobs);
        let media = view
            .renditions
            .iter()
            .find(|rendition| rendition.kind == "media")
            .expect("media rendition present");
        assert!(media.available);
    }

    #[test]
    fn embedded_media_with_missing_bound_asset_is_never_reported_available() {
        let setup = setup();
        let (material, revision) = seed_mixed_media_material(
            &setup,
            &format!("sha256:{}", media_hex()),
            MediaAvailability::Missing,
        );
        let ids = ids_of(&material, &revision);
        let (_, blobs) = media_text_translation_release(&ids, true, "edition-media");
        let view = install_ok(&setup, &material.id, &blobs);

        let media = view
            .renditions
            .iter()
            .find(|rendition| rendition.kind == "media")
            .expect("media rendition present");
        assert!(
            !media.available,
            "media embedded in the temporary carrier never makes a rendition available \
             without a usable bound material asset"
        );
        let adopted = setup
            .use_cases
            .adopt_for_material(&material.id, &view.release_id)
            .expect("adoption still succeeds with an unavailable rendition");
        assert!(adopted.adopted);
        let plan = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");
        assert!(
            !plan.selected_rendition_ids.contains(&media.rendition_id),
            "unavailable renditions are never selected"
        );
    }

    #[test]
    fn install_rejects_document_text_mismatch() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = mismatched_text_release(&ids);

        let error = install_err(&setup, &material.id, &blobs);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message
                    == "content package v3 source document rendition does not match a bound material document rendition"
        ));
    }

    #[test]
    fn install_rejects_document_text_language_mismatch() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = mismatched_text_language_release(&ids);

        let error = install_err(&setup, &material.id, &blobs);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message
                    == "content package v3 source document rendition contradicts the material's declared language"
        ));
    }

    #[test]
    fn install_rejects_ambiguous_document_text_binding() {
        let setup = setup();
        let text_rendition = domain::Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                Some(language("en")),
                TEXT,
                None,
                None,
                None,
            )
            .expect("valid document rendition"),
        );
        let zh_rendition = domain::Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                Some(language("zh-Hans")),
                TEXT,
                None,
                None,
                None,
            )
            .expect("valid document rendition"),
        );
        let material_id = initial_material_id(&[], &[text_rendition.clone(), zh_rendition.clone()])
            .expect("deterministic id");
        let revision = MaterialRevision::new(
            material_id.clone(),
            "Material",
            Vec::new(),
            vec![text_rendition, zh_rendition],
            1,
        )
        .expect("valid revision");
        let material = LearningMaterial::new(&revision, None, 1, 1).expect("valid material");
        setup
            .materials
            .create_material(&material, &revision)
            .expect("material persists");
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");

        let error = install_err(&setup, &material.id, &blobs);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 source document rendition binding is ambiguous"
        ));
    }

    #[test]
    fn install_rejects_ambiguous_media_binding() {
        let setup = setup();
        let first = MediaRendition::new(
            RenditionOrigin::Source,
            MediaKind::Audio,
            "audio/mpeg",
            format!("sha256:{}", media_hex()),
            MediaAvailability::Available,
            Some(MediaId::parse("media-a").unwrap()),
            None,
            None,
            None,
            None,
        )
        .unwrap();
        let second = MediaRendition::new(
            RenditionOrigin::Source,
            MediaKind::Audio,
            "audio/mpeg",
            format!("sha256:{}", media_hex()),
            MediaAvailability::Available,
            Some(MediaId::parse("media-b").unwrap()),
            None,
            None,
            None,
            None,
        )
        .unwrap();
        let revision = MaterialRevision::new(
            LearningMaterialId::parse("material-ambiguous").unwrap(),
            "Material",
            Vec::new(),
            vec![
                domain::Rendition::Media(first),
                domain::Rendition::Media(second),
            ],
            1,
        )
        .unwrap();
        let material = LearningMaterial {
            id: LearningMaterialId::parse("material-ambiguous").unwrap(),
            current_revision_id: revision.id.clone(),
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        setup
            .materials
            .seed_material(material.clone(), revision.clone());
        let ids = ids_of(&material, &revision);
        let files = audio_rendition_carrier(&ids, "edition-media");

        let error = install_err(&setup, &material.id, &files);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 media rendition binding is ambiguous"
        ));
    }

    #[test]
    fn install_rejects_missing_required_payload() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = missing_required_release(&ids);

        let error = install_err(&setup, &material.id, &blobs);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "content package v3 required resource payload is unavailable"
        ));
    }

    #[test]
    fn install_accepts_optional_missing_payload_as_an_availability_fact() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = optional_missing_release(&ids);

        let view = install_ok(&setup, &material.id, &blobs);
        let translation = view
            .resources
            .iter()
            .find(|resource| resource.kind == "translation")
            .expect("translation fact");
        assert_eq!(
            translation.availability,
            PackageResourceAvailability::Missing
        );
        let document = view
            .resources
            .iter()
            .find(|resource| resource.kind == "document_text")
            .expect("document fact");
        assert_eq!(
            document.availability,
            PackageResourceAvailability::Available
        );

        let adopted = setup
            .use_cases
            .adopt_for_material(&material.id, &view.release_id)
            .expect("optional missing resource does not block adoption");
        assert!(adopted.adopted);
    }

    #[test]
    fn missing_optional_resources_have_no_stored_body_and_stay_explicitly_unavailable() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = optional_missing_release(&ids);
        let view = install_ok(&setup, &material.id, &blobs);

        let translation = view
            .resources
            .iter()
            .find(|resource| resource.kind == "translation")
            .expect("translation fact");
        assert_eq!(
            translation.availability,
            PackageResourceAvailability::Missing
        );
        let stored = setup
            .package_lifecycle
            .stored_payloads(&material.id, &view.release_id)
            .expect("stored payloads");
        assert_eq!(
            stored.len(),
            1,
            "only the present document payload is stored"
        );
        assert_eq!(
            stored[0].resource_id, view.resources[0].resource_id,
            "the missing optional resource has no stored body"
        );
    }

    #[test]
    fn install_accepts_optional_opaque_resource_as_verified_metadata() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = optional_opaque_release(&ids, false);

        let view = install_ok(&setup, &material.id, &blobs);
        let opaque = view
            .resources
            .iter()
            .find(|resource| resource.kind == "future_analysis")
            .expect("opaque fact");
        assert_eq!(opaque.availability, PackageResourceAvailability::Opaque);

        let adopted = setup
            .use_cases
            .adopt_for_material(&material.id, &view.release_id)
            .expect("optional opaque resource does not block adoption");
        assert!(adopted.adopted);
        let plan = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");
        assert!(
            plan.selected_resource_ids
                .iter()
                .all(|resource_id| resource_id != &opaque.resource_id),
            "opaque resources are never selected"
        );
    }

    #[test]
    fn install_retains_present_optional_opaque_payload_bytes_exactly() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = optional_opaque_release(&ids, true);
        let view = install_ok(&setup, &material.id, &blobs);

        let opaque = view
            .resources
            .iter()
            .find(|resource| resource.kind == "future_analysis")
            .expect("opaque fact");
        assert_eq!(opaque.availability, PackageResourceAvailability::Opaque);
        let stored = setup
            .package_lifecycle
            .stored_payloads(&material.id, &view.release_id)
            .expect("stored payloads");
        let opaque_payload = stored
            .iter()
            .find(|payload| payload.resource_id == opaque.resource_id)
            .expect("the present opaque body is retained");
        assert_eq!(opaque_payload.bytes, b"opaque payload body");
        assert_eq!(opaque_payload.digest, sha256_id(b"opaque payload body"));
        assert_eq!(
            opaque_payload.size_bytes,
            b"opaque payload body".len() as u64
        );
        assert_eq!(opaque_payload.kind, "future_analysis");
        assert_eq!(
            opaque_payload.schema, "listen.payload.future-analysis.v1",
            "the opaque body stays associated with its declared schema"
        );
    }

    #[test]
    fn install_rejects_required_dependency_closure_failure() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = broken_closure_release(&ids);

        let error = install_err(&setup, &material.id, &blobs);
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message
                    == "content package v3 required resource dependency closure is unavailable"
        ));
    }

    #[test]
    fn install_is_idempotent_and_returns_the_equal_existing_installation() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");

        let first = install_ok(&setup, &material.id, &blobs);
        let second = install_ok(&setup, &material.id, &blobs);

        assert_eq!(
            second.installed_at_ms, first.installed_at_ms,
            "an idempotent reinstall preserves the original installation timestamp"
        );
        assert_eq!(first, second);
        assert_eq!(setup.package_lifecycle.installation_count(), 1);
        assert_eq!(
            setup.package_lifecycle.save_calls(),
            2,
            "the retry returns the equal existing installation"
        );
    }

    #[test]
    fn save_fails_closed_on_unequal_facts_or_bytes_for_the_same_identity() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");
        let view = install_ok(&setup, &material.id, &blobs);
        let stored = setup
            .package_lifecycle
            .get_installation(&material.id, &view.release_id)
            .unwrap()
            .expect("installed");

        // Unequal facts under the same (material, release) identity fail
        // closed and leave the existing installation untouched.
        let mut different_facts = stored.clone();
        different_facts.resources[0].kind = "word_timeline".into();
        let error = setup
            .package_lifecycle
            .save_installation(&PreparedPackageInstallation {
                installation: different_facts,
                payloads: Vec::new(),
            })
            .expect_err("unequal facts");
        assert!(matches!(error, ApplicationError::Repository(_)));
        assert_eq!(
            setup
                .package_lifecycle
                .get_installation(&material.id, &view.release_id)
                .unwrap(),
            Some(stored.clone()),
            "the unequal retry changes nothing"
        );

        // Unequal payload bytes under the same identity fail closed too.
        let mut tampered_payloads = setup
            .package_lifecycle
            .stored_payloads(&material.id, &view.release_id)
            .unwrap();
        let mut tampered = tampered_payloads[0].clone();
        let mut bytes = tampered.bytes.clone();
        *bytes.last_mut().unwrap() ^= 0x01;
        tampered.bytes = bytes;
        tampered_payloads[0] = tampered;
        let error = setup
            .package_lifecycle
            .save_installation(&PreparedPackageInstallation {
                installation: stored.clone(),
                payloads: tampered_payloads,
            })
            .expect_err("unequal bytes");
        assert!(matches!(error, ApplicationError::Repository(_)));
        assert_eq!(
            setup
                .package_lifecycle
                .get_installation(&material.id, &view.release_id)
                .unwrap(),
            Some(stored),
            "the unequal-byte retry changes nothing"
        );
    }

    #[test]
    fn reinstall_of_adopted_release_reports_existing_adoption_evidence() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");
        let installed = install_ok(&setup, &material.id, &blobs);
        assert!(!installed.adopted, "a fresh installation is never adopted");

        let adopted = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect("adoption succeeds");
        let original_adopted_at = adopted.adopted_at_ms.expect("adoption timestamp");

        let reinstalled = install_ok(&setup, &material.id, &blobs);
        assert!(
            reinstalled.adopted,
            "reinstalling an adopted equal release reports its existing adoption evidence"
        );
        assert_eq!(reinstalled.adopted_at_ms, Some(original_adopted_at));
        assert_eq!(
            reinstalled.installed_at_ms, installed.installed_at_ms,
            "the equal retry preserves the original installation timestamp"
        );
        assert_eq!(
            setup.package_lifecycle.commit_calls(),
            1,
            "reinstalling never triggers another adoption commit"
        );
        assert_eq!(setup.package_lifecycle.installation_count(), 1);
    }

    #[test]
    fn install_errors_never_contain_the_supplied_package_path() {
        let setup = setup();
        let (material, _) = seed_text_material(&setup, false);
        let directory = TestDirectory::new();
        let path = directory.path().join("nested").join("missing.listenpkg");
        fs::create_dir_all(&path).unwrap();

        let error = setup
            .use_cases
            .install_for_material(&material.id, &path)
            .expect_err("empty carrier fails inspection");
        let path_text = path.to_str().unwrap();
        assert!(
            !error.to_string().contains(path_text),
            "error display must not expose the local package path: {error}"
        );
        assert!(
            !format!("{error:?}").contains(path_text),
            "error debug must not expose the local package path: {error:?}"
        );
        assert!(matches!(
            error,
            ApplicationError::Invalid(message) if message == "content package v3 is missing release.json"
        ));
    }

    #[test]
    fn install_unsupported_release_schema_is_a_stable_error() {
        let setup = setup();
        let (material, _) = seed_text_material(&setup, false);
        let directory = TestDirectory::new();
        fs::write(
            directory.path().join("release.json"),
            r#"{"schema":"listen.content-package.release.v99","resources":[]}"#,
        )
        .unwrap();

        let error = setup
            .use_cases
            .install_for_material(&material.id, directory.path())
            .expect_err("unsupported schema fails");
        assert!(matches!(
            error,
            ApplicationError::Invalid(message) if message == "content package v3 carrier is invalid"
        ));
    }

    #[test]
    fn errors_and_views_never_leak_payloads_or_manifests() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);

        // A rejected carrier's payload content never reaches the error
        // surface, even when the payload is the reason for rejection.
        let (_, mismatched_blobs) = mismatched_text_release(&ids);
        let error = install_err(&setup, &material.id, &mismatched_blobs);
        assert!(
            !error.to_string().contains("Different text entirely."),
            "error display must not expose payload content: {error}"
        );
        assert!(
            !format!("{error:?}").contains("Different text entirely."),
            "error debug must not expose payload content: {error:?}"
        );

        // Installed views expose no payload content, manifest, or path.
        let (_, blobs) = text_only_release(&ids, "edition-1");
        let view = install_ok(&setup, &material.id, &blobs);
        let view_debug = format!("{view:?}");
        assert!(
            !view_debug.contains(TEXT),
            "views must not expose payload content: {view_debug}"
        );
        assert!(!view_debug.contains("release.json"));
        assert!(!view_debug.contains("blobs/"));

        // The domain facts persist without any payload bytes.
        let stored = setup
            .package_lifecycle
            .get_installation(&material.id, &view.release_id)
            .unwrap()
            .expect("installed");
        let facts_debug = format!("{stored:?}");
        assert!(!facts_debug.contains(TEXT));
    }

    // ---------------------------------------------------------------------
    // Listing and adoption tests
    // ---------------------------------------------------------------------

    #[test]
    fn carrier_deletion_after_install_still_lists_and_adopts_from_stored_state() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");

        let directory = TestDirectory::new();
        let path = directory.path().to_path_buf();
        for (name, bytes) in &blobs {
            let carrier_path = path.join(name);
            fs::create_dir_all(carrier_path.parent().unwrap()).unwrap();
            fs::write(carrier_path, bytes).unwrap();
        }
        let view = setup
            .use_cases
            .install_for_material(&material.id, &path)
            .expect("installation succeeds");
        fs::remove_dir_all(&path).expect("source carrier deleted");
        assert!(!path.exists(), "the source carrier is gone");

        let listed = setup
            .use_cases
            .list_editions(&material.id)
            .expect("listing works from stored state alone");
        assert_eq!(listed.len(), 1);
        assert_eq!(listed[0].release_id, view.release_id);
        let adopted = setup
            .use_cases
            .adopt_for_material(&material.id, &view.release_id)
            .expect("adoption works from stored state alone");
        assert!(adopted.adopted);
        let plan = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");
        assert_eq!(plan.release_id, view.release_id);
    }

    #[test]
    fn list_fails_when_current_revision_is_missing() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");
        install_ok(&setup, &material.id, &blobs);

        setup.materials.corrupt_current_revision(
            &material.id,
            MaterialRevisionId::parse("missing-revision").unwrap(),
        );
        let error = setup
            .use_cases
            .list_editions(&material.id)
            .expect_err("missing current revision");
        assert!(matches!(
            error,
            ApplicationError::Repository(message) if message == "current revision is missing"
        ));
    }

    #[test]
    fn list_fails_when_current_revision_belongs_to_another_material() {
        let setup = setup();
        let (material, revision) = seed_text_material_with_text(&setup, false, "Material A text.");
        let (other, other_revision) =
            seed_text_material_with_text(&setup, false, "Material B text.");
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release_with_text(&ids, "edition-1", "Material A text.");
        install_ok(&setup, &material.id, &blobs);

        setup
            .materials
            .corrupt_current_revision(&material.id, other_revision.id.clone());
        assert_ne!(other.id, material.id);
        let error = setup
            .use_cases
            .list_editions(&material.id)
            .expect_err("cross-material pointer");
        assert!(matches!(
            error,
            ApplicationError::Repository(message)
                if message == "current revision belongs to another material"
        ));
    }

    #[test]
    fn adopt_fails_when_current_revision_is_missing_without_commit() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");
        let installed = install_ok(&setup, &material.id, &blobs);

        setup.materials.corrupt_current_revision(
            &material.id,
            MaterialRevisionId::parse("missing-revision").unwrap(),
        );
        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect_err("missing current revision");
        assert!(matches!(
            error,
            ApplicationError::Repository(message) if message == "current revision is missing"
        ));
        assert_eq!(
            setup.package_lifecycle.commit_calls(),
            0,
            "a missing current revision never reaches the adoption commit"
        );
        assert_eq!(
            setup.package_lifecycle.get_adoption(&material.id).unwrap(),
            None
        );
    }

    #[test]
    fn adopt_fails_on_cross_material_pointer_without_commit_and_preserves_adoption() {
        let setup = setup();
        let (material, revision) = seed_text_material_with_text(&setup, false, "Material A text.");
        let (other, other_revision) =
            seed_text_material_with_text(&setup, false, "Material B text.");
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release_with_text(&ids, "edition-1", "Material A text.");
        let installed = install_ok(&setup, &material.id, &blobs);
        setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect("adoption succeeds before corruption");
        let previous = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");
        let commits_before = setup.package_lifecycle.commit_calls();

        setup
            .materials
            .corrupt_current_revision(&material.id, other_revision.id.clone());
        assert_ne!(other.id, material.id);
        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect_err("cross-material pointer");
        assert!(matches!(
            error,
            ApplicationError::Repository(message)
                if message == "current revision belongs to another material"
        ));
        assert_eq!(
            setup.package_lifecycle.commit_calls(),
            commits_before,
            "a cross-material pointer never reaches the adoption commit"
        );
        assert_eq!(
            setup.package_lifecycle.get_adoption(&material.id).unwrap(),
            Some(previous),
            "the existing adoption stays untouched"
        );
    }

    #[test]
    fn list_shows_two_editions_for_one_revision_with_adoption_evidence() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, first_blobs) = text_only_release(&ids, "edition-1");
        let (_, second_blobs) = text_only_release(&ids, "edition-2");
        let first = install_ok(&setup, &material.id, &first_blobs);
        let second = install_ok(&setup, &material.id, &second_blobs);
        assert_ne!(first.release_id, second.release_id);

        let adopted = setup
            .use_cases
            .adopt_for_material(&material.id, &first.release_id)
            .expect("adoption succeeds");

        let listed = setup
            .use_cases
            .list_editions(&material.id)
            .expect("list editions");
        assert_eq!(listed.len(), 2);
        let listed_first = listed
            .iter()
            .find(|view| view.release_id == first.release_id)
            .expect("first edition listed");
        assert!(listed_first.adopted);
        assert_eq!(listed_first.adopted_at_ms, adopted.adopted_at_ms);
        let listed_second = listed
            .iter()
            .find(|view| view.release_id == second.release_id)
            .expect("second edition listed");
        assert!(!listed_second.adopted);
        assert!(listed_second.adopted_at_ms.is_none());
    }

    #[test]
    fn adopt_text_only_edition_without_timeline_is_valid() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-text-only");
        let installed = install_ok(&setup, &material.id, &blobs);

        let view = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect("text-only adoption succeeds");
        assert!(view.adopted);
        assert!(view.adopted_at_ms.is_some());
        assert_eq!(view.release_id, installed.release_id);
        assert_eq!(setup.package_lifecycle.commit_calls(), 1);

        let plan = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");
        assert_eq!(
            plan.selected_resource_ids,
            vec![view.resources[0].resource_id.clone()],
            "the text-only edition selects its single document"
        );
        assert_eq!(plan.material_id, material.id);
        assert_eq!(plan.material_revision_id, revision.id);
    }

    #[test]
    fn adopt_produces_coherent_media_resource_plan() {
        let setup = setup();
        let (material, revision) = seed_mixed_media_material(
            &setup,
            &format!("sha256:{}", media_hex()),
            MediaAvailability::Available,
        );
        let ids = ids_of(&material, &revision);
        let (_, blobs) = media_text_translation_release(&ids, true, "edition-media");
        let installed = install_ok(&setup, &material.id, &blobs);
        assert_eq!(installed.resources.len(), 2);
        assert_eq!(installed.renditions.len(), 2);

        let view = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect("coherent adoption succeeds");
        assert!(view.adopted);

        let plan = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");
        assert_eq!(plan.selected_resource_ids.len(), 2);
        assert_eq!(plan.selected_rendition_ids.len(), 2);
        assert_eq!(plan.exclusive_selections.len(), 2);
        assert_eq!(
            plan.exclusive_selections[0].family,
            "exclusive:document_text"
        );
        assert_eq!(plan.exclusive_selections[1].family, "translation:zh-hans");
        for rendition in &installed.renditions {
            assert!(
                plan.selected_rendition_ids
                    .contains(&rendition.rendition_id),
                "every available rendition is selected"
            );
        }
    }

    #[test]
    fn adopt_rejects_absent_installation() {
        let setup = setup();
        let (material, _) = seed_text_material(&setup, false);
        let error = setup
            .use_cases
            .adopt_for_material(
                &material.id,
                &PackageReleaseId::parse("sha256:missing").unwrap(),
            )
            .expect_err("absent installation");
        assert!(matches!(
            error,
            ApplicationError::NotFound("package release installation")
        ));
    }

    #[test]
    fn adopt_rejects_stale_revision_installation() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");
        let installed = install_ok(&setup, &material.id, &blobs);

        let next_rendition = domain::Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                Some(language("en")),
                "Second revision.",
                None,
                None,
                None,
            )
            .expect("valid document rendition"),
        );
        let next_revision = MaterialRevision::new(
            material.id.clone(),
            "Material v2",
            Vec::new(),
            vec![next_rendition],
            2,
        )
        .expect("valid revision");
        setup.materials.append_revision_fake(next_revision, 2);

        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect_err("stale installation");
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "package release is installed for a stale material revision"
        ));
    }

    #[test]
    fn adopt_rejects_ambiguous_exclusive_resource_family() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = ambiguous_translation_release(&ids);
        let installed = install_ok(&setup, &material.id, &blobs);

        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect_err("ambiguous family");
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message
                    == "package release has multiple candidates in an exclusive resource family"
        ));
        assert_eq!(
            setup.package_lifecycle.get_adoption(&material.id).unwrap(),
            None,
            "a rejected adoption never commits"
        );
    }

    #[test]
    fn adopt_rejects_broken_dependency_closure() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = optional_broken_closure_release(&ids);
        let installed = install_ok(&setup, &material.id, &blobs);

        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect_err("broken closure");
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "package release resource dependency closure is broken"
        ));
        assert_eq!(
            setup.package_lifecycle.get_adoption(&material.id).unwrap(),
            None,
            "a rejected adoption never commits"
        );
    }

    #[test]
    fn adopt_rejects_missing_required_candidate_in_durable_state() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        // A durable store may hold an installation whose required resource is
        // unavailable; adoption must revalidate from the immutable facts.
        let installation = domain::PackageInstallation {
            release_id: PackageReleaseId::parse("sha256:stored").unwrap(),
            release_created_at_ms: 1,
            material_id: material.id.clone(),
            material_revision_id: revision.id.clone(),
            edition: domain::LearningEdition {
                edition_id: domain::LearningEditionId::parse("edition-stored").unwrap(),
                title: "Stored".into(),
                target_language: language("en"),
                support_languages: Vec::new(),
            },
            resources: vec![domain::PackageResourceFact {
                resource_id: "resource-missing-required".into(),
                kind: "document_text".into(),
                schema: "listen.payload.document-text.v1".into(),
                role: PackageResourceRole::Base,
                required: true,
                availability: PackageResourceAvailability::Missing,
                content_language: Some(language("en")),
                support_languages: Vec::new(),
                dependencies: Vec::new(),
                payload_digest: format!("sha256:{}", "a".repeat(64)),
                payload_size_bytes: 1,
                provenance: domain::PackageResourceProvenance {
                    created_at_ms: 1,
                    tool_id: "listen-gen".into(),
                    tool_version: "0.4.0".into(),
                    provider_id: None,
                    provider_version: None,
                    model_id: None,
                    model_version: None,
                    config_sha256: None,
                },
                review_status: PackageReviewStatus::Unreviewed,
                quality_warnings: Vec::new(),
            }],
            renditions: Vec::new(),
            installed_at_ms: 1,
        };
        setup
            .package_lifecycle
            .save_installation(&PreparedPackageInstallation {
                installation: installation.clone(),
                payloads: Vec::new(),
            })
            .expect("seam stores durable state");

        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &installation.release_id)
            .expect_err("missing required candidate");
        assert!(matches!(
            error,
            ApplicationError::Invalid(message)
                if message == "package release is missing a required resource"
        ));
    }

    #[test]
    fn adopt_is_idempotent_and_preserves_the_original_timestamp() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");
        let installed = install_ok(&setup, &material.id, &blobs);

        let first = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect("first adoption");
        let second = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect("re-adoption is idempotent");
        assert_eq!(second.adopted_at_ms, first.adopted_at_ms);
        assert_eq!(
            setup.package_lifecycle.commit_calls(),
            2,
            "the idempotent re-adoption must still reach the repository commit"
        );
        assert_eq!(setup.package_lifecycle.adoption_count(), 1);
    }

    #[test]
    fn adopt_fails_closed_when_the_stored_adoption_row_was_tampered() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, blobs) = text_only_release(&ids, "edition-1");
        let installed = install_ok(&setup, &material.id, &blobs);

        setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect("first adoption");
        let original = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");

        // Another valid-looking but unequal plan for the same release: the
        // seam must fail closed on the equal same-release retry instead of
        // returning the stored row, rewriting it, or repairing it.
        let mut tampered = original.clone();
        tampered.selected_resource_ids = vec!["resource-forged".into()];
        tampered.exclusive_selections = Vec::new();
        assert_ne!(tampered, original);
        setup
            .package_lifecycle
            .tamper_adoption(&material.id, tampered.clone());

        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &installed.release_id)
            .expect_err("tampered stored adoption must fail closed");
        assert_eq!(
            setup.package_lifecycle.commit_calls(),
            2,
            "the same-release retry must reach the repository commit"
        );
        assert!(matches!(
            &error,
            ApplicationError::Repository(message)
                if message == "package adoption plan conflicts with the stored adoption row"
        ));
        let error_text = error.to_string();
        assert!(
            !error_text.contains("resource-forged"),
            "the error must not leak selection content: {error_text}"
        );
        assert!(
            !error_text.contains(installed.release_id.as_str()),
            "the error must not leak release identities: {error_text}"
        );

        let stored = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("stored adoption still present");
        assert_eq!(
            stored, tampered,
            "the tampered row is never overwritten or repaired"
        );
        assert_eq!(
            stored.adopted_at_ms, original.adopted_at_ms,
            "the original adoption timestamp is preserved"
        );
    }

    #[test]
    fn adopt_switches_to_another_installed_release() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, first_blobs) = text_only_release(&ids, "edition-1");
        let (_, second_blobs) = text_only_release(&ids, "edition-2");
        let first = install_ok(&setup, &material.id, &first_blobs);
        let second = install_ok(&setup, &material.id, &second_blobs);

        setup
            .use_cases
            .adopt_for_material(&material.id, &first.release_id)
            .expect("first adoption");
        let adopted_second = setup
            .use_cases
            .adopt_for_material(&material.id, &second.release_id)
            .expect("switch");
        assert!(adopted_second.adopted);
        assert_eq!(adopted_second.release_id, second.release_id);

        let plan = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");
        assert_eq!(plan.release_id, second.release_id);
        assert_eq!(setup.package_lifecycle.commit_calls(), 2);
    }

    #[test]
    fn failed_switch_preserves_the_previous_adoption() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, first_blobs) = text_only_release(&ids, "edition-1");
        let (_, second_blobs) = text_only_release(&ids, "edition-2");
        let first = install_ok(&setup, &material.id, &first_blobs);
        let second = install_ok(&setup, &material.id, &second_blobs);

        setup
            .use_cases
            .adopt_for_material(&material.id, &first.release_id)
            .expect("first adoption");
        setup.package_lifecycle.set_fail_commit_adoption(true);
        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &second.release_id)
            .expect_err("commit fails");
        assert!(matches!(error, ApplicationError::Repository(_)));
        setup.package_lifecycle.set_fail_commit_adoption(false);

        let plan = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("previous adoption preserved");
        assert_eq!(
            plan.release_id, first.release_id,
            "a failed switch preserves the previous adoption"
        );
        let listed = setup
            .use_cases
            .list_editions(&material.id)
            .expect("list editions");
        let listed_first = listed
            .iter()
            .find(|view| view.release_id == first.release_id)
            .expect("first edition");
        assert!(listed_first.adopted);
        let listed_second = listed
            .iter()
            .find(|view| view.release_id == second.release_id)
            .expect("second edition");
        assert!(!listed_second.adopted);
    }

    #[test]
    fn commit_adoption_fails_atomically_when_selected_resources_lack_payload_backing() {
        let setup = setup();
        let (material, revision) = seed_text_material(&setup, false);
        let ids = ids_of(&material, &revision);
        let (_, first_blobs) = text_only_release(&ids, "edition-1");
        let (_, second_blobs) = text_only_release(&ids, "edition-2");
        let first = install_ok(&setup, &material.id, &first_blobs);
        setup
            .use_cases
            .adopt_for_material(&material.id, &first.release_id)
            .expect("first adoption");
        let previous = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("adoption exists");

        // A misbehaving adapter stores facts without their payload bodies; the
        // subsequent adoption commit must fail atomically and leave the
        // previous adoption intact.
        setup.package_lifecycle.set_drop_payloads(true);
        let second = install_ok(&setup, &material.id, &second_blobs);
        assert!(
            setup
                .package_lifecycle
                .stored_payloads(&material.id, &second.release_id)
                .expect("installation exists")
                .is_empty(),
            "the simulated adapter dropped the payload bodies"
        );
        let error = setup
            .use_cases
            .adopt_for_material(&material.id, &second.release_id)
            .expect_err("commit without backing fails");
        assert!(matches!(
            error,
            ApplicationError::Repository(message)
                if message == "package release selected resources lack durable payload backing"
        ));
        let after = setup
            .package_lifecycle
            .get_adoption(&material.id)
            .unwrap()
            .expect("previous adoption preserved");
        assert_eq!(
            after, previous,
            "a failed commit preserves the previous adoption atomically"
        );
        let listed = setup
            .use_cases
            .list_editions(&material.id)
            .expect("list editions");
        assert!(
            listed
                .iter()
                .find(|view| view.release_id == first.release_id)
                .expect("first edition")
                .adopted
        );
        assert!(
            !listed
                .iter()
                .find(|view| view.release_id == second.release_id)
                .expect("second edition")
                .adopted
        );
    }

    #[test]
    fn media_fingerprint_matches_normalizes_only_sha256_forms() {
        let hex = media_hex();
        assert!(media_fingerprint_equals(
            &format!("sha256:{hex}"),
            &format!("sha256:{hex}")
        ));
        assert!(media_fingerprint_equals(&hex, &format!("sha256:{hex}")));
        assert!(!media_fingerprint_equals(
            &hex.to_uppercase(),
            &format!("sha256:{hex}")
        ));
        assert!(!media_fingerprint_equals(
            "fp-xyz",
            &format!("sha256:{hex}")
        ));
        assert!(!media_fingerprint_equals(&hex, "fp-xyz"));
    }
}
