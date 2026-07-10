use super::*;

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
async fn cold_start_words_returns_unassessed_sorted_by_frequency() {
    let app = test_app();
    let media = serde_json::json!({
        "path": "/tmp/cold-start.mp4",
        "fingerprint": "cold-start-media",
        "title": "ColdStart",
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
    let track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let track_id = track["id"].as_str().unwrap();

    // Cold-start words should return non-empty, sorted by frequency descending.
    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{track_id}/cold-start-words?limit=20"
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let candidates: Vec<serde_json::Value> =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert!(!candidates.is_empty());
    // All three fields present.
    for candidate in &candidates {
        assert!(candidate["display_form"].is_string());
        assert!(candidate["normalized_form"].is_string());
        assert!(candidate["occurrence_count"].is_u64());
    }
    // Sorted by occurrence_count descending.
    let counts: Vec<u64> = candidates
        .iter()
        .map(|c| c["occurrence_count"].as_u64().unwrap())
        .collect();
    for pair in counts.windows(2) {
        assert!(pair[0] >= pair[1], "candidates must be sorted by frequency");
    }

    // Mark one word via the existing lexical-entry upsert endpoint.
    let word = candidates[0]["display_form"].as_str().unwrap();
    let upsert = serde_json::json!({
        "language": "en",
        "kind": "word",
        "canonical_form": word,
        "display_form": word,
        "status": "known_recognized"
    })
    .to_string();
    let response = app
        .clone()
        .oneshot(
            Request::put("/v1/lexical-entries")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(upsert))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // That word should now be gone from candidates.
    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{track_id}/cold-start-words?limit=20"
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let after: Vec<serde_json::Value> =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let marked_normalized = candidates[0]["normalized_form"].as_str().unwrap();
    assert!(
        !after
            .iter()
            .any(|c| c["normalized_form"].as_str().unwrap() == marked_normalized),
        "marked word must disappear from candidates"
    );
    assert!(
        after.len() < candidates.len(),
        "total candidates should decrease after marking"
    );
}

#[tokio::test]
async fn content_fit_endpoint_serves_dual_dimension_profile() {
    let app = test_app();
    let media = serde_json::json!({
        "path": "/tmp/fit.mp4",
        "fingerprint": "content-fit-media",
        "title": "Fit",
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
    let track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/content-fit",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let profile: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(profile["subject_kind"], "media");
    assert_eq!(profile["subject_id"], media["id"]);
    assert_eq!(profile["language"], "en");
    assert_eq!(profile["algorithm_version"], "content-fit-v2");
    assert_eq!(profile["evidence_grade"], "initial_estimate");
    // Nothing is marked yet: the whole transcript is unassessed, so the
    // conservative estimate reports too_hard with an honest zero ratio.
    assert_eq!(profile["meaning"]["fit"], "too_hard");
    assert!((profile["assessed_token_ratio"].as_f64().unwrap()).abs() < 1e-6);
    let signals = profile["meaning"]["signals"].as_array().unwrap();
    assert!(
        signals
            .iter()
            .any(|signal| { signal["kind"] == "unassessed_density" && signal["decisive"] == true })
    );
    assert!(profile["input_fingerprint"].as_str().unwrap().len() == 64);

    // Second read is served from cache and stays identical.
    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/content-fit",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let cached: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(cached, profile);
}

#[tokio::test]
async fn media_library_lists_entries_and_persists_triage_intent() {
    let app = test_app();
    let media = serde_json::json!({
        "path": "/tmp/library.mp4",
        "fingerprint": "library-media",
        "title": "Library",
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
    let media_id = media["id"].as_str().unwrap();
    let fixture = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../testdata/subtitles/timeline.srt"
    );
    let request = serde_json::json!({"path": fixture, "language": "en"}).to_string();
    let response = app
        .clone()
        .oneshot(
            Request::post(format!("/v1/media/{media_id}/subtitles"))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(request))
                .unwrap(),
        )
        .await
        .unwrap();
    let track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::get("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let library: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let entry = library
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["media"]["id"] == media_id)
        .expect("registered media appears in the library");
    assert_eq!(entry["primary_track_id"], track["id"]);
    // Fit resolves through the cached track path and stays media-scoped.
    assert_eq!(entry["fit"]["subject_kind"], "media");
    assert_eq!(entry["fit"]["subject_id"], media_id);
    assert_eq!(entry["triage_intent"], serde_json::Value::Null);
    assert_eq!(entry["familiar_material"], false);

    // Pin the media; the returned entry and later listings agree.
    let response = app
        .clone()
        .oneshot(
            Request::put(format!("/v1/media/{media_id}/triage-intent"))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({"intent": "pin_intensive"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let updated: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(updated["triage_intent"], "pin_intensive");

    // Clearing with null removes the stored intent.
    let response = app
        .clone()
        .oneshot(
            Request::put(format!("/v1/media/{media_id}/triage-intent"))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(serde_json::json!({"intent": null}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let cleared: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(cleared["triage_intent"], serde_json::Value::Null);
}
