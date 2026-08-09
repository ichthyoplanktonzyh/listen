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
    DocumentTextAsset, LanguageCode, LearningMaterial, LearningMaterialId, MaterialAsset,
    MaterialRevision, MaterialRevisionId, MaterialShape, MediaId, MediaRenditionAsset,
    initial_material_id,
};

use crate::{ApplicationError, MediaRepository, now_ms};

/// A typed asset input for creating or extending a learning material.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MaterialAssetInput {
    /// Inline learner-facing text, optionally tagged with a language.
    DocumentText {
        text: String,
        language: Option<LanguageCode>,
    },
    /// A reference to an already-registered media source.
    MediaRendition { media_id: MediaId },
}

/// Input for creating a learning material.
///
/// Retention semantics: `None` (default) and `Some(true)` retain the material
/// in the personal library; `Some(false)` marks the material temporary
/// (explicitly excluded from the library projection).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CreateLearningMaterial {
    pub title: String,
    pub assets: Vec<MaterialAssetInput>,
    pub retain: Option<bool>,
}

/// Input for appending a new revision to an existing learning material.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppendMaterialRevision {
    pub title: String,
    pub assets: Vec<MaterialAssetInput>,
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

    /// Creates a learning material from typed asset inputs.
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
        let assets = self.assets_from_inputs(&input.assets)?;
        let bound_materials = self.bound_materials_for_inputs(&input.assets)?;
        let material = match bound_materials.len() {
            0 => {
                let material_id = initial_material_id(&assets)?;
                let revision =
                    MaterialRevision::new(material_id.clone(), input.title, assets, now)?;
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
                let revision =
                    MaterialRevision::new(material_id.clone(), input.title, assets, now)?;
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
        let assets = self.assets_from_inputs(&input.assets)?;
        for asset_input in &input.assets {
            if let MaterialAssetInput::MediaRendition { media_id } = asset_input
                && let Some(bound) = self.materials.material_for_media(media_id)?
                && bound.id != *material_id
            {
                return Err(ApplicationError::Conflict(
                    "media rendition belongs to another material",
                ));
            }
        }
        let revision = MaterialRevision::new(material_id.clone(), input.title, assets, now)?;
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

    /// Resolves typed inputs into domain assets, strictly through the media
    /// repository for renditions so only authoritative kind, fingerprint, and
    /// availability facts are snapshotted. No path ever enters a material.
    fn assets_from_inputs(
        &self,
        inputs: &[MaterialAssetInput],
    ) -> Result<Vec<MaterialAsset>, ApplicationError> {
        let mut assets = Vec::with_capacity(inputs.len());
        for input in inputs {
            match input {
                MaterialAssetInput::DocumentText { text, language } => {
                    assets.push(MaterialAsset::DocumentText(DocumentTextAsset::new(
                        text.clone(),
                        language.clone(),
                    )?));
                }
                MaterialAssetInput::MediaRendition { media_id } => {
                    let media = self
                        .media
                        .get(media_id)?
                        .ok_or(ApplicationError::NotFound("media"))?;
                    assets.push(MaterialAsset::MediaRendition(MediaRenditionAsset::new(
                        media_id.clone(),
                        media.kind,
                        media.fingerprint.clone(),
                        media.availability,
                    )?));
                }
            }
        }
        Ok(assets)
    }

    /// Distinct material ids that the given media inputs are currently bound
    /// to, deduplicated.
    fn bound_materials_for_inputs(
        &self,
        inputs: &[MaterialAssetInput],
    ) -> Result<HashSet<LearningMaterialId>, ApplicationError> {
        let mut bound = HashSet::new();
        for input in inputs {
            if let MaterialAssetInput::MediaRendition { media_id } = input
                && let Some(material) = self.materials.material_for_media(media_id)?
            {
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};

    use domain::{DomainError, MediaAvailability, MediaItem, MediaKind};

    fn text_input(text: &str) -> MaterialAssetInput {
        MaterialAssetInput::DocumentText {
            text: text.to_owned(),
            language: None,
        }
    }

    fn media_input(media_id: &str) -> MaterialAssetInput {
        MaterialAssetInput::MediaRendition {
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

        fn get_calls(&self) -> u64 {
            self.store.lock().unwrap().get_calls
        }

        fn snapshot(&self) -> Vec<MediaItem> {
            let store = self.store.lock().unwrap();
            let mut items: Vec<MediaItem> = store.items.values().cloned().collect();
            items.sort_by(|a, b| a.id.as_str().cmp(b.id.as_str()));
            items
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
        /// When set, `list_retained_materials` reports every material, even
        /// temporary ones, to exercise the use case's defensive filter.
        misbehave_list_retained: bool,
        /// When set, every persisted revision is stored with this
        /// `created_at_ms` (an adapter whose immutable revision keeps its
        /// original timestamp across idempotent retries), to prove write paths
        /// return the persisted revision and not the local candidate.
        rewrite_revision_created_at: Option<u64>,
    }

    #[derive(Clone, Default)]
    struct FakeMaterialRepository {
        state: Arc<Mutex<FakeMaterialState>>,
    }

    fn bind_media_assets(state: &mut FakeMaterialState, revision: &MaterialRevision) {
        for asset in &revision.assets {
            if let MaterialAsset::MediaRendition(rendition) = asset {
                state
                    .media_bindings
                    .entry(rendition.media_id.as_str().to_owned())
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

        fn revision_ids(&self) -> Vec<String> {
            let state = self.state.lock().unwrap();
            let mut ids: Vec<String> = state.revisions.keys().cloned().collect();
            ids.sort();
            ids
        }

        fn set_misbehaving_list_retained(&self, misbehave: bool) {
            self.state.lock().unwrap().misbehave_list_retained = misbehave;
        }

        /// Directly points a material's current-revision pointer, simulating a
        /// corrupt repository that breaks the material-to-revision ownership
        /// invariant. Adversarial tests use this seam to prove the use case
        /// revalidates ownership instead of trusting the pointer.
        fn set_current_revision_pointer(
            &self,
            material_id: &LearningMaterialId,
            revision_id: &MaterialRevisionId,
        ) {
            let mut state = self.state.lock().unwrap();
            state
                .materials
                .get_mut(material_id.as_str())
                .expect("material must exist before repointing its current revision")
                .current_revision_id = revision_id.clone();
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
                // Deterministic idempotency: equal content converges on the
                // first persisted material and revision.
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
                    // Idempotent retry of the already-current revision.
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
    }

    #[test]
    fn create_covers_text_audio_video_and_mixed_shapes() {
        let (use_cases, _, media) = setup();

        let text = use_cases
            .create(CreateLearningMaterial {
                title: "Notes".into(),
                assets: vec![text_input("spoken notes")],
                retain: None,
            })
            .expect("text material");
        assert_eq!(text.shape(), MaterialShape::Text);

        media.seed(media_item("media-audio", MediaKind::Audio, "fp-a"));
        let audio = use_cases
            .create(CreateLearningMaterial {
                title: "Audio".into(),
                assets: vec![media_input("media-audio")],
                retain: None,
            })
            .expect("audio material");
        assert_eq!(audio.shape(), MaterialShape::Audio);

        media.seed(media_item("media-video", MediaKind::Video, "fp-v"));
        let video = use_cases
            .create(CreateLearningMaterial {
                title: "Video".into(),
                assets: vec![media_input("media-video")],
                retain: None,
            })
            .expect("video material");
        assert_eq!(video.shape(), MaterialShape::Video);

        media.seed(media_item("media-mixed-a", MediaKind::Audio, "fp-ma"));
        let mixed = use_cases
            .create(CreateLearningMaterial {
                title: "Mixed".into(),
                assets: vec![text_input("with notes"), media_input("media-mixed-a")],
                retain: None,
            })
            .expect("text plus audio material");
        assert_eq!(mixed.shape(), MaterialShape::Mixed);

        media.seed(media_item("media-mixed-v", MediaKind::Video, "fp-mv"));
        let audio_plus_video = use_cases
            .create(CreateLearningMaterial {
                title: "AV".into(),
                assets: vec![media_input("media-mixed-a"), media_input("media-mixed-v")],
                retain: None,
            })
            .expect("audio plus video material");
        assert_eq!(audio_plus_video.shape(), MaterialShape::Mixed);
    }

    #[test]
    fn document_text_preserves_exact_input_bytes() {
        let (use_cases, _, _) = setup();
        let details = use_cases
            .create(CreateLearningMaterial {
                title: "Exact".into(),
                assets: vec![MaterialAssetInput::DocumentText {
                    text: "  leading and trailing whitespace  ".into(),
                    language: None,
                }],
                retain: None,
            })
            .expect("material");
        let MaterialAsset::DocumentText(asset) = &details.current_revision.assets[0] else {
            panic!("expected a document text asset");
        };
        assert_eq!(asset.text, "  leading and trailing whitespace  ");
    }

    #[test]
    fn media_renditions_resolve_from_authoritative_media_facts() {
        let (use_cases, _, media) = setup();
        media.seed(media_item("media-vid", MediaKind::Video, "fp-xyz"));
        let details = use_cases
            .create(CreateLearningMaterial {
                title: "Video notes".into(),
                assets: vec![media_input("media-vid")],
                retain: None,
            })
            .expect("video material");
        let MaterialAsset::MediaRendition(rendition) = &details.current_revision.assets[0] else {
            panic!("expected a media rendition asset");
        };
        assert_eq!(rendition.media_id.as_str(), "media-vid");
        assert_eq!(rendition.kind, MediaKind::Video);
        assert_eq!(rendition.fingerprint, "fp-xyz");
        assert_eq!(rendition.availability, MediaAvailability::Available);
    }

    #[test]
    fn default_retained_and_explicit_temporary_materials_in_list() {
        let (use_cases, _, _) = setup();
        let retained = use_cases
            .create(CreateLearningMaterial {
                title: "Default retained".into(),
                assets: vec![text_input("kept")],
                retain: None,
            })
            .expect("default retained");
        assert!(retained.material.retained_at_ms.is_some());

        let explicit_retained = use_cases
            .create(CreateLearningMaterial {
                title: "Explicit retained".into(),
                assets: vec![text_input("also kept")],
                retain: Some(true),
            })
            .expect("explicit retained");
        assert!(explicit_retained.material.retained_at_ms.is_some());

        let temporary = use_cases
            .create(CreateLearningMaterial {
                title: "Temporary".into(),
                assets: vec![text_input("expiring")],
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
        assert!(ids.contains(&explicit_retained.material.id.as_str()));
        assert!(!ids.contains(&temporary.material.id.as_str()));
    }

    #[test]
    fn text_only_retries_converge_without_recreating_the_material() {
        let (use_cases, materials, _) = setup();
        let first = use_cases
            .create(CreateLearningMaterial {
                title: "Same".into(),
                assets: vec![text_input("identical content")],
                retain: None,
            })
            .expect("first create");
        let retry = use_cases
            .create(CreateLearningMaterial {
                title: "Same".into(),
                assets: vec![text_input("identical content")],
                retain: None,
            })
            .expect("retry create");
        assert_eq!(retry.material.id, first.material.id);
        assert_eq!(
            retry.material.current_revision_id, first.material.current_revision_id,
            "equal content retries converge on the same revision"
        );
        assert_eq!(
            retry.current_revision.id, first.current_revision.id,
            "the returned revision is the converged persisted revision"
        );
        assert_eq!(
            materials.create_calls(),
            1,
            "the deterministic material identity exists, so the retry must not create again"
        );
        assert_eq!(
            materials.append_calls(),
            1,
            "the retry converges by appending the content-idempotent revision"
        );
        assert_eq!(
            materials.material_count(),
            1,
            "convergence keeps exactly one material"
        );
        assert_eq!(materials.revision_count(), 1);
        assert_eq!(
            retry.material.retained_at_ms, first.material.retained_at_ms,
            "the retry converges on the persisted membership"
        );
    }

    #[test]
    fn create_returns_the_persisted_revision_not_the_local_candidate() {
        let (use_cases, materials, _) = setup();
        // The adapter persists the immutable revision once with its original
        // timestamp; an idempotent retry constructs a candidate with a fresh
        // created_at_ms that must never win.
        materials.set_rewrite_revision_created_at(Some(42));

        let first = use_cases
            .create(CreateLearningMaterial {
                title: "Source of truth".into(),
                assets: vec![text_input("authoritative content")],
                retain: None,
            })
            .expect("first create");
        assert_eq!(
            first.current_revision.created_at_ms, 42,
            "create returns the persisted revision, not the locally constructed candidate"
        );
        let stored = materials
            .get_revision(&first.current_revision.id)
            .expect("read")
            .expect("stored revision");
        assert_eq!(stored, first.current_revision);

        let retry = use_cases
            .create(CreateLearningMaterial {
                title: "Source of truth".into(),
                assets: vec![text_input("authoritative content")],
                retain: None,
            })
            .expect("retry create");
        assert_eq!(retry.material.id, first.material.id);
        assert_eq!(retry.current_revision.id, first.current_revision.id);
        assert_eq!(
            retry.current_revision.created_at_ms, 42,
            "the retry returns the persisted immutable revision, never the fresh candidate"
        );

        let appended = use_cases
            .append_revision(
                &retry.material.id,
                AppendMaterialRevision {
                    title: "Source of truth v2".into(),
                    assets: vec![text_input("authoritative content")],
                },
            )
            .expect("append");
        assert_eq!(
            appended.current_revision.created_at_ms, 42,
            "append returns the persisted revision too"
        );
        assert_eq!(appended.current_revision.title, "Source of truth v2");
        let stored = materials
            .get_revision(&appended.current_revision.id)
            .expect("read")
            .expect("stored revision");
        assert_eq!(stored, appended.current_revision);
    }

    #[test]
    fn text_only_temporary_retry_with_default_retain_converges_and_retains() {
        let (use_cases, materials, _) = setup();
        let temporary = use_cases
            .create(CreateLearningMaterial {
                title: "Draft".into(),
                assets: vec![text_input("convergent content")],
                retain: Some(false),
            })
            .expect("temporary create");
        let material_id = temporary.material.id.clone();
        assert!(temporary.material.retained_at_ms.is_none());
        assert_eq!(materials.create_calls(), 1);
        assert_eq!(materials.membership_calls(), 0);

        // Equal-content retry with default retention converges on the existing
        // deterministic material, appends idempotently, and retains it.
        let retained = use_cases
            .create(CreateLearningMaterial {
                title: "Draft".into(),
                assets: vec![text_input("convergent content")],
                retain: None,
            })
            .expect("default-retain retry");
        assert_eq!(retained.material.id, material_id);
        assert_eq!(materials.create_calls(), 1, "no second create");
        assert_eq!(materials.append_calls(), 1, "converged by appending");
        assert_eq!(materials.material_count(), 1);
        assert_eq!(
            materials.membership_calls(),
            1,
            "a previously temporary material becomes retained by default"
        );
        assert!(retained.material.retained_at_ms.is_some());

        // Explicit false on the now-retained material never clears membership.
        let still_retained = use_cases
            .create(CreateLearningMaterial {
                title: "Draft".into(),
                assets: vec![text_input("convergent content")],
                retain: Some(false),
            })
            .expect("explicit-false retry");
        assert_eq!(still_retained.material.id, material_id);
        assert_eq!(
            materials.membership_calls(),
            1,
            "explicit false never clears membership"
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
                assets: vec![media_input("media-app")],
                retain: None,
            })
            .expect("create");
        let material_id = created.material.id.clone();
        assert_eq!(materials.revision_count(), 1);

        let first = use_cases
            .append_revision(
                &material_id,
                AppendMaterialRevision {
                    title: "V2".into(),
                    assets: vec![media_input("media-app"), text_input("more notes")],
                },
            )
            .expect("first append");
        assert_eq!(materials.revision_count(), 2);

        let retry = use_cases
            .append_revision(
                &material_id,
                AppendMaterialRevision {
                    title: "V2".into(),
                    assets: vec![media_input("media-app"), text_input("more notes")],
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
        assert_eq!(
            materials.revision_count(),
            2,
            "the retry persists no duplicate revision"
        );
        assert_eq!(retry.current_revision.id, first.current_revision.id);

        // Exact revision ownership: read_revision returns the bare revision.
        let read_back = use_cases
            .read_revision(&material_id, &retry.current_revision.id)
            .expect("read revision");
        assert_eq!(read_back.id, retry.current_revision.id);
        assert_eq!(read_back.material_id, material_id);

        let other = use_cases
            .create(CreateLearningMaterial {
                title: "Other".into(),
                assets: vec![text_input("other notes")],
                retain: None,
            })
            .expect("other material");
        let err = use_cases
            .read_revision(&other.material.id, &retry.current_revision.id)
            .expect_err("revision belongs to another material");
        assert!(matches!(
            err,
            ApplicationError::NotFound("material revision")
        ));

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
                assets: vec![media_input("media-list")],
                retain: None,
            })
            .expect("retained material");
        use_cases
            .create(CreateLearningMaterial {
                title: "Temporary".into(),
                assets: vec![text_input("temp notes")],
                retain: Some(false),
            })
            .expect("temporary material");
        assert_eq!(materials.material_count(), 2);

        // The misbehaving repository reports every material; the use case must
        // still return only the retained projection.
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
                assets: vec![text_input("toggle content")],
                retain: Some(false),
            })
            .expect("temporary material");
        let material_id = created.material.id.clone();
        assert_eq!(materials.membership_calls(), 0);

        use_cases.retain(&material_id).expect("retain");
        assert_eq!(materials.membership_calls(), 1);
        let retained = use_cases.retain(&material_id).expect("retain again");
        assert_eq!(
            materials.membership_calls(),
            1,
            "retaining an already-retained material is a no-op"
        );
        assert!(retained.material.retained_at_ms.is_some());

        let unretained = use_cases.unretain(&material_id).expect("unretain");
        assert_eq!(materials.membership_calls(), 2);
        assert!(unretained.material.retained_at_ms.is_none());
        use_cases.unretain(&material_id).expect("unretain again");
        assert_eq!(
            materials.membership_calls(),
            2,
            "unretaining a temporary material is a no-op"
        );

        let err = use_cases
            .unretain(&LearningMaterialId::parse("material-absent").unwrap())
            .expect_err("missing material");
        assert!(matches!(err, ApplicationError::NotFound("material")));
    }

    #[test]
    fn unretain_invokes_only_membership_mutation() {
        let (use_cases, materials, media) = setup();
        media.seed(media_item("media-keep", MediaKind::Video, "fp-keep"));
        let created = use_cases
            .create(CreateLearningMaterial {
                title: "Keep".into(),
                assets: vec![media_input("media-keep")],
                retain: None,
            })
            .expect("create");
        let material_id = created.material.id.clone();
        let revision_ids_before = materials.revision_ids();
        let media_snapshot_before = media.snapshot();
        let get_calls_before = media.get_calls();

        let unretained = use_cases.unretain(&material_id).expect("unretain");
        assert!(unretained.material.retained_at_ms.is_none());
        assert_eq!(
            materials.membership_calls(),
            1,
            "exactly one membership mutation"
        );
        assert_eq!(materials.create_calls(), 1, "no additional create");
        assert_eq!(materials.append_calls(), 0, "no revision append");
        assert_eq!(
            media.get_calls(),
            get_calls_before,
            "the media repository is untouched"
        );
        assert_eq!(
            materials.revision_ids(),
            revision_ids_before,
            "revisions are unchanged"
        );
        assert_eq!(
            media.snapshot(),
            media_snapshot_before,
            "media items are unchanged"
        );

        let bound = use_cases
            .resolve_for_media(&MediaId::parse("media-keep").unwrap())
            .expect("resolve")
            .expect("binding survives unretain");
        assert_eq!(
            bound.material.id, material_id,
            "media bindings are unchanged"
        );
    }

    #[test]
    fn unknown_media_is_not_found_for_create_and_append() {
        let (use_cases, _, media) = setup();
        let err = use_cases
            .create(CreateLearningMaterial {
                title: "Broken".into(),
                assets: vec![media_input("media-missing")],
                retain: None,
            })
            .expect_err("unknown media on create");
        assert!(matches!(err, ApplicationError::NotFound("media")));

        media.seed(media_item("media-real", MediaKind::Audio, "fp-real"));
        let created = use_cases
            .create(CreateLearningMaterial {
                title: "Real".into(),
                assets: vec![media_input("media-real")],
                retain: None,
            })
            .expect("create");
        let err = use_cases
            .append_revision(
                &created.material.id,
                AppendMaterialRevision {
                    title: "Broken append".into(),
                    assets: vec![media_input("media-gone")],
                },
            )
            .expect_err("unknown media on append");
        assert!(matches!(err, ApplicationError::NotFound("media")));
    }

    #[test]
    fn domain_constructors_own_validation_errors() {
        let (use_cases, _, media) = setup();

        let err = use_cases
            .create(CreateLearningMaterial {
                title: "Title".into(),
                assets: vec![text_input("   ")],
                retain: None,
            })
            .expect_err("whitespace-only text");
        assert!(matches!(
            err,
            ApplicationError::Domain(DomainError::WhitespaceOnlyText)
        ));

        let err = use_cases
            .create(CreateLearningMaterial {
                title: "Title".into(),
                assets: vec![],
                retain: None,
            })
            .expect_err("empty assets");
        assert!(matches!(
            err,
            ApplicationError::Domain(DomainError::EmptyValue("LearningMaterial.assets"))
        ));

        let err = use_cases
            .create(CreateLearningMaterial {
                title: "   ".into(),
                assets: vec![text_input("content")],
                retain: None,
            })
            .expect_err("blank title");
        assert!(matches!(
            err,
            ApplicationError::Domain(DomainError::EmptyValue("MaterialRevision.title"))
        ));

        media.seed(media_item("media-dup", MediaKind::Audio, "fp-dup"));
        let created = use_cases
            .create(CreateLearningMaterial {
                title: "Valid".into(),
                assets: vec![media_input("media-dup")],
                retain: None,
            })
            .expect("valid material");

        let err = use_cases
            .append_revision(
                &created.material.id,
                AppendMaterialRevision {
                    title: "   ".into(),
                    assets: vec![media_input("media-dup")],
                },
            )
            .expect_err("blank append title");
        assert!(matches!(
            err,
            ApplicationError::Domain(DomainError::EmptyValue("MaterialRevision.title"))
        ));

        let err = use_cases
            .create(CreateLearningMaterial {
                title: "Duplicates".into(),
                assets: vec![text_input("same"), text_input("same")],
                retain: None,
            })
            .expect_err("duplicate text assets");
        assert!(matches!(
            err,
            ApplicationError::Domain(DomainError::DuplicateAssetId)
        ));

        let err = use_cases
            .append_revision(
                &created.material.id,
                AppendMaterialRevision {
                    title: "Dup media".into(),
                    assets: vec![media_input("media-dup"), media_input("media-dup")],
                },
            )
            .expect_err("duplicate media assets");
        assert!(matches!(
            err,
            ApplicationError::Domain(DomainError::DuplicateAssetId)
        ));

        media.seed(media_item("media-amb", MediaKind::Audio, "fp-amb"));
        let err = use_cases
            .create(CreateLearningMaterial {
                title: "Ambiguous".into(),
                assets: vec![media_input("media-amb"), media_input("media-amb")],
                retain: None,
            })
            .expect_err("ambiguous initial media identity");
        assert!(matches!(
            err,
            ApplicationError::Domain(DomainError::AmbiguousInitialMediaIdentity)
        ));
    }

    #[test]
    fn create_converges_on_an_already_bound_media() {
        let (use_cases, materials, media) = setup();
        media.seed(media_item("media-conv", MediaKind::Audio, "fp-conv"));
        let first = use_cases
            .create(CreateLearningMaterial {
                title: "First".into(),
                assets: vec![media_input("media-conv")],
                retain: Some(false),
            })
            .expect("temporary first material");
        let first_id = first.material.id.clone();
        assert_eq!(materials.create_calls(), 1);
        assert_eq!(materials.append_calls(), 0);

        let converged = use_cases
            .create(CreateLearningMaterial {
                title: "Second".into(),
                assets: vec![media_input("media-conv")],
                retain: None,
            })
            .expect("converged material");
        assert_eq!(
            converged.material.id, first_id,
            "media-bound create converges on the existing material"
        );
        assert_eq!(
            materials.create_calls(),
            1,
            "convergence must not create a new material"
        );
        assert_eq!(
            materials.append_calls(),
            1,
            "convergence appends a revision"
        );
        assert_eq!(
            materials.membership_calls(),
            1,
            "a previously temporary material is retained by default"
        );
        assert!(converged.material.retained_at_ms.is_some());
        assert_eq!(converged.current_revision.title, "Second");

        // Explicit false never clears existing membership.
        let recreated = use_cases
            .create(CreateLearningMaterial {
                title: "Third".into(),
                assets: vec![media_input("media-conv")],
                retain: Some(false),
            })
            .expect("retain false on a retained material");
        assert!(recreated.material.retained_at_ms.is_some());
        assert_eq!(
            materials.membership_calls(),
            1,
            "explicit false never clears membership"
        );
    }

    #[test]
    fn append_accepts_same_material_and_rejects_other_materials() {
        let (use_cases, _, media) = setup();
        media.seed(media_item("media-same", MediaKind::Audio, "fp-same"));
        media.seed(media_item("media-other", MediaKind::Video, "fp-other"));
        let a = use_cases
            .create(CreateLearningMaterial {
                title: "A".into(),
                assets: vec![media_input("media-same")],
                retain: None,
            })
            .expect("material A");
        let b = use_cases
            .create(CreateLearningMaterial {
                title: "B".into(),
                assets: vec![media_input("media-other")],
                retain: None,
            })
            .expect("material B");
        assert_ne!(a.material.id, b.material.id);

        // Same-material append: media already bound to the target material.
        let appended = use_cases
            .append_revision(
                &a.material.id,
                AppendMaterialRevision {
                    title: "A v2".into(),
                    assets: vec![media_input("media-same"), text_input("notes")],
                },
            )
            .expect("same material append");
        assert_eq!(appended.material.id, a.material.id);
        assert_eq!(appended.current_revision.title, "A v2");

        // Cross-material append: media bound to B cannot join A.
        let err = use_cases
            .append_revision(
                &a.material.id,
                AppendMaterialRevision {
                    title: "A v3".into(),
                    assets: vec![media_input("media-other")],
                },
            )
            .expect_err("media belongs to another material");
        assert!(matches!(
            err,
            ApplicationError::Conflict("media rendition belongs to another material")
        ));

        // Unbound media may join any existing material and becomes bound.
        media.seed(media_item("media-fresh", MediaKind::Audio, "fp-fresh"));
        let joined = use_cases
            .append_revision(
                &a.material.id,
                AppendMaterialRevision {
                    title: "A v4".into(),
                    assets: vec![media_input("media-fresh")],
                },
            )
            .expect("unbound media joins the target");
        assert_eq!(joined.material.id, a.material.id);
        let resolved = use_cases
            .resolve_for_media(&MediaId::parse("media-fresh").unwrap())
            .expect("resolve")
            .expect("fresh media is now bound");
        assert_eq!(resolved.material.id, a.material.id);
    }

    #[test]
    fn create_rejects_media_bound_to_different_materials() {
        let (use_cases, _, media) = setup();
        media.seed(media_item("media-x1", MediaKind::Audio, "fp-x1"));
        media.seed(media_item("media-x2", MediaKind::Video, "fp-x2"));
        use_cases
            .create(CreateLearningMaterial {
                title: "X1".into(),
                assets: vec![media_input("media-x1")],
                retain: None,
            })
            .expect("material for x1");
        use_cases
            .create(CreateLearningMaterial {
                title: "X2".into(),
                assets: vec![media_input("media-x2")],
                retain: None,
            })
            .expect("material for x2");

        let err = use_cases
            .create(CreateLearningMaterial {
                title: "Both".into(),
                assets: vec![media_input("media-x1"), media_input("media-x2")],
                retain: None,
            })
            .expect_err("inputs bound to different materials");
        assert!(matches!(
            err,
            ApplicationError::Conflict("media renditions belong to different materials")
        ));
    }

    #[test]
    fn resolve_for_media_returns_none_without_a_binding() {
        let (use_cases, _, media) = setup();
        let none = use_cases
            .resolve_for_media(&MediaId::parse("media-free").unwrap())
            .expect("resolve");
        assert!(none.is_none());

        media.seed(media_item("media-bound", MediaKind::Audio, "fp-bound"));
        let created = use_cases
            .create(CreateLearningMaterial {
                title: "Bound".into(),
                assets: vec![media_input("media-bound")],
                retain: None,
            })
            .expect("material");
        let resolved = use_cases
            .resolve_for_media(&MediaId::parse("media-bound").unwrap())
            .expect("resolve")
            .expect("binding exists");
        assert_eq!(resolved.material.id, created.material.id);
        assert_eq!(resolved.current_revision.id, created.current_revision.id);
    }

    #[test]
    fn read_returns_none_for_missing_and_details_for_present() {
        let (use_cases, _, _) = setup();
        let missing = use_cases
            .read(&LearningMaterialId::parse("material-absent").unwrap())
            .expect("read");
        assert!(missing.is_none());

        let created = use_cases
            .create(CreateLearningMaterial {
                title: "Read me".into(),
                assets: vec![text_input("readable")],
                retain: None,
            })
            .expect("material");
        let read = use_cases
            .read(&created.material.id)
            .expect("read")
            .expect("present");
        assert_eq!(read.material.id, created.material.id);
        assert_eq!(read.current_revision.id, created.current_revision.id);
        assert_eq!(read.shape(), MaterialShape::Text);
    }

    #[test]
    fn current_revision_guard_rejects_missing_and_cross_material_pointers() {
        let (use_cases, materials, media) = setup();
        media.seed(media_item("media-guard", MediaKind::Audio, "fp-guard"));
        let a = use_cases
            .create(CreateLearningMaterial {
                title: "A".into(),
                assets: vec![media_input("media-guard")],
                retain: None,
            })
            .expect("material A");
        let b = use_cases
            .create(CreateLearningMaterial {
                title: "B".into(),
                assets: vec![text_input("b content")],
                retain: None,
            })
            .expect("material B");
        assert_ne!(a.material.id, b.material.id);

        // A valid current revision still assembles details on every path.
        let valid = use_cases
            .read(&a.material.id)
            .expect("read")
            .expect("valid details");
        assert_eq!(valid.current_revision.id, a.current_revision.id);

        // Corruption 1: the pointer names no revision at all. The existing
        // missing-current-revision Repository behavior is preserved.
        materials.set_current_revision_pointer(
            &a.material.id,
            &MaterialRevisionId::from_fingerprint("material-revision", "missing"),
        );
        let err = use_cases
            .read(&a.material.id)
            .expect_err("missing current revision");
        assert!(matches!(
            err,
            ApplicationError::Repository(message) if message == "current revision is missing"
        ));

        // Corruption 2: the pointer names a revision owned by another
        // material. Every details path must reject it as repository corruption
        // instead of assembling cross-material MaterialDetails.
        materials.set_current_revision_pointer(&a.material.id, &b.current_revision.id);
        let corrupted = "current revision belongs to another material";
        let err = use_cases
            .read(&a.material.id)
            .expect_err("cross-material current revision on read");
        assert!(matches!(
            err,
            ApplicationError::Repository(message) if message == corrupted
        ));
        let err = use_cases
            .resolve_for_media(&MediaId::parse("media-guard").unwrap())
            .expect_err("cross-material current revision on resolve_for_media");
        assert!(matches!(
            err,
            ApplicationError::Repository(message) if message == corrupted
        ));
        let err = use_cases
            .list_retained()
            .expect_err("cross-material current revision on list_retained");
        assert!(matches!(
            err,
            ApplicationError::Repository(message) if message == corrupted
        ));
    }

    fn assert_not_configured<T: std::fmt::Debug>(result: Result<T, ApplicationError>) {
        match result {
            Err(ApplicationError::Repository(message)) => {
                assert_eq!(message, "learning material repository is not configured")
            }
            other => panic!("expected not-configured repository error, got: {other:?}"),
        }
    }

    #[test]
    fn disabled_material_repository_errors_as_not_configured() {
        let repository = DisabledMaterialRepository;
        let asset = MaterialAsset::DocumentText(
            DocumentTextAsset::new("disabled content", None).expect("valid text asset"),
        );
        let material_id =
            initial_material_id(std::slice::from_ref(&asset)).expect("deterministic material id");
        let revision = MaterialRevision::new(material_id.clone(), "Disabled", vec![asset], 1)
            .expect("valid revision");
        let material = LearningMaterial::new(&revision, None, 1, 1).expect("valid material");
        let media_id = MediaId::parse("media-disabled").expect("valid media id");

        assert_not_configured(repository.get_material(&material_id));
        assert_not_configured(repository.create_material(&material, &revision));
        assert_not_configured(repository.append_revision(&material_id, &revision, 1));
        assert_not_configured(repository.get_revision(&revision.id));
        assert_not_configured(repository.list_retained_materials());
        assert_not_configured(repository.set_library_membership(&material_id, Some(1), 1));
        assert_not_configured(repository.material_for_media(&media_id));
    }
}
