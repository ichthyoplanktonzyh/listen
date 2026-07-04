use super::*;

#[test]
fn learning_loop_practice_review_and_events_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    let session = PracticeSession {
        id: PracticeSessionId::parse("session-1").unwrap(),
        mode: PracticeMode::Intensive,
        media_id: None,
        track_id: None,
        source: "test".into(),
        started_at_ms: 1,
        ended_at_ms: None,
    };
    repo.create_practice_session(&session).unwrap();
    assert_eq!(
        repo.get_practice_session(&session.id).unwrap(),
        Some(session.clone())
    );

    let item = PracticeItem {
        id: PracticeItemId::parse("item-1").unwrap(),
        session_id: Some(session.id.clone()),
        kind: PracticeKind::Dictation,
        target: PracticeTarget {
            kind: PracticeTargetKind::Chunk,
            id: Some("chunk-1".into()),
            sentence_id: Some(SubtitleSentenceId::parse("sentence-1").unwrap()),
            chunk_id: Some(ChunkId::parse("chunk-1").unwrap()),
            start_ms: Some(100),
            end_ms: Some(900),
        },
        prompt_snapshot: "hello world".into(),
        expected_answer: serde_json::json!({"text": "hello world"}),
        anchors: vec![PracticeAnchor {
            kind: PracticeAnchorKind::Sentence,
            id: "sentence-1".into(),
            label: Some("hello world".into()),
            lexical_entry_id: None,
            sentence_id: Some(SubtitleSentenceId::parse("sentence-1").unwrap()),
            token_start: Some(0),
            token_end: Some(1),
            start_ms: Some(100),
            end_ms: Some(900),
        }],
        created_at_ms: 2,
    };
    repo.create_practice_item(&item).unwrap();
    assert_eq!(
        repo.get_practice_item(&item.id).unwrap(),
        Some(item.clone())
    );

    let attempt = PracticeAttempt {
        id: PracticeAttemptId::parse("attempt-1").unwrap(),
        item_id: item.id.clone(),
        submitted_at_ms: 3,
        input: serde_json::json!({"text": "hello"}),
        result: PracticeResult::Partial,
        score: Some(0.5),
        evaluation: PracticeEvaluation {
            summary: "1/2 tokens matched".into(),
            token_results: vec![],
            extra: serde_json::json!({}),
        },
        generated_observation_ids: vec![],
        generated_review_item_ids: vec![],
    };
    repo.create_practice_attempt(&attempt).unwrap();
    assert_eq!(
        repo.get_practice_attempt(&attempt.id).unwrap(),
        Some(attempt.clone())
    );

    let review = ReviewItem {
        id: ReviewItemId::parse("review-1").unwrap(),
        source: ReviewSource {
            kind: ReviewSourceKind::PracticeFailure,
            id: Some(attempt.id.as_str().into()),
            practice_attempt_id: Some(attempt.id.clone()),
            lexical_entry_id: None,
        },
        anchors: item.anchors.clone(),
        prompt_snapshot: item.prompt_snapshot.clone(),
        status: ReviewItemStatus::Active,
        created_at_ms: 4,
        updated_at_ms: 4,
    };
    repo.create_review_item(&review).unwrap();
    assert_eq!(
        repo.get_review_item(&review.id).unwrap(),
        Some(review.clone())
    );
    assert_eq!(
        repo.list_review_items(Some(ReviewItemStatus::Active), 10, 0)
            .unwrap(),
        vec![review.clone()]
    );

    let event = LearningEvent {
        id: LearningEventId::parse("event-1").unwrap(),
        occurred_at_ms: 5,
        kind: LearningEventKind::PracticeCompleted,
        subject: LearningEventSubject {
            kind: LearningEventSubjectKind::PracticeAttempt,
            id: attempt.id.as_str().into(),
        },
        payload: serde_json::json!({"result": "partial"}),
        session_id: Some(session.id),
    };
    repo.append_learning_event(&event).unwrap();
    assert_eq!(repo.list_learning_events(10, 0).unwrap(), vec![event]);

    // Query columns are projections of the JSON snapshot: re-upserting the
    // same id with changed fields must rewrite the columns together with the
    // JSON, or column-filtered queries diverge from the stored document.
    let mut updated_item = item.clone();
    updated_item.kind = PracticeKind::Cloze;
    repo.create_practice_item(&updated_item).unwrap();
    let kind_column: String = repo
        .connection
        .lock()
        .unwrap()
        .query_row(
            "SELECT kind FROM practice_items WHERE id=?1",
            [updated_item.id.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        kind_column,
        serde_json::to_string(&PracticeKind::Cloze).unwrap()
    );
    assert_eq!(
        repo.get_practice_item(&updated_item.id).unwrap(),
        Some(updated_item)
    );

    let mut updated_attempt = attempt.clone();
    updated_attempt.result = PracticeResult::Correct;
    repo.create_practice_attempt(&updated_attempt).unwrap();
    let result_column: String = repo
        .connection
        .lock()
        .unwrap()
        .query_row(
            "SELECT result FROM practice_attempts WHERE id=?1",
            [updated_attempt.id.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        result_column,
        serde_json::to_string(&PracticeResult::Correct).unwrap()
    );

    let mut archived_review = review.clone();
    archived_review.status = ReviewItemStatus::Archived;
    archived_review.updated_at_ms = 6;
    repo.create_review_item(&archived_review).unwrap();
    assert_eq!(
        repo.list_review_items(Some(ReviewItemStatus::Active), 10, 0)
            .unwrap(),
        Vec::<ReviewItem>::new()
    );
    assert_eq!(
        repo.list_review_items(Some(ReviewItemStatus::Archived), 10, 0)
            .unwrap(),
        vec![archived_review]
    );
}

#[test]
fn session_summary_derives_stuck_point_statuses_from_events_attempts_and_review() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone());

    let session = services
        .create_practice_session(application::CreatePracticeSession {
            mode: PracticeMode::Intensive,
            media_id: None,
            track_id: None,
            source: Some("test".into()),
        })
        .unwrap();
    let sentence_id = SubtitleSentenceId::parse("sentence-summary-1").unwrap();
    let target = PracticeTarget {
        kind: PracticeTargetKind::Sentence,
        id: Some(sentence_id.as_str().into()),
        sentence_id: Some(sentence_id.clone()),
        chunk_id: None,
        start_ms: Some(100),
        end_ms: Some(900),
    };
    let anchors = vec![PracticeAnchor {
        kind: PracticeAnchorKind::Sentence,
        id: sentence_id.as_str().into(),
        label: Some("would have gone".into()),
        lexical_entry_id: None,
        sentence_id: Some(sentence_id),
        token_start: Some(0),
        token_end: Some(2),
        start_ms: Some(100),
        end_ms: Some(900),
    }];

    services
        .mark_stuck_point(application::RecordStuckPointInput {
            session_id: session.id.clone(),
            target: target.clone(),
            anchors: anchors.clone(),
            label: Some("would have gone".into()),
            diagnosis_hints: vec![],
        })
        .unwrap();
    services
        .record_diagnosis_view(application::RecordDiagnosisViewInput {
            session_id: session.id.clone(),
            target: target.clone(),
            anchors: anchors.clone(),
            label: Some("would have gone".into()),
            diagnosis_hints: vec![application::DiagnosisHintEvidence {
                kind: "recognition_barrier".into(),
                reasons: vec!["weak_form".into()],
            }],
        })
        .unwrap();
    let item = services
        .create_practice_item(application::CreatePracticeItem {
            session_id: Some(session.id.clone()),
            kind: PracticeKind::Dictation,
            target: target.clone(),
            prompt_snapshot: "would have gone".into(),
            expected_text: "would have gone".into(),
            anchors: anchors.clone(),
        })
        .unwrap();
    services
        .submit_practice_attempt(application::SubmitPracticeAttempt {
            item_id: item.id.clone(),
            text_answer: "would have gone".into(),
            create_review_item_on_failure: false,
        })
        .unwrap();

    let failed_item = services
        .create_practice_item(application::CreatePracticeItem {
            session_id: Some(session.id.clone()),
            kind: PracticeKind::Dictation,
            target: PracticeTarget {
                kind: PracticeTargetKind::Chunk,
                id: Some("chunk-summary-1".into()),
                sentence_id: target.sentence_id.clone(),
                chunk_id: Some(ChunkId::parse("chunk-summary-1").unwrap()),
                start_ms: Some(1000),
                end_ms: Some(1400),
            },
            prompt_snapshot: "going to".into(),
            expected_text: "going to".into(),
            anchors,
        })
        .unwrap();
    services
        .submit_practice_attempt(application::SubmitPracticeAttempt {
            item_id: failed_item.id,
            text_answer: "gonna".into(),
            create_review_item_on_failure: true,
        })
        .unwrap();

    let summary = services.practice_session_summary(&session.id).unwrap();
    assert_eq!(summary.stuck_count, 2);
    assert_eq!(summary.resolved_count, 1);
    assert_eq!(summary.active_verified_count, 1);
    assert_eq!(summary.review_count, 1);
    assert_eq!(summary.open_count, 0);
    assert_eq!(
        summary.stuck_points[0].status,
        application::StuckPointStatus::ActivelyVerified
    );
    assert_eq!(
        summary.attribution_counts[0].reason.as_deref(),
        Some("weak_form")
    );

    let completed = services
        .complete_practice_session(
            &session.id,
            application::CompletePracticeSessionInput {
                mark_familiar: true,
            },
        )
        .unwrap();
    assert!(completed.session.ended_at_ms.is_some());
    assert!(completed.familiar_material_marked);
}
