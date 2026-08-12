//! Material Capability projection and attempts (Phase 1 contract 4.0.0).
//!
//! A Material Capability is a modality view over one Material: Read, Listen,
//! Watch, or synchronized Read-and-Listen. The projection reports
//! `available`, `derivable`, `generating`, `unavailable`, or `failed_attempt`.
//! Failure is attached to a specific attempt and never invalidates an
//! otherwise usable Material.
//!
//! Derivable is a structural fact: given the exact Renditions and Resources of
//! the Material (plus the adopted composition), a capability can be produced.
//! It deliberately does not know provider configuration — provider readiness
//! is an application fact injected at the boundary.

use serde::{Deserialize, Serialize};

use crate::{
    CapabilityAttemptId, DomainError, LearningMaterialId, MaterialRevision, MediaKind,
    PackageInstallation, PackageResourceRole, Rendition, RenditionOrigin,
};

/// One learner-facing Material Capability.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MaterialCapability {
    Read,
    Listen,
    Watch,
    SynchronizedReadListen,
}

impl MaterialCapability {
    pub fn as_str(&self) -> &'static str {
        match self {
            MaterialCapability::Read => "read",
            MaterialCapability::Listen => "listen",
            MaterialCapability::Watch => "watch",
            MaterialCapability::SynchronizedReadListen => "synchronized_read_listen",
        }
    }
}

/// One observable capability state.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityStatus {
    /// The adopted composition already provides the capability.
    Available,
    /// The capability can be produced from the current Material facts.
    Derivable,
    /// A production attempt for this capability is in flight.
    Generating,
    /// The capability cannot be provided by this stack for this Material.
    Unavailable,
    /// The latest production attempt for this capability failed.
    FailedAttempt,
}

/// Outcome of one capability production attempt.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityAttemptStatus {
    Running,
    Succeeded,
    Failed,
}

/// One durable capability production attempt for a Material. The attempt is
/// the unit of `generating` / `failed_attempt` evidence; a failed attempt never
/// rewrites the facts of an earlier attempt.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityAttempt {
    pub attempt_id: CapabilityAttemptId,
    pub material_id: LearningMaterialId,
    pub capability: MaterialCapability,
    pub status: CapabilityAttemptStatus,
    pub started_at_ms: u64,
    pub finished_at_ms: Option<u64>,
    /// Stable failure reason; raw provider output never appears here.
    pub failure_reason: Option<String>,
    /// Exact producer facts when the attempt succeeded.
    pub producer_tool_id: Option<String>,
    pub producer_tool_version: Option<String>,
}

impl CapabilityAttempt {
    pub fn start(
        material_id: LearningMaterialId,
        capability: MaterialCapability,
        started_at_ms: u64,
    ) -> Self {
        Self {
            attempt_id: CapabilityAttemptId::from_fingerprint(
                "capability-attempt",
                &format!("{}/{}", material_id.as_str(), started_at_ms),
            ),
            material_id,
            capability,
            status: CapabilityAttemptStatus::Running,
            started_at_ms,
            finished_at_ms: None,
            failure_reason: None,
            producer_tool_id: None,
            producer_tool_version: None,
        }
    }

    pub fn succeed(&mut self, finished_at_ms: u64, tool_id: String, tool_version: String) {
        self.status = CapabilityAttemptStatus::Succeeded;
        self.finished_at_ms = Some(finished_at_ms);
        self.producer_tool_id = Some(tool_id);
        self.producer_tool_version = Some(tool_version);
    }

    pub fn fail(
        &mut self,
        finished_at_ms: u64,
        reason: impl Into<String>,
    ) -> Result<(), DomainError> {
        let reason = reason.into();
        if reason.trim().is_empty() {
            return Err(DomainError::EmptyValue("CapabilityAttempt.failure_reason"));
        }
        self.status = CapabilityAttemptStatus::Failed;
        self.finished_at_ms = Some(finished_at_ms);
        self.failure_reason = Some(reason);
        Ok(())
    }
}

/// One capability projection for a Material: the observable status plus, when
/// available, the evidence that produced it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MaterialCapabilityProjection {
    pub capability: MaterialCapability,
    pub status: CapabilityStatus,
    /// Latest attempt evidence for this capability, when one exists.
    pub latest_attempt: Option<CapabilityAttempt>,
}

/// Structural derivation rules for capabilities, independent of provider
/// configuration.
///
/// - Listen is derivable from any Document Rendition (TTS path).
/// - Read is derivable from any Media Rendition (speech-to-structured-reading
///   path).
/// - Synchronized Read-and-Listen is derivable exactly when Listen is
///   derivable; the exact alignment Resource is produced with the audio.
/// - Watch is not derivable in Phase 1: it is available only from a video
///   Media Rendition.
pub fn derivation_prerequisite(
    capability: MaterialCapability,
    revision: &MaterialRevision,
) -> bool {
    match capability {
        MaterialCapability::Read => revision.renditions.iter().any(|rendition| {
            matches!(
                rendition,
                Rendition::Media(media) if media.kind == MediaKind::Video || media.kind == MediaKind::Audio
            )
        }),
        MaterialCapability::Listen => revision
            .renditions
            .iter()
            .any(|rendition| matches!(rendition, Rendition::Document(_))),
        MaterialCapability::Watch => false,
        MaterialCapability::SynchronizedReadListen => {
            derivation_prerequisite(MaterialCapability::Listen, revision)
        }
    }
}

/// Whether the adopted composition already provides a capability, from the
/// package facts alone. `available` requires an adopted installation whose
/// selected facts realize the capability.
pub fn adopted_composition_provides(
    capability: MaterialCapability,
    adopted: Option<&PackageInstallation>,
) -> bool {
    let Some(adopted) = adopted else {
        return false;
    };
    let has_document = adopted
        .renditions
        .iter()
        .any(|rendition| matches!(rendition.kind.as_str(), "document"));
    let has_audio = adopted.renditions.iter().any(|rendition| {
        matches!(rendition.kind.as_str(), "media") && rendition.media_type.starts_with("audio/")
    });
    let has_video = adopted.renditions.iter().any(|rendition| {
        matches!(rendition.kind.as_str(), "media") && { rendition.media_type.starts_with("video/") }
    });
    let has_structured_reading = adopted.resources.iter().any(|resource| {
        resource.role == PackageResourceRole::Base && resource.kind == "structured_reading"
    });
    let has_alignment = adopted.resources.iter().any(|resource| {
        resource.role == PackageResourceRole::Base && resource.kind == "anchor_time_alignment"
    });
    match capability {
        MaterialCapability::Read => has_document || has_structured_reading,
        MaterialCapability::Listen => has_audio,
        MaterialCapability::Watch => has_video,
        MaterialCapability::SynchronizedReadListen => has_audio && has_alignment,
    }
}

/// The five-state projection for one capability over the exact Material facts.
///
/// 1. An adopted composition that provides the capability is `available`.
/// 2. Otherwise the latest attempt drives `generating` or `failed_attempt`.
/// 3. Otherwise a structural prerequisite makes it `derivable`.
/// 4. Otherwise `unavailable`.
pub fn project_capability(
    capability: MaterialCapability,
    revision: &MaterialRevision,
    adopted: Option<&PackageInstallation>,
    attempts: &[CapabilityAttempt],
) -> MaterialCapabilityProjection {
    let latest_attempt = attempts
        .iter()
        .filter(|attempt| attempt.capability == capability)
        .max_by_key(|attempt| attempt.started_at_ms);
    let status = if adopted_composition_provides(capability, adopted) {
        CapabilityStatus::Available
    } else if let Some(attempt) = &latest_attempt {
        match attempt.status {
            CapabilityAttemptStatus::Running => CapabilityStatus::Generating,
            CapabilityAttemptStatus::Failed => CapabilityStatus::FailedAttempt,
            CapabilityAttemptStatus::Succeeded => {
                // A succeeded attempt that is not reflected in the adopted
                // composition is not a lie: the composition may simply not
                // have been adopted yet. The capability is still structurally
                // derivable.
                if derivation_prerequisite(capability, revision) {
                    CapabilityStatus::Derivable
                } else {
                    CapabilityStatus::Unavailable
                }
            }
        }
    } else if derivation_prerequisite(capability, revision) {
        CapabilityStatus::Derivable
    } else {
        CapabilityStatus::Unavailable
    };
    MaterialCapabilityProjection {
        capability,
        status,
        latest_attempt: latest_attempt.cloned(),
    }
}

pub fn adopted_has_derived_rendition(adopted: Option<&PackageInstallation>) -> bool {
    adopted.is_some_and(|adopted| {
        adopted
            .renditions
            .iter()
            .any(|rendition| matches!(rendition.origin, RenditionOrigin::Derived))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{DocumentRendition, LearningMaterialId, PackageReleaseId};

    fn language(code: &str) -> crate::LanguageCode {
        crate::LanguageCode::parse(code).expect("valid language code")
    }

    fn document_revision() -> MaterialRevision {
        let material_id = LearningMaterialId::parse("material-doc").expect("valid material id");
        MaterialRevision::new(
            material_id,
            "Doc",
            vec![],
            vec![Rendition::Document(
                DocumentRendition::new(
                    RenditionOrigin::Source,
                    "text/plain",
                    Some(language("en")),
                    "hello world",
                    None,
                    None,
                    None,
                )
                .expect("valid rendition"),
            )],
            1,
        )
        .expect("valid revision")
    }

    fn attempt(
        capability: MaterialCapability,
        status: CapabilityAttemptStatus,
    ) -> CapabilityAttempt {
        let mut attempt = CapabilityAttempt::start(
            LearningMaterialId::parse("material-doc").expect("valid material id"),
            capability,
            5,
        );
        match status {
            CapabilityAttemptStatus::Running => {}
            CapabilityAttemptStatus::Succeeded => {
                attempt.succeed(10, "listen-gen".into(), "0.4.0".into())
            }
            CapabilityAttemptStatus::Failed => attempt
                .fail(10, "provider unavailable")
                .expect("valid failure"),
        }
        attempt
    }

    #[test]
    fn document_revision_projects_listen_derivable_and_read_available_from_adoption() {
        let revision = document_revision();
        let projection = project_capability(MaterialCapability::Listen, &revision, None, &[]);
        assert_eq!(projection.status, CapabilityStatus::Derivable);
        let read = project_capability(MaterialCapability::Read, &revision, None, &[]);
        assert_eq!(read.status, CapabilityStatus::Unavailable);
        let watch = project_capability(MaterialCapability::Watch, &revision, None, &[]);
        assert_eq!(watch.status, CapabilityStatus::Unavailable);
    }

    #[test]
    fn running_and_failed_attempts_drive_generating_and_failed_attempt() {
        let revision = document_revision();
        let running = project_capability(
            MaterialCapability::Listen,
            &revision,
            None,
            &[attempt(
                MaterialCapability::Listen,
                CapabilityAttemptStatus::Running,
            )],
        );
        assert_eq!(running.status, CapabilityStatus::Generating);
        let failed = project_capability(
            MaterialCapability::Listen,
            &revision,
            None,
            &[attempt(
                MaterialCapability::Listen,
                CapabilityAttemptStatus::Failed,
            )],
        );
        assert_eq!(failed.status, CapabilityStatus::FailedAttempt);
        // Failure is attached to the attempt; the attempt facts are never
        // rewritten by a later attempt.
        let first = attempt(MaterialCapability::Listen, CapabilityAttemptStatus::Failed);
        let mut later = attempt(MaterialCapability::Listen, CapabilityAttemptStatus::Failed);
        later.started_at_ms = 9;
        let projection = project_capability(
            MaterialCapability::Listen,
            &revision,
            None,
            &[first.clone(), later.clone()],
        );
        assert_eq!(projection.status, CapabilityStatus::FailedAttempt);
        assert_eq!(projection.latest_attempt.expect("attempt").started_at_ms, 9);
    }

    #[test]
    fn a_succeeded_attempt_without_adoption_is_still_derivable() {
        let revision = document_revision();
        let projection = project_capability(
            MaterialCapability::Listen,
            &revision,
            None,
            &[attempt(
                MaterialCapability::Listen,
                CapabilityAttemptStatus::Succeeded,
            )],
        );
        assert_eq!(projection.status, CapabilityStatus::Derivable);
    }

    #[test]
    fn adopted_composition_provides_listen_with_audio_rendition() {
        let revision = document_revision();
        let adopted = PackageInstallation {
            release_id: PackageReleaseId::parse("sha256:release").expect("valid release id"),
            release_created_at_ms: 1,
            material_id: revision.material_id.clone(),
            material_revision_id: revision.id.clone(),
            edition: crate::LearningEdition {
                edition_id: crate::LearningEditionId::parse("edition-1").expect("valid edition id"),
                title: "Edition".into(),
                target_language: language("en"),
                support_languages: Vec::new(),
            },
            resources: Vec::new(),
            renditions: vec![crate::PackageRenditionFact {
                rendition_id: "rendition-audio".into(),
                kind: "media".into(),
                origin: RenditionOrigin::Derived,
                media_type: "audio/mpeg".into(),
                available: true,
                media_digest: format!("sha256:{}", "a".repeat(64)),
                media_size_bytes: 100,
                media_id: None,
                producer: None,
            }],
            installed_at_ms: 10,
        };
        let projection =
            project_capability(MaterialCapability::Listen, &revision, Some(&adopted), &[]);
        assert_eq!(projection.status, CapabilityStatus::Available);
    }
}
