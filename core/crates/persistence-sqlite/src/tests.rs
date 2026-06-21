use super::*;
use application::{
    AppServices, DictionaryProvider, DictionaryProviderError, ImportSubtitle,
    LexicalEntryRepository, MediaRepository, PhoneticAnalysisRepository, RegisterMedia,
    SourceContext, SubtitleRepository, TranscriptionRepository, UpdateWordProfile,
    UpsertLexicalEntry, VocabularyAssetRepository, WordObservationRepository,
};
use async_trait::async_trait;
use domain::*;
use rusqlite::{Connection, params};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

struct FakeDictionary {
    calls: AtomicUsize,
}

struct FailingDictionary;

fn transcription_job(
    id: &str,
    input_fingerprint: &str,
    status: TranscriptionJobStatus,
    updated_at_ms: u64,
) -> TranscriptionJob {
    TranscriptionJob {
        id: TranscriptionJobId::parse(id).unwrap(),
        media_id: MediaId::parse("media-1").unwrap(),
        media_title: "Media".into(),
        media_fingerprint: "media-fp".into(),
        provider_id: "test-provider".into(),
        provider_version: "v1".into(),
        runtime_id: "test-runtime".into(),
        runtime_version: "v1".into(),
        model_id: TranscriptionModelId::parse("model-1").unwrap(),
        model_revision: "rev-1".into(),
        model_checksum_sha256: "checksum".into(),
        destination: TranscriptionDestination::Primary,
        purpose: TranscriptionPurpose::Transcribe,
        requested_language: Some("en".into()),
        detected_language: Some("en".into()),
        audio_track: None,
        settings_json: "{}".into(),
        input_fingerprint: input_fingerprint.into(),
        status,
        phase_progress: 100,
        error_code: None,
        error_message: None,
        retry_of_job_id: None,
        generated_track_id: Some(SubtitleTrackId::parse("track-1").unwrap()),
        created_at_ms: 1,
        started_at_ms: Some(2),
        completed_at_ms: Some(3),
        updated_at_ms,
        archived_at_ms: None,
    }
}

fn transcription_media() -> MediaItem {
    MediaItem {
        id: MediaId::parse("media-1").unwrap(),
        path: "/tmp/media.mp4".into(),
        fingerprint: "media-fp".into(),
        title: "Media".into(),
        kind: MediaKind::Video,
        duration: Some(TimeMs::new(1_000)),
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    }
}

fn word_timeline_track() -> SubtitleTrack {
    let media_id = MediaId::parse("media-1").unwrap();
    SubtitleTrack {
        id: SubtitleTrackId::parse("track-1").unwrap(),
        media_id,
        fingerprint: "track-fp".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: SubtitleSentenceId::parse("sentence-1").unwrap(),
            index: 0,
            start: TimeMs::new(100),
            end: TimeMs::new(800),
            original_text: "hello".into(),
            display_text: "hello".into(),
            tokens: vec![SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "hello".into(),
                normalized: Some("hello".into()),
                start_char: 0,
                end_char: 5,
            }],
        }],
    }
}

fn word_timeline(
    id: &str,
    track: &SubtitleTrack,
    status: TimelineStatus,
    provider_id: &str,
    start_ms: u64,
    end_ms: u64,
) -> WordTimeline {
    let sentence_id = track.sentences[0].id.clone();
    WordTimeline {
        id: WordTimelineId::parse(id).unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        algorithm_id: provider_id.into(),
        algorithm_version: "v1".into(),
        config_hash: format!("{provider_id}-config"),
        parent_timeline_id: None,
        created_by: TimelineCreator::Algorithm,
        status,
        metrics_json: serde_json::json!({}),
        words: vec![WordTiming {
            sentence_id,
            token_index: 0,
            text: "hello".into(),
            start_ms,
            end_ms,
            confidence: Some(0.9),
            timing_source: TimingSource::ForcedAligned,
            provider_id: provider_id.into(),
            provider_version: "v1".into(),
        }],
        created_at_ms: start_ms,
        updated_at_ms: start_ms,
    }
}

#[async_trait]
impl DictionaryProvider for FakeDictionary {
    fn info(&self) -> DictionaryProviderInfo {
        DictionaryProviderInfo {
            id: "fake".into(),
            display_name: "Fake".into(),
            supported_languages: vec!["en".into()],
            provides_definitions: true,
            provides_phonetics: true,
            provides_audio: false,
            offline: true,
        }
    }

    async fn lookup(
        &self,
        _language: &LanguageCode,
        lemma: &str,
    ) -> Result<Option<DictionaryLookup>, DictionaryProviderError> {
        self.calls.fetch_add(1, Ordering::Relaxed);
        Ok(Some(DictionaryLookup {
            query: lemma.into(),
            lemma: lemma.into(),
            definitions: vec![DictionaryDefinition {
                part_of_speech: None,
                text: "definition".into(),
            }],
            phonetics: vec![DictionaryPhonetic {
                text: "/test/".into(),
                region: None,
                audio_url: None,
            }],
            provider: self.info().id,
            cached_at_ms: 0,
        }))
    }
}

#[async_trait]
impl DictionaryProvider for FailingDictionary {
    fn info(&self) -> DictionaryProviderInfo {
        DictionaryProviderInfo {
            id: "failing".into(),
            display_name: "Failing".into(),
            supported_languages: vec!["en".into()],
            provides_definitions: true,
            provides_phonetics: false,
            provides_audio: false,
            offline: false,
        }
    }

    async fn lookup(
        &self,
        _language: &LanguageCode,
        _lemma: &str,
    ) -> Result<Option<DictionaryLookup>, DictionaryProviderError> {
        Err(DictionaryProviderError("offline".into()))
    }
}

#[test]
fn new_database_migrates_to_latest() {
    let repo = SqliteRepository::in_memory().unwrap();
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
}

#[test]
fn pronunciation_cache_isolated_by_provider_version() {
    let repo = SqliteRepository::in_memory().unwrap();
    let pronunciation = WordPronunciation {
        token_index: 0,
        text: "Hello".into(),
        normalized: "hello".into(),
        variants: vec![],
    };
    repo.save_word_pronunciation("en", "en-US", &pronunciation, "provider", "v1")
        .unwrap();

    assert!(
        repo.get_word_pronunciation("en", "en-US", "hello", "provider", "v1")
            .unwrap()
            .is_some()
    );
    assert!(
        repo.get_word_pronunciation("en", "en-US", "hello", "provider", "v2")
            .unwrap()
            .is_none()
    );
    assert!(
        repo.get_word_pronunciation("en", "en-GB", "hello", "provider", "v1")
            .unwrap()
            .is_none()
    );
}

#[test]
fn upgrades_historical_v1_database() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../migrations/0001_media.sql"))
        .unwrap();
    connection.pragma_update(None, "user_version", 1).unwrap();
    migrate(&connection).unwrap();
    let version: u32 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .unwrap();
    assert_eq!(version, MIGRATION_VERSION);
}

#[test]
fn upgrades_historical_v2_database() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../migrations/0001_media.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0002_learning.sql"))
        .unwrap();
    connection.pragma_update(None, "user_version", 2).unwrap();
    migrate(&connection).unwrap();
    let version: u32 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .unwrap();
    assert_eq!(version, MIGRATION_VERSION);
}

#[test]
fn upgrades_historical_v3_database_and_creates_legacy_history() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../migrations/0001_media.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0002_learning.sql"))
        .unwrap();
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))
        .unwrap();
    connection.pragma_update(None, "user_version", 3).unwrap();
    connection.execute(
            "INSERT INTO word_profiles VALUES ('p','en','hello','hello','Hello','\"known_recognized\"',10)",
            [],
        ).unwrap();
    migrate(&connection).unwrap();
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM word_status_history", [], |r| r
                .get::<_, u32>(0))
            .unwrap(),
        1
    );
}

#[test]
fn upgrades_historical_v4_database_and_preserves_profiles() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../migrations/0001_media.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0002_learning.sql"))
        .unwrap();
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0004_vocabulary_assets.sql"))
        .unwrap();
    connection.pragma_update(None, "user_version", 4).unwrap();
    connection.execute(
            "INSERT INTO word_profiles VALUES ('p','en','hello','hello','Hello','\"known_recognized\"',10)",
            [],
        ).unwrap();
    migrate(&connection).unwrap();
    let values: (String, Option<String>, u64) = connection.query_row(
            "SELECT display_form,user_definition,learning_updated_at_ms FROM word_profiles WHERE id='p'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        ).unwrap();
    assert_eq!(values, ("Hello".into(), None, 0));
}

#[test]
fn upgrades_historical_v5_database_and_adds_transcription_assets() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../migrations/0001_media.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0002_learning.sql"))
        .unwrap();
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0004_vocabulary_assets.sql"))
        .unwrap();
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    connection
        .execute_batch(include_str!("../migrations/0005_learning_experience.sql"))
        .unwrap();
    connection.pragma_update(None, "user_version", 5).unwrap();
    migrate(&connection).unwrap();
    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM transcription_jobs", [], |row| row
                .get::<_, u32>(0))
            .unwrap(),
        0
    );
}

#[test]
fn archived_transcription_jobs_are_hidden_from_list_and_reuse() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let mut job = transcription_job("job-1", "same-input", TranscriptionJobStatus::Completed, 10);
    repo.create_job(&job).unwrap();

    assert_eq!(repo.list_jobs().unwrap().len(), 1);
    assert_eq!(
        repo.find_completed_job("same-input")
            .unwrap()
            .expect("completed job should be reusable")
            .id,
        job.id
    );

    job.archived_at_ms = Some(20);
    job.updated_at_ms = 20;
    repo.update_job(&job).unwrap();

    assert!(repo.list_jobs().unwrap().is_empty());
    assert!(repo.find_completed_job("same-input").unwrap().is_none());
    assert_eq!(
        repo.get_job(&job.id)
            .unwrap()
            .expect("archive should not delete job")
            .archived_at_ms,
        Some(20)
    );
}

#[test]
fn activating_word_timeline_updates_active_resource_and_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let older = word_timeline(
        "timeline-1",
        &track,
        TimelineStatus::Active,
        "whisper-dtw",
        120,
        300,
    );
    let newer = word_timeline(
        "timeline-2",
        &track,
        TimelineStatus::Candidate,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&older).unwrap();
    repo.save_word_timeline(&newer).unwrap();

    let active = repo.activate_word_timeline(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_word_timeline(&track.id).unwrap().unwrap().id,
        newer.id
    );
    assert_eq!(
        repo.get_word_timeline(&older.id).unwrap().unwrap().status,
        TimelineStatus::Candidate
    );

    let compatibility_timings = repo.get_word_timings(&sentence_id).unwrap();
    assert_eq!(compatibility_timings.len(), 1);
    assert_eq!(compatibility_timings[0].provider_id, "mms-fa");
    assert_eq!(compatibility_timings[0].start_ms, 150);
    assert_eq!(compatibility_timings[0].end_ms, 260);
}

#[test]
fn archiving_active_word_timeline_clears_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let timeline = word_timeline(
        "timeline-archive-active",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&timeline).unwrap();
    repo.activate_word_timeline(&timeline.id).unwrap();

    let archived = repo.archive_word_timeline(&timeline.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
    assert!(repo.get_word_timings(&sentence_id).unwrap().is_empty());
}

#[test]
fn deleting_active_word_timeline_clears_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let timeline = word_timeline(
        "timeline-delete-active",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&timeline).unwrap();
    repo.activate_word_timeline(&timeline.id).unwrap();

    let deleted = repo.delete_word_timeline(&timeline.id).unwrap();
    assert_eq!(deleted.id, timeline.id);
    assert!(repo.get_word_timeline(&timeline.id).unwrap().is_none());
    assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
    assert!(repo.get_word_timings(&sentence_id).unwrap().is_empty());
}

#[test]
fn lltimeline_resource_metadata_and_artifacts_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let metadata = LLTimelineMetadata {
        created_at_ms: 42,
        generator: LLTimelineGenerator {
            id: "fixture-production-engine".into(),
            version: "v2".into(),
            mode: "production_engine".into(),
        },
        media: LLTimelineMedia {
            id: track.media_id.clone(),
            fingerprint: "media-fingerprint".into(),
            path: None,
            title: "Fixture".into(),
            duration_ms: Some(1200),
        },
        language: track.language.clone(),
        human_reviewed: true,
        extra: serde_json::json!({"track_source": "fixture.lltimeline.json"}),
    };
    let artifacts = vec![LLTimelineArtifact {
        kind: "production_report".into(),
        provider_id: Some("fixture-production-engine".into()),
        provider_version: Some("v2".into()),
        payload: serde_json::json!({"readiness": "ready"}),
    }];

    repo.save_lltimeline_resource(&track.id, &metadata, &artifacts)
        .unwrap();

    let (saved_metadata, saved_artifacts) = repo
        .get_lltimeline_resource(&track.id)
        .unwrap()
        .expect("resource metadata should be saved");
    assert_eq!(saved_metadata.generator.id, "fixture-production-engine");
    assert!(saved_metadata.human_reviewed);
    assert_eq!(saved_artifacts.len(), 1);
    assert_eq!(saved_artifacts[0].kind, "production_report");
}

#[test]
fn upgrades_historical_v6_database_and_migrates_words_to_lexical_entries() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../migrations/0001_media.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0002_learning.sql"))
        .unwrap();
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0004_vocabulary_assets.sql"))
        .unwrap();
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    connection
        .execute_batch(include_str!("../migrations/0005_learning_experience.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../migrations/0006_transcription.sql"))
        .unwrap();
    connection.pragma_update(None, "user_version", 6).unwrap();
    connection
        .execute(
            "INSERT INTO word_profiles
             (id,language,lemma,normalized_lemma,display_form,status,updated_at_ms,
              user_definition,personal_note,learning_updated_at_ms)
             VALUES ('legacy','en','went','went','Went','\"known_not_recognized\"',10,
                     'past tense','from a lesson',11)",
            [],
        )
        .unwrap();
    migrate(&connection).unwrap();
    let value: (String, String, Option<String>, Option<String>) = connection
        .query_row(
            "SELECT kind,display_form,user_definition,personal_note
                 FROM lexical_entries WHERE id='legacy'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();
    assert_eq!(
        value,
        (
            "\"word\"".into(),
            "Went".into(),
            Some("past tense".into()),
            Some("from a lesson".into())
        )
    );
}

#[test]
fn upgrades_historical_v7_database_and_preserves_lexical_assets() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../migrations/0001_media.sql"),
        include_str!("../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../migrations/0003_subtitle_identity.sql"),
        include_str!("../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../migrations/0005_learning_experience.sql"),
        include_str!("../migrations/0006_transcription.sql"),
        include_str!("../migrations/0007_lexical_entries.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.pragma_update(None, "user_version", 7).unwrap();
    connection
        .execute(
            "INSERT INTO lexical_entries
                 (id,language,kind,canonical_form,normalized_form,display_form,status,
                  normalization_provider,normalization_version,user_corrected,updated_at_ms,
                  learning_updated_at_ms)
                 VALUES ('asset','en','\"word\"','hello','hello','Hello','\"known_recognized\"',
                         'legacy','v1',0,10,0)",
            [],
        )
        .unwrap();
    migrate(&connection).unwrap();
    assert_eq!(
        connection
            .query_row(
                "SELECT display_form FROM lexical_entries WHERE id='asset'",
                [],
                |row| { row.get::<_, String>(0) }
            )
            .unwrap(),
        "Hello"
    );
    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
}

#[test]
fn upgrades_historical_v8_database_and_adds_phonetic_analysis_assets() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../migrations/0001_media.sql"),
        include_str!("../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../migrations/0003_subtitle_identity.sql"),
        include_str!("../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../migrations/0005_learning_experience.sql"),
        include_str!("../migrations/0006_transcription.sql"),
        include_str!("../migrations/0007_lexical_entries.sql"),
        include_str!("../migrations/0008_pronunciation.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.pragma_update(None, "user_version", 8).unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM phonetic_analysis_jobs", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM phonetic_analyses", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
}

#[test]
fn upgrades_historical_v9_database_and_adds_word_timeline_assets() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../migrations/0001_media.sql"),
        include_str!("../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../migrations/0003_subtitle_identity.sql"),
        include_str!("../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../migrations/0005_learning_experience.sql"),
        include_str!("../migrations/0006_transcription.sql"),
        include_str!("../migrations/0007_lexical_entries.sql"),
        include_str!("../migrations/0008_pronunciation.sql"),
        include_str!("../migrations/0009_phonetic_analysis.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.pragma_update(None, "user_version", 9).unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM word_timeline_runs", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM lltimeline_resources", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
}

#[test]
fn upgrades_historical_v10_database_and_adds_lltimeline_resources() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../migrations/0001_media.sql"),
        include_str!("../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../migrations/0003_subtitle_identity.sql"),
        include_str!("../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../migrations/0005_learning_experience.sql"),
        include_str!("../migrations/0006_transcription.sql"),
        include_str!("../migrations/0007_lexical_entries.sql"),
        include_str!("../migrations/0008_pronunciation.sql"),
        include_str!("../migrations/0009_phonetic_analysis.sql"),
        include_str!("../migrations/0010_word_timelines.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.pragma_update(None, "user_version", 10).unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM lltimeline_resources", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
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

    let word = services
        .update_word_profile(UpdateWordProfile {
            language: "en".into(),
            lemma: "Hello".into(),
            display_form: "Hello".into(),
            status: Some(WordStatus::KnownRecognized),
            source: None,
        })
        .unwrap();
    assert_eq!(
        services.read_word_profile("EN", "hello").unwrap(),
        Some(word)
    );

    let subtitle = ImportSubtitle {
        media_id: first.id,
        source_name: "timeline.srt".into(),
        content: include_bytes!("../../../testdata/subtitles/timeline.srt").to_vec(),
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
            status: Some(WordStatus::KnownNotRecognized),
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
            status: Some(WordStatus::KnownRecognized),
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .unwrap();
    assert_ne!(phrase.entry.id, word.entry.id);
    assert_eq!(phrase.occurrences.len(), 1);
    assert_eq!(phrase.entry.status, Some(WordStatus::KnownNotRecognized));
    assert_eq!(word.entry.status, Some(WordStatus::KnownRecognized));
    services
        .update_word_profile(UpdateWordProfile {
            language: "en".into(),
            lemma: "give".into(),
            display_form: "give".into(),
            status: Some(WordStatus::UnknownMeaning),
            source: None,
        })
        .unwrap();
    let words = services
        .list_lexical_entries("en", Some(LexicalEntryKind::Word), None, "give", 10, 0)
        .unwrap();
    assert_eq!(words.len(), 1);
    assert_eq!(words[0].entry.status, Some(WordStatus::UnknownMeaning));
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
            status: Some(WordStatus::KnownRecognized),
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
            status: Some(WordStatus::UnknownMeaning),
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
            status: Some(WordStatus::KnownRecognized),
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
    imported_entry.status = Some(WordStatus::UnknownMeaning);
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
        new_status: Some(WordStatus::UnknownMeaning),
        changed_at_ms: local.entry.updated_at_ms.saturating_sub(1),
        change_source: WordChangeSource::Import,
    };

    repo.import_lexical_assets(
        std::slice::from_ref(&imported_entry),
        std::slice::from_ref(&imported_history),
        std::slice::from_ref(&imported_occurrence),
    )
    .unwrap();
    repo.import_lexical_assets(
        std::slice::from_ref(&imported_entry),
        std::slice::from_ref(&imported_history),
        std::slice::from_ref(&imported_occurrence),
    )
    .unwrap();
    let merged = services.lexical_details(&local.entry.id).unwrap().unwrap();
    assert_eq!(merged.entry.status, Some(WordStatus::KnownRecognized));
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
            .filter(|value| value.change_source == WordChangeSource::Import)
            .count(),
        1
    );
    assert_eq!(
        merged
            .history
            .iter()
            .find(|value| value.change_source == WordChangeSource::Import)
            .map(|value| &value.lexical_entry_id),
        Some(&local.entry.id)
    );
}

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
            content: include_bytes!("../../../testdata/subtitles/timeline.srt").to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .unwrap();
    let sentence = &track.sentences[0];
    let source = SourceContext {
        language: LanguageCode::parse("en").unwrap(),
        normalized_lemma: "hello".into(),
        media_id: Some(media.id),
        sentence_id: Some(sentence.id.clone()),
        original_form: "Hello".into(),
        sentence_text: sentence.display_text.clone(),
        media_title: "Source".into(),
        media_fingerprint: "source-media".into(),
        start_ms: sentence.start.get(),
        end_ms: sentence.end.get(),
    };
    let profile = services
        .update_word_profile(UpdateWordProfile {
            language: "en".into(),
            lemma: "hello".into(),
            display_form: "Hello".into(),
            status: Some(WordStatus::UnknownMeaning),
            source: Some(source.clone()),
        })
        .unwrap();
    services
        .update_word_profile(UpdateWordProfile {
            language: "en".into(),
            lemma: "hello".into(),
            display_form: "Hello".into(),
            status: Some(WordStatus::KnownRecognized),
            source: Some(source),
        })
        .unwrap();
    let details = services.word_details(&profile.id).unwrap().unwrap();
    assert_eq!(details.history.len(), 2);
    assert_eq!(details.occurrences[0].encounter_count, 2);

    services
        .create_observation(application::CreateWordObservation {
            word_profile_id: profile.id.clone(),
            sentence_id: sentence.id.clone(),
            original_form: "Hello".into(),
            result: ObservationResult::RecognizedInContext,
            source: None,
        })
        .unwrap();
    services
        .create_observation(application::CreateWordObservation {
            word_profile_id: profile.id.clone(),
            sentence_id: sentence.id.clone(),
            original_form: "Hello".into(),
            result: ObservationResult::NotRecognizedInContext,
            source: None,
        })
        .unwrap();
    assert_eq!(
        repo.list_by_sentence(&sentence.id).unwrap()[0].result,
        ObservationResult::NotRecognizedInContext
    );
    services
        .clear_observation(&profile.id, &sentence.id)
        .unwrap();
    assert!(repo.list_by_sentence(&sentence.id).unwrap().is_empty());

    services
        .set_media_availability(
            &details.occurrences[0].media_id.clone().unwrap(),
            MediaAvailability::Archived,
        )
        .unwrap();
    assert_eq!(
        services
            .word_details(&profile.id)
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
    let relinked = services.word_details(&profile.id).unwrap().unwrap();
    assert!(relinked.occurrences[0].media_id.is_some());
    assert!(relinked.occurrences[0].sentence_id.is_some());
    services
        .create_observation(application::CreateWordObservation {
            word_profile_id: profile.id.clone(),
            sentence_id: sentence.id.clone(),
            original_form: "Hello".into(),
            result: ObservationResult::RecognizedInContext,
            source: None,
        })
        .unwrap();

    let bundle = services.export_vocabulary().unwrap();
    assert_eq!(bundle.observations.len(), 1);
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
        .word_details(&profile.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        restored_details.profile.status,
        Some(WordStatus::KnownRecognized)
    );
    assert_eq!(restored_details.occurrences[0].media_id, None);
    assert_eq!(
        restored_services
            .export_vocabulary()
            .unwrap()
            .observations
            .len(),
        1
    );
    restored_services.import_vocabulary(&bundle).unwrap();
    assert_eq!(
        restored_services
            .word_details(&profile.id)
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
            let profile_id = format!("profile-{word}");
            let lexical_kind = if word % 2 == 0 {
                "\"word\""
            } else {
                "\"phrase\""
            };
            tx.execute(
                "INSERT INTO word_profiles
                     (id,language,lemma,normalized_lemma,display_form,status,updated_at_ms)
                     VALUES (?1,'en',?2,?2,?2,'\"unknown_meaning\"',?3)",
                params![profile_id, format!("word-{word:05}"), word],
            )
            .unwrap();
            tx.execute(
                "INSERT INTO lexical_entries
                     (id,language,kind,canonical_form,normalized_form,display_form,status,
                      normalization_provider,normalization_version,user_corrected,
                      updated_at_ms,learning_updated_at_ms)
                     VALUES (?1,'en',?2,?3,?3,?3,'\"unknown_meaning\"','test','v1',0,?4,0)",
                params![
                    format!("lexical-{word}"),
                    lexical_kind,
                    format!("asset-{word:05}"),
                    word
                ],
            )
            .unwrap();
            for source in 0..5 {
                tx.execute(
                    "INSERT INTO word_occurrences
                         (id,source_key,word_profile_id,original_form,sentence_text_snapshot,
                          media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,
                          end_ms_snapshot,first_seen_at_ms,last_seen_at_ms,encounter_count)
                         VALUES (?1,?2,?3,?4,?5,'Media',?6,?7,?8,?9,?9,1)",
                    params![
                        format!("occurrence-{word}-{source}"),
                        format!("source-{word}-{source}"),
                        profile_id,
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
        .list_vocabulary(
            &LanguageCode::parse("en").unwrap(),
            WordStatus::UnknownMeaning,
            "word-09",
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
            Some(WordStatus::UnknownMeaning),
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
    let result = services.update_word_profile(UpdateWordProfile {
        language: "en".into(),
        lemma: "rollback".into(),
        display_form: "Rollback".into(),
        status: Some(WordStatus::UnknownMeaning),
        source: Some(SourceContext {
            language: LanguageCode::parse("en").unwrap(),
            normalized_lemma: "rollback".into(),
            media_id: Some(MediaId::parse("missing-media").unwrap()),
            sentence_id: None,
            original_form: "Rollback".into(),
            sentence_text: "Rollback this transaction.".into(),
            media_title: "Broken".into(),
            media_fingerprint: "broken".into(),
            start_ms: 10,
            end_ms: 1000,
        }),
    });
    assert!(result.is_err());
    assert!(
        services
            .read_word_profile("en", "rollback")
            .unwrap()
            .is_none()
    );
    assert!(services.export_vocabulary().unwrap().history.is_empty());
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
                    status: Some(WordStatus::UnknownMeaning),
                },
                ExternalVocabularyEntry {
                    word: "hello".into(),
                    status: None,
                },
            ],
            default_status: Some(WordStatus::KnownRecognized),
            overwrite_existing: false,
        })
        .unwrap();
    assert_eq!(summary.created, 2);
    assert_eq!(summary.invalid, 1);
    let hello = services.read_word_profile("en", "hello").unwrap().unwrap();
    let details = services
        .update_word_learning_content(
            &hello.id,
            Some(" greeting ".into()),
            Some(" personal ".into()),
        )
        .unwrap();
    assert_eq!(details.profile.user_definition.as_deref(), Some("greeting"));
    assert_eq!(services.export_vocabulary().unwrap().version, 4);
    let second = services
        .import_external_vocabulary(&ExternalVocabularyImport {
            language: "en".into(),
            entries: vec![ExternalVocabularyEntry {
                word: "hello".into(),
                status: Some(WordStatus::UnknownMeaning),
            }],
            default_status: None,
            overwrite_existing: false,
        })
        .unwrap();
    assert_eq!(second.skipped, 1);
    assert_eq!(
        services
            .read_word_profile("en", "hello")
            .unwrap()
            .unwrap()
            .status,
        Some(WordStatus::KnownRecognized)
    );
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

#[test]
fn phonetic_models_jobs_analyses_and_feedback_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    let media = MediaItem {
        id: MediaId::from_fingerprint("media", "phonetic"),
        path: "/tmp/phonetic.wav".into(),
        fingerprint: "phonetic-media".into(),
        title: "Phonetic".into(),
        kind: MediaKind::Audio,
        duration: Some(TimeMs::new(5_000)),
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    MediaRepository::upsert(&repo, &media).unwrap();
    let sentence_id = SubtitleSentenceId::from_fingerprint("sentence", "phonetic");
    let track = SubtitleTrack {
        id: SubtitleTrackId::from_fingerprint("track", "phonetic"),
        media_id: media.id.clone(),
        fingerprint: "phonetic-track".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: sentence_id.clone(),
            index: 0,
            start: TimeMs::new(100),
            end: TimeMs::new(500),
            original_text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: vec![],
        }],
    };
    repo.save_track(&track).unwrap();
    let model_id = PhoneticAnalysisModelId::from_fingerprint("model", "fake");
    let model = PhoneticAnalysisModelDescriptor {
        id: model_id.clone(),
        provider_id: "fake".into(),
        display_name: "Fake".into(),
        family: "fake".into(),
        revision: "v1".into(),
        checksum_sha256: "abc".into(),
        download_url: None,
        local_path: None,
        size_bytes: 0,
        supported_languages: vec!["en".into()],
        supported_dialects: vec!["en-US".into()],
        phone_sets: vec!["arpabet".into()],
        supports_timestamps: true,
        expected_sample_rate_hz: 16_000,
        context_window_ms: None,
        state: PhoneticModelState::Custom,
        installed_bytes: 0,
        error: None,
        license: "test".into(),
        training_data_provenance: "synthetic".into(),
        distribution_allowed: false,
        application_verified: false,
        updated_at_ms: 1,
    };
    repo.upsert_phonetic_model(&model).unwrap();
    assert_eq!(repo.get_phonetic_model(&model_id).unwrap(), Some(model));

    let job_id = PhoneticAnalysisJobId::from_fingerprint("job", "fake");
    let mut job = PhoneticAnalysisJob {
        id: job_id.clone(),
        media_id: media.id.clone(),
        track_id: track.id.clone(),
        sentence_id: Some(sentence_id.clone()),
        scope: PhoneticAnalysisScope::Sentence,
        audio_start_ms: 100,
        audio_end_ms: 500,
        provider_id: "fake".into(),
        provider_version: "v1".into(),
        runtime_id: "fake".into(),
        runtime_version: "v1".into(),
        model_id: model_id.clone(),
        model_revision: "v1".into(),
        model_checksum_sha256: "abc".into(),
        requested_phone_set: "arpabet".into(),
        settings_json: "{}".into(),
        input_fingerprint: "input".into(),
        status: PhoneticAnalysisJobStatus::Queued,
        phase_progress: 0,
        error_code: None,
        error_message: None,
        retry_of_job_id: None,
        analysis_id: None,
        created_at_ms: 1,
        started_at_ms: None,
        completed_at_ms: None,
        updated_at_ms: 1,
    };
    repo.create_phonetic_job(&job).unwrap();
    repo.interrupt_active_phonetic_jobs(2).unwrap();
    job = repo.get_phonetic_job(&job_id).unwrap().unwrap();
    assert_eq!(job.status, PhoneticAnalysisJobStatus::Interrupted);

    job.status = PhoneticAnalysisJobStatus::Completed;
    job.updated_at_ms = 3;
    let analysis_id = PhoneticAnalysisId::from_fingerprint("analysis", "fake");
    job.analysis_id = Some(analysis_id.clone());
    repo.update_phonetic_job(&job).unwrap();
    let finding_id = PhoneticFindingId::from_fingerprint("finding", "fake");
    let analysis = PhoneticAnalysis {
        id: analysis_id.clone(),
        job_id,
        media_id: media.id,
        track_id: track.id.clone(),
        sentence_id: Some(sentence_id),
        audio_start_ms: 100,
        audio_end_ms: 500,
        provider_id: "fake".into(),
        provider_version: "v1".into(),
        model_id,
        model_revision: "v1".into(),
        model_checksum_sha256: "abc".into(),
        phone_set: "arpabet".into(),
        detected_phones: vec![DetectedPhone {
            symbol: "HH".into(),
            phone_set: "arpabet".into(),
            start_ms: 100,
            end_ms: 200,
            confidence: Some(0.9),
            token_index: Some(0),
            provider_id: "fake".into(),
            provider_version: "v1".into(),
            model_revision: "v1".into(),
        }],
        alignments: vec![],
        findings: vec![PhoneticFinding {
            id: finding_id.clone(),
            analysis_id: analysis_id.clone(),
            finding_type: "weak_form".into(),
            affected_token_start: 0,
            affected_token_end: 0,
            canonical_phones: vec!["HH".into()],
            detected_phones: vec!["HH".into()],
            aligned_phone_start: Some(0),
            aligned_phone_end: Some(0),
            audio_start_ms: 100,
            audio_end_ms: 200,
            confidence: 0.7,
            evidence: "fake".into(),
            status: PhoneticFindingStatus::SupportedByAlignment,
        }],
        analyzer_version: "v1".into(),
        created_at_ms: 3,
    };
    repo.save_phonetic_analysis(&analysis).unwrap();
    assert_eq!(
        repo.list_track_phonetic_analyses(&track.id).unwrap(),
        vec![analysis.clone()]
    );
    repo.delete_phonetic_model(&analysis.model_id).unwrap();
    assert_eq!(
        repo.list_track_phonetic_analyses(&track.id).unwrap(),
        vec![analysis.clone()]
    );
    let mut revised_analysis = analysis.clone();
    revised_analysis.id = PhoneticAnalysisId::from_fingerprint("analysis", "fake-v2");
    for finding in &mut revised_analysis.findings {
        finding.id = PhoneticFindingId::from_fingerprint("finding", "fake-v2");
        finding.analysis_id = revised_analysis.id.clone();
    }
    revised_analysis.model_revision = "v2".into();
    revised_analysis.created_at_ms = 4;
    repo.save_phonetic_analysis(&revised_analysis).unwrap();
    let versions = repo.list_track_phonetic_analyses(&track.id).unwrap();
    assert_eq!(versions.len(), 2);
    assert!(versions.contains(&analysis));
    assert!(versions.contains(&revised_analysis));
    let feedback = PhoneticFindingFeedback {
        finding_id: finding_id.clone(),
        value: PhoneticFindingFeedbackValue::Rejected,
        note: Some("test".into()),
        updated_at_ms: 4,
    };
    repo.save_phonetic_feedback(&feedback).unwrap();
    assert_eq!(
        repo.get_phonetic_feedback(&finding_id).unwrap(),
        Some(feedback.clone())
    );
    let bundle = repo.export_assets().unwrap();
    assert_eq!(bundle.version, 4);
    assert_eq!(bundle.phonetic_finding_feedback, vec![feedback.clone()]);
    let restored = SqliteRepository::in_memory().unwrap();
    restored.import_assets(&bundle).unwrap();
    assert_eq!(
        restored.get_phonetic_feedback(&finding_id).unwrap(),
        Some(feedback)
    );
}
