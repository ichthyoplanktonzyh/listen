use super::*;
use axum::body::to_bytes;
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
use persistence_sqlite::SqliteRepository;
use std::collections::BTreeSet;
use tower::ServiceExt;

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
        .with_learning_loop_repositories(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        )
        .with_difficulty_repository(repo.clone()),
        repo,
        "secret",
    )
}

fn test_app() -> Router {
    router(test_state())
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
mod media_subtitles;
mod openapi;
mod phonetic_analysis;
mod practice;
mod speech_language;
mod timelines;
