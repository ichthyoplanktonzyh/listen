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
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

/// Pins the exact payload shape the Reading Studio client sends (Slice 3):
/// manual reading-comprehension rubric → text-visible attempt → whole-span
/// self-assessment judgment. A validator change that breaks the client
/// breaks here first.
#[tokio::test]
async fn reading_studio_task_flow_round_trips() {
    let app = test_app();
    let snapshot = "A quake struck Mindanao on Monday morning.";
    let (status, rubric) = post_json(
        &app,
        "/v1/semantic/rubrics",
        serde_json::json!({
            "purpose": "reading_comprehension",
            "source": {
                "media_id": "media-1",
                "track_id": "track-1",
                "start_ms": 1000,
                "end_ms": 9000,
                "language": "en",
                "transcript_snapshot": snapshot,
            },
            "response_language": "zh",
            "points": [
                {"point_id": "main-idea", "importance": "required",
                 "statement": "主旨", "accepted_paraphrase_notes": null},
                {"point_id": "detail", "importance": "optional",
                 "statement": "细节", "accepted_paraphrase_notes": null},
            ],
            "version": 1,
            "provenance": {"kind": "manual",
                "detail": "reading studio paragraph task (user-edited template)",
                "model_id": null, "prompt_version": null, "schema_version": null},
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{rubric}");
    let rubric_id = rubric["id"].as_str().unwrap();

    let answer = "地震发生在棉兰老岛。";
    let (status, attempt) = post_json(
        &app,
        "/v1/semantic/attempts",
        serde_json::json!({
            "kind": "reading_comprehension",
            "target": {"kind": "segment", "id": null, "sentence_id": null,
                       "chunk_id": null, "start_ms": 1000, "end_ms": 9000},
            "anchors": [],
            "rubric_id": rubric_id,
            "rubric_version": 1,
            "conditions": {"source_text_visible": true, "audio_play_count": 2,
                            "notes_allowed": false, "l1_trigger": null},
            "responses": [{"revision": 1, "transcript": answer,
                "source": "typed", "recording_asset_id": null,
                "asr_reliability": null, "language": "zh",
                "recorded_at_ms": 10}],
            "status": "completed",
            "started_at_ms": 5,
            "ended_at_ms": 10,
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{attempt}");
    let attempt_id = attempt["id"].as_str().unwrap();

    // Whole-response span in Unicode scalar counts, exactly as the client
    // computes with String.runes.
    let char_count = answer.chars().count();
    let (status, judgment) = post_json(
        &app,
        "/v1/semantic/judgments",
        serde_json::json!({
            "attempt_id": attempt_id,
            "response_revision": 1,
            "rubric_id": rubric_id,
            "rubric_version": 1,
            "rubric_source_sha256": domain::transcript_sha256(snapshot),
            "response_transcript_sha256": domain::transcript_sha256(answer),
            "points": [
                {"point_id": "main-idea", "verdict": "covered",
                 "supporting_spans": [{"start_char": 0, "end_char": char_count}]},
                {"point_id": "detail", "verdict": "missing",
                 "supporting_spans": []},
            ],
            "abstain": null,
            "provenance": {"kind": "manual",
                "detail": "reading self-assessment; spans default to whole response",
                "model_id": null, "prompt_version": null, "schema_version": null},
            "raw_output": null,
            "evidence_class": "self_assessment",
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{judgment}");
    assert_eq!(judgment["evidence_class"], "self_assessment");
}

#[tokio::test]
async fn reading_marking_rejects_unknown_entry_over_http() {
    let app = test_app();
    let (status, body) = post_json(
        &app,
        "/v1/reading/markings",
        serde_json::json!({
            "lexical_entry_id": "no-such-entry",
            "sentence_id": "cue-1",
            "surface_form": "word",
            "translation_visible": false,
            "understood": true,
        }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
}

#[tokio::test]
async fn learning_observation_history_reads_back_marking_evidence() {
    let app = test_app();
    let (status, lexical) = put_json(
        &app,
        "/v1/lexical-entries",
        serde_json::json!({
            "language": "en",
            "kind": "word",
            "canonical_form": "quake",
            "display_form": "quake",
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{lexical}");
    let entry_id = lexical["entry"]["id"].as_str().unwrap();

    // One reading marking writes exactly one reading-channel observation; the
    // history endpoint must read the same row back, not a re-derivation.
    // (Raw request: the route answers 204 with an empty body, which
    // `post_json` would refuse to parse.)
    let marking_response = app
        .clone()
        .oneshot(
            Request::post("/v1/reading/markings")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "lexical_entry_id": entry_id,
                        "sentence_id": "cue-1",
                        "surface_form": "quakes",
                        "translation_visible": true,
                        "understood": true,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(marking_response.status(), StatusCode::NO_CONTENT);

    let (status, history) =
        get_json(&app, &format!("/v1/lexical-entries/{entry_id}/observations")).await;
    assert_eq!(status, StatusCode::OK, "{history}");
    let rows = history.as_array().unwrap();
    assert_eq!(rows.len(), 1, "{history}");
    assert_eq!(rows[0]["capability"], "reading");
    assert_eq!(rows[0]["surface_form"], "quakes");
    assert_eq!(rows[0]["origin"], "user_marking");
    assert!(rows[0]["occurred_at_ms"].as_u64().unwrap() > 0);

    // The capability filter is a real filter, not decoration.
    let (status, filtered) = get_json(
        &app,
        &format!("/v1/lexical-entries/{entry_id}/observations?capability=listening"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{filtered}");
    assert!(filtered.as_array().unwrap().is_empty(), "{filtered}");

    let (status, missing) =
        get_json(&app, "/v1/lexical-entries/no-such-entry/observations").await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{missing}");
}
