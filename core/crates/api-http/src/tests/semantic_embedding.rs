use super::*;

#[tokio::test]
async fn semantic_capability_and_search_degrade_without_installing_or_writing() {
    let app = test_app();
    let response = app
        .clone()
        .oneshot(
            Request::get("/v1/semantic-embedding/capability")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(body["status"], "not_installed");
    assert!(body["descriptor"].is_null());

    let response = app
        .oneshot(
            Request::get("/v1/semantic-search?query=enormous%20room&language=en")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(body["capability"]["status"], "not_installed");
    assert_eq!(body["hits"], serde_json::json!([]));
}

#[tokio::test]
async fn semantic_search_rejects_ambiguous_filters() {
    let response = test_app()
        .oneshot(
            Request::get("/v1/semantic-search?query=room&source=authority")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn semantic_gap_endpoint_keeps_the_v1_review_when_model_is_absent() {
    let response = test_app()
        .oneshot(
            Request::get(
                "/v1/production-gap/semantic-enrichment?language=en&channel=written&limit=10",
            )
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(body["review"]["readiness"], "empty");
    assert_eq!(body["semantic_capability"]["status"], "not_installed");
    assert_eq!(body["enrichments"], serde_json::json!([]));
}
