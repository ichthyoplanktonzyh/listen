use std::convert::Infallible;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, DictionaryProvider, EnglishPronunciationProvider,
    ImportSubtitle, RegisterMedia,
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

mod event_payloads;
mod m18;
mod phonetic_analysis;
mod routes;
mod sound_line;
mod speech_jobs;
mod transcription;
use m18::M18Coordinator;
use phonetic_analysis::{CreatePhoneticJobRequest, PhoneticAnalysisCoordinator};
use routes::corpus::*;
use routes::dictionary::*;
use routes::language::*;
use routes::media::*;
use routes::phonetic_analysis::*;
use routes::practice::*;
use routes::pronunciation::*;
use routes::sound_line::*;
use routes::speech::*;
use routes::timelines::*;
use routes::transcription::*;
use routes::vocabulary::*;
use sound_line::{CreateSoundLineJob, SoundLineCoordinator};
use speech_jobs::{CreateSpeechBatchJob, SpeechBatchCoordinator};
use transcription::{CreateJobRequest, TranscriptionCoordinator};

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
    pub sound_line: Arc<SoundLineCoordinator>,
    pub m18: Arc<M18Coordinator>,
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
            sound_line,
            m18: Arc::new(M18Coordinator::new()),
        }
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
        .route("/v1/lexical-entries/batch", post(m18::read_lexical_entries))
        .route(
            "/v1/lexical-entries",
            get(m18::list_lexical_entries).put(m18::upsert_lexical_entry),
        )
        .route("/v1/lexical-entries/{id}", get(m18::lexical_details))
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
            put(m18::update_lexical_learning_content),
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
            post(m18::create_lexical_observation),
        )
        .route("/v1/lexical-normalization", post(m18::normalize_lexical))
        .route(
            "/v1/lexical-normalization/correct",
            post(m18::correct_lemma),
        )
        .route(
            "/v1/sentences/{sentence_id}/phrase-candidates",
            get(m18::phrase_candidates),
        )
        .route("/v1/practice/sessions", post(create_practice_session))
        .route(
            "/v1/listening/sessions/{id}/complete",
            post(complete_listening_session),
        )
        .route("/v1/practice/items", post(create_practice_item))
        .route("/v1/practice/attempts", post(submit_practice_attempt))
        .route("/v1/practice/attempts/{id}", get(practice_attempt))
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
        .route("/v1/learning-resources", get(m18::resources))
        .route(
            "/v1/learning-resources/{id}/install",
            post(m18::install_resource),
        )
        .route(
            "/v1/learning-resources/{id}",
            axum::routing::delete(m18::remove_resource),
        )
        .route("/v1/subtitle-search", post(m18::search_subtitles))
        .route("/v1/subtitle-search/download", post(m18::download_subtitle))
        .route("/v1/vocabulary", get(list_vocabulary))
        .route("/v1/corpus/search", get(search_corpus))
        .route("/v1/corpus/reindex", post(reindex_corpus))
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
