//! Local, offline grammar/spelling findings for Writing Studio.
//! Harper types stop at this boundary; callers receive project domain facts.

use domain::{
    SemanticTaskAttemptId, WritingFeedbackFinding, WritingFeedbackGenerator, WritingFeedbackLayer,
    WritingFeedbackProvenance, WritingFindingSeverity, WritingSourceSpan, transcript_sha256,
    writing_feedback_finding_id,
};
use harper_core::{
    Dialect, Document,
    linting::{LintGroup, LintKind, Linter, Suggestion},
    parsers::PlainEnglish,
    spell::FstDictionary,
};

pub const PROVIDER_ID: &str = "harper";
pub const PROVIDER_VERSION: &str = "0.40.0";
pub const RULESET_VERSION: &str = "curated-american";

pub fn local_findings(
    attempt_id: &SemanticTaskAttemptId,
    response_revision: u32,
    text: &str,
    created_at_ms: u64,
) -> Vec<WritingFeedbackFinding> {
    let document = Document::new_curated(text, &PlainEnglish);
    let mut linter = LintGroup::new_curated(FstDictionary::curated(), Dialect::American);
    let provenance = WritingFeedbackProvenance {
        generator: WritingFeedbackGenerator::LocalRule,
        provider_id: PROVIDER_ID.into(),
        provider_version: PROVIDER_VERSION.into(),
        ruleset_version: Some(RULESET_VERSION.into()),
        evidence_class: "heuristic_proxy".into(),
    };
    linter
        .lint(&document)
        .into_iter()
        .take(8)
        .map(|lint| {
            let span = WritingSourceSpan {
                start_char: lint.span.start as u32,
                end_char: lint.span.end as u32,
            };
            let replacement = lint
                .suggestions
                .first()
                .and_then(|suggestion| match suggestion {
                    Suggestion::ReplaceWith(chars) | Suggestion::InsertAfter(chars) => {
                        Some(chars.iter().collect())
                    }
                    // An absent replacement is an explicit remove proposal. Domain
                    // validation reserves empty strings for invalid provider data.
                    Suggestion::Remove => None,
                });
            let layer = match lint.lint_kind {
                LintKind::Spelling => WritingFeedbackLayer::Spelling,
                LintKind::Punctuation | LintKind::Formatting => WritingFeedbackLayer::Punctuation,
                LintKind::WordChoice => WritingFeedbackLayer::WordChoice,
                _ => WritingFeedbackLayer::Grammar,
            };
            let id = writing_feedback_finding_id(
                attempt_id,
                response_revision,
                text,
                layer,
                Some(span),
                &lint.message,
                &provenance,
            );
            WritingFeedbackFinding {
                id,
                attempt_id: attempt_id.clone(),
                response_revision,
                response_transcript_sha256: transcript_sha256(text),
                layer,
                severity: if lint.priority <= 31 {
                    WritingFindingSeverity::Important
                } else {
                    WritingFindingSeverity::Suggestion
                },
                source_span: Some(span),
                message: lint.message,
                suggested_replacement: replacement,
                provenance: provenance.clone(),
                created_at_ms,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn harper_findings_are_local_bounded_and_revision_bound() {
        let attempt = SemanticTaskAttemptId::parse("attempt-writing").unwrap();
        let findings = local_findings(&attempt, 1, "This is an useful idea.", 100);
        assert!(!findings.is_empty());
        assert!(findings.len() <= 8);
        assert!(findings.iter().all(|finding| {
            finding.attempt_id == attempt
                && finding.response_revision == 1
                && finding.provenance.generator == WritingFeedbackGenerator::LocalRule
        }));
    }
}
