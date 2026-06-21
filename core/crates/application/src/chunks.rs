use crate::*;

impl AppServices {
    /// Detect acoustic chunk boundaries for every sentence in a subtitle track.
    ///
    /// Uses gap-based detection on existing word timings. Each sentence is
    /// processed independently; cross-sentence boundaries are never created.
    pub fn detect_track_chunks(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<
        std::collections::HashMap<
            SubtitleSentenceId,
            speech_analysis::chunk_detection::ChunkDetectionResult,
        >,
        ApplicationError,
    > {
        use speech_analysis::chunk_detection::{ChunkDetectionConfig, detect_chunk_boundaries};
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = ChunkDetectionConfig::default();
        let mut results = std::collections::HashMap::new();
        for sentence in track.sentences {
            let timings = self.word_timings(&sentence.id)?;
            let mut result = detect_chunk_boundaries(&timings, &config);
            result.sentence_id = sentence.id.clone();
            results.insert(sentence.id.clone(), result);
        }
        Ok(results)
    }

    /// Detect acoustic chunk boundaries for a single sentence.
    pub fn detect_sentence_chunks(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::chunk_detection::ChunkDetectionResult, ApplicationError> {
        use speech_analysis::chunk_detection::{ChunkDetectionConfig, detect_chunk_boundaries};
        let timings = self.word_timings(sentence_id)?;
        let mut result = detect_chunk_boundaries(&timings, &ChunkDetectionConfig::default());
        result.sentence_id = sentence_id.clone();
        Ok(result)
    }

    /// Detect text-level chunks for a single sentence.
    ///
    /// Uses embedded COCA n-gram, PHRASE List, and external phrase candidates
    /// (ECDICT + built-in rules) to partition the sentence into lexical chunks.
    /// Every word token is covered by exactly one chunk.
    pub fn detect_text_chunks(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::text_chunk_detection::TextChunkDetectionResult, ApplicationError>
    {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let candidates = self.phrase_candidates(sentence_id)?;
        Ok(speech_analysis::text_chunk_detection::detect_text_chunks(
            &sentence,
            &candidates,
        ))
    }

    /// Detect text-level chunks for every sentence in a subtitle track.
    pub fn detect_text_chunks_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<
        std::collections::HashMap<
            SubtitleSentenceId,
            speech_analysis::text_chunk_detection::TextChunkDetectionResult,
        >,
        ApplicationError,
    > {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let mut results = std::collections::HashMap::new();
        for sentence in track.sentences {
            let result = self.detect_text_chunks(&sentence.id)?;
            results.insert(sentence.id.clone(), result);
        }
        Ok(results)
    }

    /// Detect chunks using combined acoustic + text-level evidence.
    ///
    /// Uses the text partition as the structural basis and overlays acoustic
    /// boundary evidence where available. See
    /// [`speech_analysis::chunk_detection::combine_chunks`] for the combination
    /// confidence logic.
    pub fn detect_combined_sentence_chunks(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::chunk_detection::CombinedChunkResult, ApplicationError> {
        use speech_analysis::chunk_detection::{
            ChunkDetectionConfig, combine_chunks, detect_chunk_boundaries,
        };
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let timings = self.word_timings(sentence_id)?;
        let candidates = self.phrase_candidates(sentence_id)?;

        let acoustic = detect_chunk_boundaries(&timings, &ChunkDetectionConfig::default());
        let text =
            speech_analysis::text_chunk_detection::detect_text_chunks(&sentence, &candidates);

        Ok(combine_chunks(&acoustic, &text))
    }

    /// Produce the product-facing, complete chunk partition for one sentence.
    pub fn chunk_partition(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::chunk_partition::SentenceChunkPartition, ApplicationError> {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let timings = self.word_timings(sentence_id)?;
        let candidates = self.phrase_candidates(sentence_id)?;
        Ok(speech_analysis::chunk_partition::partition_sentence(
            &sentence,
            &timings,
            &candidates,
            &speech_analysis::chunk_partition::ChunkPartitionConfig::default(),
        ))
    }

    /// Produce developer-facing scores for selected and rejected chunk boundaries.
    pub fn chunk_partition_diagnostics(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<speech_analysis::chunk_partition::SentenceChunkDiagnostics, ApplicationError> {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let timings = self.word_timings(sentence_id)?;
        let candidates = self.phrase_candidates(sentence_id)?;
        Ok(
            speech_analysis::chunk_partition::partition_sentence_with_diagnostics(
                &sentence,
                &timings,
                &candidates,
                &speech_analysis::chunk_partition::ChunkPartitionConfig::default(),
            ),
        )
    }

    /// Produce product-facing chunk partitions for every sentence in a track.
    pub fn chunk_partitions_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SentenceChunkPartition>, ApplicationError> {
        let track = self
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = chunk_partition_config_for_track_source(&track.source);
        track
            .sentences
            .iter()
            .map(|sentence| {
                let timings = self.word_timings(&sentence.id)?;
                let candidates = self.phrase_candidates(&sentence.id)?;
                Ok(speech_analysis::chunk_partition::partition_sentence(
                    sentence,
                    &timings,
                    &candidates,
                    &config,
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
            .subtitles
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = chunk_partition_config_for_track_source(&track.source);
        track
            .sentences
            .iter()
            .map(|sentence| {
                let timings = self.word_timings(&sentence.id)?;
                let candidates = self.phrase_candidates(&sentence.id)?;
                Ok(
                    speech_analysis::chunk_partition::partition_sentence_with_diagnostics(
                        sentence,
                        &timings,
                        &candidates,
                        &config,
                    ),
                )
            })
            .collect()
    }

    pub fn store_word_timings(
        &self,
        track_id: &SubtitleTrackId,
        timings: &[WordTiming],
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        let track = self
            .subtitles
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
            let existing = self.subtitles.get_word_timings(sentence_id)?;
            if existing.first().is_some_and(|current| {
                values.first().is_some_and(|incoming| {
                    timing_priority(current.timing_source) > timing_priority(incoming.timing_source)
                })
            }) {
                continue;
            }
            self.subtitles.save_word_timings(sentence_id, values)?;
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
            let timeline = self.subtitles.save_word_timeline(&timeline)?;
            let _ = self.subtitles.activate_word_timeline(&timeline.id)?;
        }
        Ok(timings.to_vec())
    }

    pub fn learned_prosodic_providers(&self) -> Vec<LearnedProsodicProviderInfo> {
        vec![speech_analysis::learned_prosodic_provider::embedded_provider_info()]
    }
}
