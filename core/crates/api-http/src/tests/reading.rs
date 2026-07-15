use super::*;
use axum::body::to_bytes;

async fn get_json(app: &Router, path: &str) -> (StatusCode, serde_json::Value) {
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
    let status = response.status();
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let json = if body.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&body).unwrap()
    };
    (status, json)
}

async fn put_json(
    app: &Router,
    path: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app
        .clone()
        .oneshot(
            Request::put(path)
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

#[tokio::test]
async fn reading_position_upserts_and_reads_back() {
    let app = test_app();

    // Fresh track: no cursor yet.
    let (status, body) = get_json(&app, "/v1/reading/positions/track-1").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, serde_json::Value::Null);

    let (status, body) = put_json(
        &app,
        "/v1/reading/positions/track-1",
        serde_json::json!({
            "media_id": "media-1",
            "anchor_cue_id": "cue-a",
            "paragraph_index": 3,
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["anchor_cue_id"], "cue-a");
    assert_eq!(body["paragraph_index"], 3);

    // Upsert replaces the cursor for the same track.
    let (status, _) = put_json(
        &app,
        "/v1/reading/positions/track-1",
        serde_json::json!({
            "anchor_cue_id": "cue-b",
            "paragraph_index": 8,
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = get_json(&app, "/v1/reading/positions/track-1").await;
    assert_eq!(body["anchor_cue_id"], "cue-b");
    assert_eq!(body["paragraph_index"], 8);
    assert_eq!(body["media_id"], serde_json::Value::Null);

    // Other tracks stay independent.
    let (_, body) = get_json(&app, "/v1/reading/positions/track-2").await;
    assert_eq!(body, serde_json::Value::Null);
}

#[tokio::test]
async fn reading_position_rejects_empty_anchor() {
    let app = test_app();
    let (status, body) = put_json(
        &app,
        "/v1/reading/positions/track-1",
        serde_json::json!({
            "anchor_cue_id": "   ",
            "paragraph_index": 0,
        }),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "invalid_input");
}
