use domain::{
    ProsodicBoundaryEvidence, RhythmClaimStatus, RhythmEvidenceClass, RhythmPhraseBoundary,
    RhythmSignalSource, SoundProsodicPhrase, SoundSyllable,
};

use super::constants::{
    LENGTHENING_BOUNDARY_MIN_REFERENCES, LENGTHENING_BOUNDARY_MIN_WORD_MS,
    LENGTHENING_BOUNDARY_RATIO, LENGTHENING_BOUNDARY_RATIO_MAX,
    LENGTHENING_BOUNDARY_REFERENCE_AFTER, LENGTHENING_BOUNDARY_REFERENCE_BEFORE, PAUSE_BOUNDARY_MS,
    PITCH_RESET_BOUNDARY_MIN,
};
use super::helpers::clamp01;
use super::tokens::RhythmToken;

pub(super) fn detect_phrase_boundaries(
    tokens: &[RhythmToken],
    syllables: &[SoundSyllable],
    prosodic_phrases: &[SoundProsodicPhrase],
) -> Vec<RhythmPhraseBoundary> {
    let mut values = Vec::new();
    for pair in tokens.windows(2) {
        if !pair.iter().all(|token| token.timing_audio_supported) {
            continue;
        }
        let gap = pair[1].start_ms.saturating_sub(pair[0].end_ms);
        if gap >= PAUSE_BOUNDARY_MS {
            values.push(RhythmPhraseBoundary {
                after_token_index: Some(pair[0].index),
                before_token_index: Some(pair[1].index),
                at_ms: pair[1].start_ms,
                reason: "Pause between aligned words suggests an intonation phrase boundary."
                    .into(),
                cues: vec!["pause".into()],
                signal_sources: vec![RhythmSignalSource::Timing],
                evidence_class: RhythmEvidenceClass::HeuristicProxy,
                claim_status: RhythmClaimStatus::AudioSupported,
                is_final: false,
                confidence: 0.9,
            });
        }
    }
    for boundary_position in 0..tokens.len().saturating_sub(1) {
        let left = &tokens[boundary_position];
        let right = &tokens[boundary_position + 1];
        let gap = right.start_ms.saturating_sub(left.end_ms);
        if gap >= PAUSE_BOUNDARY_MS {
            continue;
        }
        let lengthening_ratio = pre_boundary_lengthening_ratio(tokens, boundary_position);
        let pitch_reset = left
            .pitch_reset_after_score()
            .filter(|score| *score >= PITCH_RESET_BOUNDARY_MIN);
        if lengthening_ratio.is_none() && pitch_reset.is_none() {
            continue;
        }
        let range = (LENGTHENING_BOUNDARY_RATIO_MAX - LENGTHENING_BOUNDARY_RATIO).max(f32::EPSILON);
        let mut cues = Vec::new();
        let mut signal_sources = Vec::new();
        let mut confidence: f32 = 0.0;
        if let Some(ratio) = lengthening_ratio {
            cues.push("final_lengthening".into());
            signal_sources.push(RhythmSignalSource::Timing);
            confidence = confidence.max(clamp01(
                0.7 + 0.18 * ((ratio - LENGTHENING_BOUNDARY_RATIO) / range),
            ));
        }
        if let Some(score) = pitch_reset {
            cues.push("pitch_reset".into());
            signal_sources.push(RhythmSignalSource::Pitch);
            confidence = confidence.max(clamp01(0.62 + score * 0.28));
        }
        values.push(RhythmPhraseBoundary {
            after_token_index: Some(left.index),
            before_token_index: Some(right.index),
            at_ms: left.end_ms,
            reason: match (lengthening_ratio.is_some(), pitch_reset.is_some()) {
                (true, true) => {
                    "Final lengthening and a pitch reset support this phrase boundary.".into()
                }
                (true, false) => {
                    "The pre-boundary word is lengthened relative to nearby words.".into()
                }
                (false, true) => {
                    "A pitch reset between words supports this phrase boundary.".into()
                }
                (false, false) => unreachable!(),
            },
            cues,
            signal_sources,
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status: RhythmClaimStatus::AudioSupported,
            is_final: false,
            confidence,
        });
    }
    for phrase in prosodic_phrases {
        if phrase.boundary_evidence != ProsodicBoundaryEvidence::Pause {
            continue;
        }
        let Some(first_syllable) = phrase.syllables.first() else {
            continue;
        };
        let Some(syllable) = syllables.get(*first_syllable as usize) else {
            continue;
        };
        if values
            .iter()
            .any(|value| value.at_ms.abs_diff(syllable.start_ms) < 20)
        {
            continue;
        }
        let before = tokens
            .iter()
            .rev()
            .find(|token| token.end_ms <= syllable.start_ms)
            .map(|token| token.index);
        let after = tokens
            .iter()
            .find(|token| token.start_ms >= syllable.start_ms)
            .map(|token| token.index);
        values.push(RhythmPhraseBoundary {
            after_token_index: before,
            before_token_index: after,
            at_ms: syllable.start_ms,
            reason: "Prosodic phrase detector found a pause boundary.".into(),
            cues: vec!["pause".into()],
            signal_sources: vec![RhythmSignalSource::Timing],
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status: RhythmClaimStatus::AudioSupported,
            is_final: false,
            confidence: phrase.confidence,
        });
    }
    values.sort_by_key(|value| value.at_ms);
    values
}

fn pre_boundary_lengthening_ratio(tokens: &[RhythmToken], boundary_position: usize) -> Option<f32> {
    let left = tokens.get(boundary_position)?;
    if !left.timing_audio_supported {
        return None;
    }
    if left.duration_ms() < LENGTHENING_BOUNDARY_MIN_WORD_MS {
        return None;
    }
    let unit_ms = normalized_unit_ms(left);
    let before_start = boundary_position.saturating_sub(LENGTHENING_BOUNDARY_REFERENCE_BEFORE);
    let after_end =
        (boundary_position + 1 + LENGTHENING_BOUNDARY_REFERENCE_AFTER).min(tokens.len());
    let mut references = tokens[before_start..boundary_position]
        .iter()
        .chain(tokens[boundary_position + 1..after_end].iter())
        .filter(|token| token.timing_audio_supported && token.duration_ms() > 0)
        .map(normalized_unit_ms)
        .filter(|value| *value > 0.0)
        .collect::<Vec<_>>();
    if references.len() < LENGTHENING_BOUNDARY_MIN_REFERENCES {
        return None;
    }
    references.sort_by(|left, right| left.total_cmp(right));
    let baseline = median_f32(&references);
    if baseline <= f32::EPSILON {
        return None;
    }
    let ratio = unit_ms / baseline;
    (ratio >= LENGTHENING_BOUNDARY_RATIO).then_some(ratio)
}

fn normalized_unit_ms(token: &RhythmToken) -> f32 {
    token.duration_ms() as f32 / token.expected_units().max(1) as f32
}

fn median_f32(sorted: &[f32]) -> f32 {
    let middle = sorted.len() / 2;
    if sorted.len().is_multiple_of(2) {
        (sorted[middle - 1] + sorted[middle]) / 2.0
    } else {
        sorted[middle]
    }
}
