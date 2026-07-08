use std::collections::HashMap;

use crate::*;

const RHYTHM_FRAME_PROVIDER_ID: &str = "wordtimeline-rhythm-frame";
const RHYTHM_FRAME_PROVIDER_VERSION: &str = "phase-2.21-w2";
const RHYTHM_WORD_ACOUSTIC_CUES_ARTIFACT_KIND: &str = "rhythm_word_acoustic_cues";

fn rhythm_word_acoustic_cues_by_sentence(
    artifacts: &[LLTimelineArtifact],
    word_timeline_id: Option<&WordTimelineId>,
) -> HashMap<SubtitleSentenceId, Vec<speech_analysis::sound_analysis::RhythmWordAcousticCue>> {
    let mut values: HashMap<
        SubtitleSentenceId,
        Vec<speech_analysis::sound_analysis::RhythmWordAcousticCue>,
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
                speech_analysis::sound_analysis::RhythmWordAcousticCue {
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
}

impl AppServices {
    pub fn store_rhythm_word_acoustic_analysis(
        &self,
        track_id: &SubtitleTrackId,
        timeline_id: &WordTimelineId,
        analysis: &speech_analysis::word_acoustics::WordAcousticAnalysis,
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
            provider_id: Some(speech_analysis::word_acoustics::PROVIDER_ID.into()),
            provider_version: Some(speech_analysis::word_acoustics::PROVIDER_VERSION.into()),
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
        self.timelines.list_word_timelines(track_id)
    }

    pub fn summarize_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimelineSummary>, ApplicationError> {
        let timelines = self.timelines.list_word_timelines(track_id)?;
        Ok(timelines
            .iter()
            .map(word_timeline_summary)
            .collect::<Vec<_>>())
    }

    pub fn get_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        self.timelines.get_word_timeline(id)
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
        let timeline = self.timelines.save_word_timeline(&timeline)?;
        if requested_status == TimelineStatus::Active {
            self.timelines.activate_word_timeline(&timeline.id)
        } else {
            Ok(timeline)
        }
    }

    pub fn activate_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        self.timelines.activate_word_timeline(id)
    }

    pub fn archive_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        self.timelines.archive_word_timeline(id)
    }

    pub fn publish_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        let mut timeline = self
            .timelines
            .get_word_timeline(id)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        if timeline.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived word timeline"));
        }
        mark_word_timeline_published(&mut timeline);
        timeline.updated_at_ms = now_ms();
        let timeline = self.timelines.save_word_timeline(&timeline)?;
        self.timelines.activate_word_timeline(&timeline.id)
    }

    pub fn delete_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        self.timelines.delete_word_timeline(id)
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
                let timings = match self.word_timings(&sentence.id) {
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
        let word_timelines = self.timelines.list_word_timelines(track_id)?;
        let active_word_timeline_id = word_timelines
            .iter()
            .find(|timeline| timeline.status == TimelineStatus::Active)
            .map(|timeline| timeline.id.clone());
        let chunk_timelines = self.timelines.list_chunk_timelines(track_id)?;
        let active_chunk_timeline_id = chunk_timelines
            .iter()
            .find(|timeline| timeline.status == TimelineStatus::Active)
            .map(|timeline| timeline.id.clone());
        let phone_timelines = self.timelines.list_phone_timelines(track_id)?;
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
        let sense_group_analyses = self.timelines.list_sense_group_analyses(track_id)?;
        let active_sense_group_analysis_id = sense_group_analyses
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
            artifacts,
        })
    }

    pub fn import_lltimeline_document(
        &self,
        document: LLTimelineDocument,
    ) -> Result<SubtitleTrack, ApplicationError> {
        if document.schema != LLTIMELINE_SCHEMA_V1 {
            return Err(ApplicationError::Validation("lltimeline schema"));
        }
        require_text(&document.metadata.media.fingerprint, "media fingerprint")?;
        require_text(&document.metadata.media.title, "media title")?;
        let now = now_ms();
        let media =
            MediaItem {
                id: document.metadata.media.id.clone(),
                path: document.metadata.media.path.clone().unwrap_or_else(|| {
                    format!("lltimeline://{}", document.metadata.media.id.as_str())
                }),
                fingerprint: document.metadata.media.fingerprint.clone(),
                title: document.metadata.media.title.clone(),
                kind: MediaKind::Video,
                duration: document.metadata.media.duration_ms.map(TimeMs::new),
                availability: MediaAvailability::Available,
                created_at_ms: now,
                updated_at_ms: now,
            };
        self.media.upsert(&media)?;

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
        self.subtitle_tracks.save_track(&track)?;
        self.lltimeline_resources.save_lltimeline_resource(
            &track.id,
            &document.metadata,
            &document.artifacts,
        )?;

        for mut timeline in document.word_timelines {
            if timeline.media_id != track.media_id || timeline.track_id != track.id {
                return Err(ApplicationError::Validation("lltimeline word timeline"));
            }
            if document.active_word_timeline_id.as_ref() == Some(&timeline.id)
                && timeline.status == TimelineStatus::Active
            {
                timeline.status = TimelineStatus::Candidate;
            }
            self.timelines.save_word_timeline(&timeline)?;
        }
        if let Some(active_id) = document.active_word_timeline_id {
            self.timelines.activate_word_timeline(&active_id)?;
        }

        for mut timeline in document.phone_timelines {
            if timeline.media_id != track.media_id || timeline.track_id != track.id {
                return Err(ApplicationError::Validation("lltimeline phone timeline"));
            }
            if document.active_phone_timeline_id.as_ref() == Some(&timeline.id)
                && timeline.status == TimelineStatus::Active
            {
                timeline.status = TimelineStatus::Candidate;
            }
            self.timelines.save_phone_timeline(&timeline)?;
        }
        if let Some(active_id) = document.active_phone_timeline_id {
            self.timelines.activate_phone_timeline(&active_id)?;
        }

        for frame in document.rhythm_frames {
            if frame.media_id != track.media_id || frame.track_id != track.id {
                return Err(ApplicationError::Validation("lltimeline rhythm frame"));
            }
        }

        for mut timeline in document.chunk_timelines {
            if timeline.media_id != track.media_id || timeline.track_id != track.id {
                return Err(ApplicationError::Validation("lltimeline chunk timeline"));
            }
            if document.active_chunk_timeline_id.as_ref() == Some(&timeline.id)
                && timeline.status == TimelineStatus::Active
            {
                timeline.status = TimelineStatus::Candidate;
            }
            self.timelines.save_chunk_timeline(&timeline)?;
        }
        if let Some(active_id) = document.active_chunk_timeline_id {
            self.timelines.activate_chunk_timeline(&active_id)?;
        }

        for mut analysis in document.sense_group_analyses {
            if analysis.media_id != track.media_id || analysis.track_id != track.id {
                return Err(ApplicationError::Validation(
                    "lltimeline sense group analysis",
                ));
            }
            if document.active_sense_group_analysis_id.as_ref() == Some(&analysis.id)
                && analysis.status == TimelineStatus::Active
            {
                analysis.status = TimelineStatus::Candidate;
            }
            self.timelines.save_sense_group_analysis(&analysis)?;
        }
        if let Some(active_id) = document.active_sense_group_analysis_id {
            self.timelines.activate_sense_group_analysis(&active_id)?;
        }

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
        self.import_lltimeline_document(document)
    }

    fn rhythm_frames_from_word_timeline(
        &self,
        track: &SubtitleTrack,
        word_timelines: &[WordTimeline],
        word_timeline_id: Option<&WordTimelineId>,
        active_word_timeline_id: Option<&WordTimelineId>,
        word_acoustic_cues: &HashMap<
            SubtitleSentenceId,
            Vec<speech_analysis::sound_analysis::RhythmWordAcousticCue>,
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
                            speech_analysis::phonetic_alignment::CanonicalPhone {
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
                speech_analysis::sound_analysis::build_rhythm_frame_from_word_timeline(
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
