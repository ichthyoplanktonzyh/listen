use crate::*;

impl AppServices {
    pub fn list_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimeline>, ApplicationError> {
        self.subtitles.list_word_timelines(track_id)
    }

    pub fn summarize_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimelineSummary>, ApplicationError> {
        let timelines = self.subtitles.list_word_timelines(track_id)?;
        Ok(timelines
            .iter()
            .map(word_timeline_summary)
            .collect::<Vec<_>>())
    }

    pub fn get_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        self.subtitles.get_word_timeline(id)
    }

    pub fn create_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
        input: CreateWordTimeline,
    ) -> Result<WordTimeline, ApplicationError> {
        let track = self
            .subtitles
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
        let timeline = self.subtitles.save_word_timeline(&timeline)?;
        if requested_status == TimelineStatus::Active {
            self.subtitles.activate_word_timeline(&timeline.id)
        } else {
            Ok(timeline)
        }
    }

    pub fn activate_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        self.subtitles.activate_word_timeline(id)
    }

    pub fn archive_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        self.subtitles.archive_word_timeline(id)
    }

    pub fn publish_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        let mut timeline = self
            .subtitles
            .get_word_timeline(id)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        if timeline.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived word timeline"));
        }
        mark_word_timeline_published(&mut timeline);
        timeline.updated_at_ms = now_ms();
        let timeline = self.subtitles.save_word_timeline(&timeline)?;
        self.subtitles.activate_word_timeline(&timeline.id)
    }

    pub fn delete_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        self.subtitles.delete_word_timeline(id)
    }

    pub fn word_timing_diagnostics_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SentenceWordTimingDiagnostics>, ApplicationError> {
        let track = self
            .subtitles
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
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let media = self
            .media
            .get(&track.media_id)?
            .ok_or(ApplicationError::NotFound("media item"))?;
        let word_timelines = self.subtitles.list_word_timelines(track_id)?;
        let active_word_timeline_id = word_timelines
            .iter()
            .find(|timeline| timeline.status == TimelineStatus::Active)
            .map(|timeline| timeline.id.clone());
        let chunk_timelines = self.subtitles.list_chunk_timelines(track_id)?;
        let active_chunk_timeline_id = chunk_timelines
            .iter()
            .find(|timeline| timeline.status == TimelineStatus::Active)
            .map(|timeline| timeline.id.clone());
        let persisted_resource = self.subtitles.get_lltimeline_resource(track_id)?;
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
        Ok(LLTimelineDocument {
            schema: LLTIMELINE_SCHEMA_V1.to_owned(),
            metadata,
            segments: lltimeline_segments_from_track(&track),
            word_timelines,
            active_word_timeline_id,
            phone_timelines: Vec::new(),
            active_phone_timeline_id: None,
            chunk_timelines,
            active_chunk_timeline_id,
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
        self.subtitles.save_track(&track)?;
        self.subtitles.save_lltimeline_resource(
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
            self.subtitles.save_word_timeline(&timeline)?;
        }
        if let Some(active_id) = document.active_word_timeline_id {
            self.subtitles.activate_word_timeline(&active_id)?;
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
            self.subtitles.save_chunk_timeline(&timeline)?;
        }
        if let Some(active_id) = document.active_chunk_timeline_id {
            self.subtitles.activate_chunk_timeline(&active_id)?;
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
            .subtitles
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
        remap_lltimeline_sentence_ids(&mut document, &track_id);
        for timeline in &mut document.word_timelines {
            timeline.media_id = media.id.clone();
            timeline.track_id = track_id.clone();
        }
        for timeline in &mut document.chunk_timelines {
            timeline.media_id = media.id.clone();
            timeline.track_id = track_id.clone();
        }
        self.import_lltimeline_document(document)
    }
}
