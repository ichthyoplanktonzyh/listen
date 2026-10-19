//! Phase 3.17 projection proposals and cross-modal review read models.
//!
//! Evidence, proposal, confirmation and effective capability remain separate.
//! Algorithms return proposals only; a confirmed decision is the sole path
//! that may copy a proposal conclusion into the projection slot.

use serde::{Deserialize, Serialize};

use crate::{
    AssistanceLevel, CapabilityAssessment, CapabilityConclusion, CapabilityProjection,
    CapabilityProjectionSource, LearningObservation, LexicalCapability, LexicalEntryId,
    ObservationOutcome, ObservationTaskType, ProjectionDecisionId, ProjectionProposalId,
};

pub const READING_PROJECTION_ALGORITHM_VERSION: &str = "reading-proposal-v1";
pub const LISTENING_PROPOSAL_ALGORITHM_VERSION: &str = "listening-proposal-v2";
pub const SPEAKING_PROJECTION_ALGORITHM_VERSION: &str = "speaking-proposal-v1";
pub const WRITING_PROJECTION_ALGORITHM_VERSION: &str = "writing-unassessed-v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProjectionQualification {
    Qualified,
    InsufficientEvidence,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectionEvidenceRef {
    pub observation_id: String,
    pub source_ref: Option<String>,
    pub task_type: ObservationTaskType,
    pub outcome: ObservationOutcome,
    pub occurred_at_ms: u64,
    /// Immutable fallback when the source attempt/media is unavailable.
    pub snapshot: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProjectionProposalStatus {
    Pending,
    Confirmed,
    Rejected,
    Superseded,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectionProposal {
    pub id: ProjectionProposalId,
    pub lexical_entry_id: LexicalEntryId,
    pub capability: LexicalCapability,
    pub proposed_conclusion: CapabilityConclusion,
    pub algorithm_version: String,
    pub confidence: Option<f32>,
    pub evidence_as_of_ms: u64,
    pub evidence: Vec<ProjectionEvidenceRef>,
    pub rationale: String,
    pub status: ProjectionProposalStatus,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProjectionDecisionKind {
    Confirm,
    Reject,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProjectionDecision {
    pub id: ProjectionDecisionId,
    pub proposal_id: ProjectionProposalId,
    pub decision: ProjectionDecisionKind,
    pub note: Option<String>,
    pub decided_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChannelQualificationReport {
    pub capability: LexicalCapability,
    pub qualification: ProjectionQualification,
    pub algorithm_version: String,
    pub qualifying_evidence_count: u32,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProjectionAudit {
    pub lexical_entry_id: LexicalEntryId,
    pub reports: Vec<ChannelQualificationReport>,
    pub proposals: Vec<ProjectionProposal>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CrossModalReviewKind {
    ReadingCheck,
    ListeningRecall,
    ConstructedSpeaking,
    WritingReconstruction,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CrossModalReviewCandidate {
    pub lexical_entry_id: LexicalEntryId,
    pub display_form: String,
    pub reading: CapabilityAssessment,
    pub listening: CapabilityAssessment,
    pub speaking: CapabilityAssessment,
    pub writing: CapabilityAssessment,
    pub review_kind: CrossModalReviewKind,
    pub reason: String,
    pub source: ProjectionEvidenceRef,
}

fn evidence_ref(value: &LearningObservation) -> ProjectionEvidenceRef {
    ProjectionEvidenceRef {
        observation_id: value.id.as_str().to_owned(),
        source_ref: value.source_ref.clone(),
        task_type: value.task_type,
        outcome: value.outcome,
        occurred_at_ms: value.occurred_at_ms,
        snapshot: value
            .surface_form
            .clone()
            .unwrap_or_else(|| "learning observation".into()),
    }
}

fn distinct_contexts<'a>(
    observations: impl IntoIterator<Item = &'a LearningObservation>,
) -> Vec<&'a LearningObservation> {
    let mut seen = std::collections::HashSet::new();
    observations
        .into_iter()
        .filter(|item| {
            let key = item
                .source_ref
                .as_ref()
                .map(|value| format!("source:{value}"))
                .or_else(|| {
                    item.sentence_id
                        .as_ref()
                        .map(|value| format!("sentence:{}", value.as_str()))
                })
                .or_else(|| {
                    item.media_id
                        .as_ref()
                        .map(|value| format!("media:{}", value.as_str()))
                })
                .unwrap_or_else(|| format!("observation:{}", item.id.as_str()));
            seen.insert(key)
        })
        .collect()
}

#[allow(clippy::too_many_arguments)]
fn proposal(
    lexical_entry_id: &LexicalEntryId,
    capability: LexicalCapability,
    conclusion: CapabilityConclusion,
    algorithm_version: &str,
    confidence: f32,
    evidence: Vec<&LearningObservation>,
    rationale: &str,
    now_ms: u64,
) -> ProjectionProposal {
    let evidence_as_of_ms = evidence
        .iter()
        .map(|item| item.occurred_at_ms)
        .max()
        .unwrap_or(0);
    let fingerprint = format!(
        "{}:{capability:?}:{conclusion:?}:{algorithm_version}:{}",
        lexical_entry_id.as_str(),
        evidence_as_of_ms
    );
    ProjectionProposal {
        id: ProjectionProposalId::from_fingerprint("projection-proposal", &fingerprint),
        lexical_entry_id: lexical_entry_id.clone(),
        capability,
        proposed_conclusion: conclusion,
        algorithm_version: algorithm_version.into(),
        confidence: Some(confidence),
        evidence_as_of_ms,
        evidence: evidence.into_iter().map(evidence_ref).collect(),
        rationale: rationale.into(),
        status: ProjectionProposalStatus::Pending,
        created_at_ms: now_ms,
    }
}

/// Channel-local proposal. Cross-channel facts are never inspected.
pub fn projection_proposal_v1(
    lexical_entry_id: &LexicalEntryId,
    capability: LexicalCapability,
    observations: &[LearningObservation],
    now_ms: u64,
) -> (ChannelQualificationReport, Option<ProjectionProposal>) {
    let channel = observations
        .iter()
        .filter(|item| item.capability == capability)
        .collect::<Vec<_>>();
    let (version, result): (&str, Option<ProjectionProposal>) = match capability {
        LexicalCapability::Reading => {
            let eligible = channel
                .iter()
                .copied()
                .filter(|item| {
                    item.task_type == ObservationTaskType::ReadingContextMarking
                        && item.assistance == AssistanceLevel::None
                })
                .collect::<Vec<_>>();
            let failures = distinct_contexts(
                eligible
                    .iter()
                    .copied()
                    .filter(|item| item.outcome == ObservationOutcome::Failure),
            );
            let successes = distinct_contexts(
                eligible
                    .iter()
                    .copied()
                    .filter(|item| item.outcome == ObservationOutcome::Success),
            );
            let value = if let Some(latest) = failures.first() {
                Some(proposal(
                    lexical_entry_id,
                    capability,
                    CapabilityConclusion::NotAcquired,
                    READING_PROJECTION_ALGORITHM_VERSION,
                    0.8,
                    vec![*latest],
                    "explicit unassisted reading difficulty",
                    now_ms,
                ))
            } else if successes.len() >= 2 {
                Some(proposal(
                    lexical_entry_id,
                    capability,
                    CapabilityConclusion::Acquired,
                    READING_PROJECTION_ALGORITHM_VERSION,
                    0.8,
                    successes.into_iter().take(2).collect(),
                    "two explicit unassisted reading successes",
                    now_ms,
                ))
            } else {
                None
            };
            (READING_PROJECTION_ALGORITHM_VERSION, value)
        }
        LexicalCapability::Listening => {
            let eligible = channel
                .iter()
                .copied()
                .filter(|item| item.assistance == AssistanceLevel::None)
                .collect::<Vec<_>>();
            let confirmation = eligible.iter().copied().find(|item| {
                item.task_type == ObservationTaskType::UpgradeConfirmation
                    && item.outcome == ObservationOutcome::Success
            });
            let failures = distinct_contexts(
                eligible
                    .iter()
                    .copied()
                    .filter(|item| item.outcome == ObservationOutcome::Failure),
            )
            .into_iter()
            .take(2)
            .collect::<Vec<_>>();
            let value = if failures.len() >= 2 {
                Some(proposal(
                    lexical_entry_id,
                    capability,
                    CapabilityConclusion::NotAcquired,
                    LISTENING_PROPOSAL_ALGORITHM_VERSION,
                    0.85,
                    failures,
                    "two unassisted listening failures",
                    now_ms,
                ))
            } else {
                confirmation.map(|item| {
                    proposal(
                        lexical_entry_id,
                        capability,
                        CapabilityConclusion::Acquired,
                        LISTENING_PROPOSAL_ALGORITHM_VERSION,
                        0.85,
                        vec![item],
                        "confirmed listening upgrade evidence",
                        now_ms,
                    )
                })
            };
            (LISTENING_PROPOSAL_ALGORITHM_VERSION, value)
        }
        LexicalCapability::Speaking => {
            let successes = distinct_contexts(channel.iter().copied().filter(|item| {
                item.task_type == ObservationTaskType::SpeakingProduction
                    && item.assistance == AssistanceLevel::None
                    && item.outcome == ObservationOutcome::Success
            }));
            let value = (successes.len() >= 2).then(|| {
                proposal(
                    lexical_entry_id,
                    capability,
                    CapabilityConclusion::Acquired,
                    SPEAKING_PROJECTION_ALGORITHM_VERSION,
                    0.8,
                    successes.into_iter().take(2).collect(),
                    "two user-confirmed unassisted constructed speaking uses",
                    now_ms,
                )
            });
            (SPEAKING_PROJECTION_ALGORITHM_VERSION, value)
        }
        LexicalCapability::Writing => (WRITING_PROJECTION_ALGORITHM_VERSION, None),
    };
    let count = result
        .as_ref()
        .map_or(0, |value| value.evidence.len() as u32);
    let qualified = result.is_some();
    (
        ChannelQualificationReport {
            capability,
            qualification: if qualified {
                ProjectionQualification::Qualified
            } else {
                ProjectionQualification::InsufficientEvidence
            },
            algorithm_version: version.into(),
            qualifying_evidence_count: count,
            reason: if capability == LexicalCapability::Writing {
                "no lexical-target writing confirmation exists; immutable writing attempts remain source facts".into()
            } else if qualified {
                "channel-local qualified evidence supports a correctable proposal".into()
            } else {
                "qualified evidence threshold not met; keep unassessed".into()
            },
        },
        result,
    )
}

impl ProjectionProposal {
    pub fn confirmed_projection(&self, now_ms: u64) -> CapabilityProjection {
        CapabilityProjection {
            conclusion: self.proposed_conclusion,
            source: CapabilityProjectionSource::EvidenceProjection,
            algorithm_version: self.algorithm_version.clone(),
            confidence: self.confidence,
            evidence_as_of_ms: Some(self.evidence_as_of_ms),
            updated_at_ms: now_ms,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{LearningObservationId, ObservationOrigin};

    fn observation(
        capability: LexicalCapability,
        task_type: ObservationTaskType,
        at: u64,
    ) -> LearningObservation {
        LearningObservation {
            id: LearningObservationId::parse(format!("o-{at}")).unwrap(),
            lexical_entry_id: LexicalEntryId::parse("entry").unwrap(),
            sense_id: None,
            capability,
            task_type,
            outcome: ObservationOutcome::Success,
            assistance: AssistanceLevel::None,
            surface_form: Some("make it work".into()),
            sentence_id: None,
            media_id: None,
            origin: ObservationOrigin::UserMarking,
            source_ref: Some(format!("attempt-{at}")),
            occurred_at_ms: at,
        }
    }

    #[test]
    fn channels_never_borrow_each_others_evidence() {
        let entry = LexicalEntryId::parse("entry").unwrap();
        let speaking = vec![
            observation(
                LexicalCapability::Speaking,
                ObservationTaskType::SpeakingProduction,
                1,
            ),
            observation(
                LexicalCapability::Speaking,
                ObservationTaskType::SpeakingProduction,
                2,
            ),
        ];
        assert!(
            projection_proposal_v1(&entry, LexicalCapability::Speaking, &speaking, 3)
                .1
                .is_some()
        );
        assert!(
            projection_proposal_v1(&entry, LexicalCapability::Writing, &speaking, 3)
                .1
                .is_none()
        );
    }

    #[test]
    fn writing_stays_unassessed_without_target_confirmation() {
        let entry = LexicalEntryId::parse("entry").unwrap();
        let (report, proposal) = projection_proposal_v1(&entry, LexicalCapability::Writing, &[], 1);
        assert_eq!(
            report.qualification,
            ProjectionQualification::InsufficientEvidence
        );
        assert!(proposal.is_none());
    }
}
