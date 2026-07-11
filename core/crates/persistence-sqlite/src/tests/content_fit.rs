use super::*;

const WORDS: [&str; 20] = [
    "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet",
    "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo", "sierra", "tango",
];

fn fit_services(repo: &Arc<SqliteRepository>) -> AppServices {
    AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_difficulty_repository(repo.clone())
}

fn fit_track(language: Option<&str>) -> SubtitleTrack {
    let sentence_id = SubtitleSentenceId::parse("fit-sentence-1").unwrap();
    let tokens = WORDS
        .iter()
        .enumerate()
        .map(|(i, word)| SubtitleToken {
            index: i as u32,
            kind: SubtitleTokenKind::Word,
            text: (*word).to_owned(),
            normalized: None,
            start_char: (i * 8) as u32,
            end_char: (i * 8 + word.len()) as u32,
        })
        .collect();
    SubtitleTrack {
        id: SubtitleTrackId::parse("fit-track-1").unwrap(),
        media_id: MediaId::parse("media-1").unwrap(),
        fingerprint: "fit-track-fp".into(),
        language: language.map(|value| LanguageCode::parse(value).unwrap()),
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: sentence_id,
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(6_000),
            original_text: WORDS.join(" "),
            display_text: WORDS.join(" "),
            tokens,
        }],
    }
}

fn seed_vocabulary(services: &AppServices) {
    // 17 known-recognized, 1 known-not-recognized, 1 unknown-meaning,
    // 1 (tango) never assessed.
    for word in &WORDS[..17] {
        services
            .create_lexical_entry(UpsertLexicalEntry {
                language: "en".into(),
                kind: LexicalEntryKind::Word,
                canonical_form: (*word).to_owned(),
                display_form: (*word).to_owned(),
                status: Some(LearningStatus::KnownRecognized),
                user_definition: None,
                personal_note: None,
                source: None,
            })
            .unwrap();
    }
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: "romeo".into(),
            display_form: "romeo".into(),
            status: Some(LearningStatus::KnownNotRecognized),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: "sierra".into(),
            display_form: "sierra".into(),
            status: Some(LearningStatus::UnknownMeaning),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
}

fn signal_value(dimension: &DifficultyDimension, kind: FitSignalKind) -> Option<f32> {
    dimension
        .signals
        .iter()
        .find(|signal| signal.kind == kind)
        .map(|signal| signal.value)
}

#[test]
fn content_fit_profile_computes_dual_dimensions_from_transcript_and_vocabulary() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = fit_services(&repo);
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();
    let track = fit_track(Some("en"));
    repo.save_track(&track).unwrap();
    seed_vocabulary(&services);

    let profile = services.compute_content_fit_for_track(&track.id).unwrap();

    assert_eq!(profile.subject_kind, "media");
    assert_eq!(profile.subject_id, track.media_id.as_str());
    assert_eq!(profile.algorithm_version, CONTENT_FIT_ALGORITHM_VERSION);
    assert_eq!(profile.evidence_grade, FitEvidenceGrade::InitialEstimate);

    // 1/20 unknown, 1/20 unassessed => coverage 0.90 => challenging.
    assert_eq!(profile.meaning.fit, InputFit::Challenging);
    let unknown = signal_value(&profile.meaning, FitSignalKind::UnknownMeaningDensity).unwrap();
    let unassessed = signal_value(&profile.meaning, FitSignalKind::UnassessedDensity).unwrap();
    assert!((unknown - 0.05).abs() < 1e-6);
    assert!((unassessed - 0.05).abs() < 1e-6);
    assert!((profile.assessed_token_ratio - 0.95).abs() < 1e-6);
    assert!(profile.has_sufficient_vocabulary_profile());

    // 1/20 known-not-recognized => 0.05 => challenging base band; no word
    // timeline was seeded, so no delivery signals exist to escalate it.
    assert_eq!(profile.sound.fit, InputFit::Challenging);
    let knr = signal_value(&profile.sound, FitSignalKind::KnownNotRecognizedDensity).unwrap();
    assert!((knr - 0.05).abs() < 1e-6);
    assert_eq!(profile.sound.signals.len(), 1);
}

#[test]
fn fast_delivery_escalates_sound_fit_via_active_word_timeline() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = fit_services(&repo);
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();
    let track = fit_track(Some("en"));
    repo.save_track(&track).unwrap();
    seed_vocabulary(&services);

    // 20 words over 6s of speech = 200 wpm > 180 wpm trigger.
    let sentence_id = track.sentences[0].id.clone();
    let words = (0..20u32)
        .map(|i| WordTiming {
            sentence_id: sentence_id.clone(),
            token_index: i,
            text: WORDS[i as usize].into(),
            start_ms: u64::from(i) * 300,
            end_ms: (u64::from(i) + 1) * 300,
            confidence: Some(0.9),
            timing_source: TimingSource::ForcedAligned,
            provider_id: "test".into(),
            provider_version: "v1".into(),
        })
        .collect();
    repo.save_word_timeline(&WordTimeline {
        id: WordTimelineId::parse("fit-wt-1").unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        algorithm_id: "test".into(),
        algorithm_version: "v1".into(),
        config_hash: "test-config".into(),
        parent_timeline_id: None,
        created_by: TimelineCreator::Algorithm,
        status: TimelineStatus::Active,
        metrics_json: serde_json::json!({}).into(),
        words,
        created_at_ms: 1,
        updated_at_ms: 1,
    })
    .unwrap();

    let profile = services.compute_content_fit_for_track(&track.id).unwrap();

    // challenging base (knr 0.05) + fast-speech escalation saturates the
    // remaining headroom regardless of what the derived rhythm frames add.
    assert_eq!(profile.sound.fit, InputFit::TooHard);
    let wpm = signal_value(&profile.sound, FitSignalKind::SpeechRateWpm).unwrap();
    assert!((wpm - 200.0).abs() < 0.5, "expected ~200 wpm, got {wpm}");
    assert!(
        profile
            .sound
            .signals
            .iter()
            .any(|signal| signal.kind == FitSignalKind::SpeechRateWpm && signal.decisive)
    );
    // Rhythm frames derive from the active word timeline, so weak-form and
    // compression densities are present (values are the rhythm algorithm's
    // business, not this test's).
    assert!(signal_value(&profile.sound, FitSignalKind::WeakFormDensity).is_some());
    assert!(signal_value(&profile.sound, FitSignalKind::CompressionDensity).is_some());
}

#[test]
fn content_fit_fingerprint_is_stable_until_vocabulary_changes() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = fit_services(&repo);
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();
    let track = fit_track(Some("en"));
    repo.save_track(&track).unwrap();
    seed_vocabulary(&services);

    let first = services.compute_content_fit_for_track(&track.id).unwrap();
    let second = services.compute_content_fit_for_track(&track.id).unwrap();
    assert_eq!(first.input_fingerprint, second.input_fingerprint);
    assert_eq!(first.meaning, second.meaning);
    assert_eq!(first.sound, second.sound);

    // Assessing the previously unassessed word moves the vocabulary
    // watermark, so the fingerprint must change and unassessed density drop.
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: "tango".into(),
            display_form: "tango".into(),
            status: Some(LearningStatus::KnownRecognized),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
    let third = services.compute_content_fit_for_track(&track.id).unwrap();
    assert_ne!(first.input_fingerprint, third.input_fingerprint);
    assert!((third.assessed_token_ratio - 1.0).abs() < 1e-6);
    assert_eq!(third.meaning.fit, InputFit::Comprehensible);
}

#[test]
fn cached_content_fit_reuses_profile_until_inputs_change() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = fit_services(&repo);
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();
    let track = fit_track(Some("en"));
    repo.save_track(&track).unwrap();
    seed_vocabulary(&services);

    let first = services.content_fit_for_track(&track.id).unwrap();
    let stored = application::DifficultyRepository::get_difficulty_profile(
        repo.as_ref(),
        "media",
        track.media_id.as_str(),
    )
    .unwrap()
    .expect("profile persisted on first read");
    assert_eq!(stored, first);

    // Tamper the cached row: if the second read really hits the cache, the
    // tampered value comes back; a silent recompute would erase it.
    let mut tampered = stored.clone();
    tampered.assessed_token_ratio = 0.123;
    application::DifficultyRepository::save_difficulty_profile(repo.as_ref(), &tampered).unwrap();
    let second = services.content_fit_for_track(&track.id).unwrap();
    assert!((second.assessed_token_ratio - 0.123).abs() < 1e-6);

    // A vocabulary change moves the watermark: the tampered cache is stale
    // and must be recomputed and re-persisted.
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: "tango".into(),
            display_form: "tango".into(),
            status: Some(LearningStatus::KnownRecognized),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
    let third = services.content_fit_for_track(&track.id).unwrap();
    assert!((third.assessed_token_ratio - 1.0).abs() < 1e-6);
    assert_ne!(third.input_fingerprint, first.input_fingerprint);
    let restored = application::DifficultyRepository::get_difficulty_profile(
        repo.as_ref(),
        "media",
        track.media_id.as_str(),
    )
    .unwrap()
    .unwrap();
    assert_eq!(restored, third);
}

#[test]
fn content_fit_requires_language_and_word_tokens() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = fit_services(&repo);
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();

    let track = fit_track(None);
    repo.save_track(&track).unwrap();
    assert!(matches!(
        services.compute_content_fit_for_track(&track.id),
        Err(application::ApplicationError::Validation(
            "subtitle track language"
        ))
    ));

    let mut empty_track = fit_track(Some("en"));
    empty_track.id = SubtitleTrackId::parse("fit-track-empty").unwrap();
    empty_track.fingerprint = "fit-track-empty-fp".into();
    for sentence in &mut empty_track.sentences {
        sentence.id = SubtitleSentenceId::parse("fit-sentence-empty").unwrap();
        sentence
            .tokens
            .retain(|token| token.kind != SubtitleTokenKind::Word);
    }
    repo.save_track(&empty_track).unwrap();
    assert!(matches!(
        services.compute_content_fit_for_track(&empty_track.id),
        Err(application::ApplicationError::Validation(
            "track word tokens"
        ))
    ));
}

#[test]
fn comprehension_feedback_calibrates_sound_fit_and_survives_recompute() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = fit_services(&repo).with_learning_loop_repositories(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    );
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();
    let track = fit_track(Some("en"));
    repo.save_track(&track).unwrap();
    seed_vocabulary(&services);

    // Baseline: 0.05 knr => challenging, initial estimate.
    let baseline = services.content_fit_for_track(&track.id).unwrap();
    assert_eq!(baseline.sound.fit, InputFit::Challenging);
    assert_eq!(baseline.evidence_grade, FitEvidenceGrade::InitialEstimate);

    // Two extensive sessions self-reported "unclear" on this media.
    for _ in 0..2 {
        let session = services
            .create_practice_session(application::CreatePracticeSession {
                mode: PracticeMode::Extensive,
                media_id: Some(track.media_id.clone()),
                track_id: Some(track.id.clone()),
                source: Some("test".into()),
            })
            .unwrap();
        services
            .complete_listening_session(
                &session.id,
                application::CompleteListeningSessionInput {
                    comprehension_report: Some(ListeningComprehensionReport::Unclear),
                    hunting_summary: None,
                },
            )
            .unwrap();
    }

    // The calibration record is durable evidence, not a cache row.
    let calibration = application::DifficultyRepository::get_fit_calibration(
        repo.as_ref(),
        "media",
        track.media_id.as_str(),
    )
    .unwrap()
    .expect("feedback recorded a calibration");
    assert_eq!(calibration.reports_unclear, 2);

    // The calibration watermark invalidates the cached profile: the next
    // read re-bands one step harder and reports usage_calibrated, with the
    // calibration signal attached and material signals untouched.
    let calibrated = services.content_fit_for_track(&track.id).unwrap();
    assert_ne!(calibrated.input_fingerprint, baseline.input_fingerprint);
    assert_eq!(calibrated.sound.fit, InputFit::TooHard);
    assert_eq!(calibrated.evidence_grade, FitEvidenceGrade::UsageCalibrated);
    let signal = calibrated
        .sound
        .signals
        .iter()
        .find(|signal| signal.kind == FitSignalKind::ComprehensionReportUnclearRatio)
        .expect("calibration signal present");
    assert!(signal.decisive);
    assert!((signal.value - 1.0).abs() < 1e-6);
    assert_eq!(
        signal_value(&calibrated.sound, FitSignalKind::KnownNotRecognizedDensity),
        signal_value(&baseline.sound, FitSignalKind::KnownNotRecognizedDensity),
    );

    // Vocabulary changes force a full recompute; the calibration survives it
    // because it lives outside the profile cache.
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: "tango".into(),
            display_form: "tango".into(),
            status: Some(LearningStatus::KnownRecognized),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
    let recomputed = services.content_fit_for_track(&track.id).unwrap();
    assert_ne!(recomputed.input_fingerprint, calibrated.input_fingerprint);
    assert_eq!(recomputed.evidence_grade, FitEvidenceGrade::UsageCalibrated);
    assert_eq!(recomputed.sound.fit, InputFit::TooHard);
}

#[test]
fn sessions_without_media_or_feedback_leave_no_calibration() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = fit_services(&repo).with_learning_loop_repositories(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    );
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();

    // No media on the session: nothing to calibrate.
    let session = services
        .create_practice_session(application::CreatePracticeSession {
            mode: PracticeMode::Extensive,
            media_id: None,
            track_id: None,
            source: Some("test".into()),
        })
        .unwrap();
    services
        .complete_listening_session(
            &session.id,
            application::CompleteListeningSessionInput {
                comprehension_report: Some(ListeningComprehensionReport::Unclear),
                hunting_summary: None,
            },
        )
        .unwrap();

    // Media session without report or scored attempts: also nothing.
    let media_id = MediaId::parse("media-1").unwrap();
    let session = services
        .create_practice_session(application::CreatePracticeSession {
            mode: PracticeMode::Extensive,
            media_id: Some(media_id.clone()),
            track_id: None,
            source: Some("test".into()),
        })
        .unwrap();
    services
        .complete_listening_session(
            &session.id,
            application::CompleteListeningSessionInput {
                comprehension_report: None,
                hunting_summary: None,
            },
        )
        .unwrap();
    assert!(
        application::DifficultyRepository::get_fit_calibration(
            repo.as_ref(),
            "media",
            media_id.as_str(),
        )
        .unwrap()
        .is_none()
    );
}

#[test]
fn practice_accuracy_feedback_calibrates_sound_fit() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = fit_services(&repo).with_learning_loop_repositories(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    );
    MediaRepository::upsert(repo.as_ref(), &transcription_media()).unwrap();
    let track = fit_track(Some("en"));
    repo.save_track(&track).unwrap();
    seed_vocabulary(&services);

    let session = services
        .create_practice_session(application::CreatePracticeSession {
            mode: PracticeMode::Intensive,
            media_id: Some(track.media_id.clone()),
            track_id: Some(track.id.clone()),
            source: Some("test".into()),
        })
        .unwrap();
    let sentence_id = track.sentences[0].id.clone();
    // Six dictation attempts, one correct: 1/6 <= 0.5 shifts one band
    // harder once enough attempts exist.
    for index in 0..6 {
        let item = services
            .create_practice_item(application::CreatePracticeItem {
                session_id: Some(session.id.clone()),
                kind: PracticeKind::Dictation,
                target: PracticeTarget {
                    kind: PracticeTargetKind::Sentence,
                    id: Some(sentence_id.as_str().into()),
                    sentence_id: Some(sentence_id.clone()),
                    chunk_id: None,
                    start_ms: Some(0),
                    end_ms: Some(6_000),
                },
                prompt_snapshot: format!("prompt {index}"),
                expected_text: "alpha bravo".into(),
                anchors: Vec::new(),
            })
            .unwrap();
        services
            .submit_practice_attempt(application::SubmitPracticeAttempt {
                item_id: item.id,
                text_answer: if index == 0 {
                    "alpha bravo".into()
                } else {
                    "zulu yankee".into()
                },
                create_review_item_on_failure: false,
            })
            .unwrap();
    }
    // Intensive sessions are never "completed" after 3.5.6, so accuracy must
    // already be folded in at attempt-submission time.

    let calibration = application::DifficultyRepository::get_fit_calibration(
        repo.as_ref(),
        "media",
        track.media_id.as_str(),
    )
    .unwrap()
    .expect("practice feedback recorded");
    assert_eq!(calibration.practice_attempts, 6);
    assert_eq!(calibration.practice_correct, 1);

    let profile = services.content_fit_for_track(&track.id).unwrap();
    assert_eq!(profile.evidence_grade, FitEvidenceGrade::UsageCalibrated);
    assert_eq!(profile.sound.fit, InputFit::TooHard);
    assert!(
        profile
            .sound
            .signals
            .iter()
            .any(|signal| signal.kind == FitSignalKind::PracticeCorrectRate && signal.decisive)
    );
}
