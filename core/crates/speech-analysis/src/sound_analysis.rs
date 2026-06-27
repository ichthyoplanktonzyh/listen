use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, ConnectedSpeechFamily,
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
    let connected_speech = explain_connected_speech(alignments, observed, &learning_phones);
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
        connected_speech,
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

pub fn explain_connected_speech(
    alignments: &[PhoneAlignment],
    observed: &[DetectedPhone],
    learning_phones: &[SoundLearningPhone],
) -> Vec<ConnectedSpeechExplanation> {
    let mut values = Vec::new();
    let mut learning_cursor = 0usize;

    for alignment in alignments {
        let canonical_len = alignment.canonical_phones.len();
        let phone_range = if canonical_len == 0 {
            if learning_cursor < learning_phones.len() {
                Some((learning_cursor as u32, learning_cursor as u32))
            } else {
                nearest_learning_phone_range(alignment, learning_phones)
            }
        } else {
            let start = learning_cursor;
            let end = learning_cursor + canonical_len - 1;
            learning_cursor += canonical_len;
            (end < learning_phones.len()).then_some((start as u32, end as u32))
        };

        let detected = observed_slice(observed, alignment);
        let Some(family) = connected_speech_family(alignment, &detected) else {
            continue;
        };
        let confidence = explanation_confidence(alignment, family);
        let (label, hint) = learner_copy(family);
        let status = explanation_status(alignment, family, confidence);
        let learning_symbols = phone_range
            .map(|(start, end)| {
                (start..=end)
                    .filter_map(|index| learning_phones.get(index as usize))
                    .map(|phone| phone.symbol.clone())
                    .collect()
            })
            .unwrap_or_default();

        values.push(ConnectedSpeechExplanation {
            family,
            label: label.into(),
            hint: hint.into(),
            phone_start: phone_range.map(|(start, _)| start),
            phone_end: phone_range.map(|(_, end)| end),
            token_start: alignment.token_start,
            token_end: alignment.token_end.or(alignment.token_start),
            confidence,
            status,
            expected_symbols: alignment.canonical_phones.clone(),
            learning_symbols,
            observed_symbols: detected
                .iter()
                .map(|(_, phone)| phone.symbol.clone())
                .collect(),
            evidence: evidence_copy(family, alignment.kind),
        });
    }

    values
}

fn connected_speech_family(
    alignment: &PhoneAlignment,
    detected: &[(usize, &DetectedPhone)],
) -> Option<ConnectedSpeechFamily> {
    let canonical = alignment
        .canonical_phones
        .iter()
        .map(|phone| strip_stress(phone))
        .collect::<Vec<_>>();
    let observed = detected
        .iter()
        .map(|(_, phone)| normalize_phone_symbol(&phone.symbol))
        .collect::<Vec<_>>();
    match alignment.kind {
        PhoneAlignmentKind::Substitution
            if canonical
                .iter()
                .any(|phone| matches!(phone.as_str(), "T" | "D"))
                && observed
                    .iter()
                    .any(|phone| matches!(phone.as_str(), "DX" | "ɾ")) =>
        {
            Some(ConnectedSpeechFamily::Flapping)
        }
        PhoneAlignmentKind::Substitution
            if canonical.iter().any(|phone| is_vowel(phone))
                && observed
                    .iter()
                    .any(|phone| matches!(phone.as_str(), "AX" | "AH" | "ə")) =>
        {
            Some(ConnectedSpeechFamily::WeakForm)
        }
        PhoneAlignmentKind::Merge => Some(ConnectedSpeechFamily::Assimilation),
        PhoneAlignmentKind::Deletion if alignment.token_start != alignment.token_end => {
            Some(ConnectedSpeechFamily::Contraction)
        }
        PhoneAlignmentKind::Deletion => Some(ConnectedSpeechFamily::Deletion),
        PhoneAlignmentKind::Insertion => Some(ConnectedSpeechFamily::Linking),
        PhoneAlignmentKind::Match | PhoneAlignmentKind::Substitution => None,
    }
}

fn explanation_confidence(alignment: &PhoneAlignment, family: ConnectedSpeechFamily) -> f32 {
    let base = alignment.confidence.clamp(0.0, 1.0);
    if base > 0.0 {
        return base;
    }
    match family {
        ConnectedSpeechFamily::Deletion | ConnectedSpeechFamily::Contraction => 0.62,
        ConnectedSpeechFamily::Linking => 0.58,
        _ => 0.5,
    }
}

fn explanation_status(
    alignment: &PhoneAlignment,
    family: ConnectedSpeechFamily,
    confidence: f32,
) -> ConnectedSpeechExplanationStatus {
    match family {
        ConnectedSpeechFamily::Deletion
        | ConnectedSpeechFamily::Contraction
        | ConnectedSpeechFamily::Linking
            if confidence < 0.75 =>
        {
            ConnectedSpeechExplanationStatus::PossibleByRule
        }
        _ if confidence >= 0.75 && alignment.kind != PhoneAlignmentKind::Insertion => {
            ConnectedSpeechExplanationStatus::DetectedInAudio
        }
        _ => ConnectedSpeechExplanationStatus::SupportedByAudio,
    }
}

fn learner_copy(family: ConnectedSpeechFamily) -> (&'static str, &'static str) {
    match family {
        ConnectedSpeechFamily::WeakForm => (
            "possible reduction",
            "A small function-word or vowel sound may be reduced in fast speech.",
        ),
        ConnectedSpeechFamily::Deletion => (
            "possible deletion",
            "A /t/ or /d/ sound may be weakened or not fully released here.",
        ),
        ConnectedSpeechFamily::Linking => (
            "possible linking",
            "The speaker may connect the end of one word into the next word.",
        ),
        ConnectedSpeechFamily::Assimilation => (
            "possible assimilation",
            "Neighboring sounds may blend so the boundary is easier to say.",
        ),
        ConnectedSpeechFamily::Contraction => (
            "possible contraction",
            "This phrase may be spoken as a shorter connected form.",
        ),
        ConnectedSpeechFamily::Flapping => (
            "possible flap",
            "In American English, /t/ or /d/ can sound like a quick tap between vowels.",
        ),
    }
}

fn evidence_copy(family: ConnectedSpeechFamily, kind: PhoneAlignmentKind) -> String {
    let source = match kind {
        PhoneAlignmentKind::Insertion => "extra observed sound near the word boundary",
        PhoneAlignmentKind::Deletion => "expected sound has little direct audio support",
        PhoneAlignmentKind::Merge => "neighboring expected sounds share one observed region",
        PhoneAlignmentKind::Substitution => {
            "observed sound matches a common connected-speech pattern"
        }
        PhoneAlignmentKind::Match => "matched sound",
    };
    let family = match family {
        ConnectedSpeechFamily::WeakForm => "reduction",
        ConnectedSpeechFamily::Deletion => "deletion",
        ConnectedSpeechFamily::Linking => "linking",
        ConnectedSpeechFamily::Assimilation => "assimilation",
        ConnectedSpeechFamily::Contraction => "contraction",
        ConnectedSpeechFamily::Flapping => "flapping",
    };
    format!("{family} evidence: {source}")
}

fn nearest_learning_phone_range(
    alignment: &PhoneAlignment,
    learning_phones: &[SoundLearningPhone],
) -> Option<(u32, u32)> {
    let target = alignment.detected_phone_start?;
    learning_phones
        .iter()
        .enumerate()
        .filter_map(|(index, phone)| {
            let observed = phone.observed_phone_index?;
            let distance = observed.abs_diff(target);
            Some((distance, index as u32))
        })
        .min_by_key(|(distance, _)| *distance)
        .map(|(_, index)| (index, index))
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

fn normalize_phone_symbol(symbol: &str) -> String {
    strip_stress(symbol).to_ascii_uppercase()
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
        assert!(analysis.connected_speech.is_empty());
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

    #[test]
    fn explains_required_connected_speech_families_without_changing_labels() {
        let canonical = canonical(&["AH", "T", "D", "Y", "N", "T"]);
        let observed = observed(&[
            ("AX", 0, 40),
            ("DX", 40, 80),
            ("JH", 80, 130),
            ("R", 130, 150),
        ]);
        let alignments = vec![
            alignment(
                PhoneAlignmentKind::Substitution,
                &["AH"],
                Some(0),
                Some(0),
                0,
                0.84,
            ),
            alignment(
                PhoneAlignmentKind::Substitution,
                &["T"],
                Some(1),
                Some(1),
                1,
                0.88,
            ),
            alignment(
                PhoneAlignmentKind::Merge,
                &["D", "Y"],
                Some(2),
                Some(2),
                2,
                0.81,
            ),
            alignment(PhoneAlignmentKind::Insertion, &[], Some(3), Some(3), 3, 0.7),
            alignment(
                PhoneAlignmentKind::Deletion,
                &["N", "T"],
                None,
                None,
                4,
                0.0,
            ),
        ];

        let analysis = build_sound_analysis(
            &canonical,
            &observed,
            &alignments,
            "ctc",
            "v1",
            Some("model".into()),
            "arpabet",
        );

        assert_eq!(
            analysis
                .connected_speech
                .iter()
                .map(|value| value.family)
                .collect::<Vec<_>>(),
            vec![
                ConnectedSpeechFamily::WeakForm,
                ConnectedSpeechFamily::Flapping,
                ConnectedSpeechFamily::Assimilation,
                ConnectedSpeechFamily::Linking,
                ConnectedSpeechFamily::Contraction,
            ]
        );
        assert_eq!(analysis.learning_phones[0].symbol, "AH");
        assert_eq!(
            analysis.connected_speech[0].status,
            ConnectedSpeechExplanationStatus::DetectedInAudio
        );
        assert_eq!(
            analysis.connected_speech[3].status,
            ConnectedSpeechExplanationStatus::PossibleByRule
        );
        assert_eq!(analysis.connected_speech[3].phone_start, Some(4));
        assert_eq!(analysis.connected_speech[4].confidence, 0.62);
        assert_eq!(analysis.connected_speech[4].label, "possible contraction");
    }

    #[test]
    fn explains_single_phone_deletion_as_low_confidence_hint() {
        let canonical = canonical(&["T"]);
        let observed = observed(&[("S", 0, 40)]);
        let alignments = vec![alignment(
            PhoneAlignmentKind::Deletion,
            &["T"],
            None,
            None,
            0,
            0.0,
        )];

        let analysis = build_sound_analysis(
            &canonical,
            &observed,
            &alignments,
            "ctc",
            "v1",
            Some("model".into()),
            "arpabet",
        );

        assert_eq!(
            analysis.connected_speech[0].family,
            ConnectedSpeechFamily::Deletion
        );
        assert_eq!(
            analysis.connected_speech[0].status,
            ConnectedSpeechExplanationStatus::PossibleByRule
        );
        assert_eq!(analysis.connected_speech[0].label, "possible deletion");
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

    fn canonical(symbols: &[&str]) -> Vec<CanonicalPhone> {
        symbols
            .iter()
            .enumerate()
            .map(|(index, symbol)| CanonicalPhone {
                symbol: (*symbol).into(),
                token_index: index as u32,
            })
            .collect()
    }

    fn alignment(
        kind: PhoneAlignmentKind,
        canonical: &[&str],
        detected_start: Option<u32>,
        detected_end: Option<u32>,
        token_start: u32,
        confidence: f32,
    ) -> PhoneAlignment {
        PhoneAlignment {
            kind,
            token_start: Some(token_start),
            token_end: Some(token_start + canonical.len().saturating_sub(1) as u32),
            canonical_phones: canonical.iter().map(|value| (*value).into()).collect(),
            detected_phone_start: detected_start,
            detected_phone_end: detected_end,
            confidence,
        }
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
