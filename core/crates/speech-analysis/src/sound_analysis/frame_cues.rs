//! Core-derived word acoustic cues from frame-level AcousticTrack evidence, and
//! the speech/silence spans Core reads as boundary evidence.
//!
//! This is the concrete Measured -> Derived step: Gen measures per-frame energy
//! and pitch (already relative to the recording's own median); Core interprets
//! those measurements into the same `RhythmWordAcousticCue` prominences it would
//! otherwise only receive from Gen's `word_acoustics`. Nothing here fabricates
//! evidence: a word with no frames yields no cue, and a flat recording yields a
//! neutral prominence rather than a peak.

use domain::WordTiming;

use super::config::RhythmWordAcousticCue;
use super::helpers::clamp01;

/// A pitch fall of this many semitones from one word to the next reads as a full
/// pitch reset (score 1.0). Semitones are relative to the recording median, the
/// same unit Gen writes as `f0_rel_st`.
const PITCH_RESET_SPREAD_ST: f32 = 6.0;

/// One acoustic-track frame reduced to the two recording-relative measurements
/// Core needs to derive word prominence. Both are already relative to the
/// recording's own median (Gen computes them that way), so they compare directly
/// across the words of one sentence. Either is absent on a frame where the
/// measurement was not made (for example pitch on an unvoiced frame).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AcousticFrameSample {
    pub time_ms: u64,
    pub energy_rel_db: Option<f32>,
    pub f0_rel_st: Option<f32>,
}

/// One measured speech/silence span in absolute media time. `silence` is true
/// for a measured non-speech span. Core reads these only as evidence: it never
/// turns a measured silence into a phrase boundary the boundary detector did not
/// already find; it only corroborates the detector's boundaries.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpeechActivitySpan {
    pub start_ms: u64,
    pub end_ms: u64,
    pub silence: bool,
}

/// Derives per-word `RhythmWordAcousticCue`s from frame-level evidence, keyed by
/// the word's token index. Energy and pitch prominence are the word's mean
/// recording-relative energy / pitch, min-max normalized against the other words
/// of the same window (the loudest word scores 1.0, the quietest 0.0, a flat set
/// 0.5); pitch reset is the recording-relative pitch fall into the next word.
/// Returns an empty vector when there are no frames or no word timings.
pub fn derive_word_acoustic_cues_from_frames(
    frames: &[AcousticFrameSample],
    word_timings: &[WordTiming],
) -> Vec<RhythmWordAcousticCue> {
    if frames.is_empty() || word_timings.is_empty() {
        return Vec::new();
    }
    // Per-word means over the frames inside the word's [start, end) window.
    let energy: Vec<Option<f32>> = word_timings
        .iter()
        .map(|word| {
            mean(
                frames
                    .iter()
                    .filter(|frame| in_window(frame, word))
                    .filter_map(|frame| frame.energy_rel_db),
            )
        })
        .collect();
    let pitch: Vec<Option<f32>> = word_timings
        .iter()
        .map(|word| {
            mean(
                frames
                    .iter()
                    .filter(|frame| in_window(frame, word))
                    .filter_map(|frame| frame.f0_rel_st),
            )
        })
        .collect();
    let energy_prominence = normalize_within(&energy);
    let pitch_prominence = normalize_within(&pitch);

    word_timings
        .iter()
        .enumerate()
        .filter_map(|(index, word)| {
            let energy_prominence = energy_prominence[index];
            let pitch_prominence = pitch_prominence[index];
            // A phrase-final fall reads as a reset: the recording-relative pitch
            // drops from this word to the next. Needs pitch on both words.
            let pitch_reset_after = match (pitch[index], pitch.get(index + 1).copied().flatten()) {
                (Some(here), Some(next)) if here > next => {
                    Some(clamp01((here - next) / PITCH_RESET_SPREAD_ST))
                }
                _ => None,
            };
            if energy_prominence.is_none()
                && pitch_prominence.is_none()
                && pitch_reset_after.is_none()
            {
                return None;
            }
            Some(RhythmWordAcousticCue {
                token_index: word.token_index,
                energy_prominence,
                pitch_prominence,
                pitch_reset_after,
            })
        })
        .collect()
}

fn in_window(frame: &AcousticFrameSample, word: &WordTiming) -> bool {
    frame.time_ms >= word.start_ms && frame.time_ms < word.end_ms
}

fn mean(values: impl Iterator<Item = f32>) -> Option<f32> {
    let mut sum = 0.0f32;
    let mut count = 0u32;
    for value in values {
        if value.is_finite() {
            sum += value;
            count += 1;
        }
    }
    (count > 0).then(|| sum / count as f32)
}

/// Min-max normalizes the present values to `[0, 1]`; the minimum maps to 0.0,
/// the maximum to 1.0, a flat set to 0.5, and absent entries stay absent.
fn normalize_within(values: &[Option<f32>]) -> Vec<Option<f32>> {
    let mut min = f32::INFINITY;
    let mut max = f32::NEG_INFINITY;
    for value in values.iter().flatten() {
        min = min.min(*value);
        max = max.max(*value);
    }
    if !min.is_finite() || !max.is_finite() {
        return vec![None; values.len()];
    }
    let span = max - min;
    values
        .iter()
        .map(|value| {
            value.map(|value| {
                if span <= f32::EPSILON {
                    0.5
                } else {
                    clamp01((value - min) / span)
                }
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::TimingSource;

    fn frame(time_ms: u64, energy: Option<f32>, pitch: Option<f32>) -> AcousticFrameSample {
        AcousticFrameSample {
            time_ms,
            energy_rel_db: energy,
            f0_rel_st: pitch,
        }
    }

    fn word(token_index: u32, start_ms: u64, end_ms: u64) -> WordTiming {
        WordTiming {
            sentence_id: domain::SubtitleSentenceId::from_fingerprint("s", "s"),
            token_index,
            text: "w".into(),
            start_ms,
            end_ms,
            confidence: Some(0.9),
            timing_source: TimingSource::ForcedAligned,
            provider_id: "p".into(),
            provider_version: "v".into(),
        }
    }

    #[test]
    fn loudest_word_is_the_energy_peak_quietest_is_the_floor() {
        // Word 0 [0,100): quiet (-6 dB). Word 1 [100,200): loud (+6 dB).
        let frames = vec![
            frame(0, Some(-6.0), None),
            frame(50, Some(-6.0), None),
            frame(100, Some(6.0), None),
            frame(150, Some(6.0), None),
        ];
        let words = vec![word(0, 0, 100), word(1, 100, 200)];
        let cues = derive_word_acoustic_cues_from_frames(&frames, &words);
        assert_eq!(cues.len(), 2);
        assert_eq!(cues[0].token_index, 0);
        assert_eq!(cues[0].energy_prominence, Some(0.0));
        assert_eq!(cues[1].token_index, 1);
        assert_eq!(cues[1].energy_prominence, Some(1.0));
    }

    #[test]
    fn pitch_reset_scores_a_fall_into_the_next_word() {
        // Word 0 high pitch (+3 st), word 1 low pitch (-3 st): a 6 st fall = 1.0.
        let frames = vec![frame(0, Some(0.0), Some(3.0)), frame(100, Some(0.0), Some(-3.0))];
        let words = vec![word(0, 0, 100), word(1, 100, 200)];
        let cues = derive_word_acoustic_cues_from_frames(&frames, &words);
        assert_eq!(cues[0].pitch_reset_after, Some(1.0));
        // The last word has no following word, so no reset is derived.
        assert_eq!(cues[1].pitch_reset_after, None);
    }

    #[test]
    fn word_without_frames_yields_no_cue() {
        let frames = vec![frame(0, Some(1.0), None), frame(50, Some(1.0), None)];
        // Word 1 [500,600) has no frames in its window.
        let words = vec![word(0, 0, 100), word(1, 500, 600)];
        let cues = derive_word_acoustic_cues_from_frames(&frames, &words);
        // Only word 0 is covered; a flat single value normalizes to the neutral 0.5.
        assert_eq!(cues.len(), 1);
        assert_eq!(cues[0].token_index, 0);
        assert_eq!(cues[0].energy_prominence, Some(0.5));
    }

    #[test]
    fn empty_inputs_degrade_to_no_cues() {
        assert!(derive_word_acoustic_cues_from_frames(&[], &[word(0, 0, 100)]).is_empty());
        assert!(derive_word_acoustic_cues_from_frames(&[frame(0, Some(1.0), None)], &[]).is_empty());
    }
}
