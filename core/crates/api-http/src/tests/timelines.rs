use super::*;

#[tokio::test]
async fn exports_lltimeline_document_with_active_word_timeline() {
    let app = test_app();
    let track = setup_phonetic_track(&app, "lltimeline-media").await;
    let sentence = &track["sentences"][0];
    let word_tokens = sentence["tokens"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|token| token["kind"] == "word")
        .collect::<Vec<_>>();
    assert!(!word_tokens.is_empty());
    let mut cursor = sentence["start"].as_u64().unwrap() + 10;
    let words = word_tokens
        .iter()
        .map(|token| {
            let start_ms = cursor;
            let end_ms = start_ms + 260;
            cursor = end_ms + 30;
            serde_json::json!({
                "sentence_id": sentence["id"],
                "token_index": token["index"],
                "text": token["text"],
                "start_ms": start_ms,
                "end_ms": end_ms,
                "confidence": 0.95,
                "timing_source": "forced_aligned",
                "provider_id": "test-aligner",
                "provider_version": "v1"
            })
        })
        .collect::<Vec<_>>();
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/word-timelines",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "algorithm_id": "test-aligner",
                    "algorithm_version": "v1",
                    "config_hash": "test-config",
                    "status": "active",
                    "words": words
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let timeline: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let mut document: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(document["schema"], domain::LLTIMELINE_SCHEMA_V1);
    assert_eq!(
        document["metadata"]["media"]["fingerprint"],
        "lltimeline-media"
    );
    assert_eq!(document["segments"].as_array().unwrap().len(), 4);
    assert_eq!(document["word_timelines"].as_array().unwrap().len(), 1);
    assert_eq!(document["active_word_timeline_id"], timeline["id"]);
    assert_eq!(document["phone_timelines"].as_array().unwrap().len(), 0);
    assert_eq!(document["rhythm_frames"].as_array().unwrap().len(), 1);
    assert_eq!(
        document["rhythm_frames"][0]["parent_word_timeline_id"],
        timeline["id"]
    );
    assert_eq!(document["rhythm_frames"][0]["sentence_id"], sentence["id"]);
    assert_eq!(
        document["rhythm_frames"][0]["provider_id"],
        "wordtimeline-rhythm-frame"
    );
    assert!(
        document["rhythm_frames"][0]["rhythm_frame"]["stress_anchors"]
            .as_array()
            .unwrap()
            .iter()
            .any(|anchor| anchor["claim_status"] == "audio_supported")
    );
    // The retired ChunkTimeline family no longer appears in the document.
    assert!(
        !document
            .as_object()
            .unwrap()
            .contains_key("chunk_timelines")
    );
    assert_eq!(document["sense_group_analyses"], serde_json::json!([]));
    assert_eq!(
        document["active_sense_group_analysis_id"],
        serde_json::Value::Null
    );
    document["sense_group_analyses"] = serde_json::json!([
        {
            "id": "sense-group-analysis-fixture",
            "track_id": track["id"],
            "media_id": track["media_id"],
            "parent_word_timeline_id": timeline["id"],
            "provider_id": "rule-based-sense-group",
            "provider_version": "v1",
            "algorithm": "fixture-rule-v1",
            "status": "active",
            "created_by": "algorithm",
            "metrics_json": {"fixture": true},
            "groups": [
                {
                    "id": "sense-group-fixture-0",
                    "sentence_id": sentence["id"],
                    "group_index": 0,
                    "start_token_index": word_tokens[0]["index"],
                    "end_token_index": word_tokens.last().unwrap()["index"],
                    "text": document["segments"][0]["text"],
                    "label": "clause",
                    "head_token_index": word_tokens[0]["index"],
                    "confidence": 0.9,
                    "sources": ["rule"]
                }
            ],
            "created_at_ms": 1781782222000_u64,
            "updated_at_ms": 1781782222000_u64
        }
    ]);
    document["active_sense_group_analysis_id"] = serde_json::json!("sense-group-analysis-fixture");
    document["metadata"]["generator"] = serde_json::json!({
        "id": "fixture-production-engine",
        "version": "v2",
        "mode": "production_engine"
    });
    document["artifacts"] = serde_json::json!([
        {
            "kind": "production_report",
            "provider_id": "fixture-production-engine",
            "provider_version": "v2",
            "payload": {
                "readiness": "ready",
                "post_alignment": "mfa"
            }
        },
        {
            "kind": "rhythm_word_acoustic_cues",
            "provider_id": "rust-word-acoustic-prominence",
            "provider_version": "v1",
            "payload": {
                "timeline_id": timeline["id"],
                "source_audio_path": "synthetic://energy-fixture.wav",
                "calibration": {
                    "method": "sentence_median_dbfs_delta_v1",
                    "delta_db_for_max": 6.0
                },
                "cues": [
                    {
                        "sentence_id": sentence["id"],
                        "token_index": word_tokens[0]["index"],
                        "energy_prominence": 0.95,
                        "pitch_prominence": 0.8,
                        "dbfs": -12.0,
                        "db_delta_from_sentence_median": 5.5
                    }
                ]
            }
        }
    ]);

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/lltimeline/import")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(document.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    assert_eq!(
        status,
        StatusCode::OK,
        "LLTimeline import failed: {}",
        String::from_utf8_lossy(&body)
    );
    let imported_track: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(imported_track["id"], track["id"]);
    assert_eq!(imported_track["sentences"].as_array().unwrap().len(), 4);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/word-timelines/summary",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let summaries: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(summaries.as_array().unwrap().len(), 1);
    assert_eq!(summaries[0]["status"], "active");
    assert_eq!(summaries[0]["lifecycle_stage"], "algorithm_candidate");

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let exported_after_import: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(
        exported_after_import["metadata"]["generator"]["id"],
        "fixture-production-engine"
    );
    assert_eq!(
        exported_after_import["artifacts"][0]["kind"],
        "production_report"
    );
    assert_eq!(
        exported_after_import["active_sense_group_analysis_id"],
        "sense-group-analysis-fixture"
    );
    assert_eq!(
        exported_after_import["sense_group_analyses"][0]["status"],
        "active"
    );
    assert_eq!(
        exported_after_import["sense_group_analyses"][0]["groups"][0]["sentence_id"],
        sentence["id"]
    );
    assert_eq!(
        exported_after_import["rhythm_frames"][0]["rhythm_frame"]["generated_from"],
        "wordtimeline_timing_acoustic_prominence_v1"
    );
    assert!(
        exported_after_import["rhythm_frames"][0]["rhythm_frame"]["quality"]["prominence_sources"]
            .as_array()
            .unwrap()
            .iter()
            .any(|source| source == "energy")
    );
    assert!(
        exported_after_import["rhythm_frames"][0]["rhythm_frame"]["quality"]["prominence_sources"]
            .as_array()
            .unwrap()
            .iter()
            .any(|source| source == "pitch")
    );

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/word-timelines/{}/publish",
                timeline["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let published: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(
        published["metrics_json"]["lifecycle"]["published"],
        serde_json::Value::Bool(true)
    );

    let response = app
        .clone()
        .oneshot(
            Request::delete(format!(
                "/v1/word-timelines/{}",
                timeline["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn sound_line_resources_never_disturb_active_text_timeline() {
    // Red line: building sound-line resources must never activate its own
    // (Candidate) timelines nor demote the active text-line timeline.
    let state = test_state();
    let app = router(state.clone());
    let track = setup_phonetic_track(&app, "sound-line-redline").await;
    let track_id_str = track["id"].as_str().unwrap().to_owned();
    let sentence = &track["sentences"][0];
    let word_tokens = sentence["tokens"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|token| token["kind"] == "word")
        .collect::<Vec<_>>();
    assert!(!word_tokens.is_empty());
    let mut cursor = sentence["start"].as_u64().unwrap() + 10;
    let words = word_tokens
        .iter()
        .map(|token| {
            let start_ms = cursor;
            let end_ms = start_ms + 200;
            cursor = end_ms + 20;
            serde_json::json!({
                "sentence_id": sentence["id"],
                "token_index": token["index"],
                "text": token["text"],
                "start_ms": start_ms,
                "end_ms": end_ms,
                "confidence": 0.95,
                "timing_source": "asr_aligned",
                "provider_id": "whisper-dtw",
                "provider_version": "dtw-v2"
            })
        })
        .collect::<Vec<_>>();
    let response = app
        .clone()
        .oneshot(
            Request::post(format!("/v1/subtitles/{track_id_str}/word-timelines"))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "algorithm_id": "whisper-dtw",
                        "algorithm_version": "dtw-v2",
                        "config_hash": "text-line",
                        "status": "active",
                        "metrics_json": {"line": "text"},
                        "words": words
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let text_timeline: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let export = |app: Router, track_id: String| async move {
        let response = app
            .oneshot(
                Request::get(format!("/v1/subtitles/{track_id}/lltimeline/export"))
                    .header(AUTHORIZATION, "Bearer secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        serde_json::from_slice::<serde_json::Value>(
            &to_bytes(response.into_body(), usize::MAX).await.unwrap(),
        )
        .unwrap()
    };

    let before = export(app.clone(), track_id_str.clone()).await;
    assert_eq!(before["active_word_timeline_id"], text_timeline["id"]);

    // Drive the sound line directly (no whisper JSON, no audio available):
    // it must still persist a Candidate sound-line timeline without touching active.
    let track_id = SubtitleTrackId::parse(track_id_str.clone()).unwrap();
    let result = state
        .application
        .execute_async(
            "test.build_sound_line_resources",
            move |services| async move {
                services
                    .media_analysis()
                    .build_transcription_sound_line_resources(
                        &track_id,
                        b"",
                        std::path::Path::new("/nonexistent/llplayernext-redline.wav"),
                        None,
                        None,
                    )
                    .await
            },
        )
        .await
        .unwrap();
    assert!(
        result.is_some(),
        "sound line should still produce a timeline"
    );

    let after = export(app.clone(), track_id_str.clone()).await;
    assert_eq!(
        after["active_word_timeline_id"], text_timeline["id"],
        "active text-line timeline must be untouched by the sound line"
    );
    let sound_timelines = after["word_timelines"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|timeline| timeline["metrics_json"]["line"] == "sound")
        .collect::<Vec<_>>();
    assert!(!sound_timelines.is_empty());
    for timeline in sound_timelines {
        assert_eq!(
            timeline["status"], "candidate",
            "every sound-line timeline must stay Candidate"
        );
        assert_ne!(timeline["id"], after["active_word_timeline_id"]);
    }
}

#[tokio::test]
async fn exported_rhythm_frames_prefer_sound_line_word_timeline() {
    let app = test_app();
    let track = setup_phonetic_track(&app, "lltimeline-sound-line").await;
    let sentence = &track["sentences"][0];
    let word_tokens = sentence["tokens"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|token| token["kind"] == "word")
        .collect::<Vec<_>>();
    assert!(!word_tokens.is_empty());
    let mut cursor = sentence["start"].as_u64().unwrap() + 10;
    let words = word_tokens
        .iter()
        .map(|token| {
            let start_ms = cursor;
            let end_ms = start_ms + 260;
            cursor = end_ms + 30;
            serde_json::json!({
                "sentence_id": sentence["id"],
                "token_index": token["index"],
                "text": token["text"],
                "start_ms": start_ms,
                "end_ms": end_ms,
                "confidence": 0.95,
                "timing_source": "asr_aligned",
                "provider_id": "whisper-dtw",
                "provider_version": "dtw-v2"
            })
        })
        .collect::<Vec<_>>();
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/word-timelines",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "algorithm_id": "whisper-dtw",
                    "algorithm_version": "dtw-v2",
                    "config_hash": "text-line",
                    "status": "active",
                    "metrics_json": {"line": "text"},
                    "words": words
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let text_timeline: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let mut document: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let mut sound_timeline = document["word_timelines"][0].clone();
    sound_timeline["id"] = serde_json::json!("word-timeline-sound-line-fixture");
    sound_timeline["algorithm_id"] = serde_json::json!("sound-line-whisper-dtw");
    sound_timeline["algorithm_version"] = serde_json::json!("phase-test");
    sound_timeline["config_hash"] = serde_json::json!("sound-line");
    sound_timeline["parent_timeline_id"] = text_timeline["id"].clone();
    sound_timeline["status"] = serde_json::json!("candidate");
    sound_timeline["metrics_json"] = serde_json::json!({
        "line": "sound",
        "source": "test_sound_line"
    });
    document["word_timelines"]
        .as_array_mut()
        .unwrap()
        .push(sound_timeline);
    document["artifacts"] = serde_json::json!([
        {
            "kind": "rhythm_word_acoustic_cues",
            "provider_id": "rust-word-acoustic-prominence",
            "provider_version": "v1",
            "payload": {
                "timeline_id": "word-timeline-sound-line-fixture",
                "line": "sound",
                "cues": [
                    {
                        "sentence_id": sentence["id"],
                        "token_index": word_tokens[0]["index"],
                        "energy_prominence": 0.95,
                        "pitch_prominence": 0.8
                    }
                ]
            }
        }
    ]);

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/lltimeline/import")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(document.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let exported: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let sound_timeline = exported["word_timelines"]
        .as_array()
        .unwrap()
        .iter()
        .find(|timeline| timeline["metrics_json"]["line"] == "sound")
        .unwrap();
    assert_eq!(exported["active_word_timeline_id"], text_timeline["id"]);
    assert_eq!(sound_timeline["status"], "candidate");
    assert_ne!(sound_timeline["id"], exported["active_word_timeline_id"]);
    assert_eq!(
        exported["rhythm_frames"][0]["parent_word_timeline_id"],
        sound_timeline["id"]
    );
    assert_eq!(
        exported["rhythm_frames"][0]["metrics_json"]["source"],
        "sound_line_word_timeline"
    );
    assert!(
        exported["rhythm_frames"][0]["rhythm_frame"]["quality"]["prominence_sources"]
            .as_array()
            .unwrap()
            .iter()
            .any(|source| source == "energy")
    );
}

#[tokio::test]
async fn imports_lltimeline_for_current_media_with_user_confirmed_mismatch() {
    let app = test_app();
    let source_track = setup_phonetic_track(&app, "source-media").await;
    let sentence = &source_track["sentences"][0];
    let token = sentence["tokens"]
        .as_array()
        .unwrap()
        .iter()
        .find(|token| token["kind"] == "word")
        .expect("fixture has a word token");
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/word-timelines",
                source_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "algorithm_id": "exchange-aligner",
                    "algorithm_version": "v1",
                    "config_hash": "test-config",
                    "status": "active",
                    "words": [{
                        "sentence_id": sentence["id"],
                        "token_index": token["index"],
                        "text": token["text"],
                        "start_ms": sentence["start"].as_u64().unwrap() + 10,
                        "end_ms": sentence["start"].as_u64().unwrap() + 130,
                        "confidence": 0.95,
                        "timing_source": "forced_aligned",
                        "provider_id": "exchange-aligner",
                        "provider_version": "v1"
                    }]
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                source_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let document: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "path": "/tmp/target-media.mp4",
                        "fingerprint": "target-media",
                        "title": "target-media",
                        "kind": "video"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_media: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/media/{}/lltimeline/import",
                target_media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(document.to_string()))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/media/{}/lltimeline/import?allow_mismatch=true",
                target_media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(document.to_string()))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let imported_track: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(imported_track["media_id"], target_media["id"]);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/media/{}/subtitles",
                target_media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let resources: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(resources.as_array().unwrap().len(), 1);
    assert_eq!(resources[0]["id"], imported_track["id"]);

    let response = app
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/word-timings",
                imported_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let timings: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(timings.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn imports_lltimeline_for_current_media_with_existing_resource_fingerprint() {
    let app = test_app();
    let source_track = setup_phonetic_track(&app, "existing-source-media").await;
    let sentence = &source_track["sentences"][0];
    let token = sentence["tokens"]
        .as_array()
        .unwrap()
        .iter()
        .find(|token| token["kind"] == "word")
        .expect("fixture has a word token");
    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/subtitles/{}/word-timelines",
                source_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "algorithm_id": "exchange-aligner",
                    "algorithm_version": "v1",
                    "config_hash": "test-config",
                    "status": "active",
                    "words": [{
                        "sentence_id": sentence["id"],
                        "token_index": token["index"],
                        "text": token["text"],
                        "start_ms": sentence["start"].as_u64().unwrap() + 10,
                        "end_ms": sentence["start"].as_u64().unwrap() + 130,
                        "confidence": 0.95,
                        "timing_source": "forced_aligned",
                        "provider_id": "exchange-aligner",
                        "provider_version": "v1"
                    }]
                })
                .to_string(),
            ))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/subtitles/{}/lltimeline/export",
                source_track["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let mut document: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "path": "/tmp/existing-target-media.mp4",
                        "fingerprint": "existing-target-media",
                        "title": "existing-target-media",
                        "kind": "video"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let target_media: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();

    let external_track_id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    document["metadata"]["media"] = serde_json::json!({
        "id": target_media["id"],
        "fingerprint": target_media["fingerprint"],
        "path": target_media["path"],
        "title": target_media["title"],
        "duration_ms": null
    });
    document["metadata"]["extra"]["track_id"] = serde_json::json!(external_track_id);
    let original_word_timeline_id = document["word_timelines"][0]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let external_word_timeline_id =
        "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    document["word_timelines"][0]["id"] = serde_json::json!(external_word_timeline_id);
    document["active_word_timeline_id"] = serde_json::json!(external_word_timeline_id);
    let mut sentence_ids = std::collections::HashMap::new();
    for (index, segment) in document["segments"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .enumerate()
    {
        let original = segment["id"].as_str().unwrap().to_owned();
        let external = format!("{:064x}", index + 1);
        segment["id"] = serde_json::json!(external);
        sentence_ids.insert(original, external);
    }
    for timeline in document["word_timelines"].as_array_mut().unwrap() {
        timeline["media_id"] = target_media["id"].clone();
        timeline["track_id"] = serde_json::json!(external_track_id);
        for word in timeline["words"].as_array_mut().unwrap() {
            let original = word["sentence_id"].as_str().unwrap();
            word["sentence_id"] = serde_json::json!(sentence_ids[original]);
        }
    }
    for frame in document["rhythm_frames"].as_array_mut().unwrap() {
        frame["media_id"] = target_media["id"].clone();
        frame["track_id"] = serde_json::json!(external_track_id);
        if frame["parent_word_timeline_id"].as_str() == Some(original_word_timeline_id.as_str()) {
            frame["parent_word_timeline_id"] = serde_json::json!(external_word_timeline_id);
        }
        let original = frame["sentence_id"].as_str().unwrap();
        frame["sentence_id"] = serde_json::json!(sentence_ids[original]);
    }

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/lltimeline/import")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(document.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let imported_once: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(imported_once["id"], external_track_id);

    let response = app
        .clone()
        .oneshot(
            Request::post(format!(
                "/v1/media/{}/lltimeline/import",
                target_media["id"].as_str().unwrap()
            ))
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(document.to_string()))
            .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let imported_again: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(imported_again["id"], external_track_id);
}
