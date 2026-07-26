//! Phase 3.12 provider surface HTTP tests. The default in-memory secret store
//! stands in for the OS keychain; a local fake server stands in for the model
//! endpoint, so the whole path runs offline.

use super::*;
use axum::routing::post;
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
