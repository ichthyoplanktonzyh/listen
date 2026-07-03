use domain::{
    RhythmAnchorImportance, RhythmClaimStatus, RhythmEvidenceClass, RhythmInformationAnchor,
    RhythmInformationAnchorKind, RhythmNucleus, RhythmSignalSource, RhythmStressAnchor,
    SoundLearningPhone, SoundPhoneEvidence,
};

use crate::phonetic_alignment::CanonicalPhone;

use super::constants::MIN_AUDIBLE_ANCHOR_MS;
use super::helpers::{
    arpabet_display, clamp01, is_information_function_word, is_vowel, score_flag,
};
use super::tokens::RhythmToken;

pub(super) fn detect_stress_anchors(tokens: &[RhythmToken]) -> Vec<RhythmStressAnchor> {
    let mut anchors = Vec::new();
    let final_content_token_index = tokens
        .iter()
        .rev()
        .find(|token| !token.is_function_word())
        .map(|token| token.index);
    let mut seen_content_words = Vec::new();
    for token in tokens {
        let content_word = !token.is_function_word();
        let stressed = token.has_primary_stress || token.has_secondary_stress;
        let long_enough = token.duration_ms() >= 180;
        let clearly_timed =
            token.timing_audio_supported && token.duration_ms() >= MIN_AUDIBLE_ANCHOR_MS;
        let energy_prominence = token.energy_prominence_score();
        let pitch_prominence = token.pitch_prominence_score();
        let acoustically_prominent = energy_prominence.is_some() || pitch_prominence.is_some();
        if !content_word {
            continue;
        }
        if !stressed
            && !long_enough
            && !clearly_timed
            && !acoustically_prominent
            && token.text.len() <= 2
        {
            continue;
        }
        let repeated_content = seen_content_words.contains(&token.normalized);
        let final_focus = final_content_token_index == Some(token.index);
        seen_content_words.push(token.normalized.clone());
        let confidence = clamp01(
            0.6 + score_flag(content_word) * 0.08
                + score_flag(token.has_primary_stress) * 0.14
                + score_flag(token.has_secondary_stress) * 0.08
                + score_flag(clearly_timed) * 0.08
                + token.average_confidence.unwrap_or(0.4) * 0.08
                + energy_prominence.unwrap_or(0.0) * 0.14
                + pitch_prominence.unwrap_or(0.0) * 0.14
                + score_flag(final_focus) * 0.08
                - score_flag(repeated_content) * 0.1,
        );
        let mut signal_sources = vec![RhythmSignalSource::TextPrior];
        let mut prominence_cues = vec![RhythmSignalSource::TextPrior];
        if clearly_timed || (long_enough && token.timing_audio_supported) {
            signal_sources.push(RhythmSignalSource::Timing);
            prominence_cues.push(RhythmSignalSource::Timing);
        }
        if energy_prominence.is_some() {
            signal_sources.push(RhythmSignalSource::Energy);
            prominence_cues.push(RhythmSignalSource::Energy);
        }
        if pitch_prominence.is_some() {
            signal_sources.push(RhythmSignalSource::Pitch);
            prominence_cues.push(RhythmSignalSource::Pitch);
        }
        let claim_status = claim_status(&signal_sources);
        let prominence = clamp01(
            0.45 + score_flag(token.has_primary_stress) * 0.16
                + score_flag(token.has_secondary_stress) * 0.08
                + score_flag(clearly_timed) * 0.08
                + energy_prominence.unwrap_or(0.0) * 0.24
                + pitch_prominence.unwrap_or(0.0) * 0.24
                + score_flag(final_focus) * 0.08
                - score_flag(repeated_content) * 0.1,
        );
        anchors.push(RhythmStressAnchor {
            token_index: Some(token.index),
            syllable_index: token.syllable_index,
            phone_start: token.phone_start,
            phone_end: token.phone_end,
            start_ms: token.start_ms,
            end_ms: token.end_ms,
            label: token.text.clone(),
            reason: if repeated_content {
                "Repeated content is slightly backgrounded by the information-structure prior."
                    .into()
            } else if final_focus {
                "Phrase-final content is a likely focus candidate.".into()
            } else if acoustically_prominent {
                "Catch this acoustically prominent vowel/consonant shape as a listening anchor."
                    .into()
            } else if stressed {
                "Catch this stressed vowel/consonant shape as a listening anchor.".into()
            } else if clearly_timed {
                "Catch this clearly timed content sound as a listening anchor.".into()
            } else {
                "Catch this content word as a meaning anchor.".into()
            },
            importance: if token.has_primary_stress || acoustically_prominent || final_focus {
                RhythmAnchorImportance::Primary
            } else {
                RhythmAnchorImportance::Secondary
            },
            is_nucleus: false,
            prominence,
            prominence_cues,
            signal_sources,
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status,
            confidence,
        });
    }
    anchors
}

#[derive(Debug, Clone)]
struct InformationAnchorPhone {
    index: u32,
    token_index: u32,
    symbol: String,
    display_ipa: String,
    start_ms: u64,
    end_ms: u64,
    stress: Option<u8>,
    confidence: Option<f32>,
    signal_sources: Vec<RhythmSignalSource>,
}

pub(super) fn build_information_anchors(
    tokens: &[RhythmToken],
    canonical: &[CanonicalPhone],
    learning_phones: &[SoundLearningPhone],
    stress_anchors: &[RhythmStressAnchor],
    nuclei: &[RhythmNucleus],
) -> Vec<RhythmInformationAnchor> {
    let phones = information_anchor_phones(tokens, canonical, learning_phones);
    let mut values = Vec::new();
    for token in tokens {
        if !token.timing_audio_supported && token.energy_prominence_score().is_none() {
            continue;
        }
        if token.is_function_word() && !is_information_function_word(&token.normalized) {
            continue;
        }
        let token_phones = phones
            .iter()
            .filter(|phone| phone.token_index == token.index)
            .cloned()
            .collect::<Vec<_>>();
        let Some((start, end, nucleus_index, kind)) = select_information_phone_span(&token_phones)
        else {
            continue;
        };
        let span = &token_phones[start..=end];
        let sound = span
            .iter()
            .map(|phone| phone.display_ipa.as_str())
            .collect::<String>()
            .to_lowercase();
        if sound.trim().is_empty() {
            continue;
        }
        let stress_anchor = stress_anchors
            .iter()
            .find(|anchor| anchor.token_index == Some(token.index));
        let is_nucleus = nuclei
            .iter()
            .any(|nucleus| nucleus.token_index == Some(token.index));
        let mut signal_sources = vec![RhythmSignalSource::TextPrior];
        for phone in span {
            for source in &phone.signal_sources {
                if !signal_sources.contains(source) {
                    signal_sources.push(*source);
                }
            }
        }
        if token.timing_audio_supported && !signal_sources.contains(&RhythmSignalSource::Timing) {
            signal_sources.push(RhythmSignalSource::Timing);
        }
        if token.energy_prominence_score().is_some()
            && !signal_sources.contains(&RhythmSignalSource::Energy)
        {
            signal_sources.push(RhythmSignalSource::Energy);
        }
        if token.pitch_prominence_score().is_some()
            && !signal_sources.contains(&RhythmSignalSource::Pitch)
        {
            signal_sources.push(RhythmSignalSource::Pitch);
        }
        let confidence = clamp01(
            span.iter()
                .filter_map(|phone| phone.confidence)
                .next()
                .or(token.average_confidence)
                .unwrap_or(0.55)
                + score_flag(signal_sources.contains(&RhythmSignalSource::PhoneSegmental)) * 0.12
                + score_flag(signal_sources.contains(&RhythmSignalSource::Timing)) * 0.1
                + token.energy_prominence_score().unwrap_or(0.0) * 0.12
                + token.pitch_prominence_score().unwrap_or(0.0) * 0.12,
        );
        let prominence = clamp01(
            stress_anchor
                .map(|anchor| anchor.prominence)
                .unwrap_or(0.45)
                + score_flag(kind == RhythmInformationAnchorKind::Nucleus) * 0.08
                + token.energy_prominence_score().unwrap_or(0.0) * 0.18
                + token.pitch_prominence_score().unwrap_or(0.0) * 0.18,
        );
        values.push(RhythmInformationAnchor {
            id: format!("ia{}", values.len() + 1),
            token_index: Some(token.index),
            phone_start: span.first().map(|phone| phone.index),
            phone_end: span.last().map(|phone| phone.index),
            start_ms: span
                .iter()
                .map(|phone| phone.start_ms)
                .min()
                .unwrap_or(token.start_ms),
            end_ms: span
                .iter()
                .map(|phone| phone.end_ms)
                .max()
                .unwrap_or(token.end_ms)
                .max(token.start_ms + 1),
            label: token.text.clone(),
            sound,
            kind,
            is_nucleus,
            prominence,
            cues: signal_sources.clone(),
            signal_sources: signal_sources.clone(),
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status: claim_status(&signal_sources),
            confidence,
            reason: information_anchor_reason(kind, &token_phones[nucleus_index], token),
        });
    }
    values
}

fn information_anchor_phones(
    tokens: &[RhythmToken],
    canonical: &[CanonicalPhone],
    learning_phones: &[SoundLearningPhone],
) -> Vec<InformationAnchorPhone> {
    if !learning_phones.is_empty() {
        return learning_phones
            .iter()
            .enumerate()
            .filter_map(|(index, phone)| {
                let token_index = phone.token_index?;
                let mut signal_sources = vec![RhythmSignalSource::TextPrior];
                if phone.observed_phone_index.is_some()
                    || matches!(
                        phone.evidence,
                        SoundPhoneEvidence::ObservedOnly
                            | SoundPhoneEvidence::Match
                            | SoundPhoneEvidence::Substitution
                            | SoundPhoneEvidence::Merge
                    )
                {
                    signal_sources.push(RhythmSignalSource::PhoneSegmental);
                    signal_sources.push(RhythmSignalSource::Timing);
                }
                Some(InformationAnchorPhone {
                    index: index as u32,
                    token_index,
                    symbol: phone.symbol.clone(),
                    display_ipa: phone.display_ipa.clone(),
                    start_ms: phone.start_ms,
                    end_ms: phone.end_ms.max(phone.start_ms + 1),
                    stress: phone.stress,
                    confidence: phone.confidence,
                    signal_sources,
                })
            })
            .collect();
    }

    let mut values = Vec::new();
    for token in tokens {
        let token_phones = canonical
            .iter()
            .filter(|phone| phone.token_index == token.index)
            .collect::<Vec<_>>();
        if token_phones.is_empty() {
            continue;
        }
        let duration = token.duration_ms();
        let count = token_phones.len() as u64;
        for (offset, phone) in token_phones.iter().enumerate() {
            let start_ms = token.start_ms + duration.saturating_mul(offset as u64) / count;
            let end_ms = if offset + 1 == token_phones.len() {
                token.end_ms
            } else {
                token.start_ms + duration.saturating_mul(offset as u64 + 1) / count
            };
            let mut signal_sources = vec![RhythmSignalSource::TextPrior];
            if token.timing_audio_supported {
                signal_sources.push(RhythmSignalSource::Timing);
            }
            values.push(InformationAnchorPhone {
                index: values.len() as u32,
                token_index: token.index,
                symbol: phone.symbol.clone(),
                display_ipa: arpabet_display(&phone.symbol),
                start_ms,
                end_ms: end_ms.max(start_ms + 1),
                stress: phone.stress,
                confidence: token.average_confidence,
                signal_sources,
            });
        }
    }
    values
}

fn select_information_phone_span(
    phones: &[InformationAnchorPhone],
) -> Option<(usize, usize, usize, RhythmInformationAnchorKind)> {
    if phones.is_empty() {
        return None;
    }
    let nucleus = phones
        .iter()
        .position(|phone| phone.stress.is_some_and(|stress| stress > 0) && is_vowel(&phone.symbol))
        .or_else(|| phones.iter().position(|phone| is_vowel(&phone.symbol)));
    if let Some(nucleus) = nucleus {
        let mut start = nucleus;
        while start > 0 && !is_vowel(&phones[start - 1].symbol) {
            start -= 1;
        }
        let mut end = nucleus;
        while end + 1 < phones.len() && !is_vowel(&phones[end + 1].symbol) {
            end += 1;
        }
        let kind = if phones[nucleus].stress.is_some_and(|stress| stress > 0) {
            RhythmInformationAnchorKind::Nucleus
        } else if start == end {
            RhythmInformationAnchorKind::Vowel
        } else {
            RhythmInformationAnchorKind::Segment
        };
        return Some((start, end, nucleus, kind));
    }
    Some((0, 0, 0, RhythmInformationAnchorKind::Consonant))
}

fn information_anchor_reason(
    kind: RhythmInformationAnchorKind,
    nucleus: &InformationAnchorPhone,
    token: &RhythmToken,
) -> String {
    match kind {
        RhythmInformationAnchorKind::Nucleus => {
            "This stressed audible sound is a high-value information anchor.".into()
        }
        RhythmInformationAnchorKind::Vowel => {
            "This vowel is the clearest audible point for this information word.".into()
        }
        RhythmInformationAnchorKind::Consonant => {
            "This consonant edge is the clearest audible point for this information word.".into()
        }
        RhythmInformationAnchorKind::Segment => {
            if token.energy_prominence_score().is_some() || token.pitch_prominence_score().is_some()
            {
                "This vowel-plus-consonant sound shape is acoustically foregrounded.".into()
            } else if is_vowel(&nucleus.symbol) {
                "This vowel-plus-consonant sound shape is the information anchor.".into()
            } else {
                "This audible segment carries the information anchor.".into()
            }
        }
    }
}

pub(super) fn claim_status(signal_sources: &[RhythmSignalSource]) -> RhythmClaimStatus {
    if signal_sources.iter().any(|source| is_audio_source(*source)) {
        RhythmClaimStatus::AudioSupported
    } else {
        RhythmClaimStatus::Predicted
    }
}

fn is_audio_source(source: RhythmSignalSource) -> bool {
    matches!(
        source,
        RhythmSignalSource::Timing
            | RhythmSignalSource::Energy
            | RhythmSignalSource::Pitch
            | RhythmSignalSource::PhoneSegmental
    )
}
