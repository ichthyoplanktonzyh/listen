use super::*;
use application::{
    SyntacticAnalysisDraft, SyntacticAnalysisProvider, SyntacticAnalysisRequest,
    SyntacticCapabilityStatus, SyntacticProviderCapability,
};
use async_trait::async_trait;
use domain::{
    SyntacticAlignmentStatus, SyntacticProviderDescriptor, SyntacticProviderError,
    SyntacticSentenceAnalysis, SyntacticToken,
};

struct RouteSyntacticProvider;

fn descriptor() -> SyntacticProviderDescriptor {
    SyntacticProviderDescriptor {
        provider_id: "route-neutral-fixture".into(),
        provider_version: "1".into(),
        runtime_id: "fixture".into(),
        runtime_version: "1".into(),
        model_id: "fixture".into(),
        model_version: "1".into(),
        model_checksum_sha256: "b".repeat(64),
    }
}

#[async_trait]
impl SyntacticAnalysisProvider for RouteSyntacticProvider {
    fn provider_id(&self) -> &str {
        "route-neutral-fixture"
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
        Ok(SyntacticAnalysisDraft {
            descriptor: descriptor(),
            sentences: request
                .sentences
                .iter()
                .map(|sentence| {
                    let source_tokens = sentence
                        .tokens
                        .iter()
                        .filter(|token| token.kind != domain::SubtitleTokenKind::Whitespace)
                        .collect::<Vec<_>>();
                    let root = source_tokens
                        .iter()
                        .position(|token| token.kind == domain::SubtitleTokenKind::Word)
                        .unwrap();
                    let tokens = source_tokens
                        .iter()
                        .enumerate()
                        .map(|(index, source)| {
                            let is_root = index == root;
                            let punctuation = source.kind == domain::SubtitleTokenKind::Punctuation;
                            SyntacticToken {
                                parser_token_index: index as u32,
                                surface: source.text.clone(),
                                lemma: source.text.to_ascii_lowercase(),
                                upos: if punctuation { "PUNCT" } else { "NOUN" }.into(),
                                xpos: None,
                                features: Default::default(),
                                head_parser_token_index: (!is_root).then_some(root as u32),
                                dependency_relation: if is_root {
                                    "root"
                                } else if punctuation {
                                    "punct"
                                } else {
                                    "dep"
                                }
                                .into(),
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
                })
                .collect(),
        })
    }
}

#[tokio::test]
async fn unconfigured_syntax_route_returns_exact_explicit_fallback_batch() {
    let app = test_app();
    let track = setup_phonetic_track(&app, "syntax-fallback-route").await;
    let response = app
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/syntactic-consumers",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from("{}"))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let value: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(value["analysis_request_count"], 0);
    assert_eq!(value["probe_request_count"], 0);
    assert!(!value["sentences"].as_array().unwrap().is_empty());
    assert!(
        value["sentences"]
            .as_array()
            .unwrap()
            .iter()
            .all(|sentence| {
                sentence["fallback_reason"] == "provider_not_configured"
                    && sentence.get("analysis").is_none()
                    && sentence["dependency_matches"]
                        .as_array()
                        .unwrap()
                        .is_empty()
                    && !sentence["sense_groups"].as_array().unwrap().is_empty()
            })
    );
}

#[tokio::test]
async fn configured_syntax_route_runs_one_batch_and_returns_shared_artifacts() {
    let app = router(test_state().with_syntactic_provider(Arc::new(RouteSyntacticProvider)));
    let track = setup_phonetic_track(&app, "syntax-configured-route").await;
    let response = app
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/syntactic-consumers",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from("{}"))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let value: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(value["analysis_request_count"], 1);
    assert_eq!(value["probe_request_count"], 1);
    assert_eq!(value["descriptor"]["provider_id"], "route-neutral-fixture");
    assert!(
        value["sentences"]
            .as_array()
            .unwrap()
            .iter()
            .all(|sentence| {
                sentence["analysis"]["id"].as_str().is_some()
                    && sentence.get("fallback_reason").is_none()
            })
    );
}
