use super::*;
use axum::body::to_bytes;
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
use persistence_sqlite::SqliteRepository;
use std::collections::BTreeSet;
use std::io;
use std::sync::Mutex;
use tower::ServiceExt;

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
        .with_corpus_index_repository(repo.clone())
        .with_llm_provider_profile_repository(repo.clone())
        .with_realtime_conversation_repository(repo.clone())
        .with_recording_repository(repo.clone())
        .with_material_repository(repo.clone())
        .with_package_lifecycle_repository(repo.clone())
        .with_capability_attempt_repository(repo.clone())
        .with_source_identity_repository(repo.clone()),
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
mod speech_language;
mod syntax;
mod timelines;
mod tts;
