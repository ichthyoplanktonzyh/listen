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
    DocumentRendition, DomainError, LanguageCode, LearningMaterial, LearningMaterialId,
    MaterialRevision, MaterialRevisionId, MaterialShape, MediaId, MediaKind, MediaRendition,
    Rendition, RenditionOrigin, SourceAsset, SourceAssetBinding, initial_material_id,
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

/// Input for one Document Rendition. A Source rendition optionally binds the
/// Source Asset declared earlier in the same request by position.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentRenditionInput {
    pub media_type: String,
    pub language: Option<LanguageCode>,
    pub text: String,
    pub source_asset_index: Option<usize>,
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
    pub document_renditions: Vec<DocumentRenditionInput>,
    pub media_renditions: Vec<MediaRenditionInput>,
    pub retain: Option<bool>,
}

/// Input for appending a new revision to an existing learning material.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppendMaterialRevision {
    pub title: String,
    pub source_assets: Vec<SourceAssetInput>,
    pub document_renditions: Vec<DocumentRenditionInput>,
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
        let (source_assets, renditions) = self.components_from_inputs(
            &input.source_assets,
            &input.document_renditions,
            &input.media_renditions,
        )?;
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
        let (source_assets, renditions) = self.components_from_inputs(
            &input.source_assets,
            &input.document_renditions,
            &input.media_renditions,
        )?;
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
        document_inputs: &[DocumentRenditionInput],
        media_inputs: &[MediaRenditionInput],
    ) -> Result<(Vec<SourceAsset>, Vec<Rendition>), ApplicationError> {
        let now = now_ms();
        let mut source_assets = Vec::with_capacity(source_asset_inputs.len());
        for input in source_asset_inputs {
            source_assets.push(SourceAsset::new(
                input.media_type.clone(),
                input.byte_length,
                input.sha256_digest.clone(),
                input.binding.clone(),
                domain::SourceAssetAvailability::Available,
                now,
            )?);
        }
        let mut renditions = Vec::with_capacity(document_inputs.len() + media_inputs.len());
        for input in document_inputs {
            let source_asset_id = match input.source_asset_index {
                Some(index) => Some(
                    source_assets
                        .get(index)
                        .ok_or_else(|| {
                            ApplicationError::Invalid(format!(
                                "document rendition references missing source asset index {index}"
                            ))
                        })?
                        .id
                        .clone(),
                ),
                None => None,
            };
            renditions.push(Rendition::Document(DocumentRendition::new(
                RenditionOrigin::Source,
                input.media_type.clone(),
                input.language.clone(),
                input.text.clone(),
                source_asset_id,
                None,
                None,
            )?));
        }
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};

    use domain::{MediaAvailability, MediaItem};

    fn text_input(text: &str) -> DocumentRenditionInput {
        DocumentRenditionInput {
            media_type: "text/plain".to_owned(),
            language: None,
            text: text.to_owned(),
            source_asset_index: None,
        }
    }

    fn media_input(media_id: &str) -> MediaRenditionInput {
        MediaRenditionInput {
            media_id: MediaId::parse(media_id).expect("valid media id"),
        }
    }

    fn media_item(id: &str, kind: MediaKind, fingerprint: &str) -> MediaItem {
        MediaItem {
            id: MediaId::parse(id).expect("valid media id"),
            // The media store may carry a path; a material must never see it.
            path: format!("/tmp/{id}.media"),
            fingerprint: fingerprint.to_owned(),
            title: format!("title-{id}"),
            kind,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        }
    }

    fn setup() -> (
        MaterialUseCases,
        FakeMaterialRepository,
        FakeMediaRepository,
    ) {
        let materials = FakeMaterialRepository::default();
        let media = FakeMediaRepository::default();
        let use_cases = MaterialUseCases::new(Arc::new(materials.clone()), Arc::new(media.clone()));
        (use_cases, materials, media)
    }

    #[derive(Default)]
    struct FakeMediaStore {
        items: HashMap<String, MediaItem>,
        get_calls: u64,
    }

    #[derive(Clone, Default)]
    struct FakeMediaRepository {
        store: Arc<Mutex<FakeMediaStore>>,
    }

    impl FakeMediaRepository {
        fn seed(&self, item: MediaItem) {
            self.store
                .lock()
                .unwrap()
                .items
                .insert(item.id.as_str().to_owned(), item);
        }
    }

    impl MediaRepository for FakeMediaRepository {
        fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError> {
            let mut store = self.store.lock().unwrap();
            store.get_calls += 1;
            Ok(store.items.get(id.as_str()).cloned())
        }

        fn upsert(&self, item: &MediaItem) -> Result<MediaItem, ApplicationError> {
            let mut store = self.store.lock().unwrap();
            store
                .items
                .insert(item.id.as_str().to_owned(), item.clone());
            Ok(item.clone())
        }

        fn set_library_membership(
            &self,
            media_id: &MediaId,
            retained_at_ms: Option<u64>,
            updated_at_ms: u64,
        ) -> Result<MediaItem, ApplicationError> {
            let mut store = self.store.lock().unwrap();
            let item = store
                .items
                .get_mut(media_id.as_str())
                .ok_or_else(|| ApplicationError::Repository("media not found".into()))?;
            item.retained_at_ms = retained_at_ms;
            item.updated_at_ms = updated_at_ms;
            Ok(item.clone())
        }

        fn list(&self) -> Result<Vec<MediaItem>, ApplicationError> {
            let store = self.store.lock().unwrap();
            let mut items: Vec<MediaItem> = store.items.values().cloned().collect();
            items.sort_by(|a, b| a.id.as_str().cmp(b.id.as_str()));
            Ok(items)
        }

        fn set_availability(
            &self,
            media_id: &MediaId,
            availability: MediaAvailability,
        ) -> Result<MediaItem, ApplicationError> {
            let mut store = self.store.lock().unwrap();
            let item = store
                .items
                .get_mut(media_id.as_str())
                .ok_or_else(|| ApplicationError::Repository("media not found".into()))?;
            item.availability = availability;
            Ok(item.clone())
        }

        fn get_triage_intent(
            &self,
            _media_id: &MediaId,
        ) -> Result<Option<domain::MediaTriageIntent>, ApplicationError> {
            Ok(None)
        }

        fn list_triage_intents(
            &self,
        ) -> Result<Vec<(MediaId, domain::MediaTriageIntent)>, ApplicationError> {
            Ok(Vec::new())
        }

        fn set_triage_intent(
            &self,
            _media_id: &MediaId,
            _intent: Option<domain::MediaTriageIntent>,
            _updated_at_ms: u64,
        ) -> Result<(), ApplicationError> {
            Ok(())
        }
    }

    #[derive(Default)]
    struct FakeMaterialState {
        materials: HashMap<String, LearningMaterial>,
        revisions: HashMap<String, MaterialRevision>,
        media_bindings: HashMap<String, String>,
        create_calls: u64,
        append_calls: u64,
        membership_calls: u64,
        misbehave_list_retained: bool,
        rewrite_revision_created_at: Option<u64>,
    }

    #[derive(Clone, Default)]
    struct FakeMaterialRepository {
        state: Arc<Mutex<FakeMaterialState>>,
    }

    fn bind_media_assets(state: &mut FakeMaterialState, revision: &MaterialRevision) {
        for rendition in &revision.renditions {
            if let Rendition::Media(media) = rendition
                && let Some(media_id) = &media.media_id
            {
                state
                    .media_bindings
                    .entry(media_id.as_str().to_owned())
                    .or_insert_with(|| revision.material_id.as_str().to_owned());
            }
        }
    }

    fn store_revision(state: &mut FakeMaterialState, revision: &MaterialRevision) {
        let mut stored = revision.clone();
        if let Some(created_at_ms) = state.rewrite_revision_created_at {
            stored.created_at_ms = created_at_ms;
        }
        state
            .revisions
            .insert(stored.id.as_str().to_owned(), stored);
    }

    impl FakeMaterialRepository {
        fn create_calls(&self) -> u64 {
            self.state.lock().unwrap().create_calls
        }

        fn append_calls(&self) -> u64 {
            self.state.lock().unwrap().append_calls
        }

        fn membership_calls(&self) -> u64 {
            self.state.lock().unwrap().membership_calls
        }

        fn material_count(&self) -> usize {
            self.state.lock().unwrap().materials.len()
        }

        fn revision_count(&self) -> usize {
            self.state.lock().unwrap().revisions.len()
        }

        fn set_misbehaving_list_retained(&self, misbehave: bool) {
            self.state.lock().unwrap().misbehave_list_retained = misbehave;
        }

        fn set_rewrite_revision_created_at(&self, created_at_ms: Option<u64>) {
            self.state.lock().unwrap().rewrite_revision_created_at = created_at_ms;
        }
    }

    impl MaterialRepository for FakeMaterialRepository {
        fn create_material(
            &self,
            material: &LearningMaterial,
            revision: &MaterialRevision,
        ) -> Result<LearningMaterial, ApplicationError> {
            let mut state = self.state.lock().unwrap();
            state.create_calls += 1;
            if let Some(existing) = state.materials.get(material.id.as_str()) {
                return Ok(existing.clone());
            }
            state
                .materials
                .insert(material.id.as_str().to_owned(), material.clone());
            store_revision(&mut state, revision);
            bind_media_assets(&mut state, revision);
            Ok(material.clone())
        }

        fn append_revision(
            &self,
            material_id: &LearningMaterialId,
            revision: &MaterialRevision,
            updated_at_ms: u64,
        ) -> Result<LearningMaterial, ApplicationError> {
            let mut state = self.state.lock().unwrap();
            state.append_calls += 1;
            {
                let material = state
                    .materials
                    .get(material_id.as_str())
                    .ok_or_else(|| ApplicationError::Repository("material not found".into()))?;
                if material.current_revision_id == revision.id
                    && state.revisions.contains_key(revision.id.as_str())
                {
                    return Ok(material.clone());
                }
            }
            store_revision(&mut state, revision);
            bind_media_assets(&mut state, revision);
            let material = state
                .materials
                .get_mut(material_id.as_str())
                .ok_or_else(|| ApplicationError::Repository("material not found".into()))?;
            material.current_revision_id = revision.id.clone();
            material.updated_at_ms = updated_at_ms;
            Ok(material.clone())
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
            let state = self.state.lock().unwrap();
            let mut materials: Vec<LearningMaterial> = state
                .materials
                .values()
                .filter(|material| {
                    state.misbehave_list_retained || material.retained_at_ms.is_some()
                })
                .cloned()
                .collect();
            materials.sort_by(|a, b| a.id.as_str().cmp(b.id.as_str()));
            Ok(materials)
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
            media_id: &MediaId,
        ) -> Result<Option<LearningMaterial>, ApplicationError> {
            let state = self.state.lock().unwrap();
            Ok(match state.media_bindings.get(media_id.as_str()) {
                Some(material_id) => state.materials.get(material_id).cloned(),
                None => None,
            })
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

    #[test]
    fn create_covers_text_audio_video_and_mixed_shapes() {
        let (use_cases, _, media) = setup();

        let text = use_cases
            .create(CreateLearningMaterial {
                title: "Notes".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("spoken notes")],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("text material");
        assert_eq!(text.shape(), MaterialShape::Text);

        media.seed(media_item("media-audio", MediaKind::Audio, "fp-a"));
        let audio = use_cases
            .create(CreateLearningMaterial {
                title: "Audio".into(),
                source_assets: Vec::new(),
                document_renditions: Vec::new(),
                media_renditions: vec![media_input("media-audio")],
                retain: None,
            })
            .expect("audio material");
        assert_eq!(audio.shape(), MaterialShape::Audio);

        media.seed(media_item("media-video", MediaKind::Video, "fp-v"));
        let video = use_cases
            .create(CreateLearningMaterial {
                title: "Video".into(),
                source_assets: Vec::new(),
                document_renditions: Vec::new(),
                media_renditions: vec![media_input("media-video")],
                retain: None,
            })
            .expect("video material");
        assert_eq!(video.shape(), MaterialShape::Video);

        media.seed(media_item("media-mixed-a", MediaKind::Audio, "fp-ma"));
        let mixed = use_cases
            .create(CreateLearningMaterial {
                title: "Mixed".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("with notes")],
                media_renditions: vec![media_input("media-mixed-a")],
                retain: None,
            })
            .expect("text plus audio material");
        assert_eq!(mixed.shape(), MaterialShape::Mixed);
    }

    #[test]
    fn document_rendition_preserves_exact_input_bytes() {
        let (use_cases, _, _) = setup();
        let details = use_cases
            .create(CreateLearningMaterial {
                title: "Exact".into(),
                source_assets: Vec::new(),
                document_renditions: vec![DocumentRenditionInput {
                    media_type: "text/plain".into(),
                    language: None,
                    text: "  leading and trailing whitespace  ".into(),
                    source_asset_index: None,
                }],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("material");
        let Rendition::Document(rendition) = &details.current_revision.renditions[0] else {
            panic!("expected a document rendition");
        };
        assert_eq!(rendition.text, "  leading and trailing whitespace  ");
    }

    #[test]
    fn source_assets_bind_document_renditions_by_position() {
        let (use_cases, _, _) = setup();
        let details = use_cases
            .create(CreateLearningMaterial {
                title: "With source".into(),
                source_assets: vec![SourceAssetInput {
                    media_type: "text/plain".into(),
                    byte_length: 11,
                    sha256_digest: "a".repeat(64),
                    binding: SourceAssetBinding::Managed,
                }],
                document_renditions: vec![DocumentRenditionInput {
                    media_type: "text/plain".into(),
                    language: None,
                    text: "hello world".into(),
                    source_asset_index: Some(0),
                }],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("material with source asset");
        assert_eq!(details.current_revision.source_assets.len(), 1);
        let asset = &details.current_revision.source_assets[0];
        assert_eq!(asset.byte_length, 11);
        let Rendition::Document(rendition) = &details.current_revision.renditions[0] else {
            panic!("expected a document rendition");
        };
        assert_eq!(rendition.source_asset_id.as_ref(), Some(&asset.id));

        // An out-of-range source asset index is refused.
        let err = use_cases
            .create(CreateLearningMaterial {
                title: "Bad index".into(),
                source_assets: Vec::new(),
                document_renditions: vec![DocumentRenditionInput {
                    media_type: "text/plain".into(),
                    language: None,
                    text: "hello".into(),
                    source_asset_index: Some(2),
                }],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect_err("out-of-range index");
        assert!(matches!(err, ApplicationError::Invalid(_)));
    }

    #[test]
    fn media_renditions_resolve_from_authoritative_media_facts() {
        let (use_cases, _, media) = setup();
        media.seed(media_item("media-vid", MediaKind::Video, "fp-xyz"));
        let details = use_cases
            .create(CreateLearningMaterial {
                title: "Video notes".into(),
                source_assets: Vec::new(),
                document_renditions: Vec::new(),
                media_renditions: vec![media_input("media-vid")],
                retain: None,
            })
            .expect("video material");
        let Rendition::Media(rendition) = &details.current_revision.renditions[0] else {
            panic!("expected a media rendition");
        };
        assert_eq!(
            rendition.media_id.as_ref().expect("media id").as_str(),
            "media-vid"
        );
        assert_eq!(rendition.kind, MediaKind::Video);
        assert_eq!(rendition.fingerprint, "fp-xyz");
        assert_eq!(rendition.availability, MediaAvailability::Available);
        let json = serde_json::to_value(rendition).expect("serializes");
        assert!(
            !json.as_object().expect("object").contains_key("path"),
            "renditions never carry paths"
        );
    }

    #[test]
    fn default_retained_and_explicit_temporary_materials_in_list() {
        let (use_cases, _, _) = setup();
        let retained = use_cases
            .create(CreateLearningMaterial {
                title: "Default retained".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("kept")],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("default retained");
        assert!(retained.material.retained_at_ms.is_some());

        let temporary = use_cases
            .create(CreateLearningMaterial {
                title: "Temporary".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("expiring")],
                media_renditions: Vec::new(),
                retain: Some(false),
            })
            .expect("temporary");
        assert!(temporary.material.retained_at_ms.is_none());

        let list = use_cases.list_retained().expect("list retained");
        let ids: Vec<&str> = list
            .iter()
            .map(|details| details.material.id.as_str())
            .collect();
        assert!(ids.contains(&retained.material.id.as_str()));
        assert!(!ids.contains(&temporary.material.id.as_str()));
    }

    #[test]
    fn text_only_retries_converge_without_recreating_the_material() {
        let (use_cases, materials, _) = setup();
        let first = use_cases
            .create(CreateLearningMaterial {
                title: "Same".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("identical content")],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("first create");
        let retry = use_cases
            .create(CreateLearningMaterial {
                title: "Same".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("identical content")],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("retry create");
        assert_eq!(retry.material.id, first.material.id);
        assert_eq!(
            retry.material.current_revision_id, first.material.current_revision_id,
            "equal content retries converge on the same revision"
        );
        assert_eq!(materials.create_calls(), 1, "no second create");
        assert_eq!(materials.append_calls(), 1, "converged by appending");
        assert_eq!(materials.material_count(), 1);
        assert_eq!(materials.revision_count(), 1);
    }

    #[test]
    fn create_returns_the_persisted_revision_not_the_local_candidate() {
        let (use_cases, materials, _) = setup();
        materials.set_rewrite_revision_created_at(Some(42));

        let first = use_cases
            .create(CreateLearningMaterial {
                title: "Source of truth".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("authoritative content")],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("first create");
        assert_eq!(first.current_revision.created_at_ms, 42);

        let retry = use_cases
            .create(CreateLearningMaterial {
                title: "Source of truth".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("authoritative content")],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("retry create");
        assert_eq!(retry.current_revision.created_at_ms, 42);
    }

    #[test]
    fn temporary_retry_with_default_retain_converges_and_retains() {
        let (use_cases, materials, _) = setup();
        let temporary = use_cases
            .create(CreateLearningMaterial {
                title: "Draft".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("convergent content")],
                media_renditions: Vec::new(),
                retain: Some(false),
            })
            .expect("temporary create");
        let material_id = temporary.material.id.clone();
        assert!(temporary.material.retained_at_ms.is_none());

        let retained = use_cases
            .create(CreateLearningMaterial {
                title: "Draft".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("convergent content")],
                media_renditions: Vec::new(),
                retain: None,
            })
            .expect("default-retain retry");
        assert_eq!(retained.material.id, material_id);
        assert_eq!(materials.membership_calls(), 1);
        assert!(retained.material.retained_at_ms.is_some());

        let still_retained = use_cases
            .create(CreateLearningMaterial {
                title: "Draft".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("convergent content")],
                media_renditions: Vec::new(),
                retain: Some(false),
            })
            .expect("explicit-false retry");
        assert_eq!(
            materials.membership_calls(),
            1,
            "explicit false never clears"
        );
        assert!(still_retained.material.retained_at_ms.is_some());
    }

    #[test]
    fn append_is_idempotent_and_revisions_keep_exact_ownership() {
        let (use_cases, materials, media) = setup();
        media.seed(media_item("media-app", MediaKind::Audio, "fp-app"));
        let created = use_cases
            .create(CreateLearningMaterial {
                title: "V1".into(),
                source_assets: Vec::new(),
                document_renditions: Vec::new(),
                media_renditions: vec![media_input("media-app")],
                retain: None,
            })
            .expect("create");
        let material_id = created.material.id.clone();

        let first = use_cases
            .append_revision(
                &material_id,
                AppendMaterialRevision {
                    title: "V2".into(),
                    source_assets: Vec::new(),
                    document_renditions: vec![text_input("more notes")],
                    media_renditions: vec![media_input("media-app")],
                },
            )
            .expect("first append");
        assert_eq!(materials.revision_count(), 2);

        let retry = use_cases
            .append_revision(
                &material_id,
                AppendMaterialRevision {
                    title: "V2".into(),
                    source_assets: Vec::new(),
                    document_renditions: vec![text_input("more notes")],
                    media_renditions: vec![media_input("media-app")],
                },
            )
            .expect("idempotent retry");
        assert_eq!(
            retry.material.current_revision_id,
            first.material.current_revision_id
        );
        assert_eq!(
            retry.material.updated_at_ms, first.material.updated_at_ms,
            "an idempotent retry must not advance the update time"
        );
        assert_eq!(materials.revision_count(), 2);

        let err = use_cases
            .read_revision(
                &material_id,
                &MaterialRevisionId::from_fingerprint("material-revision", "missing"),
            )
            .expect_err("missing revision");
        assert!(matches!(
            err,
            ApplicationError::NotFound("material revision")
        ));
    }

    #[test]
    fn list_retained_defends_against_a_misbehaving_repository() {
        let (use_cases, materials, media) = setup();
        media.seed(media_item("media-list", MediaKind::Audio, "fp-list"));
        let retained = use_cases
            .create(CreateLearningMaterial {
                title: "Retained".into(),
                source_assets: Vec::new(),
                document_renditions: Vec::new(),
                media_renditions: vec![media_input("media-list")],
                retain: None,
            })
            .expect("retained material");
        use_cases
            .create(CreateLearningMaterial {
                title: "Temporary".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("temp notes")],
                media_renditions: Vec::new(),
                retain: Some(false),
            })
            .expect("temporary material");

        materials.set_misbehaving_list_retained(true);
        let list = use_cases.list_retained().expect("list retained");
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].material.id, retained.material.id);
    }

    #[test]
    fn retain_and_unretain_are_idempotent() {
        let (use_cases, materials, _) = setup();
        let created = use_cases
            .create(CreateLearningMaterial {
                title: "Toggle".into(),
                source_assets: Vec::new(),
                document_renditions: vec![text_input("toggle content")],
                media_renditions: Vec::new(),
                retain: Some(false),
            })
            .expect("temporary material");
        let material_id = created.material.id.clone();

        use_cases.retain(&material_id).expect("retain");
        assert_eq!(materials.membership_calls(), 1);
        use_cases.retain(&material_id).expect("retain again");
        assert_eq!(
            materials.membership_calls(),
            1,
            "already retained is a no-op"
        );

        use_cases.unretain(&material_id).expect("unretain");
        assert_eq!(materials.membership_calls(), 2);
        use_cases.unretain(&material_id).expect("unretain again");
        assert_eq!(materials.membership_calls(), 2, "temporary is a no-op");

        let err = use_cases
            .unretain(&LearningMaterialId::parse("material-absent").unwrap())
            .expect_err("missing material");
        assert!(matches!(err, ApplicationError::NotFound("material")));
    }

    #[test]
    fn resolve_for_media_returns_bound_material_details() {
        let (use_cases, _, media) = setup();
        media.seed(media_item("media-resolve", MediaKind::Audio, "fp-r"));
        let created = use_cases
            .create(CreateLearningMaterial {
                title: "Bound".into(),
                source_assets: Vec::new(),
                document_renditions: Vec::new(),
                media_renditions: vec![media_input("media-resolve")],
                retain: None,
            })
            .expect("bound material");
        let resolved = use_cases
            .resolve_for_media(&MediaId::parse("media-resolve").unwrap())
            .expect("resolve")
            .expect("bound");
        assert_eq!(resolved.material.id, created.material.id);
        let none = use_cases
            .resolve_for_media(&MediaId::parse("media-other").unwrap())
            .expect("resolve");
        assert!(none.is_none());
    }
}
