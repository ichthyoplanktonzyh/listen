use domain::{LexicalEntryId, MediaId, ReadingPosition, SubtitleSentenceId};

use crate::{ApiError, ApiState, ApplicationError, Deserialize, Json, Path, State, StatusCode};

pub(crate) async fn reading_position(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Option<ReadingPosition>>, ApiError> {
    state
        .application
        .execute("reading.position", move |services| {
            services.reading().reading_position(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct SaveReadingPositionRequest {
    pub media_id: Option<String>,
    pub anchor_cue_id: String,
    pub paragraph_index: u32,
}

pub(crate) async fn save_reading_position(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    Json(request): Json<SaveReadingPositionRequest>,
) -> Result<Json<ReadingPosition>, ApiError> {
    let media_id = request.media_id;
    let anchor_cue_id = request.anchor_cue_id;
    let paragraph_index = request.paragraph_index;
    state
        .application
        .execute("reading.save_position", move |services| {
            services.reading().save_reading_position(
                &track_id,
                media_id.as_deref(),
                &anchor_cue_id,
                paragraph_index,
            )
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct ReadingMarkingRequest {
    pub lexical_entry_id: String,
    #[serde(default)]
    pub sentence_id: Option<String>,
    pub surface_form: String,
    #[serde(default)]
    pub media_id: Option<String>,
    pub translation_visible: bool,
    pub understood: bool,
}

/// Explicit reading-posture word marking (Phase 3.13 Slice 5): writes one
/// reading-channel observation. Paragraph task results never route here.
pub(crate) async fn record_reading_marking(
    State(state): State<ApiState>,
    Json(request): Json<ReadingMarkingRequest>,
) -> Result<StatusCode, ApiError> {
    let lexical_entry_id =
        LexicalEntryId::parse(request.lexical_entry_id).map_err(ApplicationError::from)?;
    let sentence_id = request
        .sentence_id
        .map(SubtitleSentenceId::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    let media_id = request
        .media_id
        .map(MediaId::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    let surface_form = request.surface_form;
    let translation_visible = request.translation_visible;
    let understood = request.understood;
    state
        .application
        .execute("reading.record_marking", move |services| {
            services.lexical_learning().record_reading_marking(
                &lexical_entry_id,
                sentence_id.as_ref(),
                &surface_form,
                media_id,
                translation_visible,
                understood,
            )
        })
        .await
        .map(|_| StatusCode::NO_CONTENT)
        .map_err(ApiError::from)
}
