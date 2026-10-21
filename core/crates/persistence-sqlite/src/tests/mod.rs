use super::*;
use application::{
    AppServices, ApplicationError, ContentPackageCandidateImport,
    ContentPackageCandidateImportRepository, DictionaryProvider, DictionaryProviderError,
    ImportSubtitle, LLTimelineResourceRepository, LearningEventRepository,
    LearningObservationRepository, LexicalCapabilityRepository, LexicalEntryRepository,
    ListeningInboxRepository, MediaRepository, PhoneTimelineRepository, PhoneticAnalysisRepository,
    PracticeRepository, ProsodyAnalysisRepository, RecognitionUpgradeRepository, RegisterMedia,
    ReviewQueueRepository, SenseGroupRepository, SubtitleTrackRepository, UpsertLexicalEntry,
    VocabularyAssetRepository, WordTimelineRepository,
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
        .lexical_learning()
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
        .lexical_learning()
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

fn transcription_media() -> MediaItem {
    MediaItem {
        id: MediaId::parse("media-1").unwrap(),
        path: "/tmp/media.mp4".into(),
        fingerprint: "media-fp".into(),
        title: "Media".into(),
        kind: MediaKind::Video,
        duration: Some(TimeMs::new(1_000)),
        availability: MediaAvailability::Available,
        retained_at_ms: None,
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

mod background_jobs;
mod coach_dashboard;
mod content_fit;
mod l1_diagnosis;
mod learner_profile;
mod learning_loop;
mod learning_material;
mod learning_preparation;
mod lexical;
mod llm_provider;
mod media_library;
mod migrations;
mod package_lifecycle;
mod phonetic_analysis;
mod projection_review;
mod semantic_embedding;
mod subtitles_dictionary;
mod timelines;
mod vocabulary;
