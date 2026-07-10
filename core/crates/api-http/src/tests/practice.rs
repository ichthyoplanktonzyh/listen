use super::*;

#[tokio::test]
async fn practice_routes_create_and_read_attempts() {
    let app = test_app();
    let item_response = app
        .clone()
        .oneshot(
            Request::post("/v1/practice/items")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "kind": "dictation",
                        "target": {
                            "kind": "chunk",
                            "id": "chunk-1",
                            "sentence_id": null,
                            "chunk_id": "chunk-1",
                            "start_ms": 100,
                            "end_ms": 900
                        },
                        "prompt_snapshot": "hello world",
                        "expected_text": "hello world",
                        "anchors": []
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(item_response.status(), StatusCode::OK);
    let item: serde_json::Value = serde_json::from_slice(
        &to_bytes(item_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    let item_id = item["id"].as_str().unwrap();

    let attempt_response = app
        .clone()
        .oneshot(
            Request::post("/v1/practice/attempts")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "item_id": item_id,
                        "text_answer": "hello",
                        "create_review_item_on_failure": true
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(attempt_response.status(), StatusCode::OK);
    let attempt: serde_json::Value = serde_json::from_slice(
        &to_bytes(attempt_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(attempt["result"], "partial");
    assert_eq!(
        attempt["generated_review_item_ids"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    let attempt_id = attempt["id"].as_str().unwrap();

    let due_response = app
        .clone()
        .oneshot(
            Request::get("/v1/review/items?limit=8")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(due_response.status(), StatusCode::OK);
    let due: serde_json::Value = serde_json::from_slice(
        &to_bytes(due_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    let review_id = due[0]["item"]["id"].as_str().unwrap();
    assert_eq!(
        due[0]["schedule"]["algorithm"],
        "listen_review_v1_heuristic_proxy"
    );
    assert_eq!(due[0]["card"]["kind"], "source_sentence_recall");
    assert_eq!(due[0]["card"]["answer"], "hello world");

    let review_response = app
        .clone()
        .oneshot(
            Request::post("/v1/review/attempts")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({"item_id": review_id, "rating": "good"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(review_response.status(), StatusCode::OK);
    let review_submission: serde_json::Value = serde_json::from_slice(
        &to_bytes(review_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(review_submission["attempt"]["rating"], "good");
    assert_eq!(review_submission["schedule"]["interval_days"], 3.0);
    assert_eq!(
        review_submission["generated_observation_ids"],
        serde_json::json!([])
    );
    assert_eq!(
        review_submission["hunting_candidate_ids"],
        serde_json::json!([])
    );

    let read_response = app
        .oneshot(
            Request::get(format!("/v1/practice/attempts/{attempt_id}"))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(read_response.status(), StatusCode::OK);
}

#[tokio::test]
async fn upgrade_suggestion_routes_expose_pending_and_history_queries() {
    let app = test_app();
    for path in [
        "/v1/review/upgrade-suggestions",
        "/v1/review/upgrade-suggestions/history",
    ] {
        let response = app
            .clone()
            .oneshot(
                Request::get(path)
                    .header(AUTHORIZATION, "Bearer secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let values: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), 1024 * 1024).await.unwrap())
                .unwrap();
        assert_eq!(values, serde_json::json!([]));
    }

    let missing = app
        .oneshot(
            Request::post("/v1/review/upgrade-suggestions/missing/confirm")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn practice_routes_reject_retired_intensive_endpoints_and_complete_extensive_session() {
    let app = test_app();
    let session_response = app
        .clone()
        .oneshot(
            Request::post("/v1/practice/sessions")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "mode": "extensive",
                        "media_id": null,
                        "track_id": null,
                        "source": "test"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(session_response.status(), StatusCode::OK);
    let session: serde_json::Value = serde_json::from_slice(
        &to_bytes(session_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    let session_id = session["id"].as_str().unwrap();
    let retired_summary = app
        .clone()
        .oneshot(
            Request::get(format!("/v1/practice/sessions/{session_id}/summary"))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(retired_summary.status(), StatusCode::NOT_FOUND);
    let retired_stuck = app
        .clone()
        .oneshot(
            Request::post("/v1/practice/stuck-points/mark")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(retired_stuck.status(), StatusCode::NOT_FOUND);

    let complete_response = app
        .oneshot(
            Request::post(format!("/v1/listening/sessions/{session_id}/complete"))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({"comprehension_report": "got_the_gist"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(complete_response.status(), StatusCode::OK);
    let completed: serde_json::Value = serde_json::from_slice(
        &to_bytes(complete_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    assert!(completed["ended_at_ms"].is_number());
}

#[tokio::test]
async fn practice_routes_capture_and_process_listening_inbox_items() {
    let app = test_app();
    let session_response = app
        .clone()
        .oneshot(
            Request::post("/v1/practice/sessions")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "mode": "extensive",
                        "media_id": null,
                        "track_id": null,
                        "source": "route-test"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(session_response.status(), StatusCode::OK);
    let session: serde_json::Value = serde_json::from_slice(
        &to_bytes(session_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    let session_id = session["id"].as_str().unwrap();

    let capture_response = app
        .clone()
        .oneshot(
            Request::post("/v1/listening-inbox/items")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "session_id": session_id,
                        "target": {
                            "kind": "sentence",
                            "id": "sentence-inbox-api-1",
                            "sentence_id": "sentence-inbox-api-1",
                            "chunk_id": null,
                            "start_ms": 1200,
                            "end_ms": 2200
                        },
                        "anchors": [{
                            "kind": "sentence",
                            "id": "sentence-inbox-api-1",
                            "label": "missed this line",
                            "lexical_entry_id": null,
                            "sentence_id": "sentence-inbox-api-1",
                            "token_start": 0,
                            "token_end": 2,
                            "start_ms": 1200,
                            "end_ms": 2200
                        }],
                        "label": "missed this line",
                        "subtitle_snapshot": "missed this line",
                        "context_before": null,
                        "context_after": "after"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(capture_response.status(), StatusCode::OK);
    let captured: serde_json::Value = serde_json::from_slice(
        &to_bytes(capture_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(captured["status"], "active");
    let item_id = captured["id"].as_str().unwrap();

    let list_response = app
        .clone()
        .oneshot(
            Request::get("/v1/listening-inbox/items")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(list_response.status(), StatusCode::OK);
    let items: serde_json::Value = serde_json::from_slice(
        &to_bytes(list_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(items.as_array().unwrap().len(), 1);

    let process_response = app
        .clone()
        .oneshot(
            Request::post(format!("/v1/listening-inbox/items/{item_id}/process"))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({"resolution": "review_item"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(process_response.status(), StatusCode::OK);
    let processed: serde_json::Value = serde_json::from_slice(
        &to_bytes(process_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(processed["status"], "archived");
    assert_eq!(processed["resolution"], "review_item");
    assert_eq!(processed["review_item_ids"].as_array().unwrap().len(), 1);
}
