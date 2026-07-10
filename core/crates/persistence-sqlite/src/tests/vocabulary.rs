use super::*;

/// Phase 2.6 bilingual regression capstone: the crown-jewel vocabulary asset
/// stays language-isolated. A Chinese word and an English word, with their own
/// source snapshots, never cross between the two languages' vocabularies.
#[test]
fn english_and_chinese_vocabulary_and_sources_stay_isolated() {
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
    let chinese = upsert_word_asset(
        &services,
        "zh",
        "咖啡",
        "咖啡",
        Some(LearningStatus::UnknownMeaning),
        Some(application::LexicalSourceContext {
            media_id: None,
            sentence_id: None,
            original_form: "咖啡".into(),
            sentence_text: "我想喝咖啡".into(),
            media_title: "ZH".into(),
            media_fingerprint: "zh-fp".into(),
            start_ms: 0,
            end_ms: 1000,
            token_start: None,
            token_end: None,
        }),
    );
    upsert_word_asset(
        &services,
        "en",
        "coffee",
        "coffee",
        Some(LearningStatus::KnownRecognized),
        Some(application::LexicalSourceContext {
            media_id: None,
            sentence_id: None,
            original_form: "coffee".into(),
            sentence_text: "I drink coffee".into(),
            media_title: "EN".into(),
            media_fingerprint: "en-fp".into(),
            start_ms: 0,
            end_ms: 1000,
            token_start: None,
            token_end: None,
        }),
    );

    // A word exists only under its own language; it never leaks across.
    assert!(read_word_asset(&services, "zh", "咖啡").is_some());
    assert!(read_word_asset(&services, "en", "咖啡").is_none());
    assert!(read_word_asset(&services, "en", "coffee").is_some());
    assert!(read_word_asset(&services, "zh", "coffee").is_none());

    // Vocabulary lists are isolated by language.
    let zh_vocab = services
        .list_vocabulary(
            "zh",
            None,
            Some(LearningStatus::UnknownMeaning),
            None,
            "",
            200,
            0,
        )
        .unwrap();
    assert!(zh_vocab.iter().any(|d| d.entry.normalized_form == "咖啡"));
    assert!(zh_vocab.iter().all(|d| d.entry.normalized_form != "coffee"));
    let en_vocab = services
        .list_vocabulary(
            "en",
            None,
            Some(LearningStatus::KnownRecognized),
            None,
            "",
            200,
            0,
        )
        .unwrap();
    assert!(en_vocab.iter().any(|d| d.entry.normalized_form == "coffee"));
    assert!(en_vocab.iter().all(|d| d.entry.normalized_form != "咖啡"));

    // The Chinese source snapshot is captured under the Chinese profile.
    let details = services
        .lexical_details(&chinese.entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(details.occurrences.len(), 1);
    assert_eq!(details.occurrences[0].sentence_text_snapshot, "我想喝咖啡");
}

#[test]
fn vocabulary_assets_capture_history_sources_and_restore_without_media() {
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
    let media = services
        .register_media(RegisterMedia {
            path: "/tmp/source.mp4".into(),
            fingerprint: "source-media".into(),
            title: "Source".into(),
            kind: MediaKind::Video,
            duration_ms: Some(5000),
        })
        .unwrap();
    let track = services
        .import_subtitle(ImportSubtitle {
            media_id: media.id.clone(),
            source_name: "timeline.srt".into(),
            content: include_bytes!("../../../../testdata/subtitles/timeline.srt").to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    let sentence = &track.sentences[0];
    let source = application::LexicalSourceContext {
        media_id: Some(media.id),
        sentence_id: Some(sentence.id.clone()),
        original_form: "Hello".into(),
        sentence_text: sentence.display_text.clone(),
        media_title: "Source".into(),
        media_fingerprint: "source-media".into(),
        start_ms: sentence.start.get(),
        end_ms: sentence.end.get(),
        token_start: Some(0),
        token_end: Some(0),
    };
    let entry = upsert_word_asset(
        &services,
        "en",
        "hello",
        "Hello",
        Some(LearningStatus::UnknownMeaning),
        Some(source.clone()),
    );
    upsert_word_asset(
        &services,
        "en",
        "hello",
        "Hello",
        Some(LearningStatus::KnownRecognized),
        Some(source),
    );
    let details = services.lexical_details(&entry.entry.id).unwrap().unwrap();
    assert_eq!(details.history.len(), 2);
    assert_eq!(details.occurrences[0].encounter_count, 2);

    let first_observation = services
        .create_lexical_observation(application::CreateLexicalObservation {
            lexical_entry_id: entry.entry.id.clone(),
            sentence_id: sentence.id.clone(),
            original_form: "Hello".into(),
            result: ObservationResult::RecognizedInContext,
            source: None,
        })
        .unwrap();
    let second_observation = services
        .create_lexical_observation(application::CreateLexicalObservation {
            lexical_entry_id: entry.entry.id.clone(),
            sentence_id: sentence.id.clone(),
            original_form: "Hello".into(),
            result: ObservationResult::NotRecognizedInContext,
            source: None,
        })
        .unwrap();
    // Observation identity is deterministic on (entry, sentence): a newer
    // observation replaces the result but keeps the same id, so durable
    // references (e.g. practice attempts) never dangle.
    assert_eq!(
        first_observation.id,
        domain::lexical_observation_id(&entry.entry.id, &sentence.id)
    );
    assert_eq!(first_observation.id, second_observation.id);
    let stored = repo
        .list_lexical_observations_by_sentence(&sentence.id)
        .unwrap();
    assert_eq!(stored.len(), 1);
    assert_eq!(stored[0].id, first_observation.id);
    assert_eq!(stored[0].result, ObservationResult::NotRecognizedInContext);
    // ADR 0017: the channelized stream keeps both markings even though the
    // legacy (entry, sentence) row was replaced.
    let channelized = repo
        .list_learning_observations(&entry.entry.id, None, 10, 0)
        .unwrap();
    assert_eq!(channelized.len(), 2);
    for observation in &channelized {
        assert_eq!(observation.task_type, ObservationTaskType::ContextMarking);
        assert_eq!(observation.capability, LexicalCapability::Listening);
        assert_eq!(observation.assistance, AssistanceLevel::FullText);
        assert_eq!(observation.origin, ObservationOrigin::UserMarking);
        assert_eq!(observation.surface_form.as_deref(), Some("Hello"));
    }
    services
        .clear_lexical_observation(&entry.entry.id, &sentence.id)
        .unwrap();
    assert!(
        repo.list_lexical_observations_by_sentence(&sentence.id)
            .unwrap()
            .is_empty()
    );

    services
        .set_media_availability(
            &details.occurrences[0].media_id.clone().unwrap(),
            MediaAvailability::Archived,
        )
        .unwrap();
    assert_eq!(
        services
            .lexical_details(&entry.entry.id)
            .unwrap()
            .unwrap()
            .occurrences[0]
            .media_id,
        None
    );
    services
        .register_media(RegisterMedia {
            path: "/tmp/moved-source.mp4".into(),
            fingerprint: "source-media".into(),
            title: "Source moved".into(),
            kind: MediaKind::Video,
            duration_ms: Some(5000),
        })
        .unwrap();
    let relinked = services.lexical_details(&entry.entry.id).unwrap().unwrap();
    assert!(relinked.occurrences[0].media_id.is_some());
    assert!(relinked.occurrences[0].sentence_id.is_some());
    services
        .create_lexical_observation(application::CreateLexicalObservation {
            lexical_entry_id: entry.entry.id.clone(),
            sentence_id: sentence.id.clone(),
            original_form: "Hello".into(),
            result: ObservationResult::RecognizedInContext,
            source: None,
        })
        .unwrap();

    let bundle = services.export_vocabulary().unwrap();
    assert_eq!(bundle.lexical_observations.len(), 1);
    assert_eq!(bundle.learning_observations.len(), 3);
    let restored = Arc::new(SqliteRepository::in_memory().unwrap());
    let restored_services = AppServices::new(
        restored.clone(),
        restored.clone(),
        restored.clone(),
        restored.clone(),
        restored.clone(),
        restored.clone(),
        restored.clone(),
        restored,
    );
    restored_services.import_vocabulary(&bundle).unwrap();
    let restored_details = restored_services
        .lexical_details(&entry.entry.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        restored_details.entry.status,
        Some(LearningStatus::KnownRecognized)
    );
    assert_eq!(restored_details.occurrences[0].media_id, None);
    assert_eq!(
        restored_services
            .export_vocabulary()
            .unwrap()
            .lexical_observations
            .len(),
        1
    );
    assert_eq!(
        restored_services
            .export_vocabulary()
            .unwrap()
            .learning_observations
            .len(),
        3
    );
    restored_services.import_vocabulary(&bundle).unwrap();
    assert_eq!(
        restored_services
            .export_vocabulary()
            .unwrap()
            .learning_observations
            .len(),
        3
    );
    assert_eq!(
        restored_services
            .lexical_details(&entry.entry.id)
            .unwrap()
            .unwrap()
            .occurrences
            .len(),
        1
    );
}

#[test]
fn vocabulary_query_handles_ten_thousand_profiles_and_fifty_thousand_sources() {
    let repo = SqliteRepository::in_memory().unwrap();
    {
        let mut conn = repo.connection.lock().unwrap();
        let tx = conn.transaction().unwrap();
        for word in 0..10_000 {
            let lexical_kind = if word % 2 == 0 {
                "\"word\""
            } else {
                "\"phrase\""
            };
            let lexical_id = format!("lexical-{word}");
            tx.execute(
                "INSERT INTO lexical_entries
                     (id,language,kind,granularity,normalization,normalized_key,
                      canonical_form,normalized_form,display_form,status,
                      normalization_provider,normalization_version,user_corrected,
                      updated_at_ms,learning_updated_at_ms)
                     VALUES (?1,'en',?2,?5,'core.lemma',?3,?3,?3,?3,
                             '\"unknown_meaning\"','test','v1',0,?4,0)",
                params![
                    lexical_id,
                    lexical_kind,
                    format!("asset-{word:05}"),
                    word,
                    if word % 2 == 0 {
                        "core.word"
                    } else {
                        "core.phrase"
                    },
                ],
            )
            .unwrap();
            for source in 0..5 {
                tx.execute(
                    "INSERT INTO lexical_occurrences
                         (id,source_key,lexical_entry_id,original_form,sentence_text_snapshot,
                          media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,
                          end_ms_snapshot,token_start,token_end,first_seen_at_ms,last_seen_at_ms,
                          encounter_count)
                         VALUES (?1,?2,?3,?4,?5,'Media',?6,?7,?8,NULL,NULL,?9,?9,1)",
                    params![
                        format!("occurrence-{word}-{source}"),
                        format!("source-{word}-{source}"),
                        format!("lexical-{word}"),
                        format!("word-{word:05}"),
                        format!("Sentence containing word-{word:05}"),
                        format!("media-{source}"),
                        source * 1000,
                        source * 1000 + 900,
                        word * 10 + source
                    ],
                )
                .unwrap();
            }
        }
        tx.commit().unwrap();
    }
    let started = std::time::Instant::now();
    let values = repo
        .list_lexical_entries(
            &LanguageCode::parse("en").unwrap(),
            Some(LexicalEntryKind::Word),
            Some(LearningStatus::UnknownMeaning),
            None,
            "asset-09",
            200,
            0,
        )
        .unwrap();
    assert_eq!(values.len(), 200);
    assert!(
        started.elapsed() < std::time::Duration::from_secs(2),
        "large vocabulary query took {:?}",
        started.elapsed()
    );
    let lexical_started = std::time::Instant::now();
    let lexical = repo
        .list_lexical_entries(
            &LanguageCode::parse("en").unwrap(),
            Some(LexicalEntryKind::Phrase),
            Some(LearningStatus::UnknownMeaning),
            None,
            "asset-09",
            200,
            0,
        )
        .unwrap();
    assert_eq!(lexical.len(), 200);
    assert!(
        lexical_started.elapsed() < std::time::Duration::from_secs(2),
        "large lexical query took {:?}",
        lexical_started.elapsed()
    );
}

#[test]
fn failed_source_capture_rolls_back_profile_and_history() {
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
    let result = services.create_lexical_entry(UpsertLexicalEntry {
        language: "en".into(),
        kind: LexicalEntryKind::Word,
        canonical_form: "rollback".into(),
        display_form: "Rollback".into(),
        status: Some(LearningStatus::UnknownMeaning),
        user_definition: None,
        personal_note: None,
        source: Some(application::LexicalSourceContext {
            media_id: Some(MediaId::parse("missing-media").unwrap()),
            sentence_id: None,
            original_form: "Rollback".into(),
            sentence_text: "Rollback this transaction.".into(),
            media_title: "Broken".into(),
            media_fingerprint: "broken".into(),
            start_ms: 10,
            end_ms: 1000,
            token_start: None,
            token_end: None,
        }),
    });
    assert!(result.is_err());
    assert!(read_word_asset(&services, "en", "rollback").is_none());
    assert!(
        services
            .export_vocabulary()
            .unwrap()
            .lexical_history
            .is_empty()
    );
}

#[test]
fn external_import_preserves_existing_status_and_updates_learning_content() {
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
    let summary = services
        .import_external_vocabulary(&ExternalVocabularyImport {
            language: "en".into(),
            entries: vec![
                ExternalVocabularyEntry {
                    word: "Hello".into(),
                    status: None,
                },
                ExternalVocabularyEntry {
                    word: "World".into(),
                    status: Some(LearningStatus::UnknownMeaning),
                },
                ExternalVocabularyEntry {
                    word: "hello".into(),
                    status: None,
                },
            ],
            default_status: Some(LearningStatus::KnownRecognized),
            overwrite_existing: false,
        })
        .unwrap();
    assert_eq!(summary.initialized, 2);
    assert_eq!(summary.skipped, 1);
    assert_eq!(summary.invalid, 0);
    let hello = read_word_asset(&services, "en", "hello").unwrap();
    let details = services
        .update_lexical_learning_content(
            &hello.id,
            Some(" greeting ".into()),
            Some(" personal ".into()),
        )
        .unwrap();
    assert_eq!(details.entry.user_definition.as_deref(), Some("greeting"));
    assert_eq!(services.export_vocabulary().unwrap().version, 7);
    let second = services
        .import_external_vocabulary(&ExternalVocabularyImport {
            language: "en".into(),
            entries: vec![ExternalVocabularyEntry {
                word: "hello".into(),
                status: Some(LearningStatus::UnknownMeaning),
            }],
            default_status: None,
            overwrite_existing: false,
        })
        .unwrap();
    assert_eq!(second.skipped, 1);
    assert_eq!(
        services
            .read_lexical_entries_by_forms("en", LexicalEntryKind::Word, &["hello".into()])
            .unwrap()[0]
            .status,
        Some(LearningStatus::KnownRecognized)
    );
}

#[test]
fn external_import_marks_capability_projection_with_import_source() {
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
    services
        .import_external_vocabulary(&ExternalVocabularyImport {
            language: "en".into(),
            entries: vec![ExternalVocabularyEntry {
                word: "signal".into(),
                status: Some(LearningStatus::KnownNotRecognized),
            }],
            default_status: None,
            overwrite_existing: false,
        })
        .unwrap();
    let entry = read_word_asset(&services, "en", "signal").unwrap();
    let profile = services
        .lexical_capability_profile(&entry.id)
        .unwrap()
        .unwrap();
    for dimension in [&profile.reading, &profile.listening] {
        let projection = dimension.projection.as_ref().unwrap();
        assert_eq!(projection.source, CapabilityProjectionSource::Import);
        assert_eq!(projection.algorithm_version, "legacy-status-compat-v1");
        assert!(dimension.user_override.is_none());
    }
}

#[tokio::test]
async fn dictionary_aggregation_isolates_provider_failure() {
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
    let providers: Vec<Arc<dyn DictionaryProvider>> = vec![
        Arc::new(FailingDictionary),
        Arc::new(FakeDictionary {
            calls: AtomicUsize::new(0),
        }),
    ];
    let bundle = services
        .lookup_dictionary(&providers, "en", "hello")
        .await
        .unwrap();
    assert_eq!(bundle.results.len(), 2);
    assert_eq!(
        bundle.results[0].error.as_deref(),
        Some("dictionary provider failed: offline")
    );
    assert!(bundle.results[1].lookup.is_some());
}
