//! Writing-specific feedback facts for Phase 3.15.
//!
//! A finding points at an immutable learner revision. A disposition records a
//! later user decision. Neither type contains mutable editor text, and neither
//! can manufacture a learner revision or a writing capability observation.

use serde::{Deserialize, Serialize};

use crate::{
    SemanticRubricId, SemanticTaskAttemptId, WritingFeedbackFindingId, WritingFindingDispositionId,
    transcript_sha256,
};

/// Mutable crash-recovery projection for text that has not been submitted.
/// It is outside the evidence chain and is deleted after immutable submission.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WritingDraft {
    pub rubric_id: SemanticRubricId,
    pub prompt_snapshot: String,
    pub transcript: String,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WritingFeedbackLayer {
    TaskCompletion,
    InformationCoverage,
    Organization,
    Cohesion,
    WordChoice,
    Grammar,
    Spelling,
    Punctuation,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WritingFindingSeverity {
    Notice,
    Suggestion,
    Important,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WritingFeedbackGenerator {
    LocalRule,
    Llm,
    Manual,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WritingFeedbackProvenance {
    pub generator: WritingFeedbackGenerator,
    pub provider_id: String,
    pub provider_version: String,
    pub ruleset_version: Option<String>,
    /// Orthogonal evidence class (`heuristic_proxy`, `manual_product_qa`, ...).
    pub evidence_class: String,
}

/// Half-open Unicode-scalar range over the learner revision. Character spans
/// deliberately match the Phase 3.11 judgment citation convention.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct WritingSourceSpan {
    pub start_char: u32,
    pub end_char: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WritingFeedbackFinding {
    pub id: WritingFeedbackFindingId,
    pub attempt_id: SemanticTaskAttemptId,
    pub response_revision: u32,
    pub response_transcript_sha256: String,
    pub layer: WritingFeedbackLayer,
    pub severity: WritingFindingSeverity,
    pub source_span: Option<WritingSourceSpan>,
    pub message: String,
    /// A proposal only. It is never learner text until the learner submits a
    /// later revision and an accepted disposition points to that revision.
    pub suggested_replacement: Option<String>,
    pub provenance: WritingFeedbackProvenance,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WritingFindingDecision {
    Accepted,
    Rejected,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WritingFindingDisposition {
    pub id: WritingFindingDispositionId,
    pub finding_id: WritingFeedbackFindingId,
    pub decision: WritingFindingDecision,
    /// Acceptance points at a new immutable attempt that preserves the source
    /// response and adds a later learner-authored revision.
    pub resulting_attempt_id: Option<SemanticTaskAttemptId>,
    pub resulting_response_revision: Option<u32>,
    pub note: Option<String>,
    pub occurred_at_ms: u64,
}

pub fn writing_feedback_finding_id(
    attempt_id: &SemanticTaskAttemptId,
    response_revision: u32,
    response_transcript: &str,
    layer: WritingFeedbackLayer,
    source_span: Option<WritingSourceSpan>,
    message: &str,
    provenance: &WritingFeedbackProvenance,
) -> WritingFeedbackFindingId {
    WritingFeedbackFindingId::from_fingerprint(
        "writing-feedback-finding",
        &format!(
            "{}:{response_revision}:{}:{}:{}:{}:{}:{}:{}",
            attempt_id.as_str(),
            transcript_sha256(response_transcript),
            serde_json::to_string(&layer).expect("layer serializes"),
            source_span.map(|span| span.start_char).unwrap_or(0),
            source_span.map(|span| span.end_char).unwrap_or(0),
            transcript_sha256(message),
            provenance.provider_id,
            provenance.provider_version,
        ),
    )
}

pub fn writing_finding_disposition_id(
    finding_id: &WritingFeedbackFindingId,
    decision: WritingFindingDecision,
    resulting_attempt_id: Option<&SemanticTaskAttemptId>,
    resulting_response_revision: Option<u32>,
    occurred_at_ms: u64,
) -> WritingFindingDispositionId {
    WritingFindingDispositionId::from_fingerprint(
        "writing-finding-disposition",
        &format!(
            "{}:{}:{}:{}:{occurred_at_ms}",
            finding_id.as_str(),
            serde_json::to_string(&decision).expect("decision serializes"),
            resulting_attempt_id
                .map(SemanticTaskAttemptId::as_str)
                .unwrap_or(""),
            resulting_response_revision.unwrap_or(0),
        ),
    )
}

pub fn validate_writing_feedback_finding(
    finding: &WritingFeedbackFinding,
    response_transcript: &str,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if finding.response_revision == 0 {
        errors.push("finding response revision must be >= 1".into());
    }
    if finding.response_transcript_sha256 != transcript_sha256(response_transcript) {
        errors.push("finding response hash does not match the learner revision".into());
    }
    if finding.message.trim().is_empty() {
        errors.push("finding message must not be empty".into());
    }
    if finding.provenance.provider_id.trim().is_empty()
        || finding.provenance.provider_version.trim().is_empty()
        || finding.provenance.evidence_class.trim().is_empty()
    {
        errors.push("finding provider/version/evidence provenance must be complete".into());
    }
    if let Some(span) = finding.source_span {
        let char_count = response_transcript.chars().count() as u32;
        if span.start_char >= span.end_char || span.end_char > char_count {
            errors.push("finding source span is outside the learner revision".into());
        }
    }
    if finding
        .suggested_replacement
        .as_deref()
        .is_some_and(|replacement| replacement.trim().is_empty())
    {
        errors.push("suggested replacement must be absent or non-empty".into());
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

pub fn validate_writing_finding_disposition(
    disposition: &WritingFindingDisposition,
    finding: &WritingFeedbackFinding,
) -> Result<(), Vec<String>> {
    let mut errors = Vec::new();
    if disposition.finding_id != finding.id {
        errors.push("disposition must reference its finding".into());
    }
    match (
        disposition.decision,
        disposition.resulting_attempt_id.as_ref(),
        disposition.resulting_response_revision,
    ) {
        (WritingFindingDecision::Accepted, Some(_), Some(revision))
            if revision > finding.response_revision => {}
        (WritingFindingDecision::Accepted, _, _) => {
            errors.push("acceptance must cite a new attempt and later learner revision".into());
        }
        (WritingFindingDecision::Rejected, None, None) => {}
        (WritingFindingDecision::Rejected, _, _) => {
            errors.push("rejection must not claim a resulting attempt or revision".into());
        }
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn finding() -> WritingFeedbackFinding {
        let attempt_id = SemanticTaskAttemptId::parse("writing-attempt").unwrap();
        let text = "This is an useful idea.";
        let provenance = WritingFeedbackProvenance {
            generator: WritingFeedbackGenerator::LocalRule,
            provider_id: "harper".into(),
            provider_version: "0.40.0".into(),
            ruleset_version: Some("curated-american".into()),
            evidence_class: "heuristic_proxy".into(),
        };
        WritingFeedbackFinding {
            id: writing_feedback_finding_id(
                &attempt_id,
                1,
                text,
                WritingFeedbackLayer::Grammar,
                Some(WritingSourceSpan {
                    start_char: 8,
                    end_char: 10,
                }),
                "Use ‘a’ before a consonant sound.",
                &provenance,
            ),
            attempt_id,
            response_revision: 1,
            response_transcript_sha256: transcript_sha256(text),
            layer: WritingFeedbackLayer::Grammar,
            severity: WritingFindingSeverity::Suggestion,
            source_span: Some(WritingSourceSpan {
                start_char: 8,
                end_char: 10,
            }),
            message: "Use ‘a’ before a consonant sound.".into(),
            suggested_replacement: Some("a".into()),
            provenance,
            created_at_ms: 100,
        }
    }

    #[test]
    fn finding_is_bound_to_exact_learner_revision() {
        let finding = finding();
        validate_writing_feedback_finding(&finding, "This is an useful idea.").unwrap();
        assert!(validate_writing_feedback_finding(&finding, "This is a useful idea.").is_err());
    }

    #[test]
    fn acceptance_requires_a_later_learner_revision() {
        let finding = finding();
        let accepted = WritingFindingDisposition {
            id: writing_finding_disposition_id(
                &finding.id,
                WritingFindingDecision::Accepted,
                Some(&finding.attempt_id),
                Some(2),
                200,
            ),
            finding_id: finding.id.clone(),
            decision: WritingFindingDecision::Accepted,
            resulting_attempt_id: Some(finding.attempt_id.clone()),
            resulting_response_revision: Some(2),
            note: None,
            occurred_at_ms: 200,
        };
        validate_writing_finding_disposition(&accepted, &finding).unwrap();

        let mut silent_rewrite = accepted;
        silent_rewrite.resulting_response_revision = None;
        assert!(validate_writing_finding_disposition(&silent_rewrite, &finding).is_err());
    }

    #[test]
    fn rejection_cannot_manufacture_a_revision() {
        let finding = finding();
        let rejected = WritingFindingDisposition {
            id: writing_finding_disposition_id(
                &finding.id,
                WritingFindingDecision::Rejected,
                None,
                None,
                200,
            ),
            finding_id: finding.id.clone(),
            decision: WritingFindingDecision::Rejected,
            resulting_attempt_id: None,
            resulting_response_revision: None,
            note: Some("I meant this phrasing.".into()),
            occurred_at_ms: 200,
        };
        validate_writing_finding_disposition(&rejected, &finding).unwrap();
    }
}
