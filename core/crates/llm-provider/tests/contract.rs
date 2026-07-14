//! Phase 3.12 neutrality proof.
//!
//! The same scenario suite is driven through both heterogeneous adapters
//! (OpenAI Chat Completions and Anthropic Messages) against a local fake
//! server. Each protocol receives its own wire-shaped canned response, yet the
//! neutral outcome — a `JudgmentDraft`, a standardized `LlmProviderError`, or a
//! probed capability — must be identical. Different wire in, same domain out:
//! that is the property that proves the domain layer is not captured by any
//! single provider's wire format.

use std::time::Duration;

use application::{JudgeRequest, LlmChatAdapter, SemanticJudgeProvider};
use axum::{Json, Router, extract::State, http::HeaderMap, http::StatusCode, routing::post};
use domain::{
    AsrReliability, CapabilityClaim, LanguageCode, LlmProviderError, RubricPoint,
    RubricPointImportance, RubricSource, SemanticGeneratorKind, SemanticGeneratorProvenance,
    SemanticRubric, SemanticTaskKind, semantic_rubric_id,
};
use llm_provider::{AnthropicMessagesAdapter, LlmSemanticProvider, OpenAiChatAdapter};
use tokio::net::TcpListener;

#[derive(Clone, Copy, Debug)]
enum Protocol {
    OpenAi,
    Anthropic,
}

const ALL_PROTOCOLS: [Protocol; 2] = [Protocol::OpenAi, Protocol::Anthropic];

#[derive(Clone)]
struct Canned {
    status: StatusCode,
    body: serde_json::Value,
    retry_after: Option<String>,
    delay_ms: u64,
}

async fn serve(State(canned): State<Canned>) -> (StatusCode, HeaderMap, Json<serde_json::Value>) {
    if canned.delay_ms > 0 {
        tokio::time::sleep(Duration::from_millis(canned.delay_ms)).await;
    }
    let mut headers = HeaderMap::new();
    if let Some(value) = &canned.retry_after {
        headers.insert("retry-after", value.parse().unwrap());
    }
    (canned.status, headers, Json(canned.body))
}

async fn spawn(canned: Canned) -> String {
    let router = Router::new()
        .route("/chat/completions", post(serve))
        .route("/v1/messages", post(serve))
        .with_state(canned);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    format!("http://{addr}")
}

/// Wrap a structured-output payload into each protocol's success envelope.
fn success_envelope(protocol: Protocol, tool_name: &str, output: serde_json::Value) -> Canned {
    let body = match protocol {
        Protocol::OpenAi => serde_json::json!({
            "model": "fake-openai-model",
            "choices": [ {
                "finish_reason": "stop",
                "message": { "content": output.to_string(), "refusal": null }
            } ],
            "usage": { "prompt_tokens": 10, "completion_tokens": 20 }
        }),
        Protocol::Anthropic => serde_json::json!({
            "model": "fake-anthropic-model",
            "stop_reason": "tool_use",
            "content": [ { "type": "tool_use", "name": tool_name, "input": output } ],
            "usage": { "input_tokens": 10, "output_tokens": 20 }
        }),
    };
    Canned {
        status: StatusCode::OK,
        body,
        retry_after: None,
        delay_ms: 0,
    }
}

fn sample_rubric() -> SemanticRubric {
    let language = LanguageCode::parse("en").unwrap();
    let response_language = LanguageCode::parse("en").unwrap();
    let snapshot = "The quake struck at dawn near the coast.";
    let id = semantic_rubric_id(
        None,
        0,
        4000,
        SemanticTaskKind::L2Retelling,
        &language,
        &response_language,
        snapshot,
    );
    SemanticRubric {
        id,
        purpose: SemanticTaskKind::L2Retelling,
        source: RubricSource {
            media_id: None,
            track_id: None,
            start_ms: 0,
            end_ms: 4000,
            language,
            transcript_snapshot: snapshot.into(),
        },
        response_language,
        points: vec![
            RubricPoint {
                point_id: "p1".into(),
                importance: RubricPointImportance::Required,
                statement: "A quake happened.".into(),
                accepted_paraphrase_notes: None,
            },
            RubricPoint {
                point_id: "p2".into(),
                importance: RubricPointImportance::Optional,
                statement: "It was near the coast.".into(),
                accepted_paraphrase_notes: None,
            },
        ],
        version: 1,
        provenance: SemanticGeneratorProvenance {
            kind: SemanticGeneratorKind::Fixture,
            detail: None,
            model_id: None,
            prompt_version: None,
            schema_version: None,
        },
        revision: None,
        created_at_ms: 0,
    }
}

fn judge_request() -> JudgeRequest {
    JudgeRequest {
        rubric: sample_rubric(),
        response_transcript: "quake at dawn".into(),
        response_language: LanguageCode::parse("en").unwrap(),
        asr_reliability: Some(AsrReliability::Reliable),
    }
}

/// Build the semantic judge for a protocol pointed at `base_url`.
enum Judge {
    OpenAi(LlmSemanticProvider<OpenAiChatAdapter>),
    Anthropic(LlmSemanticProvider<AnthropicMessagesAdapter>),
}

impl Judge {
    fn build(protocol: Protocol, base_url: &str, timeout: Duration) -> Self {
        match protocol {
            Protocol::OpenAi => Judge::OpenAi(LlmSemanticProvider::new(
                OpenAiChatAdapter::new(base_url, "m", Some("k".into()), timeout).unwrap(),
            )),
            Protocol::Anthropic => Judge::Anthropic(LlmSemanticProvider::new(
                AnthropicMessagesAdapter::new(base_url, "m", Some("k".into()), None, timeout)
                    .unwrap(),
            )),
        }
    }

    async fn judge(
        &self,
        request: &JudgeRequest,
    ) -> Result<application::JudgmentDraft, LlmProviderError> {
        match self {
            Judge::OpenAi(provider) => provider.judge(request).await,
            Judge::Anthropic(provider) => provider.judge(request).await,
        }
    }

    async fn probe(&self) -> Result<CapabilityClaim, LlmProviderError> {
        match self {
            Judge::OpenAi(provider) => provider.adapter().probe_structured_output().await,
            Judge::Anthropic(provider) => provider.adapter().probe_structured_output().await,
        }
    }
}

async fn run_judge(
    protocol: Protocol,
    canned: Canned,
    timeout: Duration,
) -> Result<application::JudgmentDraft, LlmProviderError> {
    let base = spawn(canned).await;
    Judge::build(protocol, &base, timeout)
        .judge(&judge_request())
        .await
}

const T: Duration = Duration::from_secs(5);

#[tokio::test]
async fn success_yields_identical_neutral_judgment_across_protocols() {
    let output = serde_json::json!({
        "abstain": null,
        "points": [
            { "point_id": "p1", "verdict": "covered", "supporting_spans": [ { "start_char": 0, "end_char": 5 } ] },
            { "point_id": "p2", "verdict": "missing", "supporting_spans": [] }
        ]
    });
    let mut drafts = Vec::new();
    for protocol in ALL_PROTOCOLS {
        let canned = success_envelope(protocol, "semantic_judgment", output.clone());
        let draft = run_judge(protocol, canned, T).await.expect("judgment");
        assert!(draft.abstain.is_none());
        assert_eq!(draft.points.len(), 2);
        assert_eq!(draft.points[0].point_id, "p1");
        drafts.push(draft.points);
    }
    // The core neutrality assertion: different wire, identical domain output.
    assert_eq!(drafts[0], drafts[1]);
}

#[tokio::test]
async fn abstain_is_carried_through_both_protocols() {
    let output = serde_json::json!({
        "abstain": { "reason": "unreliable_transcript", "note": null },
        "points": []
    });
    for protocol in ALL_PROTOCOLS {
        let canned = success_envelope(protocol, "semantic_judgment", output.clone());
        let draft = run_judge(protocol, canned, T).await.expect("judgment");
        assert!(draft.abstain.is_some());
        assert!(draft.points.is_empty());
    }
}

#[tokio::test]
async fn abstain_with_points_is_rejected_as_schema_invalid() {
    let output = serde_json::json!({
        "abstain": { "reason": "other", "note": null },
        "points": [ { "point_id": "p1", "verdict": "covered", "supporting_spans": [] } ]
    });
    for protocol in ALL_PROTOCOLS {
        let canned = success_envelope(protocol, "semantic_judgment", output.clone());
        let error = run_judge(protocol, canned, T).await.unwrap_err();
        assert!(matches!(error, LlmProviderError::SchemaInvalid { .. }));
    }
}

#[tokio::test]
async fn wrong_schema_output_maps_to_schema_invalid() {
    let output = serde_json::json!({ "abstain": null, "points": "not-an-array" });
    for protocol in ALL_PROTOCOLS {
        let canned = success_envelope(protocol, "semantic_judgment", output.clone());
        let error = run_judge(protocol, canned, T).await.unwrap_err();
        assert!(matches!(error, LlmProviderError::SchemaInvalid { .. }));
    }
}

#[tokio::test]
async fn refusal_maps_to_refusal_across_protocols() {
    for protocol in ALL_PROTOCOLS {
        let body = match protocol {
            Protocol::OpenAi => serde_json::json!({
                "model": "m",
                "choices": [ { "finish_reason": "stop", "message": { "content": null, "refusal": "I can't help with that." } } ]
            }),
            Protocol::Anthropic => serde_json::json!({
                "model": "m",
                "stop_reason": "refusal",
                "content": []
            }),
        };
        let canned = Canned {
            status: StatusCode::OK,
            body,
            retry_after: None,
            delay_ms: 0,
        };
        let error = run_judge(protocol, canned, T).await.unwrap_err();
        assert!(matches!(error, LlmProviderError::Refusal { .. }));
    }
}

#[tokio::test]
async fn truncation_maps_to_truncated_across_protocols() {
    for protocol in ALL_PROTOCOLS {
        let body = match protocol {
            Protocol::OpenAi => serde_json::json!({
                "model": "m",
                "choices": [ { "finish_reason": "length", "message": { "content": "{" } } ]
            }),
            Protocol::Anthropic => serde_json::json!({
                "model": "m",
                "stop_reason": "max_tokens",
                "content": []
            }),
        };
        let canned = Canned {
            status: StatusCode::OK,
            body,
            retry_after: None,
            delay_ms: 0,
        };
        let error = run_judge(protocol, canned, T).await.unwrap_err();
        assert!(matches!(error, LlmProviderError::Truncated));
    }
}

#[tokio::test]
async fn rate_limit_status_maps_with_retry_after() {
    for protocol in ALL_PROTOCOLS {
        let canned = Canned {
            status: StatusCode::TOO_MANY_REQUESTS,
            body: serde_json::json!({ "error": "slow down" }),
            retry_after: Some("2".into()),
            delay_ms: 0,
        };
        let error = run_judge(protocol, canned, T).await.unwrap_err();
        assert_eq!(
            error,
            LlmProviderError::RateLimit {
                retry_after_ms: Some(2000)
            }
        );
    }
}

#[tokio::test]
async fn auth_status_maps_to_auth_without_payload() {
    for protocol in ALL_PROTOCOLS {
        let canned = Canned {
            status: StatusCode::UNAUTHORIZED,
            body: serde_json::json!({ "error": "bad key sk-secret-echoed" }),
            retry_after: None,
            delay_ms: 0,
        };
        let error = run_judge(protocol, canned, T).await.unwrap_err();
        // Auth carries no payload, so no reflected secret can leak.
        assert_eq!(error, LlmProviderError::Auth);
        let serialized = serde_json::to_string(&error).unwrap();
        assert!(!serialized.contains("sk-secret-echoed"));
    }
}

#[tokio::test]
async fn slow_server_maps_to_timeout() {
    for protocol in ALL_PROTOCOLS {
        let output = serde_json::json!({ "abstain": null, "points": [] });
        let mut canned = success_envelope(protocol, "semantic_judgment", output);
        canned.delay_ms = 400;
        let error = run_judge(protocol, canned, Duration::from_millis(80))
            .await
            .unwrap_err();
        assert_eq!(error, LlmProviderError::Timeout);
    }
}

#[tokio::test]
async fn probe_measures_structured_output_support() {
    // A conforming endpoint probes as supported.
    for protocol in ALL_PROTOCOLS {
        let canned = success_envelope(
            protocol,
            "capability_probe",
            serde_json::json!({ "ok": true }),
        );
        let base = spawn(canned).await;
        let claim = Judge::build(protocol, &base, T)
            .probe()
            .await
            .expect("probe");
        assert!(matches!(
            claim,
            CapabilityClaim::Probed {
                supported: true,
                ..
            }
        ));
    }
    // An endpoint that returns the wrong shape probes as unsupported, not error.
    for protocol in ALL_PROTOCOLS {
        let canned = success_envelope(
            protocol,
            "capability_probe",
            serde_json::json!({ "ok": "nope" }),
        );
        let base = spawn(canned).await;
        let claim = Judge::build(protocol, &base, T)
            .probe()
            .await
            .expect("probe");
        assert!(matches!(
            claim,
            CapabilityClaim::Probed {
                supported: false,
                ..
            }
        ));
    }
}

// ---------------------------------------------------------------------------
// Factory: a stored profile maps to the right adapter; both seams + probe work.
// ---------------------------------------------------------------------------

use domain::{
    DataRetentionPreference, LlmAdapterKind, LlmProviderProfile, LlmUse, ProviderCapability,
    llm_provider_profile_id,
};
use llm_provider::BuiltSemanticProvider;

fn profile_for(protocol: Protocol, base_url: &str) -> LlmProviderProfile {
    let adapter_kind = match protocol {
        Protocol::OpenAi => LlmAdapterKind::OpenAiChatCompletions,
        Protocol::Anthropic => LlmAdapterKind::AnthropicMessages,
    };
    LlmProviderProfile {
        id: llm_provider_profile_id(adapter_kind, base_url, "m"),
        display_name: "t".into(),
        adapter_kind,
        protocol_version: None,
        base_url: base_url.into(),
        model_id: "m".into(),
        auth_ref: None,
        timeout_ms: 5000,
        max_retries: 0,
        cost_budget: None,
        retention: DataRetentionPreference::Unknown,
        allowed_uses: vec![LlmUse::SemanticJudgment],
        capability: ProviderCapability::unknown(),
        created_at_ms: 0,
    }
}

#[tokio::test]
async fn factory_builds_matching_adapter_for_each_profile() {
    let output = serde_json::json!({ "abstain": null, "points": [] });
    for protocol in ALL_PROTOCOLS {
        let base = spawn(success_envelope(
            protocol,
            "semantic_judgment",
            output.clone(),
        ))
        .await;
        let provider =
            BuiltSemanticProvider::build(&profile_for(protocol, &base), Some("k".into()))
                .expect("built");
        // The chosen adapter kind matches the profile.
        let expected = match protocol {
            Protocol::OpenAi => LlmAdapterKind::OpenAiChatCompletions,
            Protocol::Anthropic => LlmAdapterKind::AnthropicMessages,
        };
        assert_eq!(provider.as_judge().descriptor().adapter_kind, expected);
        // The judge seam works through the factory-built provider.
        let draft = provider
            .as_judge()
            .judge(&judge_request())
            .await
            .expect("judgment");
        assert!(draft.abstain.is_none());
    }
}

#[tokio::test]
async fn factory_probe_measures_capability() {
    for protocol in ALL_PROTOCOLS {
        let base = spawn(success_envelope(
            protocol,
            "capability_probe",
            serde_json::json!({ "ok": true }),
        ))
        .await;
        let provider =
            BuiltSemanticProvider::build(&profile_for(protocol, &base), None).expect("built");
        let claim = provider.probe_structured_output().await.expect("probe");
        assert!(matches!(
            claim,
            domain::CapabilityClaim::Probed {
                supported: true,
                ..
            }
        ));
    }
}
