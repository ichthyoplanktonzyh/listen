use super::*;
use application::{
    AppServices, ApplicationError, CoachDashboardRepository, DictionaryProvider,
    DictionaryProviderError, ImportSubtitle, LearningAssetRepository, LearningEventRepository,
    ListeningInboxRepository, MediaRepository, PhoneticAnalysisRepository, PracticeRepository,
    RegisterMedia, ReviewRepository, SubtitleRepository, TranscriptionRepository,
    UpsertLexicalEntry,
};

#[test]
fn coach_dashboard_aggregates_period_facts_without_scanning_json_in_application() {
    let repo = SqliteRepository::in_memory().unwrap();
    let conn = repo.connection.lock().unwrap();
    conn.execute("INSERT INTO practice_items (id,kind,target_kind,created_at_ms,item_json) VALUES ('item','\"cloze\"','\"sentence\"',100,'{}')", []).unwrap();
    conn.execute("INSERT INTO practice_attempts (id,item_id,result,submitted_at_ms,attempt_json) VALUES ('attempt','item','\"correct\"',150,'{}')", []).unwrap();
    conn.execute("INSERT INTO practice_sessions (id,mode,started_at_ms,ended_at_ms,session_json) VALUES ('session','\"extensive\"',100,6100,'{}')", []).unwrap();
    drop(conn);
    let facts = repo.coach_dashboard_facts(0, 10000, 10000).unwrap();
    assert_eq!(facts.practice_attempts, 1);
    assert_eq!(facts.correct_practice_attempts, 1);
    assert_eq!(facts.extensive_sessions, 1);
    assert_eq!(facts.extensive_listening_ms, 6000);
    let evidence = repo
        .coach_evidence("correct_practice_attempts", 0, 10_000, 10, 0)
        .unwrap();
    assert_eq!(evidence.len(), 1);
    assert_eq!(evidence[0].id, "attempt");
}

#[test]
fn coach_dashboard_derives_material_trajectory_and_requires_confirmed_graduation() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let conn = repo.connection.lock().unwrap();
    conn.execute("INSERT INTO media_items (id,path,fingerprint,title,kind,created_at_ms,updated_at_ms) VALUES ('media-coach','/tmp/coach.mp4','coach-fp','Coach media','\"video\"',1,1)", []).unwrap();
    for (id, started) in [("session-a", 100_u64), ("session-b", 200_u64)] {
        conn.execute("INSERT INTO practice_sessions (id,mode,media_id,started_at_ms,ended_at_ms,session_json) VALUES (?1,'\"extensive\"','media-coach',?2,?3,'{}')", params![id, started, started + 50]).unwrap();
    }
    conn.execute("INSERT INTO learning_events (id,occurred_at_ms,kind,subject_kind,subject_id,session_id,event_json) VALUES ('event-a',150,'\"listening_completed\"','\"practice_session\"','session-a','session-a',?1)", [serde_json::json!({"payload":{"comprehension_report":"got_the_gist"}}).to_string()]).unwrap();
    conn.execute("INSERT INTO learning_events (id,occurred_at_ms,kind,subject_kind,subject_id,session_id,event_json) VALUES ('event-b',250,'\"listening_completed\"','\"practice_session\"','session-b','session-b',?1)", [serde_json::json!({"payload":{"comprehension_report":"understood_all"}}).to_string()]).unwrap();
    drop(conn);
    let facts = repo.coach_dashboard_facts(0, 1000, 1000).unwrap();
    assert_eq!(
        facts.materials[0].first_report.as_deref(),
        Some("got_the_gist")
    );
    assert_eq!(
        facts.materials[0].latest_report.as_deref(),
        Some("understood_all")
    );
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
    .with_coach_dashboard_repository(repo.clone());
    let graduated = services
        .graduate_coach_material(&MediaId::parse("media-coach").unwrap())
        .unwrap();
    assert_eq!(graduated.triage_intent, Some(MediaTriageIntent::Graduated));
}

#[test]
fn coach_dashboard_large_event_query_stays_bounded() {
    let repo = SqliteRepository::in_memory().unwrap();
    let mut conn = repo.connection.lock().unwrap();
    let tx = conn.transaction().unwrap();
    for index in 0..10_000_u64 {
        tx.execute(
            "INSERT INTO learning_events (id,occurred_at_ms,kind,subject_kind,subject_id,event_json) VALUES (?1,?2,'\"l1_difficulty_hit\"','\"sentence\"',?3,'{}')",
            params![format!("event-{index}"), index, format!("sentence-{index}")],
        ).unwrap();
    }
    tx.commit().unwrap();
    drop(conn);
    let started = std::time::Instant::now();
    let facts = repo.coach_dashboard_facts(0, 20_000, 20_000).unwrap();
    assert_eq!(facts.l1_difficulty_hits, 10_000);
    assert!(started.elapsed() < std::time::Duration::from_secs(2));
}
use async_trait::async_trait;
use domain::*;
use rusqlite::{Connection, params};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

const LEGACY_PHASE_218_LEXICAL_SCHEMA: &str = r#"
CREATE TABLE lexical_entries (
  id TEXT PRIMARY KEY NOT NULL,
  language TEXT NOT NULL,
  kind TEXT NOT NULL,
  canonical_form TEXT NOT NULL,
  normalized_form TEXT NOT NULL,
  display_form TEXT NOT NULL,
  status TEXT,
  user_definition TEXT,
  personal_note TEXT,
  normalization_provider TEXT NOT NULL,
  normalization_version TEXT NOT NULL,
  user_corrected INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL,
  learning_updated_at_ms INTEGER NOT NULL DEFAULT 0,
  UNIQUE(language, kind, normalized_form)
);

CREATE INDEX idx_lexical_entries_status
  ON lexical_entries(language, kind, status, normalized_form);

CREATE TABLE lexical_occurrences (
  id TEXT PRIMARY KEY NOT NULL,
  source_key TEXT NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  original_form TEXT NOT NULL,
  sentence_text_snapshot TEXT NOT NULL,
  media_title_snapshot TEXT NOT NULL,
  media_fingerprint_snapshot TEXT NOT NULL,
  start_ms_snapshot INTEGER NOT NULL,
  end_ms_snapshot INTEGER NOT NULL,
  token_start INTEGER,
  token_end INTEGER,
  first_seen_at_ms INTEGER NOT NULL,
  last_seen_at_ms INTEGER NOT NULL,
  encounter_count INTEGER NOT NULL,
  UNIQUE(lexical_entry_id, source_key)
);

CREATE INDEX idx_lexical_occurrences_recent
  ON lexical_occurrences(lexical_entry_id, last_seen_at_ms DESC);

CREATE TABLE lexical_status_history (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  previous_status TEXT,
  new_status TEXT,
  changed_at_ms INTEGER NOT NULL,
  change_source TEXT NOT NULL
);

CREATE TABLE lemma_overrides (
  language TEXT NOT NULL,
  original_normalized TEXT NOT NULL,
  corrected_normalized TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(language, original_normalized)
);

"#;

struct FakeDictionary {
    calls: AtomicUsize,
}

struct FailingDictionary;

struct FakeChineseDictionary {
    calls: AtomicUsize,
}

fn upsert_word_asset(
    services: &AppServices,
    language: &str,
    value: &str,
    display_form: &str,
    status: Option<LearningStatus>,
    source: Option<application::LexicalSourceContext>,
) -> LexicalEntryDetails {
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: language.into(),
            kind: LexicalEntryKind::Word,
            canonical_form: value.into(),
            display_form: display_form.into(),
            status,
            user_definition: None,
            personal_note: None,
            source,
        })
        .unwrap()
}

fn read_word_asset(services: &AppServices, language: &str, value: &str) -> Option<LexicalEntry> {
    services
        .read_lexical_entries_by_forms(language, LexicalEntryKind::Word, &[value.into()])
        .unwrap()
        .into_iter()
        .next()
}

fn table_exists(connection: &Connection, name: &str) -> bool {
    connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?1",
            [name],
            |row| row.get::<_, u32>(0),
        )
        .unwrap()
        > 0
}

fn removed_resource_table_name() -> &'static str {
    concat!("learning", "_", "resources")
}

fn table_column_count(connection: &Connection, table: &str, columns: &[&str]) -> u32 {
    let placeholders = (0..columns.len())
        .map(|_| "?")
        .collect::<Vec<_>>()
        .join(",");
    let sql =
        format!("SELECT COUNT(*) FROM pragma_table_info('{table}') WHERE name IN ({placeholders})");
    connection
        .query_row(
            &sql,
            rusqlite::params_from_iter(columns.iter().copied()),
            |row| row.get::<_, u32>(0),
        )
        .unwrap()
}

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
        metrics_json: serde_json::json!({}).into(),
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

fn chunk_timeline(
    id: &str,
    track: &SubtitleTrack,
    parent: &WordTimeline,
    status: TimelineStatus,
) -> ChunkTimeline {
    ChunkTimeline {
        id: ChunkTimelineId::parse(id).unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        parent_word_timeline_id: Some(parent.id.clone()),
        provider_id: "acoustic-first-rule-partitioner".into(),
        provider_version: "v4".into(),
        algorithm: "acoustic_semantic_v1".into(),
        precision: ChunkTimelinePrecision::Precise,
        created_by: TimelineCreator::Algorithm,
        status,
        metrics_json: serde_json::json!({}).into(),
        chunks: vec![ChunkTimelineChunk {
            id: ChunkId::parse(format!("{id}-chunk-1")).unwrap(),
            sentence_id: track.sentences[0].id.clone(),
            chunk_index: 0,
            start_word_index: 0,
            end_word_index: 0,
            start_ms: 150,
            end_ms: 260,
            text: "hello".into(),
            boundary_sources: vec![ChunkBoundarySource::Pause],
            confidence: 0.9,
            warnings: Vec::new(),
            evidence_json: serde_json::json!({}).into(),
        }],
        created_at_ms: 1,
        updated_at_ms: 1,
    }
}

fn phone_timeline(
    id: &str,
    track: &SubtitleTrack,
    parent: &WordTimeline,
    status: TimelineStatus,
) -> PhoneTimeline {
    PhoneTimeline {
        id: PhoneTimelineId::parse(id).unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        sentence_id: Some(track.sentences[0].id.clone()),
        parent_word_timeline_id: Some(parent.id.clone()),
        parent_phonetic_analysis_id: None,
        provider_id: "research-fixture".into(),
        provider_version: "v1".into(),
        model_id: Some(
            PhoneticAnalysisModelId::parse("research-fixture:deterministic@v1").unwrap(),
        ),
        model_revision: Some("v1".into()),
        phone_set: "research_fixture_symbols".into(),
        precision: PhoneTimelinePrecision::Approximate,
        created_by: TimelineCreator::Algorithm,
        status,
        metrics_json: serde_json::json!({ "synthetic": true }).into(),
        phones: vec![DetectedPhone {
            symbol: "H".into(),
            display_ipa: "H".into(),
            phone_set: "research_fixture_symbols".into(),
            start_ms: 150,
            end_ms: 260,
            confidence: Some(0.5),
            token_index: Some(0),
            provider_id: "research-fixture".into(),
            provider_version: "v1".into(),
            model_revision: "v1".into(),
        }],
        alignments: Vec::new(),
        findings: Vec::new(),
        sound_analysis: None,
        created_at_ms: 1,
        updated_at_ms: 1,
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
            character_breakdowns: vec![],
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

#[async_trait]
impl DictionaryProvider for FakeChineseDictionary {
    fn info(&self) -> DictionaryProviderInfo {
        DictionaryProviderInfo {
            id: "fake-zh".into(),
            display_name: "Fake Chinese".into(),
            supported_languages: vec!["zh".into()],
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
                text: "coffee".into(),
            }],
            phonetics: vec![DictionaryPhonetic {
                text: "kā fēi".into(),
                region: Some("zh".into()),
                audio_url: None,
            }],
            character_breakdowns: vec![],
            provider: self.info().id,
            cached_at_ms: 0,
        }))
    }
}

mod content_fit;
mod l1_diagnosis;
mod learner_profile;
mod learning_loop;
mod lexical;
mod llm_provider;
mod media_library;
mod migrations;
mod phonetic_analysis;
mod semantic_task;
mod subtitles_dictionary;
mod timelines;
mod vocabulary;
