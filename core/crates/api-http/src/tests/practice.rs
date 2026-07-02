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
