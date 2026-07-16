//! Phase 3.11 semantic task use cases (ADR 0021).
//!
//! Everything here is clip-level fact recording. No path in this module
//! writes `LearningObservation`, touches capability profiles/overrides, or
//! consumes `PracticeAttempt` results — the four-layer separation is enforced
//! by construction, and the negative tests in persistence-sqlite pin it.

use domain::{
    JudgmentAdjudication, LanguageCode, MediaId, SemanticGeneratorKind,
    SemanticGeneratorProvenance, SemanticJudgment, SemanticJudgmentId, SemanticRubric,
    SemanticRubricId, SemanticTaskAttempt, SemanticTaskAttemptId, SemanticTaskKind, WritingDraft,
    WritingFeedbackFinding, WritingFeedbackFindingId, WritingFindingDisposition,
    semantic_judgment_id, transcript_sha256, validate_judgment_adjudication,
    validate_semantic_attempt, validate_semantic_judgment, validate_semantic_rubric,
    validate_writing_feedback_finding, validate_writing_finding_disposition,
};
use std::sync::Arc;

use crate::{
    ApplicationError, JudgeRequest, JudgmentDraft, SemanticJudgeProvider, SemanticTaskRepository,
};

fn invalid(errors: Vec<String>) -> ApplicationError {
    ApplicationError::Invalid(errors.join("; "))
}

/// AGENT.md evidence class for an unqualified LLM judgment. It is a heuristic
/// proxy until Phase 3.12.1 holdout qualification decides display eligibility;
/// storing it here writes no observation and unlocks no learning surface.
const LLM_JUDGMENT_EVIDENCE_CLASS: &str = "heuristic_proxy";

#[derive(Clone)]
pub struct SemanticUseCases {
    semantic_tasks: Arc<dyn SemanticTaskRepository>,
}

impl SemanticUseCases {
    pub(crate) fn new(semantic_tasks: Arc<dyn SemanticTaskRepository>) -> Self {
        Self { semantic_tasks }
    }

    /// Saves a rubric version. Version 1 creates the rubric; higher versions
    /// are manual revisions and must extend an existing earlier version.
    /// Existing (id, version) rows are never overwritten.
    pub fn save_semantic_rubric(
        &self,
        rubric: SemanticRubric,
    ) -> Result<SemanticRubric, ApplicationError> {
        validate_semantic_rubric(&rubric).map_err(invalid)?;
        if self
            .semantic_tasks
            .get_semantic_rubric(&rubric.id, rubric.version)?
            .is_some()
        {
            return Err(ApplicationError::Conflict(
                "semantic rubric version already exists",
            ));
        }
        if let Some(revision) = &rubric.revision {
            let revised_from = self
                .semantic_tasks
                .get_semantic_rubric(&rubric.id, revision.revised_from_version)?
                .ok_or(ApplicationError::NotFound("revised rubric version"))?;
            if revised_from.source.transcript_snapshot != rubric.source.transcript_snapshot {
                return Err(ApplicationError::Invalid(
                    "a rubric revision must keep the source snapshot; a new segment is a new rubric"
                        .into(),
                ));
            }
        }
        self.semantic_tasks.save_semantic_rubric(&rubric)
    }

    pub fn semantic_rubric(
        &self,
        id: &SemanticRubricId,
        version: Option<u32>,
    ) -> Result<Option<SemanticRubric>, ApplicationError> {
        match version {
            Some(version) => self.semantic_tasks.get_semantic_rubric(id, version),
            None => self.semantic_tasks.latest_semantic_rubric(id),
        }
    }

    /// Read-side lookup by source identity, so a client that only knows the
    /// segment (not the server-minted fingerprint id) can find an existing
    /// rubric instead of colliding with a 409 on re-create (Phase 3.13).
    pub fn find_rubric_for_source(
        &self,
        media_id: Option<&str>,
        start_ms: u64,
        end_ms: u64,
        purpose: SemanticTaskKind,
        response_language: &str,
        source_sha256: &str,
    ) -> Result<Option<SemanticRubric>, ApplicationError> {
        let media_id = media_id
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(MediaId::parse)
            .transpose()?;
        let response_language = LanguageCode::parse(response_language)?;
        self.semantic_tasks.find_semantic_rubric_by_source(
            media_id.as_ref(),
            start_ms,
            end_ms,
            purpose,
            &response_language,
            source_sha256,
        )
    }

    /// Records a finished (completed or abandoned) semantic attempt against
    /// an existing rubric version.
    pub fn record_semantic_attempt(
        &self,
        attempt: SemanticTaskAttempt,
    ) -> Result<SemanticTaskAttempt, ApplicationError> {
        let rubric = self
            .semantic_tasks
            .get_semantic_rubric(&attempt.rubric_id, attempt.rubric_version)?
            .ok_or(ApplicationError::NotFound("semantic rubric"))?;
        validate_semantic_attempt(&attempt, &rubric).map_err(invalid)?;
        if self
            .semantic_tasks
            .get_semantic_attempt(&attempt.id)?
            .is_some()
        {
            return Err(ApplicationError::Conflict(
                "semantic attempt already exists",
            ));
        }
        self.semantic_tasks.save_semantic_attempt(&attempt)
    }

    pub fn semantic_attempt(
        &self,
        id: &SemanticTaskAttemptId,
    ) -> Result<Option<SemanticTaskAttempt>, ApplicationError> {
        self.semantic_tasks.get_semantic_attempt(id)
    }

    pub fn semantic_attempts_for_rubric(
        &self,
        rubric_id: &SemanticRubricId,
    ) -> Result<Vec<SemanticTaskAttempt>, ApplicationError> {
        self.semantic_tasks
            .list_semantic_attempts_for_rubric(rubric_id)
    }

    /// Records one judgment over one response revision. The judgment must
    /// cite the same rubric identity/version/snapshot as its attempt; failed
    /// or absent evaluation is never synthesized — no judgment row, no
    /// conclusion.
    pub fn record_semantic_judgment(
        &self,
        judgment: SemanticJudgment,
    ) -> Result<SemanticJudgment, ApplicationError> {
        let attempt = self
            .semantic_tasks
            .get_semantic_attempt(&judgment.attempt_id)?
            .ok_or(ApplicationError::NotFound("semantic attempt"))?;
        let rubric = self
            .semantic_tasks
            .get_semantic_rubric(&judgment.rubric_id, judgment.rubric_version)?
            .ok_or(ApplicationError::NotFound("semantic rubric"))?;
        validate_semantic_judgment(&judgment, &rubric, &attempt).map_err(invalid)?;
        if self
            .semantic_tasks
            .get_semantic_judgment(&judgment.id)?
            .is_some()
        {
            return Err(ApplicationError::Conflict(
                "semantic judgment already exists",
            ));
        }
        self.semantic_tasks.save_semantic_judgment(&judgment)
    }

    pub fn semantic_judgments_for_attempt(
        &self,
        attempt_id: &SemanticTaskAttemptId,
    ) -> Result<Vec<SemanticJudgment>, ApplicationError> {
        self.semantic_tasks
            .list_semantic_judgments_for_attempt(attempt_id)
    }

    /// Records a user confirming or correcting one judged point. This is an
    /// adjudication of one automatic assertion — not a capability override —
    /// and the original judgment row stays byte-identical.
    pub fn record_judgment_adjudication(
        &self,
        adjudication: JudgmentAdjudication,
    ) -> Result<JudgmentAdjudication, ApplicationError> {
        let judgment = self
            .semantic_tasks
            .get_semantic_judgment(&adjudication.judgment_id)?
            .ok_or(ApplicationError::NotFound("semantic judgment"))?;
        validate_judgment_adjudication(&adjudication, &judgment).map_err(invalid)?;
        self.semantic_tasks
            .save_judgment_adjudication(&adjudication)
    }

    pub fn judgment_adjudications(
        &self,
        judgment_id: &SemanticJudgmentId,
    ) -> Result<Vec<JudgmentAdjudication>, ApplicationError> {
        self.semantic_tasks.list_judgment_adjudications(judgment_id)
    }

    /// Appends a feedback finding against one exact learner-authored writing
    /// revision. It does not modify the response and writes no observation.
    pub fn record_writing_feedback_finding(
        &self,
        finding: WritingFeedbackFinding,
    ) -> Result<WritingFeedbackFinding, ApplicationError> {
        let attempt = self
            .semantic_tasks
            .get_semantic_attempt(&finding.attempt_id)?
            .ok_or(ApplicationError::NotFound("semantic attempt"))?;
        if !matches!(
            attempt.kind,
            SemanticTaskKind::Dictogloss
                | SemanticTaskKind::OneSentenceSummary
                | SemanticTaskKind::Summary
                | SemanticTaskKind::OpinionResponse
        ) {
            return Err(ApplicationError::Invalid(
                "writing feedback requires a writing attempt".into(),
            ));
        }
        let response = attempt
            .responses
            .iter()
            .find(|response| response.revision == finding.response_revision)
            .ok_or(ApplicationError::NotFound("writing response revision"))?;
        validate_writing_feedback_finding(&finding, &response.transcript).map_err(invalid)?;
        if self
            .semantic_tasks
            .get_writing_feedback_finding(&finding.id)?
            .is_some()
        {
            return Err(ApplicationError::Conflict(
                "writing feedback finding already exists",
            ));
        }
        self.semantic_tasks.save_writing_feedback_finding(&finding)
    }

    pub fn writing_feedback_findings(
        &self,
        attempt_id: &SemanticTaskAttemptId,
    ) -> Result<Vec<WritingFeedbackFinding>, ApplicationError> {
        self.semantic_tasks
            .list_writing_feedback_findings(attempt_id)
    }

    pub fn writing_feedback_finding(
        &self,
        id: &WritingFeedbackFindingId,
    ) -> Result<Option<WritingFeedbackFinding>, ApplicationError> {
        self.semantic_tasks.get_writing_feedback_finding(id)
    }

    /// Runs the local Harper adapter only after the learner explicitly asks
    /// for feedback, then appends every bounded finding through the same
    /// validation/persistence path as any other provider.
    pub fn generate_local_writing_findings(
        &self,
        attempt_id: &SemanticTaskAttemptId,
        response_revision: u32,
        created_at_ms: u64,
    ) -> Result<Vec<WritingFeedbackFinding>, ApplicationError> {
        let attempt = self
            .semantic_tasks
            .get_semantic_attempt(attempt_id)?
            .ok_or(ApplicationError::NotFound("semantic attempt"))?;
        let response = attempt
            .responses
            .iter()
            .find(|response| response.revision == response_revision)
            .ok_or(ApplicationError::NotFound("writing response revision"))?;
        let mut saved = Vec::new();
        for finding in writing_feedback::local_findings(
            attempt_id,
            response_revision,
            &response.transcript,
            created_at_ms,
        ) {
            match self.record_writing_feedback_finding(finding) {
                Ok(finding) => saved.push(finding),
                Err(ApplicationError::Conflict(_)) => {}
                Err(error) => return Err(error),
            }
        }
        if saved.is_empty() {
            return self.writing_feedback_findings(attempt_id);
        }
        Ok(saved)
    }

    /// Appends a learner decision. Acceptance must cite a later typed revision;
    /// no code path applies provider text to the authoritative response.
    pub fn record_writing_finding_disposition(
        &self,
        disposition: WritingFindingDisposition,
    ) -> Result<WritingFindingDisposition, ApplicationError> {
        let finding = self
            .semantic_tasks
            .get_writing_feedback_finding(&disposition.finding_id)?
            .ok_or(ApplicationError::NotFound("writing feedback finding"))?;
        validate_writing_finding_disposition(&disposition, &finding).map_err(invalid)?;
        let source_attempt = self
            .semantic_tasks
            .get_semantic_attempt(&finding.attempt_id)?
            .ok_or(ApplicationError::NotFound("semantic attempt"))?;
        if let (Some(resulting_attempt_id), Some(revision)) = (
            disposition.resulting_attempt_id.as_ref(),
            disposition.resulting_response_revision,
        ) {
            if resulting_attempt_id == &finding.attempt_id {
                return Err(ApplicationError::Invalid(
                    "accepted finding must cite a new immutable attempt".into(),
                ));
            }
            let resulting_attempt = self
                .semantic_tasks
                .get_semantic_attempt(resulting_attempt_id)?
                .ok_or(ApplicationError::NotFound("resulting semantic attempt"))?;
            if resulting_attempt.rubric_id != source_attempt.rubric_id
                || resulting_attempt.rubric_version != source_attempt.rubric_version
                || resulting_attempt.kind != source_attempt.kind
            {
                return Err(ApplicationError::Invalid(
                    "resulting attempt must answer the same writing rubric".into(),
                ));
            }
            let preserved_source = resulting_attempt.responses.iter().any(|response| {
                response.revision == finding.response_revision
                    && response.source == domain::ResponseTranscriptSource::Typed
                    && domain::transcript_sha256(&response.transcript)
                        == finding.response_transcript_sha256
            });
            let learner_revision = resulting_attempt.responses.iter().any(|response| {
                response.revision == revision
                    && response.source == domain::ResponseTranscriptSource::Typed
            });
            if !preserved_source || !learner_revision {
                return Err(ApplicationError::Invalid(
                    "accepted finding must preserve the reviewed response and cite a later learner-typed revision".into(),
                ));
            }
        }
        if self
            .semantic_tasks
            .get_writing_finding_disposition(&disposition.id)?
            .is_some()
        {
            return Err(ApplicationError::Conflict(
                "writing finding disposition already exists",
            ));
        }
        self.semantic_tasks
            .save_writing_finding_disposition(&disposition)
    }

    pub fn writing_finding_dispositions(
        &self,
        finding_id: &WritingFeedbackFindingId,
    ) -> Result<Vec<WritingFindingDisposition>, ApplicationError> {
        self.semantic_tasks
            .list_writing_finding_dispositions(finding_id)
    }

    pub fn save_writing_draft(
        &self,
        draft: WritingDraft,
    ) -> Result<WritingDraft, ApplicationError> {
        if draft.transcript.trim().is_empty() || draft.prompt_snapshot.trim().is_empty() {
            return Err(ApplicationError::Invalid(
                "writing draft transcript and prompt must not be empty".into(),
            ));
        }
        if self
            .semantic_tasks
            .latest_semantic_rubric(&draft.rubric_id)?
            .is_none()
        {
            return Err(ApplicationError::NotFound("semantic rubric"));
        }
        self.semantic_tasks.upsert_writing_draft(&draft)
    }

    pub fn writing_draft(
        &self,
        rubric_id: &SemanticRubricId,
    ) -> Result<Option<WritingDraft>, ApplicationError> {
        self.semantic_tasks.get_writing_draft(rubric_id)
    }

    pub fn delete_writing_draft(
        &self,
        rubric_id: &SemanticRubricId,
    ) -> Result<(), ApplicationError> {
        self.semantic_tasks.delete_writing_draft(rubric_id)
    }

    /// Assembles one provider [`JudgmentDraft`] into a fully-identified,
    /// validated [`SemanticJudgment`] and records it. The vendor layer supplies
    /// only content; identity fingerprint, rubric version binding, and the
    /// source/response snapshot hashes are minted here on the server side, so a
    /// provider can never forge identity or bypass the Phase 3.11 validators
    /// (ADR 0021 four-layer separation). The stored judgment is an unqualified
    /// `heuristic_proxy`: it writes no observation and lights up no learning
    /// surface until Phase 3.12.1 grants display qualification.
    pub fn record_llm_judgment(
        &self,
        attempt_id: &SemanticTaskAttemptId,
        response_revision: u32,
        draft: JudgmentDraft,
        created_at_ms: u64,
    ) -> Result<SemanticJudgment, ApplicationError> {
        let attempt = self
            .semantic_tasks
            .get_semantic_attempt(attempt_id)?
            .ok_or(ApplicationError::NotFound("semantic attempt"))?;
        let rubric = self
            .semantic_tasks
            .get_semantic_rubric(&attempt.rubric_id, attempt.rubric_version)?
            .ok_or(ApplicationError::NotFound("semantic rubric"))?;
        let response = attempt
            .responses
            .iter()
            .find(|response| response.revision == response_revision)
            .ok_or(ApplicationError::NotFound("attempt response revision"))?;

        let provenance = SemanticGeneratorProvenance {
            kind: SemanticGeneratorKind::Llm,
            detail: None,
            model_id: draft.model_id,
            prompt_version: draft.prompt_version,
            schema_version: draft.schema_version,
        };
        let id = semantic_judgment_id(
            attempt_id,
            response_revision,
            attempt.rubric_version,
            SemanticGeneratorKind::Llm,
            created_at_ms,
        );
        let judgment = SemanticJudgment {
            id,
            attempt_id: attempt_id.clone(),
            response_revision,
            rubric_id: attempt.rubric_id.clone(),
            rubric_version: attempt.rubric_version,
            rubric_source_sha256: transcript_sha256(&rubric.source.transcript_snapshot),
            response_transcript_sha256: transcript_sha256(&response.transcript),
            points: draft.points,
            abstain: draft.abstain,
            provenance,
            raw_output: draft.raw_output,
            evidence_class: LLM_JUDGMENT_EVIDENCE_CLASS.to_string(),
            created_at_ms,
        };
        // Reuses the Phase 3.11 validator + conflict + append-only persistence.
        self.record_semantic_judgment(judgment)
    }

    /// Orchestrates one judgment: build the neutral request from the stored
    /// attempt/rubric, call the vendor provider, and record the result.
    ///
    /// Honest degradation is structural: on any [`LlmProviderError`] (offline,
    /// auth, refusal, truncated, schema-invalid, ...) the provider returns
    /// `Err` before a draft exists, so this method propagates the error and
    /// **writes no judgment** — a cut-off or refused answer never becomes a
    /// stored verdict (final §7.4).
    pub async fn judge_semantic_attempt(
        &self,
        attempt_id: &SemanticTaskAttemptId,
        response_revision: u32,
        provider: &dyn SemanticJudgeProvider,
        created_at_ms: u64,
    ) -> Result<SemanticJudgment, ApplicationError> {
        let attempt = self
            .semantic_tasks
            .get_semantic_attempt(attempt_id)?
            .ok_or(ApplicationError::NotFound("semantic attempt"))?;
        let rubric = self
            .semantic_tasks
            .get_semantic_rubric(&attempt.rubric_id, attempt.rubric_version)?
            .ok_or(ApplicationError::NotFound("semantic rubric"))?;
        let response = attempt
            .responses
            .iter()
            .find(|response| response.revision == response_revision)
            .ok_or(ApplicationError::NotFound("attempt response revision"))?;

        let request = JudgeRequest {
            rubric,
            response_transcript: response.transcript.clone(),
            response_language: response.language.clone(),
            asr_reliability: response.asr_reliability,
        };
        let draft = provider.judge(&request).await?;
        self.record_llm_judgment(attempt_id, response_revision, draft, created_at_ms)
    }
}
