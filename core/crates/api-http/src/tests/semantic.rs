use super::*;
use domain::SemanticTaskGoldFixture;

fn gold_fixture() -> SemanticTaskGoldFixture {
    serde_json::from_str(include_str!(
        "../../../../testdata/semantic-task/gold-fixture-v1.json"
    ))
    .expect("gold fixture parses")
}

async fn post_json(
    app: &Router,
    path: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app
        .clone()
        .oneshot(
            Request::post(path)
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    (status, value)
}

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
    let value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    (status, value)
}

fn rubric_request(fixture: &SemanticTaskGoldFixture) -> serde_json::Value {
    serde_json::json!({
        "purpose": fixture.rubric.purpose,
        "source": fixture.rubric.source,
        "response_language": fixture.rubric.response_language,
        "points": fixture.rubric.points,
        "version": fixture.rubric.version,
        "provenance": fixture.rubric.provenance,
    })
}

fn attempt_request(
    fixture: &SemanticTaskGoldFixture,
    index: usize,
    rubric_id: &str,
) -> serde_json::Value {
    let attempt = &fixture.attempts[index];
    serde_json::json!({
        "kind": attempt.kind,
        "target": attempt.target,
        "anchors": attempt.anchors,
        "rubric_id": rubric_id,
        "rubric_version": attempt.rubric_version,
        "conditions": attempt.conditions,
        "responses": attempt.responses,
        "status": attempt.status,
        "started_at_ms": attempt.started_at_ms,
        "ended_at_ms": attempt.ended_at_ms,
    })
}

fn judgment_request(
    fixture: &SemanticTaskGoldFixture,
    index: usize,
    rubric_id: &str,
    attempt_id: &str,
) -> serde_json::Value {
    let judgment = &fixture.judgments[index];
    serde_json::json!({
        "attempt_id": attempt_id,
        "response_revision": judgment.response_revision,
        "rubric_id": rubric_id,
        "rubric_version": judgment.rubric_version,
        "rubric_source_sha256": judgment.rubric_source_sha256,
        "response_transcript_sha256": judgment.response_transcript_sha256,
        "points": judgment.points,
        "abstain": judgment.abstain,
        "provenance": judgment.provenance,
        "raw_output": judgment.raw_output,
        "evidence_class": judgment.evidence_class,
    })
}

#[tokio::test]
async fn semantic_gold_fixture_round_trips_over_http() {
    let app = test_app();
    let fixture = gold_fixture();

    let (status, rubric) = post_json(&app, "/v1/semantic/rubrics", rubric_request(&fixture)).await;
    assert_eq!(status, StatusCode::OK);
    let rubric_id = rubric["id"].as_str().unwrap().to_owned();
    assert_eq!(rubric["version"], 1);
    assert_eq!(rubric["points"].as_array().unwrap().len(), 5);

    let mut attempt_ids = Vec::new();
    for index in 0..fixture.attempts.len() {
        let (status, attempt) = post_json(
            &app,
            "/v1/semantic/attempts",
            attempt_request(&fixture, index, &rubric_id),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        attempt_ids.push(attempt["id"].as_str().unwrap().to_owned());
    }

    let mut judgment_ids = Vec::new();
    for (index, attempt_id) in attempt_ids.iter().enumerate() {
        let (status, judgment) = post_json(
            &app,
            "/v1/semantic/judgments",
            judgment_request(&fixture, index, &rubric_id, attempt_id),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "judgment {index}: {judgment}");
        judgment_ids.push(judgment["id"].as_str().unwrap().to_owned());
    }

    // Adjudicate judgment B / p3 exactly as the fixture records it.
    let adjudication = &fixture.adjudications[0];
    let (status, saved) = post_json(
        &app,
        "/v1/semantic/adjudications",
        serde_json::json!({
            "judgment_id": judgment_ids[1],
            "point_id": adjudication.point_id,
            "prior_verdict": adjudication.prior_verdict,
            "user_verdict": adjudication.user_verdict,
            "note": adjudication.note,
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(saved["point_id"], "p3");

    // Read side: latest rubric, attempts for rubric, judgments, adjudications.
    let (status, read_rubric) = get_json(&app, &format!("/v1/semantic/rubrics/{rubric_id}")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(read_rubric["id"], rubric["id"]);

    let (status, attempts) =
        get_json(&app, &format!("/v1/semantic/rubrics/{rubric_id}/attempts")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(attempts.as_array().unwrap().len(), 3);

    let (status, judgments) = get_json(
        &app,
        &format!("/v1/semantic/attempts/{}/judgments", attempt_ids[0]),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let judged_points = judgments[0]["points"].as_array().unwrap();
    assert_eq!(judged_points.len(), 5);
    assert_eq!(judged_points[0]["verdict"], "covered");
    assert_eq!(judged_points[0]["supporting_spans"][0]["start_char"], 0);

    // The abstain judgment stays first-class: no points, explicit reason.
    let (_, abstained) = get_json(
        &app,
        &format!("/v1/semantic/attempts/{}/judgments", attempt_ids[2]),
    )
    .await;
    assert_eq!(abstained[0]["abstain"]["reason"], "unreliable_transcript");
    assert_eq!(abstained[0]["points"].as_array().unwrap().len(), 0);

    let (status, adjudications) = get_json(
        &app,
        &format!("/v1/semantic/judgments/{}/adjudications", judgment_ids[1]),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(adjudications.as_array().unwrap().len(), 1);
    assert_eq!(adjudications[0]["prior_verdict"], "partial");
    assert_eq!(adjudications[0]["user_verdict"], "covered");
}

#[tokio::test]
async fn semantic_routes_reject_matrix_violations_and_tampered_hashes() {
    let app = test_app();
    let fixture = gold_fixture();

    let (status, rubric) = post_json(&app, "/v1/semantic/rubrics", rubric_request(&fixture)).await;
    assert_eq!(status, StatusCode::OK);
    let rubric_id = rubric["id"].as_str().unwrap().to_owned();

    // Evidence-matrix violation: retelling with the source text visible.
    let mut visible = attempt_request(&fixture, 0, &rubric_id);
    visible["conditions"]["source_text_visible"] = serde_json::json!(true);
    let (status, body) = post_json(&app, "/v1/semantic/attempts", visible).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    assert_eq!(body["code"], "invalid_input");

    let (status, attempt) = post_json(
        &app,
        "/v1/semantic/attempts",
        attempt_request(&fixture, 0, &rubric_id),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let attempt_id = attempt["id"].as_str().unwrap().to_owned();

    // Tampered source hash: the judgment no longer proves it saw the rubric.
    let mut tampered = judgment_request(&fixture, 0, &rubric_id, &attempt_id);
    tampered["rubric_source_sha256"] = serde_json::json!("0".repeat(64));
    let (status, body) = post_json(&app, "/v1/semantic/judgments", tampered).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    assert_eq!(body["code"], "invalid_input");

    // Unknown rubric version is not found, not silently created.
    let mut wrong_version = attempt_request(&fixture, 1, &rubric_id);
    wrong_version["rubric_version"] = serde_json::json!(9);
    let (status, _) = post_json(&app, "/v1/semantic/attempts", wrong_version).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
