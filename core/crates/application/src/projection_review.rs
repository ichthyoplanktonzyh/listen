use std::sync::Arc;

use domain::{
    LanguageCode, LearningChangeSource, LexicalCapability, LexicalEntryId, LexicalEntryKind,
    ProjectionDecision, ProjectionDecisionId, ProjectionDecisionKind, ProjectionProposal,
    ProjectionProposalId, ProjectionProposalStatus, listening_projection_proposal,
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

    /// Re-evaluates only listening evidence and returns its correctable
    /// proposal. The user still has to confirm a proposed projection.
    pub fn audit_and_refresh(
        &self,
        lexical_entry_id: &LexicalEntryId,
    ) -> Result<domain::ProjectionAudit, ApplicationError> {
        self.entries
            .lexical_details(lexical_entry_id)?
            .ok_or(ApplicationError::NotFound("lexical entry"))?;
        let evidence = self.observations.list_learning_observations(
            lexical_entry_id,
            Some(LexicalCapability::Listening),
            EVIDENCE_LIMIT,
            0,
        )?;
        let (report, proposal) =
            listening_projection_proposal(lexical_entry_id, &evidence, now_ms());
        if let Some(proposal) = proposal {
            self.capabilities.save_projection_proposal(&proposal)?;
        }
        let proposals = self
            .capabilities
            .list_projection_proposals(lexical_entry_id, Some(LexicalCapability::Listening))?;
        Ok(domain::ProjectionAudit {
            lexical_entry_id: lexical_entry_id.clone(),
            reports: vec![report],
            proposals,
        })
    }

    pub fn proposals(
        &self,
        lexical_entry_id: &LexicalEntryId,
    ) -> Result<Vec<ProjectionProposal>, ApplicationError> {
        self.capabilities
            .list_projection_proposals(lexical_entry_id, Some(LexicalCapability::Listening))
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
        if proposal.capability != LexicalCapability::Listening {
            return Err(ApplicationError::Validation(
                "only listening projection proposals are active",
            ));
        }
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
        self.capabilities.resolve_projection_proposal(
            &record,
            &proposal,
            (decision == ProjectionDecisionKind::Confirm)
                .then(|| proposal.confirmed_projection(decided_at_ms)),
        )?;
        if decision == ProjectionDecisionKind::Confirm {
            self.sync_legacy_listening_status(&proposal.lexical_entry_id, decided_at_ms)?;
        }
        self.capabilities
            .projection_proposal(proposal_id)?
            .ok_or(ApplicationError::NotFound("projection proposal"))
    }

    /// Refreshes listening projections for the learner's existing word
    /// entries. Other capability dimensions are not queried or proposed here.
    pub fn rebuild_language(
        &self,
        language: &LanguageCode,
    ) -> Result<Vec<domain::ProjectionAudit>, ApplicationError> {
        let mut audits = Vec::new();
        let mut offset = 0;
        loop {
            let page = self.entries.list_lexical_entries(
                language,
                Some(LexicalEntryKind::Word),
                None,
                None,
                "",
                200,
                offset,
            )?;
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

    fn sync_legacy_listening_status(
        &self,
        lexical_entry_id: &LexicalEntryId,
        decided_at_ms: u64,
    ) -> Result<(), ApplicationError> {
        let profile = self
            .capabilities
            .lexical_capability_profile(lexical_entry_id, None)?
            .ok_or(ApplicationError::NotFound("lexical entry"))?;
        if let Some(mut details) = self.entries.lexical_details(lexical_entry_id)? {
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
        Ok(())
    }
}
