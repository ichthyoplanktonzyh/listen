use std::convert::Infallible;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, DictionaryProvider, EnglishPronunciationProvider,
    ImportSubtitle, InMemorySecretStore, RecordSpeakingProduction, RegisterMedia, SecretStore,
    SyntacticAnalysisProvider, SyntacticConsumerOrchestrator, SyntacticProductQualification,
};
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use axum::{Json, Router};
use dictionary_provider::{
    ChineseDictionaryProvider, ChinesePronunciationProvider, EcdictProvider,
    FreeDictionaryProvider, JapaneseDictionaryProvider,
};
use domain::{
    HuntingCandidate, HuntingCandidateStatus, HuntingOccurrenceQueryResult, HuntingTarget,
    HuntingTargetId, HuntingTargetStatus, LanguageCode, LearningStatus, LexicalEntryId,
    ListeningInboxItem, ListeningInboxItemId, ListeningInboxStatus, MediaAvailability, MediaId,
    MediaKind, MediaTriageIntent, PracticeAttempt, PracticeAttemptId, PracticeItem,
    PracticeSession, PracticeSessionId, ReviewItem, ReviewItemId, SubtitleSentenceId,
    SubtitleTrackId, UpgradeSuggestion, UpgradeSuggestionId, UpgradeSuggestionStatus,
    VocabularyAssetBundle,
};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;

mod event_payloads {
    pub use local_runtime::events::*;
}
mod routes;
mod secret_store_keychain;
use local_runtime::{
    CreateJobRequest, CreatePhoneticJobRequest, CreateSoundLineJob, CreateSpeechBatchJob,
    LearningResourceManager, PhoneticAnalysisCoordinator, SoundLineCoordinator,
    SpeechBatchCoordinator, SpeechSynthesisManager, SubtitleSearchCoordinator,
    TranscriptionCoordinator,
};
pub use local_runtime::{SyntaxCapabilityManager, SyntaxCapabilityStatus, SyntaxCapabilityView};
use routes::corpus::{reindex_corpus, search_corpus};
use routes::dictionary::{diagnose_sentence, dictionary_lookup};
use routes::language::{language_profile, list_languages};
use routes::learner::{l1_specialty_occurrences, learner_profile, update_learner_profile};
use routes::llm::{
    delete_llm_provider, generate_rubric_via_llm_provider, get_llm_provider,
    judge_via_llm_provider, list_llm_providers, probe_llm_provider, register_llm_provider,
};
use routes::media::{
    archive_subtitle, cold_start_words, delete_subtitle, export_subtitle, import_lltimeline,
    import_lltimeline_for_media, import_subtitle, list_media_library, media_subtitles, read_media,
    read_subtitle, register_media, restore_subtitle, set_media_triage_intent, track_content_fit,
    update_track_language,
};
use routes::phonetic_analysis::{
    cancel_phonetic_analysis_job, cancel_phonetic_analysis_model_install,
    clear_terminal_phonetic_analysis_jobs, create_phonetic_analysis_job,
    delete_phonetic_analysis_job, delete_phonetic_analysis_model, install_phonetic_analysis_model,
    phonetic_analysis_findings, phonetic_analysis_job, phonetic_analysis_jobs,
    phonetic_analysis_models, phonetic_analysis_providers, register_custom_phonetic_analysis_model,
    retry_phonetic_analysis_job, track_phonetic_analyses, update_phonetic_finding_feedback,
};
use routes::practice::{
    archive_hunting_target, capture_listening_inbox_item, coach_dashboard, coach_evidence,
    compare_shadowing, complete_listening_session, complete_shadowing_attempt,
    confirm_upgrade_suggestion, create_hunting_target, create_practice_item,
    create_practice_session, create_recording_asset, create_review_item, delete_recording_asset,
    graduate_coach_material, list_due_review_items, list_hunting_candidates,
    list_hunting_occurrences, list_hunting_targets, list_listening_inbox_items,
    list_upgrade_suggestions, practice_attempt, process_listening_inbox_item, recording_asset,
    recording_audio_facts, reject_upgrade_suggestion, review_item, submit_hunting_check,
    submit_practice_attempt, submit_review_attempt, upgrade_suggestion_history,
};
use routes::production_corpus::{
    production_gap_review, reindex_production_corpus, search_production_corpus,
};
use routes::pronunciation::{
    analyze_pronunciation_sentence, generate_track_pronunciation, pronunciation_lookup,
    pronunciation_providers, track_pronunciation,
};
use routes::reading::{reading_position, record_reading_marking, save_reading_position};
use routes::realtime_conversation::{
    connect as connect_realtime_conversation, delete_profile as delete_realtime_profile,
    list_profiles as list_realtime_profiles, register_profile as register_realtime_profile,
    save_session as save_realtime_session, save_turn as save_realtime_turn,
};
use routes::semantic::{
    confirm_speaking_target, create_judgment_adjudication, create_semantic_attempt,
    create_semantic_judgment, create_semantic_rubric, create_writing_disposition,
    create_writing_finding, delete_writing_draft, generate_local_writing_findings,
    lookup_semantic_rubric, save_writing_draft, semantic_attempt, semantic_attempt_judgments,
    semantic_judgment_adjudications, semantic_rubric, semantic_rubric_attempts,
    writing_dispositions, writing_draft, writing_findings,
};
use routes::semantic_embedding::{
    capability as semantic_embedding_capability, disable as disable_semantic_embedding,
    enable as enable_semantic_embedding, enrich_gap_review as enrich_production_gap_semantically,
    install as install_semantic_embedding, rebuild as rebuild_semantic_embedding,
    search as semantic_search, uninstall as uninstall_semantic_embedding,
};
use routes::sound_line::{
    cancel_sound_line_job, create_sound_line_job, retry_sound_line_job, sound_line_job,
    sound_line_jobs,
};
use routes::speech::{
    cancel_speech_job, create_speech_job, retry_speech_job, speech_job, speech_jobs,
};
use routes::syntax::{
    cancel_syntax_capability, disable_syntax_capability, enable_syntax_capability,
    install_syntax_capability, run_syntactic_consumers, run_track_syntax_analysis,
    syntax_capability, track_syntax_analysis_status, uninstall_syntax_capability,
    update_syntax_capability, validate_syntax_capability,
};
use routes::timelines::{
    activate_chunk_timeline, activate_phone_timeline, activate_sense_group_analysis,
    activate_word_timeline, archive_chunk_timeline, archive_phone_timeline,
    archive_sense_group_analysis, archive_word_timeline, chunk_providers, chunk_timeline,
    create_track_word_timeline, delete_chunk_timeline, delete_phone_timeline,
    delete_sense_group_analysis, delete_word_timeline, export_chunk_timeline,
    export_phone_timeline, export_track_lltimeline, export_word_timeline, generate_chunk_timeline,
    generate_sense_group_analysis, generate_track_word_timings, phone_timeline,
    publish_word_timeline, sense_group_analysis, track_chunk_diagnostics, track_chunk_partitions,
    track_chunk_timeline_summaries, track_chunk_timelines, track_phone_timeline_summaries,
    track_phone_timelines, track_sense_group_analyses, track_sense_group_analysis_summaries,
    track_word_timeline_summaries, track_word_timelines, track_word_timing_diagnostics,
    track_word_timings, word_timeline,
};
use routes::transcription::{
    archive_transcription_job, cancel_recording_transcription, cancel_transcription_job,
    cancel_transcription_model_install, create_recording_transcription, create_transcription_job,
    delete_transcription_model, install_transcription_model, pronunciation_rules,
    recording_transcription_job, register_custom_transcription_model, retry_transcription_job,
    transcription_job, transcription_jobs, transcription_models, transcription_providers,
};
use routes::tts::{clear_speech_synthesis_cache, speech_synthesis_capability, synthesize_speech};
use routes::vocabulary::{
    assign_sense_folder_occurrence, create_sense_folder, delete_sense_folder, export_vocabulary,
    get_capability_profile, import_external_vocabulary, import_vocabulary, list_vocabulary,
    read_progress, set_capability_override, unassign_sense_folder_occurrence,
    update_media_availability, update_progress, update_sense_folder,
};
pub use secret_store_keychain::KeychainSecretStore;

static ERROR_SEQUENCE: AtomicU64 = AtomicU64::new(1);

#[derive(Clone)]
pub struct ApiState {
    pub services: AppServices,
    pub token: Arc<str>,
    pub events: broadcast::Sender<EventEnvelope>,
    pub dictionaries: Arc<Vec<Arc<dyn DictionaryProvider>>>,
    pub transcription: Arc<TranscriptionCoordinator>,
    pub phonetic_analysis: Arc<PhoneticAnalysisCoordinator>,
    pub speech_jobs: Arc<SpeechBatchCoordinator>,
    /// Provider-neutral local-first TTS. It owns synthesis/cache lifecycle and
    /// deliberately has no learning repository, so playback cannot become
    /// evidence or personal-production data.
    pub speech_synthesis: Arc<SpeechSynthesisManager>,
    pub sound_line: Arc<SoundLineCoordinator>,
    pub learning_resources: Arc<LearningResourceManager>,
    pub subtitle_search: Arc<SubtitleSearchCoordinator>,
    /// Optional Phase 3.9.2 syntax capability. The default has no runtime and
    /// returns the exact B/rule-SenseGroup fallback without touching Python.
    pub syntactic_consumers: Arc<SyntacticConsumerOrchestrator>,
    /// Phase 3.9.3 optional resource lifecycle. This is separate from learning
    /// assets and remains `not_installed` in tests/default composition.
    pub syntax_capability: Arc<SyntaxCapabilityManager>,
    /// Single-flight guard for rebuildable whole-track syntax batches. Cache
    /// lookup is repeated after acquiring it, so concurrent UI/background
    /// triggers cannot duplicate a provider batch.
    pub syntax_analysis_lock: Arc<tokio::sync::Mutex<()>>,
    /// Phase 3.12: resolves provider credentials at dispatch time. Defaults to
    /// an in-memory store; the composition root injects the OS keychain via
    /// [`ApiState::with_secret_store`]. The secret never lives on `services`.
    pub secret_store: Arc<dyn SecretStore>,
    /// Explicit opt-in model lifecycle. It has no learning repositories and
    /// cannot write corpus/evidence/projection facts.
    pub semantic_embedding: Arc<embedding_provider::ManagedFastEmbedProvider>,
}

impl ApiState {
    pub fn new<R>(services: AppServices, repository: Arc<R>, token: impl Into<Arc<str>>) -> Self
    where
        R: application::TranscriptionRepository + application::PhoneticAnalysisRepository + 'static,
    {
        let (events, _) = broadcast::channel(128);
        let ecdict = Arc::new(EcdictProvider::new());
        let services = services
            .with_lexical_normalizers(vec![ecdict.clone()])
            .with_pronunciation_providers(vec![
                Arc::new(EnglishPronunciationProvider),
                Arc::new(ChinesePronunciationProvider::new()),
            ]);
        let transcription = Arc::new(
            TranscriptionCoordinator::new(services.clone(), repository.clone(), events.clone())
                .expect("transcription coordinator must initialize"),
        );
        #[cfg(test)]
        let phonetic_analysis = Arc::new(
            PhoneticAnalysisCoordinator::new_with_test_provider(
                services.clone(),
                repository,
                events.clone(),
            )
            .expect("phonetic analysis coordinator must initialize"),
        );
        #[cfg(not(test))]
        let phonetic_analysis = Arc::new(
            PhoneticAnalysisCoordinator::new(services.clone(), repository, events.clone())
                .expect("phonetic analysis coordinator must initialize"),
        );
        let speech_jobs = Arc::new(SpeechBatchCoordinator::new(
            services.clone(),
            events.clone(),
        ));
        let sound_line = SoundLineCoordinator::new(services.clone(), events.clone());
        Self {
            services,
            token: token.into(),
            events,
            dictionaries: Arc::new(vec![
                ecdict,
                Arc::new(ChineseDictionaryProvider::new()),
                Arc::new(JapaneseDictionaryProvider::new()),
                Arc::new(
                    FreeDictionaryProvider::new().expect("dictionary HTTP client must initialize"),
                ),
            ]),
            transcription,
            phonetic_analysis,
            speech_jobs,
            speech_synthesis: SpeechSynthesisManager::new(
                std::env::temp_dir().join(format!("llplayer-tts-unmanaged-{}", std::process::id())),
                Vec::new(),
            ),
            sound_line,
            learning_resources: Arc::new(LearningResourceManager::new()),
            subtitle_search: Arc::new(SubtitleSearchCoordinator::new()),
            syntactic_consumers: Arc::new(SyntacticConsumerOrchestrator::new(
                None,
                SyntacticProductQualification::corrected_v2(),
            )),
            syntax_capability: SyntaxCapabilityManager::unmanaged(),
            syntax_analysis_lock: Arc::new(tokio::sync::Mutex::new(())),
            secret_store: Arc::new(InMemorySecretStore::new()),
            semantic_embedding: Arc::new(embedding_provider::ManagedFastEmbedProvider::new(
                std::env::temp_dir().join(format!(
                    "llplayer-embedding-unmanaged-{}",
                    std::process::id()
                )),
            )),
        }
    }

    /// Injects the platform secret store (OS keychain in production).
    pub fn with_secret_store(mut self, secret_store: Arc<dyn SecretStore>) -> Self {
        self.secret_store = secret_store;
        self
    }

    pub fn with_syntactic_provider(mut self, provider: Arc<dyn SyntacticAnalysisProvider>) -> Self {
        self.syntactic_consumers = Arc::new(SyntacticConsumerOrchestrator::new(
            Some(provider),
            SyntacticProductQualification::corrected_v2(),
        ));
        self
    }

    pub fn with_syntax_capability(
        mut self,
        manager: Arc<SyntaxCapabilityManager>,
        provider: Arc<dyn SyntacticAnalysisProvider>,
    ) -> Self {
        self.syntax_capability = manager;
        self.syntactic_consumers = Arc::new(SyntacticConsumerOrchestrator::new(
            Some(provider),
            SyntacticProductQualification::corrected_v2(),
        ));
        self
    }

    pub fn with_speech_synthesis(mut self, manager: Arc<SpeechSynthesisManager>) -> Self {
        self.speech_synthesis = manager;
        self
    }

    pub fn with_semantic_embedding_manager(
        mut self,
        manager: Arc<embedding_provider::ManagedFastEmbedProvider>,
    ) -> Self {
        self.semantic_embedding = manager;
        self
    }
}

pub fn router(state: ApiState) -> Router {
    let protected = Router::new()
        .route("/v1/media", post(register_media).get(list_media_library))
        .route(
            "/v1/media/{media_id}/triage-intent",
            put(set_media_triage_intent),
        )
        .route("/v1/lltimeline/import", post(import_lltimeline))
        .route("/v1/media/{media_id}", get(read_media))
        .route(
            "/v1/media/{media_id}/lltimeline/import",
            post(import_lltimeline_for_media),
        )
        .route(
            "/v1/media/{media_id}/subtitles",
            get(media_subtitles).post(import_subtitle),
        )
        .route(
            "/v1/subtitles/{track_id}",
            get(read_subtitle).delete(delete_subtitle),
        )
        .route("/v1/subtitles/{track_id}/archive", post(archive_subtitle))
        .route("/v1/subtitles/{track_id}/restore", post(restore_subtitle))
        .route(
            "/v1/subtitles/{track_id}/language",
            axum::routing::patch(update_track_language),
        )
        .route("/v1/subtitles/{track_id}/export", get(export_subtitle))
        .route(
            "/v1/subtitles/{track_id}/content-fit",
            get(track_content_fit),
        )
        .route(
            "/v1/subtitles/{track_id}/cold-start-words",
            get(cold_start_words),
        )
        .route("/v1/pronunciation/providers", get(pronunciation_providers))
        .route("/v1/pronunciation/lookup", get(pronunciation_lookup))
        .route(
            "/v1/speech-synthesis/capability",
            get(speech_synthesis_capability),
        )
        .route("/v1/speech-synthesis", post(synthesize_speech))
        .route(
            "/v1/speech-synthesis/cache",
            delete(clear_speech_synthesis_cache),
        )
        .route(
            "/v1/pronunciation/analyze-sentence",
            post(analyze_pronunciation_sentence),
        )
        .route("/v1/pronunciation/rules", get(pronunciation_rules))
        .route(
            "/v1/subtitles/{track_id}/pronunciation",
            get(track_pronunciation),
        )
        .route(
            "/v1/subtitles/{track_id}/pronunciation-analysis",
            post(generate_track_pronunciation),
        )
        .route(
            "/v1/subtitles/{track_id}/word-timings",
            get(track_word_timings).post(generate_track_word_timings),
        )
        .route(
            "/v1/subtitles/{track_id}/word-timelines",
            get(track_word_timelines).post(create_track_word_timeline),
        )
        .route(
            "/v1/subtitles/{track_id}/word-timelines/summary",
            get(track_word_timeline_summaries),
        )
        .route(
            "/v1/subtitles/{track_id}/lltimeline/export",
            get(export_track_lltimeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}",
            get(word_timeline).delete(delete_word_timeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}/activate",
            post(activate_word_timeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}/publish",
            post(publish_word_timeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}/archive",
            post(archive_word_timeline),
        )
        .route(
            "/v1/word-timelines/{timeline_id}/export",
            get(export_word_timeline),
        )
        .route(
            "/v1/subtitles/{track_id}/word-timing-diagnostics",
            get(track_word_timing_diagnostics),
        )
        .route(
            "/v1/subtitles/{track_id}/chunk-partitions",
            get(track_chunk_partitions),
        )
        .route(
            "/v1/subtitles/{track_id}/chunk-diagnostics",
            get(track_chunk_diagnostics),
        )
        .route("/v1/chunk/providers", get(chunk_providers))
        .route(
            "/v1/subtitles/{track_id}/chunk-timelines",
            get(track_chunk_timelines).post(generate_chunk_timeline),
        )
        .route(
            "/v1/subtitles/{track_id}/chunk-timelines/summary",
            get(track_chunk_timeline_summaries),
        )
        .route(
            "/v1/chunk-timelines/{timeline_id}",
            get(chunk_timeline).delete(delete_chunk_timeline),
        )
        .route(
            "/v1/chunk-timelines/{timeline_id}/activate",
            post(activate_chunk_timeline),
        )
        .route(
            "/v1/chunk-timelines/{timeline_id}/archive",
            post(archive_chunk_timeline),
        )
        .route(
            "/v1/chunk-timelines/{timeline_id}/export",
            get(export_chunk_timeline),
        )
        .route(
            "/v1/subtitles/{track_id}/sense-group-analyses",
            get(track_sense_group_analyses).post(generate_sense_group_analysis),
        )
        .route(
            "/v1/subtitles/{track_id}/syntactic-consumers",
            post(run_syntactic_consumers),
        )
        .route(
            "/v1/subtitles/{track_id}/syntax-analysis",
            get(track_syntax_analysis_status).post(run_track_syntax_analysis),
        )
        .route("/v1/syntax/capability", get(syntax_capability))
        .route(
            "/v1/syntax/capability/install",
            post(install_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/cancel",
            post(cancel_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/validate",
            post(validate_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/enable",
            post(enable_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/disable",
            post(disable_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/uninstall",
            post(uninstall_syntax_capability),
        )
        .route(
            "/v1/syntax/capability/update",
            post(update_syntax_capability),
        )
        .route(
            "/v1/subtitles/{track_id}/sense-group-analyses/summary",
            get(track_sense_group_analysis_summaries),
        )
        .route(
            "/v1/sense-group-analyses/{analysis_id}",
            get(sense_group_analysis).delete(delete_sense_group_analysis),
        )
        .route(
            "/v1/sense-group-analyses/{analysis_id}/activate",
            post(activate_sense_group_analysis),
        )
        .route(
            "/v1/sense-group-analyses/{analysis_id}/archive",
            post(archive_sense_group_analysis),
        )
        .route(
            "/v1/subtitles/{track_id}/phone-timelines",
            get(track_phone_timelines),
        )
        .route(
            "/v1/subtitles/{track_id}/phone-timelines/summary",
            get(track_phone_timeline_summaries),
        )
        .route(
            "/v1/phone-timelines/{timeline_id}",
            get(phone_timeline).delete(delete_phone_timeline),
        )
        .route(
            "/v1/phone-timelines/{timeline_id}/activate",
            post(activate_phone_timeline),
        )
        .route(
            "/v1/phone-timelines/{timeline_id}/archive",
            post(archive_phone_timeline),
        )
        .route(
            "/v1/phone-timelines/{timeline_id}/export",
            get(export_phone_timeline),
        )
        .route("/v1/speech/jobs", get(speech_jobs).post(create_speech_job))
        .route("/v1/speech/jobs/{job_id}", get(speech_job))
        .route("/v1/speech/jobs/{job_id}/cancel", post(cancel_speech_job))
        .route("/v1/speech/jobs/{job_id}/retry", post(retry_speech_job))
        .route(
            "/v1/sound-line/jobs",
            get(sound_line_jobs).post(create_sound_line_job),
        )
        .route("/v1/sound-line/jobs/{job_id}", get(sound_line_job))
        .route(
            "/v1/sound-line/jobs/{job_id}/cancel",
            post(cancel_sound_line_job),
        )
        .route(
            "/v1/sound-line/jobs/{job_id}/retry",
            post(retry_sound_line_job),
        )
        .route(
            "/v1/media/{media_id}/progress",
            get(read_progress).put(update_progress),
        )
        .route(
            "/v1/lexical-entries/batch",
            post(routes::lexical_entries::read_lexical_entries),
        )
        .route(
            "/v1/lexical-entries",
            get(routes::lexical_entries::list_lexical_entries)
                .put(routes::lexical_entries::upsert_lexical_entry),
        )
        .route(
            "/v1/lexical-entries/{id}",
            get(routes::lexical_entries::lexical_details),
        )
        .route(
            "/v1/lexical-entries/{id}/capability-profile",
            get(get_capability_profile),
        )
        .route(
            "/v1/lexical-entries/{id}/capability/{capability}",
            put(set_capability_override),
        )
        .route(
            "/v1/lexical-entries/{id}/learning-content",
            put(routes::lexical_entries::update_lexical_learning_content),
        )
        .route(
            "/v1/lexical-entries/{entry_id}/sense-folders",
            post(create_sense_folder),
        )
        .route(
            "/v1/lexical-entries/{entry_id}/sense-folders/{sense_id}",
            put(update_sense_folder).delete(delete_sense_folder),
        )
        .route(
            "/v1/lexical-entries/{entry_id}/sense-folders/{sense_id}/occurrences/{occurrence_id}",
            put(assign_sense_folder_occurrence).delete(unassign_sense_folder_occurrence),
        )
        .route(
            "/v1/lexical-observations",
            post(routes::lexical_entries::create_lexical_observation),
        )
        .route(
            "/v1/lexical-normalization",
            post(routes::lexical_entries::normalize_lexical),
        )
        .route(
            "/v1/lexical-normalization/correct",
            post(routes::lexical_entries::correct_lemma),
        )
        .route(
            "/v1/sentences/{sentence_id}/phrase-candidates",
            get(routes::lexical_entries::phrase_candidates),
        )
        .route("/v1/practice/sessions", post(create_practice_session))
        .route("/v1/coach/dashboard", get(coach_dashboard))
        .route("/v1/coach/evidence", get(coach_evidence))
        .route(
            "/v1/coach/materials/{media_id}/graduate",
            post(graduate_coach_material),
        )
        .route(
            "/v1/listening/sessions/{id}/complete",
            post(complete_listening_session),
        )
        .route("/v1/practice/items", post(create_practice_item))
        .route("/v1/practice/attempts", post(submit_practice_attempt))
        .route("/v1/practice/attempts/{id}", get(practice_attempt))
        .route(
            "/v1/practice/shadowing-attempts",
            post(complete_shadowing_attempt),
        )
        .route("/v1/shadowing/comparisons", post(compare_shadowing))
        .route("/v1/recordings", post(create_recording_asset))
        .route(
            "/v1/recordings/{id}",
            get(recording_asset).delete(delete_recording_asset),
        )
        .route(
            "/v1/recordings/{id}/audio-facts",
            get(recording_audio_facts),
        )
        .route(
            "/v1/recording-transcriptions",
            post(create_recording_transcription),
        )
        .route(
            "/v1/recording-transcriptions/{job_id}",
            get(recording_transcription_job),
        )
        .route(
            "/v1/recording-transcriptions/{job_id}/cancel",
            post(cancel_recording_transcription),
        )
        .route(
            "/v1/listening-inbox/items",
            get(list_listening_inbox_items).post(capture_listening_inbox_item),
        )
        .route(
            "/v1/listening-inbox/items/{id}/process",
            post(process_listening_inbox_item),
        )
        .route("/v1/hunting/candidates", get(list_hunting_candidates))
        .route(
            "/v1/hunting/targets",
            get(list_hunting_targets).post(create_hunting_target),
        )
        .route("/v1/hunting/targets/{id}", delete(archive_hunting_target))
        .route("/v1/hunting/occurrences", get(list_hunting_occurrences))
        .route("/v1/hunting/checks", post(submit_hunting_check))
        .route(
            "/v1/review/items",
            get(list_due_review_items).post(create_review_item),
        )
        .route("/v1/review/items/{id}", get(review_item))
        .route("/v1/review/attempts", post(submit_review_attempt))
        .route(
            "/v1/review/upgrade-suggestions",
            get(list_upgrade_suggestions),
        )
        .route(
            "/v1/review/upgrade-suggestions/history",
            get(upgrade_suggestion_history),
        )
        .route(
            "/v1/review/upgrade-suggestions/{id}/confirm",
            post(confirm_upgrade_suggestion),
        )
        .route(
            "/v1/review/upgrade-suggestions/{id}/reject",
            post(reject_upgrade_suggestion),
        )
        .route(
            "/v1/learning-resources",
            get(routes::learning_resources::list),
        )
        .route(
            "/v1/learning-resources/{id}/install",
            post(routes::learning_resources::install),
        )
        .route(
            "/v1/learning-resources/{id}",
            axum::routing::delete(routes::learning_resources::remove),
        )
        .route("/v1/subtitle-search", post(routes::subtitle_search::search))
        .route(
            "/v1/subtitle-search/download",
            post(routes::subtitle_search::download),
        )
        .route("/v1/vocabulary", get(list_vocabulary))
        .route("/v1/corpus/search", get(search_corpus))
        .route("/v1/corpus/reindex", post(reindex_corpus))
        .route(
            "/v1/production-corpus/search",
            get(search_production_corpus),
        )
        .route(
            "/v1/production-corpus/reindex",
            post(reindex_production_corpus),
        )
        .route("/v1/production-gap/review", get(production_gap_review))
        .route(
            "/v1/semantic-embedding/capability",
            get(semantic_embedding_capability),
        )
        .route(
            "/v1/semantic-embedding/install",
            post(install_semantic_embedding),
        )
        .route(
            "/v1/semantic-embedding/enable",
            post(enable_semantic_embedding),
        )
        .route(
            "/v1/semantic-embedding/disable",
            post(disable_semantic_embedding),
        )
        .route(
            "/v1/semantic-embedding",
            delete(uninstall_semantic_embedding),
        )
        .route(
            "/v1/semantic-embedding/reindex",
            post(rebuild_semantic_embedding),
        )
        .route("/v1/semantic-search", get(semantic_search))
        .route(
            "/v1/production-gap/semantic-enrichment",
            get(enrich_production_gap_semantically),
        )
        .route("/v1/vocabulary/export", get(export_vocabulary))
        .route("/v1/vocabulary/import", post(import_vocabulary))
        .route(
            "/v1/vocabulary/import-external",
            post(import_external_vocabulary),
        )
        .route(
            "/v1/media/{media_id}/availability",
            axum::routing::put(update_media_availability),
        )
        .route("/v1/events", get(events))
        .route("/v1/dictionary", get(dictionary_lookup))
        .route(
            "/v1/learner/profile",
            get(learner_profile).put(update_learner_profile),
        )
        .route("/v1/learner/l1-specialty", get(l1_specialty_occurrences))
        .route(
            "/v1/reading/positions/{track_id}",
            get(reading_position).put(save_reading_position),
        )
        .route("/v1/reading/markings", post(record_reading_marking))
        .route("/v1/semantic/rubrics", post(create_semantic_rubric))
        .route("/v1/semantic/rubrics/lookup", get(lookup_semantic_rubric))
        .route("/v1/semantic/rubrics/{id}", get(semantic_rubric))
        .route(
            "/v1/semantic/rubrics/{id}/attempts",
            get(semantic_rubric_attempts),
        )
        .route("/v1/semantic/attempts", post(create_semantic_attempt))
        .route(
            "/v1/semantic/writing-drafts/{id}",
            get(writing_draft)
                .put(save_writing_draft)
                .delete(delete_writing_draft),
        )
        .route("/v1/semantic/attempts/{id}", get(semantic_attempt))
        .route(
            "/v1/semantic/attempts/{id}/writing-findings",
            get(writing_findings).post(create_writing_finding),
        )
        .route(
            "/v1/semantic/attempts/{id}/writing-findings/local",
            post(generate_local_writing_findings),
        )
        .route(
            "/v1/semantic/attempts/{id}/speaking-targets",
            post(confirm_speaking_target),
        )
        .route(
            "/v1/semantic/attempts/{id}/judgments",
            get(semantic_attempt_judgments),
        )
        .route("/v1/semantic/judgments", post(create_semantic_judgment))
        .route(
            "/v1/semantic/judgments/{id}/adjudications",
            get(semantic_judgment_adjudications),
        )
        .route(
            "/v1/semantic/adjudications",
            post(create_judgment_adjudication),
        )
        .route(
            "/v1/semantic/writing-findings/{id}/dispositions",
            get(writing_dispositions).post(create_writing_disposition),
        )
        .route(
            "/v1/llm/providers",
            get(list_llm_providers).post(register_llm_provider),
        )
        .route(
            "/v1/llm/providers/{id}",
            get(get_llm_provider).delete(delete_llm_provider),
        )
        .route("/v1/llm/providers/{id}/probe", post(probe_llm_provider))
        .route(
            "/v1/realtime/providers",
            get(list_realtime_profiles).post(register_realtime_profile),
        )
        .route(
            "/v1/realtime/providers/{id}",
            delete(delete_realtime_profile),
        )
        .route(
            "/v1/realtime/conversations/ws",
            get(connect_realtime_conversation),
        )
        .route("/v1/realtime/sessions", post(save_realtime_session))
        .route("/v1/realtime/turns", post(save_realtime_turn))
        .route("/v1/llm/providers/{id}/judge", post(judge_via_llm_provider))
        .route(
            "/v1/llm/providers/{id}/rubric",
            post(generate_rubric_via_llm_provider),
        )
        .route("/v1/languages", get(list_languages))
        .route("/v1/languages/{code}/profile", get(language_profile))
        .route("/v1/transcription/providers", get(transcription_providers))
        .route("/v1/transcription/models", get(transcription_models))
        .route(
            "/v1/transcription/models/install",
            post(install_transcription_model),
        )
        .route(
            "/v1/transcription/models/register-custom",
            post(register_custom_transcription_model),
        )
        .route(
            "/v1/transcription/models/{model_id}/cancel-install",
            post(cancel_transcription_model_install),
        )
        .route(
            "/v1/transcription/models/{model_id}",
            axum::routing::delete(delete_transcription_model),
        )
        .route(
            "/v1/transcription/jobs",
            get(transcription_jobs).post(create_transcription_job),
        )
        .route("/v1/transcription/jobs/{job_id}", get(transcription_job))
        .route(
            "/v1/transcription/jobs/{job_id}/cancel",
            post(cancel_transcription_job),
        )
        .route(
            "/v1/transcription/jobs/{job_id}/retry",
            post(retry_transcription_job),
        )
        .route(
            "/v1/transcription/jobs/{job_id}/archive",
            post(archive_transcription_job),
        )
        .route(
            "/v1/phonetic-analysis/providers",
            get(phonetic_analysis_providers),
        )
        .route(
            "/v1/phonetic-analysis/models",
            get(phonetic_analysis_models),
        )
        .route(
            "/v1/phonetic-analysis/models/install",
            post(install_phonetic_analysis_model),
        )
        .route(
            "/v1/phonetic-analysis/models/register-custom",
            post(register_custom_phonetic_analysis_model),
        )
        .route(
            "/v1/phonetic-analysis/models/{model_id}/cancel-install",
            post(cancel_phonetic_analysis_model_install),
        )
        .route(
            "/v1/phonetic-analysis/models/{model_id}",
            delete(delete_phonetic_analysis_model),
        )
        .route(
            "/v1/phonetic-analysis/jobs",
            get(phonetic_analysis_jobs).post(create_phonetic_analysis_job),
        )
        .route(
            "/v1/phonetic-analysis/jobs/clear",
            post(clear_terminal_phonetic_analysis_jobs),
        )
        .route(
            "/v1/phonetic-analysis/jobs/{job_id}",
            get(phonetic_analysis_job).delete(delete_phonetic_analysis_job),
        )
        .route(
            "/v1/phonetic-analysis/jobs/{job_id}/cancel",
            post(cancel_phonetic_analysis_job),
        )
        .route(
            "/v1/phonetic-analysis/jobs/{job_id}/retry",
            post(retry_phonetic_analysis_job),
        )
        .route(
            "/v1/subtitles/{track_id}/phonetic-analyses",
            get(track_phonetic_analyses),
        )
        .route(
            "/v1/phonetic-analysis/{analysis_id}/findings",
            get(phonetic_analysis_findings),
        )
        .route(
            "/v1/phonetic-analysis/findings/{finding_id}/feedback",
            put(update_phonetic_finding_feedback),
        )
        .route(
            "/v1/sentences/{sentence_id}/diagnosis",
            get(diagnose_sentence),
        )
        .route_layer(middleware::from_fn_with_state(state.clone(), authorize));

    Router::new()
        .route("/v1/health", get(health))
        .merge(protected)
        .with_state(state)
}

async fn events(
    State(state): State<ApiState>,
) -> Sse<impl futures_core::Stream<Item = Result<Event, Infallible>>> {
    let mut receiver = state.events.subscribe();
    let stream = async_stream::stream! {
        while let Ok(envelope) = receiver.recv().await {
            yield Ok(Event::default().json_data(envelope).expect("event envelope serializes"));
        }
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

async fn authorize(
    State(state): State<ApiState>,
    headers: HeaderMap,
    request: Request<Body>,
    next: Next,
) -> Result<Response, ApiError> {
    let expected = format!("Bearer {}", state.token);
    if headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v == expected)
    {
        Ok(next.run(request).await)
    } else {
        Err(ApiError::unauthorized())
    }
}

#[derive(Serialize)]
struct Health {
    status: &'static str,
    api_version: u16,
}

async fn health() -> Json<Health> {
    Json(Health {
        status: "ok",
        api_version: 1,
    })
}

#[derive(Debug, Serialize)]
pub struct ErrorBody {
    pub code: &'static str,
    pub message: String,
    pub correlation_id: String,
    pub retryable: bool,
}

#[derive(Debug)]
pub struct ApiError {
    status: StatusCode,
    body: ErrorBody,
}

impl ApiError {
    pub(crate) fn new(
        status: StatusCode,
        code: &'static str,
        message: impl Into<String>,
        retryable: bool,
    ) -> Self {
        Self {
            status,
            body: ErrorBody {
                code,
                message: message.into(),
                correlation_id: format!("api-{}", ERROR_SEQUENCE.fetch_add(1, Ordering::Relaxed)),
                retryable,
            },
        }
    }

    fn unauthorized() -> Self {
        Self::new(
            StatusCode::UNAUTHORIZED,
            "unauthorized",
            "invalid local API token",
            false,
        )
    }

    pub(crate) fn not_found(entity: &'static str) -> Self {
        Self::new(
            StatusCode::NOT_FOUND,
            "not_found",
            format!("{entity} was not found"),
            false,
        )
    }

    pub(crate) fn gateway(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_GATEWAY, code, message, true)
    }
}

impl From<ApplicationError> for ApiError {
    fn from(value: ApplicationError) -> Self {
        match value {
            ApplicationError::NotFound(entity) => Self::not_found(entity),
            ApplicationError::Validation(field) => Self::new(
                StatusCode::BAD_REQUEST,
                "validation_error",
                format!("{field} must not be empty"),
                false,
            ),
            ApplicationError::Invalid(message) => {
                Self::new(StatusCode::BAD_REQUEST, "invalid_input", message, false)
            }
            ApplicationError::Domain(error) => Self::new(
                StatusCode::BAD_REQUEST,
                "domain_error",
                error.to_string(),
                false,
            ),
            ApplicationError::Repository(error) => Self::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "repository_error",
                error,
                true,
            ),
            ApplicationError::Subtitle(error) => Self::new(
                StatusCode::BAD_REQUEST,
                "subtitle_parse_error",
                error.to_string(),
                false,
            ),
            ApplicationError::DictionaryProvider(error) => Self::new(
                StatusCode::BAD_GATEWAY,
                "dictionary_provider_error",
                error.to_string(),
                true,
            ),
            ApplicationError::LexicalNormalizationProvider(error) => Self::new(
                StatusCode::BAD_GATEWAY,
                "lexical_normalization_provider_error",
                error.to_string(),
                true,
            ),
            ApplicationError::Conflict(message) => {
                Self::new(StatusCode::CONFLICT, "asset_conflict", message, false)
            }
            ApplicationError::ExternalProcess(message) => Self::new(
                StatusCode::BAD_GATEWAY,
                "external_process_error",
                message,
                true,
            ),
            // Phase 3.12: the standardized provider taxonomy. `to_string()` is
            // secret-free by construction (auth carries no payload), so this
            // never echoes a credential to the client.
            ApplicationError::Provider(error) => {
                use domain::LlmProviderError as E;
                let (status, retryable) = match &error {
                    E::RateLimit { .. } => (StatusCode::TOO_MANY_REQUESTS, true),
                    E::Timeout => (StatusCode::GATEWAY_TIMEOUT, true),
                    E::Offline => (StatusCode::BAD_GATEWAY, true),
                    E::UnsupportedCapability { .. } => (StatusCode::BAD_REQUEST, false),
                    _ => (StatusCode::BAD_GATEWAY, false),
                };
                Self::new(status, "llm_provider_error", error.to_string(), retryable)
            }
            ApplicationError::SecretStore(error) => Self::new(
                StatusCode::INTERNAL_SERVER_ERROR,
                "secret_store_error",
                error.to_string(),
                true,
            ),
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        eprintln!(
            "{}",
            serde_json::json!({
                "event": "api.error",
                "status": self.status.as_u16(),
                "code": self.body.code,
                "message": self.body.message,
                "correlation_id": self.body.correlation_id,
                "retryable": self.body.retryable,
            })
        );
        (self.status, Json(self.body)).into_response()
    }
}

#[cfg(test)]
mod tests;
