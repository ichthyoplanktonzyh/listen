use application::CreateWordTimeline;

use super::*;

fn l1_services(repo: &Arc<SqliteRepository>) -> AppServices {
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
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_corpus_index_repository(repo.clone())
    .with_learner_profile_repository(repo.clone())
}

fn import_english_sentence(services: &AppServices) -> SubtitleTrack {
    let media = services.media_analysis().register_media(RegisterMedia {
            path: "/tmp/l1-diagnosis.mp4".into(),
            fingerprint: "l1-diagnosis-media".into(),
            title: "L1 diagnosis media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    services.media_analysis().import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "l1.srt".into(),
            content: b"1\n00:00:00,000 --> 00:00:03,000\nI want to check the results now.\n"
                .to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap()
}

fn mark_all_words_known(services: &AppServices, track: &SubtitleTrack) {
    for token in &track.sentences[0].tokens {
        if token.kind != SubtitleTokenKind::Word {
            continue;
        }
        let lemma = token.normalized.clone().unwrap();
        upsert_word_asset(
            services,
            "en",
            &lemma,
            &lemma,
            Some(LearningStatus::KnownRecognized),
            None,
        );
    }
}

fn active_word_timeline(services: &AppServices, track: &SubtitleTrack) {
    let sentence = &track.sentences[0];
    let word_tokens = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    let step = 3000 / word_tokens.len() as u64;
    let words = word_tokens
        .iter()
        .enumerate()
        .map(|(index, token)| WordTiming {
            sentence_id: sentence.id.clone(),
            token_index: token.index,
            text: token.text.clone(),
            start_ms: index as u64 * step,
            end_ms: (index as u64 + 1) * step,
            confidence: Some(0.9),
            timing_source: TimingSource::ForcedAligned,
            provider_id: "test".into(),
            provider_version: "v1".into(),
        })
        .collect::<Vec<_>>();
    services.media_analysis().create_word_timeline(
            &track.id,
            CreateWordTimeline {
                algorithm_id: Some("test".into()),
                algorithm_version: Some("v1".into()),
                config_hash: None,
                parent_timeline_id: None,
                created_by: Some(TimelineCreator::User),
                status: Some(TimelineStatus::Active),
                metrics_json: None,
                words,
            },
        )
        .unwrap();
}

#[test]
fn l1_diagnosis_degrades_cleanly_without_l1_or_profile_or_frame() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = l1_services(&repo);
    let track = import_english_sentence(&services);
    let sentence_id = track.sentences[0].id.clone();

    // No L1 declared: baseline diagnosis is untouched.
    let baseline = services.media_analysis().diagnose_sentence(&sentence_id).unwrap();
    assert!(baseline.l1_context.is_none());
    assert!(baseline.l1_hints.is_empty());

    // Unsupported (L1, L2) pair: context only, no generic content.
    services
        .learner_profile()
        .set_learner_l1(Some("ja"), Some("zh"))
        .unwrap();
    let unsupported = services.media_analysis().diagnose_sentence(&sentence_id).unwrap();
    let context = unsupported.l1_context.expect("context for declared L1");
    assert_eq!(context.support, L1DiagnosisSupport::UnsupportedPair);
    assert!(unsupported.l1_hints.is_empty());
    // The baseline hint list is unchanged by the L1 layer.
    assert_eq!(unsupported.hints, baseline.hints);

    // Supported pair but no rhythm frame (no word timeline yet): no hints.
    services
        .learner_profile()
        .set_learner_l1(Some("zh"), Some("zh"))
        .unwrap();
    mark_all_words_known(&services, &track);
    let no_frame = services.media_analysis().diagnose_sentence(&sentence_id).unwrap();
    assert_eq!(
        no_frame.l1_context.unwrap().support,
        L1DiagnosisSupport::Supported
    );
    assert!(no_frame.l1_hints.is_empty());
}

#[test]
fn l1_hits_attach_replayable_spans_and_record_idempotent_events() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = l1_services(&repo);
    let track = import_english_sentence(&services);
    let sentence_id = track.sentences[0].id.clone();
    services
        .learner_profile()
        .set_learner_l1(Some("zh"), Some("zh"))
        .unwrap();
    // All words known+recognized so the base diagnosis lands on the
    // sound-side OtherFactors hint that gates the L1 layer.
    mark_all_words_known(&services, &track);
    active_word_timeline(&services, &track);

    let diagnosis = services.media_analysis().diagnose_sentence(&sentence_id).unwrap();
    assert_eq!(
        diagnosis.l1_context.as_ref().unwrap().support,
        L1DiagnosisSupport::Supported
    );
    assert!(
        !diagnosis.l1_hints.is_empty(),
        "the sentence carries weak forms / a want-to contraction, so at least \
         one difficulty category must fire"
    );
    for hint in &diagnosis.l1_hints {
        assert!(
            !hint.spans.is_empty(),
            "{} without spans",
            hint.difficulty_kind
        );
        for span in &hint.spans {
            assert!(span.end_ms > span.start_ms);
        }
    }

    // Hits are durable, subject-scoped, and idempotent per (sentence, kind).
    let events = repo.list_learning_events(100, 0).unwrap();
    let hit_events = events
        .iter()
        .filter(|event| event.kind == LearningEventKind::L1DifficultyHit)
        .collect::<Vec<_>>();
    assert_eq!(hit_events.len(), diagnosis.l1_hints.len());
    assert!(
        hit_events
            .iter()
            .all(|event| event.subject.id == sentence_id.as_str())
    );

    services.media_analysis().diagnose_sentence(&sentence_id).unwrap();
    let events_after = repo.list_learning_events(100, 0).unwrap();
    assert_eq!(
        events_after
            .iter()
            .filter(|event| event.kind == LearningEventKind::L1DifficultyHit)
            .count(),
        hit_events.len(),
        "re-diagnosing must not duplicate hit events"
    );
}

#[test]
fn family_projection_feeds_specialty_aggregation() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = l1_services(&repo);
    let track = import_english_sentence(&services);
    services
        .learner_profile()
        .set_learner_l1(Some("zh"), Some("zh"))
        .unwrap();
    mark_all_words_known(&services, &track);
    // Creating an active word timeline reindexes the track, which writes the
    // family annotation rows alongside words/phrases/chunks.
    active_word_timeline(&services, &track);

    let diagnosis = services.media_analysis().diagnose_sentence(&track.sentences[0].id).unwrap();
    let kind = &diagnosis.l1_hints[0].difficulty_kind;

    let specialty = services.media_analysis().l1_specialty_occurrences(kind, "en", None, 30)
        .unwrap();
    assert!(specialty.indexed, "projection rows must serve the query");
    assert!(!specialty.occurrences.is_empty());
    for occurrence in &specialty.occurrences {
        assert_eq!(occurrence.kind, CorpusOccurrenceKind::ConnectedSpeech);
        assert!(occurrence.end_ms > occurrence.start_ms);
        assert!(
            specialty
                .families
                .contains(occurrence.normalized_key.as_ref().unwrap())
        );
        assert_eq!(
            occurrence.sentence_id.as_ref(),
            Some(&track.sentences[0].id)
        );
    }

    // Unknown category and unsupported pair degrade to typed errors.
    assert!(
        services.media_analysis().l1_specialty_occurrences("not_a_kind", "en", None, 30)
            .is_err()
    );
    assert!(
        services.media_analysis().l1_specialty_occurrences(kind, "ja", None, 30)
            .is_err()
    );
}

#[test]
fn specialty_degrades_to_current_track_without_corpus_projection() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    // No corpus index repository configured: the projection is absent, so
    // the specialty query must fall back to current-track aggregation.
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
    .with_learner_profile_repository(repo.clone());
    let track = import_english_sentence(&services);
    services
        .learner_profile()
        .set_learner_l1(Some("zh"), Some("zh"))
        .unwrap();
    mark_all_words_known(&services, &track);
    active_word_timeline(&services, &track);

    let diagnosis = services.media_analysis().diagnose_sentence(&track.sentences[0].id).unwrap();
    let kind = &diagnosis.l1_hints[0].difficulty_kind;

    let no_track = services.media_analysis().l1_specialty_occurrences(kind, "en", None, 30)
        .unwrap();
    assert!(!no_track.indexed);
    assert!(no_track.occurrences.is_empty());

    let degraded = services.media_analysis().l1_specialty_occurrences(kind, "en", Some(track.id.as_str()), 30)
        .unwrap();
    assert!(!degraded.indexed);
    assert!(!degraded.occurrences.is_empty());
    assert!(
        degraded
            .occurrences
            .iter()
            .all(|occurrence| occurrence.track_id.as_ref() == Some(&track.id))
    );
}
