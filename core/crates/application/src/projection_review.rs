use std::sync::Arc;

use domain::{
    CapabilityAssessment, CrossModalReviewCandidate, CrossModalReviewKind, LanguageCode,
    LearningChangeSource, LexicalCapability, LexicalCapabilityProfile, LexicalEntryId,
    LexicalEntryKind, ProjectionAudit, ProjectionDecision, ProjectionDecisionId,
    ProjectionDecisionKind, ProjectionEvidenceRef, ProjectionProposal, ProjectionProposalId,
    ProjectionProposalStatus, projection_proposal_v1,
};

use crate::{
    ApplicationError, LearningObservationRepository, LexicalCapabilityRepository,
    LexicalEntryRepository, now_ms,
};

const EVIDENCE_LIMIT: u32 = 500;

#[derive(Clone)]
pub struct ProjectionReviewUseCases {
    capabilities: Arc<dyn LexicalCapabilityRepository>,
    observations: Arc<dyn LearningObservationRepository>,
    entries: Arc<dyn LexicalEntryRepository>,
}

impl ProjectionReviewUseCases {
    pub(crate) fn new(
        capabilities: Arc<dyn LexicalCapabilityRepository>,
        observations: Arc<dyn LearningObservationRepository>,
        entries: Arc<dyn LexicalEntryRepository>,
    ) -> Self {
        Self {
            capabilities,
            observations,
            entries,
        }
    }

    pub fn audit_and_refresh(
        &self,
        lexical_entry_id: &LexicalEntryId,
    ) -> Result<ProjectionAudit, ApplicationError> {
        self.entries
            .lexical_details(lexical_entry_id)?
            .ok_or(ApplicationError::NotFound("lexical entry"))?;
        let now = now_ms();
        let mut reports = Vec::with_capacity(4);
        for capability in LexicalCapability::ALL {
            let evidence = self.observations.list_learning_observations(
                lexical_entry_id,
                Some(capability),
                EVIDENCE_LIMIT,
                0,
            )?;
            let (report, proposal) =
                projection_proposal_v1(lexical_entry_id, capability, &evidence, now);
            reports.push(report);
            if let Some(proposal) = proposal {
                self.capabilities.save_projection_proposal(&proposal)?;
            }
        }
        let proposals = self
            .capabilities
            .list_projection_proposals(lexical_entry_id, None)?;
        Ok(ProjectionAudit {
            lexical_entry_id: lexical_entry_id.clone(),
            reports,
            proposals,
        })
    }

    pub fn proposals(
        &self,
        lexical_entry_id: &LexicalEntryId,
    ) -> Result<Vec<ProjectionProposal>, ApplicationError> {
        self.capabilities
            .list_projection_proposals(lexical_entry_id, None)
    }

    pub fn decide(
        &self,
        proposal_id: &ProjectionProposalId,
        decision: ProjectionDecisionKind,
        note: Option<String>,
    ) -> Result<ProjectionProposal, ApplicationError> {
        let proposal = self
            .capabilities
            .projection_proposal(proposal_id)?
            .ok_or(ApplicationError::NotFound("projection proposal"))?;
        if proposal.status != ProjectionProposalStatus::Pending {
            return Err(ApplicationError::Conflict(
                "projection proposal is already resolved",
            ));
        }
        let decided_at_ms = now_ms();
        let record = ProjectionDecision {
            id: ProjectionDecisionId::from_fingerprint(
                "projection-decision",
                &format!("{}:{decision:?}:{decided_at_ms}", proposal_id.as_str()),
            ),
            proposal_id: proposal_id.clone(),
            decision,
            note,
            decided_at_ms,
        };
        // Decision + confirmed projection/history are one repository
        // transaction. An override is not touched and still wins at read time.
        self.capabilities.resolve_projection_proposal(
            &record,
            &proposal,
            (decision == ProjectionDecisionKind::Confirm)
                .then(|| proposal.confirmed_projection(decided_at_ms)),
        )?;
        if decision == ProjectionDecisionKind::Confirm {
            let profile = self
                .capabilities
                .lexical_capability_profile(&proposal.lexical_entry_id, None)?
                .ok_or(ApplicationError::NotFound("lexical entry"))?;
            if let Some(mut details) = self.entries.lexical_details(&proposal.lexical_entry_id)? {
                let legacy = profile.legacy_status_view();
                if details.entry.status != legacy {
                    details.entry.status = legacy;
                    details.entry.updated_at_ms = decided_at_ms;
                    details.entry.learning_updated_at_ms = decided_at_ms;
                    self.entries.upsert_lexical_entry(
                        &details.entry,
                        None,
                        LearningChangeSource::CapabilityOverrideSync,
                    )?;
                }
            }
        }
        self.capabilities
            .projection_proposal(proposal_id)?
            .ok_or(ApplicationError::NotFound("projection proposal"))
    }

    pub fn rebuild_language(
        &self,
        language: &LanguageCode,
    ) -> Result<Vec<ProjectionAudit>, ApplicationError> {
        let mut audits = Vec::new();
        let mut offset = 0;
        loop {
            let page = self
                .entries
                .list_lexical_entries(language, None, None, None, "", 200, offset)?;
            if page.is_empty() {
                break;
            }
            for details in &page {
                audits.push(self.audit_and_refresh(&details.entry.id)?);
            }
            offset += page.len() as u32;
        }
        Ok(audits)
    }

    pub fn cross_modal_gaps(
        &self,
        language: &LanguageCode,
        limit: u32,
    ) -> Result<Vec<CrossModalReviewCandidate>, ApplicationError> {
        let entries = self.entries.list_lexical_entries(
            language,
            Some(LexicalEntryKind::Word),
            None,
            None,
            "",
            limit.saturating_mul(4).max(40),
            0,
        )?;
        let mut result = Vec::new();
        for details in entries {
            let profile = details
                .capability_profile
                .unwrap_or_else(|| LexicalCapabilityProfile::unassessed(details.entry.id.clone()));
            let assessments = (
                profile.reading.effective_assessment(),
                profile.listening.effective_assessment(),
                profile.speaking.effective_assessment(),
                profile.writing.effective_assessment(),
            );
            let (capability, review_kind, reason) = match assessments {
                (
                    CapabilityAssessment::Acquired,
                    CapabilityAssessment::Acquired,
                    CapabilityAssessment::NotAcquired,
                    _,
                ) => (
                    LexicalCapability::Speaking,
                    CrossModalReviewKind::ConstructedSpeaking,
                    "reading/listening are acquired while speaking is explicitly not acquired",
                ),
                (
                    CapabilityAssessment::Acquired,
                    CapabilityAssessment::Acquired,
                    _,
                    CapabilityAssessment::NotAcquired,
                ) => (
                    LexicalCapability::Writing,
                    CrossModalReviewKind::WritingReconstruction,
                    "reading/listening are acquired while writing is explicitly not acquired",
                ),
                (CapabilityAssessment::Acquired, CapabilityAssessment::NotAcquired, _, _) => (
                    LexicalCapability::Listening,
                    CrossModalReviewKind::ListeningRecall,
                    "reading is acquired while listening is explicitly not acquired",
                ),
                (CapabilityAssessment::NotAcquired, _, _, _) => (
                    LexicalCapability::Reading,
                    CrossModalReviewKind::ReadingCheck,
                    "reading is explicitly not acquired",
                ),
                _ => continue, // unassessed is never treated as failure
            };
            let observations = self.observations.list_learning_observations(
                &details.entry.id,
                Some(capability),
                EVIDENCE_LIMIT,
                0,
            )?;
            let Some(source_observation) = observations.first() else {
                continue;
            };
            let display_form = details.entry.display_form;
            result.push(CrossModalReviewCandidate {
                lexical_entry_id: details.entry.id,
                display_form: display_form.clone(),
                reading: assessments.0,
                listening: assessments.1,
                speaking: assessments.2,
                writing: assessments.3,
                review_kind,
                reason: reason.into(),
                source: ProjectionEvidenceRef {
                    observation_id: source_observation.id.as_str().into(),
                    source_ref: source_observation.source_ref.clone(),
                    task_type: source_observation.task_type,
                    outcome: source_observation.outcome,
                    occurred_at_ms: source_observation.occurred_at_ms,
                    snapshot: source_observation
                        .surface_form
                        .clone()
                        .unwrap_or(display_form),
                },
            });
            if result.len() >= limit as usize {
                break;
            }
        }
        Ok(result)
    }
}
