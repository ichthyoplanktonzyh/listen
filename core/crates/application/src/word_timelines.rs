use std::collections::{HashMap, HashSet};

use crate::{
    ApplicationError, ChunkTimeline, ContentPackageCandidateImport, CreateWordTimeline,
    LLTIMELINE_SCHEMA_V1, LLTimelineArtifact, LLTimelineDocument, LLTimelineGenerator,
    LLTimelineImport, LLTimelineMedia, LLTimelineMetadata, LLTimelineRhythmFrame,
    MediaAnalysisUseCases, MediaAvailability, MediaId, MediaItem, MediaKind, PhoneTimeline,
    ProsodyAnalysis, RhythmFrameId, SenseGroupAnalysis, SentenceWordTimingDiagnostics,
    SubtitleSentenceId, SubtitleTrack, SubtitleTrackId, SubtitleTrackStatus, TimeMs,
    TimelineCreator, TimelineMetrics, TimelineStatus, WordTimeline, WordTimelineId,
    WordTimelineSummary, WordTimingBoundaryDiagnostic, build_word_timeline, detached_media_path,
    lltimeline_segments_from_track, lltimeline_segments_to_sentences, lltimeline_track_extra,
    lltimeline_track_fingerprint, lltimeline_track_id, mark_word_timeline_published,
    merge_lltimeline_track_extra, now_ms, remap_lltimeline_identity, require_text,
    validate_word_timeline_words, word_timeline_summary,
};

const RHYTHM_FRAME_PROVIDER_ID: &str = "wordtimeline-rhythm-frame";
const RHYTHM_FRAME_PROVIDER_VERSION: &str = "phase-2.21-w2";
const RHYTHM_WORD_ACOUSTIC_CUES_ARTIFACT_KIND: &str = "rhythm_word_acoustic_cues";

fn rhythm_word_acoustic_cues_by_sentence(
    artifacts: &[LLTimelineArtifact],
    word_timeline_id: Option<&WordTimelineId>,
) -> HashMap<SubtitleSentenceId, Vec<speech_analysis::audible_structure::RhythmWordAcousticCue>> {
    let mut values: HashMap<
        SubtitleSentenceId,
        Vec<speech_analysis::audible_structure::RhythmWordAcousticCue>,
    > = HashMap::new();
    let Some(word_timeline_id) = word_timeline_id else {
        return values;
    };
    for artifact in artifacts {
        if artifact.kind != RHYTHM_WORD_ACOUSTIC_CUES_ARTIFACT_KIND {
            continue;
        }
        if artifact
            .payload
            .get("timeline_id")
            .and_then(serde_json::Value::as_str)
            .is_some_and(|timeline_id| timeline_id != word_timeline_id.as_str())
        {
            continue;
        }
        let Some(cues) = artifact
            .payload
            .get("cues")
            .and_then(serde_json::Value::as_array)
        else {
            continue;
        };
        for cue in cues {
            let Some(sentence_id) = cue
                .get("sentence_id")
                .and_then(serde_json::Value::as_str)
                .and_then(|value| SubtitleSentenceId::parse(value).ok())
            else {
                continue;
            };
            let Some(token_index) = cue
                .get("token_index")
                .and_then(serde_json::Value::as_u64)
                .and_then(|value| u32::try_from(value).ok())
            else {
                continue;
            };
            let energy_prominence = cue
                .get("energy_prominence")
                .and_then(serde_json::Value::as_f64)
                .filter(|value| value.is_finite())
                .map(|value| (value as f32).clamp(0.0, 1.0));
            let pitch_prominence = cue
                .get("pitch_prominence")
                .and_then(serde_json::Value::as_f64)
                .filter(|value| value.is_finite())
                .map(|value| (value as f32).clamp(0.0, 1.0));
            let pitch_reset_after = cue
                .get("pitch_reset_after")
                .and_then(serde_json::Value::as_f64)
                .filter(|value| value.is_finite())
                .map(|value| (value as f32).clamp(0.0, 1.0));
            if energy_prominence.is_none()
                && pitch_prominence.is_none()
                && pitch_reset_after.is_none()
            {
                continue;
            }
            values.entry(sentence_id).or_default().push(
                speech_analysis::audible_structure::RhythmWordAcousticCue {
                    token_index,
                    energy_prominence,
                    pitch_prominence,
                    pitch_reset_after,
                },
            );
        }
    }
    values
}

fn rhythm_word_acoustic_artifact_timeline_id(
    artifact: &LLTimelineArtifact,
) -> Option<WordTimelineId> {
    if artifact.kind != RHYTHM_WORD_ACOUSTIC_CUES_ARTIFACT_KIND {
        return None;
    }
    artifact
        .payload
        .get("timeline_id")
        .and_then(serde_json::Value::as_str)
        .and_then(|value| WordTimelineId::parse(value.to_owned()).ok())
}

fn word_timeline_line(timeline: &WordTimeline) -> Option<&str> {
    timeline
        .metrics_json
        .as_object()
        .get("line")
        .and_then(serde_json::Value::as_str)
}

fn select_rhythm_source_word_timeline_id(
    word_timelines: &[WordTimeline],
    active_word_timeline_id: Option<&WordTimelineId>,
    artifacts: &[LLTimelineArtifact],
) -> Option<WordTimelineId> {
    for artifact in artifacts.iter().rev() {
        let Some(timeline_id) = rhythm_word_acoustic_artifact_timeline_id(artifact) else {
            continue;
        };
        if word_timelines.iter().any(|timeline| {
            timeline.id == timeline_id && timeline.status != TimelineStatus::Archived
        }) {
            return Some(timeline_id);
        }
    }
    word_timelines
        .iter()
        .filter(|timeline| {
            timeline.status != TimelineStatus::Archived
                && word_timeline_line(timeline) == Some("sound")
        })
        .max_by_key(|timeline| timeline.updated_at_ms)
        .map(|timeline| timeline.id.clone())
        .or_else(|| active_word_timeline_id.cloned())
        .or_else(|| {
            word_timelines
                .iter()
                .filter(|timeline| {
                    timeline.status != TimelineStatus::Archived
                        && word_timeline_line(timeline) == Some("text")
                        && timeline
                            .metrics_json
                            .as_object()
                            .get("preparation_input_fingerprint")
                            .and_then(serde_json::Value::as_str)
                            .is_some()
                })
                .max_by_key(|timeline| timeline.updated_at_ms)
                .map(|timeline| timeline.id.clone())
        })
}

fn prepare_active_selection<T, I: Eq>(
    items: &mut [T],
    active_id: Option<&I>,
    item_id: impl Fn(&T) -> &I,
    status: impl Fn(&mut T) -> &mut TimelineStatus,
    field: &'static str,
) -> Result<(), ApplicationError> {
    let mut found = active_id.is_none();
    for item in items {
        let selected = active_id.is_some_and(|active_id| item_id(item) == active_id);
        let item_status = status(item);
        if selected {
            found = true;
            if *item_status == TimelineStatus::Archived {
                return Err(ApplicationError::Invalid(format!("{field} is archived")));
            }
            *item_status = TimelineStatus::Active;
        } else if *item_status == TimelineStatus::Active {
            *item_status = TimelineStatus::Candidate;
        }
    }
    if found {
        Ok(())
    } else {
        Err(ApplicationError::Invalid(format!(
            "{field} is not in the document"
        )))
    }
}

fn validate_and_prepare_lltimeline_resources(
    document: &mut LLTimelineDocument,
    track: &SubtitleTrack,
) -> Result<(), ApplicationError> {
    let sentence_ids = track
        .sentences
        .iter()
        .map(|sentence| sentence.id.clone())
        .collect::<HashSet<_>>();
    let word_ids = document
        .word_timelines
        .iter()
        .map(|timeline| timeline.id.clone())
        .collect::<HashSet<_>>();
    if word_ids.len() != document.word_timelines.len() {
        return Err(ApplicationError::Invalid(
            "duplicate LLTimeline word timeline id".into(),
        ));
    }
    for timeline in &document.word_timelines {
        if timeline.media_id != track.media_id || timeline.track_id != track.id {
            return Err(ApplicationError::Invalid(
                "LLTimeline word timeline belongs to another source".into(),
            ));
        }
        if timeline
            .parent_timeline_id
            .as_ref()
            .is_some_and(|parent| !word_ids.contains(parent))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline word timeline parent is missing".into(),
            ));
        }
        if timeline
            .words
            .iter()
            .any(|word| !sentence_ids.contains(&word.sentence_id))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline word timing sentence is missing".into(),
            ));
        }
    }
    prepare_active_selection(
        &mut document.word_timelines,
        document.active_word_timeline_id.as_ref(),
        |timeline: &WordTimeline| &timeline.id,
        |timeline: &mut WordTimeline| &mut timeline.status,
        "active_word_timeline_id",
    )?;

    let phone_ids = document
        .phone_timelines
        .iter()
        .map(|timeline| timeline.id.clone())
        .collect::<HashSet<_>>();
    if phone_ids.len() != document.phone_timelines.len() {
        return Err(ApplicationError::Invalid(
            "duplicate LLTimeline phone timeline id".into(),
        ));
    }
    for timeline in &document.phone_timelines {
        if timeline.media_id != track.media_id || timeline.track_id != track.id {
            return Err(ApplicationError::Invalid(
                "LLTimeline phone timeline belongs to another source".into(),
            ));
        }
        if timeline
            .sentence_id
            .as_ref()
            .is_some_and(|sentence| !sentence_ids.contains(sentence))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline phone timeline sentence is missing".into(),
            ));
        }
        if timeline
            .parent_word_timeline_id
            .as_ref()
            .is_some_and(|parent| !word_ids.contains(parent))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline phone timeline parent is missing".into(),
            ));
        }
    }
    prepare_active_selection(
        &mut document.phone_timelines,
        document.active_phone_timeline_id.as_ref(),
        |timeline: &PhoneTimeline| &timeline.id,
        |timeline: &mut PhoneTimeline| &mut timeline.status,
        "active_phone_timeline_id",
    )?;

    let chunk_ids = document
        .chunk_timelines
        .iter()
        .map(|timeline| timeline.id.clone())
        .collect::<HashSet<_>>();
    if chunk_ids.len() != document.chunk_timelines.len() {
        return Err(ApplicationError::Invalid(
            "duplicate LLTimeline chunk timeline id".into(),
        ));
    }
    for timeline in &document.chunk_timelines {
        if timeline.media_id != track.media_id || timeline.track_id != track.id {
            return Err(ApplicationError::Invalid(
                "LLTimeline chunk timeline belongs to another source".into(),
            ));
        }
        if timeline
            .parent_word_timeline_id
            .as_ref()
            .is_some_and(|parent| !word_ids.contains(parent))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline chunk timeline parent is missing".into(),
            ));
        }
        if timeline
            .chunks
            .iter()
            .any(|chunk| !sentence_ids.contains(&chunk.sentence_id))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline chunk sentence is missing".into(),
            ));
        }
    }
    prepare_active_selection(
        &mut document.chunk_timelines,
        document.active_chunk_timeline_id.as_ref(),
        |timeline: &ChunkTimeline| &timeline.id,
        |timeline: &mut ChunkTimeline| &mut timeline.status,
        "active_chunk_timeline_id",
    )?;

    let sense_group_ids = document
        .sense_group_analyses
        .iter()
        .map(|analysis| analysis.id.clone())
        .collect::<HashSet<_>>();
    if sense_group_ids.len() != document.sense_group_analyses.len() {
        return Err(ApplicationError::Invalid(
            "duplicate LLTimeline sense-group analysis id".into(),
        ));
    }
    for analysis in &document.sense_group_analyses {
        if analysis.media_id != track.media_id || analysis.track_id != track.id {
            return Err(ApplicationError::Invalid(
                "LLTimeline sense-group analysis belongs to another source".into(),
            ));
        }
        if analysis
            .parent_word_timeline_id
            .as_ref()
            .is_some_and(|parent| !word_ids.contains(parent))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline sense-group analysis parent is missing".into(),
            ));
        }
        if analysis
            .groups
            .iter()
            .any(|group| !sentence_ids.contains(&group.sentence_id))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline sense-group sentence is missing".into(),
            ));
        }
    }
    prepare_active_selection(
        &mut document.sense_group_analyses,
        document.active_sense_group_analysis_id.as_ref(),
        |analysis: &SenseGroupAnalysis| &analysis.id,
        |analysis: &mut SenseGroupAnalysis| &mut analysis.status,
        "active_sense_group_analysis_id",
    )?;

    let prosody_ids = document
        .prosody_analyses
        .iter()
        .map(|analysis| analysis.id.clone())
        .collect::<HashSet<_>>();
    if prosody_ids.len() != document.prosody_analyses.len() {
        return Err(ApplicationError::Invalid(
            "duplicate LLTimeline prosody analysis id".into(),
        ));
    }
    for analysis in &document.prosody_analyses {
        if analysis.media_id != track.media_id || analysis.track_id != track.id {
            return Err(ApplicationError::Invalid(
                "LLTimeline prosody analysis belongs to another source".into(),
            ));
        }
        if analysis
            .parent_word_timeline_id
            .as_ref()
            .is_some_and(|parent| !word_ids.contains(parent))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline prosody analysis parent is missing".into(),
            ));
        }
        if analysis
            .anchors
            .iter()
            .any(|anchor| !sentence_ids.contains(&anchor.word_ref.sentence_id))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline prosody anchor sentence is missing".into(),
            ));
        }
        if analysis.chunks.iter().any(|chunk| {
            !sentence_ids.contains(&chunk.sentence_id)
                || chunk.start_token_index > chunk.end_token_index
                || chunk.nucleus_token_index.is_some_and(|index| {
                    index < chunk.start_token_index || index > chunk.end_token_index
                })
                || !track.sentences.iter().any(|sentence| {
                    sentence.id == chunk.sentence_id
                        && sentence
                            .tokens
                            .iter()
                            .any(|token| token.index == chunk.start_token_index)
                        && sentence
                            .tokens
                            .iter()
                            .any(|token| token.index == chunk.end_token_index)
                })
        }) {
            return Err(ApplicationError::Invalid(
                "LLTimeline prosodic chunk span is invalid".into(),
            ));
        }
    }
    prepare_active_selection(
        &mut document.prosody_analyses,
        document.active_prosody_analysis_id.as_ref(),
        |analysis: &ProsodyAnalysis| &analysis.id,
        |analysis: &mut ProsodyAnalysis| &mut analysis.status,
        "active_prosody_analysis_id",
    )?;

    let rhythm_ids = document
        .rhythm_frames
        .iter()
        .map(|frame| frame.id.clone())
        .collect::<HashSet<_>>();
    if rhythm_ids.len() != document.rhythm_frames.len() {
        return Err(ApplicationError::Invalid(
            "duplicate LLTimeline rhythm frame id".into(),
        ));
    }
    for frame in &document.rhythm_frames {
        if frame.media_id != track.media_id || frame.track_id != track.id {
            return Err(ApplicationError::Invalid(
                "LLTimeline rhythm frame belongs to another source".into(),
            ));
        }
        if !sentence_ids.contains(&frame.sentence_id) {
            return Err(ApplicationError::Invalid(
                "LLTimeline rhythm frame sentence is missing".into(),
            ));
        }
        if frame
            .parent_word_timeline_id
            .as_ref()
            .is_some_and(|parent| !word_ids.contains(parent))
        {
            return Err(ApplicationError::Invalid(
                "LLTimeline rhythm frame parent is missing".into(),
            ));
        }
    }
    Ok(())
}

impl MediaAnalysisUseCases {
    pub(crate) fn store_rhythm_word_acoustic_analysis(
        &self,
        track_id: &SubtitleTrackId,
        timeline_id: &WordTimelineId,
        analysis: &speech_analysis::timing::WordAcousticAnalysis,
    ) -> Result<usize, ApplicationError> {
        let document = self.export_lltimeline_document(track_id)?;
        if !document
            .word_timelines
            .iter()
            .any(|timeline| &timeline.id == timeline_id)
        {
            return Err(ApplicationError::NotFound("word timeline"));
        }
        let mut artifacts = document.artifacts;
        artifacts.retain(|artifact| {
            artifact.kind != RHYTHM_WORD_ACOUSTIC_CUES_ARTIFACT_KIND
                || artifact
                    .payload
                    .get("timeline_id")
                    .and_then(serde_json::Value::as_str)
                    .is_some_and(|value| value != timeline_id.as_str())
        });
        artifacts.push(LLTimelineArtifact {
            kind: RHYTHM_WORD_ACOUSTIC_CUES_ARTIFACT_KIND.into(),
            provider_id: Some(speech_analysis::timing::WORD_ACOUSTICS_PROVIDER_ID.into()),
            provider_version: Some(speech_analysis::timing::WORD_ACOUSTICS_PROVIDER_VERSION.into()),
            payload: serde_json::json!({
                "status": "scored",
                "line": "sound",
                "timeline_id": timeline_id.as_str(),
                "sample_rate_hz": analysis.sample_rate_hz,
                "calibration": {
                    "energy": "sentence_median_dbfs_delta_v1",
                    "pitch": "normalized_autocorrelation_word_range_reset_v1",
                },
                "cue_count": analysis.cues.len(),
                "positive_energy_cue_count": analysis.positive_energy_cue_count(),
                "positive_pitch_cue_count": analysis.positive_pitch_cue_count(),
                "cues": analysis.cues,
            }),
        });
        self.lltimeline_resources.save_lltimeline_resource(
            track_id,
            &document.metadata,
            &artifacts,
        )?;
        Ok(analysis.cues.len())
    }

    pub fn list_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimeline>, ApplicationError> {
        self.word_timelines.list_word_timelines(track_id)
    }

    pub fn summarize_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimelineSummary>, ApplicationError> {
        let timelines = self.word_timelines.list_word_timelines(track_id)?;
        Ok(timelines
            .iter()
            .map(word_timeline_summary)
            .collect::<Vec<_>>())
    }

    pub fn get_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        self.word_timelines.get_word_timeline(id)
    }

    pub fn create_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
        input: CreateWordTimeline,
    ) -> Result<WordTimeline, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let words = validate_word_timeline_words(&track, &input.words)?;
        let requested_status = input.status.unwrap_or(TimelineStatus::Candidate);
        let mut timeline = build_word_timeline(
            &track,
            words,
            input.algorithm_id,
            input.algorithm_version,
            input.config_hash,
            input.parent_timeline_id,
            input.created_by,
            requested_status,
            input.metrics_json,
        )?;
        if requested_status == TimelineStatus::Active {
            timeline.status = TimelineStatus::Candidate;
        }
        let timeline = self.word_timelines.save_word_timeline(&timeline)?;
        let timeline = if requested_status == TimelineStatus::Active {
            self.word_timelines.activate_word_timeline(&timeline.id)?
        } else {
            timeline
        };
        self.reindex_track_corpus(&timeline.track_id)?;
        Ok(timeline)
    }

    /// Materializes the pronunciation timing cache as the active text-line
    /// timeline used by foundation preparation.
    pub fn create_foundation_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
        preparation_input_fingerprint: &str,
    ) -> Result<WordTimeline, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        if let Some(existing) = self
            .word_timelines
            .list_word_timelines(track_id)?
            .into_iter()
            .find(|timeline| {
                timeline.track_id == track.id
                    && timeline.media_id == track.media_id
                    && timeline.status != TimelineStatus::Archived
                    && !timeline.words.is_empty()
                    && timeline
                        .metrics_json
                        .as_object()
                        .get("line")
                        .and_then(serde_json::Value::as_str)
                        == Some("text")
                    && timeline
                        .metrics_json
                        .as_object()
                        .get("preparation_input_fingerprint")
                        .and_then(serde_json::Value::as_str)
                        == Some(preparation_input_fingerprint)
            })
        {
            let active = self
                .word_timelines
                .activate_word_timeline_if_absent(&existing.id)?;
            if active.id == existing.id {
                self.reindex_track_corpus(&active.track_id)?;
                return Ok(active);
            }
            return Ok(existing);
        }
        let mut words = Vec::new();
        for sentence in &track.sentences {
            words.extend(self.pronunciation().word_timings(&sentence.id)?);
        }
        let timeline = self.create_word_timeline(
            track_id,
            crate::CreateWordTimeline {
                algorithm_id: Some("foundation-pronunciation-timing".into()),
                algorithm_version: Some("v1".into()),
                config_hash: Some(preparation_input_fingerprint.into()),
                parent_timeline_id: None,
                created_by: Some(TimelineCreator::Algorithm),
                status: Some(TimelineStatus::Candidate),
                metrics_json: Some(
                    serde_json::json!({
                        "line": "text",
                        "preparation_input_fingerprint": preparation_input_fingerprint,
                    })
                    .into(),
                ),
                words,
            },
        )?;
        let active = self
            .word_timelines
            .activate_word_timeline_if_absent(&timeline.id)?;
        if active.id == timeline.id {
            self.reindex_track_corpus(&active.track_id)?;
            Ok(active)
        } else {
            Ok(timeline)
        }
    }

    pub fn activate_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        let timeline = self.word_timelines.activate_word_timeline(id)?;
        // Rhythm frames derive from word timelines, so the corpus family
        // projection (Phase 3.9) is stale after any lifecycle change here.
        self.reindex_track_corpus(&timeline.track_id)?;
        Ok(timeline)
    }

    pub fn archive_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        let timeline = self.word_timelines.archive_word_timeline(id)?;
        self.reindex_track_corpus(&timeline.track_id)?;
        Ok(timeline)
    }

    pub fn publish_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        let mut timeline = self
            .word_timelines
            .get_word_timeline(id)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        if timeline.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived word timeline"));
        }
        mark_word_timeline_published(&mut timeline);
        timeline.updated_at_ms = now_ms();
        let timeline = self.word_timelines.save_word_timeline(&timeline)?;
        let timeline = self.word_timelines.activate_word_timeline(&timeline.id)?;
        self.reindex_track_corpus(&timeline.track_id)?;
        Ok(timeline)
    }

    pub fn delete_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        let timeline = self.word_timelines.delete_word_timeline(id)?;
        self.reindex_track_corpus(&timeline.track_id)?;
        Ok(timeline)
    }

    pub fn word_timing_diagnostics_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SentenceWordTimingDiagnostics>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        track
            .sentences
            .iter()
            .filter_map(|sentence| {
                let timings = match self.pronunciation().word_timings(&sentence.id) {
                    Ok(timings) => timings,
                    Err(error) => return Some(Err(error)),
                };
                if timings.is_empty() {
                    return None;
                }
                Some(Ok(SentenceWordTimingDiagnostics {
                    sentence_id: sentence.id.clone(),
                    boundaries: timings
                        .windows(2)
                        .map(|pair| WordTimingBoundaryDiagnostic {
                            left_token_index: pair[0].token_index,
                            right_token_index: pair[1].token_index,
                            left_end_ms: pair[0].end_ms,
                            right_start_ms: pair[1].start_ms,
                            gap_ms: pair[1].start_ms.saturating_sub(pair[0].end_ms),
                            left_timing_source: pair[0].timing_source,
                            right_timing_source: pair[1].timing_source,
                            left_provider_id: pair[0].provider_id.clone(),
                            left_provider_version: pair[0].provider_version.clone(),
                            right_provider_id: pair[1].provider_id.clone(),
                            right_provider_version: pair[1].provider_version.clone(),
                        })
                        .collect(),
                }))
            })
            .collect()
    }

    pub fn export_lltimeline_document(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<LLTimelineDocument, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let media = self
            .media
            .get(&track.media_id)?
            .ok_or(ApplicationError::NotFound("media item"))?;
        let word_timelines = self.word_timelines.list_word_timelines(track_id)?;
        let active_word_timeline_id = word_timelines
            .iter()
            .find(|timeline| timeline.status == TimelineStatus::Active)
            .map(|timeline| timeline.id.clone());
        let chunk_timelines = self.chunk_timelines.list_chunk_timelines(track_id)?;
        let active_chunk_timeline_id = chunk_timelines
            .iter()
            .find(|timeline| timeline.status == TimelineStatus::Active)
            .map(|timeline| timeline.id.clone());
        let phone_timelines = self.phone_timelines.list_phone_timelines(track_id)?;
        let active_phone_timeline_id = phone_timelines
            .iter()
            .find(|timeline| timeline.status == TimelineStatus::Active)
            .map(|timeline| timeline.id.clone());
        let persisted_resource = self
            .lltimeline_resources
            .get_lltimeline_resource(track_id)?;
        let (metadata, artifacts) = if let Some((mut metadata, artifacts)) = persisted_resource {
            metadata.media = LLTimelineMedia {
                id: media.id,
                fingerprint: media.fingerprint,
                path: Some(media.path),
                title: media.title,
                duration_ms: media.duration.map(TimeMs::get),
            };
            metadata.language = track.language.clone();
            metadata.human_reviewed = metadata.human_reviewed
                || word_timelines.iter().any(|timeline| {
                    timeline.status == TimelineStatus::Active
                        && timeline.created_by == TimelineCreator::User
                });
            metadata.extra = merge_lltimeline_track_extra(
                metadata.extra,
                &track.id,
                &track.fingerprint,
                &track.source,
            );
            (metadata, artifacts)
        } else {
            (
                LLTimelineMetadata {
                    created_at_ms: now_ms(),
                    generator: LLTimelineGenerator {
                        id: "llplayernext".into(),
                        version: env!("CARGO_PKG_VERSION").into(),
                        mode: "production_engine".into(),
                    },
                    media: LLTimelineMedia {
                        id: media.id,
                        fingerprint: media.fingerprint,
                        path: Some(media.path),
                        title: media.title,
                        duration_ms: media.duration.map(TimeMs::get),
                    },
                    language: track.language.clone(),
                    human_reviewed: word_timelines.iter().any(|timeline| {
                        timeline.status == TimelineStatus::Active
                            && timeline.created_by == TimelineCreator::User
                    }),
                    extra: lltimeline_track_extra(&track.id, &track.fingerprint, &track.source),
                },
                Vec::new(),
            )
        };
        let rhythm_source_word_timeline_id = select_rhythm_source_word_timeline_id(
            &word_timelines,
            active_word_timeline_id.as_ref(),
            &artifacts,
        );
        let word_acoustic_cues = rhythm_word_acoustic_cues_by_sentence(
            &artifacts,
            rhythm_source_word_timeline_id.as_ref(),
        );
        let rhythm_frames = self.rhythm_frames_from_word_timeline(
            &track,
            &word_timelines,
            rhythm_source_word_timeline_id.as_ref(),
            active_word_timeline_id.as_ref(),
            &word_acoustic_cues,
        )?;
        let sense_group_analyses = self.sense_groups.list_sense_group_analyses(track_id)?;
        let active_sense_group_analysis_id = sense_group_analyses
            .iter()
            .find(|a| a.status == TimelineStatus::Active)
            .map(|a| a.id.clone());
        let prosody_analyses = self.prosody.list_prosody_analyses(track_id)?;
        let active_prosody_analysis_id = prosody_analyses
            .iter()
            .find(|a| a.status == TimelineStatus::Active)
            .map(|a| a.id.clone());
        Ok(LLTimelineDocument {
            schema: LLTIMELINE_SCHEMA_V1.to_owned(),
            metadata,
            segments: lltimeline_segments_from_track(&track),
            word_timelines,
            active_word_timeline_id,
            phone_timelines,
            active_phone_timeline_id,
            rhythm_frames,
            chunk_timelines,
            active_chunk_timeline_id,
            sense_group_analyses,
            active_sense_group_analysis_id,
            prosody_analyses,
            active_prosody_analysis_id,
            artifacts,
        })
    }

    pub fn import_lltimeline_document(
        &self,
        document: LLTimelineDocument,
    ) -> Result<SubtitleTrack, ApplicationError> {
        self.import_lltimeline_document_with_media(document, None)
    }

    fn import_lltimeline_document_with_media(
        &self,
        mut document: LLTimelineDocument,
        attached_media: Option<MediaItem>,
    ) -> Result<SubtitleTrack, ApplicationError> {
        if document.schema != LLTIMELINE_SCHEMA_V1 {
            return Err(ApplicationError::Validation("lltimeline schema"));
        }
        require_text(&document.metadata.media.fingerprint, "media fingerprint")?;
        require_text(&document.metadata.media.title, "media title")?;
        let (media, media_to_create) = match attached_media {
            Some(media) => (media, None),
            None => {
                if let Some(existing) = self.media.get(&document.metadata.media.id)? {
                    if existing.fingerprint != document.metadata.media.fingerprint {
                        return Err(ApplicationError::Conflict(
                            "lltimeline media identity has a different fingerprint",
                        ));
                    }
                    (existing, None)
                } else {
                    let now = now_ms();
                    let media = MediaItem {
                        id: document.metadata.media.id.clone(),
                        // A path in an LLTimeline document is a source snapshot. The
                        // detached import endpoint has not attached or verified live
                        // media, so it must never expose that snapshot as playable.
                        path: detached_media_path(&document.metadata.media.id),
                        fingerprint: document.metadata.media.fingerprint.clone(),
                        title: document.metadata.media.title.clone(),
                        kind: MediaKind::Video,
                        duration: document.metadata.media.duration_ms.map(TimeMs::new),
                        availability: MediaAvailability::Missing,
                        created_at_ms: now,
                        updated_at_ms: now,
                    };
                    (media.clone(), Some(media))
                }
            }
        };

        let track_id = lltimeline_track_id(&document)?;
        let fingerprint = lltimeline_track_fingerprint(&document);
        let source = document
            .metadata
            .extra
            .get("track_source")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("lltimeline-json-v1")
            .to_owned();
        let track = SubtitleTrack {
            id: track_id,
            media_id: media.id.clone(),
            fingerprint,
            language: document.metadata.language.clone(),
            source,
            status: SubtitleTrackStatus::Available,
            sentences: lltimeline_segments_to_sentences(&document.segments)?,
        };
        validate_and_prepare_lltimeline_resources(&mut document, &track)?;
        let imported_word_ids = document
            .word_timelines
            .iter()
            .map(|timeline| timeline.id.clone())
            .collect::<HashSet<_>>();
        let mut effective_word_timelines = self.word_timelines.list_word_timelines(&track.id)?;
        effective_word_timelines.retain(|timeline| !imported_word_ids.contains(&timeline.id));
        for timeline in &mut effective_word_timelines {
            if timeline.status == TimelineStatus::Active {
                timeline.status = TimelineStatus::Candidate;
            }
        }
        effective_word_timelines.extend(document.word_timelines.iter().cloned());
        let rhythm_source_word_timeline_id = select_rhythm_source_word_timeline_id(
            &effective_word_timelines,
            document.active_word_timeline_id.as_ref(),
            &document.artifacts,
        );
        let word_acoustic_cues = rhythm_word_acoustic_cues_by_sentence(
            &document.artifacts,
            rhythm_source_word_timeline_id.as_ref(),
        );
        let canonical_rhythm_frames = self.rhythm_frames_from_word_timeline(
            &track,
            &effective_word_timelines,
            rhythm_source_word_timeline_id.as_ref(),
            document.active_word_timeline_id.as_ref(),
            &word_acoustic_cues,
        )?;
        let active_chunk_timeline = document.active_chunk_timeline_id.as_ref().and_then(|id| {
            document
                .chunk_timelines
                .iter()
                .find(|timeline| &timeline.id == id)
        });
        let corpus_occurrences = self.build_subtitle_corpus_occurrences_from_resources(
            &track,
            active_chunk_timeline,
            &canonical_rhythm_frames,
        )?;
        let import = LLTimelineImport {
            media_to_create,
            track: track.clone(),
            metadata: document.metadata,
            artifacts: document.artifacts,
            word_timelines: document.word_timelines,
            phone_timelines: document.phone_timelines,
            chunk_timelines: document.chunk_timelines,
            sense_group_analyses: document.sense_group_analyses,
            prosody_analyses: document.prosody_analyses,
            corpus_occurrences,
        };
        self.lltimeline_imports.import_lltimeline(&import)?;

        Ok(track)
    }

    pub(crate) fn import_content_package_document_with_media(
        &self,
        mut document: LLTimelineDocument,
        media: MediaItem,
    ) -> Result<SubtitleTrack, ApplicationError> {
        if document.schema != LLTIMELINE_SCHEMA_V1 {
            return Err(ApplicationError::Validation("lltimeline schema"));
        }
        require_text(&document.metadata.media.fingerprint, "media fingerprint")?;
        require_text(&document.metadata.media.title, "media title")?;
        if document.metadata.media.id != media.id
            || document.metadata.media.fingerprint != media.fingerprint
        {
            return Err(ApplicationError::Validation(
                "content package media identity",
            ));
        }
        let track = SubtitleTrack {
            id: lltimeline_track_id(&document)?,
            media_id: media.id,
            fingerprint: lltimeline_track_fingerprint(&document),
            language: document.metadata.language.clone(),
            source: document
                .metadata
                .extra
                .get("track_source")
                .and_then(serde_json::Value::as_str)
                .unwrap_or("listen-resource-package-v1")
                .to_owned(),
            status: SubtitleTrackStatus::Available,
            sentences: lltimeline_segments_to_sentences(&document.segments)?,
        };
        validate_and_prepare_lltimeline_resources(&mut document, &track)?;
        if document.active_word_timeline_id.is_some()
            || document.active_phone_timeline_id.is_some()
            || document.active_chunk_timeline_id.is_some()
            || document.active_sense_group_analysis_id.is_some()
            || document.active_prosody_analysis_id.is_some()
            || document
                .word_timelines
                .iter()
                .any(|v| v.status != TimelineStatus::Candidate)
            || document
                .phone_timelines
                .iter()
                .any(|v| v.status != TimelineStatus::Candidate)
            || document
                .chunk_timelines
                .iter()
                .any(|v| v.status != TimelineStatus::Candidate)
            || document
                .sense_group_analyses
                .iter()
                .any(|v| v.status != TimelineStatus::Candidate)
            || document
                .prosody_analyses
                .iter()
                .any(|v| v.status != TimelineStatus::Candidate)
        {
            return Err(ApplicationError::Invalid(
                "content package import must be candidate-only".into(),
            ));
        }
        let corpus_occurrences =
            self.build_subtitle_corpus_occurrences_from_resources(&track, None, &[])?;
        self.content_package_imports
            .import_content_package_candidates(&ContentPackageCandidateImport {
                track: track.clone(),
                metadata: document.metadata,
                artifacts: document.artifacts,
                word_timelines: document.word_timelines,
                phone_timelines: document.phone_timelines,
                chunk_timelines: document.chunk_timelines,
                sense_group_analyses: document.sense_group_analyses,
                prosody_analyses: document.prosody_analyses,
                corpus_occurrences,
            })?;
        Ok(track)
    }

    pub fn import_lltimeline_document_for_media(
        &self,
        media_id: &MediaId,
        mut document: LLTimelineDocument,
        allow_mismatch: bool,
    ) -> Result<SubtitleTrack, ApplicationError> {
        if document.schema != LLTIMELINE_SCHEMA_V1 {
            return Err(ApplicationError::Validation("lltimeline schema"));
        }
        require_text(&document.metadata.media.fingerprint, "media fingerprint")?;
        let media = self
            .media
            .get(media_id)?
            .ok_or(ApplicationError::NotFound("media item"))?;
        if document.metadata.media.fingerprint != media.fingerprint && !allow_mismatch {
            return Err(ApplicationError::Validation("lltimeline media fingerprint"));
        }
        let track_fingerprint = lltimeline_track_fingerprint(&document);
        let track_id = self
            .subtitle_tracks
            .get_by_media_fingerprint(&media.id, &track_fingerprint)?
            .map(|track| track.id)
            .unwrap_or_else(|| {
                SubtitleTrackId::from_fingerprint(
                    "subtitle-track",
                    &format!("{}:{}", media.id.as_str(), track_fingerprint),
                )
            });
        let source = document
            .metadata
            .extra
            .get("track_source")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("lltimeline-json-v1")
            .to_owned();
        let original_media = document.metadata.media.clone();
        let mut extra = document
            .metadata
            .extra
            .as_object()
            .cloned()
            .unwrap_or_default();
        extra.insert(
            "origin_media_id".into(),
            serde_json::json!(original_media.id.as_str()),
        );
        extra.insert(
            "origin_media_fingerprint".into(),
            serde_json::json!(original_media.fingerprint.clone()),
        );
        if let Some(path) = original_media.path.clone() {
            extra.insert("origin_media_path".into(), serde_json::json!(path));
        }
        extra.insert(
            "origin_media_title".into(),
            serde_json::json!(original_media.title),
        );
        if original_media.fingerprint != media.fingerprint {
            extra.insert(
                "attached_with_media_mismatch".into(),
                serde_json::json!(true),
            );
        }
        document.metadata.extra = serde_json::Value::Object(extra);
        document.metadata.media = LLTimelineMedia {
            id: media.id.clone(),
            fingerprint: media.fingerprint.clone(),
            path: Some(media.path.clone()),
            title: media.title.clone(),
            duration_ms: media.duration.map(TimeMs::get),
        };
        document.metadata.extra = merge_lltimeline_track_extra(
            document.metadata.extra,
            &track_id,
            &track_fingerprint,
            &source,
        );
        remap_lltimeline_identity(&mut document, &track_id, &media.id);
        self.import_lltimeline_document_with_media(document, Some(media))
    }

    fn rhythm_frames_from_word_timeline(
        &self,
        track: &SubtitleTrack,
        word_timelines: &[WordTimeline],
        word_timeline_id: Option<&WordTimelineId>,
        active_word_timeline_id: Option<&WordTimelineId>,
        word_acoustic_cues: &HashMap<
            SubtitleSentenceId,
            Vec<speech_analysis::audible_structure::RhythmWordAcousticCue>,
        >,
    ) -> Result<Vec<LLTimelineRhythmFrame>, ApplicationError> {
        let Some(word_timeline_id) = word_timeline_id else {
            return Ok(Vec::new());
        };
        let Some(timeline) = word_timelines
            .iter()
            .find(|timeline| &timeline.id == word_timeline_id)
        else {
            return Ok(Vec::new());
        };
        let source = if Some(&timeline.id) == active_word_timeline_id {
            "active_word_timeline_fallback"
        } else if word_timeline_line(timeline) == Some("sound") {
            "sound_line_word_timeline"
        } else if timeline
            .metrics_json
            .as_object()
            .get("preparation_input_fingerprint")
            .and_then(serde_json::Value::as_str)
            .is_some()
        {
            "foundation_word_timeline"
        } else {
            "acoustic_cue_word_timeline"
        };
        let is_english = track
            .language
            .as_ref()
            .map(|lang| lang.as_str().starts_with("en"))
            .unwrap_or(true);
        let mut frames = Vec::new();
        for sentence in &track.sentences {
            let words = timeline
                .words
                .iter()
                .filter(|word| word.sentence_id == sentence.id)
                .cloned()
                .collect::<Vec<_>>();
            if words.is_empty() {
                continue;
            }
            let canonical = if is_english {
                speech_analysis::analyze_sentence(sentence)
                    .phonemes
                    .into_iter()
                    .filter_map(|phone| {
                        phone.token_index.map(|token_index| {
                            speech_analysis::phonetics::CanonicalPhone {
                                symbol: phone.symbol,
                                token_index,
                                stress: phone.stress,
                            }
                        })
                    })
                    .collect::<Vec<_>>()
            } else {
                Vec::new()
            };
            let rhythm_frame =
                speech_analysis::audible_structure::build_rhythm_frame_from_word_timeline(
                    sentence,
                    &canonical,
                    &words,
                    word_acoustic_cues
                        .get(&sentence.id)
                        .map(|cues| cues.as_slice()),
                );
            let id = RhythmFrameId::from_fingerprint(
                "rhythm-frame",
                &format!("{}:{}", timeline.id.as_str(), sentence.id.as_str()),
            );
            frames.push(LLTimelineRhythmFrame {
                id,
                track_id: track.id.clone(),
                media_id: track.media_id.clone(),
                sentence_id: sentence.id.clone(),
                parent_word_timeline_id: Some(timeline.id.clone()),
                provider_id: RHYTHM_FRAME_PROVIDER_ID.into(),
                provider_version: RHYTHM_FRAME_PROVIDER_VERSION.into(),
                status: TimelineStatus::Active,
                metrics_json: TimelineMetrics::from_value(serde_json::json!({
                    "source": source,
                    "word_count": words.len(),
                    "energy_cue_count": word_acoustic_cues
                        .get(&sentence.id)
                        .map(|cues| cues.len())
                        .unwrap_or(0),
                })),
                rhythm_frame,
                created_at_ms: timeline.updated_at_ms,
                updated_at_ms: now_ms(),
            });
        }
        Ok(frames)
    }
}
