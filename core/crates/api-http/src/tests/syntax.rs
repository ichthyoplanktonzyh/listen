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
use std::sync::atomic::{AtomicUsize, Ordering};

struct RouteSyntacticProvider {
    analyses: Arc<AtomicUsize>,
}

impl RouteSyntacticProvider {
    fn new() -> (Arc<Self>, Arc<AtomicUsize>) {
        let analyses = Arc::new(AtomicUsize::new(0));
        (
            Arc::new(Self {
                analyses: analyses.clone(),
            }),
            analyses,
        )
    }
}

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
        self.analyses.fetch_add(1, Ordering::SeqCst);
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
    let (provider, _) = RouteSyntacticProvider::new();
    let app = router(test_state().with_syntactic_provider(provider));
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

#[tokio::test]
async fn track_analysis_reuses_fingerprint_cache_and_force_rebuilds() {
    let (provider, analyses) = RouteSyntacticProvider::new();
    let root = std::env::temp_dir().join(format!(
        "llplayer-syntax-cache-test-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let manager = SyntaxCapabilityManager::new(&root, None);
    tokio::fs::create_dir_all(manager.install_dir().join("venv/bin"))
        .await
        .unwrap();
    tokio::fs::write(manager.install_dir().join("venv/bin/python"), b"fixture")
        .await
        .unwrap();
    tokio::fs::write(manager.install_dir().join("syntax-sidecar.py"), b"fixture")
        .await
        .unwrap();
    manager.assume_ready_for_tests().await;
    let app = router(test_state().with_syntax_capability(manager, provider));
    let track = setup_phonetic_track(&app, "syntax-cache-route").await;
    let uri = format!(
        "/v1/subtitles/{}/syntax-analysis",
        track["id"].as_str().unwrap()
    );
    let run = |force: bool| {
        app.clone().oneshot(
            Request::post(&uri)
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(serde_json::json!({"force": force}).to_string()))
                .unwrap(),
        )
    };
    let first = run(false).await.unwrap();
    assert_eq!(first.status(), StatusCode::OK);
    let first: serde_json::Value =
        serde_json::from_slice(&to_bytes(first.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(first["status"], "ready");
    assert_eq!(first["cache_hit"], false);
    assert_eq!(analyses.load(Ordering::SeqCst), 1);
    let batch_group_count = first["batch"]["sentences"]
        .as_array()
        .unwrap()
        .iter()
        .map(|sentence| sentence["sense_groups"].as_array().unwrap().len())
        .sum::<usize>();
    assert!(batch_group_count > 0);

    let persisted = get_sense_group_analyses(&app, track["id"].as_str().unwrap()).await;
    assert_eq!(persisted.len(), 1);
    let active = persisted
        .iter()
        .find(|analysis| analysis["status"] == "active")
        .unwrap();
    assert_eq!(
        active["groups"].as_array().unwrap().len(),
        batch_group_count
    );
    let active_id = active["id"].as_str().unwrap().to_owned();

    let second = run(false).await.unwrap();
    let second: serde_json::Value =
        serde_json::from_slice(&to_bytes(second.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(second["cache_hit"], true);
    assert_eq!(analyses.load(Ordering::SeqCst), 1);
    let persisted_after_cache_hit =
        get_sense_group_analyses(&app, track["id"].as_str().unwrap()).await;
    assert_eq!(persisted_after_cache_hit.len(), 1);
    assert_eq!(persisted_after_cache_hit[0]["id"], active_id);
    assert_eq!(persisted_after_cache_hit[0]["status"], "active");

    let rebuilt = run(true).await.unwrap();
    assert_eq!(rebuilt.status(), StatusCode::OK);
    assert_eq!(analyses.load(Ordering::SeqCst), 2);
    let persisted_after_force = get_sense_group_analyses(&app, track["id"].as_str().unwrap()).await;
    assert_eq!(persisted_after_force.len(), 1);
    assert_eq!(persisted_after_force[0]["id"], active_id);
    assert_eq!(persisted_after_force[0]["status"], "active");
    let _ = tokio::fs::remove_dir_all(root).await;
}

async fn get_sense_group_analyses(app: &Router, track_id: &str) -> Vec<serde_json::Value> {
    let response = app
        .clone()
        .oneshot(
            Request::get(format!("/v1/subtitles/{track_id}/sense-group-analyses"))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap()
}
