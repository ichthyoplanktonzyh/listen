use crate::*;

pub(crate) async fn track_word_timings(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::WordTiming>>, ApiError> {
    state
        .services
        .word_timings_for_track(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_word_timelines(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::WordTimeline>>, ApiError> {
    state
        .services
        .list_word_timelines(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_word_timeline_summaries(
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

pub(crate) async fn word_timeline(
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

pub(crate) async fn export_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    word_timeline(State(state), Path(timeline_id)).await
}

pub(crate) async fn create_track_word_timeline(
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

pub(crate) async fn export_track_lltimeline(
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

pub(crate) async fn activate_word_timeline(
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

pub(crate) async fn publish_word_timeline(
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

pub(crate) async fn archive_word_timeline(
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

pub(crate) async fn delete_word_timeline(
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

pub(crate) async fn track_word_timing_diagnostics(
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

pub(crate) async fn track_chunk_partitions(
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

pub(crate) async fn track_chunk_diagnostics(
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

pub(crate) async fn chunk_providers(
    State(state): State<ApiState>,
) -> Json<Vec<application::LearnedProsodicProviderInfo>> {
    Json(state.services.learned_prosodic_providers())
}

pub(crate) async fn track_chunk_timelines(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::ChunkTimeline>>, ApiError> {
    state
        .services
        .list_chunk_timelines(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_chunk_timeline_summaries(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::ChunkTimelineSummary>>, ApiError> {
    state
        .services
        .summarize_chunk_timelines(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    state
        .services
        .get_chunk_timeline(
            &domain::ChunkTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )?
        .ok_or(ApplicationError::NotFound("chunk timeline"))
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn export_chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    chunk_timeline(State(state), Path(timeline_id)).await
}

pub(crate) async fn generate_chunk_timeline(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    request: Option<Json<GenerateChunkTimelineRequest>>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    let status = request.and_then(|Json(request)| request.status);
    state
        .services
        .generate_chunk_timeline(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
            status,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn activate_chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    state
        .services
        .activate_chunk_timeline(
            &domain::ChunkTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    state
        .services
        .archive_chunk_timeline(
            &domain::ChunkTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    state
        .services
        .delete_chunk_timeline(
            &domain::ChunkTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_phone_timelines(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::PhoneTimeline>>, ApiError> {
    state
        .services
        .list_phone_timelines(&SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_phone_timeline_summaries(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::PhoneTimelineSummary>>, ApiError> {
    state
        .services
        .summarize_phone_timelines(
            &SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn phone_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::PhoneTimeline>, ApiError> {
    state
        .services
        .get_phone_timeline(
            &domain::PhoneTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )?
        .ok_or(ApplicationError::NotFound("phone timeline"))
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn export_phone_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::PhoneTimeline>, ApiError> {
    phone_timeline(State(state), Path(timeline_id)).await
}

pub(crate) async fn activate_phone_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::PhoneTimeline>, ApiError> {
    state
        .services
        .activate_phone_timeline(
            &domain::PhoneTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_phone_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::PhoneTimeline>, ApiError> {
    state
        .services
        .archive_phone_timeline(
            &domain::PhoneTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_phone_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::PhoneTimeline>, ApiError> {
    state
        .services
        .delete_phone_timeline(
            &domain::PhoneTimelineId::parse(timeline_id).map_err(ApplicationError::from)?,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn generate_track_word_timings(
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
pub(crate) struct WordTimingsRequest {
    timings: Vec<domain::WordTiming>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateWordTimelineRequest {
    algorithm_id: Option<String>,
    algorithm_version: Option<String>,
    config_hash: Option<String>,
    parent_timeline_id: Option<domain::WordTimelineId>,
    created_by: Option<domain::TimelineCreator>,
    status: Option<domain::TimelineStatus>,
    metrics_json: Option<serde_json::Value>,
    words: Vec<domain::WordTiming>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct GenerateChunkTimelineRequest {
    status: Option<domain::TimelineStatus>,
}
