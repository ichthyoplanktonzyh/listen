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
fn subtitle_and_corpus_unit_of_work_rolls_back_on_projection_failure() {
    let repo = SqliteRepository::in_memory().unwrap();
    let media = MediaItem {
        id: MediaId::from_fingerprint("media", "atomic-subtitle"),
        path: "/tmp/atomic-subtitle.mp4".into(),
        fingerprint: "atomic-subtitle".into(),
        title: "atomic subtitle".into(),
        kind: MediaKind::Video,
        duration: None,
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    MediaRepository::upsert(&repo, &media).unwrap();
    let track = SubtitleTrack {
        id: SubtitleTrackId::from_fingerprint("track", "atomic-subtitle"),
        media_id: media.id.clone(),
        fingerprint: "atomic-subtitle".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "atomic.srt".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("sentence", "atomic-subtitle"),
            index: 0,
            start: TimeMs::new(1_000),
            end: TimeMs::new(2_000),
            original_text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: Vec::new(),
        }],
    };
    let invalid_occurrence = CorpusOccurrence {
        id: CorpusOccurrenceId::from_fingerprint("corpus", "invalid-sentence"),
        language: LanguageCode::parse("en").unwrap(),
        kind: CorpusOccurrenceKind::Lexical,
        normalized_key: Some("hello".into()),
        display_text: "Hello".into(),
        media_id: Some(media.id),
        track_id: Some(track.id.clone()),
        sentence_id: Some(SubtitleSentenceId::parse("missing-sentence").unwrap()),
        start_ms: 1_000,
        end_ms: 2_000,
        source_snapshot: "Hello".into(),
    };

    assert!(
        repo.save_track_and_replace_corpus(&track, &[invalid_occurrence])
            .is_err()
    );
    assert_eq!(repo.get_track(&track.id).unwrap(), None);
    let occurrence_count: u32 = repo
        .connection
        .lock()
        .query_row("SELECT COUNT(*) FROM corpus_occurrences", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(occurrence_count, 0);
}

#[test]
fn retrying_existing_subtitle_repairs_a_missing_corpus_projection() {
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/retry-corpus.mp4".into(),
            fingerprint: "retry-corpus-media".into(),
            title: "Retry corpus".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    let input = ImportSubtitle {
        media_id: media.id,
        source_name: "retry.srt".into(),
        content: b"1\n00:00:01,000 --> 00:00:03,000\nTake care of yourself.\n".to_vec(),
        language: Some("en".into()),
        identity_salt: None,
    };
    let partial_track = services
        .media_analysis()
        .import_subtitle(input.clone())
        .unwrap();
    repo.connection
        .lock()
        .execute(
            "DELETE FROM corpus_occurrences WHERE track_id=?1",
            [partial_track.id.as_str()],
        )
        .unwrap();
    assert!(
        services
            .media_analysis()
            .search_corpus("en", "care", 10, 0)
            .unwrap()
            .is_empty()
    );

    let retried = services.media_analysis().import_subtitle(input).unwrap();

    assert_eq!(retried, partial_track);
    assert_eq!(
        services
            .media_analysis()
            .search_corpus("en", "care", 10, 0)
            .unwrap()
            .len(),
        1
    );
}

#[test]
fn changing_track_language_retokenizes_sentences_and_replaces_corpus_atomically() {
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/retokenize.mp4".into(),
            fingerprint: "retokenize-media".into(),
            title: "Retokenize".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    let english_track = services
        .media_analysis()
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "retokenize.srt".into(),
            content: "1\n00:00:01,000 --> 00:00:03,000\n我想喝咖啡\n"
                .as_bytes()
                .to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    let english_words = english_track.sentences[0]
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .count();
    assert_eq!(english_words, 1);
    let original_sentence = english_track.sentences[0].clone();
    {
        let conn = repo.connection.lock();
        conn.execute(
            "INSERT INTO word_timings
             (sentence_id,timing_source,provider_id,provider_version,timings_json,updated_at_ms)
             VALUES (?1,'\"subtitle\"','test','1','[]',1)",
            [original_sentence.id.as_str()],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO phonetic_analysis_jobs
             (id,media_id,track_id,sentence_id,input_fingerprint,status,job_json,updated_at_ms)
             VALUES ('retokenize-job',?1,?2,?3,'input','\"completed\"','{}',1)",
            rusqlite::params![
                english_track.media_id.as_str(),
                english_track.id.as_str(),
                original_sentence.id.as_str()
            ],
        )
        .unwrap();
    }

    let chinese = LanguageCode::parse("zh").unwrap();
    let updated = services
        .media_analysis()
        .update_track_language(&english_track.id, &chinese)
        .unwrap();

    let chinese_words = updated.sentences[0]
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .count();
    assert!(chinese_words > 1);
    let projected_chinese_key = updated.sentences[0]
        .tokens
        .iter()
        .find(|token| token.kind == SubtitleTokenKind::Word)
        .and_then(|token| token.normalized.clone())
        .unwrap();
    assert_eq!(updated.sentences[0].id, original_sentence.id);
    assert_eq!(
        updated.sentences[0].original_text,
        original_sentence.original_text
    );
    assert_eq!(
        updated.sentences[0].display_text,
        original_sentence.display_text
    );
    assert_eq!(updated.sentences[0].start, original_sentence.start);
    assert_eq!(updated.sentences[0].end, original_sentence.end);
    assert_eq!(repo.get_track(&updated.id).unwrap(), Some(updated.clone()));
    let conn = repo.connection.lock();
    let retained_word_timings: u32 = conn
        .query_row(
            "SELECT COUNT(*) FROM word_timings WHERE sentence_id=?1",
            [original_sentence.id.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    let retained_phonetic_jobs: u32 = conn
        .query_row(
            "SELECT COUNT(*) FROM phonetic_analysis_jobs WHERE sentence_id=?1",
            [original_sentence.id.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    drop(conn);
    assert_eq!(retained_word_timings, 1);
    assert_eq!(retained_phonetic_jobs, 1);
    assert!(
        services
            .media_analysis()
            .search_corpus("en", "我想喝咖啡", 10, 0)
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        services
            .media_analysis()
            .search_corpus("zh", &projected_chinese_key, 10, 0)
            .unwrap()
            .len(),
        1
    );
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/corpus.mp4".into(),
            fingerprint: "corpus-media".into(),
            title: "Corpus media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    services
        .media_analysis()
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "corpus.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:03,000\nTake care of yourself.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();

    let word = services
        .media_analysis()
        .search_corpus("en", "care", 10, 0)
        .unwrap();
    assert_eq!(word.len(), 1);
    assert_eq!(word[0].kind, CorpusOccurrenceKind::Lexical);
    assert_eq!(word[0].display_text, "care");
    let phrase = services
        .media_analysis()
        .search_corpus("en", "take care", 10, 0)
        .unwrap();
    assert_eq!(phrase.len(), 1);
    assert_eq!(phrase[0].kind, CorpusOccurrenceKind::Phrase);
    assert_eq!(phrase[0].source_snapshot, "Take care of yourself.");
}

#[test]
fn active_prosody_analysis_projects_chunk_occurrences_into_corpus() {
    // R5: the corpus chunk projection is sourced from the active Prosody
    // Analysis (the sole prosodic-chunk semantic source) instead of the
    // retired ChunkTimeline. Activating projects chunk rows; archiving
    // removes them.
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/corpus-prosody.mp4".into(),
            fingerprint: "corpus-prosody-media".into(),
            title: "Corpus prosody media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    let track = services
        .media_analysis()
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "corpus-prosody.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:03,000\nTake care of yourself.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    let analysis = ProsodyAnalysis {
        id: ProsodyAnalysisId::parse("corpus-prosody-analysis").unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        parent_word_timeline_id: None,
        provider_id: "listen-gen".into(),
        provider_version: "0.1.0".into(),
        algorithm: "prosody-v1".into(),
        status: TimelineStatus::Candidate,
        created_by: TimelineCreator::Algorithm,
        metrics_json: serde_json::json!({}).into(),
        chunks: vec![domain::ProsodicChunk {
            sentence_id: track.sentences[0].id.clone(),
            chunk_index: 0,
            start_token_index: 0,
            // Tokens are (0, Word "Take"), (1, Whitespace), (2, Word "care");
            // the word-anchored span 0..2 projects the phrase "Take care".
            end_token_index: 2,
            nucleus_token_index: Some(0),
            confidence: 0.9,
        }],
        anchors: vec![ProsodyAnchor {
            word_ref: ProsodyWordRef {
                sentence_id: track.sentences[0].id.clone(),
                token_index: 0,
            },
            syllable_index: None,
            lexical_stress: LexicalStress::Primary,
            realized_prominence: 0.8,
            utterance_role: UtteranceRole::Nucleus,
            evidence: vec![ProsodyEvidence::Energy, ProsodyEvidence::Pitch],
            confidence: 0.9,
        }],
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    repo.save_prosody_analysis(&analysis).unwrap();
    services
        .media_analysis()
        .activate_prosody_analysis(&analysis.id)
        .unwrap();

    let hits = services
        .media_analysis()
        .search_corpus("en", "take care", 10, 0)
        .unwrap();
    let chunks: Vec<_> = hits
        .iter()
        .filter(|hit| hit.kind == CorpusOccurrenceKind::Chunk)
        .collect();
    assert_eq!(chunks.len(), 1);
    assert_eq!(chunks[0].source_snapshot, "Take care");
    assert!(
        hits.iter()
            .any(|hit| hit.kind == CorpusOccurrenceKind::Phrase)
    );

    services
        .media_analysis()
        .archive_prosody_analysis(&analysis.id)
        .unwrap();
    let hits = services
        .media_analysis()
        .search_corpus("en", "take care", 10, 0)
        .unwrap();
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/corpus-sample-a.mp4".into(),
            fingerprint: "corpus-sample-a".into(),
            title: "Sample A".into(),
            kind: MediaKind::Video,
            duration_ms: Some(60_000),
        })
        .unwrap();
    services.media_analysis().import_subtitle(ImportSubtitle {
            media_id: media_a.id,
            source_name: "a.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:02,000\nTake care now.\n\n2\n00:00:03,000 --> 00:00:04,000\nI care a lot.\n\n3\n00:00:05,000 --> 00:00:06,000\nThey care too.\n"
                .to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    let media_b = services
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/corpus-sample-b.mp4".into(),
            fingerprint: "corpus-sample-b".into(),
            title: "Sample B".into(),
            kind: MediaKind::Video,
            duration_ms: Some(60_000),
        })
        .unwrap();
    services
        .media_analysis()
        .import_subtitle(ImportSubtitle {
            media_id: media_b.id.clone(),
            source_name: "b.srt".into(),
            content: b"1\n00:00:50,000 --> 00:00:51,000\nWe care differently.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();

    let hits = services
        .media_analysis()
        .search_corpus("en", "care", 2, 0)
        .unwrap();
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

struct StubLemmaProvider;

impl application::LexicalNormalizationProvider for StubLemmaProvider {
    fn provider_id(&self) -> &'static str {
        "stub-lemma"
    }

    fn version(&self) -> &str {
        "v1"
    }

    fn normalize(
        &self,
        language: &LanguageCode,
        value: &str,
    ) -> Result<Option<String>, application::LexicalNormalizationProviderError> {
        Ok((language.as_str() == "en" && value == "running").then(|| "run".to_owned()))
    }

    fn phrase_candidates(
        &self,
        _language: &LanguageCode,
        _sentence: &SubtitleSentence,
    ) -> Result<Vec<PhraseCandidate>, application::LexicalNormalizationProviderError> {
        Ok(Vec::new())
    }
}

#[test]
fn corpus_word_keys_and_free_text_queries_share_lemma_normalization() {
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
    .with_corpus_index_repository(repo.clone())
    .with_lexical_normalizers(vec![Arc::new(StubLemmaProvider)]);
    let media = services
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/corpus-lemma.mp4".into(),
            fingerprint: "corpus-lemma-media".into(),
            title: "Corpus lemma media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    services
        .media_analysis()
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "corpus-lemma.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:03,000\nHe is running fast.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();

    // The index keys the inflected token by its provider lemma…
    let by_lemma = services
        .media_analysis()
        .search_corpus("en", "run", 10, 0)
        .unwrap();
    assert_eq!(by_lemma.len(), 1);
    assert_eq!(by_lemma[0].display_text, "running");
    assert_eq!(by_lemma[0].normalized_key.as_deref(), Some("run"));
    // …and a free-text inflected query normalizes onto the same key.
    let by_surface = services
        .media_analysis()
        .search_corpus("en", "Running", 10, 0)
        .unwrap();
    assert_eq!(by_surface.len(), 1);
    assert_eq!(by_surface[0].display_text, "running");
}

#[test]
fn deleting_a_track_keeps_corpus_search_coherent() {
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/corpus-delete.mp4".into(),
            fingerprint: "corpus-delete-media".into(),
            title: "Corpus delete media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    let track = services
        .media_analysis()
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "corpus-delete.srt".into(),
            content: b"1\n00:00:01,000 --> 00:00:03,000\nTake care of yourself.\n".to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    assert_eq!(
        services
            .media_analysis()
            .search_corpus("en", "take care", 10, 0)
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        services
            .media_analysis()
            .search_corpus("en", "care", 10, 0)
            .unwrap()
            .len(),
        1
    );

    repo.delete_track(&track.id).unwrap();

    assert!(
        services
            .media_analysis()
            .search_corpus("en", "take care", 10, 0)
            .unwrap()
            .is_empty()
    );
    assert!(
        services
            .media_analysis()
            .search_corpus("en", "care", 10, 0)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn rebuild_corpus_index_backfills_preexisting_tracks() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    // Persist source rows without the atomic projection boundary, modelling a
    // library created before the corpus projection existed (schema < v28).
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/corpus-rebuild.mp4".into(),
            fingerprint: "corpus-rebuild-media".into(),
            title: "Corpus rebuild media".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .unwrap();
    let pre_projection_track = SubtitleTrack {
        id: SubtitleTrackId::from_fingerprint("track", "corpus-rebuild"),
        media_id: media.id,
        fingerprint: "corpus-rebuild".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "corpus-rebuild.srt".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("sentence", "corpus-rebuild"),
            index: 0,
            start: TimeMs::new(1_000),
            end: TimeMs::new(3_000),
            original_text: "Take care of yourself.".into(),
            display_text: "Take care of yourself.".into(),
            tokens: vec![SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "care".into(),
                normalized: Some("care".into()),
                start_char: 5,
                end_char: 9,
            }],
        }],
    };
    repo.save_track(&pre_projection_track).unwrap();

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
            .media_analysis()
            .search_corpus("en", "care", 10, 0)
            .unwrap()
            .is_empty()
    );
    assert_eq!(services.media_analysis().rebuild_corpus_index().unwrap(), 1);
    let hits = services
        .media_analysis()
        .search_corpus("en", "care", 10, 0)
        .unwrap();
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
        .dictionary()
        .lookup_dictionary(&providers, "en", "hello")
        .await
        .unwrap();
    services
        .dictionary()
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
        .dictionary()
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
        .dictionary()
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/zh.mp4".into(),
            fingerprint: "zh-media".into(),
            title: "ZH".into(),
            kind: MediaKind::Video,
            duration_ms: Some(5000),
        })
        .unwrap();
    let track = services
        .media_analysis()
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

    let diagnosis = services
        .media_analysis()
        .diagnose_sentence(&sentence.id)
        .unwrap();
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
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/tmp/zh.mp4".into(),
            fingerprint: "zh-reasons".into(),
            title: "ZH".into(),
            kind: MediaKind::Video,
            duration_ms: Some(5000),
        })
        .unwrap();
    let track = services
        .media_analysis()
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

    let diagnosis = services
        .media_analysis()
        .diagnose_sentence(&sentence.id)
        .unwrap();
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
