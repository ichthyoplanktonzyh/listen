//! Package lifecycle facts and rules for the learner-facing Package
//! Installation and Learning Edition Adoption intents.
//!
//! This module owns the immutable installed-release facts and the pure,
//! deterministic adoption rule. It deliberately contains no file path,
//! archive, repository, or HTTP concepts, and it never carries raw payloads,
//! manifests, or learner media paths: only the identity, availability,
//! provenance, review, and selection facts that later persistence needs.
//!
//! Installation is candidate-only: it validates availability facts and never
//! adopts an Edition or changes any active selection. Adoption is a separate
//! explicit intent that resolves one coherent release from the immutable
//! installed facts through [`adoption_commit_plan`].

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    LanguageCode, LearningEditionId, LearningMaterialId, MaterialRevisionId, PackageReleaseId,
};

/// Availability of one package resource. Candidate resources may be selected
/// by an adoption; missing and opaque resources are explicit unavailable
/// facts that are never selected.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PackageResourceAvailability {
    /// Known payload schema, present, and verified.
    Available,
    /// Known payload schema but the payload blob is absent.
    Missing,
    /// Unknown payload schema, preserved as verified opaque metadata.
    Opaque,
}

/// Resource role within an Edition: the learner-facing base content or an
/// assistance resource for a support language.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PackageResourceRole {
    Base,
    Assistance,
}

/// Immutable review fact attached to a package resource.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PackageReviewStatus {
    Unreviewed,
    MachineChecked,
    HumanReviewed,
}

/// Immutable producer provenance facts of a package resource. Raw provider
/// output never appears here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackageResourceProvenance {
    pub created_at_ms: u64,
    pub tool_id: String,
    pub tool_version: String,
    pub provider_id: Option<String>,
    pub provider_version: Option<String>,
    pub model_id: Option<String>,
    pub model_version: Option<String>,
    pub config_sha256: Option<String>,
}

/// One immutable resource fact of a package release: identity, availability,
/// dependency closure edges, provenance, and review status. The payload bytes
/// and manifest are never retained.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackageResourceFact {
    pub resource_id: String,
    pub kind: String,
    pub schema: String,
    pub role: PackageResourceRole,
    pub required: bool,
    pub availability: PackageResourceAvailability,
    pub content_language: Option<LanguageCode>,
    pub support_languages: Vec<LanguageCode>,
    pub dependencies: Vec<String>,
    pub payload_digest: String,
    pub payload_size_bytes: u64,
    pub provenance: PackageResourceProvenance,
    pub review_status: PackageReviewStatus,
    pub quality_warnings: Vec<String>,
}

/// One immutable media rendition fact of a package release. Only the kind,
/// digest, size, and availability snapshot are retained; media paths never
/// enter this module.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackageRenditionFact {
    pub rendition_id: String,
    pub kind: String,
    pub media_type: String,
    pub available: bool,
    pub media_digest: String,
    pub media_size_bytes: u64,
}

/// One Learning Edition of a learning material revision, as declared by an
/// installed package release.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LearningEdition {
    pub edition_id: LearningEditionId,
    pub title: String,
    pub target_language: LanguageCode,
    pub support_languages: Vec<LanguageCode>,
}

/// An immutable prepared installation: exactly one release of one Edition of
/// one Material Revision, with the verified resource, rendition, provenance,
/// review, and availability facts. The source `.listenpkg` path, blob paths,
/// raw manifest JSON, and learner media paths are never retained.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PackageInstallation {
    pub release_id: PackageReleaseId,
    pub release_created_at_ms: u64,
    pub material_id: LearningMaterialId,
    pub material_revision_id: MaterialRevisionId,
    pub edition: LearningEdition,
    pub resources: Vec<PackageResourceFact>,
    pub renditions: Vec<PackageRenditionFact>,
    pub installed_at_ms: u64,
}

/// One resolved active selection for an exclusive resource family.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExclusiveSelection {
    pub family: String,
    pub resource_id: String,
}

/// The deterministic, dependency-closed adoption commit plan for one
/// installed release. Carries every fact the persistence adapter needs to
/// commit the adoption and all supported active-selection changes together;
/// no caller ever coordinates individual resource writes.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AdoptionCommitPlan {
    pub release_id: PackageReleaseId,
    pub material_id: LearningMaterialId,
    pub material_revision_id: MaterialRevisionId,
    pub edition: LearningEdition,
    /// Every available candidate resource, sorted by resource id.
    pub selected_resource_ids: Vec<String>,
    /// The resolved per-family active selections, sorted by family.
    pub exclusive_selections: Vec<ExclusiveSelection>,
    /// Every available media rendition, sorted by rendition id.
    pub selected_rendition_ids: Vec<String>,
    pub adopted_at_ms: u64,
}

/// Pure adoption-rule failures. Stale-revision and absent-installation
/// failures are application facts and stay in the application layer.
#[derive(Debug, Error, PartialEq, Eq, Clone)]
pub enum PackageLifecycleError {
    #[error("required package resource {resource_id} is not available")]
    MissingRequiredResource { resource_id: String },
    #[error("package resource {resource_id} depends on unavailable resource {dependency_id}")]
    BrokenDependencyClosure {
        resource_id: String,
        dependency_id: String,
    },
    #[error(
        "multiple candidate resources in one exclusive resource family ({family}): {resource_ids:?}"
    )]
    AmbiguousExclusiveFamily {
        family: String,
        resource_ids: Vec<String>,
    },
}

/// Resolves the deterministic adoption commit plan for an installed release.
///
/// The rule is order-independent and never selects by incidental vector,
/// filesystem, or database order:
///
/// 1. Every required resource must be available.
/// 2. Every available candidate's dependency closure must be available;
///    an available resource may not depend on a missing or opaque resource.
/// 3. At most one available candidate may exist in any exclusive resource
///    family; more than one is rejected rather than guessed.
/// 4. The selected set is every available candidate, the per-family active
///    selections are resolved from the exclusive families, and every
///    available rendition is selected. All id lists are sorted.
pub fn adoption_commit_plan(
    installation: &PackageInstallation,
    adopted_at_ms: u64,
) -> Result<AdoptionCommitPlan, PackageLifecycleError> {
    let by_id: HashMap<&str, &PackageResourceFact> = installation
        .resources
        .iter()
        .map(|resource| (resource.resource_id.as_str(), resource))
        .collect();

    // 1. Required resources must be available.
    for resource in &installation.resources {
        if resource.required && resource.availability != PackageResourceAvailability::Available {
            return Err(PackageLifecycleError::MissingRequiredResource {
                resource_id: resource.resource_id.clone(),
            });
        }
    }

    // 2. Every available candidate's dependency closure must be available.
    for resource in &installation.resources {
        if resource.availability != PackageResourceAvailability::Available {
            continue;
        }
        for dependency_id in &resource.dependencies {
            let broken = match by_id.get(dependency_id.as_str()) {
                Some(dependency)
                    if dependency.availability == PackageResourceAvailability::Available =>
                {
                    continue;
                }
                _ => true,
            };
            if broken {
                return Err(PackageLifecycleError::BrokenDependencyClosure {
                    resource_id: resource.resource_id.clone(),
                    dependency_id: dependency_id.clone(),
                });
            }
        }
    }

    // 3. Exclusive families may hold at most one available candidate. Family
    // membership is a pure fact of kind and declared languages, so the
    // rejection is independent of any storage order.
    let mut families: HashMap<String, Vec<String>> = HashMap::new();
    for resource in &installation.resources {
        if resource.availability != PackageResourceAvailability::Available {
            continue;
        }
        for family in exclusive_families(resource) {
            families
                .entry(family)
                .or_default()
                .push(resource.resource_id.clone());
        }
    }
    let mut ambiguous: Vec<(&String, &Vec<String>)> =
        families.iter().filter(|(_, ids)| ids.len() > 1).collect();
    ambiguous.sort_by(|(family_a, _), (family_b, _)| family_a.cmp(family_b));
    if let Some((family, ids)) = ambiguous.first() {
        let mut resource_ids = (*ids).clone();
        resource_ids.sort();
        return Err(PackageLifecycleError::AmbiguousExclusiveFamily {
            family: (*family).clone(),
            resource_ids,
        });
    }

    // 4. Deterministic selection from the immutable facts.
    let mut selected_resource_ids: Vec<String> = installation
        .resources
        .iter()
        .filter(|resource| resource.availability == PackageResourceAvailability::Available)
        .map(|resource| resource.resource_id.clone())
        .collect();
    selected_resource_ids.sort();

    let mut exclusive_selections: Vec<ExclusiveSelection> = families
        .into_iter()
        .map(|(family, mut ids)| {
            ids.sort();
            ExclusiveSelection {
                family,
                resource_id: ids.pop().expect("family has one available candidate"),
            }
        })
        .collect();
    exclusive_selections.sort_by(|a, b| a.family.cmp(&b.family));

    let mut selected_rendition_ids: Vec<String> = installation
        .renditions
        .iter()
        .filter(|rendition| rendition.available)
        .map(|rendition| rendition.rendition_id.clone())
        .collect();
    selected_rendition_ids.sort();

    Ok(AdoptionCommitPlan {
        release_id: installation.release_id.clone(),
        material_id: installation.material_id.clone(),
        material_revision_id: installation.material_revision_id.clone(),
        edition: installation.edition.clone(),
        selected_resource_ids,
        exclusive_selections,
        selected_rendition_ids,
        adopted_at_ms,
    })
}

/// The exclusive families a resource belongs to. Base content kinds are
/// exclusive per kind; translations are exclusive per declared support
/// language so one Edition may carry several language translations.
fn exclusive_families(resource: &PackageResourceFact) -> Vec<String> {
    match resource.kind.as_str() {
        "document_text"
        | "timed_text_track"
        | "subtitle_text_track"
        | "word_timeline"
        | "phone_timeline"
        | "sense_group_analysis"
        | "word_acoustics"
        | "prosody_analysis" => vec![format!("exclusive:{}", resource.kind)],
        "translation" => resource
            .support_languages
            .iter()
            .map(|language| format!("translation:{}", language.as_str()))
            .collect(),
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn language(code: &str) -> LanguageCode {
        LanguageCode::parse(code).expect("valid language code")
    }

    fn edition(edition_id: &str) -> LearningEdition {
        LearningEdition {
            edition_id: LearningEditionId::parse(edition_id).expect("valid edition id"),
            title: format!("Edition {edition_id}"),
            target_language: language("en"),
            support_languages: vec![language("zh-Hans")],
        }
    }

    fn resource(
        resource_id: &str,
        kind: &str,
        required: bool,
        availability: PackageResourceAvailability,
        dependencies: &[&str],
    ) -> PackageResourceFact {
        PackageResourceFact {
            resource_id: resource_id.to_owned(),
            kind: kind.to_owned(),
            schema: format!("listen.payload.{kind}.v1"),
            role: PackageResourceRole::Base,
            required,
            availability,
            content_language: Some(language("en")),
            support_languages: Vec::new(),
            dependencies: dependencies.iter().map(|id| (*id).to_owned()).collect(),
            payload_digest: format!("sha256:{resource_id}"),
            payload_size_bytes: 1,
            provenance: PackageResourceProvenance {
                created_at_ms: 1,
                tool_id: "listen-gen".into(),
                tool_version: "0.4.0".into(),
                provider_id: None,
                provider_version: None,
                model_id: None,
                model_version: None,
                config_sha256: None,
            },
            review_status: PackageReviewStatus::MachineChecked,
            quality_warnings: Vec::new(),
        }
    }

    fn translation(resource_id: &str, support_language: &str) -> PackageResourceFact {
        let mut resource = resource(
            resource_id,
            "translation",
            false,
            PackageResourceAvailability::Available,
            &["document-1"],
        );
        resource.role = PackageResourceRole::Assistance;
        resource.content_language = None;
        resource.support_languages = vec![language(support_language)];
        resource
    }

    fn installation(resources: Vec<PackageResourceFact>) -> PackageInstallation {
        PackageInstallation {
            release_id: PackageReleaseId::parse("sha256:release").expect("valid release id"),
            release_created_at_ms: 1,
            material_id: LearningMaterialId::parse("material-1").expect("valid material id"),
            material_revision_id: MaterialRevisionId::from_fingerprint(
                "material-revision",
                "rev-1",
            ),
            edition: edition("edition-1"),
            resources,
            renditions: Vec::new(),
            installed_at_ms: 10,
        }
    }

    #[test]
    fn text_only_edition_without_timeline_is_adoptable() {
        let document = resource(
            "document-1",
            "document_text",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let plan = adoption_commit_plan(&installation(vec![document.clone()]), 100).unwrap();
        assert_eq!(plan.release_id.as_str(), "sha256:release");
        assert_eq!(plan.adopted_at_ms, 100);
        assert_eq!(plan.selected_resource_ids, vec!["document-1".to_owned()]);
        assert_eq!(
            plan.exclusive_selections,
            vec![ExclusiveSelection {
                family: "exclusive:document_text".into(),
                resource_id: "document-1".into(),
            }]
        );
        assert!(plan.selected_rendition_ids.is_empty());
    }

    #[test]
    fn media_only_installation_without_resources_is_adoptable() {
        let mut installation = installation(Vec::new());
        installation.renditions = vec![PackageRenditionFact {
            rendition_id: "rendition-1".into(),
            kind: "audio".into(),
            media_type: "audio/mpeg".into(),
            available: true,
            media_digest: format!("sha256:{}", "a".repeat(64)),
            media_size_bytes: 100,
        }];
        let plan = adoption_commit_plan(&installation, 100).unwrap();
        assert!(plan.selected_resource_ids.is_empty());
        assert!(plan.exclusive_selections.is_empty());
        assert_eq!(plan.selected_rendition_ids, vec!["rendition-1".to_owned()]);
    }

    #[test]
    fn missing_required_resource_rejects_the_plan() {
        let document = resource(
            "document-1",
            "document_text",
            true,
            PackageResourceAvailability::Missing,
            &[],
        );
        let error = adoption_commit_plan(&installation(vec![document]), 100).unwrap_err();
        assert_eq!(
            error,
            PackageLifecycleError::MissingRequiredResource {
                resource_id: "document-1".into()
            }
        );
    }

    #[test]
    fn broken_dependency_closure_rejects_the_plan() {
        let document = resource(
            "document-1",
            "document_text",
            false,
            PackageResourceAvailability::Available,
            &[],
        );
        let zh_hans = translation("translation-1", "zh-Hans");
        let missing = resource(
            "missing-1",
            "word_timeline",
            false,
            PackageResourceAvailability::Missing,
            &[],
        );
        let broken_candidate = translation("translation-2", "zh-Hans");
        let mut broken = broken_candidate.clone();
        broken.dependencies = vec!["missing-1".to_owned()];

        let error =
            adoption_commit_plan(&installation(vec![document, zh_hans, missing, broken]), 100)
                .unwrap_err();
        assert_eq!(
            error,
            PackageLifecycleError::BrokenDependencyClosure {
                resource_id: "translation-2".into(),
                dependency_id: "missing-1".into()
            }
        );
    }

    #[test]
    fn opaque_dependency_rejects_the_plan() {
        let document = resource(
            "document-1",
            "document_text",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let mut dependent = resource(
            "dependent-1",
            "word_timeline",
            false,
            PackageResourceAvailability::Available,
            &["opaque-1"],
        );
        dependent.content_language = None;
        dependent.role = PackageResourceRole::Assistance;
        let opaque = resource(
            "opaque-1",
            "future_analysis",
            false,
            PackageResourceAvailability::Opaque,
            &[],
        );
        let error = adoption_commit_plan(&installation(vec![document, dependent, opaque]), 100)
            .unwrap_err();
        assert_eq!(
            error,
            PackageLifecycleError::BrokenDependencyClosure {
                resource_id: "dependent-1".into(),
                dependency_id: "opaque-1".into()
            }
        );
    }

    #[test]
    fn ambiguous_exclusive_family_rejects_the_plan() {
        let document = resource(
            "document-1",
            "document_text",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let first = translation("translation-1", "zh-Hans");
        let second = translation("translation-2", "zh-Hans");
        let error =
            adoption_commit_plan(&installation(vec![document, first, second]), 100).unwrap_err();
        assert_eq!(
            error,
            PackageLifecycleError::AmbiguousExclusiveFamily {
                family: "translation:zh-hans".into(),
                resource_ids: vec!["translation-1".into(), "translation-2".into()],
            }
        );
    }

    #[test]
    fn translation_families_are_exclusive_per_support_language() {
        let document = resource(
            "document-1",
            "document_text",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let simplified = translation("translation-1", "zh-Hans");
        let traditional = translation("translation-2", "zh-Hant");
        let plan =
            adoption_commit_plan(&installation(vec![document, simplified, traditional]), 100)
                .unwrap();
        assert_eq!(
            plan.selected_resource_ids,
            vec![
                "document-1".to_owned(),
                "translation-1".to_owned(),
                "translation-2".to_owned()
            ]
        );
        assert_eq!(
            plan.exclusive_selections,
            vec![
                ExclusiveSelection {
                    family: "exclusive:document_text".into(),
                    resource_id: "document-1".into(),
                },
                ExclusiveSelection {
                    family: "translation:zh-hans".into(),
                    resource_id: "translation-1".into(),
                },
                ExclusiveSelection {
                    family: "translation:zh-hant".into(),
                    resource_id: "translation-2".into(),
                },
            ]
        );
    }

    #[test]
    fn optional_missing_and_opaque_resources_do_not_block_adoption() {
        let document = resource(
            "document-1",
            "document_text",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let optional_missing = resource(
            "missing-1",
            "word_timeline",
            false,
            PackageResourceAvailability::Missing,
            &[],
        );
        let opaque = resource(
            "opaque-1",
            "future_analysis",
            false,
            PackageResourceAvailability::Opaque,
            &[],
        );
        let plan = adoption_commit_plan(
            &installation(vec![document.clone(), optional_missing, opaque]),
            100,
        )
        .unwrap();
        assert_eq!(plan.selected_resource_ids, vec!["document-1".to_owned()]);
        assert_eq!(
            plan.exclusive_selections,
            vec![ExclusiveSelection {
                family: "exclusive:document_text".into(),
                resource_id: "document-1".into(),
            }]
        );
    }

    #[test]
    fn plan_is_deterministic_regardless_of_fact_order() {
        let document = resource(
            "document-1",
            "document_text",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let subtitle = resource(
            "subtitle-1",
            "subtitle_text_track",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let timeline = resource(
            "timeline-1",
            "word_timeline",
            true,
            PackageResourceAvailability::Available,
            &["subtitle-1"],
        );
        let acoustics = resource(
            "acoustics-1",
            "word_acoustics",
            false,
            PackageResourceAvailability::Available,
            &["timeline-1"],
        );

        let forward = installation(vec![
            document.clone(),
            subtitle.clone(),
            timeline.clone(),
            acoustics.clone(),
        ]);
        let reversed = installation(vec![acoustics, timeline, subtitle, document]);
        let first = adoption_commit_plan(&forward, 100).unwrap();
        let second = adoption_commit_plan(&reversed, 100).unwrap();
        assert_eq!(first, second);
        assert_eq!(
            first.selected_resource_ids,
            vec![
                "acoustics-1".to_owned(),
                "document-1".to_owned(),
                "subtitle-1".to_owned(),
                "timeline-1".to_owned(),
            ]
        );
        assert_eq!(first.exclusive_selections.len(), 4);
    }

    #[test]
    fn exclusive_selections_resolve_every_family_to_one_resource() {
        let document = resource(
            "document-1",
            "document_text",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let timeline = resource(
            "timeline-1",
            "word_timeline",
            true,
            PackageResourceAvailability::Available,
            &[],
        );
        let plan =
            adoption_commit_plan(&installation(vec![document.clone(), timeline.clone()]), 100)
                .unwrap();
        let selections: Vec<(&str, &str)> = plan
            .exclusive_selections
            .iter()
            .map(|selection| (selection.family.as_str(), selection.resource_id.as_str()))
            .collect();
        assert_eq!(
            selections,
            vec![
                ("exclusive:document_text", "document-1"),
                ("exclusive:word_timeline", "timeline-1"),
            ]
        );
    }
}
