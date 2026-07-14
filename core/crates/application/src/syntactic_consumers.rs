use std::collections::HashMap;
use std::sync::Arc;

use domain::{
    ConnectedSpeechExplanation, PhraseCandidate, SenseGroupSource, SubtitleSentence,
    SubtitleSentenceId, SyntacticAnalysis, SyntacticAnalysisId, SyntacticProviderDescriptor,
    SyntacticValidationReport,
};
use serde::{Deserialize, Serialize};
use speech_analysis::audible_structure::match_dependency_patterns;
use speech_analysis::audible_structure::{
    ConnectedSpeechContext, SyntacticProviderQualification, predict_default_connected,
    predict_default_connected_with_context,
};
use speech_analysis::audible_structure::{
    SenseGroupPartitionConfig, SenseGroupSpan, partition_sentence, partition_sentence_with_syntax,
};

use crate::{
    SyntacticAnalysisDraft, SyntacticAnalysisProvider, SyntacticAnalysisRequest,
    SyntacticCapabilityStatus, finalize_syntactic_analysis,
};

/// Product qualification is capability-specific. It never keys behavior on a
/// provider id, and a future query must be explicitly added rather than
/// inheriting blanket parser trust.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyntacticProductQualification {
    pub artifact: bool,
    pub reference_b_verified_subset: bool,
    pub sense_group: bool,
    pub dependency_matcher: bool,
}

impl SyntacticProductQualification {
    pub const fn corrected_v2() -> Self {
        Self {
            artifact: true,
            reference_b_verified_subset: true,
            sense_group: true,
            dependency_matcher: true,
        }
    }

    pub const fn unqualified() -> Self {
        Self {
            artifact: false,
            reference_b_verified_subset: false,
            sense_group: false,
            dependency_matcher: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyntacticFallbackReason {
    ProviderNotConfigured,
    RuntimeMissing,
    ModelMissing,
    ModelCorrupt,
    UnsupportedLanguage,
    Timeout,
    InvalidOutput,
    ProtocolFailure,
    ProcessFailure,
    ProviderFailure,
    ArtifactUnqualified,
    MissingSentence,
    InvalidSentence,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyntacticPatternNode {
    pub binding: String,
    pub lemma: Option<String>,
    pub upos: Option<String>,
    pub dependency_relation: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyntacticPatternEdge {
    pub head_binding: String,
    pub dependent_binding: String,
    pub dependency_relation: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyntacticDependencyPattern {
    pub matcher_key: String,
    pub nodes: Vec<SyntacticPatternNode>,
    #[serde(default)]
    pub edges: Vec<SyntacticPatternEdge>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SyntacticSenseGroupSpan {
    pub start_token_index: u32,
    pub end_token_index: u32,
    pub sources: Vec<SenseGroupSource>,
    pub confidence: f32,
    pub label: Option<String>,
    pub head_token_index: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub syntactic_analysis_id: Option<SyntacticAnalysisId>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyntacticDependencyMatch {
    pub matcher_version: String,
    pub matcher_key: String,
    pub syntactic_analysis_id: SyntacticAnalysisId,
    pub sentence_id: SubtitleSentenceId,
    pub start_token_index: u32,
    pub end_token_index: u32,
    pub bindings: std::collections::BTreeMap<String, Vec<u32>>,
    pub evidence_class: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SyntacticSentenceConsumers {
    pub sentence_id: SubtitleSentenceId,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub analysis: Option<SyntacticAnalysis>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub validation: Option<SyntacticValidationReport>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fallback_reason: Option<SyntacticFallbackReason>,
    pub reference_b: Vec<ConnectedSpeechExplanation>,
    pub sense_groups: Vec<SyntacticSenseGroupSpan>,
    pub dependency_matches: Vec<SyntacticDependencyMatch>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SyntacticConsumerBatch {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub descriptor: Option<SyntacticProviderDescriptor>,
    pub qualification: SyntacticProductQualification,
    pub probe_request_count: u32,
    pub analysis_request_count: u32,
    pub sentences: Vec<SyntacticSentenceConsumers>,
}

pub struct SyntacticConsumerOrchestrator {
    provider: Option<Arc<dyn SyntacticAnalysisProvider>>,
    qualification: SyntacticProductQualification,
}

impl SyntacticConsumerOrchestrator {
    pub fn new(
        provider: Option<Arc<dyn SyntacticAnalysisProvider>>,
        qualification: SyntacticProductQualification,
    ) -> Self {
        Self {
            provider,
            qualification,
        }
    }

    pub async fn consume(
        &self,
        request: SyntacticAnalysisRequest,
        phrase_candidates: &HashMap<SubtitleSentenceId, Vec<PhraseCandidate>>,
        patterns: &[SyntacticDependencyPattern],
    ) -> SyntacticConsumerBatch {
        let Some(provider) = self.provider.as_deref() else {
            return fallback_batch(
                &request.sentences,
                phrase_candidates,
                self.qualification,
                SyntacticFallbackReason::ProviderNotConfigured,
                0,
                0,
            );
        };
        if !self.qualification.artifact {
            return fallback_batch(
                &request.sentences,
                phrase_candidates,
                self.qualification,
                SyntacticFallbackReason::ArtifactUnqualified,
                0,
                0,
            );
        }
        let capability = match provider.probe(&request.language).await {
            Ok(capability) => capability,
            Err(error) => {
                return fallback_batch(
                    &request.sentences,
                    phrase_candidates,
                    self.qualification,
                    error_fallback(&error),
                    1,
                    0,
                );
            }
        };
        if capability.status != SyntacticCapabilityStatus::Ready {
            return fallback_batch(
                &request.sentences,
                phrase_candidates,
                self.qualification,
                capability_fallback(capability.status),
                1,
                0,
            );
        }
        let draft = match provider.analyze(&request).await {
            Ok(draft) => draft,
            Err(error) => {
                return fallback_batch(
                    &request.sentences,
                    phrase_candidates,
                    self.qualification,
                    error_fallback(&error),
                    1,
                    1,
                );
            }
        };
        let descriptor = Some(draft.descriptor.clone());
        let mut by_sentence = draft
            .sentences
            .into_iter()
            .map(|sentence| (sentence.sentence_id.clone(), sentence))
            .collect::<HashMap<_, _>>();
        let sentences = request
            .sentences
            .iter()
            .map(|source| {
                let Some(sentence_draft) = by_sentence.remove(&source.id) else {
                    return fallback_sentence(
                        source,
                        phrase_candidates,
                        SyntacticFallbackReason::MissingSentence,
                    );
                };
                let sentence_request = SyntacticAnalysisRequest {
                    language: request.language.clone(),
                    sentences: vec![source.clone()],
                    profile_fingerprint: request.profile_fingerprint.clone(),
                };
                let sentence_draft = SyntacticAnalysisDraft {
                    descriptor: draft.descriptor.clone(),
                    sentences: vec![sentence_draft],
                };
                let Ok((analysis, validation)) =
                    finalize_syntactic_analysis(&sentence_request, sentence_draft)
                else {
                    return fallback_sentence(
                        source,
                        phrase_candidates,
                        SyntacticFallbackReason::InvalidSentence,
                    );
                };
                consume_valid_sentence(
                    source,
                    analysis,
                    validation,
                    phrase_candidates,
                    patterns,
                    self.qualification,
                )
            })
            .collect();
        SyntacticConsumerBatch {
            descriptor,
            qualification: self.qualification,
            probe_request_count: 1,
            analysis_request_count: 1,
            sentences,
        }
    }
}

fn consume_valid_sentence(
    source: &SubtitleSentence,
    analysis: SyntacticAnalysis,
    validation: SyntacticValidationReport,
    phrase_candidates: &HashMap<SubtitleSentenceId, Vec<PhraseCandidate>>,
    patterns: &[SyntacticDependencyPattern],
    qualification: SyntacticProductQualification,
) -> SyntacticSentenceConsumers {
    let phrases = phrase_candidates
        .get(&source.id)
        .map(Vec::as_slice)
        .unwrap_or_default();
    let syntax_qualification = SyntacticProviderQualification::Qualified;
    let reference_b = if qualification.reference_b_verified_subset {
        predict_default_connected_with_context(
            source,
            &ConnectedSpeechContext::with_syntax(&analysis, &validation, syntax_qualification),
        )
    } else {
        predict_default_connected(source)
    };
    let syntax_sentence = &analysis.sentences[0];
    let sense_groups = if qualification.sense_group {
        partition_sentence_with_syntax(
            source,
            phrases,
            &SenseGroupPartitionConfig::default(),
            syntax_sentence,
        )
    } else {
        partition_sentence(source, phrases, &SenseGroupPartitionConfig::default())
    }
    .into_iter()
    .map(|span| {
        SyntacticSenseGroupSpan::from_syntax(
            span,
            qualification.sense_group.then_some(&analysis.id),
        )
    })
    .collect();
    let dependency_matches = if qualification.dependency_matcher {
        let algorithm_patterns = patterns
            .iter()
            .map(speech_analysis::audible_structure::DependencyPatternSpec::from)
            .collect::<Vec<_>>();
        match_dependency_patterns(
            &analysis,
            &validation,
            syntax_qualification,
            &algorithm_patterns,
        )
        .into_iter()
        .map(SyntacticDependencyMatch::from)
        .collect()
    } else {
        Vec::new()
    };
    SyntacticSentenceConsumers {
        sentence_id: source.id.clone(),
        analysis: Some(analysis),
        validation: Some(validation),
        fallback_reason: None,
        reference_b,
        sense_groups,
        dependency_matches,
    }
}

fn fallback_batch(
    sentences: &[SubtitleSentence],
    phrase_candidates: &HashMap<SubtitleSentenceId, Vec<PhraseCandidate>>,
    qualification: SyntacticProductQualification,
    reason: SyntacticFallbackReason,
    probe_request_count: u32,
    analysis_request_count: u32,
) -> SyntacticConsumerBatch {
    SyntacticConsumerBatch {
        descriptor: None,
        qualification,
        probe_request_count,
        analysis_request_count,
        sentences: sentences
            .iter()
            .map(|sentence| fallback_sentence(sentence, phrase_candidates, reason.clone()))
            .collect(),
    }
}

fn fallback_sentence(
    sentence: &SubtitleSentence,
    phrase_candidates: &HashMap<SubtitleSentenceId, Vec<PhraseCandidate>>,
    reason: SyntacticFallbackReason,
) -> SyntacticSentenceConsumers {
    let phrases = phrase_candidates
        .get(&sentence.id)
        .map(Vec::as_slice)
        .unwrap_or_default();
    SyntacticSentenceConsumers {
        sentence_id: sentence.id.clone(),
        analysis: None,
        validation: None,
        fallback_reason: Some(reason),
        reference_b: predict_default_connected(sentence),
        sense_groups: partition_sentence(sentence, phrases, &SenseGroupPartitionConfig::default())
            .into_iter()
            .map(SyntacticSenseGroupSpan::from)
            .collect(),
        dependency_matches: Vec::new(),
    }
}

fn capability_fallback(status: SyntacticCapabilityStatus) -> SyntacticFallbackReason {
    match status {
        SyntacticCapabilityStatus::Ready => SyntacticFallbackReason::ProviderFailure,
        SyntacticCapabilityStatus::RuntimeMissing => SyntacticFallbackReason::RuntimeMissing,
        SyntacticCapabilityStatus::ModelMissing => SyntacticFallbackReason::ModelMissing,
        SyntacticCapabilityStatus::ModelCorrupt => SyntacticFallbackReason::ModelCorrupt,
        SyntacticCapabilityStatus::UnsupportedLanguage => {
            SyntacticFallbackReason::UnsupportedLanguage
        }
    }
}

fn error_fallback(error: &domain::SyntacticProviderError) -> SyntacticFallbackReason {
    match error {
        domain::SyntacticProviderError::RuntimeMissing => SyntacticFallbackReason::RuntimeMissing,
        domain::SyntacticProviderError::ModelMissing => SyntacticFallbackReason::ModelMissing,
        domain::SyntacticProviderError::ModelCorrupt => SyntacticFallbackReason::ModelCorrupt,
        domain::SyntacticProviderError::UnsupportedLanguage { .. } => {
            SyntacticFallbackReason::UnsupportedLanguage
        }
        domain::SyntacticProviderError::Timeout => SyntacticFallbackReason::Timeout,
        domain::SyntacticProviderError::InvalidOutput { .. } => {
            SyntacticFallbackReason::InvalidOutput
        }
        domain::SyntacticProviderError::Protocol { .. } => SyntacticFallbackReason::ProtocolFailure,
        domain::SyntacticProviderError::Process { .. } => SyntacticFallbackReason::ProcessFailure,
    }
}

impl From<SenseGroupSpan> for SyntacticSenseGroupSpan {
    fn from(value: SenseGroupSpan) -> Self {
        Self {
            start_token_index: value.start_token_index,
            end_token_index: value.end_token_index,
            sources: value.sources,
            confidence: value.confidence,
            label: value.label,
            head_token_index: value.head_token_index,
            syntactic_analysis_id: None,
        }
    }
}

impl SyntacticSenseGroupSpan {
    fn from_syntax(value: SenseGroupSpan, analysis_id: Option<&SyntacticAnalysisId>) -> Self {
        let mut span = Self::from(value);
        span.syntactic_analysis_id = analysis_id.cloned();
        span
    }
}

impl From<&SyntacticDependencyPattern>
    for speech_analysis::audible_structure::DependencyPatternSpec
{
    fn from(value: &SyntacticDependencyPattern) -> Self {
        Self {
            matcher_key: value.matcher_key.clone(),
            nodes: value
                .nodes
                .iter()
                .map(
                    |node| speech_analysis::audible_structure::DependencyNodeConstraint {
                        binding: node.binding.clone(),
                        lemma: node.lemma.clone(),
                        upos: node.upos.clone(),
                        dependency_relation: node.dependency_relation.clone(),
                    },
                )
                .collect(),
            edges: value
                .edges
                .iter()
                .map(
                    |edge| speech_analysis::audible_structure::DependencyEdgeConstraint {
                        head_binding: edge.head_binding.clone(),
                        dependent_binding: edge.dependent_binding.clone(),
                        dependency_relation: edge.dependency_relation.clone(),
                    },
                )
                .collect(),
        }
    }
}

impl From<speech_analysis::audible_structure::DependencyMatchCandidate>
    for SyntacticDependencyMatch
{
    fn from(value: speech_analysis::audible_structure::DependencyMatchCandidate) -> Self {
        Self {
            matcher_version: value.matcher_version,
            matcher_key: value.matcher_key,
            syntactic_analysis_id: value.syntactic_analysis_id,
            sentence_id: value.sentence_id,
            start_token_index: value.token_span.start_token_index,
            end_token_index: value.token_span.end_token_index,
            bindings: value.bindings,
            evidence_class: value.evidence_class,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use async_trait::async_trait;
    use domain::{
        LanguageCode, SyntacticAlignmentStatus, SyntacticProviderError, SyntacticSentenceAnalysis,
        SyntacticToken, TimeMs,
    };

    use super::*;

    struct CountingProvider {
        probes: Arc<AtomicUsize>,
        analyses: Arc<AtomicUsize>,
        invalidate_second_sentence: bool,
    }

    struct TimeoutProvider;

    #[async_trait]
    impl SyntacticAnalysisProvider for TimeoutProvider {
        fn provider_id(&self) -> &str {
            "timeout-fixture"
        }

        async fn probe(
            &self,
            language: &LanguageCode,
        ) -> Result<crate::SyntacticProviderCapability, SyntacticProviderError> {
            Ok(crate::SyntacticProviderCapability {
                descriptor: Some(descriptor()),
                language: language.clone(),
                status: SyntacticCapabilityStatus::Ready,
            })
        }

        async fn analyze(
            &self,
            _request: &SyntacticAnalysisRequest,
        ) -> Result<SyntacticAnalysisDraft, SyntacticProviderError> {
            Err(SyntacticProviderError::Timeout)
        }
    }

    fn descriptor() -> SyntacticProviderDescriptor {
        SyntacticProviderDescriptor {
            provider_id: "neutral-qualified-fixture".into(),
            provider_version: "1".into(),
            runtime_id: "fixture-runtime".into(),
            runtime_version: "1".into(),
            model_id: "fixture-model".into(),
            model_version: "1".into(),
            model_checksum_sha256: "a".repeat(64),
        }
    }

    #[async_trait]
    impl SyntacticAnalysisProvider for CountingProvider {
        fn provider_id(&self) -> &str {
            "neutral-qualified-fixture"
        }

        async fn probe(
            &self,
            language: &LanguageCode,
        ) -> Result<crate::SyntacticProviderCapability, SyntacticProviderError> {
            self.probes.fetch_add(1, Ordering::SeqCst);
            Ok(crate::SyntacticProviderCapability {
                descriptor: Some(descriptor()),
                language: language.clone(),
                status: SyntacticCapabilityStatus::Ready,
            })
        }

        async fn analyze(
            &self,
            request: &SyntacticAnalysisRequest,
        ) -> Result<SyntacticAnalysisDraft, SyntacticProviderError> {
            self.analyses.fetch_add(1, Ordering::SeqCst);
            let mut sentences = request.sentences.iter().map(syntax_for).collect::<Vec<_>>();
            if self.invalidate_second_sentence
                && let Some(token) = sentences
                    .get_mut(1)
                    .and_then(|sentence| sentence.tokens.first_mut())
            {
                token.head_parser_token_index = None;
                token.dependency_relation = "root".into();
            }
            Ok(SyntacticAnalysisDraft {
                descriptor: descriptor(),
                sentences,
            })
        }
    }

    fn sentence(id: &str, text: &str) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(2000),
            original_text: text.into(),
            display_text: text.into(),
            tokens: subtitle_core::tokenize_english(text),
        }
    }

    fn syntax_for(sentence: &SubtitleSentence) -> SyntacticSentenceAnalysis {
        let words = sentence
            .tokens
            .iter()
            .filter(|token| token.kind == domain::SubtitleTokenKind::Word)
            .collect::<Vec<_>>();
        let root = words.len() - 1;
        let tokens = words
            .iter()
            .enumerate()
            .map(|(index, source)| {
                let lower = source.text.to_ascii_lowercase();
                let (upos, relation) = match lower.as_str() {
                    "they" => ("PRON", "nsubj"),
                    "are" | "have" => ("AUX", "aux"),
                    "to" => ("PART", "mark"),
                    _ if index == root => ("VERB", "root"),
                    _ => ("VERB", "dep"),
                };
                SyntacticToken {
                    parser_token_index: index as u32,
                    surface: source.text.clone(),
                    lemma: lower,
                    upos: upos.into(),
                    xpos: None,
                    features: BTreeMap::new(),
                    head_parser_token_index: (index != root).then_some(root as u32),
                    dependency_relation: relation.into(),
                    start_char: source.start_char,
                    end_char: source.end_char,
                    subtitle_token_indices: vec![source.index],
                    alignment_status: SyntacticAlignmentStatus::Exact,
                    confidence: None,
                }
            })
            .collect();
        SyntacticSentenceAnalysis {
            sentence_id: sentence.id.clone(),
            source_text: sentence.display_text.clone(),
            source_char_count: sentence.display_text.chars().count() as u32,
            tokens,
            unaligned_subtitle_token_indices: Vec::new(),
            lexical_alignment_coverage: 1.0,
        }
    }

    fn have_to_pattern() -> SyntacticDependencyPattern {
        SyntacticDependencyPattern {
            matcher_key: "have-to-candidate".into(),
            nodes: vec![
                SyntacticPatternNode {
                    binding: "predicate".into(),
                    lemma: Some("leave".into()),
                    upos: Some("VERB".into()),
                    dependency_relation: None,
                },
                SyntacticPatternNode {
                    binding: "have".into(),
                    lemma: Some("have".into()),
                    upos: None,
                    dependency_relation: None,
                },
            ],
            edges: vec![SyntacticPatternEdge {
                head_binding: "predicate".into(),
                dependent_binding: "have".into(),
                dependency_relation: Some("aux".into()),
            }],
        }
    }

    #[tokio::test]
    async fn one_provider_call_yields_per_sentence_artifacts_for_all_consumers() {
        let probes = Arc::new(AtomicUsize::new(0));
        let analyses = Arc::new(AtomicUsize::new(0));
        let provider = Arc::new(CountingProvider {
            probes: probes.clone(),
            analyses: analyses.clone(),
            invalidate_second_sentence: false,
        });
        let sentences = vec![
            sentence("syntax-product-1", "They are going to leave."),
            sentence("syntax-product-2", "They have to leave."),
        ];
        let result = SyntacticConsumerOrchestrator::new(
            Some(provider),
            SyntacticProductQualification::corrected_v2(),
        )
        .consume(
            SyntacticAnalysisRequest {
                language: LanguageCode::parse("en").unwrap(),
                sentences,
                profile_fingerprint: "corrected-v2".into(),
            },
            &HashMap::new(),
            &[have_to_pattern()],
        )
        .await;
        assert_eq!(probes.load(Ordering::SeqCst), 1);
        assert_eq!(analyses.load(Ordering::SeqCst), 1);
        assert_eq!(result.analysis_request_count, 1);
        assert_eq!(result.sentences.len(), 2);
        assert!(
            result
                .sentences
                .iter()
                .all(|value| value.analysis.is_some())
        );
        assert_ne!(
            result.sentences[0].analysis.as_ref().unwrap().id,
            result.sentences[1].analysis.as_ref().unwrap().id
        );
        assert!(result.sentences[0].reference_b.iter().any(|value| {
            value
                .evidence
                .contains("prediction_provenance:syntax_model")
        }));
        assert!(result.sentences[0].sense_groups.iter().any(|span| {
            span.sources
                .contains(&domain::SenseGroupSource::DependencyParse)
        }));
        let first_artifact_id = result.sentences[0].analysis.as_ref().unwrap().id.as_str();
        assert!(result.sentences[0].reference_b.iter().any(|value| {
            value
                .evidence
                .contains(&format!("syntactic_artifact:{first_artifact_id}"))
        }));
        assert!(result.sentences[0].sense_groups.iter().all(|span| {
            span.syntactic_analysis_id.as_ref().unwrap().as_str() == first_artifact_id
        }));
        assert_eq!(result.sentences[1].dependency_matches.len(), 1);
        let artifact_id = result.sentences[1].analysis.as_ref().unwrap().id.as_str();
        assert_eq!(
            result.sentences[1].dependency_matches[0]
                .syntactic_analysis_id
                .as_str(),
            artifact_id
        );
    }

    #[tokio::test]
    async fn invalid_tree_falls_back_only_its_sentence_without_another_provider_call() {
        let probes = Arc::new(AtomicUsize::new(0));
        let analyses = Arc::new(AtomicUsize::new(0));
        let provider = Arc::new(CountingProvider {
            probes: probes.clone(),
            analyses: analyses.clone(),
            invalidate_second_sentence: true,
        });
        let valid = sentence("syntax-isolation-1", "They are going to leave.");
        let invalid = sentence("syntax-isolation-2", "They have to leave.");
        let expected_b = predict_default_connected(&invalid);
        let result = SyntacticConsumerOrchestrator::new(
            Some(provider),
            SyntacticProductQualification::corrected_v2(),
        )
        .consume(
            SyntacticAnalysisRequest {
                language: LanguageCode::parse("en").unwrap(),
                sentences: vec![valid, invalid],
                profile_fingerprint: "corrected-v2".into(),
            },
            &HashMap::new(),
            &[have_to_pattern()],
        )
        .await;

        assert_eq!(probes.load(Ordering::SeqCst), 1);
        assert_eq!(analyses.load(Ordering::SeqCst), 1);
        assert!(result.sentences[0].analysis.is_some());
        assert_eq!(result.sentences[1].analysis, None);
        assert_eq!(
            result.sentences[1].fallback_reason,
            Some(SyntacticFallbackReason::InvalidSentence)
        );
        assert_eq!(result.sentences[1].reference_b, expected_b);
        assert!(result.sentences[1].dependency_matches.is_empty());
    }

    #[tokio::test]
    async fn missing_provider_is_exact_b_and_rule_sense_group_fallback() {
        let sentence = sentence("syntax-fallback", "They have to leave.");
        let expected_b = predict_default_connected(&sentence);
        let expected_groups =
            partition_sentence(&sentence, &[], &SenseGroupPartitionConfig::default())
                .into_iter()
                .map(SyntacticSenseGroupSpan::from)
                .collect::<Vec<_>>();
        let result =
            SyntacticConsumerOrchestrator::new(None, SyntacticProductQualification::corrected_v2())
                .consume(
                    SyntacticAnalysisRequest {
                        language: LanguageCode::parse("en").unwrap(),
                        sentences: vec![sentence],
                        profile_fingerprint: "corrected-v2".into(),
                    },
                    &HashMap::new(),
                    &[have_to_pattern()],
                )
                .await;
        assert_eq!(result.analysis_request_count, 0);
        assert_eq!(result.sentences[0].reference_b, expected_b);
        assert_eq!(result.sentences[0].sense_groups, expected_groups);
        assert!(result.sentences[0].dependency_matches.is_empty());
        assert_eq!(
            result.sentences[0].fallback_reason,
            Some(SyntacticFallbackReason::ProviderNotConfigured)
        );
    }

    #[tokio::test]
    async fn timeout_is_explicit_and_preserves_exact_consumer_fallbacks() {
        let sentence = sentence("syntax-timeout", "They have to leave.");
        let expected_b = predict_default_connected(&sentence);
        let result = SyntacticConsumerOrchestrator::new(
            Some(Arc::new(TimeoutProvider)),
            SyntacticProductQualification::corrected_v2(),
        )
        .consume(
            SyntacticAnalysisRequest {
                language: LanguageCode::parse("en").unwrap(),
                sentences: vec![sentence],
                profile_fingerprint: "corrected-v2".into(),
            },
            &HashMap::new(),
            &[have_to_pattern()],
        )
        .await;

        assert_eq!(result.probe_request_count, 1);
        assert_eq!(result.analysis_request_count, 1);
        assert_eq!(result.sentences[0].reference_b, expected_b);
        assert_eq!(
            result.sentences[0].fallback_reason,
            Some(SyntacticFallbackReason::Timeout)
        );
    }
}
