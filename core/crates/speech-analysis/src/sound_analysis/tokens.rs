use domain::{
    SoundLearningPhone, SoundSyllable, SubtitleSentence, SubtitleTokenKind, SyllableStress,
    TimingSource, WordTiming,
};

use crate::phonetic_alignment::CanonicalPhone;

use super::config::RhythmWordAcousticCue;
use super::helpers::{clamp01, is_function_word, normalize_rhythm_word};

pub(super) struct RhythmToken {
    pub(super) index: u32,
    pub(super) text: String,
    pub(super) normalized: String,
    pub(super) start_ms: u64,
    pub(super) end_ms: u64,
    pub(super) phone_start: Option<u32>,
    pub(super) phone_end: Option<u32>,
    pub(super) phone_count: u32,
    pub(super) syllable_index: Option<u32>,
    pub(super) syllable_count: u32,
    pub(super) has_primary_stress: bool,
    pub(super) has_secondary_stress: bool,
    pub(super) average_confidence: Option<f32>,
    pub(super) energy_prominence: Option<f32>,
    pub(super) pitch_prominence: Option<f32>,
    pub(super) pitch_reset_after: Option<f32>,
    pub(super) timing_audio_supported: bool,
    pub(super) from_word_timeline: bool,
}

impl RhythmToken {
    pub(super) fn duration_ms(&self) -> u64 {
        self.end_ms.saturating_sub(self.start_ms).max(1)
    }

    pub(super) fn expected_units(&self) -> u32 {
        self.phone_count.max(self.syllable_count).max(1)
    }

    pub(super) fn is_function_word(&self) -> bool {
        is_function_word(&self.normalized)
    }

    pub(super) fn energy_prominence_score(&self) -> Option<f32> {
        self.energy_prominence
            .filter(|value| value.is_finite() && *value > 0.0)
            .map(clamp01)
    }

    pub(super) fn pitch_prominence_score(&self) -> Option<f32> {
        self.pitch_prominence
            .filter(|value| value.is_finite() && *value > 0.0)
            .map(clamp01)
    }

    pub(super) fn pitch_reset_after_score(&self) -> Option<f32> {
        self.pitch_reset_after
            .filter(|value| value.is_finite() && *value > 0.0)
            .map(clamp01)
    }
}

pub(super) fn rhythm_tokens(
    sentence: Option<&SubtitleSentence>,
    canonical: &[CanonicalPhone],
    word_timings: Option<&[WordTiming]>,
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    learning_phones: &[SoundLearningPhone],
    syllables: &[SoundSyllable],
) -> Vec<RhythmToken> {
    let word_timeline_tokens =
        rhythm_tokens_from_word_timings(sentence, canonical, word_timings, word_acoustic_cues);
    if !word_timeline_tokens.is_empty() {
        return word_timeline_tokens;
    }

    if let Some(sentence) = sentence {
        let mut values = Vec::new();
        for token in sentence
            .tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
        {
            if let Some(value) = rhythm_token(
                token.index,
                &token.text,
                token.normalized.as_deref().unwrap_or(&token.text),
                learning_phones,
                syllables,
                word_acoustic_cues,
            ) {
                values.push(value);
            }
        }
        if !values.is_empty() {
            return values;
        }
    }

    let mut token_indexes = learning_phones
        .iter()
        .filter_map(|phone| phone.token_index)
        .collect::<Vec<_>>();
    token_indexes.sort_unstable();
    token_indexes.dedup();
    token_indexes
        .into_iter()
        .filter_map(|index| {
            rhythm_token(
                index,
                &format!("token-{index}"),
                &format!("token-{index}"),
                learning_phones,
                syllables,
                word_acoustic_cues,
            )
        })
        .collect()
}

fn rhythm_token(
    token_index: u32,
    text: &str,
    normalized: &str,
    learning_phones: &[SoundLearningPhone],
    syllables: &[SoundSyllable],
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
) -> Option<RhythmToken> {
    let phone_indexes = learning_phones
        .iter()
        .enumerate()
        .filter_map(|(index, phone)| (phone.token_index == Some(token_index)).then_some(index))
        .collect::<Vec<_>>();
    let first_phone = *phone_indexes.first()?;
    let last_phone = *phone_indexes.last()?;
    let start_ms = phone_indexes
        .iter()
        .filter_map(|index| learning_phones.get(*index))
        .map(|phone| phone.start_ms)
        .min()
        .unwrap_or(0);
    let end_ms = phone_indexes
        .iter()
        .filter_map(|index| learning_phones.get(*index))
        .map(|phone| phone.end_ms)
        .max()
        .unwrap_or(start_ms + 1);
    let confidences = phone_indexes
        .iter()
        .filter_map(|index| {
            learning_phones
                .get(*index)
                .and_then(|phone| phone.confidence)
        })
        .collect::<Vec<_>>();
    let average_confidence = (!confidences.is_empty())
        .then(|| confidences.iter().sum::<f32>() / confidences.len() as f32);
    let syllable_indexes = syllables
        .iter()
        .enumerate()
        .filter_map(|(index, syllable)| {
            syllable
                .phones
                .iter()
                .any(|phone| (*phone as usize) >= first_phone && (*phone as usize) <= last_phone)
                .then_some(index as u32)
        })
        .collect::<Vec<_>>();
    let has_primary_stress = syllable_indexes.iter().any(|index| {
        syllables
            .get(*index as usize)
            .is_some_and(|syllable| syllable.stress == SyllableStress::Primary)
    });
    let has_secondary_stress = syllable_indexes.iter().any(|index| {
        syllables
            .get(*index as usize)
            .is_some_and(|syllable| syllable.stress == SyllableStress::Secondary)
    });

    Some(RhythmToken {
        index: token_index,
        text: text.into(),
        normalized: normalize_rhythm_word(normalized),
        start_ms,
        end_ms: end_ms.max(start_ms + 1),
        phone_start: Some(first_phone as u32),
        phone_end: Some(last_phone as u32),
        phone_count: phone_indexes.len() as u32,
        syllable_index: syllable_indexes.first().copied(),
        syllable_count: syllable_indexes.len().max(1) as u32,
        has_primary_stress,
        has_secondary_stress,
        average_confidence,
        energy_prominence: acoustic_energy_prominence(word_acoustic_cues, token_index),
        pitch_prominence: acoustic_pitch_prominence(word_acoustic_cues, token_index),
        pitch_reset_after: acoustic_pitch_reset_after(word_acoustic_cues, token_index),
        timing_audio_supported: true,
        from_word_timeline: false,
    })
}

fn rhythm_tokens_from_word_timings(
    sentence: Option<&SubtitleSentence>,
    canonical: &[CanonicalPhone],
    word_timings: Option<&[WordTiming]>,
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
) -> Vec<RhythmToken> {
    let (Some(sentence), Some(word_timings)) = (sentence, word_timings) else {
        return Vec::new();
    };
    let mut timings = word_timings
        .iter()
        .filter(|timing| timing.sentence_id == sentence.id)
        .filter(|timing| timing.end_ms > timing.start_ms)
        .collect::<Vec<_>>();
    if timings.is_empty() {
        timings = word_timings
            .iter()
            .filter(|timing| timing.end_ms > timing.start_ms)
            .collect::<Vec<_>>();
    }
    if timings.is_empty() {
        return Vec::new();
    }
    timings.sort_by_key(|timing| (timing.start_ms, timing.end_ms, timing.token_index));
    let mut values = Vec::new();
    for timing in timings {
        let token = sentence.tokens.iter().find(|token| {
            token.index == timing.token_index && token.kind == SubtitleTokenKind::Word
        });
        let text = token
            .map(|token| token.text.as_str())
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(timing.text.as_str());
        let normalized = token
            .and_then(|token| token.normalized.as_deref())
            .unwrap_or(text);
        let token_phones = canonical
            .iter()
            .filter(|phone| phone.token_index == timing.token_index)
            .collect::<Vec<_>>();
        let syllable_count = token_phones
            .iter()
            .filter(|phone| phone.stress.is_some())
            .count()
            .max(1) as u32;
        let has_primary_stress = token_phones
            .iter()
            .any(|phone| phone.stress == Some(1) || phone.stress == Some(2));
        let has_secondary_stress = token_phones.iter().any(|phone| phone.stress == Some(2));
        values.push(RhythmToken {
            index: timing.token_index,
            text: text.into(),
            normalized: normalize_rhythm_word(normalized),
            start_ms: timing.start_ms,
            end_ms: timing.end_ms.max(timing.start_ms + 1),
            phone_start: None,
            phone_end: None,
            phone_count: token_phones.len() as u32,
            syllable_index: None,
            syllable_count,
            has_primary_stress,
            has_secondary_stress,
            average_confidence: timing.confidence,
            energy_prominence: acoustic_energy_prominence(word_acoustic_cues, timing.token_index),
            pitch_prominence: acoustic_pitch_prominence(word_acoustic_cues, timing.token_index),
            pitch_reset_after: acoustic_pitch_reset_after(word_acoustic_cues, timing.token_index),
            timing_audio_supported: is_audio_backed_word_timing(timing.timing_source),
            from_word_timeline: true,
        });
    }
    values
}

pub(super) fn is_audio_backed_word_timing(source: TimingSource) -> bool {
    matches!(
        source,
        TimingSource::AsrReported
            | TimingSource::AsrAligned
            | TimingSource::ForcedAligned
            | TimingSource::UserAdjusted
    )
}

fn acoustic_energy_prominence(
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    token_index: u32,
) -> Option<f32> {
    word_acoustic_cues?
        .iter()
        .find(|cue| cue.token_index == token_index)
        .and_then(|cue| cue.energy_prominence)
        .filter(|value| value.is_finite() && *value > 0.0)
        .map(clamp01)
}

fn acoustic_pitch_prominence(
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    token_index: u32,
) -> Option<f32> {
    word_acoustic_cues?
        .iter()
        .find(|cue| cue.token_index == token_index)
        .and_then(|cue| cue.pitch_prominence)
        .filter(|value| value.is_finite() && *value > 0.0)
        .map(clamp01)
}

fn acoustic_pitch_reset_after(
    word_acoustic_cues: Option<&[RhythmWordAcousticCue]>,
    token_index: u32,
) -> Option<f32> {
    word_acoustic_cues?
        .iter()
        .find(|cue| cue.token_index == token_index)
        .and_then(|cue| cue.pitch_reset_after)
        .filter(|value| value.is_finite() && *value > 0.0)
        .map(clamp01)
}
