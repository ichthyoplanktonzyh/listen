use super::*;
use axum::body::to_bytes;
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
use persistence_sqlite::SqliteRepository;
use std::collections::BTreeSet;
use tower::ServiceExt;

mod semantic_embedding;

fn test_state() -> ApiState {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    ApiState::new(
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
        .with_llm_provider_profile_repository(repo.clone())
        .with_realtime_conversation_repository(repo.clone())
        .with_reading_position_repository(repo.clone()),
        repo,
        "secret",
    )
}

fn test_app() -> Router {
    router(test_state())
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
mod media_subtitles;
mod openapi;
mod phonetic_analysis;
mod practice;
mod reading;
mod semantic;
mod speech_language;
mod syntax;
mod timelines;
mod tts;
