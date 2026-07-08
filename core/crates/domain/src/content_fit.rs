//! Dual-dimension content fit (ADR 0018).
//!
//! Meaning fit asks whether the learner would understand the transcript if
//! they could read it; sound fit asks whether they can decode the audio by
//! ear at this delivery. Banding is rule-based and monotonic rather than a
//! weighted score: every band must be explainable from the emitted signals.
//!
//! All thresholds in this module are `heuristic_proxy` anchored to published
//! research (see ADR 0018 research notes); they live here as the single
//! definition point, and changing any constant requires bumping
//! [`CONTENT_FIT_ALGORITHM_VERSION`].

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::LanguageCode;

// v1 -> v2 (Phase 3.5 Slice 7): usage-feedback calibration joined the
// pipeline — comprehension self-reports and practice accuracy shift the
// sound-fit band by at most one step and may set `usage_calibrated`.
// Banding thresholds themselves are unchanged from v1.
pub const CONTENT_FIT_ALGORITHM_VERSION: &str = "content-fit-v2";

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
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DifficultyDimension {
    pub fit: InputFit,
    pub signals: Vec<FitSignal>,
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

/// Bands meaning fit from coverage `1 − unknown − unassessed`. Unassessed
/// tokens count against coverage (conservative; invariant 1 keeps them a
/// distinct signal rather than folding them into unknown).
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
            },
            FitSignal {
                kind: FitSignalKind::UnassessedDensity,
                value: unassessed,
                decisive: unassessed > 0.0,
            },
        ],
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
        });
    }
    if calibration.practice_attempts >= CALIBRATION_MIN_PRACTICE_ATTEMPTS {
        informative = true;
        let rate = calibration.practice_correct.min(calibration.practice_attempts) as f32
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
        });
    }
    if let Some(density) = inputs.compression_density {
        signals.push(FitSignal {
            kind: FitSignalKind::CompressionDensity,
            value: density,
            decisive: false,
        });
    }
    if let Some(length) = inputs.mean_chunk_length {
        signals.push(FitSignal {
            kind: FitSignalKind::MeanChunkLength,
            value: length,
            decisive: false,
        });
    }
    DifficultyDimension { fit, signals }
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert_eq!(dim.signals[0].kind, FitSignalKind::KnownNotRecognizedDensity);
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
        };
        assert!(!profile.has_sufficient_vocabulary_profile());
        profile.assessed_token_ratio = MIN_ASSESSED_TOKEN_RATIO;
        assert!(profile.has_sufficient_vocabulary_profile());
    }
}
