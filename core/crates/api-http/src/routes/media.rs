use crate::*;

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

pub(crate) async fn read_media(
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

pub(crate) async fn import_lltimeline(
    State(state): State<ApiState>,
    Json(document): Json<domain::LLTimelineDocument>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    state
        .services
        .import_lltimeline_document(document)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn import_lltimeline_for_media(
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

pub(crate) async fn media_subtitles(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<Vec<domain::SubtitleTrack>>, ApiError> {
    state
        .services
        .subtitle_tracks_for_media(&MediaId::parse(media_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn read_subtitle(
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

pub(crate) async fn archive_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    state
        .services
        .archive_subtitle_track(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn restore_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    state
        .services
        .restore_subtitle_track(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_subtitle(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    state
        .services
        .delete_subtitle_track(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)?
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

pub(crate) fn srt_time(value: u64) -> String {
    let hours = value / 3_600_000;
    let minutes = value / 60_000 % 60;
    let seconds = value / 1_000 % 60;
    let milliseconds = value % 1_000;
    format!("{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}")
}
