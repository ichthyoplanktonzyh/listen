//! Independent rich-acoustic boundary evidence providers.
//!
//! These analyzers emit per-boundary evidence and never construct display
//! chunks directly. Missing or estimated timing data produces no evidence so
//! callers naturally degrade to the gap/text partitioner.

use domain::{SubtitleSentenceId, TimingSource, WordTiming};
use serde::{Deserialize, Serialize};

pub const LENGTHENING_PROVIDER_ID: &str = "word-duration-lengthening";
pub const LENGTHENING_PROVIDER_VERSION: &str = "v1";
pub const FILLED_PAUSE_PROVIDER_ID: &str = "filled-pause-hesitation";
pub const FILLED_PAUSE_PROVIDER_VERSION: &str = "v1";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PreBoundaryLengtheningConfig {
    pub minimum_word_duration_ms: u64,
    pub minimum_reference_words: usize,
    pub reference_words_before: usize,
    pub reference_words_after: usize,
    pub ratio_threshold: f32,
    pub ratio_for_max_score: f32,
}

impl Default for PreBoundaryLengtheningConfig {
    fn default() -> Self {
        Self {
            minimum_word_duration_ms: 220,
            minimum_reference_words: 3,
            reference_words_before: 3,
            reference_words_after: 2,
            ratio_threshold: 1.75,
            ratio_for_max_score: 2.75,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FilledPauseHesitationConfig {
    pub score_penalty: f32,
    pub filled_pauses: Vec<String>,
}

impl Default for FilledPauseHesitationConfig {
    fn default() -> Self {
        Self {
            score_penalty: 1.0,
            filled_pauses: ["uh", "um", "erm", "hmm", "mm"]
                .into_iter()
                .map(str::to_owned)
                .collect(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RichAcousticEvidenceKind {
    PreBoundaryLengthening,
    FilledPauseHesitation,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RichAcousticBoundaryEvidence {
    pub sentence_id: SubtitleSentenceId,
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub kind: RichAcousticEvidenceKind,
    pub score_delta: f32,
    pub provider_id: String,
    pub provider_version: String,
    pub measurement: RichAcousticMeasurement,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum RichAcousticMeasurement {
    PreBoundaryLengthening {
        word_duration_ms: u64,
        local_baseline_ms: u64,
        ratio: f32,
        reference_word_count: usize,
    },
    FilledPauseHesitation {
        text: String,
    },
}

pub fn analyze_pre_boundary_lengthening(
    timings: &[WordTiming],
    config: &PreBoundaryLengtheningConfig,
) -> Vec<RichAcousticBoundaryEvidence> {
    let mut evidence = Vec::new();
    for boundary_position in 0..timings.len().saturating_sub(1) {
        let left = &timings[boundary_position];
        let right = &timings[boundary_position + 1];
        if left.sentence_id != right.sentence_id
            || !is_real_timing(left.timing_source)
            || !is_real_timing(right.timing_source)
        {
            continue;
        }

        let word_duration_ms = duration_ms(left);
        if word_duration_ms < config.minimum_word_duration_ms {
            continue;
        }

        let before_start = boundary_position.saturating_sub(config.reference_words_before);
        let after_end = (boundary_position + 1 + config.reference_words_after).min(timings.len());
        let mut references = timings[before_start..boundary_position]
            .iter()
            .chain(timings[boundary_position + 1..after_end].iter())
            .filter(|timing| {
                timing.sentence_id == left.sentence_id && is_real_timing(timing.timing_source)
            })
            .map(duration_ms)
            .filter(|duration| *duration > 0)
            .collect::<Vec<_>>();
        if references.len() < config.minimum_reference_words {
            continue;
        }
        references.sort_unstable();
        let local_baseline_ms = median(&references);
        if local_baseline_ms == 0 {
            continue;
        }
        let ratio = word_duration_ms as f32 / local_baseline_ms as f32;
        if ratio < config.ratio_threshold {
            continue;
        }
        let range = (config.ratio_for_max_score - config.ratio_threshold).max(f32::EPSILON);
        let score_delta =
            (0.75 + 0.25 * ((ratio - config.ratio_threshold) / range)).clamp(0.0, 1.0);
        evidence.push(RichAcousticBoundaryEvidence {
            sentence_id: left.sentence_id.clone(),
            left_token_index: left.token_index,
            right_token_index: right.token_index,
            kind: RichAcousticEvidenceKind::PreBoundaryLengthening,
            score_delta,
            provider_id: LENGTHENING_PROVIDER_ID.into(),
            provider_version: LENGTHENING_PROVIDER_VERSION.into(),
            measurement: RichAcousticMeasurement::PreBoundaryLengthening {
                word_duration_ms,
                local_baseline_ms,
                ratio,
                reference_word_count: references.len(),
            },
        });
    }
    evidence
}

pub fn analyze_filled_pause_hesitation(
    timings: &[WordTiming],
    config: &FilledPauseHesitationConfig,
) -> Vec<RichAcousticBoundaryEvidence> {
    timings
        .windows(2)
        .filter_map(|pair| {
            let left = &pair[0];
            let right = &pair[1];
            if left.sentence_id != right.sentence_id
                || !is_real_timing(left.timing_source)
                || !is_real_timing(right.timing_source)
            {
                return None;
            }
            let hesitation =
                [left.text.as_str(), right.text.as_str()]
                    .into_iter()
                    .find(|text| {
                        let normalized = text
                            .trim_matches(|value: char| !value.is_alphanumeric())
                            .to_ascii_lowercase();
                        config
                            .filled_pauses
                            .iter()
                            .any(|pause| pause == &normalized)
                    })?;
            Some(RichAcousticBoundaryEvidence {
                sentence_id: left.sentence_id.clone(),
                left_token_index: left.token_index,
                right_token_index: right.token_index,
                kind: RichAcousticEvidenceKind::FilledPauseHesitation,
                score_delta: -config.score_penalty.abs(),
                provider_id: FILLED_PAUSE_PROVIDER_ID.into(),
                provider_version: FILLED_PAUSE_PROVIDER_VERSION.into(),
                measurement: RichAcousticMeasurement::FilledPauseHesitation {
                    text: hesitation.into(),
                },
            })
        })
        .collect()
}

fn is_real_timing(source: TimingSource) -> bool {
    source != TimingSource::Estimated
}

fn duration_ms(timing: &WordTiming) -> u64 {
    timing.end_ms.saturating_sub(timing.start_ms)
}

fn median(sorted: &[u64]) -> u64 {
    let middle = sorted.len() / 2;
    if sorted.len().is_multiple_of(2) {
        sorted[middle - 1].saturating_add(sorted[middle]) / 2
    } else {
        sorted[middle]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::SubtitleSentenceId;

    fn timings(durations: &[u64], source: TimingSource) -> Vec<WordTiming> {
        let sentence_id = SubtitleSentenceId::parse("s1").unwrap();
        let mut cursor = 0;
        durations
            .iter()
            .enumerate()
            .map(|(index, duration)| {
                let start_ms = cursor;
                let end_ms = start_ms + duration;
                cursor = end_ms + 20;
                WordTiming {
                    sentence_id: sentence_id.clone(),
                    token_index: index as u32,
                    text: format!("w{index}"),
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
    fn detects_lengthened_word_without_a_pause() {
        let values = timings(&[120, 130, 125, 360, 120, 130], TimingSource::ForcedAligned);
        let result =
            analyze_pre_boundary_lengthening(&values, &PreBoundaryLengtheningConfig::default());
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].left_token_index, 3);
        assert!(result[0].score_delta >= 0.75);
    }

    #[test]
    fn ordinary_word_duration_emits_no_evidence() {
        let values = timings(&[120, 130, 125, 140, 120, 130], TimingSource::ForcedAligned);
        assert!(
            analyze_pre_boundary_lengthening(&values, &PreBoundaryLengtheningConfig::default())
                .is_empty()
        );
    }

    #[test]
    fn estimated_timings_degrade_to_no_evidence() {
        let values = timings(&[120, 130, 125, 360, 120, 130], TimingSource::Estimated);
        assert!(
            analyze_pre_boundary_lengthening(&values, &PreBoundaryLengtheningConfig::default())
                .is_empty()
        );
    }

    #[test]
    fn insufficient_local_context_emits_no_evidence() {
        let values = timings(&[360, 120, 130], TimingSource::ForcedAligned);
        assert!(
            analyze_pre_boundary_lengthening(&values, &PreBoundaryLengtheningConfig::default())
                .is_empty()
        );
    }

    #[test]
    fn filled_pause_emits_negative_boundary_evidence() {
        let mut values = timings(&[120, 130, 125, 120], TimingSource::AsrReported);
        values[1].text = "um".into();
        let result =
            analyze_filled_pause_hesitation(&values, &FilledPauseHesitationConfig::default());
        assert_eq!(result.len(), 2);
        assert!(result.iter().all(|item| item.score_delta < 0.0));
    }

    #[test]
    fn estimated_filled_pause_emits_no_evidence() {
        let mut values = timings(&[120, 130, 125], TimingSource::Estimated);
        values[1].text = "um".into();
        assert!(
            analyze_filled_pause_hesitation(&values, &FilledPauseHesitationConfig::default())
                .is_empty()
        );
    }
}
