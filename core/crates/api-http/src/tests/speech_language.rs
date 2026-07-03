use super::*;

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

#[tokio::test]
async fn language_routes_track_patch_and_terminal_job_clear_are_typed() {
    let app = test_app();
    let response = app
        .clone()
        .oneshot(
            Request::get("/v1/languages")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let languages: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert!(
        languages
            .as_array()
            .unwrap()
            .contains(&serde_json::json!("en"))
    );
    assert!(
        languages
            .as_array()
            .unwrap()
            .contains(&serde_json::json!("zh"))
    );
    assert!(
        languages
            .as_array()
            .unwrap()
            .contains(&serde_json::json!("ja"))
    );

    let response = app
        .clone()
        .oneshot(
            Request::get("/v1/languages/en-US/profile")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let profile: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(profile["language"], "en-us");
    assert_eq!(profile["lexical_normalization"], "core.lemma");
    assert_eq!(profile["word_timeline"], "supported");

    let track = setup_phonetic_track(&app, "language-patch").await;
    let response = app
        .clone()
        .oneshot(
            Request::patch(format!(
                "/v1/subtitles/{}/language",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({"language": "zh-Hant"}).to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let updated: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(updated["language"], "zh-hant");

    let response = app
        .oneshot(
            Request::post("/v1/phonetic-analysis/jobs/clear")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let cleared: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(cleared["deleted"], 0);
}
