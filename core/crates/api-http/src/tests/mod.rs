use super::*;
use axum::body::to_bytes;
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
use persistence_sqlite::SqliteRepository;
use std::collections::BTreeSet;
use std::io;
use std::sync::Mutex;
use tower::ServiceExt;

mod semantic_embedding;

#[derive(Clone, Default)]
struct CapturedLogs(Arc<Mutex<Vec<u8>>>);

struct CapturedWriter(Arc<Mutex<Vec<u8>>>);

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for CapturedLogs {
    type Writer = CapturedWriter;

    fn make_writer(&'a self) -> Self::Writer {
        CapturedWriter(self.0.clone())
    }
}

impl io::Write for CapturedWriter {
    fn write(&mut self, buffer: &[u8]) -> io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buffer);
        Ok(buffer.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn test_state_with_repository() -> (ApiState, Arc<SqliteRepository>) {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let state = ApiState::new(
        AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        )
        .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
        .with_recording_repository(repo.clone())
        .with_difficulty_repository(repo.clone())
        .with_corpus_index_repository(repo.clone())
        .with_coach_dashboard_repository(repo.clone())
        .with_semantic_task_repository(repo.clone())
        .with_production_corpus_repository(repo.clone())
        .with_personal_expression_repository(repo.clone())
        .with_llm_provider_profile_repository(repo.clone())
        .with_realtime_conversation_repository(repo.clone())
        .with_reading_position_repository(repo.clone())
        .with_material_repository(repo.clone())
        .with_package_lifecycle_repository(repo.clone()),
        repo.clone(),
        "secret",
    );
    (state, repo)
}

fn test_state() -> ApiState {
    test_state_with_repository().0
}

fn test_app() -> Router {
    router(test_state())
}

#[tokio::test(flavor = "current_thread")]
async fn application_executor_keeps_async_runtime_responsive_during_blocking_work() {
    let executor = test_state().application;
    let (started_tx, started_rx) = tokio::sync::oneshot::channel();
    let (release_tx, release_rx) = std::sync::mpsc::channel();
    let operation = tokio::spawn(async move {
        executor
            .execute("test.blocking", move |_| {
                started_tx.send(()).unwrap();
                release_rx.recv().unwrap();
                Ok(7_u8)
            })
            .await
    });
    started_rx.await.unwrap();

    let heartbeat = tokio::spawn(async {
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        42_u8
    });
    assert_eq!(
        tokio::time::timeout(std::time::Duration::from_millis(100), heartbeat)
            .await
            .expect("async runtime heartbeat must not be blocked")
            .unwrap(),
        42
    );

    release_tx.send(()).unwrap();
    assert_eq!(operation.await.unwrap().unwrap(), 7);
}

#[tokio::test(flavor = "current_thread")]
async fn application_executor_drives_mixed_async_work_off_the_runtime_worker() {
    let executor = test_state().application;
    let (started_tx, started_rx) = tokio::sync::oneshot::channel();
    let (release_tx, release_rx) = std::sync::mpsc::channel();
    let operation = tokio::spawn(async move {
        executor
            .execute_async("test.mixed", move |_| async move {
                started_tx.send(()).unwrap();
                release_rx.recv().unwrap();
                tokio::time::sleep(std::time::Duration::from_millis(1)).await;
                Ok(9_u8)
            })
            .await
    });
    started_rx.await.unwrap();

    let heartbeat = tokio::time::timeout(
        std::time::Duration::from_millis(100),
        tokio::time::sleep(std::time::Duration::from_millis(10)),
    );
    heartbeat
        .await
        .expect("mixed application future must not block the async runtime");

    release_tx.send(()).unwrap();
    assert_eq!(operation.await.unwrap().unwrap(), 9);
}

#[tokio::test]
async fn internal_repository_details_are_redacted_from_http_errors() {
    let logs = CapturedLogs::default();
    let subscriber = tracing_subscriber::fmt()
        .json()
        .without_time()
        .with_writer(logs.clone())
        .finish();
    let response = tracing::subscriber::with_default(subscriber, || {
        ApiError::from(ApplicationError::Repository(
            "database /private/user/listen.sqlite: secret_table failed".to_owned(),
        ))
        .into_response()
    });
    assert_eq!(response.status(), StatusCode::INTERNAL_SERVER_ERROR);

    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let body = String::from_utf8(body.to_vec()).unwrap();
    assert!(body.contains("\"code\":\"repository_error\""));
    assert!(body.contains("local data operation failed"));
    assert!(!body.contains("/private/user"));
    assert!(!body.contains("secret_table"));

    let diagnostics = String::from_utf8(logs.0.lock().unwrap().clone()).unwrap();
    assert!(diagnostics.contains("/private/user/listen.sqlite"));
    assert!(diagnostics.contains("secret_table"));
    let body: serde_json::Value = serde_json::from_str(&body).unwrap();
    assert!(diagnostics.contains(body["correlation_id"].as_str().unwrap()));
}

#[tokio::test(flavor = "current_thread")]
async fn every_response_has_a_correlation_id_and_completion_diagnostic() {
    let logs = CapturedLogs::default();
    let subscriber = tracing_subscriber::fmt()
        .json()
        .without_time()
        .with_writer(logs.clone())
        .finish();
    let _guard = tracing::subscriber::set_default(subscriber);
    let response = test_app()
        .oneshot(Request::get("/v1/media").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    let header = response
        .headers()
        .get("x-correlation-id")
        .unwrap()
        .to_str()
        .unwrap()
        .to_owned();
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(body["correlation_id"], header);

    let diagnostics = String::from_utf8(logs.0.lock().unwrap().clone()).unwrap();
    assert!(diagnostics.contains("\"event\":\"api.request.completed\""));
    assert!(diagnostics.contains(&header));
    assert!(!diagnostics.contains("Bearer secret"));
}

#[tokio::test]
async fn personal_expression_is_explicit_versioned_and_channel_honest() {
    let app = test_app();
    let create = app
        .clone()
        .oneshot(
            Request::post("/v1/personal-expression/patterns")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "language":"en",
                        "source":{"kind":"reading","text":"I ended up fixing it.","media_id":"media-that-may-disappear","media_fingerprint":"source-fp","start_ms":10,"end_ms":20},
                        "name":"Ended up",
                        "pattern_text":"I ended up {result}.",
                        "slots":[{"name":"result","required":true}],
                        "note":"My real outcomes",
                        "system_construction_id":null
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(create.status(), StatusCode::CREATED);
    let body = to_bytes(create.into_body(), usize::MAX).await.unwrap();
    let pattern: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let pattern_id = pattern["id"].as_str().unwrap();
    let version_id = pattern["current_version"]["id"].as_str().unwrap();

    let writing = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/personal-expression/patterns/{pattern_id}/attempts"
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "pattern_version_id":version_id,
                    "channel":"writing",
                    "assistance":"no_text",
                    "response_text":"I ended up fixing the release after dinner.",
                    "self_assessment":"expressed"
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(writing.status(), StatusCode::CREATED);

    let invalid_speaking = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/personal-expression/patterns/{pattern_id}/attempts"
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "pattern_version_id":version_id,
                    "channel":"speaking",
                    "assistance":"no_text",
                    "response_text":"I ended up fixing it.",
                    "raw_transcript":"raw",
                    "self_assessment":"partly_expressed"
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(invalid_speaking.status(), StatusCode::BAD_REQUEST);

    let export = app
        .clone()
        .oneshot(
            Request::get("/v1/personal-expression/export?language=en")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(export.status(), StatusCode::OK);
    let body = to_bytes(export.into_body(), usize::MAX).await.unwrap();
    let bundle: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(bundle["schema"], "llplayer.personal-expression.v1");
    assert_eq!(
        bundle["patterns"][0]["versions"].as_array().unwrap().len(),
        1
    );
    assert_eq!(
        bundle["patterns"][0]["attempts"].as_array().unwrap().len(),
        1
    );

    let read = app
        .oneshot(
            Request::get(format!("/v1/personal-expression/patterns/{pattern_id}"))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(read.status(), StatusCode::OK);
    let body = to_bytes(read.into_body(), usize::MAX).await.unwrap();
    let persisted: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(persisted["source"]["text"], "I ended up fixing it.");
    assert!(persisted["current_version"]["system_construction_id"].is_null());
}

#[tokio::test]
async fn realtime_provider_registration_is_write_only_and_listable() {
    let app = test_app();
    let secret = "realtime-api-secret-not-returned";
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/realtime/providers")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "display_name":"QA OpenAI",
                        "adapter_kind":"open_ai_realtime",
                        "base_url":"wss://api.openai.com/v1/realtime",
                        "model_id":"gpt-realtime",
                        "voice":"marin",
                        "secret":secret
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let text = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(!text.contains(secret));
    assert!(!text.contains("auth_ref"));
    assert!(text.contains("has_credential"));

    let response = app
        .oneshot(
            Request::get("/v1/realtime/providers")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn local_realtime_provider_registration_is_keyless() {
    let app = test_app();
    let response = app
        .oneshot(
            Request::post("/v1/realtime/providers")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "display_name":"Local cascade",
                        "adapter_kind":"local_cascade_realtime",
                        "base_url":"ws://127.0.0.1:8765/v1/realtime",
                        "model_id":"hf-speech-to-speech-ora",
                        "voice":"local"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(body["adapter_kind"], "local_cascade_realtime");
    assert_eq!(body["has_credential"], false);
    assert!(body.get("auth_ref").is_none());
}

#[tokio::test]
async fn new_remote_realtime_provider_still_requires_a_credential() {
    let app = test_app();
    let response = app
        .oneshot(
            Request::post("/v1/realtime/providers")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "display_name":"Remote without secret",
                        "adapter_kind":"open_ai_realtime",
                        "base_url":"wss://api.openai.com/v1/realtime",
                        "model_id":"gpt-realtime",
                        "voice":"marin"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn realtime_history_lists_sessions_and_ordered_turns() {
    let app = test_app();
    let profile_response = app
        .clone()
        .oneshot(
            Request::post("/v1/realtime/providers")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "display_name":"History provider",
                        "adapter_kind":"open_ai_realtime",
                        "base_url":"wss://api.example/realtime",
                        "model_id":"realtime-model",
                        "voice":"marin",
                        "secret":"provider-secret"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let profile: serde_json::Value = serde_json::from_slice(
        &to_bytes(profile_response.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();
    let profile_id = profile["id"].as_str().unwrap();
    let session_id = "history-session";
    let save_session = app
        .clone()
        .oneshot(
            Request::post("/v1/realtime/sessions")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "id":session_id,
                        "profile_id":profile_id,
                        "language":"en",
                        "context":null,
                        "status":"active",
                        "started_at_ms":10,
                        "ended_at_ms":null,
                        "failure_kind":null
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(save_session.status(), StatusCode::OK);

    for (sequence, id, text) in [
        (2, "assistant-later", "Second"),
        (1, "assistant-first", "First"),
    ] {
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/realtime/turns")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "id":id,
                            "session_id":session_id,
                            "sequence":sequence,
                            "role":"assistant",
                            "status":"finalized",
                            "assistance":"unknown",
                            "provider_transcript":{
                                "text":text,
                                "provider_item_id":null,
                                "received_at_ms":20
                            },
                            "local_transcript":null,
                            "recording_asset_id":null,
                            "started_at_ms":11,
                            "ended_at_ms":20,
                            "failure_kind":null
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    let sessions = app
        .clone()
        .oneshot(
            Request::get("/v1/realtime/sessions")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let sessions: serde_json::Value =
        serde_json::from_slice(&to_bytes(sessions.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(sessions[0]["id"], session_id);

    let turns = app
        .oneshot(
            Request::get(format!("/v1/realtime/sessions/{session_id}/turns"))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let turns: serde_json::Value =
        serde_json::from_slice(&to_bytes(turns.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(turns[0]["sequence"], 1);
    assert_eq!(turns[1]["sequence"], 2);
}

#[tokio::test]
async fn coach_dashboard_is_channel_ready_and_uses_starter_state() {
    let app = test_app();
    let response = app
        .clone()
        .oneshot(
            Request::get("/v1/coach/dashboard?days=7")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(body["channels"][0]["channel"], "listening");
    assert_eq!(body["channels"][1]["status"], "unassessed");
    assert_eq!(body["starter_checklist"].as_array().unwrap().len(), 3);
    let evidence = app
        .oneshot(
            Request::get("/v1/coach/evidence?metric=practice_attempts&days=7")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(evidence.status(), StatusCode::OK);
    let evidence_body: serde_json::Value =
        serde_json::from_slice(&to_bytes(evidence.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(evidence_body, serde_json::json!([]));
}

async fn setup_phonetic_track(app: &Router, fingerprint: &str) -> serde_json::Value {
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "path": format!("/tmp/{fingerprint}.mp4"),
                        "fingerprint": fingerprint,
                        "title": fingerprint,
                        "kind": "video"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let media: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let fixture = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../testdata/subtitles/timeline.srt"
    );
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/media/{}/subtitles",
                media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({"path": fixture, "language": "en"}).to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap()
}

async fn wait_for_phonetic_job(app: &Router, job_id: &str, expected: &[&str]) -> serde_json::Value {
    for _ in 0..100 {
        let response = app
            .clone()
            .oneshot(
                Request::get(format!("/v1/phonetic-analysis/jobs/{job_id}"))
                    .header(AUTHORIZATION, "Bearer secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let value: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        if expected.contains(&value["status"].as_str().unwrap()) {
            return value;
        }
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
    }
    panic!("phonetic analysis job did not reach {expected:?}");
}

mod general;
mod llm;
mod material;
mod media_subtitles;
mod openapi;
mod package_lifecycle;
mod phonetic_analysis;
mod practice;
mod reading;
mod semantic;
mod speech_language;
mod syntax;
mod timelines;
mod tts;
