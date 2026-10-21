//! Provider neutrality contract for the retained listening assistance: subtitle
//! sense-group partitioning and structured-output capability probing.

use std::{sync::Arc, time::Duration};

use application::{
    LlmChatAdapter, SemanticLlmRuntimeFactory, SenseGroupPartitionProvider,
    SenseGroupPartitionRequest, SenseGroupProtectedSpan, SenseGroupTokenInput,
};
use axum::{Json, Router, extract::State, http::HeaderMap, http::StatusCode, routing::post};
use domain::{
    CapabilityClaim, DataRetentionPreference, LanguageCode, LlmAdapterKind, LlmProviderError,
    LlmProviderProfile, LlmUse, ProviderCapability, llm_provider_profile_id,
};
use llm_provider::{
    AnthropicMessagesAdapter, LlmSemanticProvider, LlmSemanticRuntimeFactory, OpenAiChatAdapter,
};
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

fn success_envelope(protocol: Protocol, tool_name: &str, output: serde_json::Value) -> Canned {
    let body = match protocol {
        Protocol::OpenAi => serde_json::json!({
            "model": "fake-openai-model",
            "choices": [{
                "finish_reason": "stop",
                "message": { "content": output.to_string(), "refusal": null }
            }],
            "usage": { "prompt_tokens": 10, "completion_tokens": 20 }
        }),
        Protocol::Anthropic => serde_json::json!({
            "model": "fake-anthropic-model",
            "stop_reason": "tool_use",
            "content": [{ "type": "tool_use", "name": tool_name, "input": output }],
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

fn request() -> SenseGroupPartitionRequest {
    SenseGroupPartitionRequest {
        language: Some(LanguageCode::parse("en").unwrap()),
        source_text: "When it rains, we stay inside.".into(),
        tokens: vec![
            SenseGroupTokenInput {
                index: 0,
                text: "When".into(),
                kind: "word".into(),
            },
            SenseGroupTokenInput {
                index: 2,
                text: "it".into(),
                kind: "word".into(),
            },
            SenseGroupTokenInput {
                index: 4,
                text: "rains".into(),
                kind: "word".into(),
            },
            SenseGroupTokenInput {
                index: 5,
                text: ",".into(),
                kind: "punctuation".into(),
            },
            SenseGroupTokenInput {
                index: 7,
                text: "we".into(),
                kind: "word".into(),
            },
            SenseGroupTokenInput {
                index: 9,
                text: "stay".into(),
                kind: "word".into(),
            },
            SenseGroupTokenInput {
                index: 11,
                text: "inside".into(),
                kind: "word".into(),
            },
        ],
        protected_spans: vec![SenseGroupProtectedSpan {
            start_token_index: 9,
            end_token_index: 11,
        }],
        candidate_boundary_after_token_indices: vec![4],
    }
}

enum Provider {
    OpenAi(LlmSemanticProvider<OpenAiChatAdapter>),
    Anthropic(LlmSemanticProvider<AnthropicMessagesAdapter>),
}

impl Provider {
    fn build(protocol: Protocol, base_url: &str, timeout: Duration) -> Self {
        match protocol {
            Protocol::OpenAi => Self::OpenAi(LlmSemanticProvider::new(
                OpenAiChatAdapter::new(base_url, "m", Some("k".into()), timeout).unwrap(),
            )),
            Protocol::Anthropic => Self::Anthropic(LlmSemanticProvider::new(
                AnthropicMessagesAdapter::new(base_url, "m", Some("k".into()), None, timeout)
                    .unwrap(),
            )),
        }
    }

    fn sense_groups(&self) -> &dyn SenseGroupPartitionProvider {
        match self {
            Self::OpenAi(provider) => provider,
            Self::Anthropic(provider) => provider,
        }
    }

    async fn probe(&self) -> Result<CapabilityClaim, LlmProviderError> {
        match self {
            Self::OpenAi(provider) => provider.adapter().probe_structured_output().await,
            Self::Anthropic(provider) => provider.adapter().probe_structured_output().await,
        }
    }

    async fn partition(
        &self,
        input: &SenseGroupPartitionRequest,
    ) -> Result<application::SenseGroupPartitionDraft, LlmProviderError> {
        self.sense_groups().partition_sense_groups(input).await
    }
}

const TIMEOUT: Duration = Duration::from_secs(5);

async fn run_partition(
    protocol: Protocol,
    canned: Canned,
    timeout: Duration,
) -> Result<application::SenseGroupPartitionDraft, LlmProviderError> {
    let base = spawn(canned).await;
    Provider::build(protocol, &base, timeout)
        .partition(&request())
        .await
}

#[tokio::test]
async fn sense_group_partition_is_protocol_neutral() {
    let output = serde_json::json!({ "boundary_after_token_indices": [4] });
    let mut results = Vec::new();
    for protocol in ALL_PROTOCOLS {
        let draft = run_partition(
            protocol,
            success_envelope(protocol, "sense_group_partition", output.clone()),
            TIMEOUT,
        )
        .await
        .expect("partition");
        assert_eq!(
            draft.prompt_version.as_deref(),
            Some("sense-group-partition/v1")
        );
        assert_eq!(draft.boundary_after_token_indices, vec![4]);
        results.push(draft.boundary_after_token_indices);
    }
    assert_eq!(results[0], results[1]);
}

#[tokio::test]
async fn malformed_output_maps_to_schema_invalid_for_both_protocols() {
    let output = serde_json::json!({ "boundary_after_token_indices": "invalid" });
    for protocol in ALL_PROTOCOLS {
        let error = run_partition(
            protocol,
            success_envelope(protocol, "sense_group_partition", output.clone()),
            TIMEOUT,
        )
        .await
        .unwrap_err();
        assert!(matches!(error, LlmProviderError::SchemaInvalid { .. }));
    }
}

#[tokio::test]
async fn refusal_and_truncation_map_to_neutral_errors() {
    for protocol in ALL_PROTOCOLS {
        let refusal = match protocol {
            Protocol::OpenAi => serde_json::json!({
                "model": "m",
                "choices": [{ "finish_reason": "stop", "message": { "content": null, "refusal": "I can't help with that." } }]
            }),
            Protocol::Anthropic => serde_json::json!({
                "model": "m", "stop_reason": "refusal", "content": []
            }),
        };
        let error = run_partition(
            protocol,
            Canned {
                status: StatusCode::OK,
                body: refusal,
                retry_after: None,
                delay_ms: 0,
            },
            TIMEOUT,
        )
        .await
        .unwrap_err();
        assert!(matches!(error, LlmProviderError::Refusal { .. }));

        let truncated = match protocol {
            Protocol::OpenAi => serde_json::json!({
                "model": "m",
                "choices": [{ "finish_reason": "length", "message": { "content": "{" } }]
            }),
            Protocol::Anthropic => serde_json::json!({
                "model": "m", "stop_reason": "max_tokens", "content": []
            }),
        };
        let error = run_partition(
            protocol,
            Canned {
                status: StatusCode::OK,
                body: truncated,
                retry_after: None,
                delay_ms: 0,
            },
            TIMEOUT,
        )
        .await
        .unwrap_err();
        assert_eq!(error, LlmProviderError::Truncated);
    }
}

#[tokio::test]
async fn provider_failures_are_normalized_without_leaking_auth_payloads() {
    for protocol in ALL_PROTOCOLS {
        let rate_limit = run_partition(
            protocol,
            Canned {
                status: StatusCode::TOO_MANY_REQUESTS,
                body: serde_json::json!({ "error": "slow down" }),
                retry_after: Some("2".into()),
                delay_ms: 0,
            },
            TIMEOUT,
        )
        .await
        .unwrap_err();
        assert_eq!(
            rate_limit,
            LlmProviderError::RateLimit {
                retry_after_ms: Some(2000)
            }
        );

        let auth = run_partition(
            protocol,
            Canned {
                status: StatusCode::UNAUTHORIZED,
                body: serde_json::json!({ "error": "bad key sk-secret-echoed" }),
                retry_after: None,
                delay_ms: 0,
            },
            TIMEOUT,
        )
        .await
        .unwrap_err();
        assert_eq!(auth, LlmProviderError::Auth);
        assert!(
            !serde_json::to_string(&auth)
                .unwrap()
                .contains("sk-secret-echoed")
        );
    }
}

#[tokio::test]
async fn slow_provider_maps_to_timeout() {
    for protocol in ALL_PROTOCOLS {
        let mut canned = success_envelope(
            protocol,
            "sense_group_partition",
            serde_json::json!({ "boundary_after_token_indices": [4] }),
        );
        canned.delay_ms = 400;
        let error = run_partition(protocol, canned, Duration::from_millis(80))
            .await
            .unwrap_err();
        assert_eq!(error, LlmProviderError::Timeout);
    }
}

#[tokio::test]
async fn probe_measures_structured_output_support() {
    for protocol in ALL_PROTOCOLS {
        let base = spawn(success_envelope(
            protocol,
            "capability_probe",
            serde_json::json!({ "ok": true }),
        ))
        .await;
        let claim = Provider::build(protocol, &base, TIMEOUT)
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
}

fn profile_for(protocol: Protocol, base_url: &str) -> LlmProviderProfile {
    let adapter_kind = match protocol {
        Protocol::OpenAi => LlmAdapterKind::OpenAiChatCompletions,
        Protocol::Anthropic => LlmAdapterKind::AnthropicMessages,
    };
    LlmProviderProfile {
        id: llm_provider_profile_id(adapter_kind, base_url, "m"),
        display_name: "test".into(),
        adapter_kind,
        protocol_version: None,
        base_url: base_url.into(),
        model_id: "m".into(),
        auth_ref: None,
        timeout_ms: 5000,
        max_retries: 0,
        batch_policy: domain::LlmBatchPolicy::default(),
        cost_budget: None,
        retention: DataRetentionPreference::Unknown,
        allowed_uses: vec![LlmUse::SenseGroupPartition],
        capability: ProviderCapability::unknown(),
        created_at_ms: 0,
    }
}

#[tokio::test]
async fn factory_builds_the_retained_sense_group_capability() {
    let output = serde_json::json!({ "boundary_after_token_indices": [4] });
    for protocol in ALL_PROTOCOLS {
        let base = spawn(success_envelope(
            protocol,
            "sense_group_partition",
            output.clone(),
        ))
        .await;
        let runtime = LlmSemanticRuntimeFactory::new()
            .build(&profile_for(protocol, &base), Some("k".into()))
            .expect("runtime");
        let draft = runtime
            .sense_groups()
            .partition_sense_groups(&request())
            .await
            .expect("partition");
        assert_eq!(draft.boundary_after_token_indices, vec![4]);
        let probe_base = spawn(success_envelope(
            protocol,
            "capability_probe",
            serde_json::json!({ "ok": true }),
        ))
        .await;
        let probe_runtime = LlmSemanticRuntimeFactory::new()
            .build(&profile_for(protocol, &probe_base), Some("k".into()))
            .expect("probe runtime");
        let claim = probe_runtime
            .probe_structured_output()
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
}

async fn capture_request(
    State(captured): State<Arc<std::sync::Mutex<Option<serde_json::Value>>>>,
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    *captured.lock().unwrap() = Some(body);
    Json(serde_json::json!({
        "model": "m",
        "choices": [{
            "finish_reason": "stop",
            "message": { "content": "{\"ok\":true}", "refusal": null }
        }]
    }))
}

#[tokio::test]
async fn openai_adapter_uses_json_object_mode_with_schema_in_prompt() {
    use std::sync::Mutex;

    let captured: Arc<Mutex<Option<serde_json::Value>>> = Arc::new(Mutex::new(None));
    let router = Router::new()
        .route("/chat/completions", post(capture_request))
        .with_state(captured.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    let adapter = OpenAiChatAdapter::new(
        format!("http://{addr}"),
        "deepseek-v4-flash",
        Some("k".into()),
        TIMEOUT,
    )
    .unwrap();
    adapter.probe_structured_output().await.expect("probe");

    let body = captured.lock().unwrap().clone().expect("request captured");
    assert_eq!(body["response_format"]["type"], "json_object");
    let system = body["messages"][0]["content"].as_str().unwrap();
    assert!(system.to_lowercase().contains("json"));
    assert!(system.contains("ok"));
    assert_eq!(body["thinking"]["type"], "disabled");
}
