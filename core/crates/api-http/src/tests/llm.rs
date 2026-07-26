//! Phase 3.12 provider surface HTTP tests. The default in-memory secret store
//! stands in for the OS keychain; a local fake server stands in for the model
//! endpoint, so the whole path runs offline.

use super::*;
use axum::routing::post;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use tokio::net::TcpListener;

async fn fake_ok(State(body): State<serde_json::Value>) -> Json<serde_json::Value> {
    Json(body)
}

/// Spawns a fake OpenAI-compatible endpoint returning `body` for chat calls.
async fn spawn_fake_openai(body: serde_json::Value) -> String {
    let router = Router::new()
        .route("/chat/completions", post(fake_ok))
        .with_state(body);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    format!("http://{addr}")
}

#[derive(Clone)]
struct ConcurrentFake {
    body: serde_json::Value,
    active: Arc<AtomicUsize>,
    max_active: Arc<AtomicUsize>,
}

async fn fake_concurrent(State(state): State<ConcurrentFake>) -> Json<serde_json::Value> {
    let active = state.active.fetch_add(1, Ordering::SeqCst) + 1;
    state.max_active.fetch_max(active, Ordering::SeqCst);
    tokio::time::sleep(std::time::Duration::from_millis(40)).await;
    state.active.fetch_sub(1, Ordering::SeqCst);
    Json(state.body)
}

async fn spawn_concurrent_fake_openai(body: serde_json::Value) -> (String, Arc<AtomicUsize>) {
    let max_active = Arc::new(AtomicUsize::new(0));
    let state = ConcurrentFake {
        body,
        active: Arc::new(AtomicUsize::new(0)),
        max_active: max_active.clone(),
    };
    let router = Router::new()
        .route("/chat/completions", post(fake_concurrent))
        .with_state(state);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    (format!("http://{addr}"), max_active)
}

fn openai_content_envelope(content: &str) -> serde_json::Value {
    serde_json::json!({
        "model": "fake",
        "choices": [ { "finish_reason": "stop", "message": { "content": content, "refusal": null } } ]
    })
}

async fn post_json(
    app: &Router,
    uri: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app
        .clone()
        .oneshot(
            Request::post(uri)
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let json = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or_else(|_| {
            serde_json::Value::String(String::from_utf8_lossy(&bytes).to_string())
        })
    };
    (status, json)
}

fn register_body(base_url: &str, secret: Option<&str>) -> serde_json::Value {
    let mut body = serde_json::json!({
        "display_name": "Test Provider",
        "adapter_kind": "openai_chat_completions",
        "base_url": base_url,
        "model_id": "m",
        "retention": "unknown",
        "allowed_uses": ["semantic_judgment"]
    });
    if let Some(secret) = secret {
        body["secret"] = serde_json::json!(secret);
    }
    body
}

#[tokio::test]
async fn register_lists_and_probes_provider_without_leaking_secret() {
    let base = spawn_fake_openai(openai_content_envelope("{\"ok\": true}")).await;
    let app = test_app();

    // Register with a credential.
    let (status, view) = post_json(
        &app,
        "/v1/llm/providers",
        register_body(&base, Some("sk-secret-777")),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "register failed: {view}");
    assert_eq!(view["has_credential"], true);
    // The response is a view with no auth_ref and no secret anywhere.
    assert!(view.get("auth_ref").is_none());
    assert!(!view.to_string().contains("sk-secret-777"));
    let id = view["id"].as_str().unwrap().to_string();

    // It shows up in the list, still without the secret.
    let list = app
        .clone()
        .oneshot(
            Request::get("/v1/llm/providers")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(list.status(), StatusCode::OK);
    let list_body: serde_json::Value =
        serde_json::from_slice(&to_bytes(list.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(list_body.as_array().unwrap().len(), 1);
    assert!(!list_body.to_string().contains("sk-secret-777"));

    // Probe actually measures structured-output support against the endpoint.
    let (status, probe) = post_json(
        &app,
        &format!("/v1/llm/providers/{id}/probe"),
        serde_json::Value::Null,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(probe["structured_output"]["state"], "probed");
    assert_eq!(probe["structured_output"]["supported"], true);
}

#[tokio::test]
async fn delete_removes_provider() {
    let base = spawn_fake_openai(openai_content_envelope("{\"ok\": true}")).await;
    let app = test_app();
    let (_, view) = post_json(
        &app,
        "/v1/llm/providers",
        register_body(&base, Some("sk-x")),
    )
    .await;
    let id = view["id"].as_str().unwrap().to_string();

    let deleted = app
        .clone()
        .oneshot(
            Request::delete(format!("/v1/llm/providers/{id}"))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(deleted.status(), StatusCode::NO_CONTENT);

    let missing = app
        .oneshot(
            Request::get(format!("/v1/llm/providers/{id}"))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn generate_rubric_returns_a_draft_without_persisting() {
    let rubric_json = serde_json::json!({
        "points": [
            {
                "importance": "required",
                "statement": "A quake happened.",
                "accepted_paraphrase_notes": null
            },
            {
                "importance": "optional",
                "statement": "It was near the coast.",
                "accepted_paraphrase_notes": "coast/shore"
            }
        ]
    })
    .to_string();
    let base = spawn_fake_openai(openai_content_envelope(&rubric_json)).await;
    let app = test_app();
    let (_, view) = post_json(
        &app,
        "/v1/llm/providers",
        register_body(&base, Some("sk-x")),
    )
    .await;
    let id = view["id"].as_str().unwrap().to_string();

    let (status, draft) = post_json(
        &app,
        &format!("/v1/llm/providers/{id}/rubric"),
        serde_json::json!({
            "purpose": "reading_comprehension",
            "source_language": "en",
            "response_language": "zh",
            "transcript_snapshot": "The quake struck at dawn near the coast."
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "generate failed: {draft}");
    let points = draft["points"].as_array().unwrap();
    assert_eq!(points.len(), 2);
    assert_eq!(points[0]["importance"], "required");
    assert_eq!(points[0]["statement"], "A quake happened.");
    assert_eq!(points[1]["accepted_paraphrase_notes"], "coast/shore");
    // Draft only: no rubric identity/version/source is minted by the provider.
    assert!(draft.get("id").is_none());
    assert!(draft.get("version").is_none());
}

#[tokio::test]
async fn judge_via_unknown_provider_is_not_found() {
    let app = test_app();
    let (status, _) = post_json(
        &app,
        "/v1/llm/providers/deadbeef/judge",
        serde_json::json!({ "attempt_id": "whatever", "response_revision": 1 }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn sense_group_provider_generates_a_valid_persisted_analysis() {
    let (base, max_active) = spawn_concurrent_fake_openai(openai_content_envelope(
        "{\"boundary_after_token_indices\": []}",
    ))
    .await;
    let app = test_app();
    let mut provider_body = register_body(&base, Some("sk-x"));
    provider_body["allowed_uses"] = serde_json::json!(["sense_group_partition"]);
    provider_body["max_retries"] = serde_json::json!(1);
    let (status, provider) = post_json(&app, "/v1/llm/providers", provider_body).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "provider registration failed: {provider}"
    );

    let (status, media) = post_json(
        &app,
        "/v1/media",
        serde_json::json!({
            "path": "/tmp/llm-sense-groups.mp4",
            "fingerprint": "llm-sense-groups-media",
            "title": "LLM Sense Groups",
            "kind": "video"
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "media registration failed: {media}");
    let fixture = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../testdata/subtitles/timeline.srt"
    );
    let (status, track) = post_json(
        &app,
        &format!("/v1/media/{}/subtitles", media["id"].as_str().unwrap()),
        serde_json::json!({ "path": fixture, "language": "en" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "subtitle import failed: {track}");

    let (status, analysis) = post_json(
        &app,
        &format!(
            "/v1/llm/providers/{}/sense-groups",
            provider["id"].as_str().unwrap()
        ),
        serde_json::json!({
            "track_id": track["id"],
            "status": "candidate"
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "generation failed: {analysis}");
    assert_eq!(analysis["provider_id"], "llm-sense-group");
    assert_eq!(analysis["algorithm"], "hybrid_rule_llm_partition_v1");
    assert_eq!(analysis["metrics_json"]["llm_sentence_count"], 4);
    assert_eq!(analysis["metrics_json"]["fallback_sentence_count"], 0);
    assert_eq!(analysis["metrics_json"]["batch_sentence_count"], 4);
    assert_eq!(analysis["metrics_json"]["max_concurrency"], 4);
    assert!(
        max_active.load(Ordering::SeqCst) >= 2,
        "track sentences should be analyzed concurrently"
    );
    assert!(
        analysis["groups"]
            .as_array()
            .is_some_and(|groups| !groups.is_empty())
    );
    assert!(analysis["groups"].as_array().unwrap().iter().all(|group| {
        group["sources"]
            .as_array()
            .is_some_and(|sources| sources.iter().any(|source| source == "language_model"))
    }));

    // A syntactically valid JSON response with impossible token indices is
    // retried once per sentence, then safely replaced by rule output.
    let invalid_base = spawn_fake_openai(openai_content_envelope(
        "{\"boundary_after_token_indices\": [999]}",
    ))
    .await;
    let mut invalid_provider_body = register_body(&invalid_base, None);
    invalid_provider_body["allowed_uses"] = serde_json::json!(["sense_group_partition"]);
    invalid_provider_body["max_retries"] = serde_json::json!(1);
    let (_, invalid_provider) = post_json(&app, "/v1/llm/providers", invalid_provider_body).await;
    let (status, fallback) = post_json(
        &app,
        &format!(
            "/v1/llm/providers/{}/sense-groups",
            invalid_provider["id"].as_str().unwrap()
        ),
        serde_json::json!({ "track_id": track["id"] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "fallback failed: {fallback}");
    assert_eq!(fallback["metrics_json"]["llm_sentence_count"], 0);
    assert_eq!(fallback["metrics_json"]["fallback_sentence_count"], 4);
    assert_eq!(fallback["metrics_json"]["retry_count"], 4);
    assert!(fallback["groups"].as_array().unwrap().iter().all(|group| {
        group["sources"]
            .as_array()
            .is_some_and(|sources| sources.iter().all(|source| source != "language_model"))
    }));
}
