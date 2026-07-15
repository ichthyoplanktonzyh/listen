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

async fn request_status(
    app: &Router,
    method: axum::http::Method,
    path: &str,
    body: serde_json::Value,
) -> StatusCode {
    app.clone()
        .oneshot(
            Request::builder()
                .method(method)
                .uri(path)
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap()
        .status()
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

#[tokio::test]
async fn semantic_rubric_lookup_finds_by_source_identity() {
    let app = test_app();
    let fixture = gold_fixture();
    let (status, created) = post_json(&app, "/v1/semantic/rubrics", rubric_request(&fixture)).await;
    assert_eq!(status, StatusCode::OK);

    let source = &fixture.rubric.source;
    let sha = domain::transcript_sha256(&source.transcript_snapshot);
    let query = format!(
        "/v1/semantic/rubrics/lookup?media_id={}&start_ms={}&end_ms={}\
         &purpose=l1_retelling&response_language=zh&source_sha256={sha}",
        source.media_id.as_ref().unwrap().as_str(),
        source.start_ms,
        source.end_ms,
    );
    let (status, found) = get_json(&app, &query).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(found["id"], created["id"]);
    assert_eq!(found["version"], created["version"]);

    // A different purpose or hash finds nothing instead of guessing.
    let miss = query.replace("purpose=l1_retelling", "purpose=summary");
    let (status, body) = get_json(&app, &miss).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body, serde_json::Value::Null);
}

#[tokio::test]
async fn speaking_target_confirmation_requires_qualified_literal_evidence() {
    let app = test_app();
    let fixture = gold_fixture();

    let mut rubric_body = rubric_request(&fixture);
    rubric_body["purpose"] = serde_json::json!("l2_retelling");
    rubric_body["response_language"] = serde_json::json!("en");
    let (status, rubric) = post_json(&app, "/v1/semantic/rubrics", rubric_body).await;
    assert_eq!(status, StatusCode::OK);
    let rubric_id = rubric["id"].as_str().unwrap();

    let lexical_response = app
        .clone()
        .oneshot(
            Request::put("/v1/lexical-entries")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "language": "en",
                        "kind": "phrase",
                        "canonical_form": "until Tuesday",
                        "display_form": "until Tuesday"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(lexical_response.status(), StatusCode::OK);
    let lexical: serde_json::Value = serde_json::from_slice(
        &to_bytes(lexical_response.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();
    let lexical_entry_id = lexical["entry"]["id"].as_str().unwrap();

    let attempt_body = serde_json::json!({
        "kind": "l2_retelling",
        "target": {
            "kind": "segment", "id": null, "sentence_id": null,
            "chunk_id": null, "start_ms": 26200, "end_ms": 53760
        },
        "anchors": [],
        "rubric_id": rubric_id,
        "rubric_version": 1,
        "conditions": {
            "source_text_visible": false,
            "audio_play_count": 1,
            "notes_allowed": false,
            "l1_trigger": null,
            "speaking_assistance": null,
            "speaking_recall": "immediate",
            "prompt_snapshot": null
        },
        "responses": [{
            "revision": 1,
            "raw_transcript": "The storm delayed the fairy to Tuesday.",
            "transcript": "The storm delayed the ferry until Tuesday.",
            "source": "asr",
            "recording_asset_id": "recording-speaking-target",
            "asr_reliability": "suspect",
            "language": "en",
            "recorded_at_ms": 1781222460000_u64
        }],
        "status": "completed",
        "started_at_ms": 1781222400000_u64,
        "ended_at_ms": 1781222460000_u64
    });
    let (status, attempt) = post_json(&app, "/v1/semantic/attempts", attempt_body.clone()).await;
    assert_eq!(status, StatusCode::OK, "{attempt}");
    let attempt_id = attempt["id"].as_str().unwrap();

    let confirmation = serde_json::json!({
        "lexical_entry_id": lexical_entry_id,
        "surface_form": "until Tuesday",
        "sentence_id": null
    });
    let status = request_status(
        &app,
        axum::http::Method::POST,
        &format!("/v1/semantic/attempts/{attempt_id}/speaking-targets"),
        confirmation.clone(),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let mut absent = confirmation.clone();
    absent["surface_form"] = serde_json::json!("Tuesday morning");
    let status = request_status(
        &app,
        axum::http::Method::POST,
        &format!("/v1/semantic/attempts/{attempt_id}/speaking-targets"),
        absent,
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let mut unreliable_body = attempt_body;
    unreliable_body["responses"][0]["asr_reliability"] = serde_json::json!("unreliable");
    unreliable_body["started_at_ms"] = serde_json::json!(1781222500000_u64);
    unreliable_body["ended_at_ms"] = serde_json::json!(1781222560000_u64);
    let (status, unreliable) = post_json(&app, "/v1/semantic/attempts", unreliable_body).await;
    assert_eq!(status, StatusCode::OK, "{unreliable}");
    let unreliable_id = unreliable["id"].as_str().unwrap();
    let status = request_status(
        &app,
        axum::http::Method::POST,
        &format!("/v1/semantic/attempts/{unreliable_id}/speaking-targets"),
        confirmation.clone(),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let (status, l1_rubric) =
        post_json(&app, "/v1/semantic/rubrics", rubric_request(&fixture)).await;
    assert_eq!(status, StatusCode::OK);
    let l1_rubric_id = l1_rubric["id"].as_str().unwrap();
    let (status, l1_attempt) = post_json(
        &app,
        "/v1/semantic/attempts",
        attempt_request(&fixture, 0, l1_rubric_id),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let l1_attempt_id = l1_attempt["id"].as_str().unwrap();
    let status = request_status(
        &app,
        axum::http::Method::POST,
        &format!("/v1/semantic/attempts/{l1_attempt_id}/speaking-targets"),
        confirmation,
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}
