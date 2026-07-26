use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, ImportSubtitle, IntoResponse, Json,
    LanguageCode, MediaId, MediaKind, MediaTriageIntent, Path, Query, RegisterMedia, Response,
    State, StatusCode, SubtitleTrackId,
};

#[derive(Debug, Deserialize)]
pub(crate) struct RegisterMediaRequest {
    path: String,
    fingerprint: String,
    title: String,
    kind: MediaKind,
    duration_ms: Option<u64>,
}

pub(crate) async fn register_media(
    State(state): State<ApiState>,
    Json(request): Json<RegisterMediaRequest>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let input = RegisterMedia {
        path: request.path,
        fingerprint: request.fingerprint,
        title: request.title,
        kind: request.kind,
        duration_ms: request.duration_ms,
    };
    state
        .application
        .execute("media.register", move |services| {
            services.media_analysis().register_media(input)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

/// Media library read model for triage (Phase 3.5 Slice 5): every media with
/// cached fit facts, user triage intent, and the familiar-material mark. The
/// client derives queue grouping from these facts; nothing here gates access.
pub(crate) async fn list_media_library(
    State(state): State<ApiState>,
) -> Result<Json<Vec<application::MediaLibraryEntry>>, ApiError> {
    state
        .application
        .execute("media.list_library", move |services| {
            services.media_analysis().list_media_library()
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct SetTriageIntentRequest {
    intent: Option<MediaTriageIntent>,
}

pub(crate) async fn set_media_triage_intent(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<SetTriageIntentRequest>,
) -> Result<Json<application::MediaLibraryEntry>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("media.set_triage_intent", move |services| {
            services
                .media_analysis()
                .set_media_triage_intent(&id, request.intent)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn read_media(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("media.read", move |services| {
            services.media_analysis().read_media(&id)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("media"))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ImportSubtitleRequest {
    path: String,
    language: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ImportLLTimelineForMediaQuery {
    allow_mismatch: Option<bool>,
}

pub(crate) async fn import_subtitle(
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
    let input = ImportSubtitle {
        media_id,
        source_name,
        content,
        language: request.language,
        identity_salt: None,
    };
    state
        .application
        .execute("subtitle.import", move |services| {
            services.media_analysis().import_subtitle(input)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct UpdateTrackLanguageRequest {
    language: String,
}

pub(crate) async fn update_track_language(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    Json(request): Json<UpdateTrackLanguageRequest>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let language = LanguageCode::parse(request.language).map_err(ApplicationError::from)?;
    state
        .application
        .execute("subtitle.update_language", move |services| {
            services
                .media_analysis()
                .update_track_language(&track_id, &language)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn import_lltimeline(
    State(state): State<ApiState>,
    Json(document): Json<domain::LLTimelineDocument>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    state
        .application
        .execute("lltimeline.import", move |services| {
            services
                .media_analysis()
                .import_lltimeline_document(document)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn import_lltimeline_for_media(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Query(query): Query<ImportLLTimelineForMediaQuery>,
    Json(document): Json<domain::LLTimelineDocument>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    let allow_mismatch = query.allow_mismatch.unwrap_or(false);
    state
        .application
        .execute("lltimeline.import_for_media", move |services| {
            services
                .media_analysis()
                .import_lltimeline_document_for_media(&media_id, document, allow_mismatch)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn media_subtitles(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<Vec<domain::SubtitleTrack>>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("subtitle.list_for_media", move |services| {
            services
                .media_analysis()
                .subtitle_tracks_for_media(&media_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn read_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("subtitle.read", move |services| {
            services.media_analysis().read_subtitle_track(&track_id)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("subtitle track"))
}

/// Dual-dimension content fit for one track's media (ADR 0018). Served from
/// the fingerprint-validated cache; recomputes only when transcript,
/// timelines, or the vocabulary profile changed.
pub(crate) async fn track_content_fit(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::ContentDifficultyProfile>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("media.content_fit", move |services| {
            services.media_analysis().content_fit_for_track(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct ColdStartWordsQuery {
    limit: Option<u32>,
}

pub(crate) async fn cold_start_words(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    Query(query): Query<ColdStartWordsQuery>,
) -> Result<Json<Vec<application::ColdStartWordCandidate>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let limit = query.limit.unwrap_or(20);
    state
        .application
        .execute("media.cold_start_words", move |services| {
            services
                .media_analysis()
                .cold_start_word_candidates(&track_id, limit)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("subtitle.archive", move |services| {
            services.media_analysis().archive_subtitle_track(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn restore_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("subtitle.restore", move |services| {
            services.media_analysis().restore_subtitle_track(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("subtitle.delete", move |services| {
            services.media_analysis().delete_subtitle_track(&track_id)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("subtitle track"))
}

#[derive(Debug, Deserialize)]
pub(crate) struct SubtitleExportQuery {
    format: Option<String>,
}

pub(crate) async fn export_subtitle(
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
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let track = state
        .application
        .execute("subtitle.export_read", move |services| {
            services.media_analysis().read_subtitle_track(&track_id)
        })
        .await?
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

pub(crate) fn srt_time(value: u64) -> String {
    let hours = value / 3_600_000;
    let minutes = value / 60_000 % 60;
    let seconds = value / 1_000 % 60;
    let milliseconds = value % 1_000;
    format!("{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}")
}
