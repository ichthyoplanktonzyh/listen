use super::*;

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
