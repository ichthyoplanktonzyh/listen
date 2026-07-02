use super::*;

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
