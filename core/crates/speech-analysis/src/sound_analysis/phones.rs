use domain::{
    DetectedPhone, PhoneAlignment, PhoneAlignmentKind, ProsodicBoundaryEvidence,
    SoundLearningPhone, SoundPhoneEvidence, SoundProsodicPhrase, SoundSyllable, SyllableStress,
};

use crate::phonetic_alignment::CanonicalPhone;

use super::constants::PAUSE_BOUNDARY_MS;
use super::helpers::{arpabet_display, is_vowel};

pub fn build_learning_phones(
    canonical: &[CanonicalPhone],
    observed: &[DetectedPhone],
    alignments: &[PhoneAlignment],
    phone_set: &str,
) -> Vec<SoundLearningPhone> {
    if canonical.is_empty() {
        return observed
            .iter()
            .enumerate()
            .map(|(index, phone)| SoundLearningPhone {
                symbol: phone.symbol.clone(),
                display_ipa: phone.display_ipa.clone(),
                phone_set: phone.phone_set.clone(),
                start_ms: phone.start_ms,
                end_ms: phone.end_ms,
                confidence: phone.confidence,
                token_index: phone.token_index,
                stress: None,
                observed_phone_index: Some(index as u32),
                observed_symbol: Some(phone.symbol.clone()),
                evidence: SoundPhoneEvidence::ObservedOnly,
            })
            .collect();
    }

    let mut values = Vec::new();
    for alignment in alignments {
        match alignment.kind {
            PhoneAlignmentKind::Insertion => {}
            PhoneAlignmentKind::Deletion => {
                for symbol in &alignment.canonical_phones {
                    let index = values.len();
                    let (start_ms, end_ms) = estimated_slot(canonical.len(), observed, index);
                    values.push(SoundLearningPhone {
                        symbol: symbol.clone(),
                        display_ipa: arpabet_display(symbol),
                        phone_set: phone_set.into(),
                        start_ms,
                        end_ms,
                        confidence: None,
                        token_index: alignment.token_start,
                        stress: canonical
                            .iter()
                            .find(|phone| phone.symbol == *symbol)
                            .and_then(|phone| phone.stress),
                        observed_phone_index: None,
                        observed_symbol: None,
                        evidence: SoundPhoneEvidence::Deletion,
                    });
                }
            }
            PhoneAlignmentKind::Match
            | PhoneAlignmentKind::Substitution
            | PhoneAlignmentKind::Merge => {
                let observed_slice = observed_slice(observed, alignment);
                let evidence = match alignment.kind {
                    PhoneAlignmentKind::Match => SoundPhoneEvidence::Match,
                    PhoneAlignmentKind::Substitution => SoundPhoneEvidence::Substitution,
                    PhoneAlignmentKind::Merge => SoundPhoneEvidence::Merge,
                    _ => SoundPhoneEvidence::ExpectedOnly,
                };
                for (offset, symbol) in alignment.canonical_phones.iter().enumerate() {
                    let (start_ms, end_ms, confidence, observed_index, observed_symbol) =
                        aligned_timing(&observed_slice, offset, alignment.canonical_phones.len());
                    values.push(SoundLearningPhone {
                        symbol: symbol.clone(),
                        display_ipa: arpabet_display(symbol),
                        phone_set: phone_set.into(),
                        start_ms,
                        end_ms,
                        confidence,
                        token_index: alignment.token_start,
                        stress: canonical
                            .iter()
                            .find(|phone| {
                                phone.symbol == *symbol
                                    && Some(phone.token_index) == alignment.token_start
                            })
                            .and_then(|phone| phone.stress),
                        observed_phone_index: observed_index,
                        observed_symbol,
                        evidence,
                    });
                }
            }
        }
    }

    if values.is_empty() {
        canonical
            .iter()
            .enumerate()
            .map(|(index, phone)| {
                let (start_ms, end_ms) = estimated_slot(canonical.len(), observed, index);
                SoundLearningPhone {
                    symbol: phone.symbol.clone(),
                    display_ipa: arpabet_display(&phone.symbol),
                    phone_set: phone_set.into(),
                    start_ms,
                    end_ms,
                    confidence: None,
                    token_index: Some(phone.token_index),
                    stress: phone.stress,
                    observed_phone_index: None,
                    observed_symbol: None,
                    evidence: SoundPhoneEvidence::ExpectedOnly,
                }
            })
            .collect()
    } else {
        values
    }
}

pub fn syllabify(phones: &[SoundLearningPhone]) -> Vec<SoundSyllable> {
    if phones.is_empty() {
        return Vec::new();
    }
    let nuclei = phones
        .iter()
        .enumerate()
        .filter_map(|(index, phone)| is_vowel(&phone.symbol).then_some(index))
        .collect::<Vec<_>>();
    if nuclei.is_empty() {
        return vec![syllable(
            0,
            phones.len() - 1,
            Vec::new(),
            Vec::new(),
            (0..phones.len()).map(|value| value as u32).collect(),
            phones,
        )];
    }

    let mut starts = Vec::with_capacity(nuclei.len());
    let mut ends = Vec::with_capacity(nuclei.len());
    starts.push(0);
    for pair in nuclei.windows(2) {
        let prev_nucleus = pair[0];
        let next_nucleus = pair[1];
        let consonants = next_nucleus.saturating_sub(prev_nucleus + 1);
        let has_pause_before_next_nucleus = next_nucleus > 0
            && phones[next_nucleus]
                .start_ms
                .saturating_sub(phones[next_nucleus - 1].end_ms)
                >= PAUSE_BOUNDARY_MS;
        let next_start = if consonants == 0 || has_pause_before_next_nucleus {
            next_nucleus
        } else {
            next_nucleus - 1
        };
        ends.push(next_start.saturating_sub(1));
        starts.push(next_start);
    }
    ends.push(phones.len() - 1);

    nuclei
        .iter()
        .enumerate()
        .map(|(syllable_index, nucleus)| {
            let start = starts[syllable_index];
            let end = ends[syllable_index];
            let onset = (start..*nucleus).map(|value| value as u32).collect();
            let coda = ((*nucleus + 1)..=end).map(|value| value as u32).collect();
            syllable(start, end, onset, vec![*nucleus as u32], coda, phones)
        })
        .collect()
}

pub fn detect_prosodic_phrases(syllables: &[SoundSyllable]) -> Vec<SoundProsodicPhrase> {
    if syllables.is_empty() {
        return Vec::new();
    }
    let mut phrases = Vec::new();
    let mut start = 0usize;
    let mut evidence = ProsodicBoundaryEvidence::SentenceStart;
    for index in 1..syllables.len() {
        let gap = syllables[index]
            .start_ms
            .saturating_sub(syllables[index - 1].end_ms);
        if gap >= PAUSE_BOUNDARY_MS {
            phrases.push(phrase(start, index - 1, evidence, 0.95, syllables));
            start = index;
            evidence = ProsodicBoundaryEvidence::Pause;
        }
    }
    phrases.push(phrase(
        start,
        syllables.len() - 1,
        if start == 0 {
            ProsodicBoundaryEvidence::SentenceEnd
        } else {
            evidence
        },
        0.9,
        syllables,
    ));
    phrases
}

pub(super) fn observed_slice<'a>(
    observed: &'a [DetectedPhone],
    alignment: &PhoneAlignment,
) -> Vec<(usize, &'a DetectedPhone)> {
    let Some(start) = alignment.detected_phone_start else {
        return Vec::new();
    };
    let Some(end) = alignment.detected_phone_end else {
        return Vec::new();
    };
    (start as usize..=end as usize)
        .filter_map(|index| observed.get(index).map(|phone| (index, phone)))
        .collect()
}

fn aligned_timing(
    observed_slice: &[(usize, &DetectedPhone)],
    offset: usize,
    canonical_len: usize,
) -> (u64, u64, Option<f32>, Option<u32>, Option<String>) {
    if observed_slice.is_empty() {
        return (0, 1, None, None, None);
    }
    if observed_slice.len() == canonical_len {
        let (index, phone) = observed_slice[offset];
        return (
            phone.start_ms,
            phone.end_ms,
            phone.confidence,
            Some(index as u32),
            Some(phone.symbol.clone()),
        );
    }
    let (index, phone) = observed_slice[offset.min(observed_slice.len() - 1)];
    let duration = phone.end_ms.saturating_sub(phone.start_ms).max(1);
    let width = (duration / canonical_len.max(1) as u64).max(1);
    let start_ms = phone.start_ms + width * offset as u64;
    let end_ms = if offset + 1 == canonical_len {
        phone.end_ms
    } else {
        start_ms + width
    };
    (
        start_ms,
        end_ms.max(start_ms + 1),
        phone.confidence,
        Some(index as u32),
        Some(phone.symbol.clone()),
    )
}

fn estimated_slot(total: usize, observed: &[DetectedPhone], index: usize) -> (u64, u64) {
    let start = observed.first().map(|phone| phone.start_ms).unwrap_or(0);
    let end = observed.last().map(|phone| phone.end_ms).unwrap_or(1);
    let duration = end.saturating_sub(start).max(total.max(1) as u64);
    let width = (duration / total.max(1) as u64).max(1);
    let phone_start = start + width * index as u64;
    (
        phone_start,
        (phone_start + width).min(end).max(phone_start + 1),
    )
}

fn syllable(
    start: usize,
    end: usize,
    onset: Vec<u32>,
    nucleus: Vec<u32>,
    coda: Vec<u32>,
    phones: &[SoundLearningPhone],
) -> SoundSyllable {
    let stress = nucleus
        .iter()
        .filter_map(|index| phones.get(*index as usize).and_then(|phone| phone.stress))
        .map(stress_level)
        .next()
        .unwrap_or(SyllableStress::Unknown);
    SoundSyllable {
        phones: (start..=end).map(|value| value as u32).collect(),
        onset,
        nucleus,
        coda,
        start_ms: phones[start].start_ms,
        end_ms: phones[end].end_ms,
        stress,
    }
}

fn stress_level(value: u8) -> SyllableStress {
    match value {
        1 => SyllableStress::Primary,
        2 => SyllableStress::Secondary,
        0 => SyllableStress::Unstressed,
        _ => SyllableStress::Unknown,
    }
}

fn phrase(
    start: usize,
    end: usize,
    boundary_evidence: ProsodicBoundaryEvidence,
    confidence: f32,
    syllables: &[SoundSyllable],
) -> SoundProsodicPhrase {
    SoundProsodicPhrase {
        syllables: (start..=end).map(|value| value as u32).collect(),
        start_ms: syllables[start].start_ms,
        end_ms: syllables[end].end_ms,
        boundary_evidence,
        confidence,
    }
}
