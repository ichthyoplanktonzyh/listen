//! Material Capability projection and attempt use cases (Phase 1 contract
//! 4.0.0).
//!
//! The projection is the observable five-state view over one Material:
//! `available`, `derivable`, `generating`, `unavailable`, or `failed_attempt`.
//! Attempts are durable facts owned here; a failed attempt never rewrites the
//! facts of an earlier attempt.

use std::sync::Arc;

use domain::{
    CapabilityAttempt, CapabilityAttemptStatus, LearningMaterialId, MaterialCapability,
    MaterialCapabilityProjection, project_capability,
};

use crate::{ApplicationError, MaterialRepository, PackageLifecycleRepository};

/// Use cases that own Material capability projection and production attempts.
#[derive(Clone)]
pub struct MaterialCapabilityUseCases {
    materials: Arc<dyn MaterialRepository>,
    package_lifecycle: Arc<dyn PackageLifecycleRepository>,
    attempts: Arc<dyn CapabilityAttemptRepository>,
}

impl MaterialCapabilityUseCases {
    pub fn new(
        materials: Arc<dyn MaterialRepository>,
        package_lifecycle: Arc<dyn PackageLifecycleRepository>,
        attempts: Arc<dyn CapabilityAttemptRepository>,
    ) -> Self {
        Self {
            materials,
            package_lifecycle,
            attempts,
        }
    }

    /// Projects all four capabilities for the material's actual current
    /// revision against the adopted composition and the durable attempt
    /// evidence. The material must exist (`NotFound("material")`).
    pub fn project(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Vec<MaterialCapabilityProjection>, ApplicationError> {
        let material = self
            .materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let revision = self
            .materials
            .get_revision(&material.current_revision_id)?
            .ok_or_else(|| ApplicationError::Repository("current revision is missing".into()))?;
        let adopted = self.package_lifecycle.get_adoption(material_id)?;
        // The adoption names a release; the adopted composition facts are the
        // installed release's immutable resource and rendition facts.
        let adopted_installation = match &adopted {
            Some(plan) => self
                .package_lifecycle
                .get_installation(material_id, &plan.release_id)?,
            None => None,
        };
        let attempts = self.attempts.list_attempts(material_id)?;
        Ok([
            MaterialCapability::Read,
            MaterialCapability::Listen,
            MaterialCapability::Watch,
            MaterialCapability::SynchronizedReadListen,
        ]
        .map(|capability| {
            project_capability(
                capability,
                &revision,
                adopted_installation.as_ref(),
                &attempts,
            )
        })
        .to_vec())
    }

    /// Starts a production attempt for one capability. Retrying a capability
    /// creates a new attempt and never rewrites the old attempt's facts.
    pub fn start_attempt(
        &self,
        material_id: &LearningMaterialId,
        capability: MaterialCapability,
        started_at_ms: u64,
    ) -> Result<CapabilityAttempt, ApplicationError> {
        self.materials
            .get_material(material_id)?
            .ok_or(ApplicationError::NotFound("material"))?;
        let attempt = CapabilityAttempt::start(material_id.clone(), capability, started_at_ms);
        self.attempts.save_attempt(&attempt)?;
        Ok(attempt)
    }

    /// Finalizes a running attempt as succeeded or failed. The attempt must
    /// exist, belong to the material, and still be running; a failed attempt
    /// carries a stable reason. Returns the finalized attempt.
    pub fn finalize_attempt(
        &self,
        material_id: &LearningMaterialId,
        attempt_id: &domain::CapabilityAttemptId,
        outcome: AttemptOutcome,
        finished_at_ms: u64,
    ) -> Result<CapabilityAttempt, ApplicationError> {
        let attempts = self.attempts.list_attempts(material_id)?;
        let mut attempt = attempts
            .into_iter()
            .find(|attempt| &attempt.attempt_id == attempt_id)
            .ok_or(ApplicationError::NotFound("capability attempt"))?;
        if attempt.status != CapabilityAttemptStatus::Running {
            return Err(ApplicationError::Conflict(
                "capability attempt is not running",
            ));
        }
        match outcome {
            AttemptOutcome::Succeeded {
                tool_id,
                tool_version,
            } => {
                attempt.succeed(finished_at_ms, tool_id, tool_version);
            }
            AttemptOutcome::Failed { reason } => {
                attempt
                    .fail(finished_at_ms, reason)
                    .map_err(crate::learning_material::domain_error)?;
            }
        }
        self.attempts.save_attempt(&attempt)?;
        Ok(attempt)
    }
}

/// Outcome of a finalized capability production attempt.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AttemptOutcome {
    Succeeded {
        tool_id: String,
        tool_version: String,
    },
    Failed {
        reason: String,
    },
}

/// Persistence contract for capability production attempts.
pub trait CapabilityAttemptRepository: Send + Sync {
    fn save_attempt(&self, attempt: &CapabilityAttempt) -> Result<(), ApplicationError>;

    fn list_attempts(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Vec<CapabilityAttempt>, ApplicationError>;
}

pub(crate) struct DisabledCapabilityAttemptRepository;

impl CapabilityAttemptRepository for DisabledCapabilityAttemptRepository {
    fn save_attempt(&self, _attempt: &CapabilityAttempt) -> Result<(), ApplicationError> {
        Err(ApplicationError::Repository(
            "capability attempt repository is not configured".into(),
        ))
    }

    fn list_attempts(
        &self,
        _material_id: &LearningMaterialId,
    ) -> Result<Vec<CapabilityAttempt>, ApplicationError> {
        Err(ApplicationError::Repository(
            "capability attempt repository is not configured".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};

    use domain::{DocumentRendition, MaterialRevision, Rendition, RenditionOrigin};

    use crate::PreparedPackageInstallation;

    #[derive(Default, Clone)]
    struct FakeAttemptRepository {
        attempts: Arc<Mutex<HashMap<String, Vec<CapabilityAttempt>>>>,
    }

    impl CapabilityAttemptRepository for FakeAttemptRepository {
        fn save_attempt(&self, attempt: &CapabilityAttempt) -> Result<(), ApplicationError> {
            let mut store = self.attempts.lock().unwrap();
            let attempts = store
                .entry(attempt.material_id.as_str().to_owned())
                .or_default();
            if let Some(existing) = attempts
                .iter_mut()
                .find(|existing| existing.attempt_id == attempt.attempt_id)
            {
                *existing = attempt.clone();
            } else {
                attempts.push(attempt.clone());
            }
            Ok(())
        }

        fn list_attempts(
            &self,
            material_id: &LearningMaterialId,
        ) -> Result<Vec<CapabilityAttempt>, ApplicationError> {
            Ok(self
                .attempts
                .lock()
                .unwrap()
                .get(material_id.as_str())
                .cloned()
                .unwrap_or_default())
        }
    }

    #[derive(Default, Clone)]
    struct FakeMaterials {
        materials: Arc<Mutex<HashMap<String, domain::LearningMaterial>>>,
        revisions: Arc<Mutex<HashMap<String, MaterialRevision>>>,
    }

    impl FakeMaterials {
        fn create_text_material(&self, title: &str, text: &str) -> LearningMaterialId {
            let now = 1;
            let renditions = vec![Rendition::Document(
                DocumentRendition::new(
                    RenditionOrigin::Source,
                    "text/plain",
                    None,
                    text.to_owned(),
                    None,
                    None,
                    None,
                )
                .expect("valid rendition"),
            )];
            let material_id =
                domain::initial_material_id(&[], &renditions).expect("valid material id");
            let revision =
                MaterialRevision::new(material_id.clone(), title, Vec::new(), renditions, now)
                    .expect("valid revision");
            let material = domain::LearningMaterial::new(&revision, Some(now), now, now)
                .expect("valid material");
            self.materials
                .lock()
                .unwrap()
                .insert(material.id.as_str().to_owned(), material.clone());
            self.revisions
                .lock()
                .unwrap()
                .insert(revision.id.as_str().to_owned(), revision);
            material.id
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
            revision_id: &domain::MaterialRevisionId,
        ) -> Result<Option<MaterialRevision>, ApplicationError> {
            Ok(self
                .revisions
                .lock()
                .unwrap()
                .get(revision_id.as_str())
                .cloned())
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

    struct NoPackageLifecycle;

    impl PackageLifecycleRepository for NoPackageLifecycle {
        fn save_installation(
            &self,
            _installation: &PreparedPackageInstallation,
        ) -> Result<domain::PackageInstallation, ApplicationError> {
            unreachable!("not used in these tests")
        }
        fn get_installation(
            &self,
            _material_id: &LearningMaterialId,
            _release_id: &domain::PackageReleaseId,
        ) -> Result<Option<domain::PackageInstallation>, ApplicationError> {
            unreachable!("not used in these tests")
        }
        fn list_installations(
            &self,
            _material_id: &LearningMaterialId,
        ) -> Result<Vec<domain::PackageInstallation>, ApplicationError> {
            unreachable!("not used in these tests")
        }
        fn get_adoption(
            &self,
            _material_id: &LearningMaterialId,
        ) -> Result<Option<domain::AdoptionCommitPlan>, ApplicationError> {
            Ok(None)
        }
        fn commit_adoption(
            &self,
            _plan: &domain::AdoptionCommitPlan,
        ) -> Result<domain::AdoptionCommitPlan, ApplicationError> {
            unreachable!("not used in these tests")
        }
    }

    fn setup() -> (MaterialCapabilityUseCases, FakeMaterials) {
        let materials = FakeMaterials::default();
        let use_cases = MaterialCapabilityUseCases::new(
            Arc::new(materials.clone()),
            Arc::new(NoPackageLifecycle),
            Arc::new(FakeAttemptRepository::default()),
        );
        (use_cases, materials)
    }

    #[test]
    fn attempt_lifecycle_is_durable_and_retries_never_rewrite_old_facts() {
        let (use_cases, materials) = setup();
        let material_id = materials.create_text_material("Doc", "hello world");
        let first = use_cases
            .start_attempt(&material_id, MaterialCapability::Listen, 5)
            .expect("start");
        let failed = use_cases
            .finalize_attempt(
                &material_id,
                &first.attempt_id,
                AttemptOutcome::Failed {
                    reason: "provider unavailable".into(),
                },
                10,
            )
            .expect("finalize");
        assert_eq!(failed.status, CapabilityAttemptStatus::Failed);
        assert_eq!(
            failed.failure_reason.as_deref(),
            Some("provider unavailable")
        );

        // A retry creates a new attempt and never rewrites the first.
        let retry = use_cases
            .start_attempt(&material_id, MaterialCapability::Listen, 11)
            .expect("retry");
        assert_ne!(retry.attempt_id, first.attempt_id);
        let finished = use_cases
            .finalize_attempt(
                &material_id,
                &retry.attempt_id,
                AttemptOutcome::Succeeded {
                    tool_id: "listen-gen".into(),
                    tool_version: "0.4.0".into(),
                },
                20,
            )
            .expect("finalize");
        assert_eq!(finished.status, CapabilityAttemptStatus::Succeeded);

        let projection = use_cases
            .project(&material_id)
            .expect("project")
            .into_iter()
            .find(|projection| projection.capability == MaterialCapability::Listen)
            .expect("listen projection");
        // The latest attempt is the succeeded retry; without an adoption the
        // capability is still structurally derivable.
        assert_eq!(
            projection
                .latest_attempt
                .as_ref()
                .expect("attempt")
                .attempt_id,
            retry.attempt_id
        );
        assert_eq!(projection.status, domain::CapabilityStatus::Derivable);
    }

    #[test]
    fn finalizing_an_unknown_or_finished_attempt_is_refused() {
        let (use_cases, materials) = setup();
        let material_id = materials.create_text_material("Doc", "hello world");
        let unknown = domain::CapabilityAttemptId::parse("attempt-missing").expect("valid id");
        let err = use_cases
            .finalize_attempt(
                &material_id,
                &unknown,
                AttemptOutcome::Failed {
                    reason: "reason".into(),
                },
                10,
            )
            .expect_err("unknown attempt");
        assert!(matches!(
            err,
            ApplicationError::NotFound("capability attempt")
        ));

        let attempt = use_cases
            .start_attempt(&material_id, MaterialCapability::Listen, 1)
            .expect("start");
        use_cases
            .finalize_attempt(
                &material_id,
                &attempt.attempt_id,
                AttemptOutcome::Failed {
                    reason: "reason".into(),
                },
                2,
            )
            .expect("finalize");
        let err = use_cases
            .finalize_attempt(
                &material_id,
                &attempt.attempt_id,
                AttemptOutcome::Succeeded {
                    tool_id: "listen-gen".into(),
                    tool_version: "0.4.0".into(),
                },
                3,
            )
            .expect_err("already finished");
        assert!(matches!(
            err,
            ApplicationError::Conflict("capability attempt is not running")
        ));
    }

    #[test]
    fn empty_failure_reasons_are_rejected() {
        let (use_cases, materials) = setup();
        let material_id = materials.create_text_material("Doc", "hello world");
        let attempt = use_cases
            .start_attempt(&material_id, MaterialCapability::Listen, 1)
            .expect("start");
        let err = use_cases
            .finalize_attempt(
                &material_id,
                &attempt.attempt_id,
                AttemptOutcome::Failed {
                    reason: "   ".into(),
                },
                2,
            )
            .expect_err("blank reason");
        assert!(matches!(err, ApplicationError::Invalid(_)));
    }
}
