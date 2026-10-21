//! Material Capability projection and attempts (contract 5.0.0).
//!
//! A Material Capability is a modality view over one Material: Read, Listen,
//! Watch, or synchronized Read-and-Listen. The projection reports
//! `available`, `derivable`, `generating`, `unavailable`, or `failed_attempt`
//! by reading both the current Material revision and the selected adopted
//! composition.
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
    MediaKind, Rendition, RenditionOrigin,
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
    /// The current media source or adopted composition already provides it.
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

/// An available source media rendition that agrees with its declared media
/// kind. Material API inputs bind source renditions to the current media item;
/// keep the checks here too so stale or malformed snapshots do not advertise
/// a playback capability.
fn revision_has_media_kind(revision: &MaterialRevision, kind: MediaKind) -> bool {
    revision.renditions.iter().any(|rendition| {
        matches!(
            rendition,
            Rendition::Media(media)
                if media.origin == RenditionOrigin::Source
                    && media.media_id.is_some()
                    && media.availability == crate::MediaAvailability::Available
                    && media.kind == kind
                    && crate::media_type_kind(&media.media_type) == Some(kind)
        )
    })
}

/// A source Document Rendition is an input from which reading and audio can
/// be produced. It must still point at an available Source Asset in this
/// revision; a derived or detached document is not a new source.
fn revision_has_document(revision: &MaterialRevision) -> bool {
    revision.renditions.iter().any(|rendition| {
        matches!(
            rendition,
            Rendition::Document(document)
                if document.origin == RenditionOrigin::Source
                    && document.source_asset_id.as_ref().is_some_and(|asset_id| {
                        revision.source_assets.iter().any(|asset| {
                            asset.id == *asset_id
                                && asset.availability == crate::SourceAssetAvailability::Available
                        })
                    })
        )
    })
}

/// A selected, available media rendition of the adopted composition.
fn adopted_has_media_kind(adopted: Option<&AdoptedComposition>, kind: MediaKind) -> bool {
    adopted.is_some_and(|adopted| {
        adopted.renditions.iter().any(|rendition| {
            rendition.kind == "media"
                && rendition.available
                && adopted
                    .selected_rendition_ids
                    .contains(&rendition.rendition_id)
                && crate::media_type_kind(&rendition.media_type) == Some(kind)
        })
    })
}

fn has_media(revision: &MaterialRevision, adopted: Option<&AdoptedComposition>) -> bool {
    [MediaKind::Audio, MediaKind::Video]
        .into_iter()
        .any(|kind| {
            revision_has_media_kind(revision, kind) || adopted_has_media_kind(adopted, kind)
        })
}

fn adopted_has_structured_reading(adopted: &AdoptedComposition) -> bool {
    adopted.resources.iter().any(|resource| {
        resource.kind == "structured_reading"
            && resource.availability == crate::PackageResourceAvailability::Available
            && adopted
                .selected_resource_ids
                .contains(&resource.resource_id)
    })
}

fn adopted_has_matching_alignment(adopted: &AdoptedComposition) -> bool {
    let reading_ids: Vec<&str> = adopted
        .resources
        .iter()
        .filter(|resource| {
            resource.kind == "structured_reading"
                && resource.availability == crate::PackageResourceAvailability::Available
                && adopted
                    .selected_resource_ids
                    .contains(&resource.resource_id)
        })
        .map(|resource| resource.resource_id.as_str())
        .collect();
    !reading_ids.is_empty()
        && adopted.resources.iter().any(|alignment| {
            alignment.kind == "anchor_time_alignment"
                && alignment.availability == crate::PackageResourceAvailability::Available
                && adopted
                    .selected_resource_ids
                    .contains(&alignment.resource_id)
                && alignment.anchor_resource_ids.iter().any(|anchor_id| {
                    reading_ids
                        .iter()
                        .any(|reading_id| *reading_id == anchor_id)
                })
        })
}

/// Structural derivation rules for listening capabilities, independent of
/// provider configuration. Read and synchronized Read-and-Listen can be
/// produced from audio/video or a source document. Listen can also be
/// synthesized from a source document; Watch requires existing video.
fn derivation_prerequisite(
    capability: MaterialCapability,
    revision: &MaterialRevision,
    adopted: Option<&AdoptedComposition>,
) -> bool {
    match capability {
        MaterialCapability::Read | MaterialCapability::SynchronizedReadListen => {
            has_media(revision, adopted) || revision_has_document(revision)
        }
        MaterialCapability::Listen => revision_has_document(revision),
        MaterialCapability::Watch => false,
    }
}

/// Whether the current source or selected package composition already
/// provides a capability. Structured-reading capabilities require an exact,
/// available package resource and either a source document or media input.
/// Media playback itself needs no package adoption when the current revision
/// already binds the source rendition.
fn current_source_or_adoption_provides(
    capability: MaterialCapability,
    revision: &MaterialRevision,
    adopted: Option<&AdoptedComposition>,
) -> bool {
    let has_audio = revision_has_media_kind(revision, MediaKind::Audio)
        || adopted_has_media_kind(adopted, MediaKind::Audio);
    let has_video = revision_has_media_kind(revision, MediaKind::Video)
        || adopted_has_media_kind(adopted, MediaKind::Video);
    let Some(adopted) = adopted else {
        return match capability {
            MaterialCapability::Listen => has_audio,
            MaterialCapability::Watch => has_video,
            MaterialCapability::Read | MaterialCapability::SynchronizedReadListen => false,
        };
    };
    let media_available = has_audio || has_video;
    let document_available = revision_has_document(revision)
        || adopted.renditions.iter().any(|rendition| {
            rendition.kind == "document"
                && rendition.available
                && adopted
                    .selected_rendition_ids
                    .contains(&rendition.rendition_id)
        });
    let has_structured_reading = adopted_has_structured_reading(adopted);
    match capability {
        MaterialCapability::Read => {
            (media_available || document_available) && has_structured_reading
        }
        MaterialCapability::Listen => has_audio,
        MaterialCapability::Watch => has_video,
        MaterialCapability::SynchronizedReadListen => {
            (media_available || document_available)
                && has_structured_reading
                && adopted_has_matching_alignment(adopted)
        }
    }
}

/// The five-state projection for one capability over the exact Material facts
/// and the adopted composition.
///
/// 1. A source or adopted composition that provides the capability is `available`.
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
    let status = if current_source_or_adoption_provides(capability, revision, adopted) {
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
        PackageInstallation, PackageReleaseId, PackageResourceFact, RenditionOrigin, SourceAsset,
        SourceAssetAvailability, SourceAssetBinding,
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
        let bytes = b"hello world";
        let source_asset = SourceAsset::new(
            "text/plain",
            bytes.len() as u64,
            text_digest("hello world"),
            SourceAssetBinding::Managed,
            SourceAssetAvailability::Available,
            1,
        )
        .expect("valid source asset");
        MaterialRevision::new(
            material_id,
            "Doc",
            vec![source_asset.clone()],
            vec![Rendition::Document(
                DocumentRendition::new(
                    RenditionOrigin::Source,
                    "text/plain",
                    Some(language("en")),
                    text_digest("hello world"),
                    11,
                    Some(source_asset.id),
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
        media_revision_with_availability(kind, crate::MediaAvailability::Available)
    }

    fn media_revision_with_availability(
        kind: MediaKind,
        availability: crate::MediaAvailability,
    ) -> MaterialRevision {
        let (material_id, media_id, fingerprint, media_type) = match kind {
            MediaKind::Audio => ("material-audio", "media-audio", "fp-audio", "audio/mpeg"),
            MediaKind::Video => ("material-video", "media-video", "fp-video", "video/mp4"),
        };
        MaterialRevision::new(
            LearningMaterialId::parse(material_id).expect("valid material id"),
            "Media",
            vec![],
            vec![Rendition::Media(
                crate::MediaRendition::new(
                    RenditionOrigin::Source,
                    kind,
                    media_type,
                    fingerprint,
                    availability,
                    Some(crate::MediaId::parse(media_id).expect("valid media id")),
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
            LearningMaterialId::parse("material-audio").expect("valid material id"),
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
    fn document_sources_can_be_read_or_synthesized_but_not_watched() {
        let revision = document_revision();
        for capability in [
            MaterialCapability::Read,
            MaterialCapability::Listen,
            MaterialCapability::SynchronizedReadListen,
        ] {
            assert_eq!(
                project_capability(capability, &revision, None, &[]).status,
                CapabilityStatus::Derivable,
                "a source document can derive {capability:?}"
            );
        }
        assert_eq!(
            project_capability(MaterialCapability::Watch, &revision, None, &[]).status,
            CapabilityStatus::Unavailable
        );

        let mut adopted_document = adopted(false, false, false, Vec::new());
        adopted_document
            .renditions
            .push(crate::PackageRenditionFact {
                rendition_id: "rendition-document".into(),
                kind: "document".into(),
                origin: RenditionOrigin::Source,
                media_type: "text/plain".into(),
                available: true,
                media_digest: format!("sha256:{}", "d".repeat(64)),
                media_size_bytes: 11,
                media_id: None,
                source_asset_id: None,
                producer: None,
            });
        adopted_document
            .selected_rendition_ids
            .push("rendition-document".into());
        for capability in [
            MaterialCapability::Read,
            MaterialCapability::Listen,
            MaterialCapability::SynchronizedReadListen,
        ] {
            assert_eq!(
                project_capability(capability, &revision, Some(&adopted_document), &[]).status,
                CapabilityStatus::Derivable,
                "structured reading has not yet been selected for {capability:?}"
            );
        }
        assert_eq!(
            project_capability(
                MaterialCapability::Watch,
                &revision,
                Some(&adopted_document),
                &[]
            )
            .status,
            CapabilityStatus::Unavailable
        );
    }

    #[test]
    fn audio_and_video_sources_project_direct_and_derivable_capabilities() {
        let audio = media_revision(MediaKind::Audio);
        assert_eq!(
            project_capability(MaterialCapability::Listen, &audio, None, &[]).status,
            CapabilityStatus::Available
        );
        assert_eq!(
            project_capability(MaterialCapability::Watch, &audio, None, &[]).status,
            CapabilityStatus::Unavailable
        );
        for capability in [
            MaterialCapability::Read,
            MaterialCapability::SynchronizedReadListen,
        ] {
            assert_eq!(
                project_capability(capability, &audio, None, &[]).status,
                CapabilityStatus::Derivable
            );
        }

        let video = media_revision(MediaKind::Video);
        assert_eq!(
            project_capability(MaterialCapability::Listen, &video, None, &[]).status,
            CapabilityStatus::Unavailable
        );
        assert_eq!(
            project_capability(MaterialCapability::Watch, &video, None, &[]).status,
            CapabilityStatus::Available
        );
        for capability in [
            MaterialCapability::Read,
            MaterialCapability::SynchronizedReadListen,
        ] {
            assert_eq!(
                project_capability(capability, &video, None, &[]).status,
                CapabilityStatus::Derivable
            );
        }
    }

    #[test]
    fn unavailable_or_mislabeled_source_renditions_do_not_enable_capabilities() {
        let missing =
            media_revision_with_availability(MediaKind::Audio, crate::MediaAvailability::Missing);
        for capability in [
            MaterialCapability::Read,
            MaterialCapability::Listen,
            MaterialCapability::Watch,
            MaterialCapability::SynchronizedReadListen,
        ] {
            assert_eq!(
                project_capability(capability, &missing, None, &[]).status,
                CapabilityStatus::Unavailable
            );
        }

        let mut mislabeled = media_revision(MediaKind::Audio);
        let Rendition::Media(media) = &mut mislabeled.renditions[0] else {
            unreachable!("fixture has a media rendition")
        };
        media.media_type = "video/mp4".into();
        assert_eq!(
            project_capability(MaterialCapability::Listen, &mislabeled, None, &[]).status,
            CapabilityStatus::Unavailable
        );
        assert_eq!(
            project_capability(MaterialCapability::Watch, &mislabeled, None, &[]).status,
            CapabilityStatus::Unavailable
        );
    }

    #[test]
    fn running_and_failed_attempts_drive_generating_and_failed_attempt() {
        let revision = media_revision(MediaKind::Audio);
        let running = project_capability(
            MaterialCapability::Read,
            &revision,
            None,
            &[attempt(
                MaterialCapability::Read,
                CapabilityAttemptStatus::Running,
                1,
            )],
        );
        assert_eq!(running.status, CapabilityStatus::Generating);
        let failed = project_capability(
            MaterialCapability::Read,
            &revision,
            None,
            &[attempt(
                MaterialCapability::Read,
                CapabilityAttemptStatus::Failed,
                1,
            )],
        );
        assert_eq!(failed.status, CapabilityStatus::FailedAttempt);
        // Failure is attached to the attempt; the attempt facts are never
        // rewritten by a later attempt.
        let first = attempt(MaterialCapability::Read, CapabilityAttemptStatus::Failed, 1);
        let mut later = attempt(MaterialCapability::Read, CapabilityAttemptStatus::Failed, 2);
        later.started_at_ms = 9;
        let projection = project_capability(
            MaterialCapability::Read,
            &revision,
            None,
            &[first.clone(), later.clone()],
        );
        assert_eq!(projection.status, CapabilityStatus::FailedAttempt);
        assert_eq!(projection.latest_attempt.expect("attempt").started_at_ms, 9);
    }

    #[test]
    fn cancelled_and_superseded_attempts_are_never_failed_attempts() {
        let revision = media_revision(MediaKind::Audio);
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
                MaterialCapability::Read,
                &revision,
                None,
                &[attempt(MaterialCapability::Read, status, 1)],
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
        let revision = media_revision(MediaKind::Audio);
        let projection = project_capability(
            MaterialCapability::Read,
            &revision,
            None,
            &[attempt(
                MaterialCapability::Read,
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
            selected_rendition_ids: if with_audio {
                vec!["rendition-audio".into()]
            } else {
                Vec::new()
            },
        }
    }

    #[test]
    fn adopted_audio_and_exact_reading_alignment_provide_capabilities() {
        let revision = media_revision(MediaKind::Video);
        // A selected audio rendition makes Listen available for a video
        // material without requiring a package adoption for its source video.
        let audio_only = adopted(true, false, false, Vec::new());
        let listen = project_capability(
            MaterialCapability::Listen,
            &revision,
            Some(&audio_only),
            &[],
        );
        assert_eq!(listen.status, CapabilityStatus::Available);

        // Structured reading + available media + a compatible alignment make
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
        // from the current media, but is never available from the adoption.
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
    fn structured_reading_does_not_create_independent_listen_audio() {
        let revision = media_revision(MediaKind::Video);
        // An adopted reading resource does not derive audio. Video playback
        // remains Watch, and Read can use the adopted structure.
        let synced = adopted(false, true, false, Vec::new());
        let listen = project_capability(MaterialCapability::Listen, &revision, Some(&synced), &[]);
        assert_eq!(listen.status, CapabilityStatus::Unavailable);
        let read = project_capability(MaterialCapability::Read, &revision, Some(&synced), &[]);
        assert_eq!(read.status, CapabilityStatus::Available);
    }

    #[test]
    fn adopted_composition_view_projects_from_an_installation_and_plan() {
        let revision = media_revision(MediaKind::Video);
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

    #[test]
    fn adopted_media_must_be_available_and_selected() {
        let revision = media_revision(MediaKind::Video);
        let mut unavailable = adopted(true, false, false, Vec::new());
        unavailable.renditions[0].available = false;
        assert_eq!(
            project_capability(
                MaterialCapability::Listen,
                &revision,
                Some(&unavailable),
                &[]
            )
            .status,
            CapabilityStatus::Unavailable
        );

        let mut unselected = adopted(true, false, false, Vec::new());
        unselected.selected_rendition_ids.clear();
        assert_eq!(
            project_capability(
                MaterialCapability::Listen,
                &revision,
                Some(&unselected),
                &[]
            )
            .status,
            CapabilityStatus::Unavailable
        );
    }
}
