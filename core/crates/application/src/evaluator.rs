//! Deterministic practice-answer sequence alignment (issue #98 baseline).
//!
//! The evaluator is deliberately narrower than the semantic-task judgment
//! system: it aligns bounded text answers and may accept provider-backed lemma
//! equivalence for selected practice kinds. Open-ended rubric/LLM evaluation
//! remains a separate follow-up under issue #98.

use std::sync::Arc;

use domain::{
    LanguageCode, PracticeEvaluation, PracticeKind, PracticeResult, PracticeTokenEvaluation,
    PracticeTokenResult, SubtitleTokenKind,
};

use crate::{ApplicationError, LexicalNormalizationProvider};

const EVALUATOR_VERSION: &str = "practice-answer-alignment-v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EquivalencePolicy {
    SurfaceOnly,
    Lemma,
}

/// Per-kind policy for the deterministic baseline.
///
/// This is a `heuristic_proxy`, not a semantic assessment: dictation preserves
/// surface-form strictness, while the existing fill/reproduction tasks may use
/// an installed lexical provider to recognize lemma-equivalent word forms.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct EvaluationStrategy {
    equivalence_policy: EquivalencePolicy,
}

impl EvaluationStrategy {
    pub fn for_kind(kind: PracticeKind) -> Self {
        let equivalence_policy = match kind {
            PracticeKind::Dictation => EquivalencePolicy::SurfaceOnly,
            PracticeKind::Cloze | PracticeKind::SubtitleFade | PracticeKind::Shadowing => {
                EquivalencePolicy::Lemma
            }
        };
        Self { equivalence_policy }
    }
}

#[derive(Clone)]
pub struct PracticeAnswerEvaluator {
    normalizers: Arc<Vec<Arc<dyn LexicalNormalizationProvider>>>,
    language: LanguageCode,
}

impl PracticeAnswerEvaluator {
    pub fn new(
        normalizers: Arc<Vec<Arc<dyn LexicalNormalizationProvider>>>,
        language: LanguageCode,
    ) -> Self {
        Self {
            normalizers,
            language,
        }
    }

    pub fn evaluate(
        &self,
        kind: PracticeKind,
        expected: &str,
        actual: &str,
    ) -> Result<PracticeEvaluation, ApplicationError> {
        self.evaluate_with_strategy(EvaluationStrategy::for_kind(kind), expected, actual)
    }

    fn evaluate_with_strategy(
        &self,
        strategy: EvaluationStrategy,
        expected: &str,
        actual: &str,
    ) -> Result<PracticeEvaluation, ApplicationError> {
        let expected_tokens = normalize_answer_tokens(&self.language, expected);
        let actual_tokens = normalize_answer_tokens(&self.language, actual);
        let trace = self.trace(&strategy);

        if expected_tokens.is_empty() && actual_tokens.is_empty() {
            return Ok(PracticeEvaluation {
                summary: "0/0 tokens matched".into(),
                token_results: Vec::new(),
                extra: trace,
            });
        }

        let alignment = if expected_tokens == actual_tokens {
            AlignmentOutput {
                token_results: expected_tokens
                    .iter()
                    .map(|token| PracticeTokenEvaluation {
                        expected: Some(token.clone()),
                        actual: Some(token.clone()),
                        result: PracticeTokenResult::Correct,
                    })
                    .collect(),
                equivalent_matches: Vec::new(),
            }
        } else {
            self.align(&expected_tokens, &actual_tokens, strategy)?
        };
        let correct = alignment
            .token_results
            .iter()
            .filter(|entry| token_result_is_correct(entry.result))
            .count();
        let mut extra = trace;
        extra["expected_token_count"] = expected_tokens.len().into();
        extra["actual_token_count"] = actual_tokens.len().into();
        extra["equivalent_matches"] = serde_json::Value::Array(alignment.equivalent_matches);

        Ok(PracticeEvaluation {
            summary: format!("{correct}/{} tokens matched", expected_tokens.len()),
            token_results: alignment.token_results,
            extra,
        })
    }

    fn trace(&self, strategy: &EvaluationStrategy) -> serde_json::Value {
        let normalizers = self
            .normalizers
            .iter()
            .map(|provider| {
                serde_json::json!({
                    "provider_id": provider.provider_id(),
                    "provider_version": provider.version(),
                })
            })
            .collect::<Vec<_>>();
        serde_json::json!({
            "evaluator_version": EVALUATOR_VERSION,
            "algorithm": "global-edit-distance",
            "evidence_class": "heuristic_proxy",
            "language": self.language.as_str(),
            "equivalence_policy": match strategy.equivalence_policy {
                EquivalencePolicy::SurfaceOnly => "surface_only",
                EquivalencePolicy::Lemma => "lemma",
            },
            "normalizers": normalizers,
            "expected_token_count": 0,
            "actual_token_count": 0,
            "equivalent_matches": [],
        })
    }

    fn align(
        &self,
        expected: &[String],
        actual: &[String],
        strategy: EvaluationStrategy,
    ) -> Result<AlignmentOutput, ApplicationError> {
        let n = expected.len();
        let m = actual.len();
        let provider_normalizations = self.normalize_for_equivalence(expected, actual, strategy)?;
        let mut relations = vec![vec![TokenRelation::Different; m]; n];
        for (i, expected_token) in expected.iter().enumerate() {
            for (j, actual_token) in actual.iter().enumerate() {
                relations[i][j] = Self::token_relation(
                    expected_token,
                    actual_token,
                    i,
                    j,
                    &provider_normalizations,
                );
            }
        }

        // Global edit-distance alignment: match/equivalent costs 0; a
        // substitution, insertion, or deletion costs 1. There are no
        // task-specific numeric thresholds to tune from a tiny fixture set.
        let mut cost = vec![vec![0usize; m + 1]; n + 1];
        for (i, row) in cost.iter_mut().enumerate().skip(1) {
            row[0] = i;
        }
        for (j, cell) in cost[0].iter_mut().enumerate().skip(1) {
            *cell = j;
        }
        for i in 1..=n {
            for j in 1..=m {
                let substitution = cost[i - 1][j - 1]
                    + usize::from(matches!(relations[i - 1][j - 1], TokenRelation::Different));
                let deletion = cost[i - 1][j] + 1;
                let insertion = cost[i][j - 1] + 1;
                cost[i][j] = substitution.min(deletion).min(insertion);
            }
        }

        let mut token_results = Vec::with_capacity(n.max(m));
        let mut equivalent_matches = Vec::new();
        let (mut i, mut j) = (n, m);
        while i > 0 || j > 0 {
            if i > 0 && j > 0 {
                let relation = &relations[i - 1][j - 1];
                let substitution =
                    cost[i - 1][j - 1] + usize::from(matches!(relation, TokenRelation::Different));
                if cost[i][j] == substitution {
                    let result = match relation {
                        TokenRelation::Exact => PracticeTokenResult::Correct,
                        TokenRelation::Equivalent {
                            provider_id,
                            provider_version,
                        } => {
                            equivalent_matches.push(serde_json::json!({
                                "expected": expected[i - 1],
                                "actual": actual[j - 1],
                                "provider_id": provider_id,
                                "provider_version": provider_version,
                            }));
                            PracticeTokenResult::Equivalent
                        }
                        TokenRelation::Different => PracticeTokenResult::Mismatch,
                    };
                    token_results.push(PracticeTokenEvaluation {
                        expected: Some(expected[i - 1].clone()),
                        actual: Some(actual[j - 1].clone()),
                        result,
                    });
                    i -= 1;
                    j -= 1;
                    continue;
                }
            }
            if i > 0 && cost[i][j] == cost[i - 1][j] + 1 {
                token_results.push(PracticeTokenEvaluation {
                    expected: Some(expected[i - 1].clone()),
                    actual: None,
                    result: PracticeTokenResult::Missing,
                });
                i -= 1;
            } else {
                token_results.push(PracticeTokenEvaluation {
                    expected: None,
                    actual: Some(actual[j - 1].clone()),
                    result: PracticeTokenResult::Extra,
                });
                j -= 1;
            }
        }
        token_results.reverse();
        equivalent_matches.reverse();
        Ok(AlignmentOutput {
            token_results,
            equivalent_matches,
        })
    }

    fn normalize_for_equivalence(
        &self,
        expected: &[String],
        actual: &[String],
        strategy: EvaluationStrategy,
    ) -> Result<Vec<ProviderNormalization>, ApplicationError> {
        if strategy.equivalence_policy == EquivalencePolicy::SurfaceOnly {
            return Ok(Vec::new());
        }
        let mut result = Vec::with_capacity(self.normalizers.len());
        for normalizer in self.normalizers.iter() {
            let expected_lemmas = expected
                .iter()
                .map(|token| normalizer.normalize(&self.language, token))
                .collect::<Result<Vec<_>, _>>()?;
            let actual_lemmas = actual
                .iter()
                .map(|token| normalizer.normalize(&self.language, token))
                .collect::<Result<Vec<_>, _>>()?;
            result.push(ProviderNormalization {
                provider_id: normalizer.provider_id().to_owned(),
                provider_version: normalizer.version().to_owned(),
                expected_lemmas,
                actual_lemmas,
            });
        }
        Ok(result)
    }

    fn token_relation(
        expected: &str,
        actual: &str,
        expected_index: usize,
        actual_index: usize,
        normalizations: &[ProviderNormalization],
    ) -> TokenRelation {
        if expected == actual {
            return TokenRelation::Exact;
        }
        for normalization in normalizations {
            let expected_lemma = &normalization.expected_lemmas[expected_index];
            let actual_lemma = &normalization.actual_lemmas[actual_index];
            if expected_lemma.is_some() && expected_lemma == actual_lemma {
                return TokenRelation::Equivalent {
                    provider_id: normalization.provider_id.clone(),
                    provider_version: normalization.provider_version.clone(),
                };
            }
        }
        TokenRelation::Different
    }
}

#[derive(Clone)]
enum TokenRelation {
    Exact,
    Equivalent {
        provider_id: String,
        provider_version: String,
    },
    Different,
}

struct ProviderNormalization {
    provider_id: String,
    provider_version: String,
    expected_lemmas: Vec<Option<String>>,
    actual_lemmas: Vec<Option<String>>,
}

struct AlignmentOutput {
    token_results: Vec<PracticeTokenEvaluation>,
    equivalent_matches: Vec<serde_json::Value>,
}

pub fn normalize_answer_tokens(language: &LanguageCode, value: &str) -> Vec<String> {
    subtitle_core::tokenize(Some(language), value)
        .into_iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .map(|token| token.normalized.unwrap_or(token.text))
        .filter(|token| !token.is_empty())
        .collect()
}

fn token_result_is_correct(result: PracticeTokenResult) -> bool {
    matches!(
        result,
        PracticeTokenResult::Correct | PracticeTokenResult::Equivalent
    )
}

pub fn practice_result(evaluation: &PracticeEvaluation) -> PracticeResult {
    if evaluation.token_results.is_empty() {
        return PracticeResult::Skipped;
    }
    if evaluation
        .token_results
        .iter()
        .all(|value| token_result_is_correct(value.result))
    {
        PracticeResult::Correct
    } else if evaluation
        .token_results
        .iter()
        .any(|value| token_result_is_correct(value.result))
    {
        PracticeResult::Partial
    } else {
        PracticeResult::Incorrect
    }
}

pub fn practice_score(evaluation: &PracticeEvaluation) -> Option<f32> {
    if evaluation.token_results.is_empty() {
        return None;
    }
    let correct = evaluation
        .token_results
        .iter()
        .filter(|value| token_result_is_correct(value.result))
        .count();
    Some(correct as f32 / evaluation.token_results.len() as f32)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::LexicalNormalizationProviderError;
    use domain::SubtitleSentence;

    struct StubNormalizer;

    impl LexicalNormalizationProvider for StubNormalizer {
        fn provider_id(&self) -> &'static str {
            "stub"
        }

        fn version(&self) -> &str {
            "v1"
        }

        fn normalize(
            &self,
            language: &LanguageCode,
            value: &str,
        ) -> Result<Option<String>, LexicalNormalizationProviderError> {
            if language.as_str() != "en" {
                return Ok(None);
            }
            Ok(Some(
                match value {
                    "goes" | "go" => "go",
                    other => other,
                }
                .to_owned(),
            ))
        }

        fn phrase_candidates(
            &self,
            _language: &LanguageCode,
            _sentence: &SubtitleSentence,
        ) -> Result<Vec<domain::PhraseCandidate>, LexicalNormalizationProviderError> {
            Ok(Vec::new())
        }
    }

    struct FailingNormalizer;

    impl LexicalNormalizationProvider for FailingNormalizer {
        fn provider_id(&self) -> &'static str {
            "failing"
        }

        fn version(&self) -> &str {
            "v1"
        }

        fn normalize(
            &self,
            _language: &LanguageCode,
            _value: &str,
        ) -> Result<Option<String>, LexicalNormalizationProviderError> {
            Err(LexicalNormalizationProviderError("fixture failure".into()))
        }

        fn phrase_candidates(
            &self,
            _language: &LanguageCode,
            _sentence: &SubtitleSentence,
        ) -> Result<Vec<domain::PhraseCandidate>, LexicalNormalizationProviderError> {
            Ok(Vec::new())
        }
    }

    fn evaluator() -> PracticeAnswerEvaluator {
        PracticeAnswerEvaluator::new(Arc::new(Vec::new()), language("en"))
    }

    fn language(value: &str) -> LanguageCode {
        LanguageCode::parse(value).unwrap()
    }

    #[test]
    fn exact_match_is_correct() {
        let evaluation = evaluator()
            .evaluate(PracticeKind::Dictation, "I want to go", "I want to go")
            .unwrap();
        assert_eq!(practice_result(&evaluation), PracticeResult::Correct);
        assert_eq!(practice_score(&evaluation), Some(1.0));
    }

    #[test]
    fn deletion_and_insertion_do_not_cascade() {
        let deletion = evaluator()
            .evaluate(PracticeKind::Dictation, "I want to go", "I want go")
            .unwrap();
        assert_eq!(
            deletion
                .token_results
                .iter()
                .map(|token| token.result)
                .collect::<Vec<_>>(),
            vec![
                PracticeTokenResult::Correct,
                PracticeTokenResult::Correct,
                PracticeTokenResult::Missing,
                PracticeTokenResult::Correct,
            ]
        );

        let insertion = evaluator()
            .evaluate(
                PracticeKind::Dictation,
                "I want to go",
                "I really want to go",
            )
            .unwrap();
        assert_eq!(
            insertion
                .token_results
                .iter()
                .filter(|token| token.result == PracticeTokenResult::Extra)
                .count(),
            1
        );
    }

    #[test]
    fn substitution_and_empty_answers_are_explainable() {
        let substitution = evaluator()
            .evaluate(PracticeKind::Dictation, "I want to go", "I want to come")
            .unwrap();
        assert_eq!(
            substitution
                .token_results
                .iter()
                .filter(|token| token.result == PracticeTokenResult::Mismatch)
                .count(),
            1
        );

        let empty = evaluator()
            .evaluate(PracticeKind::Dictation, "", "  ")
            .unwrap();
        assert_eq!(practice_result(&empty), PracticeResult::Skipped);
        assert_eq!(practice_score(&empty), None);
    }

    #[test]
    fn dictation_is_surface_strict_but_cloze_accepts_provider_lemma() {
        let evaluator =
            PracticeAnswerEvaluator::new(Arc::new(vec![Arc::new(StubNormalizer)]), language("en"));
        let dictation = evaluator
            .evaluate(PracticeKind::Dictation, "she goes home", "she go home")
            .unwrap();
        assert_eq!(
            dictation.token_results[1].result,
            PracticeTokenResult::Mismatch
        );

        let cloze = evaluator
            .evaluate(PracticeKind::Cloze, "she goes home", "she go home")
            .unwrap();
        assert_eq!(
            cloze.token_results[1].result,
            PracticeTokenResult::Equivalent
        );
        assert_eq!(practice_result(&cloze), PracticeResult::Correct);
        assert_eq!(cloze.extra["equivalent_matches"][0]["provider_id"], "stub");
        assert_eq!(
            cloze.extra["evaluator_version"],
            "practice-answer-alignment-v1"
        );
    }

    #[test]
    fn configured_normalizer_failure_aborts_instead_of_scoring_the_learner() {
        let evaluator = PracticeAnswerEvaluator::new(
            Arc::new(vec![Arc::new(FailingNormalizer)]),
            language("en"),
        );
        let error = evaluator
            .evaluate(PracticeKind::Cloze, "she goes home", "she go home")
            .unwrap_err();
        assert!(matches!(
            error,
            ApplicationError::LexicalNormalizationProvider(_)
        ));

        let exact = evaluator
            .evaluate(PracticeKind::Cloze, "she goes home", "she goes home")
            .unwrap();
        assert_eq!(practice_result(&exact), PracticeResult::Correct);
    }

    #[test]
    fn language_profile_tokenizer_handles_unspaced_chinese() {
        let tokens = normalize_answer_tokens(&language("zh"), "我想喝咖啡");
        assert!(tokens.len() > 1);
        assert_eq!(tokens.concat(), "我想喝咖啡");
    }

    #[test]
    fn trace_records_language_policy_and_configured_normalizers() {
        let evaluation = evaluator()
            .evaluate(PracticeKind::Dictation, "Hello, world!", "hello world")
            .unwrap();
        assert_eq!(practice_result(&evaluation), PracticeResult::Correct);
        assert_eq!(evaluation.extra["language"], "en");
        assert_eq!(evaluation.extra["equivalence_policy"], "surface_only");
        assert_eq!(evaluation.extra["evidence_class"], "heuristic_proxy");
    }
}
