//! Lightweight word-level acoustic features for the bundled consumer runtime.

use std::collections::HashMap;
use std::io::Cursor;

use domain::{SubtitleSentenceId, TimingSource, WordTiming};
use serde::{Deserialize, Serialize};

pub const PROVIDER_ID: &str = "rust-word-acoustic-prominence";
pub const PROVIDER_VERSION: &str = "v1";

const ENERGY_PROMINENCE_DB_FOR_MAX: f32 = 6.0;
const PITCH_PROMINENCE_SEMITONES_FOR_MAX: f32 = 6.0;
const PITCH_FRAME_MS: u64 = 40;
const PITCH_HOP_MS: u64 = 20;
const MAX_PITCH_FRAMES_PER_WORD: usize = 8;
const MIN_F0_HZ: f32 = 65.0;
const MAX_F0_HZ: f32 = 400.0;
const MIN_PITCH_CORRELATION: f32 = 0.62;
const MIN_PITCH_PROMINENCE: f32 = 0.08;
const MIN_PITCH_RESET: f32 = 0.15;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WordAcousticAnalysis {
    pub sample_rate_hz: u32,
    pub cues: Vec<WordAcousticMeasurement>,
}

impl WordAcousticAnalysis {
    pub fn positive_energy_cue_count(&self) -> usize {
        self.cues
            .iter()
            .filter(|cue| cue.energy_prominence.unwrap_or(0.0) > 0.0)
            .count()
    }

    pub fn positive_pitch_cue_count(&self) -> usize {
        self.cues
            .iter()
            .filter(|cue| cue.pitch_prominence.unwrap_or(0.0) > 0.0)
            .count()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WordAcousticMeasurement {
    pub sentence_id: SubtitleSentenceId,
    pub token_index: u32,
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub energy_prominence: Option<f32>,
    pub dbfs: Option<f32>,
    pub sentence_median_dbfs: Option<f32>,
    pub db_delta_from_sentence_median: Option<f32>,
    pub pitch_prominence: Option<f32>,
    pub f0_median_hz: Option<f32>,
    pub f0_range_semitones: Option<f32>,
    pub voiced_frame_ratio: f32,
    pub pitch_reset_after: Option<f32>,
}

#[derive(Debug, Clone)]
struct PendingMeasurement {
    timing: WordTiming,
    dbfs: Option<f32>,
    pitch: PitchTrack,
}

#[derive(Debug, Clone, Default)]
struct PitchTrack {
    median_hz: Option<f32>,
    range_semitones: Option<f32>,
    first_hz: Option<f32>,
    last_hz: Option<f32>,
    voiced_frame_ratio: f32,
}

pub fn analyze_word_acoustics_from_pcm_wav(
    wav_bytes: &[u8],
    timings: &[WordTiming],
) -> Result<WordAcousticAnalysis, WordAcousticError> {
    let (samples, sample_rate_hz) = read_pcm16_mono(wav_bytes)?;
    let pitch_sample_rate_hz = sample_rate_hz.min(8_000);
    let pitch_samples = downsample(&samples, sample_rate_hz, pitch_sample_rate_hz);
    let mut pending = timings
        .iter()
        .filter(|timing| timing.timing_source != TimingSource::Estimated)
        .filter(|timing| timing.end_ms > timing.start_ms)
        .map(|timing| PendingMeasurement {
            timing: timing.clone(),
            dbfs: rms_dbfs_for_window(&samples, sample_rate_hz, timing.start_ms, timing.end_ms),
            pitch: pitch_track_for_window(
                &pitch_samples,
                pitch_sample_rate_hz,
                timing.start_ms,
                timing.end_ms,
            ),
        })
        .collect::<Vec<_>>();
    pending.sort_by_key(|value| {
        (
            value.timing.sentence_id.as_str().to_owned(),
            value.timing.start_ms,
            value.timing.token_index,
        )
    });

    let mut by_sentence = HashMap::<SubtitleSentenceId, Vec<usize>>::new();
    for (index, value) in pending.iter().enumerate() {
        by_sentence
            .entry(value.timing.sentence_id.clone())
            .or_default()
            .push(index);
    }

    let mut cues = Vec::with_capacity(pending.len());
    for indexes in by_sentence.values() {
        let sentence_median_dbfs = median(
            indexes
                .iter()
                .filter_map(|index| pending[*index].dbfs)
                .collect(),
        );
        let sentence_median_f0 = median(
            indexes
                .iter()
                .filter_map(|index| pending[*index].pitch.median_hz)
                .collect(),
        );

        for (position, index) in indexes.iter().copied().enumerate() {
            let value = &pending[index];
            let db_delta = value
                .dbfs
                .zip(sentence_median_dbfs)
                .map(|(dbfs, baseline)| dbfs - baseline);
            let energy_prominence =
                db_delta.map(|delta| (delta / ENERGY_PROMINENCE_DB_FOR_MAX).clamp(0.0, 1.0));
            let pitch_prominence = pitch_prominence(&value.pitch, sentence_median_f0);
            let pitch_reset_after = indexes
                .get(position + 1)
                .and_then(|next| pitch_reset(&value.pitch, &pending[*next].pitch));
            cues.push(WordAcousticMeasurement {
                sentence_id: value.timing.sentence_id.clone(),
                token_index: value.timing.token_index,
                text: value.timing.text.clone(),
                start_ms: value.timing.start_ms,
                end_ms: value.timing.end_ms,
                energy_prominence,
                dbfs: value.dbfs,
                sentence_median_dbfs,
                db_delta_from_sentence_median: db_delta,
                pitch_prominence,
                f0_median_hz: value.pitch.median_hz,
                f0_range_semitones: value.pitch.range_semitones,
                voiced_frame_ratio: value.pitch.voiced_frame_ratio,
                pitch_reset_after,
            });
        }
    }
    cues.sort_by_key(|cue| (cue.start_ms, cue.token_index));

    Ok(WordAcousticAnalysis {
        sample_rate_hz,
        cues,
    })
}

fn read_pcm16_mono(wav_bytes: &[u8]) -> Result<(Vec<f32>, u32), WordAcousticError> {
    let mut reader = hound::WavReader::new(Cursor::new(wav_bytes))
        .map_err(|error| WordAcousticError::InvalidWav(error.to_string()))?;
    let spec = reader.spec();
    if spec.channels != 1
        || spec.bits_per_sample != 16
        || spec.sample_format != hound::SampleFormat::Int
    {
        return Err(WordAcousticError::UnsupportedWav);
    }
    let samples = reader
        .samples::<i16>()
        .map(|sample| {
            sample
                .map(|value| f32::from(value) / 32_768.0)
                .map_err(|error| WordAcousticError::InvalidWav(error.to_string()))
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok((samples, spec.sample_rate))
}

fn rms_dbfs_for_window(
    samples: &[f32],
    sample_rate_hz: u32,
    start_ms: u64,
    end_ms: u64,
) -> Option<f32> {
    let (start, end) = sample_window(samples.len(), sample_rate_hz, start_ms, end_ms)?;
    let window = &samples[start..end];
    let mean_square =
        window.iter().map(|sample| sample * sample).sum::<f32>() / window.len() as f32;
    Some(20.0 * mean_square.sqrt().max(1e-9).log10())
}

fn downsample(samples: &[f32], source_rate_hz: u32, target_rate_hz: u32) -> Vec<f32> {
    if source_rate_hz <= target_rate_hz {
        return samples.to_vec();
    }
    let factor = (source_rate_hz / target_rate_hz).max(1) as usize;
    samples
        .chunks(factor)
        .map(|chunk| chunk.iter().sum::<f32>() / chunk.len() as f32)
        .collect()
}

fn pitch_track_for_window(
    samples: &[f32],
    sample_rate_hz: u32,
    start_ms: u64,
    end_ms: u64,
) -> PitchTrack {
    let Some((start, end)) = sample_window(samples.len(), sample_rate_hz, start_ms, end_ms) else {
        return PitchTrack::default();
    };
    let frame_len = (u64::from(sample_rate_hz) * PITCH_FRAME_MS / 1_000) as usize;
    let hop_len = (u64::from(sample_rate_hz) * PITCH_HOP_MS / 1_000).max(1) as usize;
    if frame_len == 0 || end.saturating_sub(start) < frame_len {
        return PitchTrack::default();
    }
    let available_frames = 1 + (end - start - frame_len) / hop_len;
    let frame_indexes = evenly_spaced_indexes(available_frames, MAX_PITCH_FRAMES_PER_WORD);
    let mut estimates = Vec::with_capacity(frame_indexes.len());
    for frame_index in frame_indexes.iter().copied() {
        let frame_start = start + frame_index * hop_len;
        if let Some(f0) = estimate_f0(
            &samples[frame_start..frame_start + frame_len],
            sample_rate_hz,
        ) {
            estimates.push(f0);
        }
    }
    if estimates.is_empty() {
        return PitchTrack::default();
    }
    let voiced_frame_ratio = estimates.len() as f32 / frame_indexes.len().max(1) as f32;
    let first_hz = estimates.first().copied();
    let last_hz = estimates.last().copied();
    estimates.sort_by(f32::total_cmp);
    let median_hz = median(estimates.clone());
    let low = percentile(&estimates, 0.1);
    let high = percentile(&estimates, 0.9);
    let range_semitones = low
        .zip(high)
        .filter(|(low, high)| *low > 0.0 && high >= low)
        .map(|(low, high)| 12.0 * (high / low).log2());
    PitchTrack {
        median_hz,
        range_semitones,
        first_hz,
        last_hz,
        voiced_frame_ratio,
    }
}

fn estimate_f0(frame: &[f32], sample_rate_hz: u32) -> Option<f32> {
    let mean = frame.iter().sum::<f32>() / frame.len() as f32;
    let centered = frame.iter().map(|value| value - mean).collect::<Vec<_>>();
    let energy = centered.iter().map(|value| value * value).sum::<f32>() / centered.len() as f32;
    if energy.sqrt() < 0.003 {
        return None;
    }
    let min_lag = ((sample_rate_hz as f32 / MAX_F0_HZ).floor() as usize).max(1);
    let max_lag =
        ((sample_rate_hz as f32 / MIN_F0_HZ).ceil() as usize).min(centered.len().saturating_sub(2));
    if max_lag <= min_lag {
        return None;
    }
    let correlations = (min_lag..=max_lag)
        .map(|lag| normalized_autocorrelation(&centered, lag))
        .collect::<Vec<_>>();
    let (best_offset, best_correlation) = correlations
        .iter()
        .copied()
        .enumerate()
        .max_by(|left, right| left.1.total_cmp(&right.1))?;
    if best_correlation < MIN_PITCH_CORRELATION {
        return None;
    }
    let lag = min_lag + best_offset;
    let refined_lag = if best_offset > 0 && best_offset + 1 < correlations.len() {
        parabolic_peak(
            lag as f32,
            correlations[best_offset - 1],
            best_correlation,
            correlations[best_offset + 1],
        )
    } else {
        lag as f32
    };
    Some(sample_rate_hz as f32 / refined_lag.max(1.0))
}

fn normalized_autocorrelation(frame: &[f32], lag: usize) -> f32 {
    let mut numerator = 0.0;
    let mut left_energy = 0.0;
    let mut right_energy = 0.0;
    for index in 0..frame.len() - lag {
        let left = frame[index];
        let right = frame[index + lag];
        numerator += left * right;
        left_energy += left * left;
        right_energy += right * right;
    }
    let denominator = (left_energy * right_energy).sqrt();
    if denominator <= f32::EPSILON {
        0.0
    } else {
        numerator / denominator
    }
}

fn parabolic_peak(center: f32, left: f32, middle: f32, right: f32) -> f32 {
    let denominator = left - 2.0 * middle + right;
    if denominator.abs() <= f32::EPSILON {
        center
    } else {
        center + 0.5 * (left - right) / denominator
    }
}

fn pitch_prominence(track: &PitchTrack, sentence_median_f0: Option<f32>) -> Option<f32> {
    let median_hz = track.median_hz?;
    let range_score =
        (track.range_semitones.unwrap_or(0.0) / PITCH_PROMINENCE_SEMITONES_FOR_MAX).clamp(0.0, 1.0);
    let deviation_score = sentence_median_f0
        .filter(|baseline| *baseline > 0.0)
        .map(|baseline| {
            (12.0 * (median_hz / baseline).log2()).abs() / PITCH_PROMINENCE_SEMITONES_FOR_MAX
        })
        .unwrap_or(0.0)
        .clamp(0.0, 1.0);
    let prominence =
        (0.65 * range_score + 0.35 * deviation_score) * track.voiced_frame_ratio.clamp(0.0, 1.0);
    (prominence >= MIN_PITCH_PROMINENCE).then_some(prominence.clamp(0.0, 1.0))
}

fn pitch_reset(left: &PitchTrack, right: &PitchTrack) -> Option<f32> {
    let (Some(left_hz), Some(right_hz)) = (left.last_hz, right.first_hz) else {
        return None;
    };
    if left_hz <= 0.0 || right_hz <= 0.0 {
        return None;
    }
    let upward_reset_semitones = 12.0 * (right_hz / left_hz).log2();
    let score = (upward_reset_semitones / PITCH_PROMINENCE_SEMITONES_FOR_MAX).clamp(0.0, 1.0);
    (score >= MIN_PITCH_RESET).then_some(score)
}

fn sample_window(
    sample_count: usize,
    sample_rate_hz: u32,
    start_ms: u64,
    end_ms: u64,
) -> Option<(usize, usize)> {
    let start = ((start_ms.saturating_mul(u64::from(sample_rate_hz))) / 1_000)
        .min(sample_count as u64) as usize;
    let end = ((end_ms.saturating_mul(u64::from(sample_rate_hz))) / 1_000).min(sample_count as u64)
        as usize;
    (end > start).then_some((start, end))
}

fn evenly_spaced_indexes(count: usize, maximum: usize) -> Vec<usize> {
    if count <= maximum {
        return (0..count).collect();
    }
    (0..maximum)
        .map(|index| index * (count - 1) / (maximum - 1))
        .collect()
}

fn median(mut values: Vec<f32>) -> Option<f32> {
    values.retain(|value| value.is_finite());
    values.sort_by(f32::total_cmp);
    if values.is_empty() {
        return None;
    }
    let middle = values.len() / 2;
    if values.len().is_multiple_of(2) {
        Some((values[middle - 1] + values[middle]) / 2.0)
    } else {
        Some(values[middle])
    }
}

fn percentile(sorted: &[f32], percentile: f32) -> Option<f32> {
    if sorted.is_empty() {
        return None;
    }
    let index = ((sorted.len() - 1) as f32 * percentile.clamp(0.0, 1.0)).round() as usize;
    sorted.get(index).copied()
}

#[derive(Debug, thiserror::Error)]
pub enum WordAcousticError {
    #[error("invalid WAV: {0}")]
    InvalidWav(String),
    #[error("word acoustics require mono PCM16 WAV")]
    UnsupportedWav,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f32::consts::TAU;

    fn wav_with_words() -> Vec<u8> {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: 16_000,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut cursor = Cursor::new(Vec::new());
        {
            let mut writer = hound::WavWriter::new(&mut cursor, spec).unwrap();
            for index in 0..16_000 {
                let time = index as f32 / 16_000.0;
                let (frequency, amplitude) = if index < 8_000 {
                    (120.0, 0.12)
                } else {
                    (220.0 + 80.0 * ((time - 0.5) * 2.0), 0.55)
                };
                let sample = (amplitude * (TAU * frequency * time).sin() * i16::MAX as f32) as i16;
                writer.write_sample(sample).unwrap();
            }
            writer.finalize().unwrap();
        }
        cursor.into_inner()
    }

    fn timings() -> Vec<WordTiming> {
        let sentence_id = SubtitleSentenceId::parse("sentence-1").unwrap();
        [(0, "quiet", 0, 500), (1, "focus", 500, 1_000)]
            .into_iter()
            .map(|(token_index, text, start_ms, end_ms)| WordTiming {
                sentence_id: sentence_id.clone(),
                token_index,
                text: text.into(),
                start_ms,
                end_ms,
                confidence: Some(0.8),
                timing_source: TimingSource::AsrReported,
                provider_id: "whisper.cpp".into(),
                provider_version: "dtw-v2".into(),
            })
            .collect()
    }

    #[test]
    fn extracts_energy_and_pitch_prominence_without_a_model() {
        let analysis = analyze_word_acoustics_from_pcm_wav(&wav_with_words(), &timings()).unwrap();
        assert_eq!(analysis.sample_rate_hz, 16_000);
        assert_eq!(analysis.cues.len(), 2);
        assert!(analysis.cues[1].energy_prominence.unwrap() > 0.5);
        assert!(analysis.cues[1].pitch_prominence.unwrap() > 0.1);
        assert!(analysis.cues[0].f0_median_hz.unwrap() > 100.0);
        assert!(analysis.cues[1].f0_median_hz.unwrap() > 180.0);
    }

    #[test]
    fn estimated_timings_do_not_claim_word_acoustics() {
        let mut values = timings();
        values[0].timing_source = TimingSource::Estimated;
        let analysis = analyze_word_acoustics_from_pcm_wav(&wav_with_words(), &values).unwrap();
        assert_eq!(analysis.cues.len(), 1);
        assert_eq!(analysis.cues[0].token_index, 1);
    }
}
