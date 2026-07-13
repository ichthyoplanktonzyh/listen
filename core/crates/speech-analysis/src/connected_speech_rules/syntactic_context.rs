use domain::{
    SubtitleSentence, SyntacticAnalysis, SyntacticSentenceAnalysis, SyntacticValidationReport,
};

use super::{PhraseContext, RuleWord};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyntacticProviderQualification {
    Qualified,
    Unqualified,
}

/// Optional syntax input for Reference B.
///
/// Structural validation and provider qualification are separate gates. A
/// valid artifact from an unqualified research model is deliberately ignored.
#[derive(Debug, Clone, Copy)]
pub struct ConnectedSpeechContext<'a> {
    analysis: Option<&'a SyntacticAnalysis>,
    validation: Option<&'a SyntacticValidationReport>,
    qualification: SyntacticProviderQualification,
}

impl<'a> ConnectedSpeechContext<'a> {
    pub const fn without_syntax() -> Self {
        Self {
            analysis: None,
            validation: None,
            qualification: SyntacticProviderQualification::Unqualified,
        }
    }

    pub const fn with_syntax(
        analysis: &'a SyntacticAnalysis,
        validation: &'a SyntacticValidationReport,
        qualification: SyntacticProviderQualification,
    ) -> Self {
        Self {
            analysis: Some(analysis),
            validation: Some(validation),
            qualification,
        }
    }

    pub(super) fn active_sentence(
        &self,
        source: &SubtitleSentence,
    ) -> Option<&'a SyntacticSentenceAnalysis> {
        if self.qualification != SyntacticProviderQualification::Qualified
            || !self
                .validation
                .is_some_and(|report| report.is_activatable())
        {
            return None;
        }
        self.analysis?.sentences.iter().find(|sentence| {
            sentence.sentence_id == source.id
                && sentence.source_text == source.display_text
                && sentence.source_char_count == source.display_text.chars().count() as u32
        })
    }

    pub(super) fn artifact_id(&self) -> Option<&str> {
        self.analysis.map(|analysis| analysis.id.as_str())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum PhrasePredictionProvenance {
    TextHeuristic,
    SyntaxModel,
}

impl PhrasePredictionProvenance {
    pub(super) fn evidence_suffix(self, context: &ConnectedSpeechContext<'_>) -> String {
        match self {
            Self::TextHeuristic => "prediction_provenance:text_heuristic".into(),
            Self::SyntaxModel => format!(
                "prediction_provenance:syntax_model; syntactic_artifact:{}",
                context.artifact_id().unwrap_or("unavailable")
            ),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub(super) struct SyntacticPhraseDecision {
    pub(super) allowed: bool,
    pub(super) provenance: PhrasePredictionProvenance,
}

pub(super) fn syntactic_phrase_decision(
    context: PhraseContext,
    words: &[RuleWord],
    pair_index: usize,
    sentence: &SubtitleSentence,
    syntax: &SyntacticSentenceAnalysis,
) -> Option<SyntacticPhraseDecision> {
    // The locked v1 evaluation did not qualify want-to extraction. Keep its
    // existing conservative text gate even when a future qualified artifact is
    // present; enabling it requires a new preregistered evaluation.
    if matches!(
        context,
        PhraseContext::Always | PhraseContext::WantToInfinitive
    ) {
        return None;
    }
    let first = words.get(pair_index)?;
    let second = words.get(pair_index + 1)?;
    let complement = words.get(pair_index + 2)?;
    if super::context::has_punctuation_boundary(
        sentence,
        second.token_index,
        complement.token_index,
    ) {
        return Some(decision(false));
    }
    let first_syntax = syntax_token_for_word(syntax, first.token_index)?;
    let complement_syntax = syntax_token_for_word(syntax, complement.token_index)?;

    let allowed = match context {
        PhraseContext::GoingToInfinitive => is_verb(complement_syntax),
        PhraseContext::UsedToInfinitive => {
            let previous_is_state_copula = pair_index
                .checked_sub(1)
                .and_then(|index| words.get(index))
                .and_then(|word| syntax_token_for_word(syntax, word.token_index))
                .is_some_and(|token| matches!(token.lemma.as_str(), "be" | "get"));
            !previous_is_state_copula
                && is_verb(complement_syntax)
                && complement_syntax
                    .features
                    .get("VerbForm")
                    .map(String::as_str)
                    != Some("Ger")
        }
        PhraseContext::FollowedByLikelyVerb => {
            let following = words
                .get(pair_index + 3)
                .and_then(|word| syntax_token_for_word(syntax, word.token_index));
            let is_have_to_do_with = first_syntax.lemma == "have"
                && complement_syntax.lemma == "do"
                && following.is_some_and(|token| token.lemma == "with");
            is_verb(complement_syntax) && !is_have_to_do_with
        }
        PhraseContext::Always | PhraseContext::WantToInfinitive => return None,
    };
    Some(decision(allowed))
}

fn syntax_token_for_word(
    syntax: &SyntacticSentenceAnalysis,
    subtitle_token_index: u32,
) -> Option<&domain::SyntacticToken> {
    let mut matches = syntax
        .tokens
        .iter()
        .filter(|token| token.subtitle_token_indices.contains(&subtitle_token_index));
    let first = matches.next()?;
    matches.next().is_none().then_some(first)
}

fn is_verb(token: &domain::SyntacticToken) -> bool {
    matches!(token.upos.as_str(), "VERB" | "AUX")
}

fn decision(allowed: bool) -> SyntacticPhraseDecision {
    SyntacticPhraseDecision {
        allowed,
        provenance: PhrasePredictionProvenance::SyntaxModel,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use domain::{
        LanguageCode, SYNTACTIC_CONTRACT_VERSION, SubtitleSentenceId, SyntacticAlignmentStatus,
        SyntacticAnalysisId, SyntacticProviderDescriptor, SyntacticToken,
        SyntacticValidationStatus, TimeMs,
    };

    use super::*;
    use crate::connected_speech_rules::{
        predict_default_connected, predict_default_connected_with_context,
    };

    fn sentence(text: &str) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("syntax-b").unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1000),
            original_text: text.into(),
            display_text: text.into(),
            tokens: subtitle_core::tokenize_english(text),
        }
    }

    fn analysis(
        sentence: &SubtitleSentence,
        annotations: &[(&str, &str, Option<(&str, &str)>)],
    ) -> SyntacticAnalysis {
        let words = sentence
            .tokens
            .iter()
            .filter(|token| token.kind == domain::SubtitleTokenKind::Word)
            .collect::<Vec<_>>();
        assert_eq!(words.len(), annotations.len());
        let tokens = words
            .iter()
            .zip(annotations)
            .enumerate()
            .map(|(index, (source, (lemma, upos, feature)))| {
                let mut features = BTreeMap::new();
                if let Some((key, value)) = feature {
                    features.insert((*key).into(), (*value).into());
                }
                SyntacticToken {
                    parser_token_index: index as u32,
                    surface: source.text.clone(),
                    lemma: (*lemma).into(),
                    upos: (*upos).into(),
                    xpos: None,
                    features,
                    head_parser_token_index: (index != 0).then_some(0),
                    dependency_relation: if index == 0 { "root" } else { "dep" }.into(),
                    start_char: source.start_char,
                    end_char: source.end_char,
                    subtitle_token_indices: vec![source.index],
                    alignment_status: SyntacticAlignmentStatus::Exact,
                    confidence: None,
                }
            })
            .collect();
        SyntacticAnalysis {
            id: SyntacticAnalysisId::parse("qualified-synthetic-artifact").unwrap(),
            contract_version: SYNTACTIC_CONTRACT_VERSION,
            descriptor: SyntacticProviderDescriptor {
                provider_id: "neutral-qualified-fixture".into(),
                provider_version: "1".into(),
                runtime_id: "fixture".into(),
                runtime_version: "1".into(),
                model_id: "fixture".into(),
                model_version: "1".into(),
                model_checksum_sha256: "a".repeat(64),
            },
            language: LanguageCode::parse("en").unwrap(),
            source_fingerprint: "fixture".into(),
            profile_fingerprint: "fixture".into(),
            sentences: vec![SyntacticSentenceAnalysis {
                sentence_id: sentence.id.clone(),
                source_text: sentence.display_text.clone(),
                source_char_count: sentence.display_text.chars().count() as u32,
                tokens,
                unaligned_subtitle_token_indices: Vec::new(),
                lexical_alignment_coverage: 1.0,
            }],
        }
    }

    fn valid_report() -> SyntacticValidationReport {
        SyntacticValidationReport {
            status: SyntacticValidationStatus::Valid,
            lexical_alignment_coverage: 1.0,
            punctuation_alignment_coverage: 1.0,
            issues: Vec::new(),
        }
    }

    #[test]
    fn qualified_syntax_blocks_lowercase_motion_that_heuristic_allows() {
        let source = sentence("we are going to brooklyn");
        assert!(
            predict_default_connected(&source)
                .iter()
                .any(|value| value.evidence.contains("informal-going-to"))
        );
        let syntax = analysis(
            &source,
            &[
                ("we", "PRON", None),
                ("be", "AUX", None),
                ("go", "VERB", None),
                ("to", "ADP", None),
                ("brooklyn", "PROPN", None),
            ],
        );
        let report = valid_report();
        let context = ConnectedSpeechContext::with_syntax(
            &syntax,
            &report,
            SyntacticProviderQualification::Qualified,
        );
        assert!(
            !predict_default_connected_with_context(&source, &context)
                .iter()
                .any(|value| value.evidence.contains("informal-going-to"))
        );
    }

    #[test]
    fn qualified_future_uses_syntax_provenance_without_becoming_audio_evidence() {
        let source = sentence("we are going to announce");
        let syntax = analysis(
            &source,
            &[
                ("we", "PRON", None),
                ("be", "AUX", None),
                ("go", "VERB", None),
                ("to", "PART", None),
                ("announce", "VERB", Some(("VerbForm", "Inf"))),
            ],
        );
        let report = valid_report();
        let values = predict_default_connected_with_context(
            &source,
            &ConnectedSpeechContext::with_syntax(
                &syntax,
                &report,
                SyntacticProviderQualification::Qualified,
            ),
        );
        let future = values
            .iter()
            .find(|value| value.evidence.contains("informal-going-to"))
            .unwrap();
        assert!(
            future
                .evidence
                .contains("prediction_provenance:syntax_model")
        );
        assert!(future.evidence.contains("qualified-synthetic-artifact"));
        assert_eq!(
            future.status,
            domain::ConnectedSpeechExplanationStatus::PossibleByRule
        );
    }

    #[test]
    fn unqualified_artifact_is_exact_fallback() {
        let source = sentence("we are going to announce");
        let syntax = analysis(
            &source,
            &[
                ("we", "PRON", None),
                ("be", "AUX", None),
                ("go", "VERB", None),
                ("to", "PART", None),
                ("announce", "VERB", None),
            ],
        );
        let report = valid_report();
        assert_eq!(
            predict_default_connected(&source),
            predict_default_connected_with_context(
                &source,
                &ConnectedSpeechContext::with_syntax(
                    &syntax,
                    &report,
                    SyntacticProviderQualification::Unqualified,
                ),
            )
        );
    }

    #[test]
    fn syntax_blocks_get_used_to_state_and_have_to_do_with_idiom() {
        let state = sentence("she gets used to working");
        let state_syntax = analysis(
            &state,
            &[
                ("she", "PRON", None),
                ("get", "VERB", None),
                ("use", "ADJ", None),
                ("to", "ADP", None),
                ("work", "VERB", Some(("VerbForm", "Ger"))),
            ],
        );
        let report = valid_report();
        assert!(
            !predict_default_connected_with_context(
                &state,
                &ConnectedSpeechContext::with_syntax(
                    &state_syntax,
                    &report,
                    SyntacticProviderQualification::Qualified,
                ),
            )
            .iter()
            .any(|value| value.evidence.contains("habitual-used-to"))
        );

        let idiom = sentence("literacy has to do with reading");
        let idiom_syntax = analysis(
            &idiom,
            &[
                ("literacy", "NOUN", None),
                ("have", "VERB", None),
                ("to", "PART", None),
                ("do", "VERB", Some(("VerbForm", "Inf"))),
                ("with", "ADP", None),
                ("read", "VERB", Some(("VerbForm", "Ger"))),
            ],
        );
        assert!(
            !predict_default_connected_with_context(
                &idiom,
                &ConnectedSpeechContext::with_syntax(
                    &idiom_syntax,
                    &report,
                    SyntacticProviderQualification::Qualified,
                ),
            )
            .iter()
            .any(|value| value.evidence.contains("obligation-has-to"))
        );
    }

    #[test]
    fn want_to_remains_text_heuristic_after_failed_locked_gate() {
        let source = sentence("I want to leave");
        let syntax = analysis(
            &source,
            &[
                ("I", "PRON", None),
                ("want", "VERB", None),
                ("to", "PART", None),
                ("leave", "VERB", Some(("VerbForm", "Inf"))),
            ],
        );
        let report = valid_report();
        let values = predict_default_connected_with_context(
            &source,
            &ConnectedSpeechContext::with_syntax(
                &syntax,
                &report,
                SyntacticProviderQualification::Qualified,
            ),
        );
        let want = values
            .iter()
            .find(|value| value.evidence.contains("informal-want-to"))
            .unwrap();
        assert!(
            want.evidence
                .contains("prediction_provenance:text_heuristic")
        );
    }
}
