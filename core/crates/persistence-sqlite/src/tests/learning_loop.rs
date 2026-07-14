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
fn shadowing_completion_persists_recording_without_creating_capability_evidence() {
    let recording_path = write_shadowing_wav("recording", 900, 450, 600);
    let reference_path = write_shadowing_wav("reference", 800, 400, 550);
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
    .with_recording_repository(repo.clone());
    let session = services
        .practice_learning()
        .create_practice_session(application::CreatePracticeSession {
            mode: PracticeMode::Intensive,
            media_id: None,
            track_id: None,
            source: Some("shadowing-test".into()),
        })
        .unwrap();
    let target = PracticeTarget {
        kind: PracticeTargetKind::Chunk,
        id: Some("chunk-1".into()),
        sentence_id: Some(SubtitleSentenceId::parse("sentence-1").unwrap()),
        chunk_id: Some(ChunkId::parse("chunk-1").unwrap()),
        start_ms: Some(100),
        end_ms: Some(900),
    };
    let item = services
        .practice_learning()
        .create_practice_item(application::CreatePracticeItem {
            session_id: Some(session.id.clone()),
            kind: PracticeKind::Shadowing,
            target: target.clone(),
            prompt_snapshot: "follow this chunk".into(),
            expected_text: "follow this chunk".into(),
            anchors: vec![],
        })
        .unwrap();
    let recording = services
        .recordings()
        .create_recording_asset(application::CreateRecordingAsset {
            file_path: recording_path.to_string_lossy().into_owned(),
            duration_ms: 900,
            target,
            source_segment: PlayableSegment {
                media_id: None,
                start_ms: 100,
                end_ms: 900,
                label: "chunk 1".into(),
                subtitle_snapshot: "follow this chunk".into(),
                availability: PlayableSegmentAvailability::Available,
            },
            language: LanguageCode::parse("en").unwrap(),
            audio: RecordingAudioMetadata {
                container: "wav".into(),
                codec: "pcm_s16le".into(),
                sample_rate_hz: 16_000,
                channels: 1,
                sample_format: "s16".into(),
                byte_length: 24_960,
                content_sha256: "a".repeat(64),
            },
            recorder_version: "flutter-recorder-v1".into(),
        })
        .unwrap();
    let attempt = services
        .recordings()
        .complete_shadowing_attempt(application::CompleteShadowingAttempt {
            item_id: item.id,
            recording_id: recording.id.clone(),
        })
        .unwrap();

    assert_eq!(attempt.result, PracticeResult::Completed);
    assert_eq!(attempt.score, None);
    assert!(attempt.generated_observation_ids.is_empty());
    assert!(attempt.generated_review_item_ids.is_empty());
    // Phase 3.11 boundary extension: a non-scored shadowing completion also
    // creates no semantic fact — constructed speaking success can only come
    // from a semantic task judgment, never from imitation completion.
    for table in ["semantic_task_attempts", "semantic_judgments"] {
        let semantic_rows: i64 = repo
            .connection
            .lock()
            .unwrap()
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(semantic_rows, 0, "{table} must stay empty");
    }
    let linked = services
        .recordings()
        .recording_asset(&recording.id)
        .unwrap()
        .unwrap();
    assert_eq!(linked.practice_attempt_id, Some(attempt.id.clone()));
    assert_eq!(
        services
            .recordings()
            .complete_shadowing_attempt(application::CompleteShadowingAttempt {
                item_id: attempt.item_id.clone(),
                recording_id: recording.id.clone(),
            })
            .unwrap()
            .id,
        attempt.id
    );
    let comparison = services
        .recordings()
        .compare_shadowing(application::CreateShadowingComparison {
            recording_id: recording.id.clone(),
            reference_wav_path: reference_path.to_string_lossy().into_owned(),
        })
        .unwrap();
    assert_eq!(comparison.duration_delta_ms, 100);
    assert_eq!(comparison.pause_alignment.reference_pauses.len(), 1);
    assert_eq!(comparison.pause_alignment.recording_pauses.len(), 1);
    assert!(!comparison.reference_waveform.peaks.is_empty());
    let events = repo
        .list_learning_events_for_session(&session.id, 10, 0)
        .unwrap();
    assert!(
        events
            .iter()
            .any(|event| event.payload["evaluation_kind"] == "not_scored"),
        "shadowing completion must emit an explicit unscored event"
    );
    assert_eq!(
        services
            .recordings()
            .delete_recording_asset(&recording.id)
            .unwrap(),
        Some(linked)
    );
    assert!(
        services
            .recordings()
            .recording_asset(&recording.id)
            .unwrap()
            .is_none()
    );
    let _ = std::fs::remove_file(recording_path);
    let _ = std::fs::remove_file(reference_path);
}

fn write_shadowing_wav(
    label: &str,
    duration_ms: u64,
    pause_start_ms: u64,
    pause_end_ms: u64,
) -> std::path::PathBuf {
    let sample_rate = 16_000_u32;
    let sample_count = duration_ms as u32 * sample_rate / 1000;
    let data_size = sample_count * 2;
    let mut bytes = Vec::with_capacity(44 + data_size as usize);
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&(36 + data_size).to_le_bytes());
    bytes.extend_from_slice(b"WAVEfmt \x10\0\0\0\x01\0\x01\0");
    bytes.extend_from_slice(&sample_rate.to_le_bytes());
    bytes.extend_from_slice(&(sample_rate * 2).to_le_bytes());
    bytes.extend_from_slice(&2_u16.to_le_bytes());
    bytes.extend_from_slice(&16_u16.to_le_bytes());
    bytes.extend_from_slice(b"data");
    bytes.extend_from_slice(&data_size.to_le_bytes());
    for index in 0..sample_count {
        let time_ms = index as u64 * 1000 / sample_rate as u64;
        let sample = if (pause_start_ms..pause_end_ms).contains(&time_ms) {
            0_i16
        } else {
            8_000_i16
        };
        bytes.extend_from_slice(&sample.to_le_bytes());
    }
    let path = std::env::temp_dir().join(format!(
        "llplayer-{label}-{}-{}.wav",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::write(&path, bytes).unwrap();
    path
}

#[test]
fn failed_review_records_context_evidence_and_hunting_candidate_without_status_change() {
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
    let media = services
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/review-evidence.mp4".into(),
            fingerprint: "review-evidence".into(),
            title: "Review evidence".into(),
            kind: MediaKind::Video,
            duration_ms: Some(5_000),
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
    let sentence = &track.sentences[0];
    let lexical = upsert_word_asset(
        &services,
        "en",
        "hello",
        "Hello",
        Some(LearningStatus::KnownNotRecognized),
        None,
    );
    let review = services
        .practice_learning()
        .create_review_item(application::CreateReviewItem {
            source: ReviewSource {
                kind: ReviewSourceKind::PracticeFailure,
                id: None,
                practice_attempt_id: None,
                lexical_entry_id: Some(lexical.entry.id.clone()),
                media_id: Some(media.id),
                track_id: Some(track.id.clone()),
            },
            anchors: vec![PracticeAnchor {
                kind: PracticeAnchorKind::LexicalEntry,
                id: lexical.entry.id.as_str().into(),
                label: Some("Hello".into()),
                lexical_entry_id: Some(lexical.entry.id.clone()),
                sentence_id: Some(sentence.id.clone()),
                token_start: Some(0),
                token_end: Some(0),
                start_ms: Some(sentence.start.get()),
                end_ms: Some(sentence.end.get()),
            }],
            prompt_snapshot: sentence.display_text.clone(),
        })
        .unwrap();

    let submission = services
        .practice_learning()
        .submit_review_attempt(application::SubmitReviewAttempt {
            item_id: review.id.clone(),
            rating: ReviewRating::Again,
        })
        .unwrap();

    assert_eq!(submission.generated_observation_ids.len(), 1);
    assert_eq!(submission.hunting_candidate_ids.len(), 1);
    let observations = repo
        .list_lexical_observations_by_sentence(&sentence.id)
        .unwrap();
    assert_eq!(observations.len(), 1);
    assert_eq!(
        observations[0].result,
        ObservationResult::NotRecognizedInContext
    );
    let candidates = services
        .practice_learning()
        .hunting_candidates(Some(HuntingCandidateStatus::Active), 10, 0)
        .unwrap();
    assert_eq!(candidates.len(), 1);
    assert_eq!(candidates[0].review_item_id, review.id);
    assert_eq!(candidates[0].failure_count, 1);
    assert_eq!(candidates[0].target_snapshot, "Hello");
    let target = services
        .practice_learning()
        .create_hunting_target(application::CreateHuntingTargetInput {
            lexical_entry_id: lexical.entry.id.clone(),
            source_kind: HuntingTargetSourceKind::ReviewCandidate,
            source_id: Some(candidates[0].id.as_str().into()),
        })
        .unwrap();
    assert_eq!(target.target_snapshot, "Hello");
    assert_eq!(target.status, HuntingTargetStatus::Active);
    assert_eq!(
        services
            .practice_learning()
            .list_hunting_targets(Some(HuntingTargetStatus::Active), 10, 0)
            .unwrap(),
        vec![target.clone()]
    );
    assert_eq!(
        services
            .practice_learning()
            .list_hunting_candidates(Some(HuntingCandidateStatus::Consumed), 10, 0)
            .unwrap()[0]
            .id,
        candidates[0].id
    );
    let archived = services
        .practice_learning()
        .archive_hunting_target(&target.id)
        .unwrap();
    assert_eq!(archived.status, HuntingTargetStatus::Archived);
    assert!(
        services
            .practice_learning()
            .list_hunting_targets(Some(HuntingTargetStatus::Active), 10, 0)
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        services
            .lexical_learning()
            .lexical_details(&lexical.entry.id)
            .unwrap()
            .unwrap()
            .entry
            .status,
        Some(LearningStatus::KnownNotRecognized)
    );

    // ADR 0017: the same failed review also lands one channelized
    // listening observation, deduplicated across source and anchors.
    let channelized = repo
        .list_learning_observations(&lexical.entry.id, Some(LexicalCapability::Listening), 10, 0)
        .unwrap();
    assert_eq!(channelized.len(), 1);
    assert_eq!(channelized[0].task_type, ObservationTaskType::ReviewRecall);
    assert_eq!(channelized[0].outcome, ObservationOutcome::Failure);
    assert_eq!(channelized[0].assistance, AssistanceLevel::None);
    assert_eq!(channelized[0].origin, ObservationOrigin::ReviewTask);
    assert_eq!(channelized[0].surface_form.as_deref(), Some("Hello"));
    assert_eq!(
        channelized[0].source_ref.as_deref(),
        Some(submission.attempt.id.as_str())
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
        chunk_id: None,
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
fn recognition_evidence_deduplicates_context_and_upgrade_history_round_trips() {
    let repo = SqliteRepository::in_memory().unwrap();
    let lexical_entry_id = LexicalEntryId::parse("lexical-upgrade-1").unwrap();
    let first = RecognitionEvidence {
        id: RecognitionEvidenceId::parse("evidence-1").unwrap(),
        lexical_entry_id: lexical_entry_id.clone(),
        context_key: "sentence:one".into(),
        sentence_id: Some(SubtitleSentenceId::parse("one").unwrap()),
        media_id: None,
        source_kind: RecognitionEvidenceSourceKind::Review,
        source_id: "review-attempt-1".into(),
        occurred_at_ms: 10,
    };
    repo.upsert_recognition_evidence(&first).unwrap();
    let mut replacement = first.clone();
    replacement.id = RecognitionEvidenceId::parse("evidence-replacement").unwrap();
    replacement.source_id = "review-attempt-2".into();
    replacement.occurred_at_ms = 20;
    let saved = repo.upsert_recognition_evidence(&replacement).unwrap();
    assert_eq!(saved.source_id, "review-attempt-2");
    assert_eq!(
        repo.list_recognition_evidence(&lexical_entry_id, 10, 0)
            .unwrap()
            .len(),
        1
    );

    let suggestion = UpgradeSuggestion {
        id: UpgradeSuggestionId::parse("suggestion-1").unwrap(),
        lexical_entry_id: lexical_entry_id.clone(),
        lexical_display_form: "would have".into(),
        previous_status: LearningStatus::KnownNotRecognized,
        suggested_status: LearningStatus::KnownRecognized,
        status: UpgradeSuggestionStatus::Pending,
        evidence_context_count: 5,
        evidence_ids: vec![first.id],
        threshold: 5,
        evidence_class: "heuristic_proxy".into(),
        created_at_ms: 30,
        resolved_at_ms: None,
        cooldown_until_ms: None,
        capability: None,
        previous_assessment: None,
        suggested_assessment: None,
    };
    repo.save_upgrade_suggestion(&suggestion).unwrap();
    assert_eq!(
        repo.list_upgrade_suggestions(
            Some(&lexical_entry_id),
            Some(UpgradeSuggestionStatus::Pending),
            10,
            0,
        )
        .unwrap(),
        vec![suggestion]
    );
}

#[test]
fn five_distinct_review_contexts_require_confirmation_before_status_upgrade() {
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
    let lexical = upsert_word_asset(
        &services,
        "en",
        "would",
        "would",
        Some(LearningStatus::KnownNotRecognized),
        None,
    );
    let mut generated = Vec::new();
    for index in 0..5 {
        let sentence_id = SubtitleSentenceId::parse(format!("upgrade-context-{index}")).unwrap();
        let review = services
            .practice_learning()
            .create_review_item(application::CreateReviewItem {
                source: ReviewSource {
                    kind: ReviewSourceKind::Sentence,
                    id: Some(sentence_id.as_str().into()),
                    practice_attempt_id: None,
                    lexical_entry_id: Some(lexical.entry.id.clone()),
                    media_id: None,
                    track_id: None,
                },
                anchors: vec![PracticeAnchor {
                    kind: PracticeAnchorKind::LexicalEntry,
                    id: lexical.entry.id.as_str().into(),
                    label: Some("would".into()),
                    lexical_entry_id: Some(lexical.entry.id.clone()),
                    sentence_id: Some(sentence_id),
                    token_start: None,
                    token_end: None,
                    start_ms: None,
                    end_ms: None,
                }],
                prompt_snapshot: format!("context {index}"),
            })
            .unwrap();
        generated = services
            .practice_learning()
            .submit_review_attempt(application::SubmitReviewAttempt {
                item_id: review.id,
                rating: ReviewRating::Good,
            })
            .unwrap()
            .upgrade_suggestions;
    }
    assert_eq!(generated.len(), 1);
    assert_eq!(generated[0].evidence_context_count, 5);
    assert_eq!(generated[0].capability, Some(LexicalCapability::Listening));
    assert_eq!(
        generated[0].suggested_assessment,
        Some(CapabilityAssessment::Acquired)
    );
    assert_eq!(
        services
            .lexical_learning()
            .lexical_details(&lexical.entry.id)
            .unwrap()
            .unwrap()
            .entry
            .status,
        Some(LearningStatus::KnownNotRecognized)
    );

    let confirmed = services
        .lexical_learning()
        .confirm_upgrade_suggestion(&generated[0].id)
        .unwrap();
    assert_eq!(confirmed.status, UpgradeSuggestionStatus::Accepted);
    let details = services
        .lexical_learning()
        .lexical_details(&lexical.entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(details.entry.status, Some(LearningStatus::KnownRecognized));
    assert_eq!(
        details.history[0].change_source,
        LearningChangeSource::CapabilityOverrideSync
    );
    let profile = services
        .lexical_learning()
        .lexical_capability_profile(&lexical.entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::Acquired
    );
    // ADR 0019: the conclusion is derived from the observation stream by
    // listening-projection-v1, not written directly by the confirm handler.
    let projection = profile.listening.projection.as_ref().unwrap();
    assert_eq!(
        projection.algorithm_version,
        LISTENING_PROJECTION_ALGORITHM_VERSION
    );
    assert_eq!(
        projection.source,
        CapabilityProjectionSource::EvidenceProjection
    );
    assert_eq!(projection.confidence, Some(LISTENING_CONFIDENCE_TASK));
    assert!(projection.evidence_as_of_ms.is_some());
}

#[test]
fn listening_projection_flips_on_task_failure_and_blocks_self_report_upgrade() {
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
    // Word the user believes they can catch by ear (self-report / panel set).
    let lexical = upsert_word_asset(
        &services,
        "en",
        "gonna",
        "gonna",
        Some(LearningStatus::KnownRecognized),
        None,
    );

    // One failed audio review on a never-confirmed word flips the listening
    // view — the "看得懂听不出" discovery (ADR 0019 accepted behavior change).
    let review = services
        .practice_learning()
        .create_review_item(application::CreateReviewItem {
            source: ReviewSource {
                kind: ReviewSourceKind::LexicalEntry,
                id: Some(lexical.entry.id.as_str().into()),
                practice_attempt_id: None,
                lexical_entry_id: Some(lexical.entry.id.clone()),
                media_id: None,
                track_id: None,
            },
            anchors: vec![PracticeAnchor {
                kind: PracticeAnchorKind::LexicalEntry,
                id: lexical.entry.id.as_str().into(),
                label: Some("gonna".into()),
                lexical_entry_id: Some(lexical.entry.id.clone()),
                sentence_id: None,
                token_start: None,
                token_end: None,
                start_ms: None,
                end_ms: None,
            }],
            prompt_snapshot: "gonna".into(),
        })
        .unwrap();
    services
        .practice_learning()
        .submit_review_attempt(application::SubmitReviewAttempt {
            item_id: review.id,
            rating: ReviewRating::Again,
        })
        .unwrap();
    let details = services
        .lexical_learning()
        .lexical_details(&lexical.entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        details.entry.status,
        Some(LearningStatus::KnownNotRecognized)
    );
    let profile = services
        .lexical_learning()
        .lexical_capability_profile(&lexical.entry.id)
        .unwrap()
        .unwrap();
    let projection = profile.listening.projection.as_ref().unwrap();
    assert_eq!(
        projection.algorithm_version,
        LISTENING_PROJECTION_ALGORITHM_VERSION
    );
    assert_eq!(projection.confidence, Some(LISTENING_CONFIDENCE_TASK));

    // Writer ladder: re-declaring "认识" through the legacy status path may
    // not upgrade over the task-grade evidence conclusion (option A).
    upsert_word_asset(
        &services,
        "en",
        "gonna",
        "gonna",
        Some(LearningStatus::KnownRecognized),
        None,
    );
    let details = services
        .lexical_learning()
        .lexical_details(&lexical.entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        details.entry.status,
        Some(LearningStatus::KnownNotRecognized)
    );
    // Reading is not evidence-owned: the self-report still lands there.
    let profile = services
        .lexical_learning()
        .lexical_capability_profile(&lexical.entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Reading),
        CapabilityAssessment::Acquired
    );
}

#[test]
fn rejecting_upgrade_suggestion_sets_cooldown_without_status_change() {
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
    let lexical = upsert_word_asset(
        &services,
        "en",
        "could",
        "could",
        Some(LearningStatus::KnownNotRecognized),
        None,
    );
    for index in 0..5 {
        repo.upsert_recognition_evidence(&RecognitionEvidence {
            id: RecognitionEvidenceId::parse(format!("reject-evidence-{index}")).unwrap(),
            lexical_entry_id: lexical.entry.id.clone(),
            context_key: format!("sentence:reject-{index}"),
            sentence_id: Some(SubtitleSentenceId::parse(format!("reject-{index}")).unwrap()),
            media_id: None,
            source_kind: RecognitionEvidenceSourceKind::Review,
            source_id: format!("attempt-{index}"),
            occurred_at_ms: index,
        })
        .unwrap();
    }
    let final_review = services
        .practice_learning()
        .create_review_item(application::CreateReviewItem {
            source: ReviewSource {
                kind: ReviewSourceKind::Sentence,
                id: Some("reject-4".into()),
                practice_attempt_id: None,
                lexical_entry_id: Some(lexical.entry.id.clone()),
                media_id: None,
                track_id: None,
            },
            anchors: vec![PracticeAnchor {
                kind: PracticeAnchorKind::LexicalEntry,
                id: lexical.entry.id.as_str().into(),
                label: Some("could".into()),
                lexical_entry_id: Some(lexical.entry.id.clone()),
                sentence_id: Some(SubtitleSentenceId::parse("reject-4").unwrap()),
                token_start: None,
                token_end: None,
                start_ms: None,
                end_ms: None,
            }],
            prompt_snapshot: "reject context".into(),
        })
        .unwrap();
    let suggestion = services
        .practice_learning()
        .submit_review_attempt(application::SubmitReviewAttempt {
            item_id: final_review.id,
            rating: ReviewRating::Good,
        })
        .unwrap()
        .upgrade_suggestions
        .remove(0);
    let rejected = services
        .lexical_learning()
        .reject_upgrade_suggestion(&suggestion.id)
        .unwrap();
    assert_eq!(rejected.status, UpgradeSuggestionStatus::Rejected);
    assert!(rejected.cooldown_until_ms > rejected.resolved_at_ms);
    assert_eq!(
        services
            .lexical_learning()
            .lexical_details(&lexical.entry.id)
            .unwrap()
            .unwrap()
            .entry
            .status,
        Some(LearningStatus::KnownNotRecognized)
    );
    let next_review = services
        .practice_learning()
        .create_review_item(application::CreateReviewItem {
            source: ReviewSource {
                kind: ReviewSourceKind::Sentence,
                id: Some("reject-next".into()),
                practice_attempt_id: None,
                lexical_entry_id: Some(lexical.entry.id.clone()),
                media_id: None,
                track_id: None,
            },
            anchors: vec![PracticeAnchor {
                kind: PracticeAnchorKind::LexicalEntry,
                id: lexical.entry.id.as_str().into(),
                label: Some("could".into()),
                lexical_entry_id: Some(lexical.entry.id.clone()),
                sentence_id: Some(SubtitleSentenceId::parse("reject-next").unwrap()),
                token_start: None,
                token_end: None,
                start_ms: None,
                end_ms: None,
            }],
            prompt_snapshot: "new context during cooldown".into(),
        })
        .unwrap();
    let during_cooldown = services
        .practice_learning()
        .submit_review_attempt(application::SubmitReviewAttempt {
            item_id: next_review.id,
            rating: ReviewRating::Good,
        })
        .unwrap();
    assert!(during_cooldown.upgrade_suggestions.is_empty());
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
        chunk_id: None,
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
    assert!(
        !events
            .iter()
            .any(|event| event.kind == LearningEventKind::FamiliarMaterialMarked)
    );
}
