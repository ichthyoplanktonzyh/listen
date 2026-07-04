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
async fn practice_routes_record_stuck_points_and_complete_session() {
    let app = test_app();
    let session_response = app
        .clone()
        .oneshot(
            Request::post("/v1/practice/sessions")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "mode": "intensive",
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
    let stuck_input = serde_json::json!({
        "session_id": session_id,
        "target": {
            "kind": "sentence",
            "id": "sentence-api-1",
            "sentence_id": "sentence-api-1",
            "chunk_id": null,
            "start_ms": 100,
            "end_ms": 900
        },
        "anchors": [{
            "kind": "sentence",
            "id": "sentence-api-1",
            "label": "would have",
            "lexical_entry_id": null,
            "sentence_id": "sentence-api-1",
            "token_start": 0,
            "token_end": 1,
            "start_ms": 100,
            "end_ms": 900
        }],
        "label": "would have",
        "diagnosis_hints": []
    });

    let mark_response = app
        .clone()
        .oneshot(
            Request::post("/v1/practice/stuck-points/mark")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(stuck_input.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(mark_response.status(), StatusCode::OK);

    let summary_response = app
        .clone()
        .oneshot(
            Request::get(format!("/v1/practice/sessions/{session_id}/summary"))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(summary_response.status(), StatusCode::OK);
    let summary: serde_json::Value = serde_json::from_slice(
        &to_bytes(summary_response.into_body(), 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(summary["stuck_count"], 1);
    assert_eq!(summary["open_count"], 1);

    let complete_response = app
        .oneshot(
            Request::post(format!("/v1/practice/sessions/{session_id}/complete"))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({"mark_familiar": true}).to_string(),
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
    assert!(completed["session"]["ended_at_ms"].is_number());
    assert_eq!(completed["familiar_material_marked"], true);
}
