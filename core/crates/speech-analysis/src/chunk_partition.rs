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

use crate::rich_acoustic_evidence::{
    FilledPauseHesitationConfig, PreBoundaryLengtheningConfig, RichAcousticBoundaryEvidence,
    RichAcousticEvidenceKind, RichAcousticMeasurement, analyze_filled_pause_hesitation,
    analyze_pre_boundary_lengthening,
};
use crate::text_chunk_detection::{TextChunkEvidence, detect_text_chunks};

pub const PARTITIONER_ID: &str = "acoustic-first-rule-partitioner";
pub const PARTITIONER_VERSION: &str = "v3";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkPartitionConfig {
    pub asr_reported_gap_threshold_ms: u64,
    pub forced_aligned_gap_threshold_ms: u64,
    pub user_adjusted_gap_threshold_ms: u64,
    pub moderate_gap_ratio: f32,
    pub boundary_score_threshold: f32,
    pub minimum_words: usize,
    pub preferred_min_words: usize,
    pub preferred_max_words: usize,
    pub soft_max_words: usize,
    pub hard_max_words: usize,
    pub punctuation_reliability: PunctuationReliability,
    pub pre_boundary_lengthening: Option<PreBoundaryLengtheningConfig>,
    pub filled_pause_hesitation: Option<FilledPauseHesitationConfig>,
}

impl Default for ChunkPartitionConfig {
    fn default() -> Self {
        Self {
            asr_reported_gap_threshold_ms: 250,
            forced_aligned_gap_threshold_ms: 180,
            user_adjusted_gap_threshold_ms: 150,
            moderate_gap_ratio: 0.6,
            boundary_score_threshold: 0.7,
            minimum_words: 2,
            preferred_min_words: 3,
            preferred_max_words: 5,
            soft_max_words: 7,
            hard_max_words: 10,
            punctuation_reliability: PunctuationReliability::Trusted,
            pre_boundary_lengthening: Some(PreBoundaryLengtheningConfig::default()),
            filled_pause_hesitation: Some(FilledPauseHesitationConfig::default()),
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
    PreBoundaryLengthening,
    StrongPunctuation,
    Punctuation,
    LengthLimit,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ChunkBoundaryEvidence {
    AcousticGap {
        gap_ms: u64,
    },
    PreBoundaryLengthening {
        word_duration_ms: u64,
        local_baseline_ms: u64,
        ratio: f32,
        provider_id: String,
        provider_version: String,
    },
    FilledPauseHesitation {
        text: String,
        score_penalty: f32,
        provider_id: String,
        provider_version: String,
    },
    StrongPunctuation {
        text: String,
    },
    Punctuation {
        text: String,
    },
    PhraseProtection {
        text: String,
    },
    ReadabilityFit {
        word_count: usize,
    },
    FragmentPenalty {
        word_count: usize,
        remaining_words: usize,
    },
    LengthLimit {
        word_count: usize,
    },
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BoundaryDiagnostic {
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub raw_score: f32,
    pub selection_threshold: f32,
    pub selected: bool,
    pub forced: bool,
    pub primary_source: Option<ChunkBoundarySource>,
    pub evidence: Vec<ChunkBoundaryEvidence>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SentenceChunkDiagnostics {
    pub partition: SentenceChunkPartition,
    pub candidates: Vec<BoundaryDiagnostic>,
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
    partition_sentence_with_diagnostics(sentence, timings, phrase_candidates, config).partition
}

pub fn partition_sentence_with_diagnostics(
    sentence: &SubtitleSentence,
    timings: &[WordTiming],
    phrase_candidates: &[PhraseCandidate],
    config: &ChunkPartitionConfig,
) -> SentenceChunkDiagnostics {
    let mut rich_acoustic_evidence = Vec::new();
    if let Some(real_timings) = complete_real_timings(sentence, timings) {
        if let Some(lengthening) = config.pre_boundary_lengthening.as_ref() {
            rich_acoustic_evidence
                .extend(analyze_pre_boundary_lengthening(&real_timings, lengthening));
        }
        if let Some(hesitation) = config.filled_pause_hesitation.as_ref() {
            rich_acoustic_evidence
                .extend(analyze_filled_pause_hesitation(&real_timings, hesitation));
        }
    }
    partition_sentence_with_rich_acoustic_evidence(
        sentence,
        timings,
        phrase_candidates,
        &rich_acoustic_evidence,
        config,
    )
}

pub fn partition_sentence_with_rich_acoustic_evidence(
    sentence: &SubtitleSentence,
    timings: &[WordTiming],
    phrase_candidates: &[PhraseCandidate],
    rich_acoustic_evidence: &[RichAcousticBoundaryEvidence],
    config: &ChunkPartitionConfig,
) -> SentenceChunkDiagnostics {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    if words.is_empty() {
        return SentenceChunkDiagnostics {
            partition: SentenceChunkPartition {
                sentence_id: sentence.id.clone(),
                chunks: Vec::new(),
                partitioner_id: PARTITIONER_ID.into(),
                partitioner_version: PARTITIONER_VERSION.into(),
                timing_quality: ChunkTimingQuality::Synthesized,
            },
            candidates: Vec::new(),
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
    let mut diagnostics = Vec::new();
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

        for item in rich_acoustic_evidence.iter().filter(|item| {
            item.sentence_id == sentence.id
                && item.left_token_index == left.index
                && item.right_token_index == right.index
        }) {
            let score_delta = if item.score_delta.is_finite() {
                item.score_delta.clamp(-2.0, 2.0)
            } else {
                0.0
            };
            score += score_delta;
            match (&item.kind, &item.measurement) {
                (
                    RichAcousticEvidenceKind::PreBoundaryLengthening,
                    RichAcousticMeasurement::PreBoundaryLengthening {
                        word_duration_ms,
                        local_baseline_ms,
                        ratio,
                        ..
                    },
                ) => {
                    evidence.push(ChunkBoundaryEvidence::PreBoundaryLengthening {
                        word_duration_ms: *word_duration_ms,
                        local_baseline_ms: *local_baseline_ms,
                        ratio: *ratio,
                        provider_id: item.provider_id.clone(),
                        provider_version: item.provider_version.clone(),
                    });
                    primary_source.get_or_insert(ChunkBoundarySource::PreBoundaryLengthening);
                }
                (
                    RichAcousticEvidenceKind::FilledPauseHesitation,
                    RichAcousticMeasurement::FilledPauseHesitation { text },
                ) => {
                    evidence.push(ChunkBoundaryEvidence::FilledPauseHesitation {
                        text: text.clone(),
                        score_penalty: score_delta.abs(),
                        provider_id: item.provider_id.clone(),
                        provider_version: item.provider_version.clone(),
                    });
                }
                _ => {}
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
            score -= 0.8;
            evidence.push(ChunkBoundaryEvidence::PhraseProtection {
                text: phrase.text.clone(),
            });
        }

        let has_boundary_signal = evidence.iter().any(|item| {
            matches!(
                item,
                ChunkBoundaryEvidence::AcousticGap { .. }
                    | ChunkBoundaryEvidence::PreBoundaryLengthening { .. }
                    | ChunkBoundaryEvidence::StrongPunctuation { .. }
                    | ChunkBoundaryEvidence::Punctuation { .. }
            )
        });
        if has_boundary_signal
            && word_count >= config.preferred_min_words
            && word_count < config.preferred_max_words
        {
            score += 0.25;
            evidence.push(ChunkBoundaryEvidence::ReadabilityFit { word_count });
        }

        if word_count >= config.hard_max_words
            || (word_count >= config.soft_max_words && remaining_words >= config.minimum_words)
        {
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
        if !force_boundary
            && !has_strong_acoustic_gap
            && (word_count < config.minimum_words || remaining_words < config.minimum_words)
        {
            score -= 1.0;
            evidence.push(ChunkBoundaryEvidence::FragmentPenalty {
                word_count,
                remaining_words,
            });
        }

        let selected = force_boundary || score >= config.boundary_score_threshold;
        diagnostics.push(BoundaryDiagnostic {
            left_token_index: left.index,
            right_token_index: right.index,
            raw_score: score,
            selection_threshold: config.boundary_score_threshold,
            selected,
            forced: force_boundary,
            primary_source,
            evidence: evidence.clone(),
        });

        if selected {
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

    SentenceChunkDiagnostics {
        partition: SentenceChunkPartition {
            sentence_id: sentence.id.clone(),
            chunks,
            partitioner_id: PARTITIONER_ID.into(),
            partitioner_version: PARTITIONER_VERSION.into(),
            timing_quality,
        },
        candidates: diagnostics,
    }
}

fn complete_real_timings(
    sentence: &SubtitleSentence,
    timings: &[WordTiming],
) -> Option<Vec<WordTiming>> {
    let by_token = timings
        .iter()
        .filter(|timing| timing.sentence_id == sentence.id)
        .map(|timing| (timing.token_index, timing))
        .collect::<HashMap<_, _>>();
    let ordered = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .map(|word| by_token.get(&word.index).copied())
        .collect::<Option<Vec<_>>>()?;
    if ordered
        .iter()
        .any(|timing| timing.timing_source == TimingSource::Estimated)
        || ordered.iter().any(|timing| timing.start_ms > timing.end_ms)
        || ordered
            .windows(2)
            .any(|pair| pair[0].end_ms > pair[1].start_ms)
    {
        return None;
    }
    Some(ordered.into_iter().cloned().collect())
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

    fn timings_with_durations(
        sentence: &SubtitleSentence,
        durations: &[u64],
        source: TimingSource,
    ) -> Vec<WordTiming> {
        let mut cursor = 0u64;
        sentence
            .tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
            .zip(durations)
            .map(|(token, duration)| {
                let start_ms = cursor;
                let end_ms = start_ms + duration;
                cursor = end_ms + 20;
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
    fn pre_boundary_lengthening_splits_without_a_gap() {
        let sentence = words(&["we", "can", "solve", "this", "problem", "today"]);
        let values = timings_with_durations(
            &sentence,
            &[120, 130, 125, 360, 120, 130],
            TimingSource::ForcedAligned,
        );
        let result = partition_sentence(&sentence, &values, &[], &ChunkPartitionConfig::default());
        assert_eq!(result.chunks.len(), 2);
        assert_eq!(result.chunks[0].text, "we can solve this");
        assert_eq!(
            result.chunks[0]
                .boundary_after
                .as_ref()
                .unwrap()
                .primary_source,
            ChunkBoundarySource::PreBoundaryLengthening
        );
    }

    #[test]
    fn missing_lengthening_features_degrade_to_c2_partition() {
        let sentence = words(&["we", "can", "solve", "this", "problem", "today"]);
        let values = timings_with_durations(
            &sentence,
            &[120, 130, 125, 360, 120, 130],
            TimingSource::ForcedAligned,
        );
        let result = partition_sentence(
            &sentence,
            &values,
            &[],
            &ChunkPartitionConfig {
                pre_boundary_lengthening: None,
                ..ChunkPartitionConfig::default()
            },
        );
        assert_eq!(result.chunks.len(), 1);
    }

    #[test]
    fn incomplete_real_timings_do_not_run_rich_providers() {
        let sentence = words(&["we", "can", "solve", "this", "problem", "today"]);
        let mut values = timings_with_durations(
            &sentence,
            &[120, 130, 125, 360, 120, 130],
            TimingSource::ForcedAligned,
        );
        values.remove(0);
        let result = partition_sentence(&sentence, &values, &[], &ChunkPartitionConfig::default());
        assert_eq!(result.timing_quality, ChunkTimingQuality::Synthesized);
        assert_eq!(result.chunks.len(), 1);
    }

    #[test]
    fn filled_pause_hesitation_reduces_false_gap_boundary() {
        let sentence = words(&["well", "um", "we", "should", "go"]);
        let values = timings(&sentence, Some(1));
        let without_hesitation = partition_sentence(
            &sentence,
            &values,
            &[],
            &ChunkPartitionConfig {
                filled_pause_hesitation: None,
                ..ChunkPartitionConfig::default()
            },
        );
        let with_hesitation =
            partition_sentence(&sentence, &values, &[], &ChunkPartitionConfig::default());
        assert_eq!(without_hesitation.chunks.len(), 2);
        assert_eq!(with_hesitation.chunks.len(), 1);
        let candidate = partition_sentence_with_diagnostics(
            &sentence,
            &values,
            &[],
            &ChunkPartitionConfig::default(),
        )
        .candidates
        .into_iter()
        .find(|candidate| candidate.left_token_index == 1)
        .unwrap();
        assert!(candidate.evidence.iter().any(|evidence| {
            matches!(
                evidence,
                ChunkBoundaryEvidence::FilledPauseHesitation { .. }
            )
        }));
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
    fn diagnostics_include_selected_and_rejected_candidates() {
        let sentence = words(&["we", "can", "try", "again"]);
        let diagnostics = partition_sentence_with_diagnostics(
            &sentence,
            &timings(&sentence, Some(1)),
            &[],
            &ChunkPartitionConfig::default(),
        );
        assert_eq!(diagnostics.candidates.len(), 3);
        assert_eq!(
            diagnostics
                .candidates
                .iter()
                .filter(|candidate| candidate.selected)
                .count(),
            1
        );
        let selected = diagnostics
            .candidates
            .iter()
            .find(|candidate| candidate.selected)
            .unwrap();
        assert_eq!(selected.left_token_index, 1);
        assert_eq!(
            selected.primary_source,
            Some(ChunkBoundarySource::AcousticGap)
        );
        assert!(
            selected
                .evidence
                .iter()
                .any(|evidence| matches!(evidence, ChunkBoundaryEvidence::AcousticGap { .. }))
        );
        assert!(
            diagnostics
                .candidates
                .iter()
                .filter(|candidate| !candidate.selected)
                .all(|candidate| candidate.raw_score < candidate.selection_threshold)
        );
        assert!(diagnostics.candidates.iter().any(|candidate| {
            candidate
                .evidence
                .iter()
                .any(|evidence| matches!(evidence, ChunkBoundaryEvidence::FragmentPenalty { .. }))
        }));
    }

    #[test]
    fn diagnostics_explain_readability_supported_boundary() {
        let sentence = words(&["we", "can", "solve", "this", "problem", "together"]);
        let mut values = timings(&sentence, None);
        values[4].start_ms = values[3].end_ms + 180;
        values[4].end_ms = values[4].start_ms + 200;
        values[5].start_ms = values[4].end_ms + 20;
        values[5].end_ms = values[5].start_ms + 200;
        let diagnostics = partition_sentence_with_diagnostics(
            &sentence,
            &values,
            &[],
            &ChunkPartitionConfig::default(),
        );
        let selected = diagnostics
            .candidates
            .iter()
            .find(|candidate| candidate.selected)
            .unwrap();
        assert!(selected.evidence.iter().any(|evidence| {
            matches!(
                evidence,
                ChunkBoundaryEvidence::ReadabilityFit { word_count: 4 }
            )
        }));
    }

    #[test]
    fn golden_length_and_gap_scenarios_remain_stable() {
        let cases = [
            (
                &["one", "two", "three", "four"][..],
                None,
                vec!["one two three four"],
            ),
            (
                &["one", "two", "three", "four", "five", "six"][..],
                None,
                vec!["one two three four five six"],
            ),
            (
                &["one", "two", "three", "four", "five", "six", "seven"][..],
                None,
                vec!["one two three four five", "six seven"],
            ),
            (
                &[
                    "one", "two", "three", "four", "five", "six", "seven", "eight",
                ][..],
                None,
                vec!["one two three four five", "six seven eight"],
            ),
            (
                &["we", "can", "try", "this", "again"][..],
                Some(1),
                vec!["we can", "try this again"],
            ),
        ];

        for (words_value, gap_after, expected) in cases {
            let sentence = words(words_value);
            let result = partition_sentence(
                &sentence,
                &timings(&sentence, gap_after),
                &[],
                &ChunkPartitionConfig::default(),
            );
            assert_eq!(
                result
                    .chunks
                    .iter()
                    .map(|chunk| chunk.text.as_str())
                    .collect::<Vec<_>>(),
                expected
            );
        }
    }

    #[test]
    fn sentence_identity_is_preserved_for_empty_result() {
        let sentence = sentence(vec![("!", SubtitleTokenKind::Punctuation)]);
        let result = partition_sentence(&sentence, &[], &[], &ChunkPartitionConfig::default());
        assert_eq!(result.sentence_id, sentence.id);
        assert!(result.chunks.is_empty());
    }
}
