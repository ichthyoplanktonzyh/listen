//! Dual-dimension content fit (ADR 0018, Issue #94 v3 upgrade).
//!
//! Meaning fit asks whether the learner would understand the transcript if
//! they could read it; sound fit asks whether they can decode the audio by
//! ear at this delivery.
//!
//! v1–v2: rule-based monotonic banding from fixed thresholds.
//! v3 (Issue #94): feature snapshot with personalized weighted baseline.
//! All default thresholds and weights remain explicit `heuristic_proxy`
//! seeds until offline calibration qualifies replacements.
//!
//! Changing any constant or weight requires bumping
//! [`CONTENT_FIT_ALGORITHM_VERSION`].

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::LanguageCode;

// v2 -> v3 (Issue #94): personalized feature snapshot + weighted baseline.
pub const CONTENT_FIT_ALGORITHM_VERSION: &str = "content-fit-v3";

/// Stable fingerprint over the canonical input-identity string composed by
/// the computation service (timeline identities + vocabulary watermark +
/// algorithm version). Same inputs must yield the same fingerprint so cached
/// profiles can be reused; any component change must change it.
pub fn content_fit_fingerprint(canonical_input: &str) -> String {
    hex::encode(Sha256::digest(format!("content-fit:{canonical_input}")))
}

/// Meaning coverage bands. Anchors: ~98% coverage for unassisted reading
/// comprehension (Hu & Nation 2000; Nation 2006), ~95% for adequate listening
/// comprehension (van Zeeland & Schmitt 2013), ~90% as the partial
/// comprehension floor observed in the same study.
pub const MEANING_COVERAGE_TOO_EASY: f32 = 0.98;
pub const MEANING_COVERAGE_COMPREHENSIBLE: f32 = 0.95;
pub const MEANING_COVERAGE_CHALLENGING: f32 = 0.90;

/// Known-not-recognized density bands (share of word tokens the learner knows
/// by meaning but has not acquired by ear). No direct research equivalent —
/// pure heuristic_proxy pending manual product QA.
pub const SOUND_KNR_TOO_EASY_MAX: f32 = 0.02;
pub const SOUND_KNR_COMPREHENSIBLE_MAX: f32 = 0.05;
pub const SOUND_KNR_CHALLENGING_MAX: f32 = 0.10;

/// Delivery escalation triggers. Fast-rate anchor: L2 comprehension degrades
/// toward ~200 wpm and is comfortable around 130–160 wpm (Griffiths 1992;
/// genre rates in Tauroza & Allison 1990). Weak-form threshold is a
/// heuristic_proxy over rhythm-frame weak groups per word token.
pub const SOUND_FAST_SPEECH_WPM: f32 = 180.0;
pub const SOUND_HIGH_WEAK_FORM_DENSITY: f32 = 0.30;

/// Below this share of assessed word tokens the profile is a conservative
/// guess and consumers must show the honest-degradation state (ADR 0018
/// decision 4) instead of presenting the bands as calibrated.
pub const MIN_ASSESSED_TOKEN_RATIO: f32 = 0.5;

/// Usage-feedback calibration thresholds (Phase 3.5 Slice 7). Only this
/// path may set `usage_calibrated` (ADR 0018 decision 1). All values are
/// `heuristic_proxy` with no direct research anchor — self-report majority
/// and mastery-style accuracy cutoffs — pending real-usage manual QA;
/// changing any of them requires bumping [`CONTENT_FIT_ALGORITHM_VERSION`].
///
/// Comprehension reports need at least this many samples before they count.
pub const CALIBRATION_MIN_REPORTS: u32 = 2;
/// Majority share for a report direction to move the band. Ties at exactly
/// one half resolve toward "harder": when self-reports disagree, the honest
/// direction is the cautious one.
pub const CALIBRATION_REPORT_MAJORITY: f32 = 0.5;
/// Practice accuracy needs at least this many scored attempts to count.
pub const CALIBRATION_MIN_PRACTICE_ATTEMPTS: u32 = 5;
/// Correct-rate at or above this shifts one band easier.
pub const CALIBRATION_PRACTICE_EASIER_MIN_CORRECT: f32 = 0.85;
/// Correct-rate at or below this shifts one band harder.
pub const CALIBRATION_PRACTICE_HARDER_MAX_CORRECT: f32 = 0.5;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InputFit {
    TooEasy,
    Comprehensible,
    Challenging,
    TooHard,
}

impl InputFit {
    /// One band harder, saturating at `TooHard`.
    fn escalate(self) -> Self {
        match self {
            Self::TooEasy => Self::Comprehensible,
            Self::Comprehensible => Self::Challenging,
            Self::Challenging | Self::TooHard => Self::TooHard,
        }
    }

    /// One band easier, saturating at `TooEasy`.
    fn relax(self) -> Self {
        match self {
            Self::TooHard => Self::Challenging,
            Self::Challenging => Self::Comprehensible,
            Self::Comprehensible | Self::TooEasy => Self::TooEasy,
        }
    }
}

/// Explicit user triage intent for one media (ADR 0018 decision 6). Intent is
/// durable user judgment, not derived state: it always outranks fit-derived
/// queue suggestions but never blocks anything — ignoring triage entirely
/// leaves every feature behaving identically (P3/P5 red lines).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaTriageIntent {
    /// Keep this media in the extensive-listening queue.
    PinExtensive,
    /// Keep this media in the intensive-listening target list.
    PinIntensive,
    /// Set this media aside for now (暂缓区).
    Defer,
    /// User-confirmed completion after repeated comprehension improvement.
    /// This organizes the library; it is not a capability judgment.
    Graduated,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FitEvidenceGrade {
    /// Computed from material + vocabulary profile alone.
    InitialEstimate,
    /// Adjusted by the learner's own usage feedback (comprehension reports,
    /// practice performance). Only the feedback-calibration path may set this.
    UsageCalibrated,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FitSignalKind {
    // -- v1/v2 signals --
    UnknownMeaningDensity,
    UnassessedDensity,
    KnownNotRecognizedDensity,
    SpeechRateWpm,
    WeakFormDensity,
    CompressionDensity,
    MeanChunkLength,
    /// Calibration: share of extensive-session self-reports saying "unclear".
    ComprehensionReportUnclearRatio,
    /// Calibration: correct-rate over scored practice attempts on this media.
    PracticeCorrectRate,
    // -- v3 signals (Issue #94) --
    /// Mean sense-group length in word tokens (semantic density proxy).
    MeanSenseGroupLength,
    /// Number of sense groups per sentence (structural complexity).
    SenseGroupDensity,
    /// Share of tokens that belong to multi-word expressions.
    MultiWordExpressionDensity,
    /// Share of multi-word expressions whose meaning is marked unknown.
    UnknownPhraseDensity,
    /// Share of multi-word expressions without a learner assessment.
    UnassessedPhraseDensity,
    /// Max dependency tree depth across sentences (syntactic complexity).
    SyntaxDepth,
    /// Mean dependency arc span in token positions (syntactic complexity).
    MeanDependencySpan,
    /// Ratio of inter-word pauses to speech duration (prosodic difficulty).
    PauseRatio,
    /// Share of replays per sentence on this media (learner behavior).
    ReplayDensity,
    /// Share of word lookups per unique word on this media (learner behavior).
    LookupDensity,
    /// Mean timing reliability derived from timing provenance.
    SubtitleTimingQuality,
}

/// One explainability datum behind a band. `decisive` marks signals that
/// selected or escalated the band, as opposed to informational context; the
/// UI derives its "为什么" copy from these, never from raw formulas
/// (shared-context invariant 18).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FitSignal {
    pub kind: FitSignalKind,
    pub value: f32,
    pub decisive: bool,
    /// Signed contribution to the dimension difficulty score. Positive values
    /// make the material harder; negative values make it easier. Legacy
    /// profiles omit this field.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub contribution: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DifficultyDimension {
    pub fit: InputFit,
    pub signals: Vec<FitSignal>,
    /// Normalized v3 difficulty score in `[0, 1]`; absent on v1/v2 profiles.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub score: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContentDifficultyProfile {
    /// `"media"` today; `"sentence"` is a reserved seam (ADR 0018 decision 5).
    pub subject_kind: String,
    pub subject_id: String,
    pub language: LanguageCode,
    pub meaning: DifficultyDimension,
    pub sound: DifficultyDimension,
    /// Share of word tokens whose lexical entry carries any assessment.
    pub assessed_token_ratio: f32,
    pub evidence_grade: FitEvidenceGrade,
    pub algorithm_version: String,
    pub computed_at_ms: u64,
    pub input_fingerprint: String,
    /// v3 (Issue #94): full feature snapshot backing the banding decision.
    /// `None` for profiles computed by v1/v2 algorithms (backward compat).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feature_snapshot: Option<ContentFitFeatureSnapshot>,
    /// v3 (Issue #94): feature evidence coverage summary.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feature_coverage: Option<FeatureCoverage>,
}

impl ContentDifficultyProfile {
    /// Whether the vocabulary profile covers enough of the transcript for the
    /// bands to be presented without the honest-degradation state.
    pub fn has_sufficient_vocabulary_profile(&self) -> bool {
        self.assessed_token_ratio >= MIN_ASSESSED_TOKEN_RATIO
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MeaningFitInputs {
    pub unknown_meaning_density: f32,
    pub unassessed_density: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct SoundFitInputs {
    pub known_not_recognized_density: f32,
    pub speech_rate_wpm: Option<f32>,
    pub weak_form_density: Option<f32>,
    pub compression_density: Option<f32>,
    pub mean_chunk_length: Option<f32>,
}

// ---------------------------------------------------------------------------
// v3 feature snapshot (Issue #94)
// ---------------------------------------------------------------------------

/// Complete feature snapshot backing the v3 banding decision. All features
/// are `Option<f32>`; absent features degrade gracefully (weight excluded
/// from normalization) rather than defaulting to zero.
///
/// evidence_class: every field is `heuristic_proxy` unless noted otherwise.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContentFitFeatureSnapshot {
    // -- Material features (v1/v2 carry-forward) --
    pub unknown_meaning_density: f32,
    pub unassessed_density: f32,
    pub known_not_recognized_density: f32,
    pub speech_rate_wpm: Option<f32>,
    pub weak_form_density: Option<f32>,
    pub compression_density: Option<f32>,
    pub mean_chunk_length: Option<f32>,
    // -- v3 material features --
    /// Mean number of word tokens per sense group.
    pub mean_sense_group_length: Option<f32>,
    /// Sense groups per sentence.
    pub sense_group_density: Option<f32>,
    /// Share of word tokens that are part of a multi-word-expression sense group.
    pub multi_word_expression_density: Option<f32>,
    /// Share of detected multi-word expressions marked unknown by this learner.
    pub unknown_phrase_density: Option<f32>,
    /// Share of detected multi-word expressions without a learner assessment.
    pub unassessed_phrase_density: Option<f32>,
    /// Maximum dependency tree depth across all sentences.
    pub syntax_depth: Option<f32>,
    /// Mean absolute dependency arc span in token positions.
    pub mean_dependency_span: Option<f32>,
    /// Ratio of inter-word pauses to total speech duration.
    pub pause_ratio: Option<f32>,
    // -- v3 learner-behavior features --
    /// Replays per sentence (rolling window over recent listening sessions).
    pub replay_density: Option<f32>,
    /// Word lookups per unique word token in the transcript.
    pub lookup_density: Option<f32>,
    // -- Quality features --
    /// Mean timing reliability by provenance (estimated < ASR-reported <
    /// aligned < forced/user-adjusted).
    pub subtitle_timing_quality: Option<f32>,
    /// Assessed token ratio lifted from the top-level profile.
    pub assessed_token_ratio: f32,
}

impl ContentFitFeatureSnapshot {
    /// Build a snapshot from the legacy v2 inputs (no v3 features available).
    pub fn from_v2_inputs(
        meaning: &MeaningFitInputs,
        sound: &SoundFitInputs,
        assessed_token_ratio: f32,
    ) -> Self {
        Self {
            unknown_meaning_density: meaning.unknown_meaning_density,
            unassessed_density: meaning.unassessed_density,
            known_not_recognized_density: sound.known_not_recognized_density,
            speech_rate_wpm: sound.speech_rate_wpm,
            weak_form_density: sound.weak_form_density,
            compression_density: sound.compression_density,
            mean_chunk_length: sound.mean_chunk_length,
            mean_sense_group_length: None,
            sense_group_density: None,
            multi_word_expression_density: None,
            unknown_phrase_density: None,
            unassessed_phrase_density: None,
            syntax_depth: None,
            mean_dependency_span: None,
            pause_ratio: None,
            replay_density: None,
            lookup_density: None,
            subtitle_timing_quality: None,
            assessed_token_ratio,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ContentFitFeatureKind {
    SpeechRateWpm,
    WeakFormDensity,
    CompressionDensity,
    MeanChunkLength,
    MeanSenseGroupLength,
    SenseGroupDensity,
    MultiWordExpressionDensity,
    UnknownPhraseDensity,
    UnassessedPhraseDensity,
    SyntaxDepth,
    MeanDependencySpan,
    PauseRatio,
    ReplayDensity,
    LookupDensity,
    SubtitleTimingQuality,
}

/// Summary of the evidence available for a v3 decision. Missing features are
/// explicit so consumers and offline calibration never confuse "unknown" with
/// a favorable zero.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FeatureCoverage {
    pub total_features: u32,
    pub available_features: u32,
    pub coverage_ratio: f32,
    pub missing_features: Vec<ContentFitFeatureKind>,
}

impl FeatureCoverage {
    pub fn compute(snapshot: &ContentFitFeatureSnapshot) -> Self {
        let optional_features = [
            (
                ContentFitFeatureKind::SpeechRateWpm,
                snapshot.speech_rate_wpm,
            ),
            (
                ContentFitFeatureKind::WeakFormDensity,
                snapshot.weak_form_density,
            ),
            (
                ContentFitFeatureKind::CompressionDensity,
                snapshot.compression_density,
            ),
            (
                ContentFitFeatureKind::MeanChunkLength,
                snapshot.mean_chunk_length,
            ),
            (
                ContentFitFeatureKind::MeanSenseGroupLength,
                snapshot.mean_sense_group_length,
            ),
            (
                ContentFitFeatureKind::SenseGroupDensity,
                snapshot.sense_group_density,
            ),
            (
                ContentFitFeatureKind::MultiWordExpressionDensity,
                snapshot.multi_word_expression_density,
            ),
            (
                ContentFitFeatureKind::UnknownPhraseDensity,
                snapshot.unknown_phrase_density,
            ),
            (
                ContentFitFeatureKind::UnassessedPhraseDensity,
                snapshot.unassessed_phrase_density,
            ),
            (ContentFitFeatureKind::SyntaxDepth, snapshot.syntax_depth),
            (
                ContentFitFeatureKind::MeanDependencySpan,
                snapshot.mean_dependency_span,
            ),
            (ContentFitFeatureKind::PauseRatio, snapshot.pause_ratio),
            (
                ContentFitFeatureKind::ReplayDensity,
                snapshot.replay_density,
            ),
            (
                ContentFitFeatureKind::LookupDensity,
                snapshot.lookup_density,
            ),
            (
                ContentFitFeatureKind::SubtitleTimingQuality,
                snapshot.subtitle_timing_quality,
            ),
        ];
        let total = optional_features.len() as u32;
        let missing_features = optional_features
            .iter()
            .filter_map(|(kind, value)| value.is_none().then_some(*kind))
            .collect::<Vec<_>>();
        let available = total - missing_features.len() as u32;
        FeatureCoverage {
            // +3 for the always-present required features.
            total_features: total + 3,
            available_features: available + 3,
            coverage_ratio: (available + 3) as f32 / (total + 3) as f32,
            missing_features,
        }
    }
}

// ---------------------------------------------------------------------------
// v3 weighted banding (Issue #94)
// ---------------------------------------------------------------------------

/// Per-feature weights for the v3 weighted baseline. Default values are
/// calibrated to produce v2-equivalent banding when only legacy features
/// are present. All weights are `heuristic_proxy`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContentFitWeights {
    // -- Meaning dimension weights --
    pub w_unknown_meaning: f32,
    pub w_unassessed: f32,
    pub w_sense_group_length: f32,
    pub w_sense_group_density: f32,
    pub w_mwe_density: f32,
    pub w_unknown_phrase: f32,
    pub w_unassessed_phrase: f32,
    pub w_syntax_depth: f32,
    pub w_dependency_span: f32,
    // -- Sound dimension weights --
    pub w_knr: f32,
    pub w_speech_rate: f32,
    pub w_weak_form: f32,
    pub w_compression: f32,
    pub w_chunk_length: f32,
    pub w_pause_ratio: f32,
    pub w_replay_density: f32,
    pub w_lookup_density: f32,
    pub w_subtitle_quality: f32,
}

impl Default for ContentFitWeights {
    /// Explainable heuristic baseline. These coefficients are deliberately
    /// public data and are inputs to the offline calibrator; they are not
    /// presented as learned probabilities.
    fn default() -> Self {
        Self {
            w_unknown_meaning: 0.40,
            w_unassessed: 0.40,
            w_sense_group_length: 0.05,
            w_sense_group_density: 0.03,
            w_mwe_density: 0.05,
            w_unknown_phrase: 0.15,
            w_unassessed_phrase: 0.05,
            w_syntax_depth: 0.07,
            w_dependency_span: 0.05,
            w_knr: 0.45,
            w_speech_rate: 0.15,
            w_weak_form: 0.10,
            w_compression: 0.05,
            w_chunk_length: 0.05,
            w_pause_ratio: 0.05,
            w_replay_density: 0.05,
            w_lookup_density: 0.05,
            w_subtitle_quality: 0.05,
        }
    }
}

/// Default v3 thresholds over normalized weighted difficulty. They are
/// `heuristic_proxy` seeds for the offline threshold search.
pub const MEANING_SCORE_TOO_EASY: f32 = 0.10;
pub const MEANING_SCORE_COMPREHENSIBLE: f32 = 0.25;
pub const MEANING_SCORE_CHALLENGING: f32 = 0.50;

pub const SOUND_SCORE_TOO_EASY: f32 = 0.15;
pub const SOUND_SCORE_COMPREHENSIBLE: f32 = 0.35;
pub const SOUND_SCORE_CHALLENGING: f32 = 0.60;

fn normalize_range(value: f32, easy: f32, hard: f32) -> f32 {
    if hard <= easy {
        return 0.0;
    }
    ((value - easy) / (hard - easy)).clamp(0.0, 1.0)
}

fn band(score: f32, thresholds: [f32; 3]) -> InputFit {
    if score <= thresholds[0] {
        InputFit::TooEasy
    } else if score <= thresholds[1] {
        InputFit::Comprehensible
    } else if score <= thresholds[2] {
        InputFit::Challenging
    } else {
        InputFit::TooHard
    }
}

fn weighted_dimension(
    components: &[(f32, f32, FitSignalKind, f32)],
    thresholds: [f32; 3],
) -> DifficultyDimension {
    let total_weight = components
        .iter()
        .map(|(weight, _, _, _)| weight)
        .sum::<f32>();
    let score = if total_weight > 0.0 {
        components
            .iter()
            .map(|(weight, normalized, _, _)| weight * normalized)
            .sum::<f32>()
            / total_weight
    } else {
        0.0
    }
    .clamp(0.0, 1.0);
    let signals = components
        .iter()
        .map(|(weight, normalized, kind, raw)| {
            let contribution = if total_weight > 0.0 {
                weight * normalized / total_weight
            } else {
                0.0
            };
            FitSignal {
                kind: *kind,
                value: *raw,
                decisive: contribution >= 0.10,
                contribution: Some(contribution),
            }
        })
        .collect();
    DifficultyDimension {
        fit: band(score, thresholds),
        signals,
        score: Some(score),
    }
}

pub fn weighted_meaning_fit(
    snapshot: &ContentFitFeatureSnapshot,
    weights: &ContentFitWeights,
) -> DifficultyDimension {
    let mut components = vec![
        (
            weights.w_unknown_meaning,
            normalize_range(snapshot.unknown_meaning_density, 0.0, 0.10),
            FitSignalKind::UnknownMeaningDensity,
            snapshot.unknown_meaning_density,
        ),
        (
            weights.w_unassessed,
            normalize_range(snapshot.unassessed_density, 0.0, 0.10),
            FitSignalKind::UnassessedDensity,
            snapshot.unassessed_density,
        ),
    ];
    macro_rules! add_optional {
        ($value:expr, $weight:expr, $kind:expr, $normalized:expr) => {
            if let Some(raw) = $value {
                components.push(($weight, $normalized(raw), $kind, raw));
            }
        };
    }
    add_optional!(
        snapshot.mean_sense_group_length,
        weights.w_sense_group_length,
        FitSignalKind::MeanSenseGroupLength,
        |raw| normalize_range(raw, 2.0, 10.0)
    );
    add_optional!(
        snapshot.sense_group_density,
        weights.w_sense_group_density,
        FitSignalKind::SenseGroupDensity,
        |raw| normalize_range(raw, 1.0, 5.0)
    );
    add_optional!(
        snapshot.multi_word_expression_density,
        weights.w_mwe_density,
        FitSignalKind::MultiWordExpressionDensity,
        |raw: f32| raw.clamp(0.0, 1.0)
    );
    add_optional!(
        snapshot.unknown_phrase_density,
        weights.w_unknown_phrase,
        FitSignalKind::UnknownPhraseDensity,
        |raw: f32| raw.clamp(0.0, 1.0)
    );
    add_optional!(
        snapshot.unassessed_phrase_density,
        weights.w_unassessed_phrase,
        FitSignalKind::UnassessedPhraseDensity,
        |raw: f32| raw.clamp(0.0, 1.0)
    );
    add_optional!(
        snapshot.syntax_depth,
        weights.w_syntax_depth,
        FitSignalKind::SyntaxDepth,
        |raw| normalize_range(raw, 2.0, 10.0)
    );
    add_optional!(
        snapshot.mean_dependency_span,
        weights.w_dependency_span,
        FitSignalKind::MeanDependencySpan,
        |raw| normalize_range(raw, 1.0, 6.0)
    );
    weighted_dimension(
        &components,
        [
            MEANING_SCORE_TOO_EASY,
            MEANING_SCORE_COMPREHENSIBLE,
            MEANING_SCORE_CHALLENGING,
        ],
    )
}

/// Computes v3 sound fit from the feature snapshot + weights. Absent features
/// are excluded from the weighted sum (their weight is removed from the
/// normalization denominator) so they never penalize or inflate the score.
pub fn weighted_sound_fit(
    snapshot: &ContentFitFeatureSnapshot,
    weights: &ContentFitWeights,
) -> DifficultyDimension {
    let mut components: Vec<(f32, f32, FitSignalKind, f32)> = vec![(
        weights.w_knr,
        normalize_range(snapshot.known_not_recognized_density, 0.0, 0.10),
        FitSignalKind::KnownNotRecognizedDensity,
        snapshot.known_not_recognized_density,
    )];

    macro_rules! add_optional {
        ($value:expr, $weight:expr, $kind:expr, $normalized:expr) => {
            if let Some(raw) = $value {
                components.push(($weight, $normalized(raw), $kind, raw));
            }
        };
    }

    add_optional!(
        snapshot.speech_rate_wpm,
        weights.w_speech_rate,
        FitSignalKind::SpeechRateWpm,
        |raw| normalize_range(raw, 100.0, 240.0)
    );
    add_optional!(
        snapshot.weak_form_density,
        weights.w_weak_form,
        FitSignalKind::WeakFormDensity,
        |raw| normalize_range(raw, 0.0, 0.50)
    );
    add_optional!(
        snapshot.compression_density,
        weights.w_compression,
        FitSignalKind::CompressionDensity,
        |raw| normalize_range(raw, 0.0, 0.30)
    );
    add_optional!(
        snapshot.mean_chunk_length,
        weights.w_chunk_length,
        FitSignalKind::MeanChunkLength,
        |raw| normalize_range(raw, 2.0, 10.0)
    );
    add_optional!(
        snapshot.pause_ratio,
        weights.w_pause_ratio,
        FitSignalKind::PauseRatio,
        |raw| 1.0 - normalize_range(raw, 0.0, 0.25)
    );
    add_optional!(
        snapshot.replay_density,
        weights.w_replay_density,
        FitSignalKind::ReplayDensity,
        |raw| normalize_range(raw, 0.0, 1.0)
    );
    add_optional!(
        snapshot.lookup_density,
        weights.w_lookup_density,
        FitSignalKind::LookupDensity,
        |raw| normalize_range(raw, 0.0, 0.50)
    );
    add_optional!(
        snapshot.subtitle_timing_quality,
        weights.w_subtitle_quality,
        FitSignalKind::SubtitleTimingQuality,
        |raw: f32| 1.0 - raw.clamp(0.0, 1.0)
    );
    weighted_dimension(
        &components,
        [
            SOUND_SCORE_TOO_EASY,
            SOUND_SCORE_COMPREHENSIBLE,
            SOUND_SCORE_CHALLENGING,
        ],
    )
}

// ---------------------------------------------------------------------------
// v3 calibration sample (Issue #94, Slice 3)
// ---------------------------------------------------------------------------

/// One calibration data point: a feature snapshot paired with the observed
/// outcome from user behavior. Used for offline analysis and future model
/// training (v4). The `outcome_band` is derived from the calibration record
/// (self-reported comprehension + practice accuracy).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CalibrationSample {
    pub subject_kind: String,
    pub subject_id: String,
    pub language: LanguageCode,
    pub snapshot: ContentFitFeatureSnapshot,
    /// Uncalibrated v3 predictions. Feedback is kept out of the prediction so
    /// the exported label cannot leak into its own feature vector.
    pub predicted_meaning_score: f32,
    pub predicted_sound_score: f32,
    pub predicted_meaning_band: InputFit,
    pub predicted_sound_band: InputFit,
    /// Frozen v2 comparison computed from the same material snapshot.
    pub v2_meaning_band: InputFit,
    pub v2_sound_band: InputFit,
    /// Difficulty target derived from eligible comprehension reports and
    /// scored practice accuracy. `None` means feedback is not yet sufficient.
    pub observed_difficulty: Option<f32>,
    /// Comprehension self-report distribution.
    pub reports_understood_all: u32,
    pub reports_got_the_gist: u32,
    pub reports_unclear: u32,
    /// Practice accuracy.
    pub practice_attempts: u32,
    pub practice_correct: u32,
    pub sampled_at_ms: u64,
}

/// Minimum feedback sessions needed before a calibration sample is useful.
pub const CALIBRATION_SAMPLE_MIN_FEEDBACK: u32 = CALIBRATION_MIN_REPORTS;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ContentFitThresholds {
    pub too_easy_max: f32,
    pub comprehensible_max: f32,
    pub challenging_max: f32,
}

impl ContentFitThresholds {
    pub const fn sound_v3() -> Self {
        Self {
            too_easy_max: SOUND_SCORE_TOO_EASY,
            comprehensible_max: SOUND_SCORE_COMPREHENSIBLE,
            challenging_max: SOUND_SCORE_CHALLENGING,
        }
    }

    fn as_array(self) -> [f32; 3] {
        [
            self.too_easy_max,
            self.comprehensible_max,
            self.challenging_max,
        ]
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContentFitEvaluationReport {
    pub sample_count: u32,
    pub v2_mean_absolute_band_error: f32,
    pub v3_mean_absolute_band_error: f32,
    pub v3_improvement: f32,
    pub recommended_sound_thresholds: ContentFitThresholds,
}

fn band_index(value: InputFit) -> i32 {
    match value {
        InputFit::TooEasy => 0,
        InputFit::Comprehensible => 1,
        InputFit::Challenging => 2,
        InputFit::TooHard => 3,
    }
}

fn observed_band(value: f32) -> InputFit {
    band(value.clamp(0.0, 1.0), [0.20, 0.45, 0.70])
}

fn mean_band_error(
    samples: &[CalibrationSample],
    predict: impl Fn(&CalibrationSample) -> InputFit,
) -> f32 {
    let mut total = 0.0;
    let mut count = 0u32;
    for sample in samples {
        let Some(observed) = sample.observed_difficulty else {
            continue;
        };
        total += (band_index(predict(sample)) - band_index(observed_band(observed))).abs() as f32;
        count += 1;
    }
    if count == 0 {
        0.0
    } else {
        total / count as f32
    }
}

/// Exhaustive deterministic threshold search for the small offline baseline.
/// Callers should evaluate the returned thresholds on a separate holdout set;
/// this function deliberately performs no hidden split or randomization.
pub fn search_sound_thresholds(samples: &[CalibrationSample]) -> ContentFitThresholds {
    let mut best = ContentFitThresholds::sound_v3();
    let mut best_error = mean_band_error(samples, |sample| {
        band(sample.predicted_sound_score, best.as_array())
    });
    for easy_step in 1..=6 {
        for comprehensible_step in (easy_step + 1)..=14 {
            for challenging_step in (comprehensible_step + 1)..=19 {
                let candidate = ContentFitThresholds {
                    too_easy_max: easy_step as f32 * 0.05,
                    comprehensible_max: comprehensible_step as f32 * 0.05,
                    challenging_max: challenging_step as f32 * 0.05,
                };
                let error = mean_band_error(samples, |sample| {
                    band(sample.predicted_sound_score, candidate.as_array())
                });
                if error < best_error {
                    best = candidate;
                    best_error = error;
                }
            }
        }
    }
    best
}

pub fn evaluate_calibration_samples(samples: &[CalibrationSample]) -> ContentFitEvaluationReport {
    let eligible = samples
        .iter()
        .filter(|sample| sample.observed_difficulty.is_some())
        .cloned()
        .collect::<Vec<_>>();
    let recommended = search_sound_thresholds(&eligible);
    evaluate_calibration_samples_with_thresholds(&eligible, recommended)
}

pub fn evaluate_calibration_samples_with_thresholds(
    samples: &[CalibrationSample],
    thresholds: ContentFitThresholds,
) -> ContentFitEvaluationReport {
    let eligible = samples
        .iter()
        .filter(|sample| sample.observed_difficulty.is_some())
        .cloned()
        .collect::<Vec<_>>();
    let v2_error = mean_band_error(&eligible, |sample| sample.v2_sound_band);
    let v3_error = mean_band_error(&eligible, |sample| {
        band(sample.predicted_sound_score, thresholds.as_array())
    });
    ContentFitEvaluationReport {
        sample_count: eligible.len() as u32,
        v2_mean_absolute_band_error: v2_error,
        v3_mean_absolute_band_error: v3_error,
        v3_improvement: v2_error - v3_error,
        recommended_sound_thresholds: thresholds,
    }
}

pub fn meaning_fit(inputs: MeaningFitInputs) -> DifficultyDimension {
    let unknown = inputs.unknown_meaning_density.clamp(0.0, 1.0);
    let unassessed = inputs.unassessed_density.clamp(0.0, 1.0);
    let coverage = (1.0 - unknown - unassessed).clamp(0.0, 1.0);
    let fit = if coverage >= MEANING_COVERAGE_TOO_EASY {
        InputFit::TooEasy
    } else if coverage >= MEANING_COVERAGE_COMPREHENSIBLE {
        InputFit::Comprehensible
    } else if coverage >= MEANING_COVERAGE_CHALLENGING {
        InputFit::Challenging
    } else {
        InputFit::TooHard
    };
    DifficultyDimension {
        fit,
        signals: vec![
            FitSignal {
                kind: FitSignalKind::UnknownMeaningDensity,
                value: unknown,
                decisive: true,
                contribution: None,
            },
            FitSignal {
                kind: FitSignalKind::UnassessedDensity,
                value: unassessed,
                decisive: unassessed > 0.0,
                contribution: None,
            },
        ],
        score: None,
    }
}

/// Recorded usage-feedback corrections for one subject's sound fit (Phase
/// 3.5 Slice 7). This is durable learner evidence, never a cache row: it
/// lives outside the profile cache and must survive every fit recompute.
/// Raw material signals are never rewritten — calibration only shifts the
/// presented band and appends its own explainability signals.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SoundFitCalibration {
    pub subject_kind: String,
    pub subject_id: String,
    /// Comprehension self-report counters (3.3 extensive sessions).
    pub reports_understood_all: u32,
    pub reports_got_the_gist: u32,
    pub reports_unclear: u32,
    /// Scored practice attempts on this media (skipped attempts excluded).
    pub practice_attempts: u32,
    pub practice_correct: u32,
    pub updated_at_ms: u64,
}

impl SoundFitCalibration {
    pub fn new(subject_kind: &str, subject_id: &str) -> Self {
        Self {
            subject_kind: subject_kind.to_owned(),
            subject_id: subject_id.to_owned(),
            reports_understood_all: 0,
            reports_got_the_gist: 0,
            reports_unclear: 0,
            practice_attempts: 0,
            practice_correct: 0,
            updated_at_ms: 0,
        }
    }

    fn report_total(&self) -> u32 {
        self.reports_understood_all + self.reports_got_the_gist + self.reports_unclear
    }
}

/// Continuous calibration target in `[0, 1]` derived from the same durable
/// feedback channels used by the online one-band correction. This is an
/// offline label, never an input to the prediction being evaluated.
pub fn calibration_observed_difficulty(calibration: &SoundFitCalibration) -> Option<f32> {
    let mut components = Vec::new();
    let reports = calibration.report_total();
    if reports >= CALIBRATION_MIN_REPORTS {
        components.push(
            (calibration.reports_got_the_gist as f32 * 0.5 + calibration.reports_unclear as f32)
                / reports as f32,
        );
    }
    if calibration.practice_attempts >= CALIBRATION_MIN_PRACTICE_ATTEMPTS {
        let correct = calibration
            .practice_correct
            .min(calibration.practice_attempts) as f32
            / calibration.practice_attempts as f32;
        components.push(1.0 - correct);
    }
    if components.is_empty() {
        None
    } else {
        Some(components.iter().sum::<f32>() / components.len() as f32)
    }
}

/// Derived view of a calibration record: how far to shift the sound band
/// and which explainability signals to attach.
#[derive(Debug, Clone, PartialEq)]
pub struct SoundFitCalibrationOutcome {
    /// Negative = easier, positive = harder; clamped to one band either way
    /// so calibration re-frames expectations without overriding the material
    /// evidence outright.
    pub band_shift: i8,
    pub signals: Vec<FitSignal>,
    /// True when at least one feedback channel has enough evidence — the
    /// gate for `usage_calibrated` (a zero shift with enough data is still a
    /// calibration: usage confirmed the band).
    pub informative: bool,
}

/// Pure derivation from the recorded counters; recomputable at any time, so
/// constant changes (with the required version bump) re-derive history
/// instead of mutating it.
pub fn sound_fit_calibration_outcome(
    calibration: &SoundFitCalibration,
) -> SoundFitCalibrationOutcome {
    let mut shift: i32 = 0;
    let mut signals = Vec::new();
    let mut informative = false;
    let reports = calibration.report_total();
    if reports >= CALIBRATION_MIN_REPORTS {
        informative = true;
        let unclear_ratio = calibration.reports_unclear as f32 / reports as f32;
        let understood_ratio = calibration.reports_understood_all as f32 / reports as f32;
        // Unclear majority is checked first: at an exact tie the cautious
        // direction wins (see CALIBRATION_REPORT_MAJORITY).
        let component = if unclear_ratio >= CALIBRATION_REPORT_MAJORITY {
            1
        } else if understood_ratio >= CALIBRATION_REPORT_MAJORITY {
            -1
        } else {
            0
        };
        shift += component;
        signals.push(FitSignal {
            kind: FitSignalKind::ComprehensionReportUnclearRatio,
            value: unclear_ratio,
            decisive: component != 0,
            contribution: None,
        });
    }
    if calibration.practice_attempts >= CALIBRATION_MIN_PRACTICE_ATTEMPTS {
        informative = true;
        let rate = calibration
            .practice_correct
            .min(calibration.practice_attempts) as f32
            / calibration.practice_attempts as f32;
        let component = if rate <= CALIBRATION_PRACTICE_HARDER_MAX_CORRECT {
            1
        } else if rate >= CALIBRATION_PRACTICE_EASIER_MIN_CORRECT {
            -1
        } else {
            0
        };
        shift += component;
        signals.push(FitSignal {
            kind: FitSignalKind::PracticeCorrectRate,
            value: rate,
            decisive: component != 0,
            contribution: None,
        });
    }
    SoundFitCalibrationOutcome {
        band_shift: shift.clamp(-1, 1) as i8,
        signals,
        informative,
    }
}

/// Applies a calibration outcome to a computed sound dimension: shifts the
/// band one step (saturating) and appends the calibration signals. The
/// material signals stay untouched — displayed reasons remain exactly the
/// inputs that produced the band.
pub fn apply_sound_fit_calibration(
    mut dimension: DifficultyDimension,
    outcome: &SoundFitCalibrationOutcome,
) -> DifficultyDimension {
    if outcome.band_shift < 0 {
        dimension.fit = dimension.fit.relax();
    } else if outcome.band_shift > 0 {
        dimension.fit = dimension.fit.escalate();
    }
    dimension.signals.extend(outcome.signals.iter().cloned());
    dimension
}

/// Bands sound fit: base band from known-not-recognized density, then one
/// escalation per triggered delivery signal, saturating at `TooHard`.
/// Absent optional signals are omitted entirely — never defaulted to zero.
pub fn sound_fit(inputs: SoundFitInputs) -> DifficultyDimension {
    let knr = inputs.known_not_recognized_density.clamp(0.0, 1.0);
    let mut fit = if knr < SOUND_KNR_TOO_EASY_MAX {
        InputFit::TooEasy
    } else if knr < SOUND_KNR_COMPREHENSIBLE_MAX {
        InputFit::Comprehensible
    } else if knr < SOUND_KNR_CHALLENGING_MAX {
        InputFit::Challenging
    } else {
        InputFit::TooHard
    };
    let mut signals = vec![FitSignal {
        kind: FitSignalKind::KnownNotRecognizedDensity,
        value: knr,
        decisive: true,
        contribution: None,
    }];
    if let Some(wpm) = inputs.speech_rate_wpm {
        let fast = wpm > SOUND_FAST_SPEECH_WPM;
        if fast {
            fit = fit.escalate();
        }
        signals.push(FitSignal {
            kind: FitSignalKind::SpeechRateWpm,
            value: wpm,
            decisive: fast,
            contribution: None,
        });
    }
    if let Some(density) = inputs.weak_form_density {
        let high = density > SOUND_HIGH_WEAK_FORM_DENSITY;
        if high {
            fit = fit.escalate();
        }
        signals.push(FitSignal {
            kind: FitSignalKind::WeakFormDensity,
            value: density,
            decisive: high,
            contribution: None,
        });
    }
    if let Some(density) = inputs.compression_density {
        signals.push(FitSignal {
            kind: FitSignalKind::CompressionDensity,
            value: density,
            decisive: false,
            contribution: None,
        });
    }
    if let Some(length) = inputs.mean_chunk_length {
        signals.push(FitSignal {
            kind: FitSignalKind::MeanChunkLength,
            value: length,
            decisive: false,
            contribution: None,
        });
    }
    DifficultyDimension {
        fit,
        signals,
        score: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot() -> ContentFitFeatureSnapshot {
        ContentFitFeatureSnapshot {
            unknown_meaning_density: 0.0,
            unassessed_density: 0.0,
            known_not_recognized_density: 0.0,
            speech_rate_wpm: None,
            weak_form_density: None,
            compression_density: None,
            mean_chunk_length: None,
            mean_sense_group_length: None,
            sense_group_density: None,
            multi_word_expression_density: None,
            unknown_phrase_density: None,
            unassessed_phrase_density: None,
            syntax_depth: None,
            mean_dependency_span: None,
            pause_ratio: None,
            replay_density: None,
            lookup_density: None,
            subtitle_timing_quality: None,
            assessed_token_ratio: 1.0,
        }
    }

    fn meaning(unknown: f32, unassessed: f32) -> InputFit {
        meaning_fit(MeaningFitInputs {
            unknown_meaning_density: unknown,
            unassessed_density: unassessed,
        })
        .fit
    }

    #[test]
    fn meaning_fit_bands_at_coverage_thresholds() {
        // coverage = 1 − unknown; endpoints are inclusive for the easier band
        assert_eq!(meaning(0.02, 0.0), InputFit::TooEasy);
        assert_eq!(meaning(0.021, 0.0), InputFit::Comprehensible);
        assert_eq!(meaning(0.05, 0.0), InputFit::Comprehensible);
        assert_eq!(meaning(0.051, 0.0), InputFit::Challenging);
        assert_eq!(meaning(0.10, 0.0), InputFit::Challenging);
        assert_eq!(meaning(0.101, 0.0), InputFit::TooHard);
    }

    #[test]
    fn unassessed_tokens_count_against_coverage() {
        // 1% unknown alone is too_easy; 4% unassessed on top drops coverage
        // to 95% (comprehensible), and the unassessed signal turns decisive.
        assert_eq!(meaning(0.01, 0.0), InputFit::TooEasy);
        let dim = meaning_fit(MeaningFitInputs {
            unknown_meaning_density: 0.01,
            unassessed_density: 0.04,
        });
        assert_eq!(dim.fit, InputFit::Comprehensible);
        let unassessed = dim
            .signals
            .iter()
            .find(|s| s.kind == FitSignalKind::UnassessedDensity)
            .expect("unassessed signal always emitted");
        assert!(unassessed.decisive);
    }

    #[test]
    fn sound_fit_base_bands_from_knr_density() {
        let base = |knr| {
            sound_fit(SoundFitInputs {
                known_not_recognized_density: knr,
                ..SoundFitInputs::default()
            })
            .fit
        };
        assert_eq!(base(0.0), InputFit::TooEasy);
        assert_eq!(base(0.02), InputFit::Comprehensible);
        assert_eq!(base(0.05), InputFit::Challenging);
        assert_eq!(base(0.10), InputFit::TooHard);
    }

    #[test]
    fn delivery_signals_escalate_and_saturate() {
        // comprehensible base + fast speech -> challenging
        let dim = sound_fit(SoundFitInputs {
            known_not_recognized_density: 0.03,
            speech_rate_wpm: Some(200.0),
            ..SoundFitInputs::default()
        });
        assert_eq!(dim.fit, InputFit::Challenging);
        assert!(
            dim.signals
                .iter()
                .any(|s| s.kind == FitSignalKind::SpeechRateWpm && s.decisive)
        );

        // challenging base + fast speech + heavy weak forms saturates at too_hard
        let dim = sound_fit(SoundFitInputs {
            known_not_recognized_density: 0.08,
            speech_rate_wpm: Some(200.0),
            weak_form_density: Some(0.4),
            ..SoundFitInputs::default()
        });
        assert_eq!(dim.fit, InputFit::TooHard);
    }

    #[test]
    fn slow_delivery_signals_are_informational_not_decisive() {
        let dim = sound_fit(SoundFitInputs {
            known_not_recognized_density: 0.03,
            speech_rate_wpm: Some(150.0),
            weak_form_density: Some(0.1),
            compression_density: Some(0.05),
            mean_chunk_length: Some(3.2),
        });
        assert_eq!(dim.fit, InputFit::Comprehensible);
        let decisive: Vec<_> = dim.signals.iter().filter(|s| s.decisive).collect();
        assert_eq!(decisive.len(), 1);
        assert_eq!(decisive[0].kind, FitSignalKind::KnownNotRecognizedDensity);
        assert_eq!(dim.signals.len(), 5);
    }

    #[test]
    fn absent_optional_signals_are_omitted() {
        let dim = sound_fit(SoundFitInputs {
            known_not_recognized_density: 0.03,
            ..SoundFitInputs::default()
        });
        assert_eq!(dim.signals.len(), 1);
        assert_eq!(
            dim.signals[0].kind,
            FitSignalKind::KnownNotRecognizedDensity
        );
    }

    fn calibration(
        (all, gist, unclear): (u32, u32, u32),
        (attempts, correct): (u32, u32),
    ) -> SoundFitCalibration {
        SoundFitCalibration {
            reports_understood_all: all,
            reports_got_the_gist: gist,
            reports_unclear: unclear,
            practice_attempts: attempts,
            practice_correct: correct,
            updated_at_ms: 1,
            ..SoundFitCalibration::new("media", "m1")
        }
    }

    #[test]
    fn calibration_below_minimum_evidence_is_not_informative() {
        let outcome = sound_fit_calibration_outcome(&calibration((1, 0, 0), (4, 4)));
        assert!(!outcome.informative);
        assert_eq!(outcome.band_shift, 0);
        assert!(outcome.signals.is_empty());
    }

    #[test]
    fn report_majorities_shift_the_band_with_cautious_ties() {
        // Understood majority -> easier.
        let outcome = sound_fit_calibration_outcome(&calibration((2, 1, 0), (0, 0)));
        assert!(outcome.informative);
        assert_eq!(outcome.band_shift, -1);
        assert_eq!(outcome.signals.len(), 1);
        assert!(outcome.signals[0].decisive);
        // Unclear majority -> harder.
        let outcome = sound_fit_calibration_outcome(&calibration((0, 1, 2), (0, 0)));
        assert_eq!(outcome.band_shift, 1);
        // Exact tie (1 understood / 1 unclear): both ratios sit at the
        // majority threshold; the cautious direction (harder) wins.
        let outcome = sound_fit_calibration_outcome(&calibration((1, 0, 1), (0, 0)));
        assert_eq!(outcome.band_shift, 1);
        // Gist-heavy mix moves nothing but still counts as calibrated.
        let outcome = sound_fit_calibration_outcome(&calibration((1, 3, 1), (0, 0)));
        assert!(outcome.informative);
        assert_eq!(outcome.band_shift, 0);
        assert!(!outcome.signals[0].decisive);
    }

    #[test]
    fn practice_accuracy_shifts_the_band_at_the_cutoffs() {
        // 5/5 correct = 1.0 >= 0.85 -> easier.
        let outcome = sound_fit_calibration_outcome(&calibration((0, 0, 0), (5, 5)));
        assert_eq!(outcome.band_shift, -1);
        assert!(outcome.signals[0].decisive);
        // 2/5 correct = 0.4 <= 0.5 -> harder.
        let outcome = sound_fit_calibration_outcome(&calibration((0, 0, 0), (5, 2)));
        assert_eq!(outcome.band_shift, 1);
        // 3/5 correct = 0.6 in the neutral zone.
        let outcome = sound_fit_calibration_outcome(&calibration((0, 0, 0), (5, 3)));
        assert!(outcome.informative);
        assert_eq!(outcome.band_shift, 0);
    }

    #[test]
    fn calibration_channels_combine_and_clamp_to_one_band() {
        // Both channels say harder: still only one band.
        let outcome = sound_fit_calibration_outcome(&calibration((0, 0, 3), (5, 1)));
        assert_eq!(outcome.band_shift, 1);
        assert_eq!(outcome.signals.len(), 2);
        // Channels disagree: they cancel out.
        let outcome = sound_fit_calibration_outcome(&calibration((3, 0, 0), (5, 1)));
        assert_eq!(outcome.band_shift, 0);
        assert!(outcome.informative);
    }

    #[test]
    fn applying_calibration_shifts_saturating_and_keeps_material_signals() {
        let base = sound_fit(SoundFitInputs {
            known_not_recognized_density: 0.06, // challenging
            ..SoundFitInputs::default()
        });
        let harder = sound_fit_calibration_outcome(&calibration((0, 0, 2), (0, 0)));
        let dimension = apply_sound_fit_calibration(base.clone(), &harder);
        assert_eq!(dimension.fit, InputFit::TooHard);
        // Material signal untouched, calibration signal appended.
        assert_eq!(dimension.signals[0], base.signals[0]);
        assert_eq!(
            dimension.signals[1].kind,
            FitSignalKind::ComprehensionReportUnclearRatio
        );

        let easier = sound_fit_calibration_outcome(&calibration((2, 0, 0), (0, 0)));
        let dimension = apply_sound_fit_calibration(base.clone(), &easier);
        assert_eq!(dimension.fit, InputFit::Comprehensible);

        // Saturation at the easy end.
        let easy = sound_fit(SoundFitInputs::default());
        let dimension = apply_sound_fit_calibration(easy, &easier);
        assert_eq!(dimension.fit, InputFit::TooEasy);
    }

    #[test]
    fn v3_phrase_capability_personalizes_identical_word_coverage() {
        let weights = ContentFitWeights::default();
        let mut known_phrases = snapshot();
        known_phrases.multi_word_expression_density = Some(0.4);
        known_phrases.unknown_phrase_density = Some(0.0);
        known_phrases.unassessed_phrase_density = Some(0.0);
        let mut unknown_phrases = known_phrases.clone();
        unknown_phrases.unknown_phrase_density = Some(1.0);

        let easier = weighted_meaning_fit(&known_phrases, &weights);
        let harder = weighted_meaning_fit(&unknown_phrases, &weights);
        assert!(harder.score.unwrap() > easier.score.unwrap());
        assert!(band_index(harder.fit) > band_index(easier.fit));
        assert!(
            harder
                .signals
                .iter()
                .any(|signal| signal.kind == FitSignalKind::UnknownPhraseDensity
                    && signal.contribution.unwrap() > 0.0)
        );
    }

    #[test]
    fn feature_coverage_names_missing_evidence_without_defaulting_to_zero() {
        let mut value = snapshot();
        value.speech_rate_wpm = Some(150.0);
        let coverage = FeatureCoverage::compute(&value);
        assert!(coverage.available_features < coverage.total_features);
        assert!(
            coverage
                .missing_features
                .contains(&ContentFitFeatureKind::ReplayDensity)
        );
        assert!(
            !coverage
                .missing_features
                .contains(&ContentFitFeatureKind::SpeechRateWpm)
        );
    }

    #[test]
    fn offline_threshold_search_reports_v3_against_frozen_v2() {
        let language = LanguageCode::parse("en").unwrap();
        let samples = [0.05, 0.30, 0.55, 0.85]
            .into_iter()
            .enumerate()
            .map(|(index, score)| CalibrationSample {
                subject_kind: "media".into(),
                subject_id: format!("m{index}"),
                language: language.clone(),
                snapshot: snapshot(),
                predicted_meaning_score: 0.0,
                predicted_sound_score: score,
                predicted_meaning_band: InputFit::TooEasy,
                predicted_sound_band: band(score, ContentFitThresholds::sound_v3().as_array()),
                v2_meaning_band: InputFit::TooEasy,
                v2_sound_band: InputFit::TooEasy,
                observed_difficulty: Some(score),
                reports_understood_all: 0,
                reports_got_the_gist: 0,
                reports_unclear: 2,
                practice_attempts: 0,
                practice_correct: 0,
                sampled_at_ms: 1,
            })
            .collect::<Vec<_>>();
        let report = evaluate_calibration_samples(&samples);
        assert_eq!(report.sample_count, 4);
        assert!(
            report.v3_mean_absolute_band_error < report.v2_mean_absolute_band_error,
            "{report:?}"
        );
        assert!(report.v3_improvement > 0.0);
    }

    #[test]
    fn sufficient_vocabulary_profile_threshold() {
        let mut profile = ContentDifficultyProfile {
            subject_kind: "media".into(),
            subject_id: "m1".into(),
            language: LanguageCode::parse("en".to_owned()).unwrap(),
            meaning: meaning_fit(MeaningFitInputs {
                unknown_meaning_density: 0.0,
                unassessed_density: 0.6,
            }),
            sound: sound_fit(SoundFitInputs::default()),
            assessed_token_ratio: 0.4,
            evidence_grade: FitEvidenceGrade::InitialEstimate,
            algorithm_version: CONTENT_FIT_ALGORITHM_VERSION.into(),
            computed_at_ms: 42,
            input_fingerprint: "fp".into(),
            feature_snapshot: None,
            feature_coverage: None,
        };
        assert!(!profile.has_sufficient_vocabulary_profile());
        profile.assessed_token_ratio = MIN_ASSESSED_TOKEN_RATIO;
        assert!(profile.has_sufficient_vocabulary_profile());
    }
}
