//! Optional learned prosodic boundary evidence provider.
//!
//! The bundled model is a small project-authored linear classifier distributed
//! under MIT. It is a deployable integration baseline, not a claim of
//! state-of-the-art prosodic recognition. Model load or feature failures emit
//! no evidence so the partitioner retains C1-C3 behavior.

use domain::{SubtitleSentenceId, TimingSource, WordTiming};
use serde::{Deserialize, Serialize};

const EMBEDDED_MODEL: &str = include_str!("../data/prosodic-boundary-linear-v1.json");

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearnedProsodicProviderInfo {
    pub provider_id: String,
    pub model_revision: String,
    pub license: String,
    pub runtime: String,
    pub available: bool,
    pub optional: bool,
    pub diagnostic: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearnedProsodicProviderConfig {
    pub enabled: bool,
    pub gap_reference_ms: u64,
    pub local_reference_words: usize,
    pub minimum_reference_words: usize,
}

impl Default for LearnedProsodicProviderConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            gap_reference_ms: 250,
            local_reference_words: 3,
            minimum_reference_words: 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearnedProsodicBoundaryEvidence {
    pub sentence_id: SubtitleSentenceId,
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub probability: f32,
    pub score_delta: f32,
    pub provider_id: String,
    pub model_revision: String,
    pub license: String,
    pub features: ProsodicFeatureSnapshot,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProsodicFeatureSnapshot {
    pub left_duration_ratio: f32,
    pub gap_ratio: f32,
    pub previous_gap_ratio: f32,
    pub position_balance: f32,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
struct LinearModel {
    provider_id: String,
    model_revision: String,
    license: String,
    #[allow(dead_code)]
    description: String,
    bias: f32,
    weights: LinearWeights,
    probability_threshold: f32,
    score_scale: f32,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
struct LinearWeights {
    left_duration_ratio: f32,
    gap_ratio: f32,
    previous_gap_ratio: f32,
    position_balance: f32,
}

pub fn analyze_with_embedded_model(
    timings: &[WordTiming],
    config: &LearnedProsodicProviderConfig,
) -> Vec<LearnedProsodicBoundaryEvidence> {
    analyze_with_model_json(timings, config, EMBEDDED_MODEL).unwrap_or_default()
}

pub fn embedded_provider_info() -> LearnedProsodicProviderInfo {
    match serde_json::from_str::<LinearModel>(EMBEDDED_MODEL)
        .map_err(|error| LearnedProsodicError::InvalidModel(error.to_string()))
        .and_then(|model| validate_model(&model).map(|_| model))
    {
        Ok(model) => LearnedProsodicProviderInfo {
            provider_id: model.provider_id,
            model_revision: model.model_revision,
            license: model.license,
            runtime: "embedded-linear-cpu".into(),
            available: true,
            optional: true,
            diagnostic: Some(
                "Project-authored deployable baseline; not an external PSST model.".into(),
            ),
        },
        Err(error) => LearnedProsodicProviderInfo {
            provider_id: "llplayer-prosodic-linear".into(),
            model_revision: "unavailable".into(),
            license: "MIT".into(),
            runtime: "embedded-linear-cpu".into(),
            available: false,
            optional: true,
            diagnostic: Some(error.to_string()),
        },
    }
}

pub fn analyze_with_model_json(
    timings: &[WordTiming],
    config: &LearnedProsodicProviderConfig,
    model_json: &str,
) -> Result<Vec<LearnedProsodicBoundaryEvidence>, LearnedProsodicError> {
    if !config.enabled {
        return Ok(Vec::new());
    }
    let model: LinearModel = serde_json::from_str(model_json)
        .map_err(|error| LearnedProsodicError::InvalidModel(error.to_string()))?;
    validate_model(&model)?;
    if timings.len() < config.minimum_reference_words + 1
        || timings
            .iter()
            .any(|timing| timing.timing_source == TimingSource::Estimated)
    {
        return Ok(Vec::new());
    }

    let mut evidence = Vec::new();
    for boundary_position in 0..timings.len().saturating_sub(1) {
        let left = &timings[boundary_position];
        let right = &timings[boundary_position + 1];
        if left.sentence_id != right.sentence_id {
            continue;
        }
        let features = match feature_snapshot(timings, boundary_position, config) {
            Ok(features) => features,
            Err(LearnedProsodicError::MissingFeatures) => continue,
            Err(error) => return Err(error),
        };
        let logit = model.bias
            + model.weights.left_duration_ratio * features.left_duration_ratio
            + model.weights.gap_ratio * features.gap_ratio
            + model.weights.previous_gap_ratio * features.previous_gap_ratio
            + model.weights.position_balance * features.position_balance;
        let probability = sigmoid(logit);
        if probability < model.probability_threshold {
            continue;
        }
        evidence.push(LearnedProsodicBoundaryEvidence {
            sentence_id: left.sentence_id.clone(),
            left_token_index: left.token_index,
            right_token_index: right.token_index,
            probability,
            score_delta: ((probability - 0.5) * model.score_scale).clamp(0.0, 1.0),
            provider_id: model.provider_id.clone(),
            model_revision: model.model_revision.clone(),
            license: model.license.clone(),
            features,
        });
    }
    Ok(evidence)
}

fn feature_snapshot(
    timings: &[WordTiming],
    boundary_position: usize,
    config: &LearnedProsodicProviderConfig,
) -> Result<ProsodicFeatureSnapshot, LearnedProsodicError> {
    let left = &timings[boundary_position];
    let right = &timings[boundary_position + 1];
    let left_duration = duration_ms(left);
    let start = boundary_position.saturating_sub(config.local_reference_words);
    let end = (boundary_position + 2 + config.local_reference_words).min(timings.len());
    let mut references = timings[start..end]
        .iter()
        .enumerate()
        .filter(|(relative, timing)| {
            start + *relative != boundary_position
                && timing.sentence_id == left.sentence_id
                && timing.timing_source != TimingSource::Estimated
        })
        .map(|(_, timing)| duration_ms(timing))
        .filter(|duration| *duration > 0)
        .collect::<Vec<_>>();
    if references.len() < config.minimum_reference_words || left_duration == 0 {
        return Err(LearnedProsodicError::MissingFeatures);
    }
    references.sort_unstable();
    let baseline = median(&references);
    if baseline == 0 || config.gap_reference_ms == 0 {
        return Err(LearnedProsodicError::MissingFeatures);
    }
    let gap_ms = right.start_ms.saturating_sub(left.end_ms);
    let previous_gap_ms = boundary_position
        .checked_sub(1)
        .map(|previous| left.start_ms.saturating_sub(timings[previous].end_ms))
        .unwrap_or_default();
    let position = (boundary_position + 1) as f32 / timings.len() as f32;
    Ok(ProsodicFeatureSnapshot {
        left_duration_ratio: left_duration as f32 / baseline as f32,
        gap_ratio: (gap_ms as f32 / config.gap_reference_ms as f32).clamp(0.0, 4.0),
        previous_gap_ratio: (previous_gap_ms as f32 / config.gap_reference_ms as f32)
            .clamp(0.0, 4.0),
        position_balance: 1.0 - (position - 0.5).abs() * 2.0,
    })
}

fn validate_model(model: &LinearModel) -> Result<(), LearnedProsodicError> {
    let values = [
        model.bias,
        model.weights.left_duration_ratio,
        model.weights.gap_ratio,
        model.weights.previous_gap_ratio,
        model.weights.position_balance,
        model.probability_threshold,
        model.score_scale,
    ];
    if model.provider_id.trim().is_empty()
        || model.model_revision.trim().is_empty()
        || model.license.trim().is_empty()
        || values.iter().any(|value| !value.is_finite())
        || !(0.0..=1.0).contains(&model.probability_threshold)
        || model.score_scale < 0.0
    {
        return Err(LearnedProsodicError::InvalidModel(
            "invalid model metadata or coefficients".into(),
        ));
    }
    Ok(())
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

fn sigmoid(value: f32) -> f32 {
    1.0 / (1.0 + (-value).exp())
}

#[derive(Debug, thiserror::Error, PartialEq)]
pub enum LearnedProsodicError {
    #[error("invalid learned prosodic model: {0}")]
    InvalidModel(String),
    #[error("required prosodic features are unavailable")]
    MissingFeatures,
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::SubtitleSentenceId;

    fn timings(durations: &[u64], gaps: &[u64]) -> Vec<WordTiming> {
        let sentence_id = SubtitleSentenceId::parse("s1").unwrap();
        let mut cursor = 0;
        durations
            .iter()
            .enumerate()
            .map(|(index, duration)| {
                let start_ms = cursor;
                let end_ms = start_ms + duration;
                cursor = end_ms + gaps.get(index).copied().unwrap_or_default();
                WordTiming {
                    sentence_id: sentence_id.clone(),
                    token_index: index as u32,
                    text: format!("w{index}"),
                    start_ms,
                    end_ms,
                    confidence: None,
                    timing_source: TimingSource::ForcedAligned,
                    provider_id: "test".into(),
                    provider_version: "v1".into(),
                }
            })
            .collect()
    }

    #[test]
    fn embedded_model_emits_provider_attributed_evidence() {
        let values = timings(&[120, 130, 125, 340, 120, 130], &[20, 20, 20, 20, 20]);
        let result =
            analyze_with_embedded_model(&values, &LearnedProsodicProviderConfig::default());
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].left_token_index, 3);
        assert_eq!(result[0].provider_id, "llplayer-prosodic-linear");
        assert_eq!(result[0].license, "MIT");
    }

    #[test]
    fn disabled_provider_emits_no_evidence() {
        let values = timings(&[120, 130, 125, 340, 120, 130], &[20, 20, 20, 20, 20]);
        assert!(
            analyze_with_embedded_model(
                &values,
                &LearnedProsodicProviderConfig {
                    enabled: false,
                    ..LearnedProsodicProviderConfig::default()
                }
            )
            .is_empty()
        );
    }

    #[test]
    fn invalid_model_is_failure_safe_at_embedded_boundary() {
        let values = timings(&[120, 130, 125, 340, 120, 130], &[20, 20, 20, 20, 20]);
        assert!(
            analyze_with_model_json(
                &values,
                &LearnedProsodicProviderConfig::default(),
                "{bad json"
            )
            .is_err()
        );
    }

    #[test]
    fn embedded_provider_reports_license_and_optional_runtime() {
        let info = embedded_provider_info();
        assert!(info.available);
        assert!(info.optional);
        assert_eq!(info.license, "MIT");
        assert_eq!(info.runtime, "embedded-linear-cpu");
    }
}
