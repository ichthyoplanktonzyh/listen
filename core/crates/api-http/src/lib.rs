use std::convert::Infallible;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use api_events::{EventEnvelope, EventName};
use application::{
    AppServices, ApplicationError, CreateWordObservation, DictionaryProvider, ImportSubtitle,
    RegisterMedia, SourceContext, UpdateWordProfile,
};
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, Request, StatusCode};
use axum::middleware::{self, Next};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use axum::{Json, Router};
use dictionary_provider::{EcdictProvider, FreeDictionaryProvider};
use domain::{
    LanguageCode, MediaAvailability, MediaId, MediaKind, ObservationResult, SubtitleSentenceId,
    SubtitleTrackId, VocabularyAssetBundle, WordProfileId, WordStatus,
};
use serde::{Deserialize, Serialize};
use tokio::sync::broadcast;

mod m18;
mod phonetic_analysis;
mod speech_jobs;
mod transcription;
use m18::M18Coordinator;
use phonetic_analysis::{CreatePhoneticJobRequest, PhoneticAnalysisCoordinator};
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
    pub m18: Arc<M18Coordinator>,
}

impl ApiState {
    pub fn new<R>(services: AppServices, repository: Arc<R>, token: impl Into<Arc<str>>) -> Self
    where
        R: application::TranscriptionRepository + application::PhoneticAnalysisRepository + 'static,
    {
        let (events, _) = broadcast::channel(128);
        let ecdict = Arc::new(EcdictProvider::new());
        let services = services.with_lexical_normalizers(vec![ecdict.clone()]);
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
        Self {
            services,
            token: token.into(),
            events,
            dictionaries: Arc::new(vec![
                ecdict,
                Arc::new(
                    FreeDictionaryProvider::new().expect("dictionary HTTP client must initialize"),
                ),
            ]),
            transcription,
            phonetic_analysis,
            speech_jobs,
            m18: Arc::new(M18Coordinator::new()),
        }
    }
}

pub fn router(state: ApiState) -> Router {
    let protected = Router::new()
        .route("/v1/media", post(register_media))
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
        .route("/v1/subtitles/{track_id}", get(read_subtitle))
        .route("/v1/subtitles/{track_id}/export", get(export_subtitle))
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
        .route("/v1/speech/jobs", get(speech_jobs).post(create_speech_job))
        .route("/v1/speech/jobs/{job_id}", get(speech_job))
        .route("/v1/speech/jobs/{job_id}/cancel", post(cancel_speech_job))
        .route("/v1/speech/jobs/{job_id}/retry", post(retry_speech_job))
        .route("/v1/word-profiles/batch", post(read_words))
        .route(
            "/v1/media/{media_id}/progress",
            get(read_progress).put(update_progress),
        )
        .route("/v1/word-profiles", get(read_word).put(update_word))
        .route("/v1/word-observations", post(create_observation))
        .route(
            "/v1/lexical-entries",
            get(m18::list_lexical_entries).put(m18::upsert_lexical_entry),
        )
        .route("/v1/lexical-entries/{id}", get(m18::lexical_details))
        .route("/v1/lexical-normalization", post(m18::normalize_lexical))
        .route(
            "/v1/lexical-normalization/correct",
            post(m18::correct_lemma),
        )
        .route(
            "/v1/sentences/{sentence_id}/phrase-candidates",
            get(m18::phrase_candidates),
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
        .route("/v1/vocabulary/export", get(export_vocabulary))
        .route("/v1/vocabulary/import", post(import_vocabulary))
        .route("/v1/word-profiles/{profile_id}/details", get(word_details))
        .route(
            "/v1/word-profiles/{profile_id}/learning-content",
            put(update_learning_content),
        )
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
            "/v1/phonetic-analysis/jobs/{job_id}",
            get(phonetic_analysis_job),
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

#[derive(Debug, Deserialize)]
struct RegisterMediaRequest {
    path: String,
    fingerprint: String,
    title: String,
    kind: MediaKind,
    duration_ms: Option<u64>,
}

async fn register_media(
    State(state): State<ApiState>,
    Json(request): Json<RegisterMediaRequest>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    state
        .services
        .register_media(RegisterMedia {
            path: request.path,
            fingerprint: request.fingerprint,
            title: request.title,
            kind: request.kind,
            duration_ms: request.duration_ms,
        })
        .map(Json)
        .map_err(ApiError::from)
}

async fn read_media(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .services
        .read_media(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("media"))
}

#[derive(Debug, Deserialize)]
struct ImportSubtitleRequest {
    path: String,
    language: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ImportLLTimelineForMediaQuery {
    allow_mismatch: Option<bool>,
}

async fn import_subtitle(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<ImportSubtitleRequest>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    let content = tokio::fs::read(&request.path).await.map_err(|error| {
        ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_read_error",
            error.to_string(),
            false,
        )
    })?;
    let source_name = std::path::Path::new(&request.path)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(&request.path)
        .to_owned();
    state
        .services
        .import_subtitle(ImportSubtitle {
            media_id,
            source_name,
            content,
            language: request.language,
            identity_salt: None,
        })
        .map(Json)
        .map_err(ApiError::from)
}

async fn import_lltimeline(
    State(state): State<ApiState>,
    Json(document): Json<domain::LLTimelineDocument>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    state
        .services
        .import_lltimeline_document(document)
        .map(Json)
        .map_err(ApiError::from)
}

async fn import_lltimeline_for_media(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Query(query): Query<ImportLLTimelineForMediaQuery>,
    Json(document): Json<domain::LLTimelineDocument>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    state
        .services
        .import_lltimeline_document_for_media(
            &MediaId::parse(media_id).map_err(ApplicationError::from)?,
            document,
            query.allow_mismatch.unwrap_or(false),
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn media_subtitles(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<Vec<domain::SubtitleTrack>>, ApiError> {
    state
        .services
        .subtitle_tracks_for_media(&MediaId::parse(media_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn read_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .services
        .read_subtitle_track(&track_id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("subtitle track"))
}

#[derive(Debug, Deserialize)]
struct SubtitleExportQuery {
    format: Option<String>,
}

async fn export_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    Query(query): Query<SubtitleExportQuery>,
) -> Result<Response, ApiError> {
    if query.format.as_deref().unwrap_or("srt") != "srt" {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "unsupported_export_format",
            "only SRT export is supported",
            false,
        ));
    }
    let track = state
        .services
        .read_subtitle_track(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)?
        .ok_or_else(|| ApiError::not_found("subtitle track"))?;
    let mut output = String::new();
    for sentence in track.sentences {
        output.push_str(&format!(
            "{}\n{} --> {}\n{}\n\n",
            sentence.index + 1,
            srt_time(sentence.start.get()),
            srt_time(sentence.end.get()),
            sentence.display_text
        ));
    }
    Ok((
        [(
            axum::http::header::CONTENT_TYPE,
            "application/x-subrip; charset=utf-8",
        )],
        output,
    )
        .into_response())
}

fn srt_time(value: u64) -> String {
    let hours = value / 3_600_000;
    let minutes = value / 60_000 % 60;
    let seconds = value / 1_000 % 60;
    let milliseconds = value % 1_000;
    format!("{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}")
}

async fn pronunciation_providers(
    State(state): State<ApiState>,
) -> Json<Vec<domain::PronunciationProviderInfo>> {
    let providers = state.services.pronunciation_providers();
    for provider in providers.iter().filter(|provider| !provider.available) {
        let _ = state.events.send(EventEnvelope::v1(
            EventName::PronunciationProviderUnavailable,
            serde_json::json!({
                "provider_id": provider.id,
                "provider_version": provider.version,
                "diagnostic": provider.diagnostic,
            }),
        ));
    }
    for provider in providers.iter().filter(|provider| provider.degraded) {
        let _ = state.events.send(EventEnvelope::v1(
            EventName::PronunciationProviderDegraded,
            serde_json::json!({
                "provider_id": provider.id,
                "provider_version": provider.version,
                "diagnostic": provider.diagnostic,
            }),
        ));
    }
    Json(providers)
}

#[derive(Debug, Deserialize)]
struct PronunciationLookupQuery {
    word: String,
}

async fn pronunciation_lookup(
    State(state): State<ApiState>,
    Query(query): Query<PronunciationLookupQuery>,
) -> Result<Json<domain::WordPronunciation>, ApiError> {
    state
        .services
        .lookup_pronunciation(&query.word)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
struct SentenceIdRequest {
    sentence_id: String,
}

async fn analyze_pronunciation_sentence(
    State(state): State<ApiState>,
    Json(request): Json<SentenceIdRequest>,
) -> Result<Json<domain::SentencePronunciation>, ApiError> {
    let sentence_id =
        SubtitleSentenceId::parse(request.sentence_id).map_err(ApplicationError::from)?;
    if state.services.pronunciation_cache_state(&sentence_id)? == Some(false) {
        let _ = state.events.send(EventEnvelope::v1(
            EventName::SpeechCacheInvalidated,
            serde_json::json!({"kind": "pronunciation_analysis", "sentence_id": sentence_id}),
        ));
    }
    let value = state.services.analyze_pronunciation(&sentence_id)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PronunciationAnalysisCompleted,
        serde_json::json!({"sentence_id": value.sentence_id}),
    ));
    Ok(Json(value))
}

async fn track_pronunciation(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::SentencePronunciation>>, ApiError> {
    let parsed_track_id =
        SubtitleTrackId::parse(track_id.clone()).map_err(ApplicationError::from)?;
    let total = state
        .services
        .read_subtitle_track(&parsed_track_id)?
        .ok_or(ApplicationError::NotFound("subtitle track"))?
        .sentences
        .len();
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PronunciationAnalysisProgress,
        serde_json::json!({"track_id": track_id, "processed": 0, "total": total}),
    ));
    let values = state
        .services
        .analyze_pronunciation_track(&parsed_track_id)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PronunciationAnalysisProgress,
        serde_json::json!({"track_id": track_id, "processed": total, "total": total}),
    ));
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PronunciationAnalysisCompleted,
        serde_json::json!({"track_id": track_id, "count": values.len()}),
    ));
    Ok(Json(values))
}

async fn generate_track_pronunciation(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::SentencePronunciation>>, ApiError> {
    track_pronunciation(State(state), Path(track_id)).await
}

async fn speech_jobs(
    State(state): State<ApiState>,
) -> Result<Json<Vec<speech_jobs::SpeechBatchJob>>, ApiError> {
    state.speech_jobs.list().map(Json).map_err(ApiError::from)
}

async fn create_speech_job(
    State(state): State<ApiState>,
    Json(request): Json<CreateSpeechBatchJob>,
) -> Result<Json<speech_jobs::SpeechBatchJob>, ApiError> {
    state
        .speech_jobs
        .clone()
        .create(request)
        .map(Json)
        .map_err(ApiError::from)
}

async fn speech_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<speech_jobs::SpeechBatchJob>, ApiError> {
    state
        .speech_jobs
        .get(&job_id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("speech batch job"))
}

async fn cancel_speech_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<speech_jobs::SpeechBatchJob>, ApiError> {
    state
        .speech_jobs
        .cancel(&job_id)
        .map(Json)
        .map_err(ApiError::from)
}

async fn retry_speech_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<speech_jobs::SpeechBatchJob>, ApiError> {
    state
        .speech_jobs
        .clone()
        .retry(&job_id)
        .map(Json)
        .map_err(ApiError::from)
}

async fn track_word_timings(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::WordTiming>>, ApiError> {
    state
        .services
        .word_timings_for_track(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn track_word_timelines(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::WordTimeline>>, ApiError> {
    state
        .services
        .list_word_timelines(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn track_word_timeline_summaries(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::WordTimelineSummary>>, ApiError> {
    state
        .services
        .summarize_word_timelines(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    state
        .services
        .get_word_timeline(
            &domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )?
        .ok_or(ApplicationError::NotFound("word timeline"))
        .map(Json)
        .map_err(ApiError::from)
}

async fn export_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    word_timeline(State(state), Path(timeline_id)).await
}

async fn create_track_word_timeline(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    Json(request): Json<CreateWordTimelineRequest>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    state
        .services
        .create_word_timeline(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
            application::CreateWordTimeline {
                algorithm_id: request.algorithm_id,
                algorithm_version: request.algorithm_version,
                config_hash: request.config_hash,
                parent_timeline_id: request.parent_timeline_id,
                created_by: request.created_by,
                status: request.status,
                metrics_json: request.metrics_json,
                words: request.words,
            },
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn export_track_lltimeline(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::LLTimelineDocument>, ApiError> {
    state
        .services
        .export_lltimeline_document(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn activate_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    state
        .services
        .activate_word_timeline(
            &domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn publish_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    state
        .services
        .publish_word_timeline(
            &domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn archive_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    state
        .services
        .archive_word_timeline(
            &domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn delete_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    state
        .services
        .delete_word_timeline(
            &domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn track_word_timing_diagnostics(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<application::SentenceWordTimingDiagnostics>>, ApiError> {
    state
        .services
        .word_timing_diagnostics_for_track(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn track_chunk_partitions(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<application::SentenceChunkPartition>>, ApiError> {
    state
        .services
        .chunk_partitions_for_track(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn track_chunk_diagnostics(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<application::SentenceChunkDiagnostics>>, ApiError> {
    state
        .services
        .chunk_diagnostics_for_track(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn chunk_providers(
    State(state): State<ApiState>,
) -> Json<Vec<application::LearnedProsodicProviderInfo>> {
    Json(state.services.learned_prosodic_providers())
}

async fn generate_track_word_timings(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    request: Option<Json<WordTimingsRequest>>,
) -> Result<Json<Vec<domain::WordTiming>>, ApiError> {
    let parsed_track_id =
        SubtitleTrackId::parse(track_id.clone()).map_err(ApplicationError::from)?;
    let total = state
        .services
        .read_subtitle_track(&parsed_track_id)?
        .ok_or(ApplicationError::NotFound("subtitle track"))?
        .sentences
        .len();
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordTimingsProgress,
        serde_json::json!({"track_id": track_id, "processed": 0, "total": total}),
    ));
    let values = match request {
        Some(Json(request)) if !request.timings.is_empty() => state
            .services
            .store_word_timings(&parsed_track_id, &request.timings)?,
        _ => state.services.word_timings_for_track(&parsed_track_id)?,
    };
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordTimingsProgress,
        serde_json::json!({"track_id": track_id, "processed": total, "total": total}),
    ));
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordTimingsCompleted,
        serde_json::json!({"track_id": track_id, "count": values.len()}),
    ));
    Ok(Json(values))
}

#[derive(Debug, Deserialize)]
struct WordTimingsRequest {
    timings: Vec<domain::WordTiming>,
}

#[derive(Debug, Deserialize)]
struct CreateWordTimelineRequest {
    algorithm_id: Option<String>,
    algorithm_version: Option<String>,
    config_hash: Option<String>,
    parent_timeline_id: Option<domain::WordTimelineId>,
    created_by: Option<domain::TimelineCreator>,
    status: Option<domain::TimelineStatus>,
    metrics_json: Option<serde_json::Value>,
    words: Vec<domain::WordTiming>,
}

async fn pronunciation_rules(State(state): State<ApiState>) -> Json<serde_json::Value> {
    Json(state.services.pronunciation_rules())
}

async fn transcription_providers(
    State(state): State<ApiState>,
) -> Json<Vec<domain::TranscriptionProviderInfo>> {
    Json(state.transcription.providers())
}

async fn transcription_models(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::TranscriptionModelDescriptor>>, ApiError> {
    state
        .transcription
        .models()
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
struct ModelIdRequest {
    model_id: String,
}

async fn install_transcription_model(
    State(state): State<ApiState>,
    Json(request): Json<ModelIdRequest>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let id =
        domain::TranscriptionModelId::parse(request.model_id).map_err(ApplicationError::from)?;
    let coordinator = state.transcription.clone();
    tokio::spawn(async move {
        let _ = coordinator.install_model(id).await;
    });
    Ok(Json(serde_json::json!({"installation_started": true})))
}

#[derive(Debug, Deserialize)]
struct RegisterCustomModelRequest {
    path: String,
}

async fn register_custom_transcription_model(
    State(state): State<ApiState>,
    Json(request): Json<RegisterCustomModelRequest>,
) -> Result<Json<domain::TranscriptionModelDescriptor>, ApiError> {
    state
        .transcription
        .register_custom_model(request.path)
        .map(Json)
        .map_err(ApiError::from)
}

async fn cancel_transcription_model_install(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<Json<domain::TranscriptionModelDescriptor>, ApiError> {
    state
        .transcription
        .cancel_model_install(
            &domain::TranscriptionModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn delete_transcription_model(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    state
        .transcription
        .delete_model(
            &domain::TranscriptionModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

async fn transcription_jobs(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::TranscriptionJob>>, ApiError> {
    state.transcription.jobs().map(Json).map_err(ApiError::from)
}

async fn create_transcription_job(
    State(state): State<ApiState>,
    Json(request): Json<CreateJobRequest>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .clone()
        .create_job(request)
        .map(Json)
        .map_err(ApiError::from)
}

async fn transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("transcription job"))
}

async fn cancel_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .cancel_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn retry_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .clone()
        .retry_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn archive_transcription_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::TranscriptionJob>, ApiError> {
    state
        .transcription
        .archive_job(&domain::TranscriptionJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn phonetic_analysis_providers(
    State(state): State<ApiState>,
) -> Json<Vec<domain::PhoneticAnalysisProviderInfo>> {
    Json(state.phonetic_analysis.providers())
}

async fn phonetic_analysis_models(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::PhoneticAnalysisModelDescriptor>>, ApiError> {
    state
        .phonetic_analysis
        .models()
        .map(Json)
        .map_err(ApiError::from)
}

async fn install_phonetic_analysis_model(
    State(state): State<ApiState>,
    Json(request): Json<ModelIdRequest>,
) -> Result<Json<domain::PhoneticAnalysisModelDescriptor>, ApiError> {
    state
        .phonetic_analysis
        .install_model(
            &domain::PhoneticAnalysisModelId::parse(request.model_id)
                .map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn register_custom_phonetic_analysis_model(
    State(state): State<ApiState>,
    Json(request): Json<RegisterCustomModelRequest>,
) -> Result<Json<domain::PhoneticAnalysisModelDescriptor>, ApiError> {
    state
        .phonetic_analysis
        .register_custom_model(request.path)
        .map(Json)
        .map_err(ApiError::from)
}

async fn cancel_phonetic_analysis_model_install(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<Json<domain::PhoneticAnalysisModelDescriptor>, ApiError> {
    state
        .phonetic_analysis
        .cancel_model_install(
            &domain::PhoneticAnalysisModelId::parse(model_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn delete_phonetic_analysis_model(
    State(state): State<ApiState>,
    Path(model_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    state.phonetic_analysis.delete_model(
        &domain::PhoneticAnalysisModelId::parse(model_id).map_err(ApplicationError::from)?,
    )?;
    Ok(StatusCode::NO_CONTENT)
}

async fn phonetic_analysis_jobs(
    State(state): State<ApiState>,
) -> Result<Json<Vec<domain::PhoneticAnalysisJob>>, ApiError> {
    state
        .phonetic_analysis
        .jobs()
        .map(Json)
        .map_err(ApiError::from)
}

async fn create_phonetic_analysis_job(
    State(state): State<ApiState>,
    Json(request): Json<CreatePhoneticJobRequest>,
) -> Result<Json<domain::PhoneticAnalysisJob>, ApiError> {
    state
        .phonetic_analysis
        .clone()
        .create_job(request)
        .map(Json)
        .map_err(ApiError::from)
}

async fn phonetic_analysis_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::PhoneticAnalysisJob>, ApiError> {
    state
        .phonetic_analysis
        .job(&domain::PhoneticAnalysisJobId::parse(job_id).map_err(ApplicationError::from)?)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("phonetic analysis job"))
}

async fn cancel_phonetic_analysis_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::PhoneticAnalysisJob>, ApiError> {
    state
        .phonetic_analysis
        .cancel_job(&domain::PhoneticAnalysisJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn retry_phonetic_analysis_job(
    State(state): State<ApiState>,
    Path(job_id): Path<String>,
) -> Result<Json<domain::PhoneticAnalysisJob>, ApiError> {
    state
        .phonetic_analysis
        .clone()
        .retry_job(&domain::PhoneticAnalysisJobId::parse(job_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn track_phonetic_analyses(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::PhoneticAnalysis>>, ApiError> {
    state
        .phonetic_analysis
        .analyses(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

async fn phonetic_analysis_findings(
    State(state): State<ApiState>,
    Path(analysis_id): Path<String>,
) -> Result<Json<Vec<domain::PhoneticFinding>>, ApiError> {
    state
        .phonetic_analysis
        .analysis(&domain::PhoneticAnalysisId::parse(analysis_id).map_err(ApplicationError::from)?)?
        .map(|analysis| Json(analysis.findings))
        .ok_or_else(|| ApiError::not_found("phonetic analysis"))
}

#[derive(Debug, Deserialize)]
struct PhoneticFindingFeedbackRequest {
    value: domain::PhoneticFindingFeedbackValue,
    note: Option<String>,
}

async fn update_phonetic_finding_feedback(
    State(state): State<ApiState>,
    Path(finding_id): Path<String>,
    Json(request): Json<PhoneticFindingFeedbackRequest>,
) -> Result<Json<domain::PhoneticFindingFeedback>, ApiError> {
    let feedback = domain::PhoneticFindingFeedback {
        finding_id: phonetic_analysis::finding_id(finding_id)?,
        value: request.value,
        note: request.note,
        updated_at_ms: application::now_ms(),
    };
    let feedback = state.phonetic_analysis.save_feedback(&feedback)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::PhoneticAnalysisFeedbackChanged,
        serde_json::to_value(&feedback).expect("phonetic feedback serializes"),
    ));
    Ok(Json(feedback))
}

async fn read_progress(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<ProgressResponse>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    Ok(Json(ProgressResponse {
        position_ms: state.services.read_progress(&id)?.map(domain::TimeMs::get),
    }))
}

#[derive(Debug, Deserialize)]
struct UpdateProgressRequest {
    position_ms: u64,
}

#[derive(Debug, Serialize)]
struct ProgressResponse {
    position_ms: Option<u64>,
}

async fn update_progress(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<UpdateProgressRequest>,
) -> Result<Json<ProgressResponse>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    let position = state.services.update_progress(&id, request.position_ms)?;
    Ok(Json(ProgressResponse {
        position_ms: Some(position.get()),
    }))
}

#[derive(Debug, Deserialize)]
struct WordQuery {
    language: String,
    lemma: String,
}

#[derive(Debug, Deserialize)]
struct BatchWordRequest {
    language: String,
    lemmas: Vec<String>,
}

async fn read_words(
    State(state): State<ApiState>,
    Json(request): Json<BatchWordRequest>,
) -> Result<Json<Vec<domain::WordProfile>>, ApiError> {
    state
        .services
        .read_word_profiles(&request.language, &request.lemmas)
        .map(Json)
        .map_err(ApiError::from)
}

async fn read_word(
    State(state): State<ApiState>,
    Query(query): Query<WordQuery>,
) -> Result<Json<Option<domain::WordProfile>>, ApiError> {
    state
        .services
        .read_word_profile(&query.language, &query.lemma)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
struct UpdateWordRequest {
    language: String,
    lemma: String,
    display_form: String,
    status: Option<WordStatus>,
    source: Option<SourceRequest>,
}

async fn update_word(
    State(state): State<ApiState>,
    Json(request): Json<UpdateWordRequest>,
) -> Result<Json<domain::WordProfile>, ApiError> {
    let profile = state
        .services
        .update_word_profile(UpdateWordProfile {
            language: request.language,
            lemma: request.lemma,
            display_form: request.display_form,
            status: request.status,
            source: request
                .source
                .map(SourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordProfileChanged,
        serde_json::to_value(&profile).expect("word profile serializes"),
    ));
    Ok(Json(profile))
}

#[derive(Debug, Deserialize)]
struct CreateObservationRequest {
    word_profile_id: String,
    sentence_id: String,
    original_form: String,
    result: Option<ObservationResult>,
    clear: Option<bool>,
    source: Option<SourceRequest>,
}

#[derive(Debug, Deserialize)]
struct SourceRequest {
    language: String,
    normalized_lemma: String,
    media_id: Option<String>,
    sentence_id: Option<String>,
    original_form: String,
    sentence_text: String,
    media_title: String,
    media_fingerprint: String,
    start_ms: u64,
    end_ms: u64,
}

impl SourceRequest {
    fn into_context(self) -> Result<SourceContext, ApplicationError> {
        Ok(SourceContext {
            language: LanguageCode::parse(self.language)?,
            normalized_lemma: self.normalized_lemma,
            media_id: self.media_id.map(MediaId::parse).transpose()?,
            sentence_id: self
                .sentence_id
                .map(SubtitleSentenceId::parse)
                .transpose()?,
            original_form: self.original_form,
            sentence_text: self.sentence_text,
            media_title: self.media_title,
            media_fingerprint: self.media_fingerprint,
            start_ms: self.start_ms,
            end_ms: self.end_ms,
        })
    }
}

async fn create_observation(
    State(state): State<ApiState>,
    Json(request): Json<CreateObservationRequest>,
) -> Result<Response, ApiError> {
    let word_profile_id =
        WordProfileId::parse(request.word_profile_id).map_err(ApplicationError::from)?;
    let sentence_id =
        SubtitleSentenceId::parse(request.sentence_id).map_err(ApplicationError::from)?;
    if request.clear.unwrap_or(false) {
        state
            .services
            .clear_observation(&word_profile_id, &sentence_id)?;
        let _ = state.events.send(EventEnvelope::v1(
            EventName::WordObservationCleared,
            serde_json::json!({
                "word_profile_id": word_profile_id,
                "sentence_id": sentence_id,
            }),
        ));
        return Ok(StatusCode::NO_CONTENT.into_response());
    }
    let observation = state
        .services
        .create_observation(CreateWordObservation {
            word_profile_id,
            sentence_id,
            original_form: request.original_form,
            result: request
                .result
                .ok_or(ApplicationError::Validation("result"))?,
            source: request
                .source
                .map(SourceRequest::into_context)
                .transpose()?,
        })
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::WordObservationCreated,
        serde_json::to_value(&observation).expect("word observation serializes"),
    ));
    Ok(Json(observation).into_response())
}

#[derive(Debug, Deserialize)]
struct VocabularyQuery {
    language: Option<String>,
    status: WordStatus,
    search: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
}

async fn list_vocabulary(
    State(state): State<ApiState>,
    Query(query): Query<VocabularyQuery>,
) -> Result<Json<Vec<domain::WordDetails>>, ApiError> {
    state
        .services
        .list_vocabulary(
            query.language.as_deref().unwrap_or("en"),
            query.status,
            query.search.as_deref().unwrap_or(""),
            query.limit.unwrap_or(100),
            query.offset.unwrap_or(0),
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn word_details(
    State(state): State<ApiState>,
    Path(profile_id): Path<String>,
) -> Result<Json<domain::WordDetails>, ApiError> {
    let id = WordProfileId::parse(profile_id).map_err(ApplicationError::from)?;
    state
        .services
        .word_details(&id)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("word profile"))
}

#[derive(Debug, Deserialize)]
struct UpdateLearningContentRequest {
    user_definition: Option<String>,
    personal_note: Option<String>,
}

async fn update_learning_content(
    State(state): State<ApiState>,
    Path(profile_id): Path<String>,
    Json(request): Json<UpdateLearningContentRequest>,
) -> Result<Json<domain::WordDetails>, ApiError> {
    state
        .services
        .update_word_learning_content(
            &WordProfileId::parse(profile_id).map_err(ApplicationError::from)?,
            request.user_definition,
            request.personal_note,
        )
        .map(Json)
        .map_err(ApiError::from)
}

async fn import_external_vocabulary(
    State(state): State<ApiState>,
    Json(request): Json<domain::ExternalVocabularyImport>,
) -> Result<Json<domain::ExternalVocabularyImportSummary>, ApiError> {
    state
        .services
        .import_external_vocabulary(&request)
        .map(Json)
        .map_err(ApiError::from)
}

async fn export_vocabulary(
    State(state): State<ApiState>,
) -> Result<Json<VocabularyAssetBundle>, ApiError> {
    state
        .services
        .export_vocabulary()
        .map(Json)
        .map_err(ApiError::from)
}

async fn import_vocabulary(
    State(state): State<ApiState>,
    Json(bundle): Json<VocabularyAssetBundle>,
) -> Result<Json<serde_json::Value>, ApiError> {
    state.services.import_vocabulary(&bundle)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::VocabularyAssetsImported,
        serde_json::json!({"profiles": bundle.profiles.len()}),
    ));
    Ok(Json(serde_json::json!({"imported": true})))
}

#[derive(Debug, Deserialize)]
struct UpdateAvailabilityRequest {
    availability: MediaAvailability,
}

async fn update_media_availability(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<UpdateAvailabilityRequest>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let media = state
        .services
        .set_media_availability(
            &MediaId::parse(media_id).map_err(ApplicationError::from)?,
            request.availability,
        )
        .map_err(ApiError::from)?;
    let _ = state.events.send(EventEnvelope::v1(
        EventName::MediaAvailabilityChanged,
        serde_json::to_value(&media).expect("media serializes"),
    ));
    Ok(Json(media))
}

#[derive(Debug, Deserialize)]
struct DictionaryQuery {
    language: String,
    lemma: String,
}

async fn dictionary_lookup(
    State(state): State<ApiState>,
    Query(query): Query<DictionaryQuery>,
) -> Result<Json<domain::DictionaryLookupBundle>, ApiError> {
    state
        .services
        .lookup_dictionary(state.dictionaries.as_ref(), &query.language, &query.lemma)
        .await
        .map(Json)
        .map_err(ApiError::from)
}

async fn diagnose_sentence(
    State(state): State<ApiState>,
    Path(sentence_id): Path<String>,
) -> Result<Json<domain::SentenceDiagnosis>, ApiError> {
    let sentence_id = SubtitleSentenceId::parse(sentence_id).map_err(ApplicationError::from)?;
    state
        .services
        .diagnose_sentence(&sentence_id)
        .map(Json)
        .map_err(ApiError::from)
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
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
    use persistence_sqlite::SqliteRepository;
    use tower::ServiceExt;

    fn test_app() -> Router {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        router(ApiState::new(
            AppServices::new(
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
                repo.clone(),
            ),
            repo,
            "secret",
        ))
    }

    async fn setup_phonetic_track(app: &Router, fingerprint: &str) -> serde_json::Value {
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/media")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "path": format!("/tmp/{fingerprint}.mp4"),
                            "fingerprint": fingerprint,
                            "title": fingerprint,
                            "kind": "video"
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        let media: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let fixture = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../testdata/subtitles/timeline.srt"
        );
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/media/{}/subtitles",
                    media["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({"path": fixture, "language": "en"}).to_string(),
                ))
                .unwrap(),
            )
            .await
            .unwrap();
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap()
    }

    async fn wait_for_phonetic_job(
        app: &Router,
        job_id: &str,
        expected: &[&str],
    ) -> serde_json::Value {
        for _ in 0..100 {
            let response = app
                .clone()
                .oneshot(
                    Request::get(format!("/v1/phonetic-analysis/jobs/{job_id}"))
                        .header(AUTHORIZATION, "Bearer secret")
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            let value: serde_json::Value =
                serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                    .unwrap();
            if expected.contains(&value["status"].as_str().unwrap()) {
                return value;
            }
            tokio::time::sleep(std::time::Duration::from_millis(2)).await;
        }
        panic!("phonetic analysis job did not reach {expected:?}");
    }

    #[tokio::test]
    async fn health_is_public_and_versioned() {
        let response = test_app()
            .oneshot(Request::get("/v1/health").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn protected_routes_require_token() {
        let response = test_app()
            .oneshot(Request::post("/v1/media").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn chunk_provider_catalog_reports_optional_licensed_model() {
        let response = test_app()
            .oneshot(
                Request::get("/v1/chunk/providers")
                    .header(AUTHORIZATION, "Bearer secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(body[0]["license"], "MIT");
        assert_eq!(body[0]["optional"], true);
        assert_eq!(body[0]["available"], true);
    }

    #[tokio::test]
    async fn media_registration_is_idempotent_over_http() {
        let app = test_app();
        let body = serde_json::json!({
            "path": "/tmp/a.mp4",
            "fingerprint": "abc",
            "title": "A",
            "kind": "video",
            "duration_ms": 1000
        })
        .to_string();
        let request = || {
            Request::post("/v1/media")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(body.clone()))
                .unwrap()
        };
        let first = app.clone().oneshot(request()).await.unwrap();
        assert_eq!(first.status(), StatusCode::OK);
        let first_body = to_bytes(first.into_body(), usize::MAX).await.unwrap();
        let second = app.oneshot(request()).await.unwrap();
        assert_eq!(second.status(), StatusCode::OK);
        let second_body = to_bytes(second.into_body(), usize::MAX).await.unwrap();
        let first: serde_json::Value = serde_json::from_slice(&first_body).unwrap();
        let second: serde_json::Value = serde_json::from_slice(&second_body).unwrap();
        assert_eq!(first["id"], second["id"]);
    }

    #[tokio::test]
    async fn imports_and_reads_complete_subtitle_timeline() {
        let app = test_app();
        let media = serde_json::json!({
            "path": "/tmp/a.mp4",
            "fingerprint": "subtitle-media",
            "title": "A",
            "kind": "video"
        })
        .to_string();
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/media")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(media))
                    .unwrap(),
            )
            .await
            .unwrap();
        let media: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let fixture = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../testdata/subtitles/timeline.srt"
        );
        let request = serde_json::json!({"path": fixture, "language": "en"}).to_string();
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/media/{}/subtitles",
                    media["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(request))
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let track: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(track["sentences"].as_array().unwrap().len(), 4);
        let response = app
            .clone()
            .oneshot(
                Request::get(format!("/v1/subtitles/{}", track["id"].as_str().unwrap()))
                    .header(AUTHORIZATION, "Bearer secret")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let response = app
            .clone()
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/chunk-partitions",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let partitions: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(partitions.as_array().unwrap().len(), 4);
        assert!(
            partitions[0]["chunks"]
                .as_array()
                .is_some_and(|chunks| !chunks.is_empty())
        );

        let response = app
            .clone()
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/word-timing-diagnostics",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let timing_diagnostics: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(timing_diagnostics.as_array().unwrap().len(), 4);
        assert!(timing_diagnostics[0]["boundaries"].as_array().is_some());

        let response = app
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/chunk-diagnostics",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let diagnostics: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(diagnostics.as_array().unwrap().len(), 4);
        assert!(diagnostics[0]["candidates"].as_array().is_some());
    }

    #[tokio::test]
    async fn exports_lltimeline_document_with_active_word_timeline() {
        let app = test_app();
        let track = setup_phonetic_track(&app, "lltimeline-media").await;
        let sentence = &track["sentences"][0];
        let token = sentence["tokens"]
            .as_array()
            .unwrap()
            .iter()
            .find(|token| token["kind"] == "word")
            .expect("fixture has a word token");
        let start_ms = sentence["start"].as_u64().unwrap() + 10;
        let end_ms = start_ms + 120;
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/subtitles/{}/word-timelines",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "algorithm_id": "test-aligner",
                        "algorithm_version": "v1",
                        "config_hash": "test-config",
                        "status": "active",
                        "words": [{
                            "sentence_id": sentence["id"],
                            "token_index": token["index"],
                            "text": token["text"],
                            "start_ms": start_ms,
                            "end_ms": end_ms,
                            "confidence": 0.95,
                            "timing_source": "forced_aligned",
                            "provider_id": "test-aligner",
                            "provider_version": "v1"
                        }]
                    })
                    .to_string(),
                ))
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let timeline: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();

        let response = app
            .clone()
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/lltimeline/export",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let mut document: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(document["schema"], domain::LLTIMELINE_SCHEMA_V1);
        assert_eq!(
            document["metadata"]["media"]["fingerprint"],
            "lltimeline-media"
        );
        assert_eq!(document["segments"].as_array().unwrap().len(), 4);
        assert_eq!(document["word_timelines"].as_array().unwrap().len(), 1);
        assert_eq!(document["active_word_timeline_id"], timeline["id"]);
        assert_eq!(document["phone_timelines"].as_array().unwrap().len(), 0);
        assert_eq!(document["chunk_timelines"].as_array().unwrap().len(), 0);
        document["metadata"]["generator"] = serde_json::json!({
            "id": "fixture-production-engine",
            "version": "v2",
            "mode": "production_engine"
        });
        document["artifacts"] = serde_json::json!([
            {
                "kind": "production_report",
                "provider_id": "fixture-production-engine",
                "provider_version": "v2",
                "payload": {
                    "readiness": "ready",
                    "post_alignment": "mfa"
                }
            }
        ]);

        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/lltimeline/import")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(document.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let imported_track: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(imported_track["id"], track["id"]);
        assert_eq!(imported_track["sentences"].as_array().unwrap().len(), 4);

        let response = app
            .clone()
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/word-timelines/summary",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let summaries: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(summaries.as_array().unwrap().len(), 1);
        assert_eq!(summaries[0]["status"], "active");
        assert_eq!(summaries[0]["lifecycle_stage"], "algorithm_candidate");

        let response = app
            .clone()
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/lltimeline/export",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let exported_after_import: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(
            exported_after_import["metadata"]["generator"]["id"],
            "fixture-production-engine"
        );
        assert_eq!(
            exported_after_import["artifacts"][0]["kind"],
            "production_report"
        );

        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/word-timelines/{}/publish",
                    timeline["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let published: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(
            published["metrics_json"]["lifecycle"]["published"],
            serde_json::Value::Bool(true)
        );

        let response = app
            .oneshot(
                Request::delete(format!(
                    "/v1/word-timelines/{}",
                    timeline["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn imports_lltimeline_for_current_media_with_user_confirmed_mismatch() {
        let app = test_app();
        let source_track = setup_phonetic_track(&app, "source-media").await;
        let sentence = &source_track["sentences"][0];
        let token = sentence["tokens"]
            .as_array()
            .unwrap()
            .iter()
            .find(|token| token["kind"] == "word")
            .expect("fixture has a word token");
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/subtitles/{}/word-timelines",
                    source_track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "algorithm_id": "exchange-aligner",
                        "algorithm_version": "v1",
                        "config_hash": "test-config",
                        "status": "active",
                        "words": [{
                            "sentence_id": sentence["id"],
                            "token_index": token["index"],
                            "text": token["text"],
                            "start_ms": sentence["start"].as_u64().unwrap() + 10,
                            "end_ms": sentence["start"].as_u64().unwrap() + 130,
                            "confidence": 0.95,
                            "timing_source": "forced_aligned",
                            "provider_id": "exchange-aligner",
                            "provider_version": "v1"
                        }]
                    })
                    .to_string(),
                ))
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let response = app
            .clone()
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/lltimeline/export",
                    source_track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let document: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();

        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/media")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "path": "/tmp/target-media.mp4",
                            "fingerprint": "target-media",
                            "title": "target-media",
                            "kind": "video"
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        let target_media: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();

        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/media/{}/lltimeline/import",
                    target_media["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(document.to_string()))
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);

        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/media/{}/lltimeline/import?allow_mismatch=true",
                    target_media["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(document.to_string()))
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let imported_track: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(imported_track["media_id"], target_media["id"]);

        let response = app
            .clone()
            .oneshot(
                Request::get(format!(
                    "/v1/media/{}/subtitles",
                    target_media["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let resources: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(resources.as_array().unwrap().len(), 1);
        assert_eq!(resources[0]["id"], imported_track["id"]);

        let response = app
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/word-timings",
                    imported_track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let timings: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(timings.as_array().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn phonetic_analysis_fake_provider_completes_without_audio_detection_claims() {
        let app = test_app();
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/media")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "path": "/tmp/phonetic.mp4",
                            "fingerprint": "phonetic-media",
                            "title": "Phonetic",
                            "kind": "video"
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        let media: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let fixture = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../testdata/subtitles/timeline.srt"
        );
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/media/{}/subtitles",
                    media["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({"path": fixture, "language": "en"}).to_string(),
                ))
                .unwrap(),
            )
            .await
            .unwrap();
        let track: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let job_request = serde_json::json!({
            "track_id": track["id"],
            "sentence_id": track["sentences"][0]["id"],
            "model_id": "research-fixture:deterministic@v1"
        })
        .to_string();
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/phonetic-analysis/jobs")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(job_request.clone()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let job: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let job_id = job["id"].as_str().unwrap();
        let completed = wait_for_phonetic_job(&app, job_id, &["completed"]).await;
        assert_eq!(completed["phase_progress"], 100);
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/phonetic-analysis/jobs")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(job_request))
                    .unwrap(),
            )
            .await
            .unwrap();
        let repeated: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(repeated["id"], completed["id"]);
        let response = app
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/phonetic-analyses",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let analyses: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert!(
            !analyses[0]["detected_phones"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        let findings = analyses[0]["findings"].as_array().unwrap();
        assert!(!findings.is_empty());
        assert!(
            findings
                .iter()
                .all(|finding| finding["status"] != "detected_in_audio")
        );
    }

    #[tokio::test]
    async fn phonetic_model_management_rejects_unapproved_research_fixture() {
        let app = test_app();
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/phonetic-analysis/models/install")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "model_id": "research-fixture:deterministic@v1"
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::CONFLICT);

        let response = app
            .oneshot(
                Request::delete(
                    "/v1/phonetic-analysis/models/research-fixture%3Adeterministic%40v1",
                )
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn phonetic_fake_provider_supports_partial_cancel_failure_retry_and_feedback() {
        let app = test_app();
        let track = setup_phonetic_track(&app, "phonetic-lifecycle").await;
        let create = |mode: &str| {
            Request::post("/v1/phonetic-analysis/jobs")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "track_id": track["id"],
                        "sentence_id": track["sentences"][0]["id"],
                        "model_id": "research-fixture:deterministic@v1",
                        "research_mode": mode
                    })
                    .to_string(),
                ))
                .unwrap()
        };

        let response = app.clone().oneshot(create("slow")).await.unwrap();
        let cancellable: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/phonetic-analysis/jobs/{}/cancel",
                    cancellable["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let cancelled: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(cancelled["status"], "cancelled");

        let response = app.clone().oneshot(create("fail")).await.unwrap();
        let failing: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let failed =
            wait_for_phonetic_job(&app, failing["id"].as_str().unwrap(), &["failed"]).await;
        assert_eq!(failed["error_code"], "research_fixture_failed");
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/phonetic-analysis/jobs/{}/retry",
                    failed["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let retried: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(retried["retry_of_job_id"], failed["id"]);
        wait_for_phonetic_job(&app, retried["id"].as_str().unwrap(), &["failed"]).await;

        let response = app.clone().oneshot(create("partial")).await.unwrap();
        let partial: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        wait_for_phonetic_job(&app, partial["id"].as_str().unwrap(), &["completed"]).await;
        let response = app
            .clone()
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/phonetic-analyses",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let analyses: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let analysis = analyses
            .as_array()
            .unwrap()
            .iter()
            .find(|value| value["job_id"] == partial["id"])
            .unwrap();
        assert_eq!(analysis["detected_phones"].as_array().unwrap().len(), 1);
        let finding_id = analysis["findings"][0]["id"].as_str().unwrap();
        let response = app
            .clone()
            .oneshot(
                Request::put("/v1/phonetic-analysis/findings/missing/feedback")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(r#"{"value":"confirmed"}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        let response = app
            .clone()
            .oneshot(
                Request::put(format!(
                    "/v1/phonetic-analysis/findings/{finding_id}/feedback"
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(r#"{"value":"confirmed","note":"matches"}"#))
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/phonetic-analysis/jobs")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "track_id": track["id"],
                            "model_id": "research-fixture:deterministic@v1"
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        let track_job: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        wait_for_phonetic_job(&app, track_job["id"].as_str().unwrap(), &["completed"]).await;
        let response = app
            .oneshot(
                Request::get(format!(
                    "/v1/subtitles/{}/phonetic-analyses",
                    track["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let analyses: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(
            analyses
                .as_array()
                .unwrap()
                .iter()
                .filter(|analysis| analysis["job_id"] == track_job["id"])
                .count(),
            track["sentences"].as_array().unwrap().len()
        );
    }

    #[tokio::test]
    async fn speech_batch_job_queues_ten_thousand_sentences_and_can_cancel_and_retry() {
        let app = test_app();
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/media")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "path": "/tmp/speech-batch.mp4",
                            "fingerprint": "speech-batch-media",
                            "title": "Speech batch",
                            "kind": "video"
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        let media: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let path = std::env::temp_dir().join(format!(
            "llplayer-speech-batch-{}.srt",
            application::now_ms()
        ));
        let content = (1..=10_000)
            .map(|index| format!("{index}\n00:00:00,000 --> 00:00:00,999\nHello world {index}\n\n"))
            .collect::<String>();
        std::fs::write(&path, content).unwrap();
        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/media/{}/subtitles",
                    media["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    serde_json::json!({"path": path, "language": "en"}).to_string(),
                ))
                .unwrap(),
            )
            .await
            .unwrap();
        let _ = std::fs::remove_file(&path);
        let track: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        let response = app
            .clone()
            .oneshot(
                Request::post("/v1/speech/jobs")
                    .header(AUTHORIZATION, "Bearer secret")
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        serde_json::json!({
                            "track_id": track["id"],
                            "kind": "pronunciation_analysis"
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        let job: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(job["status"], "queued");
        assert_eq!(job["total"], 10_000);

        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/speech/jobs/{}/cancel",
                    job["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let cancelled: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(cancelled["status"], "cancelled");

        let response = app
            .clone()
            .oneshot(
                Request::post(format!(
                    "/v1/speech/jobs/{}/retry",
                    job["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        let retried: serde_json::Value =
            serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap())
                .unwrap();
        assert_eq!(retried["status"], "queued");
        assert_eq!(retried["retry_of_job_id"], job["id"]);
        let response = app
            .oneshot(
                Request::post(format!(
                    "/v1/speech/jobs/{}/cancel",
                    retried["id"].as_str().unwrap()
                ))
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    #[test]
    fn openapi_lists_implemented_routes() {
        let openapi = include_str!("../../../contracts/openapi/v1.yaml");
        for path in [
            "/v1/health",
            "/v1/media",
            "/v1/lltimeline/import",
            "/v1/media/{media_id}",
            "/v1/media/{media_id}/subtitles",
            "/v1/media/{media_id}/progress",
            "/v1/subtitles/{track_id}",
            "/v1/subtitles/{track_id}/export",
            "/v1/pronunciation/providers",
            "/v1/pronunciation/lookup",
            "/v1/pronunciation/analyze-sentence",
            "/v1/pronunciation/rules",
            "/v1/subtitles/{track_id}/pronunciation",
            "/v1/subtitles/{track_id}/pronunciation-analysis",
            "/v1/subtitles/{track_id}/word-timings",
            "/v1/subtitles/{track_id}/word-timelines",
            "/v1/subtitles/{track_id}/word-timelines/summary",
            "/v1/subtitles/{track_id}/lltimeline/export",
            "/v1/word-timelines/{timeline_id}",
            "/v1/word-timelines/{timeline_id}/activate",
            "/v1/word-timelines/{timeline_id}/publish",
            "/v1/word-timelines/{timeline_id}/archive",
            "/v1/word-timelines/{timeline_id}/export",
            "/v1/subtitles/{track_id}/word-timing-diagnostics",
            "/v1/subtitles/{track_id}/chunk-partitions",
            "/v1/subtitles/{track_id}/chunk-diagnostics",
            "/v1/chunk/providers",
            "/v1/speech/jobs",
            "/v1/word-profiles",
            "/v1/word-profiles/batch",
            "/v1/word-observations",
            "/v1/vocabulary",
            "/v1/vocabulary/export",
            "/v1/vocabulary/import",
            "/v1/word-profiles/{profile_id}/details",
            "/v1/word-profiles/{profile_id}/learning-content",
            "/v1/vocabulary/import-external",
            "/v1/media/{media_id}/availability",
            "/v1/events",
            "/v1/dictionary",
            "/v1/sentences/{sentence_id}/diagnosis",
            "/v1/transcription/providers",
            "/v1/transcription/models",
            "/v1/transcription/jobs",
            "/v1/transcription/jobs/{job_id}/archive",
            "/v1/phonetic-analysis/providers",
            "/v1/phonetic-analysis/models",
            "/v1/phonetic-analysis/models/install",
            "/v1/phonetic-analysis/models/register-custom",
            "/v1/phonetic-analysis/models/{model_id}/cancel-install",
            "/v1/phonetic-analysis/models/{model_id}",
            "/v1/phonetic-analysis/jobs",
            "/v1/subtitles/{track_id}/phonetic-analyses",
            "/v1/phonetic-analysis/{analysis_id}/findings",
            "/v1/phonetic-analysis/findings/{finding_id}/feedback",
        ] {
            assert!(openapi.contains(path), "OpenAPI missing {path}");
        }
    }

    #[test]
    fn openapi_version_snapshot_and_path_count() {
        let openapi = include_str!("../../../contracts/openapi/v1.yaml");

        // API version snapshot — bump intentionally, never accidentally.
        assert!(
            openapi.contains("version: 1.0.0"),
            "OpenAPI info.version snapshot changed — update test if intentional"
        );

        // OpenAPI specification version.
        assert!(
            openapi.contains("openapi: 3.1.0"),
            "OpenAPI spec version snapshot changed"
        );

        // Count documented paths as a regression gate.
        let path_count = openapi.lines().filter(|l| l.starts_with("  /v1/")).count();
        assert_eq!(
            path_count, 79,
            "OpenAPI path count changed from 79 — update snapshot if paths were added/removed"
        );

        // All paths must be under /v1/.
        for line in openapi.lines() {
            if line.starts_with("  /") && !line.starts_with("  /v1/") {
                panic!("OpenAPI path not under /v1/ prefix: {}", line.trim());
            }
        }

        // Key schemas must exist (defines the response contract surface).
        for schema in [
            "Health:",
            "MediaItem:",
            "RegisterMedia:",
            "SubtitleTrack:",
            "SubtitleSentence:",
            "SubtitleToken:",
            "LexicalEntry:",
            "LexicalEntryDetails:",
            "WordProfile:",
            "WordObservation:",
            "WordOccurrence:",
            "SentenceDiagnosis:",
            "DictionaryLookup:",
            "DictionaryLookupBundle:",
            "VocabularyAssetBundle:",
            "LearningResource:",
            "SubtitleSearchResult:",
            "WordDetails:",
        ] {
            assert!(
                openapi.contains(&format!("    {schema}")),
                "OpenAPI schema missing: {schema}"
            );
        }
    }
}
