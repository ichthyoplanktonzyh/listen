//! Source Identity resolution use cases (Phase 1 contract 4.0.0).
//!
//! Discovered items resolve through their source-scoped canonical identity;
//! evidence fields are typed facts recorded with the mapping, never identity
//! substitutes. Subscription, discovery, acquisition, retention, installation,
//! and adoption remain distinct facts even when one learner action coordinates
//! them.

use std::sync::Arc;

use domain::{LearningMaterialId, SourceIdentityMapping, SourceItemIdentity};

use crate::{ApplicationError, MaterialRepository};

/// Persistence contract for Source Identity mappings.
pub trait SourceIdentityRepository: Send + Sync {
    /// Upserts the mapping under its canonical key, replacing the evidence
    /// facts and target with the newest authorized facts.
    fn save_mapping(&self, mapping: &SourceIdentityMapping) -> Result<(), ApplicationError>;

    /// Resolves the mapping for the canonical key, or `None` when the item was
    /// never mapped.
    fn resolve(
        &self,
        source_item: &SourceItemIdentity,
    ) -> Result<Option<SourceIdentityMapping>, ApplicationError>;
}

pub(crate) struct DisabledSourceIdentityRepository;

impl SourceIdentityRepository for DisabledSourceIdentityRepository {
    fn save_mapping(&self, _mapping: &SourceIdentityMapping) -> Result<(), ApplicationError> {
        Err(ApplicationError::Repository(
            "source identity repository is not configured".into(),
        ))
    }

    fn resolve(
        &self,
        _source_item: &SourceItemIdentity,
    ) -> Result<Option<SourceIdentityMapping>, ApplicationError> {
        Err(ApplicationError::Repository(
            "source identity repository is not configured".into(),
        ))
    }
}

/// Use cases that own Source Identity mapping and resolution.
#[derive(Clone)]
pub struct SourceIdentityUseCases {
    mappings: Arc<dyn SourceIdentityRepository>,
    materials: Arc<dyn MaterialRepository>,
}

impl SourceIdentityUseCases {
    pub fn new(
        mappings: Arc<dyn SourceIdentityRepository>,
        materials: Arc<dyn MaterialRepository>,
    ) -> Self {
        Self {
            mappings,
            materials,
        }
    }

    /// Records a mapping from a discovered item to an exact Material Revision.
    /// The target material and revision must exist and the revision must
    /// belong to the material, otherwise `NotFound("material")` /
    /// `NotFound("material revision")`. Returns the recorded mapping.
    pub fn register(
        &self,
        mapping: SourceIdentityMapping,
    ) -> Result<SourceIdentityMapping, ApplicationError> {
        let material = self
            .materials
            .get_material(&mapping.material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        if mapping.material_revision_id != material.current_revision_id {
            return Err(ApplicationError::NotFound("material revision"));
        }
        self.mappings.save_mapping(&mapping)?;
        Ok(mapping)
    }

    /// Resolves the mapping for the canonical key, or `None` when the item was
    /// never mapped. Evidence never substitutes for the canonical key.
    pub fn resolve(
        &self,
        source_item: &SourceItemIdentity,
    ) -> Result<Option<SourceIdentityMapping>, ApplicationError> {
        self.mappings.resolve(source_item)
    }

    /// Resolves to the material id for a canonical key when a mapping exists.
    pub fn resolve_material(
        &self,
        source_item: &SourceItemIdentity,
    ) -> Result<Option<LearningMaterialId>, ApplicationError> {
        Ok(self
            .mappings
            .resolve(source_item)?
            .map(|mapping| mapping.material_id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};

    use domain::{
        DocumentRendition, MaterialRevision, Rendition, RenditionOrigin, SourceItemEvidence,
    };

    #[derive(Default, Clone)]
    struct FakeMappings {
        store: Arc<Mutex<HashMap<(String, String), SourceIdentityMapping>>>,
    }

    impl SourceIdentityRepository for FakeMappings {
        fn save_mapping(&self, mapping: &SourceIdentityMapping) -> Result<(), ApplicationError> {
            self.store.lock().unwrap().insert(
                (
                    mapping.source_item.source_id.as_str().to_owned(),
                    mapping.source_item.item_id.as_str().to_owned(),
                ),
                mapping.clone(),
            );
            Ok(())
        }

        fn resolve(
            &self,
            source_item: &SourceItemIdentity,
        ) -> Result<Option<SourceIdentityMapping>, ApplicationError> {
            Ok(self
                .store
                .lock()
                .unwrap()
                .get(&(
                    source_item.source_id.as_str().to_owned(),
                    source_item.item_id.as_str().to_owned(),
                ))
                .cloned())
        }
    }

    #[derive(Default, Clone)]
    struct FakeMaterials {
        materials: Arc<Mutex<HashMap<String, domain::LearningMaterial>>>,
    }

    impl FakeMaterials {
        fn seed(&self, material: domain::LearningMaterial) {
            self.materials
                .lock()
                .unwrap()
                .insert(material.id.as_str().to_owned(), material);
        }
    }

    impl MaterialRepository for FakeMaterials {
        fn create_material(
            &self,
            _material: &domain::LearningMaterial,
            _revision: &MaterialRevision,
        ) -> Result<domain::LearningMaterial, ApplicationError> {
            unreachable!("not used in these tests")
        }
        fn append_revision(
            &self,
            _material_id: &LearningMaterialId,
            _revision: &MaterialRevision,
            _updated_at_ms: u64,
        ) -> Result<domain::LearningMaterial, ApplicationError> {
            unreachable!("not used in these tests")
        }
        fn get_material(
            &self,
            material_id: &LearningMaterialId,
        ) -> Result<Option<domain::LearningMaterial>, ApplicationError> {
            Ok(self
                .materials
                .lock()
                .unwrap()
                .get(material_id.as_str())
                .cloned())
        }
        fn get_revision(
            &self,
            _revision_id: &domain::MaterialRevisionId,
        ) -> Result<Option<MaterialRevision>, ApplicationError> {
            unreachable!("not used in these tests")
        }
        fn list_retained_materials(
            &self,
        ) -> Result<Vec<domain::LearningMaterial>, ApplicationError> {
            Ok(Vec::new())
        }
        fn set_library_membership(
            &self,
            _material_id: &LearningMaterialId,
            _retained_at_ms: Option<u64>,
            _updated_at_ms: u64,
        ) -> Result<domain::LearningMaterial, ApplicationError> {
            unreachable!("not used in these tests")
        }
        fn material_for_media(
            &self,
            _media_id: &domain::MediaId,
        ) -> Result<Option<domain::LearningMaterial>, ApplicationError> {
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

    fn material(revision: &MaterialRevision) -> domain::LearningMaterial {
        domain::LearningMaterial::new(revision, None, 1, 1).expect("valid material")
    }

    fn revision() -> MaterialRevision {
        let content = "content";
        let asset = domain::SourceAsset::new(
            "text/plain",
            content.len() as u64,
            {
                use sha2::Digest as _;
                hex::encode(sha2::Sha256::digest(content.as_bytes()))
            },
            domain::SourceAssetBinding::Managed,
            domain::SourceAssetAvailability::Available,
            1,
        )
        .expect("valid source asset");
        let renditions = vec![Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                None,
                asset.sha256_digest.clone(),
                asset.byte_length,
                Some(asset.id.clone()),
                None,
                None,
            )
            .expect("valid rendition"),
        )];
        let material_id = domain::initial_material_id(std::slice::from_ref(&asset), &renditions)
            .expect("valid material id");
        MaterialRevision::new(material_id, "Title", vec![asset], renditions, 1)
            .expect("valid revision")
    }

    fn source_item() -> SourceItemIdentity {
        SourceItemIdentity {
            source_id: domain::ContentSourceId::parse("rss:https://example.com/feed.xml")
                .expect("valid source"),
            item_id: domain::SourceItemId::parse("item-1").expect("valid item"),
        }
    }

    #[test]
    fn register_validates_the_target_revision_and_resolves_by_canonical_key() {
        let mappings = FakeMappings::default();
        let materials = FakeMaterials::default();
        let rev = revision();
        let material = material(&rev);
        materials.seed(material.clone());
        let use_cases =
            SourceIdentityUseCases::new(Arc::new(mappings), Arc::new(materials.clone()));

        let mapping = SourceIdentityMapping {
            source_item: source_item(),
            evidence: SourceItemEvidence {
                feed_item_id: Some("guid-1".into()),
                entry_url: Some("https://example.com/entry".into()),
                enclosure_urls: Vec::new(),
                file_sha256: None,
                title: Some("Entry".into()),
            },
            material_id: material.id.clone(),
            material_revision_id: rev.id.clone(),
            mapped_at_ms: 10,
        };
        use_cases.register(mapping.clone()).expect("registered");
        let resolved = use_cases
            .resolve(&source_item())
            .expect("resolved")
            .expect("mapping");
        assert_eq!(resolved, mapping);
        assert_eq!(
            use_cases
                .resolve_material(&source_item())
                .expect("resolved"),
            Some(material.id.clone())
        );

        // A stale revision under the same material is refused.
        let stale = SourceIdentityMapping {
            source_item: source_item(),
            evidence: mapping.evidence.clone(),
            material_id: material.id.clone(),
            material_revision_id: domain::MaterialRevisionId::parse("stale-revision")
                .expect("valid id"),
            mapped_at_ms: 11,
        };
        let err = use_cases.register(stale).expect_err("stale revision");
        assert!(matches!(
            err,
            ApplicationError::NotFound("material revision")
        ));
    }

    #[test]
    fn resolve_never_substitutes_evidence_for_the_canonical_key() {
        let use_cases = SourceIdentityUseCases::new(
            Arc::new(FakeMappings::default()),
            Arc::new(FakeMaterials::default()),
        );
        assert!(
            use_cases
                .resolve(&source_item())
                .expect("resolved")
                .is_none()
        );
    }
}
