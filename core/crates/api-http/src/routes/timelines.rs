use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, EventName, Json, Path, State,
    SubtitleTrackId,
};

pub(crate) async fn track_word_timings(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::WordTiming>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.word_timings", move |services| {
            services.pronunciation().word_timings_for_track(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_word_timelines(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::WordTimeline>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.list_words", move |services| {
            services.media_analysis().list_word_timelines(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_word_timeline_summaries(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::WordTimelineSummary>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.summarize_words", move |services| {
            services
                .media_analysis()
                .summarize_word_timelines(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    let timeline_id = domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.get_word", move |services| {
            services.media_analysis().get_word_timeline(&timeline_id)
        })
        .await?
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
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    let input = application::CreateWordTimeline {
        algorithm_id: request.algorithm_id,
        algorithm_version: request.algorithm_version,
        config_hash: request.config_hash,
        parent_timeline_id: request.parent_timeline_id,
        created_by: request.created_by,
        status: request.status,
        metrics_json: request.metrics_json,
        words: request.words,
    };
    state
        .application
        .execute("timeline.create_word", move |services| {
            services
                .media_analysis()
                .create_word_timeline(&track_id, input)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn export_track_lltimeline(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<domain::LLTimelineDocument>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.export_document", move |services| {
            services
                .media_analysis()
                .export_lltimeline_document(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn activate_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    let timeline_id = domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.activate_word", move |services| {
            services
                .media_analysis()
                .activate_word_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn publish_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    let timeline_id = domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.publish_word", move |services| {
            services
                .media_analysis()
                .publish_word_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    let timeline_id = domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.archive_word", move |services| {
            services
                .media_analysis()
                .archive_word_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_word_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::WordTimeline>, ApiError> {
    let timeline_id = domain::WordTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.delete_word", move |services| {
            services.media_analysis().delete_word_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_word_timing_diagnostics(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<application::SentenceWordTimingDiagnostics>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.word_diagnostics", move |services| {
            services
                .media_analysis()
                .word_timing_diagnostics_for_track(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_chunk_partitions(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<application::SentenceChunkPartition>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.chunk_partitions", move |services| {
            services
                .media_analysis()
                .chunk_partitions_for_track(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_chunk_diagnostics(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<application::SentenceChunkDiagnostics>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.chunk_diagnostics", move |services| {
            services
                .media_analysis()
                .chunk_diagnostics_for_track(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn chunk_providers(
    State(state): State<ApiState>,
) -> Result<Json<Vec<application::LearnedProsodicProviderInfo>>, ApiError> {
    state
        .application
        .execute("timeline.chunk_providers", move |services| {
            Ok(services.media_analysis().learned_prosodic_providers())
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_chunk_timelines(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::ChunkTimeline>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.list_chunks", move |services| {
            services.media_analysis().list_chunk_timelines(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_chunk_timeline_summaries(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::ChunkTimelineSummary>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.summarize_chunks", move |services| {
            services
                .media_analysis()
                .summarize_chunk_timelines(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    let timeline_id =
        domain::ChunkTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.get_chunk", move |services| {
            services.media_analysis().get_chunk_timeline(&timeline_id)
        })
        .await?
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
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.generate_chunk", move |services| {
            services
                .media_analysis()
                .generate_chunk_timeline(&track_id, status)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn activate_chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    let timeline_id =
        domain::ChunkTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.activate_chunk", move |services| {
            services
                .media_analysis()
                .activate_chunk_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    let timeline_id =
        domain::ChunkTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.archive_chunk", move |services| {
            services
                .media_analysis()
                .archive_chunk_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_chunk_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::ChunkTimeline>, ApiError> {
    let timeline_id =
        domain::ChunkTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.delete_chunk", move |services| {
            services
                .media_analysis()
                .delete_chunk_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_phone_timelines(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::PhoneTimeline>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.list_phone", move |services| {
            services.media_analysis().list_phone_timelines(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_phone_timeline_summaries(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::PhoneTimelineSummary>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.summarize_phone", move |services| {
            services
                .media_analysis()
                .summarize_phone_timelines(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn phone_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::PhoneTimeline>, ApiError> {
    let timeline_id =
        domain::PhoneTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.get_phone", move |services| {
            services
                .media_analysis()
                .get_phone_timeline(&timeline_id)?
                .ok_or(ApplicationError::NotFound("phone timeline"))
        })
        .await
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
    let timeline_id =
        domain::PhoneTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.activate_phone", move |services| {
            services
                .media_analysis()
                .activate_phone_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_phone_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::PhoneTimeline>, ApiError> {
    let timeline_id =
        domain::PhoneTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.archive_phone", move |services| {
            services
                .media_analysis()
                .archive_phone_timeline(&timeline_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_phone_timeline(
    State(state): State<ApiState>,
    Path(timeline_id): Path<String>,
) -> Result<Json<domain::PhoneTimeline>, ApiError> {
    let timeline_id =
        domain::PhoneTimelineId::parse(timeline_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.delete_phone", move |services| {
            services
                .media_analysis()
                .delete_phone_timeline(&timeline_id)
        })
        .await
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
    let total_track_id = parsed_track_id.clone();
    let total = state
        .application
        .execute("timeline.read_track_for_word_timings", move |services| {
            Ok(services
                .media_analysis()
                .read_subtitle_track(&total_track_id)?
                .ok_or(ApplicationError::NotFound("subtitle track"))?
                .sentences
                .len())
        })
        .await?;
    let _ = state.infrastructure.events.send(
        crate::event_payloads::SpeechBatchProgressPayload {
            job_id: None,
            track_id: track_id.clone(),
            processed: 0,
            total,
        }
        .envelope(EventName::WordTimingsProgress),
    );
    let values = state
        .application
        .execute(
            "timeline.generate_word_timings",
            move |services| match request {
                Some(Json(request)) if !request.timings.is_empty() => services
                    .media_analysis()
                    .store_word_timings(&parsed_track_id, &request.timings),
                _ => services
                    .pronunciation()
                    .word_timings_for_track(&parsed_track_id),
            },
        )
        .await?;
    let _ = state.infrastructure.events.send(
        crate::event_payloads::SpeechBatchProgressPayload {
            job_id: None,
            track_id: track_id.clone(),
            processed: total,
            total,
        }
        .envelope(EventName::WordTimingsProgress),
    );
    let _ = state.infrastructure.events.send(
        crate::event_payloads::WordTimingsCompletedPayload {
            job_id: None,
            track_id,
            line: None,
            count: values.len(),
            timeline_id: None,
        }
        .envelope(),
    );
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
    metrics_json: Option<domain::TimelineMetrics>,
    words: Vec<domain::WordTiming>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct GenerateChunkTimelineRequest {
    status: Option<domain::TimelineStatus>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct GenerateSenseGroupAnalysisRequest {
    status: Option<domain::TimelineStatus>,
}

pub(crate) async fn track_sense_group_analyses(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::SenseGroupAnalysis>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.list_sense_groups", move |services| {
            services
                .media_analysis()
                .list_sense_group_analyses(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn track_sense_group_analysis_summaries(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
) -> Result<Json<Vec<domain::SenseGroupAnalysisSummary>>, ApiError> {
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.summarize_sense_groups", move |services| {
            services
                .media_analysis()
                .summarize_sense_group_analyses(&track_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn generate_sense_group_analysis(
    State(state): State<ApiState>,
    Path(track_id): Path<String>,
    request: Option<Json<GenerateSenseGroupAnalysisRequest>>,
) -> Result<Json<domain::SenseGroupAnalysis>, ApiError> {
    let status = request.and_then(|Json(request)| request.status);
    let track_id = SubtitleTrackId::parse(track_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.generate_sense_group", move |services| {
            services
                .media_analysis()
                .generate_sense_group_analysis(&track_id, status)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn sense_group_analysis(
    State(state): State<ApiState>,
    Path(analysis_id): Path<String>,
) -> Result<Json<domain::SenseGroupAnalysis>, ApiError> {
    let analysis_id =
        domain::SenseGroupAnalysisId::parse(analysis_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.get_sense_group", move |services| {
            services
                .media_analysis()
                .get_sense_group_analysis(&analysis_id)?
                .ok_or(ApplicationError::NotFound("sense group analysis"))
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn activate_sense_group_analysis(
    State(state): State<ApiState>,
    Path(analysis_id): Path<String>,
) -> Result<Json<domain::SenseGroupAnalysis>, ApiError> {
    let analysis_id =
        domain::SenseGroupAnalysisId::parse(analysis_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.activate_sense_group", move |services| {
            services
                .media_analysis()
                .activate_sense_group_analysis(&analysis_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn archive_sense_group_analysis(
    State(state): State<ApiState>,
    Path(analysis_id): Path<String>,
) -> Result<Json<domain::SenseGroupAnalysis>, ApiError> {
    let analysis_id =
        domain::SenseGroupAnalysisId::parse(analysis_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.archive_sense_group", move |services| {
            services
                .media_analysis()
                .archive_sense_group_analysis(&analysis_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn delete_sense_group_analysis(
    State(state): State<ApiState>,
    Path(analysis_id): Path<String>,
) -> Result<Json<domain::SenseGroupAnalysis>, ApiError> {
    let analysis_id =
        domain::SenseGroupAnalysisId::parse(analysis_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("timeline.delete_sense_group", move |services| {
            services
                .media_analysis()
                .delete_sense_group_analysis(&analysis_id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}
