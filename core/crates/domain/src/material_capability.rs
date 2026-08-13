//! Material Capability projection and attempts (Phase 1 contract 4.0.0).
//!
//! A Material Capability is a modality view over one Material: Read, Listen,
//! Watch, or synchronized Read-and-Listen. The projection reports
//! `available`, `derivable`, `generating`, `unavailable`, or `failed_attempt`
//! by reading both the current Material revision and the adopted composition.
//! Failure is attached to a specific attempt and never invalidates an
//! otherwise usable Material.
//!
//! Derivable is a structural fact: given the exact Renditions and Resources of
//! the Material (plus the adopted composition), a capability can be produced.
//! It deliberately does not know provider configuration — provider readiness
//! is an application fact injected at the boundary.
//!
//! Attempts have honest terminal states: `succeeded`, `failed`, `cancelled`,
//! and `superseded` (interrupted). Cancelled and superseded attempts are
//! never projected as failed attempts; only real provider/install/adoption
//! failures are. An attempt id never derives from the started-at timestamp
//! alone: it combines material, capability, timestamp, and a per-capability
//! attempt key, so attempts in the same millisecond never collide.

use serde::{Deserialize, Serialize};

use crate::{
    AdoptedComposition, CapabilityAttemptId, DomainError, LearningMaterialId, MaterialRevision,
    MediaKind, Rendition,
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

/// Outcome of one capability production attempt. `Cancelled` and `Superseded`
/// are honest terminal states: they never count as failed attempts.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityAttemptStatus {
    Running,
    Succeeded,
    Failed,
    Cancelled,
    /// Interrupted: replaced by a newer attempt or terminated by a restart.
    Superseded,
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
    /// Starts a running attempt. The deterministic identity combines the
    /// material, the capability, the started-at timestamp, and a
    /// per-capability attempt key (a monotonic sequence owned by the
    /// persistence adapter): attempts in the same millisecond for the same
    /// material never collide, and a retry always produces a distinct id.
    pub fn start(
        material_id: LearningMaterialId,
        capability: MaterialCapability,
        started_at_ms: u64,
        attempt_key: u64,
    ) -> Self {
        Self {
            attempt_id: CapabilityAttemptId::from_fingerprint(
                "capability-attempt",
                &format!(
                    "{}/{}/{}/{}",
                    material_id.as_str(),
                    capability.as_str(),
                    started_at_ms,
                    attempt_key
                ),
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

    /// Marks the attempt honestly cancelled (learner or caller intent).
    pub fn cancel(&mut self, finished_at_ms: u64) {
        self.status = CapabilityAttemptStatus::Cancelled;
        self.finished_at_ms = Some(finished_at_ms);
    }

    /// Marks the attempt superseded: interrupted by a newer attempt or by a
    /// restart. Never a failure.
    pub fn supersede(&mut self, finished_at_ms: u64) {
        self.status = CapabilityAttemptStatus::Superseded;
        self.finished_at_ms = Some(finished_at_ms);
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
/// - Read is derivable from any Media Rendition (speech-to-structured-reading
///   path via ASR).
/// - Listen is derivable when a Document Rendition exists (TTS path) or the
///   adopted composition already provides a Structured Reading Resource.
/// - Synchronized Read-and-Listen is derivable exactly when the exact
///   structure, audio, and alignment can be produced from the current
///   Material facts (a Document Rendition for structure and TTS audio, or
///   media for structure via ASR).
/// - Watch is not derivable in Phase 1: it is available only from a video
///   Media Rendition.
fn derivation_prerequisite(
    capability: MaterialCapability,
    revision: &MaterialRevision,
    adopted: Option<&AdoptedComposition>,
) -> bool {
    match capability {
        MaterialCapability::Read => revision.renditions.iter().any(|rendition| {
            matches!(
                rendition,
                Rendition::Media(media)
                    if media.kind == MediaKind::Video || media.kind == MediaKind::Audio
            )
        }),
        MaterialCapability::Listen => {
            revision
                .renditions
                .iter()
                .any(|rendition| matches!(rendition, Rendition::Document(_)))
                || adopted.is_some_and(|adopted| adopted.has_selected_structured_reading())
        }
        MaterialCapability::Watch => false,
        MaterialCapability::SynchronizedReadListen => {
            let has_document = revision
                .renditions
                .iter()
                .any(|rendition| matches!(rendition, Rendition::Document(_)));
            let has_media = revision
                .renditions
                .iter()
                .any(|rendition| matches!(rendition, Rendition::Media(_)));
            has_document || has_media
        }
    }
}

/// Whether the adopted composition already provides a capability, from the
/// adopted composition facts alone. `available` requires an adopted
/// installation whose selected facts realize the capability.
fn adopted_composition_provides(
    capability: MaterialCapability,
    adopted: Option<&AdoptedComposition>,
) -> bool {
    let Some(adopted) = adopted else {
        return false;
    };
    let has_document = adopted
        .renditions
        .iter()
        .any(|rendition| matches!(rendition.kind.as_str(), "document"));
    let has_audio = adopted
        .renditions
        .iter()
        .any(|rendition| rendition.kind == "media" && rendition.media_type.starts_with("audio/"));
    let has_video = adopted
        .renditions
        .iter()
        .any(|rendition| rendition.kind == "media" && rendition.media_type.starts_with("video/"));
    let has_structured_reading = adopted
        .resources
        .iter()
        .any(|resource| resource.kind == "structured_reading");
    match capability {
        MaterialCapability::Read => has_document || has_structured_reading,
        MaterialCapability::Listen => has_audio,
        MaterialCapability::Watch => has_video,
        MaterialCapability::SynchronizedReadListen => {
            // An exact Structured Reading, usable media, and a compatible
            // alignment must all coexist: the alignment must declare the
            // exact adopted Structured Reading resource as its anchor input.
            has_audio
                && has_structured_reading
                && adopted.resources.iter().any(|resource| {
                    resource.kind == "anchor_time_alignment" && {
                        resource.anchor_resource_ids.iter().any(|anchor_id| {
                            adopted.resources.iter().any(|candidate| {
                                candidate.kind == "structured_reading"
                                    && candidate.resource_id == *anchor_id
                            })
                        })
                    }
                })
        }
    }
}

/// The five-state projection for one capability over the exact Material facts
/// and the adopted composition.
///
/// 1. An adopted composition that provides the capability is `available`.
/// 2. Otherwise the latest attempt drives `generating` or `failed_attempt`;
///    cancelled and superseded attempts are honest terminal facts that never
///    project as failures.
/// 3. Otherwise a structural prerequisite makes it `derivable`.
/// 4. Otherwise `unavailable`.
pub fn project_capability(
    capability: MaterialCapability,
    revision: &MaterialRevision,
    adopted: Option<&AdoptedComposition>,
    attempts: &[CapabilityAttempt],
) -> MaterialCapabilityProjection {
    let latest_attempt = attempts
        .iter()
        .filter(|attempt| attempt.capability == capability)
        .max_by_key(|attempt| (attempt.started_at_ms, attempt.attempt_id.as_str()));
    let status = if adopted_composition_provides(capability, adopted) {
        CapabilityStatus::Available
    } else if let Some(attempt) = &latest_attempt {
        match attempt.status {
            CapabilityAttemptStatus::Running => CapabilityStatus::Generating,
            CapabilityAttemptStatus::Failed => CapabilityStatus::FailedAttempt,
            CapabilityAttemptStatus::Succeeded
            | CapabilityAttemptStatus::Cancelled
            | CapabilityAttemptStatus::Superseded => {
                // A non-failed terminal attempt is not a failure: the
                // capability is still structurally derivable or unavailable.
                if derivation_prerequisite(capability, revision, adopted) {
                    CapabilityStatus::Derivable
                } else {
                    CapabilityStatus::Unavailable
                }
            }
        }
    } else if derivation_prerequisite(capability, revision, adopted) {
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

pub fn adopted_has_derived_rendition(adopted: Option<&AdoptedComposition>) -> bool {
    adopted.is_some_and(|adopted| {
        adopted
            .renditions
            .iter()
            .any(|rendition| matches!(rendition.origin, crate::RenditionOrigin::Derived))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        AdoptedComposition, AdoptionCommitPlan, DocumentRendition, LearningMaterialId,
        PackageInstallation, PackageReleaseId, PackageResourceFact, RenditionOrigin, SourceAssetId,
    };

    fn language(code: &str) -> crate::LanguageCode {
        crate::LanguageCode::parse(code).expect("valid language code")
    }

    fn text_digest(text: &str) -> String {
        use sha2::Digest as _;
        hex::encode(sha2::Sha256::digest(text.as_bytes()))
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
                    text_digest("hello world"),
                    11,
                    Some(SourceAssetId::parse("asset-doc").expect("valid asset id")),
                    None,
                    None,
                )
                .expect("valid rendition"),
            )],
            1,
        )
        .expect("valid revision")
    }

    fn media_revision(kind: MediaKind) -> MaterialRevision {
        let material_id = LearningMaterialId::parse("material-media").expect("valid material id");
        MaterialRevision::new(
            material_id,
            "Media",
            vec![],
            vec![Rendition::Media(
                crate::MediaRendition::new(
                    RenditionOrigin::Source,
                    kind,
                    "audio/mpeg",
                    "fp-1",
                    crate::MediaAvailability::Available,
                    Some(crate::MediaId::parse("media-1").expect("valid media id")),
                    None,
                    None,
                    None,
                    None,
                )
                .expect("valid media rendition"),
            )],
            1,
        )
        .expect("valid revision")
    }

    fn attempt(
        capability: MaterialCapability,
        status: CapabilityAttemptStatus,
        key: u64,
    ) -> CapabilityAttempt {
        let mut attempt = CapabilityAttempt::start(
            LearningMaterialId::parse("material-doc").expect("valid material id"),
            capability,
            5,
            key,
        );
        match status {
            CapabilityAttemptStatus::Running => {}
            CapabilityAttemptStatus::Succeeded => {
                attempt.succeed(10, "listen-gen".into(), "0.4.0".into())
            }
            CapabilityAttemptStatus::Failed => attempt
                .fail(10, "provider unavailable")
                .expect("valid failure"),
            CapabilityAttemptStatus::Cancelled => attempt.cancel(10),
            CapabilityAttemptStatus::Superseded => attempt.supersede(10),
        }
        attempt
    }

    #[test]
    fn attempt_ids_never_collide_within_the_same_millisecond() {
        let material_id = LearningMaterialId::parse("material-doc").expect("valid material id");
        // Same millisecond, same capability, different attempt keys.
        let first = CapabilityAttempt::start(material_id.clone(), MaterialCapability::Listen, 7, 1);
        let second =
            CapabilityAttempt::start(material_id.clone(), MaterialCapability::Listen, 7, 2);
        assert_ne!(first.attempt_id, second.attempt_id);
        // Same millisecond, different capabilities, same key.
        let read = CapabilityAttempt::start(material_id.clone(), MaterialCapability::Read, 7, 1);
        assert_ne!(first.attempt_id, read.attempt_id);
        // Deterministic retries with equal facts converge.
        let retry = CapabilityAttempt::start(material_id, MaterialCapability::Listen, 7, 1);
        assert_eq!(first.attempt_id, retry.attempt_id);
    }

    #[test]
    fn document_revision_projects_listen_derivable_and_read_unavailable() {
        let revision = document_revision();
        let projection = project_capability(MaterialCapability::Listen, &revision, None, &[]);
        assert_eq!(projection.status, CapabilityStatus::Derivable);
        let read = project_capability(MaterialCapability::Read, &revision, None, &[]);
        assert_eq!(read.status, CapabilityStatus::Unavailable);
        let watch = project_capability(MaterialCapability::Watch, &revision, None, &[]);
        assert_eq!(watch.status, CapabilityStatus::Unavailable);
        // Synchronized reading is derivable from a document (structure + TTS
        // audio + alignment can all be produced).
        let synced = project_capability(
            MaterialCapability::SynchronizedReadListen,
            &revision,
            None,
            &[],
        );
        assert_eq!(synced.status, CapabilityStatus::Derivable);
    }

    #[test]
    fn media_revision_projects_read_derivable_and_synced_derivable() {
        let revision = media_revision(MediaKind::Audio);
        let read = project_capability(MaterialCapability::Read, &revision, None, &[]);
        assert_eq!(read.status, CapabilityStatus::Derivable);
        let listen = project_capability(MaterialCapability::Listen, &revision, None, &[]);
        assert_eq!(listen.status, CapabilityStatus::Unavailable);
        let synced = project_capability(
            MaterialCapability::SynchronizedReadListen,
            &revision,
            None,
            &[],
        );
        assert_eq!(synced.status, CapabilityStatus::Derivable);
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
                1,
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
                1,
            )],
        );
        assert_eq!(failed.status, CapabilityStatus::FailedAttempt);
        // Failure is attached to the attempt; the attempt facts are never
        // rewritten by a later attempt.
        let first = attempt(
            MaterialCapability::Listen,
            CapabilityAttemptStatus::Failed,
            1,
        );
        let mut later = attempt(
            MaterialCapability::Listen,
            CapabilityAttemptStatus::Failed,
            2,
        );
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
    fn cancelled_and_superseded_attempts_are_never_failed_attempts() {
        let revision = document_revision();
        for (status, expected) in [
            (
                CapabilityAttemptStatus::Cancelled,
                CapabilityStatus::Derivable,
            ),
            (
                CapabilityAttemptStatus::Superseded,
                CapabilityStatus::Derivable,
            ),
        ] {
            let projection = project_capability(
                MaterialCapability::Listen,
                &revision,
                None,
                &[attempt(MaterialCapability::Listen, status, 1)],
            );
            assert_eq!(
                projection.status, expected,
                "{status:?} is honest, never a failed attempt"
            );
            assert_eq!(
                projection.latest_attempt.expect("attempt").status,
                status,
                "the terminal attempt fact is preserved"
            );
        }
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
                1,
            )],
        );
        assert_eq!(projection.status, CapabilityStatus::Derivable);
    }

    /// Builds an adopted composition: `with_audio` controls the audio
    /// rendition, `with_structured_reading` and `with_alignment` control the
    /// resources, and `anchor_ids` are the alignment's anchor resource inputs.
    fn adopted(
        with_audio: bool,
        with_structured_reading: bool,
        with_alignment: bool,
        anchor_ids: Vec<String>,
    ) -> AdoptedComposition {
        let mut resources: Vec<PackageResourceFact> = Vec::new();
        let mut renditions: Vec<crate::PackageRenditionFact> = Vec::new();
        if with_audio {
            renditions.push(crate::PackageRenditionFact {
                rendition_id: "rendition-audio".into(),
                kind: "media".into(),
                origin: RenditionOrigin::Derived,
                media_type: "audio/mpeg".into(),
                available: true,
                media_digest: format!("sha256:{}", "a".repeat(64)),
                media_size_bytes: 100,
                media_id: None,
                source_asset_id: None,
                producer: None,
            });
        }
        if with_structured_reading {
            resources.push(crate::PackageResourceFact {
                resource_id: "resource-reading".into(),
                kind: "structured_reading".into(),
                schema: "listen.payload.structured_reading.v1".into(),
                role: crate::PackageResourceRole::Base,
                required: true,
                availability: crate::PackageResourceAvailability::Available,
                content_language: Some(language("en")),
                support_languages: Vec::new(),
                dependencies: Vec::new(),
                anchor_resource_ids: Vec::new(),
                payload_digest: format!("sha256:{}", "b".repeat(64)),
                payload_size_bytes: 10,
                provenance: crate::PackageResourceProvenance {
                    created_at_ms: 1,
                    tool_id: "listen-gen".into(),
                    tool_version: "0.4.0".into(),
                    provider_id: None,
                    provider_version: None,
                    model_id: None,
                    model_version: None,
                    config_sha256: None,
                },
                review_status: crate::PackageReviewStatus::MachineChecked,
                quality_warnings: Vec::new(),
            });
        }
        if with_alignment {
            resources.push(crate::PackageResourceFact {
                resource_id: "resource-alignment".into(),
                kind: "anchor_time_alignment".into(),
                schema: "listen.payload.anchor_time_alignment.v1".into(),
                role: crate::PackageResourceRole::Base,
                required: true,
                availability: crate::PackageResourceAvailability::Available,
                content_language: Some(language("en")),
                support_languages: Vec::new(),
                dependencies: Vec::new(),
                anchor_resource_ids: anchor_ids,
                payload_digest: format!("sha256:{}", "c".repeat(64)),
                payload_size_bytes: 10,
                provenance: crate::PackageResourceProvenance {
                    created_at_ms: 1,
                    tool_id: "listen-gen".into(),
                    tool_version: "0.4.0".into(),
                    provider_id: None,
                    provider_version: None,
                    model_id: None,
                    model_version: None,
                    config_sha256: None,
                },
                review_status: crate::PackageReviewStatus::MachineChecked,
                quality_warnings: Vec::new(),
            });
        }
        // The alignment lists the structured reading only when selected.
        let selected_resources: Vec<String> = resources
            .iter()
            .map(|resource| resource.resource_id.clone())
            .collect();
        AdoptedComposition {
            resources,
            renditions,
            selected_resource_ids: selected_resources,
            selected_rendition_ids: vec!["rendition-audio".into()],
        }
    }

    #[test]
    fn adopted_composition_provides_listen_and_synchronized_read_listen() {
        let revision = document_revision();
        // Audio rendition alone makes Listen available.
        let audio_only = adopted(true, false, false, Vec::new());
        let listen = project_capability(
            MaterialCapability::Listen,
            &revision,
            Some(&audio_only),
            &[],
        );
        assert_eq!(listen.status, CapabilityStatus::Available);

        // Structured reading + audio + a compatible alignment make
        // Synchronized Read-and-Listen available.
        let synced = adopted(true, true, true, vec!["resource-reading".into()]);
        let projection = project_capability(
            MaterialCapability::SynchronizedReadListen,
            &revision,
            Some(&synced),
            &[],
        );
        assert_eq!(projection.status, CapabilityStatus::Available);

        // An alignment that does not anchor the selected Structured Reading
        // is not compatible: the capability stays structurally derivable
        // from the document, but is never available from the adoption.
        let mismatched = adopted(true, true, true, vec!["other-reading".into()]);
        let projection = project_capability(
            MaterialCapability::SynchronizedReadListen,
            &revision,
            Some(&mismatched),
            &[],
        );
        assert_eq!(projection.status, CapabilityStatus::Derivable);
    }

    #[test]
    fn adopted_structured_reading_makes_listen_derivable_without_document() {
        let revision = media_revision(MediaKind::Audio);
        // The adopted composition supplies a Structured Reading Resource but
        // no audio rendition, so Listen (TTS from the reading) becomes
        // derivable even though the revision has no Document Rendition.
        let synced = adopted(false, true, false, Vec::new());
        let projection =
            project_capability(MaterialCapability::Listen, &revision, Some(&synced), &[]);
        assert_eq!(projection.status, CapabilityStatus::Derivable);
    }

    #[test]
    fn adopted_composition_view_projects_from_an_installation_and_plan() {
        let revision = document_revision();
        let installation = PackageInstallation {
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
                source_asset_id: None,
                producer: None,
            }],
            installed_at_ms: 10,
        };
        let plan = AdoptionCommitPlan {
            release_id: installation.release_id.clone(),
            material_id: installation.material_id.clone(),
            material_revision_id: installation.material_revision_id.clone(),
            edition: installation.edition.clone(),
            selected_resource_ids: Vec::new(),
            exclusive_selections: Vec::new(),
            selected_rendition_ids: vec!["rendition-audio".into()],
            adopted_at_ms: 20,
        };
        let composition = crate::adopted_composition_for(&installation, &plan);
        let projection = project_capability(
            MaterialCapability::Listen,
            &revision,
            Some(&composition),
            &[],
        );
        assert_eq!(projection.status, CapabilityStatus::Available);
    }
}
