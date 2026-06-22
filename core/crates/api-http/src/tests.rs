use super::*;
use axum::body::to_bytes;
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
use persistence_sqlite::SqliteRepository;
use tower::ServiceExt;

fn test_app() -> Router {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    router(ApiState::new(
        AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        ),
        repo,
        "secret",
    ))
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

#[tokio::test]
async fn health_is_public_and_versioned() {
    let response = test_app()
        .oneshot(Request::get("/v1/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn protected_routes_require_token() {
    let response = test_app()
        .oneshot(Request::post("/v1/media").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn chunk_provider_catalog_reports_optional_licensed_model() {
    let response = test_app()
        .oneshot(
            Request::get("/v1/chunk/providers")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(body[0]["license"], "MIT");
    assert_eq!(body[0]["optional"], true);
    assert_eq!(body[0]["available"], true);
}

#[tokio::test]
async fn media_registration_is_idempotent_over_http() {
    let app = test_app();
    let body = serde_json::json!({
        "path": "/tmp/a.mp4",
        "fingerprint": "abc",
        "title": "A",
        "kind": "video",
        "duration_ms": 1000
    })
    .to_string();
    let request = || {
        Request::post("/v1/media")
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(body.clone()))
            .unwrap()
    };
    let first = app.clone().oneshot(request()).await.unwrap();
    assert_eq!(first.status(), StatusCode::OK);
    let first_body = to_bytes(first.into_body(), usize::MAX).await.unwrap();
    let second = app.oneshot(request()).await.unwrap();
    assert_eq!(second.status(), StatusCode::OK);
    let second_body = to_bytes(second.into_body(), usize::MAX).await.unwrap();
    let first: serde_json::Value = serde_json::from_slice(&first_body).unwrap();
    let second: serde_json::Value = serde_json::from_slice(&second_body).unwrap();
    assert_eq!(first["id"], second["id"]);
}

#[tokio::test]
async fn imports_and_reads_complete_subtitle_timeline() {
    let app = test_app();
    let media = serde_json::json!({
        "path": "/tmp/a.mp4",
        "fingerprint": "subtitle-media",
        "title": "A",
        "kind": "video"
    })
    .to_string();
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(media))
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
    let request = serde_json::json!({"path": fixture, "language": "en"}).to_string();
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/media/{}/subtitles",
                media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(request))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(track["sentences"].as_array().unwrap().len(), 4);
    assert_eq!(track["status"], "available");
    let response = app
        .clone()
        .oneshot(
            Request::get(format!("/v1/subtitles/{}", track["id"].as_str().unwrap()))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/chunk-partitions",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let partitions: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(partitions.as_array().unwrap().len(), 4);
    assert!(
        partitions[0]["chunks"]
            .as_array()
            .is_some_and(|chunks| !chunks.is_empty())
    );

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/word-timing-diagnostics",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let timing_diagnostics: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(timing_diagnostics.as_array().unwrap().len(), 4);
    assert!(timing_diagnostics[0]["boundaries"].as_array().is_some());

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/chunk-diagnostics",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let diagnostics: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(diagnostics.as_array().unwrap().len(), 4);
    assert!(diagnostics[0]["candidates"].as_array().is_some());

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/archive",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let archived: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(archived["status"], "archived");

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/restore",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let restored: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(restored["status"], "available");

    let response = app
        .clone()
        .oneshot(
            Request::delete(format!("/v1/subtitles/{}", track["id"].as_str().unwrap()))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/media/{}/subtitles",
                media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let resources: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert!(resources.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn exports_lltimeline_document_with_active_word_timeline() {
    let app = test_app();
    let track = setup_phonetic_track(&app, "lltimeline-media").await;
    let sentence = &track["sentences"][0];
    let token = sentence["tokens"]
        .as_array()
        .unwrap()
        .iter()
        .find(|token| token["kind"] == "word")
        .expect("fixture has a word token");
    let start_ms = sentence["start"].as_u64().unwrap() + 10;
    let end_ms = start_ms + 120;
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/word-timelines",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "algorithm_id": "test-aligner",
                    "algorithm_version": "v1",
                    "config_hash": "test-config",
                    "status": "active",
                    "words": [{
                        "sentence_id": sentence["id"],
                        "token_index": token["index"],
                        "text": token["text"],
                        "start_ms": start_ms,
                        "end_ms": end_ms,
                        "confidence": 0.95,
                        "timing_source": "forced_aligned",
                        "provider_id": "test-aligner",
                        "provider_version": "v1"
                    }]
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let timeline: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/chunk-timelines",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({"status": "active"}).to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let chunk_timeline: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(chunk_timeline["status"], "active");
    assert_eq!(chunk_timeline["parent_word_timeline_id"], timeline["id"]);
    assert_eq!(chunk_timeline["precision"], "precise");
    assert!(!chunk_timeline["chunks"].as_array().unwrap().is_empty());

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let mut document: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(document["schema"], domain::LLTIMELINE_SCHEMA_V1);
    assert_eq!(
        document["metadata"]["media"]["fingerprint"],
        "lltimeline-media"
    );
    assert_eq!(document["segments"].as_array().unwrap().len(), 4);
    assert_eq!(document["word_timelines"].as_array().unwrap().len(), 1);
    assert_eq!(document["active_word_timeline_id"], timeline["id"]);
    assert_eq!(document["phone_timelines"].as_array().unwrap().len(), 0);
    assert_eq!(document["chunk_timelines"].as_array().unwrap().len(), 1);
    assert_eq!(document["active_chunk_timeline_id"], chunk_timeline["id"]);
    document["metadata"]["generator"] = serde_json::json!({
        "id": "fixture-production-engine",
        "version": "v2",
        "mode": "production_engine"
    });
    document["artifacts"] = serde_json::json!([
        {
            "kind": "production_report",
            "provider_id": "fixture-production-engine",
            "provider_version": "v2",
            "payload": {
                "readiness": "ready",
                "post_alignment": "mfa"
            }
        }
    ]);

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/lltimeline/import")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(document.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let imported_track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(imported_track["id"], track["id"]);
    assert_eq!(imported_track["sentences"].as_array().unwrap().len(), 4);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/word-timelines/summary",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let summaries: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(summaries.as_array().unwrap().len(), 1);
    assert_eq!(summaries[0]["status"], "active");
    assert_eq!(summaries[0]["lifecycle_stage"], "algorithm_candidate");

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/chunk-timelines/summary",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let chunk_summaries: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(chunk_summaries.as_array().unwrap().len(), 1);
    assert_eq!(chunk_summaries[0]["status"], "active");

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let exported_after_import: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(
        exported_after_import["metadata"]["generator"]["id"],
        "fixture-production-engine"
    );
    assert_eq!(
        exported_after_import["artifacts"][0]["kind"],
        "production_report"
    );

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/word-timelines/{}/publish",
                timeline["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let published: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(
        published["metrics_json"]["lifecycle"]["published"],
        serde_json::Value::Bool(true)
    );

    let response = app
        .clone()
        .oneshot(
            Request::delete(format!(
                "/v1/word-timelines/{}",
                timeline["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn imports_lltimeline_for_current_media_with_user_confirmed_mismatch() {
    let app = test_app();
    let source_track = setup_phonetic_track(&app, "source-media").await;
    let sentence = &source_track["sentences"][0];
    let token = sentence["tokens"]
        .as_array()
        .unwrap()
        .iter()
        .find(|token| token["kind"] == "word")
        .expect("fixture has a word token");
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/word-timelines",
                source_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "algorithm_id": "exchange-aligner",
                    "algorithm_version": "v1",
                    "config_hash": "test-config",
                    "status": "active",
                    "words": [{
                        "sentence_id": sentence["id"],
                        "token_index": token["index"],
                        "text": token["text"],
                        "start_ms": sentence["start"].as_u64().unwrap() + 10,
                        "end_ms": sentence["start"].as_u64().unwrap() + 130,
                        "confidence": 0.95,
                        "timing_source": "forced_aligned",
                        "provider_id": "exchange-aligner",
                        "provider_version": "v1"
                    }]
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                source_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let document: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "path": "/tmp/target-media.mp4",
                        "fingerprint": "target-media",
                        "title": "target-media",
                        "kind": "video"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_media: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/media/{}/lltimeline/import",
                target_media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(document.to_string()))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/media/{}/lltimeline/import?allow_mismatch=true",
                target_media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(document.to_string()))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let imported_track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(imported_track["media_id"], target_media["id"]);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/media/{}/subtitles",
                target_media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let resources: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(resources.as_array().unwrap().len(), 1);
    assert_eq!(resources[0]["id"], imported_track["id"]);

    let response = app
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/word-timings",
                imported_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let timings: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(timings.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn imports_lltimeline_for_current_media_with_existing_resource_fingerprint() {
    let app = test_app();
    let source_track = setup_phonetic_track(&app, "existing-source-media").await;
    let sentence = &source_track["sentences"][0];
    let token = sentence["tokens"]
        .as_array()
        .unwrap()
        .iter()
        .find(|token| token["kind"] == "word")
        .expect("fixture has a word token");
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/word-timelines",
                source_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "algorithm_id": "exchange-aligner",
                    "algorithm_version": "v1",
                    "config_hash": "test-config",
                    "status": "active",
                    "words": [{
                        "sentence_id": sentence["id"],
                        "token_index": token["index"],
                        "text": token["text"],
                        "start_ms": sentence["start"].as_u64().unwrap() + 10,
                        "end_ms": sentence["start"].as_u64().unwrap() + 130,
                        "confidence": 0.95,
                        "timing_source": "forced_aligned",
                        "provider_id": "exchange-aligner",
                        "provider_version": "v1"
                    }]
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                source_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let mut document: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "path": "/tmp/existing-target-media.mp4",
                        "fingerprint": "existing-target-media",
                        "title": "existing-target-media",
                        "kind": "video"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_media: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let external_track_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    document["metadata"]["media"] = serde_json::json!({
        "id": target_media["id"],
        "fingerprint": target_media["fingerprint"],
        "path": target_media["path"],
        "title": target_media["title"],
        "duration_ms": null
    });
    document["metadata"]["extra"]["track_id"] = serde_json::json!(external_track_id);
    let mut sentence_ids = std::collections::HashMap::new();
    for (index, segment) in document["segments"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .enumerate()
    {
        let original = segment["id"].as_str().unwrap().to_owned();
        let external = format!("{:064x}", index + 1);
        segment["id"] = serde_json::json!(external);
        sentence_ids.insert(original, external);
    }
    for timeline in document["word_timelines"].as_array_mut().unwrap() {
        timeline["media_id"] = target_media["id"].clone();
        timeline["track_id"] = serde_json::json!(external_track_id);
        for word in timeline["words"].as_array_mut().unwrap() {
            let original = word["sentence_id"].as_str().unwrap();
            word["sentence_id"] = serde_json::json!(sentence_ids[original]);
        }
    }

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/lltimeline/import")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(document.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let imported_once: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(imported_once["id"], external_track_id);

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/media/{}/lltimeline/import",
                target_media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(document.to_string()))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let imported_again: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(imported_again["id"], external_track_id);
}

#[tokio::test]
async fn phonetic_analysis_fake_provider_completes_without_audio_detection_claims() {
    let app = test_app();
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "path": "/tmp/phonetic.mp4",
                        "fingerprint": "phonetic-media",
                        "title": "Phonetic",
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
    let track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let job_request = serde_json::json!({
        "track_id": track["id"],
        "sentence_id": track["sentences"][0]["id"],
        "model_id": "research-fixture:deterministic@v1"
    })
    .to_string();
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/phonetic-analysis/jobs")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(job_request.clone()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let job: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let job_id = job["id"].as_str().unwrap();
    let completed = wait_for_phonetic_job(&app, job_id, &["completed"]).await;
    assert_eq!(completed["phase_progress"], 100);
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/phonetic-analysis/jobs")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(job_request))
                .unwrap(),
        )
        .await
        .unwrap();
    let repeated: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(repeated["id"], completed["id"]);
    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/phonetic-analyses",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let analyses: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert!(
        !analyses[0]["detected_phones"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    let findings = analyses[0]["findings"].as_array().unwrap();
    assert!(!findings.is_empty());
    assert!(
        findings
            .iter()
            .all(|finding| finding["status"] != "detected_in_audio")
    );
    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/phone-timelines/summary",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let phone_timeline_summaries: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(phone_timeline_summaries.as_array().unwrap().len(), 1);
    assert_eq!(phone_timeline_summaries[0]["status"], "candidate");
    assert_eq!(phone_timeline_summaries[0]["precision"], "approximate");
    assert_eq!(
        phone_timeline_summaries[0]["parent_phonetic_analysis_id"],
        analyses[0]["id"]
    );
    assert_eq!(
        phone_timeline_summaries[0]["sentence_id"],
        analyses[0]["sentence_id"]
    );

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/phone-timelines/{}/activate",
                phone_timeline_summaries[0]["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let active_phone_timeline: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(active_phone_timeline["status"], "active");
    assert!(
        !active_phone_timeline["phones"]
            .as_array()
            .unwrap()
            .is_empty()
    );

    let response = app
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let document: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(document["phone_timelines"].as_array().unwrap().len(), 1);
    assert_eq!(
        document["active_phone_timeline_id"],
        active_phone_timeline["id"]
    );
}

#[tokio::test]
async fn phonetic_model_management_rejects_unapproved_research_fixture() {
    let app = test_app();
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/phonetic-analysis/models/install")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "model_id": "research-fixture:deterministic@v1"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CONFLICT);

    let response = app
        .oneshot(
            Request::delete("/v1/phonetic-analysis/models/research-fixture%3Adeterministic%40v1")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CONFLICT);
}

#[tokio::test]
async fn phonetic_fake_provider_supports_partial_cancel_failure_retry_and_feedback() {
    let app = test_app();
    let track = setup_phonetic_track(&app, "phonetic-lifecycle").await;
    let create = |mode: &str| {
        Request::post("/v1/phonetic-analysis/jobs")
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "track_id": track["id"],
                    "sentence_id": track["sentences"][0]["id"],
                    "model_id": "research-fixture:deterministic@v1",
                    "research_mode": mode
                })
                .to_string(),
            ))
            .unwrap()
    };

    let response = app.clone().oneshot(create("slow")).await.unwrap();
    let cancellable: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/phonetic-analysis/jobs/{}/cancel",
                cancellable["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let cancelled: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(cancelled["status"], "cancelled");

    let response = app.clone().oneshot(create("fail")).await.unwrap();
    let failing: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let failed = wait_for_phonetic_job(&app, failing["id"].as_str().unwrap(), &["failed"]).await;
    assert_eq!(failed["error_code"], "research_fixture_failed");
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/phonetic-analysis/jobs/{}/retry",
                failed["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let retried: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(retried["retry_of_job_id"], failed["id"]);
    wait_for_phonetic_job(&app, retried["id"].as_str().unwrap(), &["failed"]).await;

    let response = app.clone().oneshot(create("partial")).await.unwrap();
    let partial: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    wait_for_phonetic_job(&app, partial["id"].as_str().unwrap(), &["completed"]).await;
    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/phonetic-analyses",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let analyses: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let analysis = analyses
        .as_array()
        .unwrap()
        .iter()
        .find(|value| value["job_id"] == partial["id"])
        .unwrap();
    assert_eq!(analysis["detected_phones"].as_array().unwrap().len(), 1);
    let finding_id = analysis["findings"][0]["id"].as_str().unwrap();
    let response = app
        .clone()
        .oneshot(
            Request::put("/v1/phonetic-analysis/findings/missing/feedback")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(r#"{"value":"confirmed"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    let response = app
        .clone()
        .oneshot(
            Request::put(format!(
                "/v1/phonetic-analysis/findings/{finding_id}/feedback"
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(r#"{"value":"confirmed","note":"matches"}"#))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/phonetic-analysis/jobs")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "track_id": track["id"],
                        "model_id": "research-fixture:deterministic@v1"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let track_job: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    wait_for_phonetic_job(&app, track_job["id"].as_str().unwrap(), &["completed"]).await;
    let response = app
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/phonetic-analyses",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let analyses: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(
        analyses
            .as_array()
            .unwrap()
            .iter()
            .filter(|analysis| analysis["job_id"] == track_job["id"])
            .count(),
        track["sentences"].as_array().unwrap().len()
    );
}

#[tokio::test]
async fn speech_batch_job_queues_ten_thousand_sentences_and_can_cancel_and_retry() {
    let app = test_app();
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "path": "/tmp/speech-batch.mp4",
                        "fingerprint": "speech-batch-media",
                        "title": "Speech batch",
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
    let path = std::env::temp_dir().join(format!(
        "llplayer-speech-batch-{}.srt",
        application::now_ms()
    ));
    let content = (1..=10_000)
        .map(|index| format!("{index}\n00:00:00,000 --> 00:00:00,999\nHello world {index}\n\n"))
        .collect::<String>();
    std::fs::write(&path, content).unwrap();
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
                serde_json::json!({"path": path, "language": "en"}).to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    let _ = std::fs::remove_file(&path);
    let track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/speech/jobs")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "track_id": track["id"],
                        "kind": "pronunciation_analysis"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let job: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(job["status"], "queued");
    assert_eq!(job["total"], 10_000);

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/speech/jobs/{}/cancel",
                job["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let cancelled: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(cancelled["status"], "cancelled");

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/speech/jobs/{}/retry",
                job["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let retried: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(retried["status"], "queued");
    assert_eq!(retried["retry_of_job_id"], job["id"]);
    let response = app
        .oneshot(
            Request::post(format!(
                "/v1/speech/jobs/{}/cancel",
                retried["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}

#[test]
fn openapi_lists_implemented_routes() {
    let openapi = include_str!("../../../contracts/openapi/v1.yaml");
    for path in [
        "/v1/health",
        "/v1/media",
        "/v1/lltimeline/import",
        "/v1/media/{media_id}",
        "/v1/media/{media_id}/subtitles",
        "/v1/media/{media_id}/progress",
        "/v1/subtitles/{track_id}",
        "/v1/subtitles/{track_id}/export",
        "/v1/pronunciation/providers",
        "/v1/pronunciation/lookup",
        "/v1/pronunciation/analyze-sentence",
        "/v1/pronunciation/rules",
        "/v1/subtitles/{track_id}/pronunciation",
        "/v1/subtitles/{track_id}/pronunciation-analysis",
        "/v1/subtitles/{track_id}/word-timings",
        "/v1/subtitles/{track_id}/word-timelines",
        "/v1/subtitles/{track_id}/word-timelines/summary",
        "/v1/subtitles/{track_id}/lltimeline/export",
        "/v1/word-timelines/{timeline_id}",
        "/v1/word-timelines/{timeline_id}/activate",
        "/v1/word-timelines/{timeline_id}/publish",
        "/v1/word-timelines/{timeline_id}/archive",
        "/v1/word-timelines/{timeline_id}/export",
        "/v1/subtitles/{track_id}/word-timing-diagnostics",
        "/v1/subtitles/{track_id}/chunk-partitions",
        "/v1/subtitles/{track_id}/chunk-diagnostics",
        "/v1/chunk/providers",
        "/v1/subtitles/{track_id}/chunk-timelines",
        "/v1/subtitles/{track_id}/chunk-timelines/summary",
        "/v1/chunk-timelines/{timeline_id}",
        "/v1/chunk-timelines/{timeline_id}/activate",
        "/v1/chunk-timelines/{timeline_id}/archive",
        "/v1/chunk-timelines/{timeline_id}/export",
        "/v1/subtitles/{track_id}/phone-timelines",
        "/v1/subtitles/{track_id}/phone-timelines/summary",
        "/v1/phone-timelines/{timeline_id}",
        "/v1/phone-timelines/{timeline_id}/activate",
        "/v1/phone-timelines/{timeline_id}/archive",
        "/v1/phone-timelines/{timeline_id}/export",
        "/v1/speech/jobs",
        "/v1/word-profiles",
        "/v1/word-profiles/batch",
        "/v1/word-observations",
        "/v1/vocabulary",
        "/v1/vocabulary/export",
        "/v1/vocabulary/import",
        "/v1/word-profiles/{profile_id}/details",
        "/v1/word-profiles/{profile_id}/learning-content",
        "/v1/vocabulary/import-external",
        "/v1/media/{media_id}/availability",
        "/v1/events",
        "/v1/dictionary",
        "/v1/sentences/{sentence_id}/diagnosis",
        "/v1/transcription/providers",
        "/v1/transcription/models",
        "/v1/transcription/jobs",
        "/v1/transcription/jobs/{job_id}/archive",
        "/v1/phonetic-analysis/providers",
        "/v1/phonetic-analysis/models",
        "/v1/phonetic-analysis/models/install",
        "/v1/phonetic-analysis/models/register-custom",
        "/v1/phonetic-analysis/models/{model_id}/cancel-install",
        "/v1/phonetic-analysis/models/{model_id}",
        "/v1/phonetic-analysis/jobs",
        "/v1/subtitles/{track_id}/phonetic-analyses",
        "/v1/phonetic-analysis/{analysis_id}/findings",
        "/v1/phonetic-analysis/findings/{finding_id}/feedback",
    ] {
        assert!(openapi.contains(path), "OpenAPI missing {path}");
    }
}

#[test]
fn openapi_version_snapshot_and_path_count() {
    let openapi = include_str!("../../../contracts/openapi/v1.yaml");

    // API version snapshot — bump intentionally, never accidentally.
    assert!(
        openapi.contains("version: 1.0.0"),
        "OpenAPI info.version snapshot changed — update test if intentional"
    );

    // OpenAPI specification version.
    assert!(
        openapi.contains("openapi: 3.1.0"),
        "OpenAPI spec version snapshot changed"
    );

    // Count documented paths as a regression gate.
    let path_count = openapi.lines().filter(|l| l.starts_with("  /v1/")).count();
    assert_eq!(
        path_count, 93,
        "OpenAPI path count changed from 93 — update snapshot if paths were added/removed"
    );

    // All paths must be under /v1/.
    for line in openapi.lines() {
        if line.starts_with("  /") && !line.starts_with("  /v1/") {
            panic!("OpenAPI path not under /v1/ prefix: {}", line.trim());
        }
    }

    // Key schemas must exist (defines the response contract surface).
    for schema in [
        "Health:",
        "MediaItem:",
        "RegisterMedia:",
        "SubtitleTrack:",
        "SubtitleSentence:",
        "SubtitleToken:",
        "LexicalEntry:",
        "LexicalEntryDetails:",
        "WordProfile:",
        "WordObservation:",
        "WordOccurrence:",
        "SentenceDiagnosis:",
        "DictionaryLookup:",
        "DictionaryLookupBundle:",
        "VocabularyAssetBundle:",
        "LearningResource:",
        "SubtitleSearchResult:",
        "WordDetails:",
    ] {
        assert!(
            openapi.contains(&format!("    {schema}")),
            "OpenAPI schema missing: {schema}"
        );
    }
}
