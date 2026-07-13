//! Phase 3.11 semantic task use cases (ADR 0021).
//!
//! Everything here is clip-level fact recording. No path in this module
//! writes `LearningObservation`, touches capability profiles/overrides, or
//! consumes `PracticeAttempt` results — the four-layer separation is enforced
//! by construction, and the negative tests in persistence-sqlite pin it.

use domain::*;

use crate::{
    AppServices, ApplicationError, JudgeRequest, JudgmentDraft, SemanticJudgeProvider,
};

fn invalid(errors: Vec<String>) -> ApplicationError {
    ApplicationError::Invalid(errors.join("; "))
}

/// AGENT.md evidence class for an unqualified LLM judgment. It is a heuristic
/// proxy until Phase 3.12.1 holdout qualification decides display eligibility;
/// storing it here writes no observation and unlocks no learning surface.
const LLM_JUDGMENT_EVIDENCE_CLASS: &str = "heuristic_proxy";

impl AppServices {
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
