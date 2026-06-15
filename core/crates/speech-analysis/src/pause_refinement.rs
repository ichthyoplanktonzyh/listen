//! Refines coarse word timings with audible pauses from local PCM WAV audio.

use std::io::Cursor;

use domain::{TimingSource, WordTiming};
use serde::{Deserialize, Serialize};

pub const PROVIDER_ID: &str = "local-energy-pause-refiner";
pub const PROVIDER_VERSION: &str = "v1";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PauseRefinementConfig {
    pub frame_ms: u64,
    pub minimum_pause_ms: u64,
    pub search_radius_ms: u64,
    pub silence_dbfs: f32,
}

impl Default for PauseRefinementConfig {
    fn default() -> Self {
        Self {
            frame_ms: 10,
            minimum_pause_ms: 120,
            search_radius_ms: 350,
            silence_dbfs: -38.0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DetectedPause {
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PauseRefinementResult {
    pub timings: Vec<WordTiming>,
    pub pauses: Vec<DetectedPause>,
}

pub fn refine_word_timings_from_pcm_wav(
    wav_bytes: &[u8],
    timings: &[WordTiming],
    config: &PauseRefinementConfig,
) -> Result<PauseRefinementResult, PauseRefinementError> {
    if timings.len() < 2 {
        return Ok(PauseRefinementResult {
            timings: timings.to_vec(),
            pauses: Vec::new(),
        });
    }
    if config.frame_ms == 0 || config.minimum_pause_ms == 0 {
        return Err(PauseRefinementError::InvalidConfig);
    }

    let mut reader = hound::WavReader::new(Cursor::new(wav_bytes))
        .map_err(|error| PauseRefinementError::InvalidWav(error.to_string()))?;
    let spec = reader.spec();
    if spec.channels != 1 || spec.bits_per_sample != 16 {
        return Err(PauseRefinementError::UnsupportedWav);
    }
    let samples = reader
        .samples::<i16>()
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| PauseRefinementError::InvalidWav(error.to_string()))?;
    let silent_runs = silent_runs(&samples, spec.sample_rate, config);
    let mut refined = timings.to_vec();
    let mut pauses = Vec::new();

    for boundary in 0..timings.len() - 1 {
        let left = &timings[boundary];
        let right = &timings[boundary + 1];
        if left.sentence_id != right.sentence_id {
            continue;
        }
        let boundary_ms = left.end_ms.saturating_add(right.start_ms) / 2;
        let search_start = boundary_ms.saturating_sub(config.search_radius_ms);
        let search_end = boundary_ms.saturating_add(config.search_radius_ms);
        let Some(&(pause_start, pause_end)) = silent_runs
            .iter()
            .filter(|(start, end)| *end >= search_start && *start <= search_end)
            .min_by_key(|(start, end)| {
                let center = start.saturating_add(*end) / 2;
                center.abs_diff(boundary_ms)
            })
        else {
            continue;
        };
        if pause_start <= left.start_ms || pause_end >= right.end_ms {
            continue;
        }

        let (before, after) = refined.split_at_mut(boundary + 1);
        let refined_left = &mut before[boundary];
        let refined_right = &mut after[0];
        refined_left.end_ms = pause_start.max(refined_left.start_ms);
        refined_right.start_ms = pause_end;
        for timing in [refined_left, refined_right] {
            timing.timing_source = TimingSource::ForcedAligned;
            timing.provider_id = PROVIDER_ID.into();
            timing.provider_version = PROVIDER_VERSION.into();
        }
        pauses.push(DetectedPause {
            left_token_index: left.token_index,
            right_token_index: right.token_index,
            start_ms: pause_start,
            end_ms: pause_end,
            duration_ms: pause_end.saturating_sub(pause_start),
        });
    }

    Ok(PauseRefinementResult {
        timings: refined,
        pauses,
    })
}

fn silent_runs(
    samples: &[i16],
    sample_rate: u32,
    config: &PauseRefinementConfig,
) -> Vec<(u64, u64)> {
    let frame_samples = (u64::from(sample_rate) * config.frame_ms / 1_000).max(1) as usize;
    let threshold = 10f32.powf(config.silence_dbfs / 20.0);
    let silent = samples
        .chunks(frame_samples)
        .map(|frame| {
            let mean_square = frame
                .iter()
                .map(|sample| {
                    let normalized = f32::from(*sample) / f32::from(i16::MAX);
                    normalized * normalized
                })
                .sum::<f32>()
                / frame.len() as f32;
            mean_square.sqrt() <= threshold
        })
        .collect::<Vec<_>>();
    let minimum_frames = config.minimum_pause_ms.div_ceil(config.frame_ms) as usize;
    let mut runs = Vec::new();
    let mut start = None;
    for (index, is_silent) in silent.iter().copied().chain([false]).enumerate() {
        match (start, is_silent) {
            (None, true) => start = Some(index),
            (Some(run_start), false) => {
                if index - run_start >= minimum_frames {
                    runs.push((
                        run_start as u64 * config.frame_ms,
                        index as u64 * config.frame_ms,
                    ));
                }
                start = None;
            }
            _ => {}
        }
    }
    runs
}

#[derive(Debug, thiserror::Error)]
pub enum PauseRefinementError {
    #[error("invalid pause refinement configuration")]
    InvalidConfig,
    #[error("invalid WAV: {0}")]
    InvalidWav(String),
    #[error("pause refinement requires mono PCM16 WAV")]
    UnsupportedWav,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::chunk_partition::{ChunkPartitionConfig, partition_sentence};
    use domain::{
        SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs,
    };

    fn wav_with_pause(start_ms: u64, end_ms: u64, duration_ms: u64) -> Vec<u8> {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: 16_000,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut cursor = Cursor::new(Vec::new());
        {
            let mut writer = hound::WavWriter::new(&mut cursor, spec).unwrap();
            let pause_start = start_ms * 16;
            let pause_end = end_ms * 16;
            for index in 0..duration_ms * 16 {
                let sample = if (pause_start..pause_end).contains(&index) {
                    0
                } else {
                    8_000
                };
                writer.write_sample(sample).unwrap();
            }
            writer.finalize().unwrap();
        }
        cursor.into_inner()
    }

    fn timings() -> Vec<WordTiming> {
        let sentence_id = SubtitleSentenceId::parse("s1").unwrap();
        ["before", "after"]
            .into_iter()
            .enumerate()
            .map(|(index, text)| WordTiming {
                sentence_id: sentence_id.clone(),
                token_index: index as u32,
                text: text.into(),
                start_ms: if index == 0 { 100 } else { 500 },
                end_ms: if index == 0 { 500 } else { 900 },
                confidence: None,
                timing_source: TimingSource::AsrReported,
                provider_id: "whisper.cpp".into(),
                provider_version: "dtw-v2".into(),
            })
            .collect()
    }

    fn sentence(words: &[&str]) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("s1").unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(2_000),
            original_text: words.join(" "),
            display_text: words.join(" "),
            tokens: words
                .iter()
                .enumerate()
                .map(|(index, text)| SubtitleToken {
                    index: index as u32,
                    kind: SubtitleTokenKind::Word,
                    text: (*text).into(),
                    normalized: Some(text.to_ascii_lowercase()),
                    start_char: 0,
                    end_char: text.len() as u32,
                })
                .collect(),
        }
    }

    #[test]
    fn audible_pause_restores_inter_word_gap() {
        let result = refine_word_timings_from_pcm_wav(
            &wav_with_pause(400, 600, 1_000),
            &timings(),
            &PauseRefinementConfig::default(),
        )
        .unwrap();
        assert_eq!(result.pauses[0].start_ms, 400);
        assert_eq!(result.pauses[0].end_ms, 600);
        assert_eq!(result.timings[0].end_ms, 400);
        assert_eq!(result.timings[1].start_ms, 600);
        assert_eq!(result.timings[0].timing_source, TimingSource::ForcedAligned);
    }

    #[test]
    fn restored_pause_becomes_chunk_boundary() {
        let sentence = sentence(&["we", "can", "hear", "the", "pause", "now"]);
        let mut values = timings();
        values.clear();
        for (index, (start_ms, end_ms)) in [
            (100, 250),
            (300, 450),
            (600, 950),
            (950, 1_200),
            (1_250, 1_400),
            (1_450, 1_600),
        ]
        .into_iter()
        .enumerate()
        {
            values.push(WordTiming {
                sentence_id: sentence.id.clone(),
                token_index: index as u32,
                text: sentence.tokens[index].text.clone(),
                start_ms,
                end_ms,
                confidence: None,
                timing_source: TimingSource::AsrReported,
                provider_id: "whisper.cpp".into(),
                provider_version: "dtw-v2".into(),
            });
        }
        let before = partition_sentence(
            &sentence,
            &values,
            &[],
            &ChunkPartitionConfig {
                pre_boundary_lengthening: None,
                learned_prosodic: None,
                ..ChunkPartitionConfig::default()
            },
        );
        let refined = refine_word_timings_from_pcm_wav(
            &wav_with_pause(800, 1_100, 2_000),
            &values,
            &PauseRefinementConfig::default(),
        )
        .unwrap();
        let after = partition_sentence(
            &sentence,
            &refined.timings,
            &[],
            &ChunkPartitionConfig {
                pre_boundary_lengthening: None,
                learned_prosodic: None,
                ..ChunkPartitionConfig::default()
            },
        );
        assert_eq!(before.chunks.len(), 1);
        assert_eq!(after.chunks.len(), 2);
        assert_eq!(after.chunks[0].text, "we can hear");
    }
}
