use super::*;

#[tokio::test]
async fn coach_and_listening_suggestion_routes_return_only_listening_facts() {
    let app = test_app();
    let dashboard = app
        .clone()
        .oneshot(
            Request::get("/v1/coach/dashboard")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(dashboard.status(), StatusCode::OK);
    let dashboard: serde_json::Value =
        serde_json::from_slice(&to_bytes(dashboard.into_body(), usize::MAX).await.unwrap())
            .unwrap();
    assert!(dashboard["listening_metrics"].is_array());
    assert!(dashboard["materials"].is_array());
    assert!(dashboard.get("channels").is_none());
    assert!(dashboard.get("features").is_none());

    for path in [
        "/v1/hunting/candidates",
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
        assert_eq!(response.status(), StatusCode::OK, "{path}");
        let values: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(values, serde_json::json!([]), "{path}");
    }

    let missing_suggestion = app
        .oneshot(
            Request::post("/v1/review/upgrade-suggestions/missing/confirm")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing_suggestion.status(), StatusCode::NOT_FOUND);
}
