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
            media_id: None,
            track_id: None,
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
    let schedule = ReviewSchedule {
        item_id: review.id.clone(),
        algorithm: "listen_review_v1_heuristic_proxy".into(),
        due_at_ms: 10,
        stability: None,
        difficulty: None,
        interval_days: None,
        lapse_count: 0,
        last_reviewed_at_ms: None,
        review_count: 0,
    };
    repo.save_review_schedule(&schedule).unwrap();
    assert_eq!(
        repo.get_review_schedule(&review.id).unwrap(),
        Some(schedule.clone())
    );
    assert_eq!(repo.list_due_review_items(9, 10).unwrap(), vec![]);
    assert_eq!(
        repo.list_due_review_items(10, 10).unwrap(),
        vec![(review.clone(), schedule)]
    );

    let inbox_item = ListeningInboxItem {
        id: ListeningInboxItemId::parse("inbox-1").unwrap(),
        session_id: Some(session.id.clone()),
        media_id: None,
        track_id: None,
        target: item.target.clone(),
        anchors: item.anchors.clone(),
        label: Some("hello world".into()),
        subtitle_snapshot: "hello world".into(),
        context_before: None,
        context_after: Some("after".into()),
        captured_at_ms: 5,
        expires_at_ms: Some(7 * 24 * 60 * 60 * 1000),
        status: ListeningInboxStatus::Active,
        resolution: None,
        review_item_ids: vec![],
        practice_item_id: None,
        updated_at_ms: 5,
    };
    repo.upsert_listening_inbox_item(&inbox_item).unwrap();
    assert_eq!(
        repo.get_listening_inbox_item(&inbox_item.id).unwrap(),
        Some(inbox_item.clone())
    );
    assert_eq!(
        repo.list_listening_inbox_items(Some(ListeningInboxStatus::Active), 10, 0)
            .unwrap(),
        vec![inbox_item.clone()]
    );

    let mut archived_inbox_item = inbox_item.clone();
    archived_inbox_item.status = ListeningInboxStatus::Archived;
    archived_inbox_item.resolution = Some(ListeningInboxResolution::ReviewItem);
    archived_inbox_item.review_item_ids = vec![review.id.clone()];
    archived_inbox_item.updated_at_ms = 6;
    repo.upsert_listening_inbox_item(&archived_inbox_item)
        .unwrap();
    assert_eq!(
        repo.list_listening_inbox_items(Some(ListeningInboxStatus::Active), 10, 0)
            .unwrap(),
        Vec::<ListeningInboxItem>::new()
    );
    assert_eq!(
        repo.list_listening_inbox_items(Some(ListeningInboxStatus::Archived), 10, 0)
            .unwrap(),
        vec![archived_inbox_item.clone()]
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
fn hunting_list_enforces_five_active_targets_and_allows_replacement_after_archive() {
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
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone());
    let entries = (0..6)
        .map(|index| {
            upsert_word_asset(
                &services,
                "en",
                &format!("target-{index}"),
                &format!("Target {index}"),
                None,
                None,
            )
            .entry
        })
        .collect::<Vec<_>>();

    let mut targets = Vec::new();
    for entry in entries.iter().take(5) {
        targets.push(
            services
                .practice_learning()
                .create_hunting_target(application::CreateHuntingTargetInput {
                    lexical_entry_id: entry.id.clone(),
                    source_kind: HuntingTargetSourceKind::Manual,
                    source_id: None,
                })
                .unwrap(),
        );
    }
    assert!(matches!(
        services
            .practice_learning()
            .create_hunting_target(application::CreateHuntingTargetInput {
                lexical_entry_id: entries[5].id.clone(),
                source_kind: HuntingTargetSourceKind::Manual,
                source_id: None,
            }),
        Err(ApplicationError::Conflict(
            "hunting list already has the maximum of 5 active targets"
        ))
    ));

    services
        .practice_learning()
        .archive_hunting_target(&targets[0].id)
        .unwrap();
    let replacement = services
        .practice_learning()
        .create_hunting_target(application::CreateHuntingTargetInput {
            lexical_entry_id: entries[5].id.clone(),
            source_kind: HuntingTargetSourceKind::Manual,
            source_id: None,
        })
        .unwrap();
    assert_eq!(replacement.target_snapshot, "Target 5");
    assert_eq!(
        services
            .practice_learning()
            .list_hunting_targets(Some(HuntingTargetStatus::Active), 10, 0)
            .unwrap()
            .len(),
        5
    );
}

#[test]
fn hunting_occurrences_use_media_corpus_and_three_way_checks_keep_not_noticed_evidence_free() {
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
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_corpus_index_repository(repo.clone());
    let media = services
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/hunting.mp4".into(),
            fingerprint: "hunting-media".into(),
            title: "Hunting media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
            retain: None,
        })
        .unwrap();
    let track = services
        .media_analysis()
        .import_subtitle(ImportSubtitle {
            media_id: media.id.clone(),
            source_name: "timeline.srt".into(),
            content: include_bytes!("../../../../testdata/subtitles/timeline.srt").to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    let lexical = upsert_word_asset(&services, "en", "hello", "hello", None, None);
    let target = services
        .practice_learning()
        .create_hunting_target(application::CreateHuntingTargetInput {
            lexical_entry_id: lexical.entry.id.clone(),
            source_kind: HuntingTargetSourceKind::Manual,
            source_id: None,
        })
        .unwrap();

    let located = services
        .practice_learning()
        .hunting_occurrences(&media.id, Some(&track.id))
        .unwrap();
    assert!(located.indexed);
    assert_eq!(located.occurrences.len(), 1);
    let occurrence = &located.occurrences[0];
    assert_eq!(occurrence.target_id, target.id);
    assert_eq!(occurrence.occurrence.display_text, "Hello");

    let session = services
        .practice_learning()
        .create_practice_session(application::CreatePracticeSession {
            mode: PracticeMode::Extensive,
            media_id: Some(media.id.clone()),
            track_id: Some(track.id.clone()),
            source: Some("hunting_test".into()),
        })
        .unwrap();
    let recognized = services
        .practice_learning()
        .submit_hunting_check(application::SubmitHuntingCheckInput {
            session_id: session.id.clone(),
            target_id: target.id.clone(),
            occurrence_id: occurrence.occurrence.id.clone(),
            answer: HuntingCheckAnswer::Recognized,
        })
        .unwrap();
    assert!(recognized.observation_id.is_some());
    assert_eq!(
        repo.list_lexical_observations_by_sentence(
            occurrence.occurrence.sentence_id.as_ref().unwrap()
        )
        .unwrap()[0]
            .result,
        ObservationResult::RecognizedInContext
    );

    let not_noticed = services
        .practice_learning()
        .submit_hunting_check(application::SubmitHuntingCheckInput {
            session_id: session.id.clone(),
            target_id: target.id,
            occurrence_id: occurrence.occurrence.id.clone(),
            answer: HuntingCheckAnswer::NotNoticed,
        })
        .unwrap();
    assert!(not_noticed.observation_id.is_none());
    let events = repo
        .list_learning_events_for_session(&session.id, 100, 0)
        .unwrap();
    assert_eq!(
        events
            .iter()
            .filter(|event| event.kind == LearningEventKind::HuntingCheckAnswered)
            .count(),
        2
    );
}

#[test]
fn practice_attempts_append_channelized_observations_for_success_and_failure() {
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
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone());
    let lexical = upsert_word_asset(&services, "en", "signal", "signals", None, None);
    // Anchor without a sentence: channelized evidence must still be recorded
    // even where the legacy (entry, sentence)-keyed path cannot write.
    let anchors = vec![PracticeAnchor {
        kind: PracticeAnchorKind::LexicalEntry,
        id: lexical.entry.id.as_str().into(),
        label: Some("signals".into()),
        lexical_entry_id: Some(lexical.entry.id.clone()),
        sentence_id: None,
        token_start: None,
        token_end: None,
        start_ms: None,
        end_ms: None,
    }];
    let target = PracticeTarget {
        kind: PracticeTargetKind::Lexical,
        id: Some(lexical.entry.id.as_str().into()),
        sentence_id: None,
        start_ms: None,
        end_ms: None,
    };
    let correct_item = services
        .practice_learning()
        .create_practice_item(application::CreatePracticeItem {
            session_id: None,
            kind: PracticeKind::Dictation,
            target: target.clone(),
            prompt_snapshot: "signals".into(),
            expected_text: "signals".into(),
            anchors: anchors.clone(),
        })
        .unwrap();
    let correct = services
        .practice_learning()
        .submit_practice_attempt(application::SubmitPracticeAttempt {
            item_id: correct_item.id,
            text_answer: "signals".into(),
            create_review_item_on_failure: false,
        })
        .unwrap();
    assert_eq!(correct.result, PracticeResult::Correct);

    let failed_item = services
        .practice_learning()
        .create_practice_item(application::CreatePracticeItem {
            session_id: None,
            kind: PracticeKind::Dictation,
            target,
            prompt_snapshot: "signals".into(),
            expected_text: "signals".into(),
            anchors,
        })
        .unwrap();
    let failed = services
        .practice_learning()
        .submit_practice_attempt(application::SubmitPracticeAttempt {
            item_id: failed_item.id,
            text_answer: "single".into(),
            create_review_item_on_failure: false,
        })
        .unwrap();
    assert_ne!(failed.result, PracticeResult::Correct);
    // Legacy path stays failure-only and sentence-keyed: nothing there.
    assert!(failed.generated_observation_ids.is_empty());

    let channelized = repo
        .list_learning_observations(&lexical.entry.id, None, 10, 0)
        .unwrap();
    assert_eq!(channelized.len(), 2);
    let outcomes: Vec<_> = channelized
        .iter()
        .map(|observation| observation.outcome)
        .collect();
    assert!(outcomes.contains(&ObservationOutcome::Success));
    assert!(outcomes.iter().any(|o| *o != ObservationOutcome::Success));
    for observation in &channelized {
        assert_eq!(observation.capability, LexicalCapability::Listening);
        assert_eq!(observation.task_type, ObservationTaskType::Dictation);
        assert_eq!(observation.assistance, AssistanceLevel::None);
        assert_eq!(observation.origin, ObservationOrigin::PracticeTask);
        assert_eq!(observation.surface_form.as_deref(), Some("signals"));
        assert!(observation.sentence_id.is_none());
    }
}

#[test]
fn listening_inbox_capture_process_review_and_micro_intensive_round_trip() {
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
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone());

    let session = services
        .practice_learning()
        .create_practice_session(application::CreatePracticeSession {
            mode: PracticeMode::Extensive,
            media_id: None,
            track_id: None,
            source: Some("extensive_listening".into()),
        })
        .unwrap();
    let sentence_id = SubtitleSentenceId::parse("sentence-inbox-1").unwrap();
    let target = PracticeTarget {
        kind: PracticeTargetKind::Sentence,
        id: Some(sentence_id.as_str().into()),
        sentence_id: Some(sentence_id.clone()),
        start_ms: Some(1_000),
        end_ms: Some(2_400),
    };
    let anchors = vec![PracticeAnchor {
        kind: PracticeAnchorKind::Sentence,
        id: sentence_id.as_str().into(),
        label: Some("I missed that line".into()),
        lexical_entry_id: None,
        sentence_id: Some(sentence_id),
        token_start: Some(0),
        token_end: Some(4),
        start_ms: Some(1_000),
        end_ms: Some(2_400),
    }];

    let first = services
        .practice_learning()
        .capture_listening_inbox_item(application::CaptureListeningInboxItemInput {
            session_id: session.id.clone(),
            target: target.clone(),
            anchors: anchors.clone(),
            label: Some("I missed that line".into()),
            subtitle_snapshot: "I missed that line".into(),
            context_before: Some("before".into()),
            context_after: Some("after".into()),
            expires_in_days: Some(7),
        })
        .unwrap();
    assert_eq!(first.status, ListeningInboxStatus::Active);
    assert_eq!(
        services
            .practice_learning()
            .list_listening_inbox_items(Some(ListeningInboxStatus::Active), 10, 0)
            .unwrap()
            .len(),
        1
    );

    let reviewed = services
        .practice_learning()
        .process_listening_inbox_item(
            &first.id,
            application::ProcessListeningInboxItemInput {
                resolution: ListeningInboxResolution::ReviewItem,
            },
        )
        .unwrap();
    assert_eq!(reviewed.status, ListeningInboxStatus::Archived);
    assert_eq!(
        reviewed.resolution,
        Some(ListeningInboxResolution::ReviewItem)
    );
    assert_eq!(reviewed.review_item_ids.len(), 1);
    let review = repo
        .get_review_item(&reviewed.review_item_ids[0])
        .unwrap()
        .unwrap();
    assert_eq!(review.source.kind, ReviewSourceKind::ListeningInbox);

    let second = services
        .practice_learning()
        .capture_listening_inbox_item(application::CaptureListeningInboxItemInput {
            session_id: session.id.clone(),
            target: target.clone(),
            anchors: anchors.clone(),
            label: Some("Still fuzzy".into()),
            subtitle_snapshot: "Still fuzzy".into(),
            context_before: None,
            context_after: None,
            expires_in_days: Some(7),
        })
        .unwrap();
    let micro = services
        .practice_learning()
        .process_listening_inbox_item(
            &second.id,
            application::ProcessListeningInboxItemInput {
                resolution: ListeningInboxResolution::MicroIntensive,
            },
        )
        .unwrap();
    assert_eq!(
        micro.resolution,
        Some(ListeningInboxResolution::MicroIntensive)
    );
    let practice_item_id = micro.practice_item_id.as_ref().unwrap();
    assert!(repo.get_practice_item(practice_item_id).unwrap().is_some());

    let invalid_summary = services.practice_learning().complete_listening_session(
        &session.id,
        application::CompleteListeningSessionInput {
            comprehension_report: None,
            hunting_summary: Some(application::HuntingCompletionSummary {
                prompted_count: 5,
                recognized_count: 3,
                not_recognized_count: 2,
                not_noticed_count: 1,
            }),
        },
    );
    assert!(matches!(
        invalid_summary,
        Err(application::ApplicationError::Validation(_))
    ));

    services
        .practice_learning()
        .complete_listening_session(
            &session.id,
            application::CompleteListeningSessionInput {
                comprehension_report: Some(ListeningComprehensionReport::GotTheGist),
                hunting_summary: Some(application::HuntingCompletionSummary {
                    prompted_count: 3,
                    recognized_count: 1,
                    not_recognized_count: 1,
                    not_noticed_count: 1,
                }),
            },
        )
        .unwrap();
    let events = repo
        .list_learning_events_for_session(&session.id, 100, 0)
        .unwrap();
    assert!(
        events
            .iter()
            .any(|event| event.kind == LearningEventKind::ListeningInboxCaptured)
    );
    let completed = events
        .iter()
        .find(|event| event.kind == LearningEventKind::ListeningCompleted)
        .unwrap();
    assert_eq!(
        completed.payload["comprehension_report"],
        serde_json::json!("got_the_gist")
    );
    assert_eq!(
        completed.payload["hunting_summary"],
        serde_json::json!({
            "prompted_count": 3,
            "recognized_count": 1,
            "not_recognized_count": 1,
            "not_noticed_count": 1,
        })
    );
}

#[test]
fn review_queries_enforce_limits_and_custom_study_is_read_only() {
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
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone());
    let practice = services.practice_learning();
    let make_item = |source_kind, prompt: &str| {
        practice
            .create_review_item(application::CreateReviewItem {
                source: ReviewSource {
                    kind: source_kind,
                    id: Some(prompt.into()),
                    practice_attempt_id: None,
                    lexical_entry_id: None,
                    media_id: None,
                    track_id: None,
                },
                anchors: Vec::new(),
                prompt_snapshot: prompt.into(),
            })
            .unwrap()
    };
    let completed_new = make_item(ReviewSourceKind::Sentence, "completed-new");
    let extra_new = make_item(ReviewSourceKind::Chunk, "extra-new");
    let ahead = make_item(ReviewSourceKind::LexicalEntry, "ahead");
    let listening_item = make_item(ReviewSourceKind::Sentence, "listening-item");
    let forgotten = make_item(ReviewSourceKind::ConnectedSpeech, "forgotten");
    let now = application::now_ms();
    for (item, due, lapses) in [
        (&ahead, now + 5 * 86_400_000, 0),
        (&listening_item, now, 0),
        (&forgotten, now, 4),
    ] {
        repo.save_review_schedule(&ReviewSchedule {
            item_id: item.id.clone(),
            algorithm: "fsrs_6_default_v1".into(),
            due_at_ms: due,
            stability: Some(10.0),
            difficulty: Some(5.0),
            interval_days: Some(10.0),
            lapse_count: lapses,
            last_reviewed_at_ms: Some(now - 10 * 86_400_000),
            review_count: 3,
        })
        .unwrap();
    }

    let before_preview = repo.get_review_schedule(&extra_new.id).unwrap().unwrap();
    let previews = practice
        .review_interval_preview(&extra_new.id, Some(now))
        .unwrap();
    assert_eq!(previews.len(), 4);
    assert_eq!(
        repo.get_review_schedule(&extra_new.id).unwrap().unwrap(),
        before_preview
    );

    practice
        .update_review_daily_limits(application::ReviewDailyLimits {
            new_cards: 1,
            reviews: 100,
        })
        .unwrap();
    practice
        .submit_review_attempt(application::SubmitReviewAttempt {
            item_id: completed_new.id,
            rating: ReviewRating::Good,
        })
        .unwrap();
    let queue = practice
        .review_queue(Some(application::now_ms()), 100)
        .unwrap();
    assert!(queue.limit_status.new_limit_reached);
    assert!(
        queue
            .entries
            .iter()
            .all(|entry| entry.item.id != extra_new.id)
    );

    let schedule_snapshot = repo
        .list_review_items_with_schedules(100)
        .unwrap()
        .into_iter()
        .map(|(item, schedule)| (item.id, schedule))
        .collect::<std::collections::HashMap<_, _>>();
    let more_new = practice
        .custom_study(application::CustomStudyRequest {
            kind: application::CustomStudyKind::MoreNew,
            limit: Some(10),
            at_ms: Some(now),
        })
        .unwrap();
    assert!(
        more_new
            .entries
            .iter()
            .any(|entry| entry.item.id == extra_new.id)
    );
    assert!(!more_new.advances_normal_schedule);

    let review_ahead = practice
        .custom_study(application::CustomStudyRequest {
            kind: application::CustomStudyKind::ReviewAhead,
            limit: Some(10),
            at_ms: Some(now),
        })
        .unwrap();
    assert!(
        review_ahead
            .entries
            .iter()
            .any(|entry| entry.item.id == ahead.id)
    );
    assert!(review_ahead.advances_normal_schedule);

    let forgotten_queue = practice
        .custom_study(application::CustomStudyRequest {
            kind: application::CustomStudyKind::Forgotten {
                minimum_lapses: Some(3),
            },
            limit: Some(10),
            at_ms: Some(now),
        })
        .unwrap();
    assert_eq!(forgotten_queue.entries[0].item.id, forgotten.id);
    let extra_practice = practice
        .submit_custom_study_attempt(application::SubmitCustomStudyAttempt {
            item_id: extra_new.id.clone(),
            rating: ReviewRating::Good,
            kind: application::CustomStudyKind::MoreNew,
        })
        .unwrap();
    assert!(!extra_practice.attempt.advances_schedule);
    assert_eq!(extra_practice.schedule, before_preview);
    let after_custom = repo
        .list_review_items_with_schedules(100)
        .unwrap()
        .into_iter()
        .map(|(item, schedule)| (item.id, schedule))
        .collect::<std::collections::HashMap<_, _>>();
    assert_eq!(schedule_snapshot, after_custom);

    let overview = practice.review_deck_overview(Some(now)).unwrap();
    assert_eq!(overview.counts.due, 2);
}
