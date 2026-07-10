use super::*;

#[test]
fn subtitle_save_is_transactional_and_round_trips() {
    let repo = SqliteRepository::in_memory().unwrap();
    let media = MediaItem {
        id: MediaId::from_fingerprint("media", "m"),
        path: "/tmp/m.mp4".into(),
        fingerprint: "m".into(),
        title: "m".into(),
        kind: MediaKind::Video,
        duration: None,
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    MediaRepository::upsert(&repo, &media).unwrap();
    let track = SubtitleTrack {
        id: SubtitleTrackId::from_fingerprint("track", "t"),
        media_id: media.id,
        fingerprint: "t".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "external".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("sentence", "s"),
            index: 0,
            start: TimeMs::new(10),
            end: TimeMs::new(20),
            original_text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: vec![],
        }],
    };
    repo.save_track(&track).unwrap();
    assert_eq!(repo.get_track(&track.id).unwrap(), Some(track));
}

#[test]
fn imported_subtitles_rebuild_local_corpus_words_and_phrases() {
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
    .with_corpus_index_repository(repo.clone());
    let media = services
        .register_media(RegisterMedia {
            path: "/tmp/corpus.mp4".into(),
            fingerprint: "corpus-media".into(),
            title: "Corpus media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    services
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "corpus.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:03,000\nTake care of yourself.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();

    let word = services.search_corpus("en", "care", 10, 0).unwrap();
    assert_eq!(word.len(), 1);
    assert_eq!(word[0].kind, CorpusOccurrenceKind::Lexical);
    assert_eq!(word[0].display_text, "care");
    let phrase = services.search_corpus("en", "take care", 10, 0).unwrap();
    assert_eq!(phrase.len(), 1);
    assert_eq!(phrase[0].kind, CorpusOccurrenceKind::Phrase);
    assert_eq!(phrase[0].source_snapshot, "Take care of yourself.");
}

#[test]
fn active_chunk_timeline_rows_follow_chunk_lifecycle() {
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
    .with_corpus_index_repository(repo.clone());
    let media = services
        .register_media(RegisterMedia {
            path: "/tmp/corpus-chunk.mp4".into(),
            fingerprint: "corpus-chunk-media".into(),
            title: "Corpus chunk media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    let track = services
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "corpus-chunk.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:03,000\nTake care of yourself.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    let timeline = ChunkTimeline {
        id: ChunkTimelineId::parse("corpus-chunk-timeline").unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        parent_word_timeline_id: None,
        provider_id: "test".into(),
        provider_version: "v1".into(),
        algorithm: "test".into(),
        precision: ChunkTimelinePrecision::Precise,
        created_by: TimelineCreator::Algorithm,
        status: TimelineStatus::Candidate,
        metrics_json: serde_json::json!({}).into(),
        chunks: vec![ChunkTimelineChunk {
            id: ChunkId::parse("corpus-chunk-1").unwrap(),
            sentence_id: track.sentences[0].id.clone(),
            chunk_index: 0,
            start_word_index: 0,
            end_word_index: 1,
            start_ms: 1200,
            end_ms: 1800,
            text: "Take care".into(),
            boundary_sources: Vec::new(),
            confidence: 0.9,
            warnings: Vec::new(),
            evidence_json: serde_json::json!({}).into(),
        }],
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    repo.save_chunk_timeline(&timeline).unwrap();
    services.activate_chunk_timeline(&timeline.id).unwrap();

    let hits = services.search_corpus("en", "take care", 10, 0).unwrap();
    let chunks: Vec<_> = hits
        .iter()
        .filter(|hit| hit.kind == CorpusOccurrenceKind::Chunk)
        .collect();
    assert_eq!(chunks.len(), 1);
    assert_eq!(chunks[0].start_ms, 1200);
    assert_eq!(chunks[0].end_ms, 1800);
    assert_eq!(chunks[0].source_snapshot, "Take care");
    assert!(
        hits.iter()
            .any(|hit| hit.kind == CorpusOccurrenceKind::Phrase)
    );

    services.archive_chunk_timeline(&timeline.id).unwrap();
    let hits = services.search_corpus("en", "take care", 10, 0).unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].kind, CorpusOccurrenceKind::Phrase);
}

#[test]
fn giant_entry_search_samples_across_media() {
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
    .with_corpus_index_repository(repo.clone());
    // Media A holds three early hits; media B one late hit. A start-time
    // ordering would fill a 2-row page entirely from A's opening minutes.
    let media_a = services
        .register_media(RegisterMedia {
            path: "/tmp/corpus-sample-a.mp4".into(),
            fingerprint: "corpus-sample-a".into(),
            title: "Sample A".into(),
            kind: MediaKind::Video,
            duration_ms: Some(60_000),
        })
        .unwrap();
    services
        .import_subtitle(ImportSubtitle {
            media_id: media_a.id,
            source_name: "a.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:02,000\nTake care now.\n\n2\n00:00:03,000 --> 00:00:04,000\nI care a lot.\n\n3\n00:00:05,000 --> 00:00:06,000\nThey care too.\n"
                .to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    let media_b = services
        .register_media(RegisterMedia {
            path: "/tmp/corpus-sample-b.mp4".into(),
            fingerprint: "corpus-sample-b".into(),
            title: "Sample B".into(),
            kind: MediaKind::Video,
            duration_ms: Some(60_000),
        })
        .unwrap();
    services
        .import_subtitle(ImportSubtitle {
            media_id: media_b.id.clone(),
            source_name: "b.srt".into(),
            content: b"1\n00:00:50,000 --> 00:00:51,000\nWe care differently.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();

    let hits = services.search_corpus("en", "care", 2, 0).unwrap();
    assert_eq!(hits.len(), 2);
    let media_ids: std::collections::HashSet<_> = hits
        .iter()
        .filter_map(|hit| hit.media_id.as_ref())
        .collect();
    assert!(
        media_ids.contains(&media_b.id),
        "a truncated page must span media, not just the earliest file"
    );
    assert_eq!(media_ids.len(), 2);
}

#[test]
fn rebuild_corpus_index_backfills_preexisting_tracks() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    // Import through services without a corpus repository, modelling a library
    // created before the projection existed (schema < v28).
    let without_corpus = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    );
    let media = without_corpus
        .register_media(RegisterMedia {
            path: "/tmp/corpus-rebuild.mp4".into(),
            fingerprint: "corpus-rebuild-media".into(),
            title: "Corpus rebuild media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    without_corpus
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "corpus-rebuild.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:03,000\nTake care of yourself.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();

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
    .with_corpus_index_repository(repo.clone());
    assert!(
        services
            .search_corpus("en", "care", 10, 0)
            .unwrap()
            .is_empty()
    );
    assert_eq!(services.rebuild_corpus_index().unwrap(), 1);
    let hits = services.search_corpus("en", "care", 10, 0).unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].display_text, "care");
}

#[tokio::test]
async fn dictionary_lookup_uses_persistent_cache() {
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
    let provider: Arc<dyn DictionaryProvider> = Arc::new(FakeDictionary {
        calls: AtomicUsize::new(0),
    });
    let providers = vec![provider.clone()];
    services
        .lookup_dictionary(&providers, "en", "hello")
        .await
        .unwrap();
    services
        .lookup_dictionary(&providers, "en", "hello")
        .await
        .unwrap();
}

#[tokio::test]
async fn dictionary_lookup_routes_by_learning_language() {
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
    let english = Arc::new(FakeDictionary {
        calls: AtomicUsize::new(0),
    });
    let chinese = Arc::new(FakeChineseDictionary {
        calls: AtomicUsize::new(0),
    });
    let providers: Vec<Arc<dyn DictionaryProvider>> = vec![english.clone(), chinese.clone()];

    // A Chinese query only reaches the zh provider; the en provider is skipped
    // by supported_languages, so en and zh dictionaries never cross-talk.
    let bundle = services
        .lookup_dictionary(&providers, "zh", "咖啡")
        .await
        .unwrap();
    assert_eq!(bundle.results.len(), 1);
    assert_eq!(bundle.results[0].provider.id, "fake-zh");
    let lookup = bundle.results[0]
        .lookup
        .as_ref()
        .expect("zh lookup present");
    assert_eq!(lookup.phonetics[0].text, "kā fēi");
    assert_eq!(english.calls.load(Ordering::Relaxed), 0);
    assert_eq!(chinese.calls.load(Ordering::Relaxed), 1);

    // An English query only reaches the en provider.
    let bundle = services
        .lookup_dictionary(&providers, "en", "hello")
        .await
        .unwrap();
    assert_eq!(bundle.results.len(), 1);
    assert_eq!(bundle.results[0].provider.id, "fake");
    assert_eq!(chinese.calls.load(Ordering::Relaxed), 1);
}

#[test]
fn diagnosis_reads_lexical_entries_in_the_track_language() {
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
            path: "/tmp/zh.mp4".into(),
            fingerprint: "zh-media".into(),
            title: "ZH".into(),
            kind: MediaKind::Video,
            duration_ms: Some(5000),
        })
        .unwrap();
    let track = services
        .import_subtitle(ImportSubtitle {
            media_id: media.id.clone(),
            source_name: "zh.srt".into(),
            content: "1\n00:00:00,000 --> 00:00:02,000\n我想喝咖啡\n"
                .as_bytes()
                .to_vec(),
            language: None,
            identity_salt: None,
        })
        .unwrap();
    // The import detects Chinese, and the new repository method resolves a
    // sentence back to that track language.
    assert_eq!(
        track.language.as_ref().map(LanguageCode::as_str),
        Some("zh")
    );
    let sentence = &track.sentences[0];
    assert_eq!(
        repo.sentence_track_language(&sentence.id)
            .unwrap()
            .as_ref()
            .map(LanguageCode::as_str),
        Some("zh")
    );

    // "我" is a single token under both jieba and the char-level fallback. Give
    // it an UnknownMeaning status in zh, and a *different* status in en for the
    // same surface, to prove diagnosis reads zh and the en profile never leaks.
    let zh_entry = upsert_word_asset(
        &services,
        "zh",
        "我",
        "我",
        Some(LearningStatus::UnknownMeaning),
        None,
    );
    upsert_word_asset(
        &services,
        "en",
        "我",
        "我",
        Some(LearningStatus::KnownRecognized),
        None,
    );

    let diagnosis = services.diagnose_sentence(&sentence.id).unwrap();
    assert!(!diagnosis.unclassified_lemmas.contains(&"我".to_string()));
    let meaning = diagnosis
        .hints
        .iter()
        .find(|hint| hint.kind == DiagnosisKind::MeaningBarrier)
        .expect("zh UnknownMeaning status surfaces a meaning barrier");
    assert!(meaning.lexical_entry_ids.contains(&zh_entry.entry.id));
}

#[test]
fn recognition_barrier_carries_the_language_listening_reasons() {
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
            path: "/tmp/zh.mp4".into(),
            fingerprint: "zh-reasons".into(),
            title: "ZH".into(),
            kind: MediaKind::Video,
            duration_ms: Some(5000),
        })
        .unwrap();
    let track = services
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "zh.srt".into(),
            content: "1\n00:00:00,000 --> 00:00:02,000\n我想喝咖啡\n"
                .as_bytes()
                .to_vec(),
            language: None,
            identity_salt: None,
        })
        .unwrap();
    let sentence = &track.sentences[0];
    // KnownNotRecognized -> the word is known but was not heard -> recognition barrier.
    upsert_word_asset(
        &services,
        "zh",
        "我",
        "我",
        Some(LearningStatus::KnownNotRecognized),
        None,
    );

    let diagnosis = services.diagnose_sentence(&sentence.id).unwrap();
    let recognition = diagnosis
        .hints
        .iter()
        .find(|hint| hint.kind == DiagnosisKind::RecognitionBarrier)
        .expect("KnownNotRecognized surfaces a recognition barrier");
    // The Chinese profile's listening factors are attached as possibilities.
    assert!(recognition.reasons.contains(&"tone_confusion".to_string()));
    assert!(recognition.reasons.contains(&"word_boundary".to_string()));
    // Reasons only decorate the recognition barrier, not other hint kinds.
    for hint in &diagnosis.hints {
        if hint.kind != DiagnosisKind::RecognitionBarrier {
            assert!(hint.reasons.is_empty());
        }
    }
}
