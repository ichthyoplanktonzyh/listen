//! Product-facing sentence chunk partitioning.
//!
//! Raw acoustic and text detectors emit evidence. This module resolves that
//! evidence into one complete, non-overlapping partition suitable for display
//! and playback highlighting.

use std::collections::HashMap;

use domain::{
    PhraseCandidate, SubtitleSentence, SubtitleSentenceId, SubtitleTokenKind, TimingSource,
    WordTiming,
};
use serde::{Deserialize, Serialize};

use crate::text_chunk_detection::{TextChunkEvidence, detect_text_chunks};

pub const PARTITIONER_ID: &str = "acoustic-first-rule-partitioner";
pub const PARTITIONER_VERSION: &str = "v2";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkPartitionConfig {
    pub asr_reported_gap_threshold_ms: u64,
    pub forced_aligned_gap_threshold_ms: u64,
    pub user_adjusted_gap_threshold_ms: u64,
    pub moderate_gap_ratio: f32,
    pub boundary_score_threshold: f32,
    pub preferred_max_words: usize,
    pub hard_max_words: usize,
    pub punctuation_reliability: PunctuationReliability,
}

impl Default for ChunkPartitionConfig {
    fn default() -> Self {
        Self {
            asr_reported_gap_threshold_ms: 250,
            forced_aligned_gap_threshold_ms: 180,
            user_adjusted_gap_threshold_ms: 150,
            moderate_gap_ratio: 0.6,
            boundary_score_threshold: 0.7,
            preferred_max_words: 5,
            hard_max_words: 10,
            punctuation_reliability: PunctuationReliability::Trusted,
        }
    }
}

impl ChunkPartitionConfig {
    pub fn for_asr_generated_subtitle() -> Self {
        Self {
            punctuation_reliability: PunctuationReliability::Inferred,
            ..Self::default()
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PunctuationReliability {
    Trusted,
    Inferred,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChunkTimingQuality {
    Real,
    Estimated,
    Synthesized,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChunkBoundarySource {
    AcousticGap,
    StrongPunctuation,
    Punctuation,
    LengthLimit,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ChunkBoundaryEvidence {
    AcousticGap { gap_ms: u64 },
    StrongPunctuation { text: String },
    Punctuation { text: String },
    PhraseProtection { text: String },
    LengthLimit { word_count: usize },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DisplayChunkBoundary {
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub score: f32,
    pub primary_source: ChunkBoundarySource,
    pub evidence: Vec<ChunkBoundaryEvidence>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DisplayChunk {
    pub index: u32,
    pub token_start: u32,
    pub token_end: u32,
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub boundary_after: Option<DisplayChunkBoundary>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SentenceChunkPartition {
    pub sentence_id: SubtitleSentenceId,
    pub chunks: Vec<DisplayChunk>,
    pub partitioner_id: String,
    pub partitioner_version: String,
    pub timing_quality: ChunkTimingQuality,
}

#[derive(Debug, Clone, Copy)]
struct EffectiveTiming {
    start_ms: u64,
    end_ms: u64,
    source: Option<TimingSource>,
}

pub fn partition_sentence(
    sentence: &SubtitleSentence,
    timings: &[WordTiming],
    phrase_candidates: &[PhraseCandidate],
    config: &ChunkPartitionConfig,
) -> SentenceChunkPartition {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    if words.is_empty() {
        return SentenceChunkPartition {
            sentence_id: sentence.id.clone(),
            chunks: Vec::new(),
            partitioner_id: PARTITIONER_ID.into(),
            partitioner_version: PARTITIONER_VERSION.into(),
            timing_quality: ChunkTimingQuality::Synthesized,
        };
    }

    let (effective_timings, timing_quality) = effective_timings(sentence, &words, timings);
    let text = detect_text_chunks(sentence, phrase_candidates);
    let protected_phrases = text
        .chunks
        .iter()
        .filter(|chunk| chunk.evidence != TextChunkEvidence::SingleWord)
        .collect::<Vec<_>>();

    let mut chunks = Vec::new();
    let mut chunk_start = 0usize;
    for boundary_position in 0..words.len().saturating_sub(1) {
        let left = words[boundary_position];
        let right = words[boundary_position + 1];
        let word_count = boundary_position - chunk_start + 1;
        let mut score = 0.0f32;
        let mut evidence = Vec::new();
        let mut primary_source = None;
        let mut force_boundary = false;
        let remaining_words = words.len() - boundary_position - 1;

        if let Some(gap_threshold_ms) = acoustic_gap_threshold(
            effective_timings[boundary_position].source,
            effective_timings[boundary_position + 1].source,
            config,
        ) {
            let gap_ms = effective_timings[boundary_position + 1]
                .start_ms
                .saturating_sub(effective_timings[boundary_position].end_ms);
            if gap_ms >= gap_threshold_ms {
                let excess = gap_ms.saturating_sub(gap_threshold_ms) as f32;
                score += 1.25 + (excess / 500.0).min(0.5);
                evidence.push(ChunkBoundaryEvidence::AcousticGap { gap_ms });
                primary_source = Some(ChunkBoundarySource::AcousticGap);
            } else if gap_ms as f32 >= gap_threshold_ms as f32 * config.moderate_gap_ratio {
                score += 0.45 + 0.2 * gap_ms as f32 / gap_threshold_ms as f32;
                evidence.push(ChunkBoundaryEvidence::AcousticGap { gap_ms });
                primary_source = Some(ChunkBoundarySource::AcousticGap);
            }
        }

        if let Some((punctuation, strong)) = punctuation_between(sentence, left.index, right.index)
        {
            if strong {
                score += match config.punctuation_reliability {
                    PunctuationReliability::Trusted => 1.1,
                    PunctuationReliability::Inferred => 0.35,
                };
                force_boundary = config.punctuation_reliability == PunctuationReliability::Trusted;
                evidence.push(ChunkBoundaryEvidence::StrongPunctuation { text: punctuation });
                primary_source.get_or_insert(ChunkBoundarySource::StrongPunctuation);
            } else {
                score += match config.punctuation_reliability {
                    PunctuationReliability::Trusted => 0.45,
                    PunctuationReliability::Inferred => 0.15,
                };
                evidence.push(ChunkBoundaryEvidence::Punctuation { text: punctuation });
                primary_source.get_or_insert(ChunkBoundarySource::Punctuation);
            }
        }

        if let Some(phrase) = protected_phrases
            .iter()
            .find(|phrase| phrase.token_start <= left.index && phrase.token_end >= right.index)
        {
            score -= 0.6;
            evidence.push(ChunkBoundaryEvidence::PhraseProtection {
                text: phrase.text.clone(),
            });
        }

        if word_count >= config.hard_max_words {
            force_boundary = true;
            score += 1.0;
            evidence.push(ChunkBoundaryEvidence::LengthLimit { word_count });
            primary_source.get_or_insert(ChunkBoundarySource::LengthLimit);
        } else if word_count >= config.preferred_max_words {
            score += 0.75;
            evidence.push(ChunkBoundaryEvidence::LengthLimit { word_count });
            primary_source.get_or_insert(ChunkBoundarySource::LengthLimit);
        }

        let has_strong_acoustic_gap = evidence.iter().any(|item| {
            matches!(
                item,
                ChunkBoundaryEvidence::AcousticGap { gap_ms }
                    if acoustic_gap_threshold(
                        effective_timings[boundary_position].source,
                        effective_timings[boundary_position + 1].source,
                        config,
                    )
                    .is_some_and(|threshold| *gap_ms >= threshold)
            )
        });
        if !force_boundary && !has_strong_acoustic_gap && (word_count == 1 || remaining_words == 1)
        {
            score -= 0.35;
        }

        if force_boundary || score >= config.boundary_score_threshold {
            let boundary = DisplayChunkBoundary {
                left_token_index: left.index,
                right_token_index: right.index,
                score: score.clamp(0.0, 1.0),
                primary_source: primary_source.unwrap_or(ChunkBoundarySource::LengthLimit),
                evidence,
            };
            chunks.push(build_chunk(
                chunks.len(),
                chunk_start,
                boundary_position,
                &words,
                &effective_timings,
                Some(boundary),
            ));
            chunk_start = boundary_position + 1;
        }
    }

    chunks.push(build_chunk(
        chunks.len(),
        chunk_start,
        words.len() - 1,
        &words,
        &effective_timings,
        None,
    ));

    SentenceChunkPartition {
        sentence_id: sentence.id.clone(),
        chunks,
        partitioner_id: PARTITIONER_ID.into(),
        partitioner_version: PARTITIONER_VERSION.into(),
        timing_quality,
    }
}

fn effective_timings(
    sentence: &SubtitleSentence,
    words: &[&domain::SubtitleToken],
    timings: &[WordTiming],
) -> (Vec<EffectiveTiming>, ChunkTimingQuality) {
    let by_token = timings
        .iter()
        .filter(|timing| timing.sentence_id == sentence.id)
        .map(|timing| (timing.token_index, timing))
        .collect::<HashMap<_, _>>();
    let matched = words
        .iter()
        .map(|word| by_token.get(&word.index).copied())
        .collect::<Vec<_>>();

    let complete_and_monotonic = matched.iter().all(Option::is_some)
        && matched
            .windows(2)
            .all(|pair| pair[0].unwrap().start_ms <= pair[1].unwrap().start_ms)
        && matched
            .iter()
            .all(|timing| timing.unwrap().start_ms <= timing.unwrap().end_ms);
    if complete_and_monotonic {
        let quality = if matched
            .iter()
            .any(|timing| timing.unwrap().timing_source != TimingSource::Estimated)
        {
            ChunkTimingQuality::Real
        } else {
            ChunkTimingQuality::Estimated
        };
        return (
            matched
                .into_iter()
                .map(|timing| {
                    let timing = timing.unwrap();
                    EffectiveTiming {
                        start_ms: timing.start_ms,
                        end_ms: timing.end_ms,
                        source: (timing.timing_source != TimingSource::Estimated)
                            .then_some(timing.timing_source),
                    }
                })
                .collect(),
            quality,
        );
    }

    let start_ms = sentence.start.get();
    let duration = sentence.end.get().saturating_sub(start_ms);
    let word_count = words.len() as u64;
    let values = (0..words.len())
        .map(|index| EffectiveTiming {
            start_ms: start_ms + duration.saturating_mul(index as u64) / word_count,
            end_ms: start_ms + duration.saturating_mul(index as u64 + 1) / word_count,
            source: None,
        })
        .collect();
    (values, ChunkTimingQuality::Synthesized)
}

fn acoustic_gap_threshold(
    left: Option<TimingSource>,
    right: Option<TimingSource>,
    config: &ChunkPartitionConfig,
) -> Option<u64> {
    [left?, right?]
        .into_iter()
        .map(|source| match source {
            TimingSource::AsrReported => config.asr_reported_gap_threshold_ms,
            TimingSource::ForcedAligned => config.forced_aligned_gap_threshold_ms,
            TimingSource::UserAdjusted => config.user_adjusted_gap_threshold_ms,
            TimingSource::Estimated => unreachable!("estimated timings are not acoustic evidence"),
        })
        .max()
}

fn punctuation_between(
    sentence: &SubtitleSentence,
    left_token_index: u32,
    right_token_index: u32,
) -> Option<(String, bool)> {
    let punctuation = sentence
        .tokens
        .iter()
        .filter(|token| {
            token.index > left_token_index
                && token.index < right_token_index
                && token.kind == SubtitleTokenKind::Punctuation
        })
        .map(|token| token.text.as_str())
        .collect::<String>();
    if punctuation.is_empty() {
        return None;
    }
    let strong = punctuation
        .chars()
        .any(|value| matches!(value, '.' | '?' | '!' | ';' | ':'));
    Some((punctuation, strong))
}

fn build_chunk(
    index: usize,
    start: usize,
    end: usize,
    words: &[&domain::SubtitleToken],
    timings: &[EffectiveTiming],
    boundary_after: Option<DisplayChunkBoundary>,
) -> DisplayChunk {
    DisplayChunk {
        index: index as u32,
        token_start: words[start].index,
        token_end: words[end].index,
        text: words[start..=end]
            .iter()
            .map(|word| word.text.as_str())
            .collect::<Vec<_>>()
            .join(" "),
        start_ms: timings[start].start_ms,
        end_ms: timings[end].end_ms,
        boundary_after,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{SubtitleToken, TimeMs};

    fn sentence(tokens: Vec<(&str, SubtitleTokenKind)>) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("s1").unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(6000),
            original_text: tokens.iter().map(|(text, _)| *text).collect(),
            display_text: tokens.iter().map(|(text, _)| *text).collect(),
            tokens: tokens
                .into_iter()
                .enumerate()
                .map(|(index, (text, kind))| SubtitleToken {
                    index: index as u32,
                    kind,
                    text: text.into(),
                    normalized: (kind == SubtitleTokenKind::Word)
                        .then(|| text.to_ascii_lowercase()),
                    start_char: 0,
                    end_char: text.len() as u32,
                })
                .collect(),
        }
    }

    fn words(values: &[&str]) -> SubtitleSentence {
        sentence(
            values
                .iter()
                .map(|value| (*value, SubtitleTokenKind::Word))
                .collect(),
        )
    }

    fn timings(sentence: &SubtitleSentence, gap_after: Option<usize>) -> Vec<WordTiming> {
        timings_with_source(sentence, gap_after, TimingSource::AsrReported)
    }

    fn timings_with_source(
        sentence: &SubtitleSentence,
        gap_after: Option<usize>,
        source: TimingSource,
    ) -> Vec<WordTiming> {
        let mut cursor = 0u64;
        sentence
            .tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
            .enumerate()
            .map(|(position, token)| {
                let start_ms = cursor;
                let end_ms = start_ms + 200;
                cursor = end_ms + if gap_after == Some(position) { 400 } else { 20 };
                WordTiming {
                    sentence_id: sentence.id.clone(),
                    token_index: token.index,
                    text: token.text.clone(),
                    start_ms,
                    end_ms,
                    confidence: None,
                    timing_source: source,
                    provider_id: "test".into(),
                    provider_version: "v1".into(),
                }
            })
            .collect()
    }

    #[test]
    fn covers_every_word_once_with_length_fallback() {
        let sentence = words(&["one", "two", "three", "four", "five", "six", "seven"]);
        let result = partition_sentence(&sentence, &[], &[], &ChunkPartitionConfig::default());
        assert_eq!(result.timing_quality, ChunkTimingQuality::Synthesized);
        assert_eq!(result.chunks.len(), 2);
        assert_eq!(result.chunks[0].text, "one two three four five");
        assert_eq!(result.chunks[1].text, "six seven");
        assert_eq!(result.chunks[0].token_start, 0);
        assert_eq!(result.chunks[1].token_end, 6);
    }

    #[test]
    fn real_acoustic_gap_splits_inside_phrase_when_strong() {
        let sentence = words(&["please", "take", "care", "of", "this"]);
        let result = partition_sentence(
            &sentence,
            &timings(&sentence, Some(1)),
            &[],
            &ChunkPartitionConfig::default(),
        );
        assert_eq!(result.timing_quality, ChunkTimingQuality::Real);
        assert_eq!(result.chunks[0].text, "please take");
        assert_eq!(result.chunks[1].text, "care of this");
        assert_eq!(
            result.chunks[0]
                .boundary_after
                .as_ref()
                .unwrap()
                .primary_source,
            ChunkBoundarySource::AcousticGap
        );
    }

    #[test]
    fn estimated_timings_do_not_create_acoustic_boundaries() {
        let sentence = words(&["one", "two", "three"]);
        let mut values = timings(&sentence, Some(0));
        for timing in &mut values {
            timing.timing_source = TimingSource::Estimated;
        }
        let result = partition_sentence(&sentence, &values, &[], &ChunkPartitionConfig::default());
        assert_eq!(result.timing_quality, ChunkTimingQuality::Estimated);
        assert_eq!(result.chunks.len(), 1);
    }

    #[test]
    fn strong_punctuation_forces_boundary() {
        let sentence = sentence(vec![
            ("well", SubtitleTokenKind::Word),
            (";", SubtitleTokenKind::Punctuation),
            ("maybe", SubtitleTokenKind::Word),
        ]);
        let result = partition_sentence(&sentence, &[], &[], &ChunkPartitionConfig::default());
        assert_eq!(result.chunks.len(), 2);
        assert_eq!(
            result.chunks[0]
                .boundary_after
                .as_ref()
                .unwrap()
                .primary_source,
            ChunkBoundarySource::StrongPunctuation
        );
    }

    #[test]
    fn asr_inferred_punctuation_does_not_force_boundary_without_acoustic_support() {
        let sentence = sentence(vec![
            ("well", SubtitleTokenKind::Word),
            (";", SubtitleTokenKind::Punctuation),
            ("maybe", SubtitleTokenKind::Word),
        ]);
        let result = partition_sentence(
            &sentence,
            &timings(&sentence, None),
            &[],
            &ChunkPartitionConfig::for_asr_generated_subtitle(),
        );
        assert_eq!(result.chunks.len(), 1);
    }

    #[test]
    fn asr_inferred_punctuation_combines_with_moderate_acoustic_gap() {
        let sentence = sentence(vec![
            ("we", SubtitleTokenKind::Word),
            ("can", SubtitleTokenKind::Word),
            (";", SubtitleTokenKind::Punctuation),
            ("try", SubtitleTokenKind::Word),
            ("again", SubtitleTokenKind::Word),
        ]);
        let mut values = timings(&sentence, None);
        values[2].start_ms = values[1].end_ms + 180;
        values[2].end_ms = values[2].start_ms + 200;
        values[3].start_ms = values[2].end_ms + 20;
        values[3].end_ms = values[3].start_ms + 200;
        let result = partition_sentence(
            &sentence,
            &values,
            &[],
            &ChunkPartitionConfig::for_asr_generated_subtitle(),
        );
        assert_eq!(result.chunks.len(), 2);
        assert_eq!(result.chunks[0].text, "we can");
        assert_eq!(
            result.chunks[0]
                .boundary_after
                .as_ref()
                .unwrap()
                .primary_source,
            ChunkBoundarySource::AcousticGap
        );
    }

    #[test]
    fn forced_alignment_uses_more_sensitive_gap_threshold() {
        let sentence = words(&["we", "can", "try", "again"]);
        let asr_result = partition_sentence(
            &sentence,
            &timings(&sentence, Some(1)),
            &[],
            &ChunkPartitionConfig {
                asr_reported_gap_threshold_ms: 450,
                ..ChunkPartitionConfig::default()
            },
        );
        let aligned_result = partition_sentence(
            &sentence,
            &timings_with_source(&sentence, Some(1), TimingSource::ForcedAligned),
            &[],
            &ChunkPartitionConfig {
                asr_reported_gap_threshold_ms: 450,
                ..ChunkPartitionConfig::default()
            },
        );
        assert_eq!(asr_result.chunks.len(), 1);
        assert_eq!(aligned_result.chunks.len(), 2);
    }

    #[test]
    fn user_adjusted_timing_uses_most_sensitive_gap_threshold() {
        let sentence = words(&["we", "can", "try", "again"]);
        let mut values = timings_with_source(&sentence, None, TimingSource::UserAdjusted);
        values[2].start_ms = values[1].end_ms + 160;
        values[2].end_ms = values[2].start_ms + 200;
        values[3].start_ms = values[2].end_ms + 20;
        values[3].end_ms = values[3].start_ms + 200;
        let result = partition_sentence(&sentence, &values, &[], &ChunkPartitionConfig::default());
        assert_eq!(result.chunks.len(), 2);
    }

    #[test]
    fn phrase_protection_blocks_moderate_gap_without_other_support() {
        let sentence = words(&["please", "take", "care", "of", "this"]);
        let mut values = timings(&sentence, None);
        values[2].start_ms = values[1].end_ms + 180;
        values[2].end_ms = values[2].start_ms + 200;
        values[3].start_ms = values[2].end_ms + 20;
        values[3].end_ms = values[3].start_ms + 200;
        let result = partition_sentence(&sentence, &values, &[], &ChunkPartitionConfig::default());
        assert_eq!(result.chunks.len(), 1);
    }

    #[test]
    fn weak_evidence_does_not_create_single_word_fragment() {
        let sentence = sentence(vec![
            ("well", SubtitleTokenKind::Word),
            (",", SubtitleTokenKind::Punctuation),
            ("we", SubtitleTokenKind::Word),
            ("can", SubtitleTokenKind::Word),
            ("try", SubtitleTokenKind::Word),
            ("again", SubtitleTokenKind::Word),
        ]);
        let result = partition_sentence(
            &sentence,
            &timings(&sentence, None),
            &[],
            &ChunkPartitionConfig::default(),
        );
        assert_ne!(result.chunks[0].text, "well");
    }

    #[test]
    fn sentence_identity_is_preserved_for_empty_result() {
        let sentence = sentence(vec![("!", SubtitleTokenKind::Punctuation)]);
        let result = partition_sentence(&sentence, &[], &[], &ChunkPartitionConfig::default());
        assert_eq!(result.sentence_id, sentence.id);
        assert!(result.chunks.is_empty());
    }
}
