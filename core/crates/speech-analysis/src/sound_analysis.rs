use domain::{
    DetectedPhone, PhoneAlignment, PhoneAlignmentKind, ProsodicBoundaryEvidence, SoundAnalysis,
    SoundLearningPhone, SoundPhoneEvidence, SoundProsodicPhrase, SoundSyllable, SyllableStress,
};

use crate::phonetic_alignment::CanonicalPhone;

const PAUSE_BOUNDARY_MS: u64 = 100;

pub fn build_sound_analysis(
    canonical: &[CanonicalPhone],
    observed: &[DetectedPhone],
    alignments: &[PhoneAlignment],
    provider_id: &str,
    provider_version: &str,
    model_revision: Option<String>,
    phone_set: &str,
) -> SoundAnalysis {
    let learning_phones = build_learning_phones(canonical, observed, alignments, phone_set);
    let syllables = syllabify(&learning_phones);
    let prosodic_phrases = detect_prosodic_phrases(&syllables);
    SoundAnalysis {
        provider_id: provider_id.into(),
        provider_version: provider_version.into(),
        model_revision,
        phone_set: phone_set.into(),
        generated_from: if canonical.is_empty() {
            "observed_phones".into()
        } else {
            "expected_phones_aligned_to_observed_timing".into()
        },
        learning_phones,
        syllables,
        prosodic_phrases,
    }
}

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

fn observed_slice<'a>(
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
    SoundSyllable {
        phones: (start..=end).map(|value| value as u32).collect(),
        onset,
        nucleus,
        coda,
        start_ms: phones[start].start_ms,
        end_ms: phones[end].end_ms,
        stress: SyllableStress::Unknown,
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

fn is_vowel(symbol: &str) -> bool {
    matches!(
        strip_stress(symbol).as_str(),
        "AA" | "AE"
            | "AH"
            | "AO"
            | "AW"
            | "AX"
            | "AY"
            | "EH"
            | "ER"
            | "EY"
            | "IH"
            | "IY"
            | "OW"
            | "OY"
            | "UH"
            | "UW"
    )
}

fn strip_stress(symbol: &str) -> String {
    symbol
        .chars()
        .filter(|value| !value.is_ascii_digit())
        .collect::<String>()
        .to_ascii_uppercase()
}

fn arpabet_display(symbol: &str) -> String {
    match strip_stress(symbol).as_str() {
        "AA" => "ɑ",
        "AE" => "æ",
        "AH" => "ʌ",
        "AO" => "ɔ",
        "AW" => "aʊ",
        "AX" => "ə",
        "AY" => "aɪ",
        "EH" => "ɛ",
        "ER" => "ɝ",
        "EY" => "eɪ",
        "IH" => "ɪ",
        "IY" => "i",
        "OW" => "oʊ",
        "OY" => "ɔɪ",
        "UH" => "ʊ",
        "UW" => "u",
        "SH" => "ʃ",
        "ZH" => "ʒ",
        "TH" => "θ",
        "DH" => "ð",
        "CH" => "tʃ",
        "JH" => "dʒ",
        "NG" => "ŋ",
        "Y" => "j",
        "HH" => "h",
        "DX" => "ɾ",
        other => other,
    }
    .into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::phonetic_alignment::align_phones;

    #[test]
    fn keeps_expected_label_when_observed_label_mismatches() {
        let canonical = vec![CanonicalPhone {
            symbol: "S".into(),
            token_index: 0,
        }];
        let observed = observed(&[("K", 100, 180)]);
        let alignments = align_phones(&canonical, &observed);
        let analysis = build_sound_analysis(
            &canonical,
            &observed,
            &alignments,
            "ctc",
            "v1",
            Some("model".into()),
            "arpabet",
        );

        assert_eq!(analysis.learning_phones[0].symbol, "S");
        assert_eq!(
            analysis.learning_phones[0].observed_symbol.as_deref(),
            Some("K")
        );
        assert_eq!(
            analysis.learning_phones[0].evidence,
            SoundPhoneEvidence::Substitution
        );
        assert_eq!(analysis.learning_phones[0].start_ms, 100);
    }

    #[test]
    fn syllabifies_with_onset_maximization_and_pause_phrases() {
        let phones = vec![
            learning("S", 0, 50),
            learning("T", 50, 100),
            learning("R", 100, 150),
            learning("IY", 150, 220),
            learning("T", 220, 260),
            learning("AE", 420, 500),
        ];
        let syllables = syllabify(&phones);
        assert_eq!(syllables.len(), 2);
        assert_eq!(syllables[0].onset, vec![0, 1, 2]);
        assert_eq!(syllables[0].nucleus, vec![3]);
        assert_eq!(syllables[0].coda, vec![4]);
        assert_eq!(syllables[1].onset, Vec::<u32>::new());

        let phrases = detect_prosodic_phrases(&syllables);
        assert_eq!(phrases.len(), 2);
        assert_eq!(
            phrases[1].boundary_evidence,
            ProsodicBoundaryEvidence::Pause
        );
    }

    fn observed(values: &[(&str, u64, u64)]) -> Vec<DetectedPhone> {
        values
            .iter()
            .map(|(symbol, start_ms, end_ms)| DetectedPhone {
                symbol: (*symbol).into(),
                display_ipa: (*symbol).into(),
                phone_set: "arpabet".into(),
                start_ms: *start_ms,
                end_ms: *end_ms,
                confidence: Some(0.4),
                token_index: None,
                provider_id: "ctc".into(),
                provider_version: "v1".into(),
                model_revision: "model".into(),
            })
            .collect()
    }

    fn learning(symbol: &str, start_ms: u64, end_ms: u64) -> SoundLearningPhone {
        SoundLearningPhone {
            symbol: symbol.into(),
            display_ipa: symbol.into(),
            phone_set: "arpabet".into(),
            start_ms,
            end_ms,
            confidence: Some(0.9),
            token_index: None,
            observed_phone_index: None,
            observed_symbol: None,
            evidence: SoundPhoneEvidence::Match,
        }
    }
}
