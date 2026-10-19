use crate::{
    ApplicationError, BoundaryDiagnostic, DisplayChunk, DisplayChunkBoundary,
    LearnedProsodicProviderInfo, MediaAnalysisUseCases, SentenceChunkDiagnostics,
    SentenceChunkPartition, SubtitleSentenceId, SubtitleTokenKind, SubtitleTrack, SubtitleTrackId,
    TimelineStatus, WordTiming, build_word_timeline, chunk_partition_config_for_track_source,
    timing_priority,
};
use sha2::{Digest, Sha256};

pub fn foundation_chunk_policy() -> (&'static str, &'static str, &'static str) {
    (
        speech_analysis::chunking::PARTITIONER_ID,
        speech_analysis::chunking::PARTITIONER_VERSION,
        "acoustic_semantic_v1",
    )
}

impl MediaAnalysisUseCases {
    /// Canonical subtitle snapshot for pronunciation/word-timing artifacts.
    ///
    /// Deliberately excludes phrase-provider output: lexical updates must not
    /// invalidate a word timeline whose real inputs are unchanged.
    pub fn foundation_text_input_fingerprint(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<String, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        canonical_foundation_input_fingerprint(&track, None)
    }

    /// Canonical subtitle + phrase-analysis snapshot for chunk and rule
    /// artifacts. Provider output is sorted before hashing so repository
    /// iteration order cannot create false cache misses.
    pub fn foundation_analysis_input_fingerprint(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<String, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let mut phrase_candidates = Vec::with_capacity(track.sentences.len());
        for sentence in &track.sentences {
            let mut phrases = self.lexical_learning().phrase_candidates(&sentence.id)?;
            phrases.sort_by(|left, right| {
                (
                    left.token_start,
                    left.token_end,
                    &left.normalized_form,
                    &left.canonical_form,
                    &left.display_form,
                    &left.reason,
                )
                    .cmp(&(
                        right.token_start,
                        right.token_end,
                        &right.normalized_form,
                        &right.canonical_form,
                        &right.display_form,
                        &right.reason,
                    ))
            });
            phrase_candidates.push(phrases);
        }
        canonical_foundation_input_fingerprint(&track, Some(&phrase_candidates))
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
        let candidates = self.lexical_learning().phrase_candidates(sentence_id)?;
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
        let candidates = self.lexical_learning().phrase_candidates(sentence_id)?;
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
                let candidates = self.lexical_learning().phrase_candidates(&sentence.id)?;
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
                let candidates = self.lexical_learning().phrase_candidates(&sentence.id)?;
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

fn canonical_foundation_input_fingerprint(
    track: &SubtitleTrack,
    phrase_candidates: Option<&[Vec<domain::PhraseCandidate>]>,
) -> Result<String, ApplicationError> {
    let sentences = track
        .sentences
        .iter()
        .enumerate()
        .map(|(index, sentence)| {
            let phrases = phrase_candidates
                .and_then(|all| all.get(index))
                .cloned()
                .unwrap_or_default();
            serde_json::json!({
                "index": sentence.index,
                "start_ms": sentence.start,
                "end_ms": sentence.end,
                "original_text": sentence.original_text,
                "display_text": sentence.display_text,
                "tokens": sentence.tokens,
                "phrase_candidates": phrases,
            })
        })
        .collect::<Vec<_>>();
    let encoded = serde_json::to_vec(&serde_json::json!({
        "version": if phrase_candidates.is_some() {
            "foundation-analysis-input-v1"
        } else {
            "foundation-text-input-v1"
        },
        "language": track.language,
        "sentences": sentences,
    }))
    .map_err(|error| ApplicationError::Repository(error.to_string()))?;
    Ok(hex::encode(Sha256::digest(encoded)))
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

fn display_chunk_from_analysis(value: speech_analysis::chunking::DisplayChunk) -> DisplayChunk {
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

#[cfg(test)]
mod foundation_fingerprint_tests {
    use super::*;
    use domain::{
        LanguageCode, MediaId, PhraseCandidate, SubtitleSentence, SubtitleSentenceId,
        SubtitleToken, SubtitleTrackId, TimeMs,
    };

    fn track(token_text: &str) -> SubtitleTrack {
        SubtitleTrack {
            id: SubtitleTrackId::parse("track-a").unwrap(),
            media_id: MediaId::parse("media-a").unwrap(),
            fingerprint: "transport-fingerprint".into(),
            language: Some(LanguageCode::parse("en").unwrap()),
            source: "test".into(),
            status: domain::SubtitleTrackStatus::Available,
            sentences: vec![SubtitleSentence {
                id: SubtitleSentenceId::parse("sentence-a").unwrap(),
                index: 0,
                start: TimeMs::new(100),
                end: TimeMs::new(500),
                original_text: token_text.into(),
                display_text: token_text.into(),
                tokens: vec![SubtitleToken {
                    index: 0,
                    kind: SubtitleTokenKind::Word,
                    text: token_text.into(),
                    normalized: Some(token_text.to_lowercase()),
                    start_char: 0,
                    end_char: token_text.len() as u32,
                }],
            }],
        }
    }

    fn phrase(display: &str) -> PhraseCandidate {
        PhraseCandidate {
            canonical_form: display.to_lowercase(),
            display_form: display.into(),
            normalized_form: display.to_lowercase(),
            token_start: 0,
            token_end: 1,
            reason: "test-provider".into(),
        }
    }

    #[test]
    fn token_changes_invalidate_text_and_analysis_but_phrase_changes_only_analysis() {
        let original = track("Hello");
        let changed_token = track("Hallo");
        let phrase_a = vec![vec![phrase("Hello")]];
        let phrase_b = vec![vec![phrase("Hello there")]];

        let text = canonical_foundation_input_fingerprint(&original, None).unwrap();
        let text_after_phrase_update =
            canonical_foundation_input_fingerprint(&original, None).unwrap();
        let changed_text = canonical_foundation_input_fingerprint(&changed_token, None).unwrap();
        let analysis_a =
            canonical_foundation_input_fingerprint(&original, Some(&phrase_a)).unwrap();
        let analysis_b =
            canonical_foundation_input_fingerprint(&original, Some(&phrase_b)).unwrap();

        assert_eq!(text, text_after_phrase_update);
        assert_ne!(text, changed_text);
        assert_ne!(analysis_a, analysis_b);
    }

    #[test]
    fn opaque_track_and_media_identity_do_not_change_the_real_input_fingerprint() {
        let left = track("Hello");
        let mut right = left.clone();
        right.id = SubtitleTrackId::parse("track-b").unwrap();
        right.media_id = MediaId::parse("media-b").unwrap();
        right.fingerprint = "another-transport-fingerprint".into();

        assert_eq!(
            canonical_foundation_input_fingerprint(&left, None).unwrap(),
            canonical_foundation_input_fingerprint(&right, None).unwrap()
        );
    }
}
