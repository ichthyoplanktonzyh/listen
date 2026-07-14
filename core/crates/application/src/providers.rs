use async_trait::async_trait;
use domain::*;
use thiserror::Error;

#[async_trait]
pub trait DictionaryProvider: Send + Sync {
    fn info(&self) -> DictionaryProviderInfo;
    async fn lookup(
        &self,
        language: &LanguageCode,
        lemma: &str,
    ) -> Result<Option<DictionaryLookup>, DictionaryProviderError>;
}

#[derive(Debug, Error)]
#[error("dictionary provider failed: {0}")]
pub struct DictionaryProviderError(pub String);

pub trait LexicalNormalizationProvider: Send + Sync {
    fn provider_id(&self) -> &'static str;
    fn version(&self) -> &str;
    fn normalize(
        &self,
        language: &LanguageCode,
        value: &str,
    ) -> Result<Option<String>, LexicalNormalizationProviderError>;
    fn phrase_candidates(
        &self,
        language: &LanguageCode,
        sentence: &SubtitleSentence,
    ) -> Result<Vec<PhraseCandidate>, LexicalNormalizationProviderError>;
}

#[derive(Debug, Error)]
#[error("lexical normalization provider failed: {0}")]
pub struct LexicalNormalizationProviderError(pub String);

pub trait PronunciationProvider: Send + Sync {
    fn info(&self) -> PronunciationProviderInfo;
    fn analyze_sentence(&self, sentence: &SubtitleSentence) -> Option<SentencePronunciation>;
    fn lookup_word(&self, word: &str, token_index: u32) -> Option<WordPronunciation>;
    fn rule_catalog(&self) -> serde_json::Value {
        serde_json::json!([])
    }
}

// ---------------------------------------------------------------------------
// Phase 3.9.1 provider-neutral syntactic analysis seam.
//
// Providers return a draft only. Application assigns artifact identity and
// validates the draft against the exact SubtitleSentence/SubtitleToken snapshot
// before any consumer may activate syntax-gated behavior (ADR 0023).
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq)]
pub struct SyntacticAnalysisRequest {
    pub language: LanguageCode,
    pub sentences: Vec<SubtitleSentence>,
    pub profile_fingerprint: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SyntacticAnalysisDraft {
    pub descriptor: SyntacticProviderDescriptor,
    pub sentences: Vec<SyntacticSentenceAnalysis>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyntacticCapabilityStatus {
    Ready,
    RuntimeMissing,
    ModelMissing,
    ModelCorrupt,
    UnsupportedLanguage,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyntacticProviderCapability {
    pub descriptor: Option<SyntacticProviderDescriptor>,
    pub language: LanguageCode,
    pub status: SyntacticCapabilityStatus,
}

#[async_trait]
pub trait SyntacticAnalysisProvider: Send + Sync {
    fn provider_id(&self) -> &str;
    async fn probe(
        &self,
        language: &LanguageCode,
    ) -> Result<SyntacticProviderCapability, SyntacticProviderError>;
    async fn analyze(
        &self,
        request: &SyntacticAnalysisRequest,
    ) -> Result<SyntacticAnalysisDraft, SyntacticProviderError>;
}

pub fn finalize_syntactic_analysis(
    request: &SyntacticAnalysisRequest,
    draft: SyntacticAnalysisDraft,
) -> Result<(SyntacticAnalysis, SyntacticValidationReport), SyntacticProviderError> {
    let source_fingerprint = syntactic_source_fingerprint(&request.language, &request.sentences);
    let fingerprint = syntactic_analysis_fingerprint(
        &draft.descriptor,
        &source_fingerprint,
        &request.profile_fingerprint,
    );
    let analysis = SyntacticAnalysis {
        id: SyntacticAnalysisId::from_fingerprint("syntactic-analysis", &fingerprint),
        contract_version: SYNTACTIC_CONTRACT_VERSION,
        descriptor: draft.descriptor,
        language: request.language.clone(),
        source_fingerprint,
        profile_fingerprint: request.profile_fingerprint.clone(),
        sentences: draft.sentences,
    };
    let report = validate_syntactic_analysis(&analysis, &request.sentences);
    if report.status == SyntacticValidationStatus::Invalid {
        return Err(SyntacticProviderError::InvalidOutput {
            detail: report
                .issues
                .first()
                .map(|issue| issue.detail.clone())
                .unwrap_or_else(|| "unknown validation failure".into()),
        });
    }
    Ok((analysis, report))
}

// ---------------------------------------------------------------------------
// Phase 3.12 vendor-neutral LLM provider seams.
//
// Two layers on purpose:
//   * `LlmChatAdapter` is the *wire seam* — each heterogeneous protocol
//     (OpenAI Chat Completions, Anthropic Messages, ...) implements it. This is
//     the surface where neutrality is proven: a shared contract suite drives
//     every adapter through the same scenarios.
//   * `SemanticRubricProvider` / `SemanticJudgeProvider` are the *application
//     seams* that `AppServices` holds. A single generic composition
//     (`LlmSemanticProvider<A>` in crate `llm-provider`) builds the prompt +
//     schema, parses the output into a draft, and works over *any*
//     `LlmChatAdapter`. Swapping the adapter must not change semantics.
//
// Providers return content **drafts** only. They never mint identity, version,
// or snapshot hashes and never return a `SemanticRubric`/`SemanticJudgment`
// with an id: Phase 3.11 keeps identity, versioning, and validation on the
// server-side use case, so a vendor layer can never become a second identity
// writer (ADR 0021 four-layer separation).
// ---------------------------------------------------------------------------

/// A neutral, structured-output chat request. Wire-agnostic: it names no
/// provider message shape. Adapters translate it into their protocol and must
/// map length/refusal/schema failures onto [`LlmProviderError`].
#[derive(Debug, Clone, PartialEq)]
pub struct StructuredChatRequest {
    pub system: String,
    pub user: String,
    /// JSON Schema the output text must satisfy. Adapters that support native
    /// structured output pass it through; others fall back to strict-JSON
    /// instruction + post-hoc validation.
    pub json_schema: serde_json::Value,
    pub schema_name: String,
    pub max_output_tokens: u32,
    pub temperature: Option<f32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct TokenUsage {
    pub prompt_tokens: Option<u32>,
    pub completion_tokens: Option<u32>,
}

/// A clean, complete structured response. Adapters return this only on a
/// normal stop with text; truncation, refusal, and rate limits are errors, not
/// values, so the composition layer can never mistake a cut-off answer for a
/// real one.
#[derive(Debug, Clone, PartialEq)]
pub struct StructuredChatResponse {
    /// Raw text expected to parse as JSON matching the request schema.
    pub json_text: String,
    /// The most specific model identifier the provider reported. `None` is
    /// recorded as incomplete provenance, never invented.
    pub model_id: Option<String>,
    pub usage: Option<TokenUsage>,
}

/// A runtime view of a configured provider: which protocol, which model, and
/// its (declared or probed) capabilities.
#[derive(Debug, Clone, PartialEq)]
pub struct LlmProviderDescriptor {
    pub adapter_kind: LlmAdapterKind,
    pub model_id: String,
    pub capability: ProviderCapability,
}

/// The wire seam. One implementation per protocol family.
#[async_trait]
pub trait LlmChatAdapter: Send + Sync {
    fn adapter_kind(&self) -> LlmAdapterKind;
    fn descriptor(&self) -> LlmProviderDescriptor;
    /// Send one structured request and return the completed JSON text.
    async fn complete_structured(
        &self,
        request: &StructuredChatRequest,
    ) -> Result<StructuredChatResponse, LlmProviderError>;
    /// Actually exercise structured output against this endpoint (the Ollama
    /// trap: protocol compatibility is not capability equivalence). Returns a
    /// measured [`CapabilityClaim::Probed`].
    async fn probe_structured_output(&self) -> Result<CapabilityClaim, LlmProviderError>;
}

/// Neutral rubric-generation request. The provider proposes information points;
/// the use case assigns identity, version, provenance, and snapshot hashes.
#[derive(Debug, Clone, PartialEq)]
pub struct RubricGenerationRequest {
    pub purpose: SemanticTaskKind,
    pub source_language: LanguageCode,
    pub response_language: LanguageCode,
    pub transcript_snapshot: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RubricPointDraft {
    pub importance: RubricPointImportance,
    pub statement: String,
    pub accepted_paraphrase_notes: Option<String>,
}

/// Content-only rubric proposal. No id, no version, no source snapshot — those
/// belong to the server-side [`domain::SemanticRubric`] the use case builds.
#[derive(Debug, Clone, PartialEq)]
pub struct RubricDraft {
    pub points: Vec<RubricPointDraft>,
    pub model_id: Option<String>,
    pub prompt_version: Option<String>,
    pub schema_version: Option<String>,
    pub raw_output: serde_json::Value,
}

/// Neutral judge request over one response against a fixed rubric version.
#[derive(Debug, Clone, PartialEq)]
pub struct JudgeRequest {
    pub rubric: SemanticRubric,
    pub response_transcript: String,
    pub response_language: LanguageCode,
    pub asr_reliability: Option<AsrReliability>,
}

/// Content-only judgment proposal. Reuses the identity-free Phase 3.11
/// [`domain::PointJudgment`] / [`domain::JudgmentAbstain`]; the use case wraps
/// it into a versioned, hashed, validated `SemanticJudgment`.
#[derive(Debug, Clone, PartialEq)]
pub struct JudgmentDraft {
    pub points: Vec<PointJudgment>,
    pub abstain: Option<JudgmentAbstain>,
    pub model_id: Option<String>,
    pub prompt_version: Option<String>,
    pub schema_version: Option<String>,
    pub raw_output: serde_json::Value,
}

/// Application seam for generating a fixed scoring rubric from a segment.
#[async_trait]
pub trait SemanticRubricProvider: Send + Sync {
    fn descriptor(&self) -> LlmProviderDescriptor;
    async fn generate_rubric(
        &self,
        request: &RubricGenerationRequest,
    ) -> Result<RubricDraft, LlmProviderError>;
}

/// Application seam for judging one response against a fixed rubric version.
/// Dictogloss/summary writing feedback is judged through this same seam over
/// the corresponding `SemanticTaskKind`; there is no separate writing-feedback
/// trait until Phase 3.15 reveals its real shape (§3.6 seam discipline).
#[async_trait]
pub trait SemanticJudgeProvider: Send + Sync {
    fn descriptor(&self) -> LlmProviderDescriptor;
    async fn judge(&self, request: &JudgeRequest) -> Result<JudgmentDraft, LlmProviderError>;
}

#[cfg(test)]
mod syntactic_provider_tests {
    use super::*;
    use std::collections::BTreeMap;

    struct FakeSyntacticProvider;

    fn descriptor() -> SyntacticProviderDescriptor {
        SyntacticProviderDescriptor {
            provider_id: "fake-syntax".into(),
            provider_version: "v1".into(),
            runtime_id: "fake-runtime".into(),
            runtime_version: "v1".into(),
            model_id: "fake-model".into(),
            model_version: "v1".into(),
            model_checksum_sha256: "b".repeat(64),
        }
    }

    fn request() -> SyntacticAnalysisRequest {
        let text = "Cats run.";
        SyntacticAnalysisRequest {
            language: LanguageCode::parse("en").unwrap(),
            sentences: vec![SubtitleSentence {
                id: SubtitleSentenceId::parse("sentence-1").unwrap(),
                index: 0,
                start: TimeMs::new(0),
                end: TimeMs::new(1000),
                original_text: text.into(),
                display_text: text.into(),
                tokens: subtitle_core::tokenize_english(text),
            }],
            profile_fingerprint: "english-default-v1".into(),
        }
    }

    #[async_trait]
    impl SyntacticAnalysisProvider for FakeSyntacticProvider {
        fn provider_id(&self) -> &str {
            "fake-syntax"
        }

        async fn probe(
            &self,
            language: &LanguageCode,
        ) -> Result<SyntacticProviderCapability, SyntacticProviderError> {
            Ok(SyntacticProviderCapability {
                descriptor: Some(descriptor()),
                language: language.clone(),
                status: SyntacticCapabilityStatus::Ready,
            })
        }

        async fn analyze(
            &self,
            request: &SyntacticAnalysisRequest,
        ) -> Result<SyntacticAnalysisDraft, SyntacticProviderError> {
            let sentence = &request.sentences[0];
            Ok(SyntacticAnalysisDraft {
                descriptor: descriptor(),
                sentences: vec![SyntacticSentenceAnalysis {
                    sentence_id: sentence.id.clone(),
                    source_text: sentence.display_text.clone(),
                    source_char_count: sentence.display_text.chars().count() as u32,
                    tokens: vec![
                        SyntacticToken {
                            parser_token_index: 0,
                            surface: "Cats".into(),
                            lemma: "cat".into(),
                            upos: "NOUN".into(),
                            xpos: Some("NNS".into()),
                            features: BTreeMap::new(),
                            head_parser_token_index: Some(1),
                            dependency_relation: "nsubj".into(),
                            start_char: 0,
                            end_char: 4,
                            subtitle_token_indices: vec![0],
                            alignment_status: SyntacticAlignmentStatus::Exact,
                            confidence: None,
                        },
                        SyntacticToken {
                            parser_token_index: 1,
                            surface: "run".into(),
                            lemma: "run".into(),
                            upos: "VERB".into(),
                            xpos: Some("VBP".into()),
                            features: BTreeMap::new(),
                            head_parser_token_index: None,
                            dependency_relation: "root".into(),
                            start_char: 5,
                            end_char: 8,
                            subtitle_token_indices: vec![2],
                            alignment_status: SyntacticAlignmentStatus::Exact,
                            confidence: None,
                        },
                        SyntacticToken {
                            parser_token_index: 2,
                            surface: ".".into(),
                            lemma: ".".into(),
                            upos: "PUNCT".into(),
                            xpos: Some(".".into()),
                            features: BTreeMap::new(),
                            head_parser_token_index: Some(1),
                            dependency_relation: "punct".into(),
                            start_char: 8,
                            end_char: 9,
                            subtitle_token_indices: vec![3],
                            alignment_status: SyntacticAlignmentStatus::Exact,
                            confidence: None,
                        },
                    ],
                    unaligned_subtitle_token_indices: vec![],
                    lexical_alignment_coverage: 1.0,
                }],
            })
        }
    }

    #[tokio::test]
    async fn fake_provider_draft_is_finalized_and_validated_server_side() {
        let provider = FakeSyntacticProvider;
        let request = request();
        let capability = provider.probe(&request.language).await.unwrap();
        assert_eq!(capability.status, SyntacticCapabilityStatus::Ready);
        let draft = provider.analyze(&request).await.unwrap();
        let (analysis, report) = finalize_syntactic_analysis(&request, draft).unwrap();
        assert_eq!(analysis.descriptor.provider_id, "fake-syntax");
        assert!(report.is_activatable());
    }

    #[tokio::test]
    async fn structurally_invalid_provider_draft_is_closed_error() {
        let provider = FakeSyntacticProvider;
        let request = request();
        let mut draft = provider.analyze(&request).await.unwrap();
        draft.sentences[0].tokens[0].head_parser_token_index = Some(99);
        let error = finalize_syntactic_analysis(&request, draft).unwrap_err();
        assert!(matches!(
            error,
            SyntacticProviderError::InvalidOutput { .. }
        ));
    }
}
