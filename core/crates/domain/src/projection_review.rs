//! Listening-only projection proposals.
//!
//! Evidence, proposal, confirmation and effective capability remain separate.
//! Algorithms return proposals only; a confirmed decision is the sole path
//! that may copy a proposal conclusion into the projection slot.

use serde::{Deserialize, Serialize};

use crate::{
    AssistanceLevel, CapabilityConclusion, CapabilityProjection, CapabilityProjectionSource,
    LearningObservation, LexicalCapability, LexicalEntryId, ObservationOutcome,
    ObservationTaskType, ProjectionDecisionId, ProjectionProposalId,
};

pub const LISTENING_PROPOSAL_ALGORITHM_VERSION: &str = "listening-proposal-v2";

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
                .sentence_id
                .as_ref()
                .map(|value| format!("sentence:{}", value.as_str()))
                .or_else(|| {
                    item.media_id
                        .as_ref()
                        .map(|value| format!("media:{}", value.as_str()))
                })
                // An attempt ID proves which event produced this observation,
                // not that it happened in a distinct listening context.
                .unwrap_or_else(|| "unknown-context".into());
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

/// Listens only to unassisted listening evidence. A failure needs two distinct
/// contexts; a learner-confirmed upgrade can propose acquisition on its own.
pub fn listening_projection_proposal(
    lexical_entry_id: &LexicalEntryId,
    observations: &[LearningObservation],
    now_ms: u64,
) -> (ChannelQualificationReport, Option<ProjectionProposal>) {
    let eligible = observations
        .iter()
        .filter(|item| {
            item.capability == LexicalCapability::Listening
                && item.assistance == AssistanceLevel::None
        })
        .collect::<Vec<_>>();
    let confirmation = eligible
        .iter()
        .copied()
        .filter(|item| {
            item.task_type == ObservationTaskType::UpgradeConfirmation
                && item.outcome == ObservationOutcome::Success
        })
        .max_by_key(|item| item.occurred_at_ms);
    let failures = distinct_contexts(eligible.iter().copied().filter(|item| {
        item.outcome == ObservationOutcome::Failure
            && confirmation.is_none_or(|confirmed| item.occurred_at_ms > confirmed.occurred_at_ms)
    }))
    .into_iter()
    .take(2)
    .collect::<Vec<_>>();
    let result = if failures.len() >= 2 {
        Some(proposal(
            lexical_entry_id,
            LexicalCapability::Listening,
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
                LexicalCapability::Listening,
                CapabilityConclusion::Acquired,
                LISTENING_PROPOSAL_ALGORITHM_VERSION,
                0.85,
                vec![item],
                "confirmed listening upgrade evidence",
                now_ms,
            )
        })
    };
    let count = result
        .as_ref()
        .map_or(0, |value| value.evidence.len() as u32);
    let qualified = result.is_some();
    (
        ChannelQualificationReport {
            capability: LexicalCapability::Listening,
            qualification: if qualified {
                ProjectionQualification::Qualified
            } else {
                ProjectionQualification::InsufficientEvidence
            },
            algorithm_version: LISTENING_PROPOSAL_ALGORITHM_VERSION.into(),
            qualifying_evidence_count: count,
            reason: if qualified {
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
        outcome: ObservationOutcome,
        assistance: AssistanceLevel,
        source: &str,
        at: u64,
    ) -> LearningObservation {
        LearningObservation {
            id: LearningObservationId::parse(format!("o-{at}")).unwrap(),
            lexical_entry_id: LexicalEntryId::parse("entry").unwrap(),
            sense_id: None,
            capability,
            task_type,
            outcome,
            assistance,
            surface_form: Some("make it work".into()),
            sentence_id: None,
            media_id: Some(crate::MediaId::parse(source).unwrap()),
            origin: ObservationOrigin::UserMarking,
            source_ref: Some(source.into()),
            occurred_at_ms: at,
        }
    }

    #[test]
    fn listening_failure_requires_two_distinct_unassisted_contexts() {
        let entry = LexicalEntryId::parse("entry").unwrap();
        let single = vec![observation(
            LexicalCapability::Listening,
            ObservationTaskType::Dictation,
            ObservationOutcome::Failure,
            AssistanceLevel::None,
            "media-a",
            1,
        )];
        assert!(
            listening_projection_proposal(&entry, &single, 3)
                .1
                .is_none()
        );

        let distinct = vec![
            single[0].clone(),
            observation(
                LexicalCapability::Listening,
                ObservationTaskType::Dictation,
                ObservationOutcome::Failure,
                AssistanceLevel::None,
                "media-b",
                2,
            ),
        ];
        let (report, proposal) = listening_projection_proposal(&entry, &distinct, 3);
        assert_eq!(report.qualification, ProjectionQualification::Qualified);
        assert_eq!(
            proposal.unwrap().proposed_conclusion,
            CapabilityConclusion::NotAcquired
        );
    }

    #[test]
    fn retries_in_one_sentence_or_media_remain_one_failure_context() {
        let entry = LexicalEntryId::parse("entry").unwrap();
        let mut first_sentence_retry = observation(
            LexicalCapability::Listening,
            ObservationTaskType::Dictation,
            ObservationOutcome::Failure,
            AssistanceLevel::None,
            "media-a",
            1,
        );
        first_sentence_retry.sentence_id =
            Some(crate::SubtitleSentenceId::parse("sentence-a").unwrap());
        first_sentence_retry.source_ref = Some("attempt-a".into());
        let mut second_sentence_retry = first_sentence_retry.clone();
        second_sentence_retry.id = LearningObservationId::parse("o-2").unwrap();
        second_sentence_retry.source_ref = Some("attempt-b".into());
        second_sentence_retry.occurred_at_ms = 2;
        assert!(
            listening_projection_proposal(
                &entry,
                &[first_sentence_retry, second_sentence_retry],
                3,
            )
            .1
            .is_none(),
            "different attempt IDs in one sentence are still one context"
        );

        let mut first_media_retry = observation(
            LexicalCapability::Listening,
            ObservationTaskType::Dictation,
            ObservationOutcome::Failure,
            AssistanceLevel::None,
            "media-a",
            4,
        );
        first_media_retry.sentence_id = None;
        first_media_retry.source_ref = Some("attempt-c".into());
        let mut second_media_retry = first_media_retry.clone();
        second_media_retry.id = LearningObservationId::parse("o-5").unwrap();
        second_media_retry.source_ref = Some("attempt-d".into());
        second_media_retry.occurred_at_ms = 5;
        assert!(
            listening_projection_proposal(&entry, &[first_media_retry, second_media_retry], 6)
                .1
                .is_none(),
            "different attempt IDs in one media are still one context"
        );
    }

    #[test]
    fn latest_explicit_confirmation_wins_over_older_failures_only() {
        let entry = LexicalEntryId::parse("entry").unwrap();
        let older_failures = vec![
            observation(
                LexicalCapability::Listening,
                ObservationTaskType::ReviewRecall,
                ObservationOutcome::Failure,
                AssistanceLevel::None,
                "media-a",
                1,
            ),
            observation(
                LexicalCapability::Listening,
                ObservationTaskType::ReviewRecall,
                ObservationOutcome::Failure,
                AssistanceLevel::None,
                "media-b",
                2,
            ),
            observation(
                LexicalCapability::Listening,
                ObservationTaskType::UpgradeConfirmation,
                ObservationOutcome::Success,
                AssistanceLevel::None,
                "media-c",
                3,
            ),
        ];
        let (_, acquired) = listening_projection_proposal(&entry, &older_failures, 4);
        assert_eq!(
            acquired.unwrap().proposed_conclusion,
            CapabilityConclusion::Acquired
        );

        let mut later_failures = older_failures;
        later_failures.extend([
            observation(
                LexicalCapability::Listening,
                ObservationTaskType::ReviewRecall,
                ObservationOutcome::Failure,
                AssistanceLevel::None,
                "media-d",
                4,
            ),
            observation(
                LexicalCapability::Listening,
                ObservationTaskType::ReviewRecall,
                ObservationOutcome::Failure,
                AssistanceLevel::None,
                "media-e",
                5,
            ),
        ]);
        let (_, not_acquired) = listening_projection_proposal(&entry, &later_failures, 6);
        assert_eq!(
            not_acquired.unwrap().proposed_conclusion,
            CapabilityConclusion::NotAcquired
        );
    }

    #[test]
    fn only_a_learner_confirmed_upgrade_can_propose_listening_acquisition() {
        let entry = LexicalEntryId::parse("entry").unwrap();
        let assisted = observation(
            LexicalCapability::Listening,
            ObservationTaskType::ContextMarking,
            ObservationOutcome::Success,
            AssistanceLevel::FullText,
            "media-a",
            1,
        );
        let (report, proposal) = listening_projection_proposal(&entry, &[assisted], 2);
        assert_eq!(
            report.qualification,
            ProjectionQualification::InsufficientEvidence
        );
        assert!(proposal.is_none());

        let confirmed = observation(
            LexicalCapability::Listening,
            ObservationTaskType::UpgradeConfirmation,
            ObservationOutcome::Success,
            AssistanceLevel::None,
            "media-b",
            3,
        );
        let (_, proposal) = listening_projection_proposal(&entry, &[confirmed], 4);
        let projection = proposal.unwrap().confirmed_projection(5);
        assert_eq!(projection.conclusion, CapabilityConclusion::Acquired);
        assert_eq!(
            projection.source,
            CapabilityProjectionSource::EvidenceProjection
        );
    }

    #[test]
    fn non_listening_observations_never_create_listening_proposals() {
        let entry = LexicalEntryId::parse("entry").unwrap();
        let values = [1, 2].map(|at| {
            observation(
                LexicalCapability::Reading,
                ObservationTaskType::ContextMarking,
                ObservationOutcome::Failure,
                AssistanceLevel::None,
                if at == 1 { "media-a" } else { "media-b" },
                at,
            )
        });
        let (_, proposal) = listening_projection_proposal(&entry, &values, 3);
        assert!(proposal.is_none());
    }
}
