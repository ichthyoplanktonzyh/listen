use std::path::Path;

use domain::{
    AudioPauseInterval, AudioQualitySummary, AudioWaveformSummary, DetectedPhone,
    ShadowingAbstainReason, ShadowingAnalysis, ShadowingEvidenceComponent,
    ShadowingEvidenceCoverage, ShadowingMissingEvidence, ShadowingMissingEvidenceReason,
    ShadowingPauseAlignment, ShadowingPhoneAlignmentDetail, ShadowingPhoneAlignmentStatus,
    ShadowingProsodyComparison, ShadowingProviderInfo, ShadowingWordDetail, ShadowingWordStatus,
    SubtitleSentence, SubtitleTokenKind, TimingSource, WordTiming,
};
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

#[derive(Debug, Clone, PartialEq)]
pub struct RecordingAudioAnalysis {
    pub duration_ms: u64,
    pub pauses: Vec<AudioPauseInterval>,
    pub waveform: AudioWaveformSummary,
}

pub fn analyze_pcm16_wav_path(
    path: impl AsRef<Path>,
) -> Result<RecordingAudioAnalysis, ShadowingComparisonError> {
    let audio = read_pcm16_mono(path)?;
    Ok(RecordingAudioAnalysis {
        duration_ms: audio.duration_ms(),
        pauses: detect_pauses(&audio),
        waveform: waveform(&audio),
    })
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

// ==========================================
// Shadowing V2 Implementation
// ==========================================

#[derive(Debug, Clone, PartialEq)]
pub struct CanonicalPhoneWithTime {
    pub symbol: String,
    pub token_index: u32,
    pub stress: Option<u8>,
    pub start_ms: u64,
    pub end_ms: u64,
}

pub struct NormalizedAudio {
    pub samples: Vec<f32>,
    pub sample_rate_hz: u32,
    pub quality: AudioQualitySummary,
}

fn resample(samples: &[f32], from_rate: u32, to_rate: u32) -> Vec<f32> {
    if from_rate == to_rate {
        return samples.to_vec();
    }
    let ratio = to_rate as f32 / from_rate as f32;
    let new_len = (samples.len() as f32 * ratio) as usize;
    let mut resampled = Vec::with_capacity(new_len);
    for i in 0..new_len {
        let src_index = i as f32 / ratio;
        let index_floor = src_index.floor() as usize;
        let index_ceil = (index_floor + 1).min(samples.len() - 1);
        let weight = src_index - index_floor as f32;
        let sample = samples[index_floor] * (1.0 - weight) + samples[index_ceil] * weight;
        resampled.push(sample);
    }
    resampled
}

fn normalize_loudness(samples: &mut [f32]) {
    let max_peak = samples.iter().map(|&s| s.abs()).fold(0.0f32, f32::max);
    if max_peak > 0.001 {
        let scale = 0.8 / max_peak;
        for s in samples.iter_mut() {
            *s *= scale;
        }
    }
}

fn estimate_snr(samples: &[f32], frame_size: usize) -> f32 {
    let mut energies = Vec::new();
    for chunk in samples.chunks(frame_size) {
        if chunk.is_empty() {
            continue;
        }
        let energy: f32 = chunk.iter().map(|&s| s * s).sum::<f32>() / chunk.len() as f32;
        energies.push(energy);
    }
    if energies.is_empty() {
        return 0.0;
    }
    energies.sort_by(f32::total_cmp);
    let noise_count = (energies.len() / 10).max(1);
    let noise_energy: f32 = energies.iter().take(noise_count).sum::<f32>() / noise_count as f32;
    let signal_count = (energies.len() * 3 / 10).max(1);
    let signal_energy: f32 =
        energies.iter().rev().take(signal_count).sum::<f32>() / signal_count as f32;

    if noise_energy > 1e-10 {
        10.0 * (signal_energy / noise_energy).max(1.0).log10()
    } else {
        50.0
    }
}

fn calculate_clipping_ratio(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let clipped = samples.iter().filter(|&&s| s.abs() >= 0.99).count();
    clipped as f32 / samples.len() as f32
}

fn calculate_dc_offset(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    samples.iter().sum::<f32>() / samples.len() as f32
}

pub fn load_and_normalize_audio(
    path: impl AsRef<Path>,
) -> Result<NormalizedAudio, ShadowingComparisonError> {
    let mut reader = hound::WavReader::open(path)?;
    let spec = reader.spec();

    if spec.sample_rate == 0 || spec.channels == 0 {
        return Err(ShadowingComparisonError::UnsupportedFormat);
    }

    let samples_raw = match spec.sample_format {
        hound::SampleFormat::Int => {
            if spec.bits_per_sample == 16 {
                reader.samples::<i16>().collect::<Result<Vec<_>, _>>()?
            } else {
                return Err(ShadowingComparisonError::UnsupportedFormat);
            }
        }
        _ => return Err(ShadowingComparisonError::UnsupportedFormat),
    };

    if samples_raw.is_empty() {
        return Err(ShadowingComparisonError::EmptyAudio);
    }

    let mono_samples = if spec.channels > 1 {
        let ch = spec.channels as usize;
        let mut mixed = Vec::with_capacity(samples_raw.len() / ch);
        for chunk in samples_raw.chunks_exact(ch) {
            let sum: i32 = chunk.iter().map(|&s| s as i32).sum();
            mixed.push((sum / spec.channels as i32) as i16);
        }
        mixed
    } else {
        samples_raw
    };

    let f32_samples: Vec<f32> = mono_samples.iter().map(|&s| s as f32 / 32768.0).collect();

    let target_rate = 16000;
    let resampled_samples = if spec.sample_rate != target_rate {
        resample(&f32_samples, spec.sample_rate, target_rate)
    } else {
        f32_samples
    };

    let dc_offset = calculate_dc_offset(&resampled_samples);
    let clipping_ratio = calculate_clipping_ratio(&resampled_samples);
    let snr_db = estimate_snr(&resampled_samples, 160);

    let mut final_samples = resampled_samples;
    normalize_loudness(&mut final_samples);

    let quality = AudioQualitySummary {
        snr_db,
        clipping_ratio,
        dc_offset,
        sample_rate_hz: target_rate,
        channels: spec.channels,
    };

    Ok(NormalizedAudio {
        samples: final_samples,
        sample_rate_hz: target_rate,
        quality,
    })
}

fn samples_to_wav_bytes(samples: &[f32], sample_rate: u32) -> Result<Vec<u8>, hound::Error> {
    let mut cursor = std::io::Cursor::new(Vec::new());
    {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::new(&mut cursor, spec)?;
        for &s in samples {
            let sample_i16 = (s * 32767.0).clamp(-32768.0, 32767.0) as i16;
            writer.write_sample(sample_i16)?;
        }
        writer.finalize()?;
    }
    Ok(cursor.into_inner())
}

pub fn generate_reference_phone_timeline(
    sentence: &SubtitleSentence,
    word_timings: &[WordTiming],
) -> Vec<CanonicalPhoneWithTime> {
    let pronunciation = crate::analyze_sentence(sentence);
    let mut ref_phones = Vec::new();

    for word_pron in &pronunciation.words {
        let timing = word_timings
            .iter()
            .find(|t| t.token_index == word_pron.token_index);
        let (word_start, word_end) = match timing {
            Some(t) => (t.start_ms, t.end_ms),
            None => (0, 0),
        };

        let variant = match word_pron.variants.first() {
            Some(v) => v,
            None => continue,
        };

        let phone_count = variant.phonemes.len();
        if phone_count == 0 {
            continue;
        }

        let phone_duration = (word_end.saturating_sub(word_start)) / phone_count as u64;

        for (i, p) in variant.phonemes.iter().enumerate() {
            let start = word_start + i as u64 * phone_duration;
            let end = if i + 1 == phone_count {
                word_end
            } else {
                start + phone_duration
            };
            ref_phones.push(CanonicalPhoneWithTime {
                symbol: p.symbol.clone(),
                token_index: word_pron.token_index,
                stress: p.stress,
                start_ms: start,
                end_ms: end,
            });
        }
    }
    ref_phones
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StepV2 {
    Start,
    Match,
    Substitution,
    Insertion,
    Deletion,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PhoneAlignmentV2 {
    pub reference_phone: Option<CanonicalPhoneWithTime>,
    pub recording_phone: Option<DetectedPhone>,
    pub status: ShadowingPhoneAlignmentStatus,
}

pub fn align_phones_time_constrained(
    canonical: &[CanonicalPhoneWithTime],
    detected: &[DetectedPhone],
    ref_duration_ms: u64,
    rec_duration_ms: u64,
) -> Vec<PhoneAlignmentV2> {
    let rows = canonical.len() + 1;
    let columns = detected.len() + 1;

    let duration_ratio = if ref_duration_ms > 0 {
        rec_duration_ms as f64 / ref_duration_ms as f64
    } else {
        1.0
    };

    let mut dp = vec![vec![(f32::MAX, StepV2::Start); columns]; rows];
    dp[0][0] = (0.0, StepV2::Start);

    for (i, row) in dp.iter_mut().enumerate().skip(1) {
        row[0] = (i as f32, StepV2::Deletion);
    }
    for (j, cell) in dp[0].iter_mut().enumerate().skip(1) {
        *cell = (j as f32, StepV2::Insertion);
    }

    let max_time_skew_ms = 1500;

    for i in 1..rows {
        let ref_p = &canonical[i - 1];
        let expected_start_ms = (ref_p.start_ms as f64 * duration_ratio) as u64;

        for j in 1..columns {
            let det_p = &detected[j - 1];
            let skew_ms = expected_start_ms.abs_diff(det_p.start_ms);
            let time_penalty = if skew_ms > max_time_skew_ms { 5.0 } else { 0.0 };

            let same = ref_p.symbol == det_p.symbol;
            let sub_cost = if same { 0.0 } else { 1.5 } + time_penalty;
            let diag = dp[i - 1][j - 1].0 + sub_cost;
            let mut best_cost = diag;
            let mut best_step = if same {
                StepV2::Match
            } else {
                StepV2::Substitution
            };

            let del = dp[i - 1][j].0 + 1.0;
            if del < best_cost {
                best_cost = del;
                best_step = StepV2::Deletion;
            }

            let ins = dp[i][j - 1].0 + 1.0;
            if ins < best_cost {
                best_cost = ins;
                best_step = StepV2::Insertion;
            }

            dp[i][j] = (best_cost, best_step);
        }
    }

    let mut alignments = Vec::new();
    let mut i = canonical.len();
    let mut j = detected.len();

    while i > 0 || j > 0 {
        let (_, step) = dp[i][j];
        match step {
            StepV2::Match => {
                alignments.push(PhoneAlignmentV2 {
                    reference_phone: Some(canonical[i - 1].clone()),
                    recording_phone: Some(detected[j - 1].clone()),
                    status: ShadowingPhoneAlignmentStatus::Match,
                });
                i -= 1;
                j -= 1;
            }
            StepV2::Substitution => {
                alignments.push(PhoneAlignmentV2 {
                    reference_phone: Some(canonical[i - 1].clone()),
                    recording_phone: Some(detected[j - 1].clone()),
                    status: ShadowingPhoneAlignmentStatus::Substitution,
                });
                i -= 1;
                j -= 1;
            }
            StepV2::Insertion => {
                alignments.push(PhoneAlignmentV2 {
                    reference_phone: None,
                    recording_phone: Some(detected[j - 1].clone()),
                    status: ShadowingPhoneAlignmentStatus::Insertion,
                });
                j -= 1;
            }
            StepV2::Deletion => {
                alignments.push(PhoneAlignmentV2 {
                    reference_phone: Some(canonical[i - 1].clone()),
                    recording_phone: None,
                    status: ShadowingPhoneAlignmentStatus::Deletion,
                });
                i -= 1;
            }
            StepV2::Start => break,
        }
    }
    alignments.reverse();
    alignments
}

pub fn resolve_learner_word_timings(
    sentence: &SubtitleSentence,
    phone_alignments: &[PhoneAlignmentV2],
) -> Vec<WordTiming> {
    let mut learner_timings = Vec::new();

    let words = sentence
        .tokens
        .iter()
        .filter(|t| t.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();

    for word in words {
        let aligned_phones: Vec<&DetectedPhone> = phone_alignments
            .iter()
            .filter(|a| {
                a.reference_phone
                    .as_ref()
                    .is_some_and(|rp| rp.token_index == word.index)
            })
            .filter_map(|a| a.recording_phone.as_ref())
            .collect();

        if !aligned_phones.is_empty() {
            let start_ms = aligned_phones.iter().map(|p| p.start_ms).min().unwrap_or(0);
            let end_ms = aligned_phones.iter().map(|p| p.end_ms).max().unwrap_or(0);
            if end_ms > start_ms {
                learner_timings.push(WordTiming {
                    sentence_id: sentence.id.clone(),
                    token_index: word.index,
                    text: word.text.clone(),
                    start_ms,
                    end_ms,
                    confidence: Some(0.9),
                    timing_source: TimingSource::ForcedAligned,
                    provider_id: "shadowing-v2-alignment".into(),
                    provider_version: "v1".into(),
                });
            }
        }
    }
    learner_timings
}

pub fn compare_shadowing_v2(
    reference_wav_path: impl AsRef<Path>,
    recording_wav_path: impl AsRef<Path>,
    sentence: Option<&SubtitleSentence>,
    reference_word_timings: &[WordTiming],
    reference_start_ms: u64,
    model_dir: Option<&str>,
    model_revision: Option<&str>,
) -> Result<ShadowingAnalysis, ShadowingComparisonError> {
    let ref_audio = load_and_normalize_audio(&reference_wav_path)?;
    let rec_audio = load_and_normalize_audio(&recording_wav_path)?;

    let rec_duration_ms = rec_audio.samples.len() as u64 * 1000 / rec_audio.sample_rate_hz as u64;
    let ref_duration_ms = ref_audio.samples.len() as u64 * 1000 / ref_audio.sample_rate_hz as u64;

    if rec_duration_ms < 100 {
        return Ok(abstained_analysis(
            ShadowingAbstainReason::AudioTooShort,
            rec_audio.quality,
            Vec::new(),
        ));
    }

    if rec_audio.quality.snr_db < 5.0 {
        return Ok(abstained_analysis(
            ShadowingAbstainReason::LowAudioQuality,
            rec_audio.quality,
            Vec::new(),
        ));
    }

    let sentence = match sentence {
        Some(s) => s,
        None => {
            return Ok(abstained_analysis(
                ShadowingAbstainReason::MissingReferenceTimeline,
                rec_audio.quality,
                vec![missing_evidence(
                    ShadowingEvidenceComponent::ReferenceTimeline,
                    ShadowingMissingEvidenceReason::ReferenceTimelineUnavailable,
                )],
            ));
        }
    };

    let reference_word_timings =
        segment_relative_word_timings(reference_word_timings, reference_start_ms, ref_duration_ms);
    if reference_word_timings.is_empty() {
        return Ok(abstained_analysis(
            ShadowingAbstainReason::MissingReferenceTimeline,
            rec_audio.quality,
            vec![missing_evidence(
                ShadowingEvidenceComponent::ReferenceTimeline,
                ShadowingMissingEvidenceReason::ReferenceTimelineUnavailable,
            )],
        ));
    }

    let ref_phones = generate_reference_phone_timeline(sentence, &reference_word_timings);
    if ref_phones.is_empty() {
        return Ok(abstained_analysis(
            ShadowingAbstainReason::MissingReferenceTimeline,
            rec_audio.quality,
            vec![missing_evidence(
                ShadowingEvidenceComponent::ReferenceTimeline,
                ShadowingMissingEvidenceReason::InsufficientCoverage,
            )],
        ));
    }

    let Some(model_path) = model_dir else {
        return Ok(abstained_analysis(
            ShadowingAbstainReason::ProviderUnavailable,
            rec_audio.quality,
            vec![missing_evidence(
                ShadowingEvidenceComponent::PhoneRecognition,
                ShadowingMissingEvidenceReason::ProviderUnavailable,
            )],
        ));
    };

    let revision = model_revision.unwrap_or("unknown");
    let detected_phones = match crate::phone_recognition::recognize_phones(
        recording_wav_path.as_ref().to_str().unwrap_or(""),
        model_path,
        0,
        rec_duration_ms,
        revision,
    ) {
        Ok(result) => result.phones,
        Err(_) => {
            return Ok(abstained_analysis(
                ShadowingAbstainReason::ProviderFailure,
                rec_audio.quality,
                vec![missing_evidence(
                    ShadowingEvidenceComponent::PhoneRecognition,
                    ShadowingMissingEvidenceReason::ProviderFailed,
                )],
            ));
        }
    };

    if detected_phones.is_empty() {
        return Ok(abstained_analysis(
            ShadowingAbstainReason::LowConfidence,
            rec_audio.quality,
            vec![missing_evidence(
                ShadowingEvidenceComponent::PhoneRecognition,
                ShadowingMissingEvidenceReason::InsufficientCoverage,
            )],
        ));
    }

    analyze_shadowing_v2_with_phones(
        ref_audio,
        rec_audio,
        sentence,
        &reference_word_timings,
        &ref_phones,
        &detected_phones,
        ref_duration_ms,
        rec_duration_ms,
        revision,
    )
}

#[allow(clippy::too_many_arguments)]
fn analyze_shadowing_v2_with_phones(
    ref_audio: NormalizedAudio,
    rec_audio: NormalizedAudio,
    sentence: &SubtitleSentence,
    reference_word_timings: &[WordTiming],
    ref_phones: &[CanonicalPhoneWithTime],
    detected_phones: &[DetectedPhone],
    ref_duration_ms: u64,
    rec_duration_ms: u64,
    model_revision: &str,
) -> Result<ShadowingAnalysis, ShadowingComparisonError> {
    let phone_alignments = align_phones_time_constrained(
        ref_phones,
        detected_phones,
        ref_duration_ms,
        rec_duration_ms,
    );
    let learner_word_timings = resolve_learner_word_timings(sentence, &phone_alignments);

    let ref_norm_wav = samples_to_wav_bytes(&ref_audio.samples, ref_audio.sample_rate_hz)?;
    let rec_norm_wav = samples_to_wav_bytes(&rec_audio.samples, rec_audio.sample_rate_hz)?;

    let ref_acoustics = crate::word_acoustics::analyze_word_acoustics_from_pcm_wav(
        &ref_norm_wav,
        reference_word_timings,
    );
    let rec_acoustics = crate::word_acoustics::analyze_word_acoustics_from_pcm_wav(
        &rec_norm_wav,
        &learner_word_timings,
    );
    let mut missing = Vec::new();
    if ref_acoustics.is_err() || rec_acoustics.is_err() {
        for component in [
            ShadowingEvidenceComponent::Stress,
            ShadowingEvidenceComponent::F0,
            ShadowingEvidenceComponent::Energy,
        ] {
            missing.push(missing_evidence(
                component,
                ShadowingMissingEvidenceReason::AcousticExtractionFailed,
            ));
        }
    }
    let ref_acoustics = ref_acoustics.ok();
    let rec_acoustics = rec_acoustics.ok();

    let mut word_details = Vec::new();
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();

    for word in &words {
        let ref_timing = reference_word_timings
            .iter()
            .find(|timing| timing.token_index == word.index);
        let rec_timing = learner_word_timings
            .iter()
            .find(|timing| timing.token_index == word.index);

        let ref_duration = ref_timing
            .map(|timing| timing.end_ms.saturating_sub(timing.start_ms))
            .unwrap_or(0);
        let rec_duration = rec_timing.map(|t| t.end_ms.saturating_sub(t.start_ms));

        let ref_cue = ref_acoustics.as_ref().and_then(|analysis| {
            analysis
                .cues
                .iter()
                .find(|cue| cue.token_index == word.index)
        });
        let rec_cue = rec_acoustics.as_ref().and_then(|analysis| {
            analysis
                .cues
                .iter()
                .find(|cue| cue.token_index == word.index)
        });

        let reference_stress = ref_phones
            .iter()
            .filter(|phone| phone.token_index == word.index)
            .filter_map(|phone| phone.stress)
            .max();
        let recording_stress = rec_cue.and_then(acoustic_stress);

        let mut word_phone_details = Vec::new();
        let word_aligns = phone_alignments
            .iter()
            .filter(|alignment| {
                alignment
                    .reference_phone
                    .as_ref()
                    .is_some_and(|phone| phone.token_index == word.index)
                    || alignment
                        .recording_phone
                        .as_ref()
                        .is_some_and(|phone| phone.token_index == Some(word.index))
            })
            .collect::<Vec<_>>();

        let mut match_count = 0;
        let mut total_phones = 0;
        for wa in &word_aligns {
            if wa.status == ShadowingPhoneAlignmentStatus::Match {
                match_count += 1;
            }
            total_phones += 1;
            word_phone_details.push(ShadowingPhoneAlignmentDetail {
                reference_phone: wa.reference_phone.as_ref().map(|p| p.symbol.clone()),
                recording_phone: wa.recording_phone.as_ref().map(|p| p.symbol.clone()),
                status: wa.status,
            });
        }

        let status = if rec_timing.is_none() {
            ShadowingWordStatus::Deleted
        } else if match_count as f32 / total_phones.max(1) as f32 >= 0.6 {
            ShadowingWordStatus::Match
        } else {
            ShadowingWordStatus::Substituted
        };

        word_details.push(ShadowingWordDetail {
            token_index: word.index,
            text: word.text.clone(),
            status,
            reference_duration_ms: ref_duration,
            recording_duration_ms: rec_duration,
            reference_stress,
            recording_stress,
            reference_f0_hz: ref_cue.and_then(|c| c.f0_median_hz),
            recording_f0_hz: rec_cue.and_then(|c| c.f0_median_hz),
            reference_f0_range_semitones: ref_cue.and_then(|c| c.f0_range_semitones),
            recording_f0_range_semitones: rec_cue.and_then(|c| c.f0_range_semitones),
            reference_pitch_reset_after: ref_cue.and_then(|c| c.pitch_reset_after),
            recording_pitch_reset_after: rec_cue.and_then(|c| c.pitch_reset_after),
            reference_energy_prominence: ref_cue.and_then(|c| c.energy_prominence),
            recording_energy_prominence: rec_cue.and_then(|c| c.energy_prominence),
            phone_alignments: word_phone_details,
        });
    }

    let aligned_words = word_details
        .iter()
        .filter(|word| word.status != ShadowingWordStatus::Deleted)
        .count();
    let coverage = aligned_words as f32 / words.len().max(1) as f32;

    let confidences = detected_phones
        .iter()
        .filter_map(|phone| phone.confidence)
        .collect::<Vec<_>>();
    let confidence = if confidences.is_empty() {
        0.0
    } else {
        confidences.iter().sum::<f32>() / confidences.len() as f32
    };

    let aligned_reference_phones = phone_alignments
        .iter()
        .filter(|alignment| {
            alignment.reference_phone.is_some() && alignment.recording_phone.is_some()
        })
        .count();
    let phone_coverage = aligned_reference_phones as f32 / ref_phones.len().max(1) as f32;
    let stress_coverage = paired_word_coverage(&word_details, |word| {
        word.reference_stress.is_some() && word.recording_stress.is_some()
    });
    let f0_coverage = paired_word_coverage(&word_details, |word| {
        word.reference_f0_hz.is_some() && word.recording_f0_hz.is_some()
    });
    let energy_coverage = paired_word_coverage(&word_details, |word| {
        word.reference_energy_prominence.is_some() && word.recording_energy_prominence.is_some()
    });
    let rhythm_coverage = if paired_durations(&word_details).len() >= 2 {
        coverage
    } else {
        0.0
    };
    add_coverage_missing(
        &mut missing,
        ShadowingEvidenceComponent::WordAlignment,
        coverage,
    );
    add_coverage_missing(
        &mut missing,
        ShadowingEvidenceComponent::PhoneRecognition,
        phone_coverage,
    );
    add_coverage_missing(
        &mut missing,
        ShadowingEvidenceComponent::Stress,
        stress_coverage,
    );
    add_coverage_missing(
        &mut missing,
        ShadowingEvidenceComponent::Rhythm,
        rhythm_coverage,
    );
    add_coverage_missing(&mut missing, ShadowingEvidenceComponent::F0, f0_coverage);
    add_coverage_missing(
        &mut missing,
        ShadowingEvidenceComponent::Energy,
        energy_coverage,
    );

    let reference_pcm = pcm_audio_from_normalized(&ref_audio);
    let recording_pcm = pcm_audio_from_normalized(&rec_audio);
    let reference_pauses = detect_pauses(&reference_pcm);
    let recording_pauses = detect_pauses(&recording_pcm);
    let prosody = ShadowingProsodyComparison {
        reference_pause_count: reference_pauses.len() as u32,
        recording_pause_count: recording_pauses.len() as u32,
        pause_alignment_offset_ms: mean_nearest_pause_offset(&reference_pauses, &recording_pauses),
        mean_word_duration_ratio: mean_duration_ratio(&word_details),
        rhythm_similarity: paired_similarity(paired_durations(&word_details)),
        f0_contour_similarity: paired_similarity(
            word_details
                .iter()
                .filter_map(|word| Some((word.reference_f0_hz?, word.recording_f0_hz?)))
                .collect(),
        ),
        energy_prominence_similarity: paired_similarity(
            word_details
                .iter()
                .filter_map(|word| {
                    Some((
                        word.reference_energy_prominence?,
                        word.recording_energy_prominence?,
                    ))
                })
                .collect(),
        ),
    };

    let abstain_reason = if coverage < 0.25 {
        Some(ShadowingAbstainReason::MismatchedSpeech)
    } else if confidence < 0.35 {
        Some(ShadowingAbstainReason::LowConfidence)
    } else {
        None
    };

    if abstain_reason.is_some() {
        for word in &mut word_details {
            word.status = ShadowingWordStatus::Unassessed;
        }
    }

    let unassigned_phone_alignments = phone_alignments
        .iter()
        .filter(|alignment| alignment.reference_phone.is_none())
        .map(|alignment| ShadowingPhoneAlignmentDetail {
            reference_phone: None,
            recording_phone: alignment
                .recording_phone
                .as_ref()
                .map(|phone| phone.symbol.clone()),
            status: alignment.status,
        })
        .collect();

    Ok(ShadowingAnalysis {
        provider_id: "shadowing-v2".into(),
        provider_version: "v2".into(),
        phone_provider: Some(ShadowingProviderInfo {
            provider_id: crate::phone_recognition::PROVIDER_ID.into(),
            provider_version: crate::phone_recognition::PROVIDER_VERSION.into(),
            model_revision: model_revision.into(),
        }),
        coverage,
        confidence,
        evidence_coverage: ShadowingEvidenceCoverage {
            word_alignment: coverage,
            phone_alignment: phone_coverage,
            stress: stress_coverage,
            rhythm: rhythm_coverage,
            f0: f0_coverage,
            energy: energy_coverage,
            missing,
        },
        prosody: Some(prosody),
        audio_quality: Some(rec_audio.quality),
        abstain_reason,
        word_details,
        unassigned_phone_alignments,
    })
}

fn abstained_analysis(
    reason: ShadowingAbstainReason,
    quality: AudioQualitySummary,
    missing: Vec<ShadowingMissingEvidence>,
) -> ShadowingAnalysis {
    ShadowingAnalysis {
        provider_id: "shadowing-v2".into(),
        provider_version: "v2".into(),
        phone_provider: None,
        coverage: 0.0,
        confidence: 0.0,
        evidence_coverage: ShadowingEvidenceCoverage {
            missing,
            ..ShadowingEvidenceCoverage::default()
        },
        prosody: None,
        audio_quality: Some(quality),
        abstain_reason: Some(reason),
        word_details: Vec::new(),
        unassigned_phone_alignments: Vec::new(),
    }
}

fn missing_evidence(
    component: ShadowingEvidenceComponent,
    reason: ShadowingMissingEvidenceReason,
) -> ShadowingMissingEvidence {
    ShadowingMissingEvidence { component, reason }
}

fn segment_relative_word_timings(
    timings: &[WordTiming],
    segment_start_ms: u64,
    segment_duration_ms: u64,
) -> Vec<WordTiming> {
    let segment_end_ms = segment_start_ms.saturating_add(segment_duration_ms);
    timings
        .iter()
        .filter(|timing| timing.end_ms > segment_start_ms && timing.start_ms < segment_end_ms)
        .filter_map(|timing| {
            let start_ms = timing.start_ms.max(segment_start_ms) - segment_start_ms;
            let end_ms = timing.end_ms.min(segment_end_ms) - segment_start_ms;
            (end_ms > start_ms).then(|| WordTiming {
                start_ms,
                end_ms,
                ..timing.clone()
            })
        })
        .collect()
}

fn acoustic_stress(cue: &crate::word_acoustics::WordAcousticMeasurement) -> Option<u8> {
    let prominence = cue
        .energy_prominence
        .into_iter()
        .chain(cue.pitch_prominence)
        .reduce(f32::max)?;
    Some(u8::from(prominence >= 0.5))
}

fn paired_word_coverage(
    words: &[ShadowingWordDetail],
    predicate: impl Fn(&ShadowingWordDetail) -> bool,
) -> f32 {
    words.iter().filter(|word| predicate(word)).count() as f32 / words.len().max(1) as f32
}

fn paired_durations(words: &[ShadowingWordDetail]) -> Vec<(f32, f32)> {
    words
        .iter()
        .filter_map(|word| {
            Some((
                word.reference_duration_ms as f32,
                word.recording_duration_ms? as f32,
            ))
        })
        .filter(|(reference, recording)| *reference > 0.0 && *recording > 0.0)
        .collect()
}

fn mean_duration_ratio(words: &[ShadowingWordDetail]) -> Option<f32> {
    let pairs = paired_durations(words);
    (!pairs.is_empty()).then(|| {
        pairs
            .iter()
            .map(|(reference, recording)| recording / reference)
            .sum::<f32>()
            / pairs.len() as f32
    })
}

fn paired_similarity(pairs: Vec<(f32, f32)>) -> Option<f32> {
    (!pairs.is_empty()).then(|| {
        pairs
            .iter()
            .map(|(reference, recording)| {
                let largest = reference.abs().max(recording.abs());
                if largest <= f32::EPSILON {
                    1.0
                } else {
                    (1.0 - (reference - recording).abs() / largest).clamp(0.0, 1.0)
                }
            })
            .sum::<f32>()
            / pairs.len() as f32
    })
}

fn add_coverage_missing(
    missing: &mut Vec<ShadowingMissingEvidence>,
    component: ShadowingEvidenceComponent,
    coverage: f32,
) {
    if coverage < 0.25 && !missing.iter().any(|entry| entry.component == component) {
        missing.push(missing_evidence(
            component,
            ShadowingMissingEvidenceReason::InsufficientCoverage,
        ));
    }
}

fn pcm_audio_from_normalized(audio: &NormalizedAudio) -> PcmAudio {
    PcmAudio {
        sample_rate_hz: audio.sample_rate_hz,
        samples: audio
            .samples
            .iter()
            .map(|sample| (sample * i16::MAX as f32) as i16)
            .collect(),
    }
}

#[derive(Debug, Error)]
pub enum ShadowingComparisonError {
    #[error("shadowing comparison requires non-empty mono PCM16 WAV audio")]
    UnsupportedFormat,
    #[error("shadowing comparison audio is empty")]
    EmptyAudio,
    #[error(transparent)]
    Wav(#[from] hound::Error),
    #[error("word acoustics error: {0}")]
    WordAcoustics(#[from] crate::word_acoustics::WordAcousticError),
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

    #[test]
    fn summarizes_one_recording_without_turning_it_into_a_score() {
        let path = tempfile_path("facts", &wav(900, &[(300, 500)]));
        let result = analyze_pcm16_wav_path(&path).unwrap();
        assert_eq!(result.duration_ms, 900);
        assert_eq!(
            result.pauses,
            vec![AudioPauseInterval {
                start_ms: 300,
                end_ms: 500
            }]
        );
        assert_eq!(result.waveform.duration_ms, 900);
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn v2_abstains_when_phone_provider_is_unavailable() {
        use domain::{SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs};

        let sentence_id = SubtitleSentenceId::parse("s1").unwrap();
        let sentence = SubtitleSentence {
            id: sentence_id.clone(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1000),
            original_text: "hello world".into(),
            display_text: "hello world".into(),
            tokens: vec![
                SubtitleToken {
                    index: 0,
                    kind: SubtitleTokenKind::Word,
                    text: "hello".into(),
                    normalized: Some("hello".into()),
                    start_char: 0,
                    end_char: 5,
                },
                SubtitleToken {
                    index: 1,
                    kind: SubtitleTokenKind::Word,
                    text: "world".into(),
                    normalized: Some("world".into()),
                    start_char: 6,
                    end_char: 11,
                },
            ],
        };

        let reference_word_timings = vec![
            WordTiming {
                sentence_id: sentence_id.clone(),
                token_index: 0,
                text: "hello".into(),
                start_ms: 0,
                end_ms: 400,
                confidence: Some(1.0),
                timing_source: TimingSource::ForcedAligned,
                provider_id: "test".into(),
                provider_version: "v1".into(),
            },
            WordTiming {
                sentence_id: sentence_id.clone(),
                token_index: 1,
                text: "world".into(),
                start_ms: 400,
                end_ms: 1000,
                confidence: Some(1.0),
                timing_source: TimingSource::ForcedAligned,
                provider_id: "test".into(),
                provider_version: "v1".into(),
            },
        ];

        let reference = tempfile_path("v2ref", &speech_wav(1_000));
        let recording = tempfile_path("v2rec", &speech_wav(1_100));

        let analysis = compare_shadowing_v2(
            &reference,
            &recording,
            Some(&sentence),
            &reference_word_timings,
            0,
            None,
            None,
        )
        .unwrap();

        assert_eq!(analysis.provider_id, "shadowing-v2");
        assert_eq!(analysis.provider_version, "v2");
        assert!(analysis.audio_quality.is_some());
        assert_eq!(
            analysis.abstain_reason,
            Some(ShadowingAbstainReason::ProviderUnavailable)
        );
        assert_eq!(analysis.coverage, 0.0);
        assert!(analysis.word_details.is_empty());
        assert!(analysis.evidence_coverage.missing.iter().any(|missing| {
            missing.component == ShadowingEvidenceComponent::PhoneRecognition
                && missing.reason == ShadowingMissingEvidenceReason::ProviderUnavailable
        }));

        let _ = std::fs::remove_file(reference);
        let _ = std::fs::remove_file(recording);
    }

    #[test]
    fn v2_abstains_on_too_short_audio() {
        let reference = tempfile_path("v2short-ref", &speech_wav(1_000));
        let recording = tempfile_path("v2short-rec", &speech_wav(50));

        let analysis =
            compare_shadowing_v2(&reference, &recording, None, &[], 0, None, None).unwrap();

        assert_eq!(
            analysis.abstain_reason,
            Some(ShadowingAbstainReason::AudioTooShort)
        );
        assert_eq!(analysis.coverage, 0.0);

        let _ = std::fs::remove_file(reference);
        let _ = std::fs::remove_file(recording);
    }

    #[test]
    fn converts_absolute_word_timings_to_segment_relative_time() {
        use domain::SubtitleSentenceId;

        let timing = WordTiming {
            sentence_id: SubtitleSentenceId::parse("sentence").unwrap(),
            token_index: 0,
            text: "hello".into(),
            start_ms: 5_100,
            end_ms: 5_450,
            confidence: Some(1.0),
            timing_source: TimingSource::ForcedAligned,
            provider_id: "fixture".into(),
            provider_version: "v1".into(),
        };
        let relative = segment_relative_word_timings(&[timing], 5_000, 1_000);
        assert_eq!(relative.len(), 1);
        assert_eq!(relative[0].start_ms, 100);
        assert_eq!(relative[0].end_ms, 450);
    }

    #[test]
    fn v2_analysis_with_detected_phones_reports_real_alignment_and_insertions() {
        use domain::{SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs};

        let sentence_id = SubtitleSentenceId::parse("detected-sentence").unwrap();
        let sentence = SubtitleSentence {
            id: sentence_id.clone(),
            index: 0,
            start: TimeMs::ZERO,
            end: TimeMs::new(1_000),
            original_text: "hello".into(),
            display_text: "hello".into(),
            tokens: vec![SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "hello".into(),
                normalized: Some("hello".into()),
                start_char: 0,
                end_char: 5,
            }],
        };
        let timings = vec![WordTiming {
            sentence_id,
            token_index: 0,
            text: "hello".into(),
            start_ms: 0,
            end_ms: 1_000,
            confidence: Some(1.0),
            timing_source: TimingSource::ForcedAligned,
            provider_id: "fixture".into(),
            provider_version: "v1".into(),
        }];
        let canonical = generate_reference_phone_timeline(&sentence, &timings);
        let mut detected = canonical
            .iter()
            .map(|phone| DetectedPhone {
                symbol: phone.symbol.clone(),
                display_ipa: phone.symbol.clone(),
                phone_set: "arpabet".into(),
                start_ms: phone.start_ms,
                end_ms: phone.end_ms,
                confidence: Some(0.9),
                token_index: Some(phone.token_index),
                provider_id: crate::phone_recognition::PROVIDER_ID.into(),
                provider_version: crate::phone_recognition::PROVIDER_VERSION.into(),
                model_revision: "fixture-model".into(),
            })
            .collect::<Vec<_>>();
        detected.push(DetectedPhone {
            symbol: "AH".into(),
            display_ipa: "ə".into(),
            phone_set: "arpabet".into(),
            start_ms: 1_000,
            end_ms: 1_080,
            confidence: Some(0.8),
            token_index: None,
            provider_id: crate::phone_recognition::PROVIDER_ID.into(),
            provider_version: crate::phone_recognition::PROVIDER_VERSION.into(),
            model_revision: "fixture-model".into(),
        });
        let reference = tempfile_path("v2-detected-ref", &speech_wav(1_000));
        let recording = tempfile_path("v2-detected-rec", &speech_wav(1_100));
        let reference_audio = load_and_normalize_audio(&reference).unwrap();
        let recording_audio = load_and_normalize_audio(&recording).unwrap();

        let analysis = analyze_shadowing_v2_with_phones(
            reference_audio,
            recording_audio,
            &sentence,
            &timings,
            &canonical,
            &detected,
            1_000,
            1_100,
            "fixture-model",
        )
        .unwrap();

        assert_eq!(analysis.abstain_reason, None);
        assert_eq!(analysis.word_details.len(), 1);
        assert_eq!(analysis.word_details[0].status, ShadowingWordStatus::Match);
        assert_eq!(analysis.unassigned_phone_alignments.len(), 1);
        assert_eq!(
            analysis.unassigned_phone_alignments[0].status,
            ShadowingPhoneAlignmentStatus::Insertion
        );
        assert_eq!(
            analysis.phone_provider.unwrap().model_revision,
            "fixture-model"
        );

        let _ = std::fs::remove_file(reference);
        let _ = std::fs::remove_file(recording);
    }

    #[test]
    fn abstain_contract_matches_golden_fixture() {
        let analysis = abstained_analysis(
            ShadowingAbstainReason::ProviderUnavailable,
            AudioQualitySummary {
                snr_db: 12.5,
                clipping_ratio: 0.0,
                dc_offset: 0.0,
                sample_rate_hz: 16_000,
                channels: 1,
            },
            vec![missing_evidence(
                ShadowingEvidenceComponent::PhoneRecognition,
                ShadowingMissingEvidenceReason::ProviderUnavailable,
            )],
        );
        let actual = serde_json::to_value(analysis).unwrap();
        let expected: serde_json::Value = serde_json::from_str(include_str!(
            "../../../testdata/shadowing-v2/provider-unavailable.json"
        ))
        .unwrap();
        assert_eq!(actual, expected);
    }

    /// Generate a WAV with speech-like characteristics: a 300 Hz sine wave
    /// with amplitude modulation (envelope) that creates natural energy
    /// variation across frames, ensuring a realistic SNR estimate.
    fn speech_wav(duration_ms: u64) -> Vec<u8> {
        let sample_rate = 16_000u32;
        let total_samples = (sample_rate as u64 * duration_ms / 1000) as usize;
        let mut cursor = Cursor::new(Vec::new());
        let mut writer = hound::WavWriter::new(
            &mut cursor,
            hound::WavSpec {
                channels: 1,
                sample_rate,
                bits_per_sample: 16,
                sample_format: hound::SampleFormat::Int,
            },
        )
        .unwrap();
        for i in 0..total_samples {
            let t = i as f32 / sample_rate as f32;
            // 300 Hz carrier with 3 Hz amplitude modulation for energy variation
            let carrier = (2.0 * std::f32::consts::PI * 300.0 * t).sin();
            let envelope = 0.5 + 0.5 * (2.0 * std::f32::consts::PI * 3.0 * t).sin();
            let sample = (carrier * envelope * 16_000.0) as i16;
            writer.write_sample(sample).unwrap();
        }
        writer.finalize().unwrap();
        cursor.into_inner()
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
