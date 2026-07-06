use super::*;

#[test]
fn capability_projection_and_override_round_trip_without_losing_evidence_state() {
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
    );
    let entry = upsert_word_asset(&services, "en", "signal", "signal", None, None).entry;

    let initial = repo
        .lexical_capability_profile(&entry.id, None)
        .unwrap()
        .unwrap();
    assert_eq!(
        initial.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::Unassessed
    );

    repo.set_lexical_capability_projection(
        &entry.id,
        None,
        LexicalCapability::Reading,
        Some(CapabilityProjection {
            conclusion: CapabilityConclusion::Acquired,
            source: CapabilityProjectionSource::EvidenceProjection,
            algorithm_version: "test-projection-v1".into(),
            updated_at_ms: 10,
        }),
        10,
    )
    .unwrap();
    repo.set_lexical_capability_projection(
        &entry.id,
        None,
        LexicalCapability::Listening,
        Some(CapabilityProjection {
            conclusion: CapabilityConclusion::NotAcquired,
            source: CapabilityProjectionSource::EvidenceProjection,
            algorithm_version: "test-projection-v1".into(),
            updated_at_ms: 11,
        }),
        11,
    )
    .unwrap();
    let overridden = repo
        .set_lexical_capability_override(
            &entry.id,
            None,
            LexicalCapability::Listening,
            Some(CapabilityOverride {
                conclusion: CapabilityConclusion::Acquired,
                source: CapabilityOverrideSource::UserSelection,
                updated_at_ms: 20,
            }),
            20,
        )
        .unwrap();
    assert_eq!(
        overridden.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::Acquired
    );
    assert_eq!(
        overridden.listening.projection.unwrap().conclusion,
        CapabilityConclusion::NotAcquired
    );

    let cleared = repo
        .set_lexical_capability_override(&entry.id, None, LexicalCapability::Listening, None, 30)
        .unwrap();
    assert_eq!(
        cleared.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::NotAcquired
    );
    assert_eq!(
        cleared.legacy_status_view(),
        Some(LearningStatus::KnownNotRecognized)
    );

    let history = repo.lexical_capability_history(&entry.id, None).unwrap();
    assert_eq!(history.len(), 4);
    assert_eq!(
        history[0].change_kind,
        CapabilityStateChangeKind::OverrideCleared
    );
    assert_eq!(
        history[1].change_kind,
        CapabilityStateChangeKind::OverrideSet
    );
}

#[test]
fn services_are_idempotent_and_persist_state() {
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
    );
    let input = RegisterMedia {
        path: "/tmp/a.mp4".into(),
        fingerprint: "same-content".into(),
        title: "A".into(),
        kind: MediaKind::Video,
        duration_ms: Some(10_000),
    };
    let first = services.register_media(input.clone()).unwrap();
    let second = services.register_media(input).unwrap();
    assert_eq!(first.id, second.id);
    services.update_progress(&first.id, 1250).unwrap();
    assert_eq!(
        services.read_progress(&first.id).unwrap(),
        Some(TimeMs::new(1250))
    );

    let word = upsert_word_asset(
        &services,
        "en",
        "Hello",
        "Hello",
        Some(LearningStatus::KnownRecognized),
        None,
    );
    assert_eq!(read_word_asset(&services, "EN", "hello"), Some(word.entry));

    let subtitle = ImportSubtitle {
        media_id: first.id,
        source_name: "timeline.srt".into(),
        content: include_bytes!("../../../../testdata/subtitles/timeline.srt").to_vec(),
        language: Some("en".into()),
        identity_salt: None,
    };
    let first_track = services.import_subtitle(subtitle.clone()).unwrap();
    let second_track = services.import_subtitle(subtitle).unwrap();
    assert_eq!(first_track.id, second_track.id);
    assert_eq!(
        services.read_subtitle_track(&first_track.id).unwrap(),
        Some(first_track)
    );
}

#[test]
fn lexical_words_and_phrases_keep_independent_state_and_sources() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo,
    );
    let phrase = services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Phrase,
            canonical_form: "give up".into(),
            display_form: "give up".into(),
            status: Some(LearningStatus::KnownNotRecognized),
            user_definition: Some("stop trying".into()),
            personal_note: None,
            source: Some(application::LexicalSourceContext {
                media_id: None,
                sentence_id: None,
                original_form: "give up".into(),
                sentence_text: "Never give up.".into(),
                media_title: "Lesson".into(),
                media_fingerprint: "lesson".into(),
                start_ms: 10,
                end_ms: 20,
                token_start: Some(1),
                token_end: Some(2),
            }),
        })
        .unwrap();
    let word = services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: "give".into(),
            display_form: "give".into(),
            status: Some(LearningStatus::KnownRecognized),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
    assert_ne!(phrase.entry.id, word.entry.id);
    assert_eq!(phrase.occurrences.len(), 1);
    assert_eq!(
        phrase.entry.status,
        Some(LearningStatus::KnownNotRecognized)
    );
    assert_eq!(word.entry.status, Some(LearningStatus::KnownRecognized));
    upsert_word_asset(
        &services,
        "en",
        "give",
        "give",
        Some(LearningStatus::UnknownMeaning),
        None,
    );
    let words = services
        .list_lexical_entries("en", Some(LexicalEntryKind::Word), None, "give", 10, 0)
        .unwrap();
    assert_eq!(words.len(), 1);
    assert_eq!(words[0].entry.status, Some(LearningStatus::UnknownMeaning));
    assert_eq!(
        services
            .normalize_lexical_form("en", "went")
            .unwrap()
            .normalized,
        "go"
    );
    services.correct_lemma("en", "went", "walk").unwrap();
    assert_eq!(
        services
            .normalize_lexical_form("en", "went")
            .unwrap()
            .normalized,
        "walk"
    );
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: "run".into(),
            display_form: "run".into(),
            status: Some(LearningStatus::KnownRecognized),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: "jog".into(),
            display_form: "jog".into(),
            status: Some(LearningStatus::UnknownMeaning),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
    assert!(matches!(
        services.correct_lemma("en", "run", "jog"),
        Err(application::ApplicationError::Conflict(_))
    ));
}

#[test]
fn lexical_asset_import_merges_newest_fields_and_remaps_sources() {
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
    );
    let local = services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Phrase,
            canonical_form: "give up".into(),
            display_form: "give up".into(),
            status: Some(LearningStatus::KnownRecognized),
            user_definition: Some("local definition".into()),
            personal_note: Some("local note".into()),
            source: Some(application::LexicalSourceContext {
                media_id: None,
                sentence_id: None,
                original_form: "give up".into(),
                sentence_text: "Never give up.".into(),
                media_title: "Local lesson".into(),
                media_fingerprint: "lesson".into(),
                start_ms: 10,
                end_ms: 20,
                token_start: Some(1),
                token_end: Some(2),
            }),
        })
        .unwrap();
    let imported_id = LexicalEntryId::from_fingerprint("import", "give up");
    let mut imported_entry = local.entry.clone();
    imported_entry.id = imported_id.clone();
    imported_entry.status = Some(LearningStatus::UnknownMeaning);
    imported_entry.updated_at_ms = local.entry.updated_at_ms;
    imported_entry.user_definition = Some("newer imported definition".into());
    imported_entry.personal_note = Some("newer imported note".into());
    imported_entry.learning_updated_at_ms = local.entry.learning_updated_at_ms + 100;
    let mut imported_occurrence = local.occurrences[0].clone();
    imported_occurrence.lexical_entry_id = imported_id.clone();
    imported_occurrence.first_seen_at_ms = imported_occurrence.first_seen_at_ms.saturating_sub(5);
    imported_occurrence.last_seen_at_ms += 100;
    imported_occurrence.encounter_count = 9;
    let imported_history = LexicalStatusHistory {
        id: LexicalStatusHistoryId::from_fingerprint("import-history", "give up"),
        lexical_entry_id: imported_id,
        previous_status: None,
        new_status: Some(LearningStatus::UnknownMeaning),
        changed_at_ms: local.entry.updated_at_ms.saturating_sub(1),
        change_source: LearningChangeSource::Import,
    };

    repo.import_lexical_assets(
        std::slice::from_ref(&imported_entry),
        std::slice::from_ref(&imported_history),
        std::slice::from_ref(&imported_occurrence),
        &[],
    )
    .unwrap();
    repo.import_lexical_assets(
        std::slice::from_ref(&imported_entry),
        std::slice::from_ref(&imported_history),
        std::slice::from_ref(&imported_occurrence),
        &[],
    )
    .unwrap();
    let merged = services.lexical_details(&local.entry.id).unwrap().unwrap();
    assert_eq!(merged.entry.status, Some(LearningStatus::KnownRecognized));
    assert_eq!(
        merged.entry.user_definition.as_deref(),
        Some("newer imported definition")
    );
    assert_eq!(merged.occurrences.len(), 1);
    assert_eq!(merged.occurrences[0].encounter_count, 9);
    assert_eq!(
        merged
            .history
            .iter()
            .filter(|value| value.change_source == LearningChangeSource::Import)
            .count(),
        1
    );
    assert_eq!(
        merged
            .history
            .iter()
            .find(|value| value.change_source == LearningChangeSource::Import)
            .map(|value| &value.lexical_entry_id),
        Some(&local.entry.id)
    );
}

#[test]
fn create_lexical_entry_with_status_syncs_capability_profile() {
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
    );
    let entry = upsert_word_asset(
        &services,
        "en",
        "signal",
        "signal",
        Some(LearningStatus::KnownNotRecognized),
        None,
    )
    .entry;

    let profile = services
        .lexical_capability_profile(&entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Reading),
        CapabilityAssessment::Acquired
    );
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::NotAcquired
    );
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Speaking),
        CapabilityAssessment::Unassessed
    );
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Writing),
        CapabilityAssessment::Unassessed
    );
}

#[test]
fn user_override_syncs_legacy_status_and_does_not_erase_projection() {
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
    );
    let entry = upsert_word_asset(
        &services,
        "en",
        "focus",
        "focus",
        Some(LearningStatus::KnownNotRecognized),
        None,
    )
    .entry;

    let profile = services
        .set_lexical_capability_override(
            &entry.id,
            LexicalCapability::Listening,
            Some(CapabilityConclusion::Acquired),
        )
        .unwrap();
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::Acquired
    );
    assert_eq!(
        profile.listening.projection.as_ref().unwrap().conclusion,
        CapabilityConclusion::NotAcquired
    );
    let details = services.lexical_details(&entry.id).unwrap().unwrap();
    assert_eq!(
        details.entry.status,
        Some(LearningStatus::KnownRecognized)
    );

    let cleared = services
        .set_lexical_capability_override(&entry.id, LexicalCapability::Listening, None)
        .unwrap();
    assert_eq!(
        cleared.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::NotAcquired
    );
    let details = services.lexical_details(&entry.id).unwrap().unwrap();
    assert_eq!(
        details.entry.status,
        Some(LearningStatus::KnownNotRecognized)
    );
}

#[test]
fn export_includes_capability_profiles_and_v6_import_merges_without_overwriting_newer_override() {
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
    );
    let entry = upsert_word_asset(
        &services,
        "en",
        "merge",
        "merge",
        Some(LearningStatus::KnownNotRecognized),
        None,
    )
    .entry;
    services
        .set_lexical_capability_override(
            &entry.id,
            LexicalCapability::Listening,
            Some(CapabilityConclusion::Acquired),
        )
        .unwrap();

    let bundle = services.export_vocabulary().unwrap();
    assert_eq!(bundle.version, 6);
    assert!(!bundle.capability_profiles.is_empty());
    let exported_profile = bundle
        .capability_profiles
        .iter()
        .find(|p| p.lexical_entry_id == entry.id)
        .unwrap();
    assert!(exported_profile.listening.user_override.is_some());

    let target_repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let target_services = AppServices::new(
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
    );
    target_services.import_vocabulary(&bundle).unwrap();
    let restored = target_services
        .lexical_capability_profile(&entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        restored.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::Acquired
    );
    assert!(restored.listening.user_override.is_some());
    assert!(restored.listening.projection.is_some());
}

#[test]
fn v5_bundle_import_generates_capability_profiles_from_legacy_mapping() {
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
    );
    let entry = upsert_word_asset(
        &services,
        "en",
        "legacy",
        "legacy",
        Some(LearningStatus::KnownRecognized),
        None,
    )
    .entry;
    let mut bundle = services.export_vocabulary().unwrap();
    bundle.version = 5;
    bundle.capability_profiles.clear();

    let target_repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let target_services = AppServices::new(
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
        target_repo.clone(),
    );
    target_services.import_vocabulary(&bundle).unwrap();
    let profile = target_services
        .lexical_capability_profile(&entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Reading),
        CapabilityAssessment::Acquired
    );
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::Acquired
    );
    assert_eq!(
        profile.reading.projection.as_ref().unwrap().source,
        CapabilityProjectionSource::LegacyLearningStatusMigration
    );
}

#[test]
fn imported_projection_cannot_overwrite_local_user_override() {
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
    );
    let entry = upsert_word_asset(
        &services,
        "en",
        "protect",
        "protect",
        Some(LearningStatus::KnownNotRecognized),
        None,
    )
    .entry;
    services
        .set_lexical_capability_override(
            &entry.id,
            LexicalCapability::Listening,
            Some(CapabilityConclusion::Acquired),
        )
        .unwrap();

    let mut bundle = services.export_vocabulary().unwrap();
    for profile in &mut bundle.capability_profiles {
        if profile.lexical_entry_id == entry.id {
            profile.listening.user_override = None;
            profile.listening.projection = Some(CapabilityProjection {
                conclusion: CapabilityConclusion::NotAcquired,
                source: CapabilityProjectionSource::LegacyLearningStatusMigration,
                algorithm_version: "attacker-v1".into(),
                updated_at_ms: u64::MAX,
            });
        }
    }
    services.import_vocabulary(&bundle).unwrap();
    let profile = services
        .lexical_capability_profile(&entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        profile.effective_assessment(LexicalCapability::Listening),
        CapabilityAssessment::Acquired,
        "user override must survive even when imported projection is newer"
    );
    assert!(profile.listening.user_override.is_some());
}
