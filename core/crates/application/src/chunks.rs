use crate::*;

impl AppServices {
    pub fn list_chunk_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ChunkTimeline>, ApplicationError> {
        self.chunk_timelines.list_chunk_timelines(track_id)
    }

    pub fn summarize_chunk_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ChunkTimelineSummary>, ApplicationError> {
        let timelines = self.chunk_timelines.list_chunk_timelines(track_id)?;
        Ok(timelines.iter().map(chunk_timeline_summary).collect())
    }

    pub fn get_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError> {
        self.chunk_timelines.get_chunk_timeline(id)
    }

    pub fn generate_chunk_timeline(
        &self,
        track_id: &SubtitleTrackId,
        requested_status: Option<TimelineStatus>,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let requested_status = requested_status.unwrap_or(TimelineStatus::Candidate);
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let word_timeline = self
            .word_timelines
            .active_word_timeline(track_id)?
            .ok_or(ApplicationError::NotFound("active word timeline"))?;
        let mut grouped = std::collections::HashMap::<SubtitleSentenceId, Vec<WordTiming>>::new();
        for word in &word_timeline.words {
            grouped
                .entry(word.sentence_id.clone())
                .or_default()
                .push(word.clone());
        }
        let config = chunk_partition_config_for_track_source(&track.source);
        let mut chunks = Vec::new();
        let mut timing_sources = Vec::new();
        for sentence in &track.sentences {
            let mut timings = grouped.remove(&sentence.id).unwrap_or_default();
            timings.sort_by_key(|timing| (timing.start_ms, timing.end_ms, timing.token_index));
            timing_sources.extend(timings.iter().map(|timing| timing.timing_source));
            let candidates = self.phrase_candidates(&sentence.id)?;
            let partition = speech_analysis::chunking::partition_sentence(
                sentence,
                &timings,
                &candidates,
                &config,
            );
            for chunk in partition.chunks {
                let chunk_index = chunks.len() as u32;
                chunks.push(chunk_timeline_chunk(
                    &track,
                    &word_timeline,
                    sentence,
                    chunk_index,
                    &chunk,
                ));
            }
        }
        if chunks.is_empty() {
            return Err(ApplicationError::Validation("chunk timeline chunks"));
        }
        let precision = if timing_sources
            .iter()
            .all(|source| *source == TimingSource::Estimated)
        {
            ChunkTimelinePrecision::Approximate
        } else {
            ChunkTimelinePrecision::Precise
        };
        let now = now_ms();
        let provider_id = speech_analysis::chunking::PARTITIONER_ID.to_owned();
        let provider_version = speech_analysis::chunking::PARTITIONER_VERSION.to_owned();
        let algorithm = "acoustic_semantic_v1".to_owned();
        let fingerprint = format!(
            "{}:{}:{}:{}",
            track.id.as_str(),
            word_timeline.id.as_str(),
            provider_version,
            serde_json::to_string(&chunks).unwrap_or_default()
        );
        let mut timeline = ChunkTimeline {
            id: ChunkTimelineId::from_fingerprint("chunk-timeline", &fingerprint),
            track_id: track.id.clone(),
            media_id: track.media_id.clone(),
            parent_word_timeline_id: Some(word_timeline.id.clone()),
            provider_id,
            provider_version,
            algorithm,
            precision,
            created_by: TimelineCreator::Algorithm,
            status: requested_status,
            metrics_json: serde_json::json!({
                "parent_word_timeline_id": word_timeline.id.as_str(),
                "word_timing_sources": timing_sources.iter().map(|source| serde_json::json!(source)).collect::<Vec<_>>(),
                "partitioner_config": config,
            })
            .into(),
            chunks,
            created_at_ms: now,
            updated_at_ms: now,
        };
        if requested_status == TimelineStatus::Active {
            timeline.status = TimelineStatus::Candidate;
        }
        let timeline = self.chunk_timelines.save_chunk_timeline(&timeline)?;
        if requested_status == TimelineStatus::Active {
            let timeline = self.chunk_timelines.activate_chunk_timeline(&timeline.id)?;
            self.reindex_track_corpus(&timeline.track_id)?;
            Ok(timeline)
        } else {
            Ok(timeline)
        }
    }

    pub fn activate_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let timeline = self.chunk_timelines.activate_chunk_timeline(id)?;
        self.reindex_track_corpus(&timeline.track_id)?;
        Ok(timeline)
    }

    pub fn archive_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let timeline = self.chunk_timelines.archive_chunk_timeline(id)?;
        self.reindex_track_corpus(&timeline.track_id)?;
        Ok(timeline)
    }

    pub fn delete_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let timeline = self.chunk_timelines.delete_chunk_timeline(id)?;
        self.reindex_track_corpus(&timeline.track_id)?;
        Ok(timeline)
    }

    /// Produce the product-facing, complete chunk partition for one sentence.
    pub fn chunk_partition(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<SentenceChunkPartition, ApplicationError> {
        let sentence = self
            .subtitle_tracks
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let timings = self.pronunciation().word_timings(sentence_id)?;
        let candidates = self.phrase_candidates(sentence_id)?;
        Ok(sentence_chunk_partition_from_analysis(
            speech_analysis::chunking::partition_sentence(
                &sentence,
                &timings,
                &candidates,
                &speech_analysis::chunking::ChunkPartitionConfig::default(),
            ),
        ))
    }

    /// Produce developer-facing scores for selected and rejected chunk boundaries.
    pub fn chunk_partition_diagnostics(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<SentenceChunkDiagnostics, ApplicationError> {
        let sentence = self
            .subtitle_tracks
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let timings = self.pronunciation().word_timings(sentence_id)?;
        let candidates = self.phrase_candidates(sentence_id)?;
        Ok(sentence_chunk_diagnostics_from_analysis(
            speech_analysis::chunking::partition_sentence_with_diagnostics(
                &sentence,
                &timings,
                &candidates,
                &speech_analysis::chunking::ChunkPartitionConfig::default(),
            ),
        ))
    }

    /// Produce product-facing chunk partitions for every sentence in a track.
    pub fn chunk_partitions_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SentenceChunkPartition>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = chunk_partition_config_for_track_source(&track.source);
        track
            .sentences
            .iter()
            .map(|sentence| {
                let timings = self.pronunciation().word_timings(&sentence.id)?;
                let candidates = self.phrase_candidates(&sentence.id)?;
                Ok(sentence_chunk_partition_from_analysis(
                    speech_analysis::chunking::partition_sentence(
                        sentence,
                        &timings,
                        &candidates,
                        &config,
                    ),
                ))
            })
            .collect()
    }

    /// Produce developer-facing chunk diagnostics using the same track-source
    /// configuration as the product-facing partitions.
    pub fn chunk_diagnostics_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SentenceChunkDiagnostics>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = chunk_partition_config_for_track_source(&track.source);
        track
            .sentences
            .iter()
            .map(|sentence| {
                let timings = self.pronunciation().word_timings(&sentence.id)?;
                let candidates = self.phrase_candidates(&sentence.id)?;
                Ok(sentence_chunk_diagnostics_from_analysis(
                    speech_analysis::chunking::partition_sentence_with_diagnostics(
                        sentence,
                        &timings,
                        &candidates,
                        &config,
                    ),
                ))
            })
            .collect()
    }

    pub fn store_word_timings(
        &self,
        track_id: &SubtitleTrackId,
        timings: &[WordTiming],
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let sentences = track
            .sentences
            .iter()
            .map(|sentence| (sentence.id.clone(), sentence))
            .collect::<std::collections::HashMap<_, _>>();
        let mut grouped = std::collections::HashMap::<SubtitleSentenceId, Vec<WordTiming>>::new();
        for timing in timings {
            let sentence = sentences
                .get(&timing.sentence_id)
                .ok_or(ApplicationError::Validation("word timing sentence"))?;
            if timing.end_ms <= timing.start_ms
                || timing.start_ms < sentence.start.get()
                || timing.end_ms > sentence.end.get()
                || !sentence.tokens.iter().any(|token| {
                    token.index == timing.token_index && token.kind == SubtitleTokenKind::Word
                })
            {
                return Err(ApplicationError::Validation("word timing boundary"));
            }
            grouped
                .entry(timing.sentence_id.clone())
                .or_default()
                .push(timing.clone());
        }
        let mut accepted = Vec::new();
        for (sentence_id, values) in grouped.iter_mut() {
            values.sort_by_key(|value| (value.start_ms, value.end_ms, value.token_index));
            if values
                .windows(2)
                .any(|pair| pair[0].end_ms > pair[1].start_ms)
            {
                return Err(ApplicationError::Validation("word timing monotonicity"));
            }
            let existing = self.word_timelines.get_word_timings(sentence_id)?;
            if existing.first().is_some_and(|current| {
                values.first().is_some_and(|incoming| {
                    timing_priority(current.timing_source) > timing_priority(incoming.timing_source)
                })
            }) {
                continue;
            }
            self.word_timelines.save_word_timings(sentence_id, values)?;
            accepted.extend(values.clone());
        }
        if !accepted.is_empty() {
            let timeline = build_word_timeline(
                &track,
                accepted,
                None,
                None,
                None,
                None,
                None,
                TimelineStatus::Candidate,
                None,
            )?;
            let timeline = self.word_timelines.save_word_timeline(&timeline)?;
            let _ = self.word_timelines.activate_word_timeline(&timeline.id)?;
        }
        Ok(timings.to_vec())
    }

    pub fn learned_prosodic_providers(&self) -> Vec<LearnedProsodicProviderInfo> {
        vec![learned_prosodic_provider_info_from_analysis(
            speech_analysis::chunking::embedded_provider_info(),
        )]
    }
}

fn sentence_chunk_partition_from_analysis(
    value: speech_analysis::chunking::SentenceChunkPartition,
) -> SentenceChunkPartition {
    SentenceChunkPartition {
        sentence_id: value.sentence_id,
        chunks: value
            .chunks
            .into_iter()
            .map(display_chunk_from_analysis)
            .collect(),
        partitioner_id: value.partitioner_id,
        partitioner_version: value.partitioner_version,
        timing_quality: serialized_enum_name(value.timing_quality),
    }
}

fn display_chunk_from_analysis(
    value: speech_analysis::chunking::DisplayChunk,
) -> DisplayChunk {
    DisplayChunk {
        index: value.index,
        token_start: value.token_start,
        token_end: value.token_end,
        text: value.text,
        start_ms: value.start_ms,
        end_ms: value.end_ms,
        boundary_after: value.boundary_after.map(display_boundary_from_analysis),
    }
}

fn display_boundary_from_analysis(
    value: speech_analysis::chunking::DisplayChunkBoundary,
) -> DisplayChunkBoundary {
    DisplayChunkBoundary {
        left_token_index: value.left_token_index,
        right_token_index: value.right_token_index,
        score: value.score,
        primary_source: serialized_enum_name(value.primary_source),
        evidence: value
            .evidence
            .into_iter()
            .map(|item| serde_json::to_value(item).unwrap_or(serde_json::Value::Null))
            .collect(),
    }
}

fn sentence_chunk_diagnostics_from_analysis(
    value: speech_analysis::chunking::SentenceChunkDiagnostics,
) -> SentenceChunkDiagnostics {
    SentenceChunkDiagnostics {
        partition: sentence_chunk_partition_from_analysis(value.partition),
        candidates: value
            .candidates
            .into_iter()
            .map(boundary_diagnostic_from_analysis)
            .collect(),
    }
}

fn boundary_diagnostic_from_analysis(
    value: speech_analysis::chunking::BoundaryDiagnostic,
) -> BoundaryDiagnostic {
    BoundaryDiagnostic {
        left_token_index: value.left_token_index,
        right_token_index: value.right_token_index,
        raw_score: value.raw_score,
        selection_threshold: value.selection_threshold,
        selected: value.selected,
        forced: value.forced,
        primary_source: value.primary_source.map(serialized_enum_name),
        evidence: value
            .evidence
            .into_iter()
            .map(|item| serde_json::to_value(item).unwrap_or(serde_json::Value::Null))
            .collect(),
    }
}

fn learned_prosodic_provider_info_from_analysis(
    value: speech_analysis::chunking::LearnedProsodicProviderInfo,
) -> LearnedProsodicProviderInfo {
    LearnedProsodicProviderInfo {
        provider_id: value.provider_id,
        model_revision: value.model_revision,
        license: value.license,
        runtime: value.runtime,
        available: value.available,
        optional: value.optional,
        diagnostic: value.diagnostic,
    }
}

fn serialized_enum_name<T: serde::Serialize>(value: T) -> String {
    serde_json::to_value(value)
        .ok()
        .and_then(|value| value.as_str().map(str::to_owned))
        .unwrap_or_else(|| "unknown".to_owned())
}

fn chunk_timeline_summary(timeline: &ChunkTimeline) -> ChunkTimelineSummary {
    let confidence_values = timeline
        .chunks
        .iter()
        .map(|chunk| chunk.confidence)
        .collect::<Vec<_>>();
    let average_confidence = if confidence_values.is_empty() {
        None
    } else {
        Some(confidence_values.iter().sum::<f32>() / confidence_values.len() as f32)
    };
    ChunkTimelineSummary {
        id: timeline.id.clone(),
        track_id: timeline.track_id.clone(),
        media_id: timeline.media_id.clone(),
        parent_word_timeline_id: timeline.parent_word_timeline_id.clone(),
        provider_id: timeline.provider_id.clone(),
        provider_version: timeline.provider_version.clone(),
        algorithm: timeline.algorithm.clone(),
        precision: timeline.precision,
        created_by: timeline.created_by,
        status: timeline.status,
        chunk_count: timeline.chunks.len() as u32,
        start_ms: timeline.chunks.iter().map(|chunk| chunk.start_ms).min(),
        end_ms: timeline.chunks.iter().map(|chunk| chunk.end_ms).max(),
        average_confidence,
        created_at_ms: timeline.created_at_ms,
        updated_at_ms: timeline.updated_at_ms,
        can_activate: timeline.status != TimelineStatus::Archived,
        can_archive: timeline.status != TimelineStatus::Archived,
        can_delete: true,
    }
}

fn chunk_timeline_chunk(
    track: &SubtitleTrack,
    word_timeline: &WordTimeline,
    sentence: &SubtitleSentence,
    chunk_index: u32,
    chunk: &speech_analysis::chunking::DisplayChunk,
) -> ChunkTimelineChunk {
    let boundary_sources = chunk
        .boundary_after
        .as_ref()
        .map(|boundary| vec![chunk_boundary_source(boundary.primary_source)])
        .unwrap_or_default();
    let confidence = chunk
        .boundary_after
        .as_ref()
        .map(|boundary| boundary.score.clamp(0.0, 1.0))
        .unwrap_or(1.0);
    let id = ChunkId::from_fingerprint(
        "chunk",
        &format!(
            "{}:{}:{}:{}:{}",
            track.id.as_str(),
            word_timeline.id.as_str(),
            sentence.id.as_str(),
            chunk.token_start,
            chunk.token_end
        ),
    );
    ChunkTimelineChunk {
        id,
        sentence_id: sentence.id.clone(),
        chunk_index,
        start_word_index: chunk.token_start,
        end_word_index: chunk.token_end,
        start_ms: chunk.start_ms,
        end_ms: chunk.end_ms,
        text: chunk.text.clone(),
        boundary_sources,
        confidence,
        warnings: Vec::new(),
        evidence_json: serde_json::json!({
            "boundary_after": chunk.boundary_after,
        })
        .into(),
    }
}

fn chunk_boundary_source(
    source: speech_analysis::chunking::ChunkBoundarySource,
) -> ChunkBoundarySource {
    match source {
        speech_analysis::chunking::ChunkBoundarySource::AcousticGap => {
            ChunkBoundarySource::Pause
        }
        speech_analysis::chunking::ChunkBoundarySource::PreBoundaryLengthening => {
            ChunkBoundarySource::Lengthening
        }
        speech_analysis::chunking::ChunkBoundarySource::LearnedProsodicModel => {
            ChunkBoundarySource::Learned
        }
        speech_analysis::chunking::ChunkBoundarySource::StrongPunctuation
        | speech_analysis::chunking::ChunkBoundarySource::Punctuation => {
            ChunkBoundarySource::Punctuation
        }
        speech_analysis::chunking::ChunkBoundarySource::LengthLimit => {
            ChunkBoundarySource::LengthLimit
        }
    }
}
