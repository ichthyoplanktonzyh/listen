//! Application use cases for durable learner-facing learning material.
//!
//! This module owns the material repository contract, the typed input DTOs,
//! and the use cases that orchestrate material creation, revision, retention,
//! and media resolution. Media renditions are resolved strictly through
//! [`MediaRepository`] so only authoritative kind, fingerprint, and
//! availability facts ever enter a material; no path is ever accepted or
//! exposed. No operation here copies, moves, or deletes filesystem content or
//! learner state: revisions, media bindings, and membership are durable
//! references, not content ownership.

use std::collections::HashSet;
use std::sync::Arc;

use domain::{
    DomainError, LearningMaterial, LearningMaterialId, MaterialRevision, MaterialRevisionId,
    MaterialShape, MediaId, MediaKind, MediaRendition, Rendition, RenditionOrigin, SourceAsset,
    SourceAssetBinding, initial_material_id,
};

use crate::{ApplicationError, MediaRepository, now_ms};

/// Input for one Source Asset: the exact byte facts of the learner's
/// authorized original source. The availability of a referenced asset is a
/// later, separate fact.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceAssetInput {
    pub media_type: String,
    pub byte_length: u64,
    pub sha256_digest: String,
    pub binding: SourceAssetBinding,
}

/// Input for one Media Rendition, resolving authoritative media facts from
/// the media repository.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaRenditionInput {
    pub media_id: MediaId,
}

/// Input for creating a learning material.
///
/// Retention semantics: `None` (default) and `Some(true)` retain the material
/// in the personal library; `Some(false)` marks the material temporary
/// (explicitly excluded from the library projection).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CreateLearningMaterial {
    pub title: String,
    pub source_assets: Vec<SourceAssetInput>,
    pub media_renditions: Vec<MediaRenditionInput>,
    pub retain: Option<bool>,
}

/// Input for appending a new revision to an existing learning material.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppendMaterialRevision {
    pub title: String,
    pub source_assets: Vec<SourceAssetInput>,
    pub media_renditions: Vec<MediaRenditionInput>,
}

/// A material together with a specific (typically the current) revision.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MaterialDetails {
    pub material: LearningMaterial,
    pub current_revision: MaterialRevision,
}

impl MaterialDetails {
    /// Composition shape of the carried revision.
    pub fn shape(&self) -> MaterialShape {
        self.current_revision.shape()
    }
}

/// Persistence contract for durable learning material.
///
/// Implementations must persist revisions, the material's current-revision
/// pointer, and media bindings atomically with
/// [`MaterialRepository::create_material`] and
/// [`MaterialRepository::append_revision`]: a successful call leaves the
/// revision readable, the material's `current_revision_id` advanced, and every
/// media rendition in the revision resolvable through
/// [`MaterialRepository::material_for_media`].
///
/// [`MaterialRepository::set_library_membership`] atomically synchronizes
/// membership to every media bound to the material, so the legacy media
/// library projection follows material membership; it never touches
/// revisions, bindings, or learner state.
///
/// No operation in this contract copies, moves, or deletes filesystem content
/// or learner state.
pub trait MaterialRepository: Send + Sync {
    /// Atomically persists the initial revision, the material's current
    /// pointer, and the revision's media bindings. Retries for equal content
    /// converge idempotently on the same material and revision.
    fn create_material(
        &self,
        material: &LearningMaterial,
        revision: &MaterialRevision,
    ) -> Result<LearningMaterial, ApplicationError>;

    /// Atomically persists a new revision, advances the material's current
    /// pointer, and records any new media bindings. Preserves the material's
    /// `created_at_ms` and membership (`retained_at_ms`). Retries that repeat
    /// the already-current revision converge idempotently.
    fn append_revision(
        &self,
        material_id: &LearningMaterialId,
        revision: &MaterialRevision,
        updated_at_ms: u64,
    ) -> Result<LearningMaterial, ApplicationError>;

    fn get_material(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Option<LearningMaterial>, ApplicationError>;

    fn get_revision(
        &self,
        revision_id: &MaterialRevisionId,
    ) -> Result<Option<MaterialRevision>, ApplicationError>;

    fn list_retained_materials(&self) -> Result<Vec<LearningMaterial>, ApplicationError>;

    /// Sets or clears personal-library membership, atomically synchronizing
    /// membership to all media bound to the material. Idempotent by design.
    fn set_library_membership(
        &self,
        material_id: &LearningMaterialId,
        retained_at_ms: Option<u64>,
        updated_at_ms: u64,
    ) -> Result<LearningMaterial, ApplicationError>;

    fn material_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Option<LearningMaterial>, ApplicationError>;

    /// Updates the stored availability fact of one Source Asset of the
    /// material's current revision. Returns the material's current revision
    /// with the updated fact, or `None` when the asset does not belong to the
    /// current revision. Availability never participates in revision identity,
    /// so this is a fact update, not a new revision.
    fn set_source_asset_availability(
        &self,
        material_id: &LearningMaterialId,
        source_asset_id: &domain::SourceAssetId,
        availability: domain::SourceAssetAvailability,
    ) -> Result<Option<MaterialRevision>, ApplicationError>;
}

/// Durable learning material requires configured persistence: without a
/// repository every operation errors with the same not-configured message, so
/// an unconfigured `AppServices` can never silently drop content or present a
/// material as persisted.
pub(crate) struct DisabledMaterialRepository;

impl DisabledMaterialRepository {
    fn disabled() -> ApplicationError {
        ApplicationError::Repository("learning material repository is not configured".into())
    }
}

impl MaterialRepository for DisabledMaterialRepository {
    fn create_material(
        &self,
        _material: &LearningMaterial,
        _revision: &MaterialRevision,
    ) -> Result<LearningMaterial, ApplicationError> {
        Err(Self::disabled())
    }

    fn append_revision(
        &self,
        _material_id: &LearningMaterialId,
        _revision: &MaterialRevision,
        _updated_at_ms: u64,
    ) -> Result<LearningMaterial, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_material(
        &self,
        _material_id: &LearningMaterialId,
    ) -> Result<Option<LearningMaterial>, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_revision(
        &self,
        _revision_id: &MaterialRevisionId,
    ) -> Result<Option<MaterialRevision>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_retained_materials(&self) -> Result<Vec<LearningMaterial>, ApplicationError> {
        Err(Self::disabled())
    }

    fn set_library_membership(
        &self,
        _material_id: &LearningMaterialId,
        _retained_at_ms: Option<u64>,
        _updated_at_ms: u64,
    ) -> Result<LearningMaterial, ApplicationError> {
        Err(Self::disabled())
    }

    fn material_for_media(
        &self,
        _media_id: &MediaId,
    ) -> Result<Option<LearningMaterial>, ApplicationError> {
        Err(Self::disabled())
    }

    fn set_source_asset_availability(
        &self,
        _material_id: &LearningMaterialId,
        _source_asset_id: &domain::SourceAssetId,
        _availability: domain::SourceAssetAvailability,
    ) -> Result<Option<MaterialRevision>, ApplicationError> {
        Err(Self::disabled())
    }
}

/// Use cases that own learning-material creation, revision, retention, and
/// media resolution.
#[derive(Clone)]
pub struct MaterialUseCases {
    materials: Arc<dyn MaterialRepository>,
    media: Arc<dyn MediaRepository>,
}

impl MaterialUseCases {
    pub fn new(materials: Arc<dyn MaterialRepository>, media: Arc<dyn MediaRepository>) -> Self {
        Self { materials, media }
    }

    /// Creates a learning material from typed component inputs.
    ///
    /// Unknown media inputs fail with `NotFound("media")`. When media inputs
    /// are already bound to exactly one existing material, the request
    /// converges on that material by appending the requested revision instead
    /// of creating. Text-only and media-keyed requests whose deterministic
    /// material identity already exists converge the same way through
    /// [`MaterialRepository::get_material`]. Default/true retention retains a
    /// previously temporary material, while explicit `false` never clears
    /// existing membership. Media inputs bound to different materials fail
    /// with a conflict, as do inputs whose initial identity is ambiguous. The
    /// returned details always carry the revision actually persisted by the
    /// repository, never a locally constructed candidate.
    pub fn create(
        &self,
        input: CreateLearningMaterial,
    ) -> Result<MaterialDetails, ApplicationError> {
        let now = now_ms();
        let (source_assets, renditions) =
            self.components_from_inputs(&input.source_assets, &input.media_renditions)?;
        let bound_materials = self.bound_materials_for_inputs(&input.media_renditions)?;
        let material = match bound_materials.len() {
            0 => {
                let material_id = initial_material_id(&source_assets, &renditions)?;
                let revision = MaterialRevision::new(
                    material_id.clone(),
                    input.title.clone(),
                    source_assets,
                    renditions,
                    now,
                )?;
                if self.materials.get_material(&material_id)?.is_some() {
                    // The deterministic identity already exists (for example a
                    // text-only retry after a prior convergent write): this
                    // request converges by appending the content-idempotent
                    // revision instead of creating a row again.
                    self.materials
                        .append_revision(&material_id, &revision, now)?
                } else {
                    let retained_at_ms = match input.retain {
                        Some(false) => None,
                        _ => Some(now),
                    };
                    let material = LearningMaterial::new(&revision, retained_at_ms, now, now)?;
                    self.materials.create_material(&material, &revision)?
                }
            }
            1 => {
                let material_id = bound_materials
                    .into_iter()
                    .next()
                    .expect("exactly one bound material");
                let revision = MaterialRevision::new(
                    material_id.clone(),
                    input.title,
                    source_assets,
                    renditions,
                    now,
                )?;
                self.materials
                    .append_revision(&material_id, &revision, now)?
            }
            _ => {
                return Err(ApplicationError::Conflict(
                    "media renditions belong to different materials",
                ));
            }
        };
        // Apply the create-time retention policy to the aggregate returned by
        // the repository, covering converged writes where the row already
        // existed (possibly temporary). Explicit false never clears.
        let material = self.apply_requested_retention(material, input.retain, now)?;
        self.details_for_material(material)
    }

    /// Appends a revision to an existing material.
    ///
    /// The target material must exist (`NotFound("material")`). Media inputs
    /// may be unbound or bound to the same target material; a media rendition
    /// bound to another material fails with a conflict. The repository
    /// preserves the material's creation time and membership and returns the
    /// updated aggregate; the returned details carry the revision actually
    /// persisted by the repository, never a locally constructed candidate.
    pub fn append_revision(
        &self,
        material_id: &LearningMaterialId,
        input: AppendMaterialRevision,
    ) -> Result<MaterialDetails, ApplicationError> {
        let now = now_ms();
        self.materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let (source_assets, renditions) =
            self.components_from_inputs(&input.source_assets, &input.media_renditions)?;
        for media_input in &input.media_renditions {
            if let Some(bound) = self.materials.material_for_media(&media_input.media_id)?
                && bound.id != *material_id
            {
                return Err(ApplicationError::Conflict(
                    "media rendition belongs to another material",
                ));
            }
        }
        let revision = MaterialRevision::new(
            material_id.clone(),
            input.title,
            source_assets,
            renditions,
            now,
        )?;
        let material = self
            .materials
            .append_revision(material_id, &revision, now)?;
        self.details_for_material(material)
    }

    /// Loads a material together with its actual current revision, or `None`
    /// when the material does not exist.
    pub fn read(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Option<MaterialDetails>, ApplicationError> {
        let Some(material) = self.materials.get_material(material_id)? else {
            return Ok(None);
        };
        Ok(Some(self.details_for_material(material)?))
    }

    /// Loads a specific revision of a material as a bare [`MaterialRevision`].
    ///
    /// The revision must exist and belong to the requested material, otherwise
    /// `NotFound("material revision")` is returned. `MaterialDetails` always
    /// means a material plus its actual current revision, so historical
    /// revisions are exposed directly instead of being mislabeled current.
    pub fn read_revision(
        &self,
        material_id: &LearningMaterialId,
        revision_id: &MaterialRevisionId,
    ) -> Result<MaterialRevision, ApplicationError> {
        self.materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let revision = self
            .materials
            .get_revision(revision_id)?
            .ok_or(ApplicationError::NotFound("material revision"))?;
        if revision.material_id != *material_id {
            return Err(ApplicationError::NotFound("material revision"));
        }
        Ok(revision)
    }

    /// Lists retained materials with their current revisions.
    ///
    /// Defensively filters out any material lacking membership evidence before
    /// loading details, regardless of what the repository reports.
    pub fn list_retained(&self) -> Result<Vec<MaterialDetails>, ApplicationError> {
        let materials = self.materials.list_retained_materials()?;
        let mut details = Vec::new();
        for material in materials {
            if material.retained_at_ms.is_none() {
                continue;
            }
            details.push(self.details_for_material(material)?);
        }
        Ok(details)
    }

    /// Marks a material as retained, idempotently: an already-retained
    /// material is returned without any membership mutation.
    pub fn retain(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<MaterialDetails, ApplicationError> {
        let now = now_ms();
        let material = self
            .materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let material = if material.retained_at_ms.is_some() {
            material
        } else {
            self.materials
                .set_library_membership(material_id, Some(now), now)?
        };
        self.details_for_material(material)
    }

    /// Removes library membership, idempotently.
    ///
    /// Unretaining performs exactly one membership mutation and never creates,
    /// appends, or mutates media; revisions, bindings, and the media store are
    /// left untouched.
    pub fn unretain(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<MaterialDetails, ApplicationError> {
        let now = now_ms();
        let material = self
            .materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let material = if material.retained_at_ms.is_none() {
            material
        } else {
            self.materials
                .set_library_membership(material_id, None, now)?
        };
        self.details_for_material(material)
    }

    /// Updates the availability fact of one Source Asset of the material's
    /// current revision. The material must exist and the asset must belong to
    /// its current revision, otherwise `NotFound("source asset")`. A missing
    /// referenced asset is an unavailable fact: the Material and its
    /// membership stay untouched.
    pub fn update_source_asset_availability(
        &self,
        material_id: &LearningMaterialId,
        source_asset_id: &domain::SourceAssetId,
        availability: domain::SourceAssetAvailability,
    ) -> Result<MaterialRevision, ApplicationError> {
        self.materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        self.materials
            .set_source_asset_availability(material_id, source_asset_id, availability)?
            .ok_or(ApplicationError::NotFound("source asset"))
    }

    /// Resolves the learning material bound to a media source, or `None` when
    /// the media is not bound to any material.
    pub fn resolve_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Option<MaterialDetails>, ApplicationError> {
        let Some(material) = self.materials.material_for_media(media_id)? else {
            return Ok(None);
        };
        Ok(Some(self.details_for_material(material)?))
    }

    /// Loads the material's actual current revision from the repository and
    /// assembles authoritative details. `MaterialDetails` always means the
    /// material plus its true current revision, so every write and read path
    /// resolves the revision named by the returned aggregate instead of
    /// trusting a locally constructed candidate.
    fn details_for_material(
        &self,
        material: LearningMaterial,
    ) -> Result<MaterialDetails, ApplicationError> {
        let current_revision = self.current_revision(&material)?;
        Ok(MaterialDetails {
            material,
            current_revision,
        })
    }

    fn current_revision(
        &self,
        material: &LearningMaterial,
    ) -> Result<MaterialRevision, ApplicationError> {
        let revision = self
            .materials
            .get_revision(&material.current_revision_id)?
            .ok_or_else(|| ApplicationError::Repository("current revision is missing".into()))?;
        if revision.material_id != material.id {
            // A repository must never point a material's current-revision
            // pointer at a revision owned by another material. Surface the
            // corruption instead of silently substituting or repointing.
            return Err(ApplicationError::Repository(
                "current revision belongs to another material".into(),
            ));
        }
        Ok(revision)
    }

    /// Resolves typed inputs into domain components, strictly through the
    /// media repository for media renditions so only authoritative kind,
    /// fingerprint, and availability facts are snapshotted. No path ever
    /// enters a material.
    fn components_from_inputs(
        &self,
        source_asset_inputs: &[SourceAssetInput],
        media_inputs: &[MediaRenditionInput],
    ) -> Result<(Vec<SourceAsset>, Vec<Rendition>), ApplicationError> {
        let now = now_ms();
        let mut source_assets = Vec::with_capacity(source_asset_inputs.len());
        for input in source_asset_inputs {
            if domain::media_type_kind(&input.media_type).is_none() {
                return Err(ApplicationError::Invalid(
                    "source asset must be audio or video media".into(),
                ));
            }
            source_assets.push(SourceAsset::new(
                input.media_type.clone(),
                input.byte_length,
                input.sha256_digest.clone(),
                input.binding.clone(),
                domain::SourceAssetAvailability::Available,
                now,
            )?);
        }
        let mut renditions = Vec::with_capacity(media_inputs.len());
        for input in media_inputs {
            let media = self
                .media
                .get(&input.media_id)?
                .ok_or(ApplicationError::NotFound("media"))?;
            renditions.push(Rendition::Media(MediaRendition::new(
                RenditionOrigin::Source,
                media.kind,
                media_media_type(media.kind),
                media.fingerprint.clone(),
                media.availability,
                Some(media.id.clone()),
                None,
                None,
                None,
                None,
            )?));
        }
        Ok((source_assets, renditions))
    }

    /// Distinct material ids that the given media inputs are currently bound
    /// to, deduplicated.
    fn bound_materials_for_inputs(
        &self,
        inputs: &[MediaRenditionInput],
    ) -> Result<HashSet<LearningMaterialId>, ApplicationError> {
        let mut bound = HashSet::new();
        for input in inputs {
            if let Some(material) = self.materials.material_for_media(&input.media_id)? {
                bound.insert(material.id);
            }
        }
        Ok(bound)
    }

    /// Applies the create-time retention policy to the aggregate returned by
    /// the repository. Default/true retention records membership for a
    /// temporary material; explicit `false` never clears existing membership.
    /// Reading the aggregate first makes the policy idempotent.
    fn apply_requested_retention(
        &self,
        material: LearningMaterial,
        retain: Option<bool>,
        now: u64,
    ) -> Result<LearningMaterial, ApplicationError> {
        if retain == Some(false) || material.retained_at_ms.is_some() {
            Ok(material)
        } else {
            self.materials
                .set_library_membership(&material.id, Some(now), now)
        }
    }
}

fn media_media_type(kind: MediaKind) -> String {
    match kind {
        MediaKind::Video => "video/mp4".to_owned(),
        MediaKind::Audio => "audio/mpeg".to_owned(),
    }
}

/// Maps a domain construction failure to the stable application error.
pub fn domain_error(error: DomainError) -> ApplicationError {
    ApplicationError::Invalid(error.to_string())
}
