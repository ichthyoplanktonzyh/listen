use std::path::Path;

use domain::{AudioPauseInterval, AudioWaveformSummary, ShadowingPauseAlignment};
use thiserror::Error;

const FRAME_MS: u64 = 10;
const MINIMUM_PAUSE_MS: u64 = 120;
const SILENCE_DBFS: f32 = -38.0;
const WAVEFORM_BUCKETS: usize = 80;

#[derive(Debug, Clone, PartialEq)]
pub struct ShadowingAudioAnalysis {
    pub duration_delta_ms: i64,
    pub pause_alignment: ShadowingPauseAlignment,
    pub reference_waveform: AudioWaveformSummary,
    pub recording_waveform: AudioWaveformSummary,
}

pub fn compare_pcm16_wav_paths(
    reference_path: impl AsRef<Path>,
    recording_path: impl AsRef<Path>,
) -> Result<ShadowingAudioAnalysis, ShadowingComparisonError> {
    let reference = read_pcm16_mono(reference_path)?;
    let recording = read_pcm16_mono(recording_path)?;
    let reference_pauses = detect_pauses(&reference);
    let recording_pauses = detect_pauses(&recording);
    let mean_absolute_offset_ms = mean_nearest_pause_offset(&reference_pauses, &recording_pauses);
    Ok(ShadowingAudioAnalysis {
        duration_delta_ms: recording.duration_ms() as i64 - reference.duration_ms() as i64,
        pause_alignment: ShadowingPauseAlignment {
            reference_pauses,
            recording_pauses,
            mean_absolute_offset_ms,
        },
        reference_waveform: waveform(&reference),
        recording_waveform: waveform(&recording),
    })
}

struct PcmAudio {
    sample_rate_hz: u32,
    samples: Vec<i16>,
}

impl PcmAudio {
    fn duration_ms(&self) -> u64 {
        self.samples.len() as u64 * 1000 / self.sample_rate_hz as u64
    }
}

fn read_pcm16_mono(path: impl AsRef<Path>) -> Result<PcmAudio, ShadowingComparisonError> {
    let mut reader = hound::WavReader::open(path)?;
    let spec = reader.spec();
    if spec.channels != 1
        || spec.bits_per_sample != 16
        || spec.sample_format != hound::SampleFormat::Int
        || spec.sample_rate == 0
    {
        return Err(ShadowingComparisonError::UnsupportedFormat);
    }
    let samples = reader.samples::<i16>().collect::<Result<Vec<_>, _>>()?;
    if samples.is_empty() {
        return Err(ShadowingComparisonError::EmptyAudio);
    }
    Ok(PcmAudio {
        sample_rate_hz: spec.sample_rate,
        samples,
    })
}

fn waveform(audio: &PcmAudio) -> AudioWaveformSummary {
    let bucket_count = WAVEFORM_BUCKETS.min(audio.samples.len()).max(1);
    let samples_per_bucket = audio.samples.len().div_ceil(bucket_count);
    let mut peaks = Vec::with_capacity(bucket_count);
    let mut rms = Vec::with_capacity(bucket_count);
    for bucket in audio.samples.chunks(samples_per_bucket) {
        let peak = bucket
            .iter()
            .map(|sample| (*sample as f32 / i16::MAX as f32).abs())
            .fold(0.0_f32, f32::max);
        let energy = bucket
            .iter()
            .map(|sample| {
                let normalized = *sample as f32 / i16::MAX as f32;
                normalized * normalized
            })
            .sum::<f32>()
            / bucket.len() as f32;
        peaks.push(peak.clamp(0.0, 1.0));
        rms.push(energy.sqrt().clamp(0.0, 1.0));
    }
    AudioWaveformSummary {
        duration_ms: audio.duration_ms(),
        bucket_ms: audio.duration_ms().div_ceil(bucket_count as u64).max(1),
        peaks,
        rms,
    }
}

fn detect_pauses(audio: &PcmAudio) -> Vec<AudioPauseInterval> {
    let frame_samples = (audio.sample_rate_hz as u64 * FRAME_MS / 1000).max(1) as usize;
    let threshold = 10f32.powf(SILENCE_DBFS / 20.0);
    let mut result = Vec::new();
    let mut silent_start = None;
    let frame_count = audio.samples.len().div_ceil(frame_samples);
    for frame_index in 0..frame_count {
        let start = frame_index * frame_samples;
        let end = (start + frame_samples).min(audio.samples.len());
        let rms = (audio.samples[start..end]
            .iter()
            .map(|sample| {
                let normalized = *sample as f32 / i16::MAX as f32;
                normalized * normalized
            })
            .sum::<f32>()
            / (end - start) as f32)
            .sqrt();
        if rms <= threshold {
            silent_start.get_or_insert(frame_index as u64 * FRAME_MS);
        } else if let Some(pause_start) = silent_start.take() {
            push_pause(&mut result, pause_start, frame_index as u64 * FRAME_MS);
        }
    }
    if let Some(pause_start) = silent_start {
        push_pause(&mut result, pause_start, audio.duration_ms());
    }
    result
}

fn push_pause(result: &mut Vec<AudioPauseInterval>, start_ms: u64, end_ms: u64) {
    if end_ms.saturating_sub(start_ms) >= MINIMUM_PAUSE_MS {
        result.push(AudioPauseInterval { start_ms, end_ms });
    }
}

fn mean_nearest_pause_offset(
    reference: &[AudioPauseInterval],
    recording: &[AudioPauseInterval],
) -> Option<u64> {
    if reference.is_empty() || recording.is_empty() {
        return None;
    }
    let total = reference
        .iter()
        .map(|pause| {
            let midpoint = (pause.start_ms + pause.end_ms) / 2;
            recording
                .iter()
                .map(|candidate| midpoint.abs_diff((candidate.start_ms + candidate.end_ms) / 2))
                .min()
                .unwrap_or(0)
        })
        .sum::<u64>();
    Some(total / reference.len() as u64)
}

#[derive(Debug, Error)]
pub enum ShadowingComparisonError {
    #[error("shadowing comparison requires non-empty mono PCM16 WAV audio")]
    UnsupportedFormat,
    #[error("shadowing comparison audio is empty")]
    EmptyAudio,
    #[error(transparent)]
    Wav(#[from] hound::Error),
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn wav(duration_ms: u64, pauses: &[(u64, u64)]) -> Vec<u8> {
        let mut cursor = Cursor::new(Vec::new());
        let mut writer = hound::WavWriter::new(
            &mut cursor,
            hound::WavSpec {
                channels: 1,
                sample_rate: 16_000,
                bits_per_sample: 16,
                sample_format: hound::SampleFormat::Int,
            },
        )
        .unwrap();
        for index in 0..duration_ms * 16 {
            let time_ms = index / 16;
            let silent = pauses
                .iter()
                .any(|(start, end)| (*start..*end).contains(&time_ms));
            writer
                .write_sample(if silent { 0_i16 } else { 8_000_i16 })
                .unwrap();
        }
        writer.finalize().unwrap();
        cursor.into_inner()
    }

    #[test]
    fn compares_duration_pauses_and_bounded_waveforms() {
        let reference = tempfile_path("reference", &wav(1_000, &[(400, 600)]));
        let recording = tempfile_path("recording", &wav(1_100, &[(450, 650)]));
        let result = compare_pcm16_wav_paths(&reference, &recording).unwrap();
        assert_eq!(result.duration_delta_ms, 100);
        assert_eq!(result.pause_alignment.reference_pauses.len(), 1);
        assert_eq!(result.pause_alignment.recording_pauses.len(), 1);
        assert_eq!(result.pause_alignment.mean_absolute_offset_ms, Some(50));
        assert_eq!(result.reference_waveform.peaks.len(), WAVEFORM_BUCKETS);
        assert!(
            result
                .recording_waveform
                .peaks
                .iter()
                .all(|value| (0.0..=1.0).contains(value))
        );
        let _ = std::fs::remove_file(reference);
        let _ = std::fs::remove_file(recording);
    }

    fn tempfile_path(label: &str, bytes: &[u8]) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(format!(
            "llplayer-shadowing-{label}-{}-{}.wav",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::write(&path, bytes).unwrap();
        path
    }
}
