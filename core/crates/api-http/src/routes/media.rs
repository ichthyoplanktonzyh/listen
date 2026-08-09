use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, ImportSubtitle, IntoResponse, Json,
    LanguageCode, MediaId, MediaKind, MediaTriageIntent, Path, Query, RegisterMedia, Response,
    Serialize, State, StatusCode, SubtitleTrackId,
};
use tokio::io::AsyncReadExt;

/// Local subtitle imports are intentionally bounded. Eight MiB comfortably
/// covers feature-length SRT/VTT files while preventing a path request from
/// turning into an unbounded allocation.
pub(crate) const MAX_SUBTITLE_FILE_BYTES: u64 = 8 * 1024 * 1024;

#[derive(Debug, Deserialize)]
pub(crate) struct RegisterMediaRequest {
    path: String,
    fingerprint: String,
    title: String,
    kind: MediaKind,
    duration_ms: Option<u64>,
    /// Personal Library membership choice. Omitted (or null) means retained,
    /// preserving the historical behavior for old clients; explicit false
    /// registers Temporary Material (readable by media ID but absent from the
    /// media library); explicit true retains it.
    retain: Option<bool>,
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
        retain: request.retain,
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

/// Idempotent explicit learner intent to add an existing media item to the
/// Personal Library. Preserves an existing membership timestamp and routes
/// all policy through the application layer.
pub(crate) async fn retain_media(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("media.retain", move |services| {
            services.media_analysis().retain_media(&id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

/// Idempotent explicit learner intent to remove an existing media item from
/// the Personal Library. Changes membership only; the media stays registered
/// and readable, and every learner-owned record remains intact.
pub(crate) async fn unretain_media(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
) -> Result<Json<domain::MediaItem>, ApiError> {
    let id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("media.unretain", move |services| {
            services.media_analysis().unretain_media(&id)
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

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ImportContentPackageRequest {
    package_path: String,
}

#[derive(Debug, Serialize)]
pub(crate) struct ImportContentPackageResponse {
    track: domain::SubtitleTrack,
    receipt: ContentPackageImportReceipt,
}

#[derive(Debug, Serialize)]
pub(crate) struct ContentPackageImportReceipt {
    manifest_sha256: String,
    resources: Vec<ContentPackageResourceDisposition>,
    warnings: Vec<String>,
}

#[derive(Debug, Serialize)]
pub(crate) struct ContentPackageResourceDisposition {
    resource_id: String,
    kind: String,
    local_ids: Vec<String>,
    outcome: &'static str,
    reason: Option<String>,
    review_status: Option<&'static str>,
    provenance: Option<ContentPackageResourceProvenance>,
}

#[derive(Debug, Serialize)]
pub(crate) struct ContentPackageResourceProvenance {
    created_at_ms: u64,
    tool: ContentPackageResourceProducer,
    provider: Option<ContentPackageResourceProducer>,
    model: Option<ContentPackageResourceProducer>,
    config_sha256: Option<String>,
}

#[derive(Debug, Serialize)]
pub(crate) struct ContentPackageResourceProducer {
    id: String,
    version: String,
}

impl From<application::ImportedContentPackage> for ImportContentPackageResponse {
    fn from(value: application::ImportedContentPackage) -> Self {
        Self {
            track: value.track,
            receipt: ContentPackageImportReceipt {
                manifest_sha256: value.receipt.manifest_sha256,
                resources: value
                    .receipt
                    .resources
                    .into_iter()
                    .map(|resource| ContentPackageResourceDisposition {
                        resource_id: resource.resource_id,
                        kind: resource.kind,
                        local_ids: resource.local_ids,
                        outcome: match resource.outcome {
                            application::ResourceImportOutcome::Consumed => "consumed",
                            application::ResourceImportOutcome::PreservedNotConsumed => {
                                "preserved_not_consumed"
                            }
                        },
                        reason: resource.reason,
                        review_status: resource.review_status.map(|status| match status {
                            application::ResourceImportReviewStatus::Unreviewed => "unreviewed",
                            application::ResourceImportReviewStatus::MachineChecked => {
                                "machine_checked"
                            }
                            application::ResourceImportReviewStatus::HumanReviewed => {
                                "human_reviewed"
                            }
                        }),
                        provenance: resource.provenance.map(|value| {
                            ContentPackageResourceProvenance {
                                created_at_ms: value.created_at_ms,
                                tool: ContentPackageResourceProducer {
                                    id: value.tool.id,
                                    version: value.tool.version,
                                },
                                provider: value.provider.map(|producer| {
                                    ContentPackageResourceProducer {
                                        id: producer.id,
                                        version: producer.version,
                                    }
                                }),
                                model: value.model.map(|producer| ContentPackageResourceProducer {
                                    id: producer.id,
                                    version: producer.version,
                                }),
                                config_sha256: value.config_sha256,
                            }
                        }),
                    })
                    .collect(),
                warnings: value.receipt.warnings,
            },
        }
    }
}

pub(crate) async fn import_subtitle(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<ImportSubtitleRequest>,
) -> Result<Json<domain::SubtitleTrack>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    let content = read_subtitle_file(&request.path).await?;
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

pub(crate) async fn read_subtitle_file(path: &str) -> Result<Vec<u8>, ApiError> {
    let file = tokio::fs::File::open(path)
        .await
        .map_err(subtitle_read_error)?;
    let metadata = file.metadata().await.map_err(subtitle_read_error)?;
    if metadata.len() > MAX_SUBTITLE_FILE_BYTES {
        return Err(subtitle_file_too_large());
    }

    // Metadata is only an early rejection. The read itself is capped at
    // limit+1 so a file replaced or extended after metadata cannot bypass the
    // bound (TOCTOU-safe allocation and response semantics).
    let mut content = Vec::with_capacity(metadata.len().min(MAX_SUBTITLE_FILE_BYTES) as usize);
    let mut limited = file.take(MAX_SUBTITLE_FILE_BYTES + 1);
    limited
        .read_to_end(&mut content)
        .await
        .map_err(subtitle_read_error)?;
    if content.len() as u64 > MAX_SUBTITLE_FILE_BYTES {
        return Err(subtitle_file_too_large());
    }
    Ok(content)
}

fn subtitle_read_error(error: std::io::Error) -> ApiError {
    ApiError::new(
        StatusCode::BAD_REQUEST,
        "subtitle_read_error",
        error.to_string(),
        false,
    )
}

fn subtitle_file_too_large() -> ApiError {
    ApiError::new(
        StatusCode::PAYLOAD_TOO_LARGE,
        "subtitle_file_too_large",
        format!("subtitle file exceeds {MAX_SUBTITLE_FILE_BYTES} bytes"),
        false,
    )
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

pub(crate) async fn import_content_package(
    State(state): State<ApiState>,
    Path(media_id): Path<String>,
    Json(request): Json<ImportContentPackageRequest>,
) -> Result<Json<ImportContentPackageResponse>, ApiError> {
    let media_id = MediaId::parse(media_id).map_err(ApplicationError::from)?;
    if request.package_path.trim().is_empty() {
        return Err(content_package_invalid("package path must not be empty"));
    }
    let package_path = std::path::PathBuf::from(request.package_path);
    state
        .application
        .execute("content_package.import", move |services| {
            services
                .media_analysis()
                .import_content_package_path(&media_id, &package_path)
        })
        .await
        .map(ImportContentPackageResponse::from)
        .map(Json)
        .map_err(content_package_import_error)
}

fn content_package_import_error(error: ApplicationError) -> ApiError {
    match error {
        ApplicationError::NotFound(entity) => ApiError::not_found(entity),
        ApplicationError::Validation("content package media fingerprint") => ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "content_package_media_mismatch",
            "content package does not match the selected media",
            false,
        ),
        ApplicationError::Invalid(message) => content_package_invalid(message),
        ApplicationError::Domain(error) => content_package_invalid(error.to_string()),
        ApplicationError::Repository(message) => ApiError::internal(
            StatusCode::INTERNAL_SERVER_ERROR,
            "content_package_import_failed",
            "content package import failed",
            message,
            true,
        ),
        other => ApiError::internal(
            StatusCode::INTERNAL_SERVER_ERROR,
            "content_package_import_failed",
            "content package import failed",
            other.to_string(),
            false,
        ),
    }
}

fn content_package_invalid(internal_message: impl Into<String>) -> ApiError {
    ApiError::internal(
        StatusCode::UNPROCESSABLE_ENTITY,
        "content_package_invalid",
        "content package is invalid or cannot be accessed",
        internal_message,
        false,
    )
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
pub(crate) struct CalibrationSamplesQuery {
    language: Option<String>,
}

/// Offline calibration export. Predictions are uncalibrated and feedback is
/// emitted only as the observed label, preventing target leakage.
pub(crate) async fn content_fit_calibration_samples(
    State(state): State<ApiState>,
    Query(query): Query<CalibrationSamplesQuery>,
) -> Result<Json<Vec<domain::CalibrationSample>>, ApiError> {
    let language = query
        .language
        .map(LanguageCode::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    state
        .application
        .execute("media.content_fit_calibration_samples", move |services| {
            services
                .media_analysis()
                .export_calibration_samples(language.as_ref())
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
