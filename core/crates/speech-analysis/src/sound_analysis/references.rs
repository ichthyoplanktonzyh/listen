use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, ConnectedSpeechFamily,
    RhythmAudibleGroup, RhythmAudibleStructure, RhythmConnectedSpeechRef, RhythmDivergenceKind,
    RhythmEvidenceClass, RhythmFrameReferences, RhythmReference, RhythmSignalSource,
    SubtitleSentence, SubtitleTokenKind,
};

use super::helpers::{arpabet_display, strip_stress};

pub(super) fn rhythm_references(
    uses_word_timeline: bool,
    uses_audio_timing: bool,
    uses_energy_cues: bool,
    uses_pitch_cues: bool,
) -> RhythmFrameReferences {
    RhythmFrameReferences {
        citation: RhythmReference {
            label: "citation_form".into(),
            source: "dictionary_lexical_stress".into(),
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
        },
        default_connected: Some(RhythmReference {
            label: "default_connected_variants".into(),
            source: crate::connected_speech_rules::rule_source().into(),
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
        }),
        actual: RhythmReference {
            label: "actual_delivery".into(),
            source: if uses_word_timeline
                && uses_audio_timing
                && uses_energy_cues
                && uses_pitch_cues
            {
                "word_timeline_duration_energy_pitch".into()
            } else if uses_word_timeline && uses_audio_timing && uses_energy_cues {
                "word_timeline_duration_energy".into()
            } else if uses_word_timeline && uses_audio_timing && uses_pitch_cues {
                "word_timeline_duration_pitch".into()
            } else if uses_word_timeline && uses_audio_timing {
                "word_timeline_duration".into()
            } else if uses_word_timeline && uses_energy_cues && uses_pitch_cues {
                "word_timeline_estimated_timing_energy_pitch".into()
            } else if uses_word_timeline && uses_energy_cues {
                "word_timeline_estimated_timing_energy".into()
            } else if uses_word_timeline && uses_pitch_cues {
                "word_timeline_estimated_timing_pitch".into()
            } else if uses_word_timeline {
                "word_timeline_estimated_timing".into()
            } else {
                "phone_timeline_transitional".into()
            },
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
        },
    }
}

pub(super) fn build_connected_speech_refs(
    sentence: Option<&SubtitleSentence>,
    connected_speech: &[ConnectedSpeechExplanation],
) -> Vec<RhythmConnectedSpeechRef> {
    connected_speech
        .iter()
        .enumerate()
        .map(|(index, value)| {
            let predicted_by_rule =
                crate::connected_speech_rules::is_default_rule_explanation(value);
            let signal_sources = match value.status {
                ConnectedSpeechExplanationStatus::PossibleByRule => {
                    vec![RhythmSignalSource::TextPrior]
                }
                ConnectedSpeechExplanationStatus::SupportedByAudio
                | ConnectedSpeechExplanationStatus::DetectedInAudio
                    if predicted_by_rule =>
                {
                    vec![
                        RhythmSignalSource::TextPrior,
                        RhythmSignalSource::PhoneSegmental,
                    ]
                }
                ConnectedSpeechExplanationStatus::SupportedByAudio
                | ConnectedSpeechExplanationStatus::DetectedInAudio => {
                    vec![RhythmSignalSource::PhoneSegmental]
                }
            };
            let (citation_structure, predicted_structure) =
                predicted_audible_structures(sentence, value);
            let actual_structure = actual_audible_structure(value);
            RhythmConnectedSpeechRef {
                id: format!("cs{}", index + 1),
                connected_speech_index: Some(index as u32),
                token_start: value.token_start,
                token_end: value.token_end.or(value.token_start),
                phone_start: value.phone_start,
                phone_end: value.phone_end,
                family: Some(value.family),
                surface_text: connected_surface_text(
                    sentence,
                    value.token_start,
                    value.token_end.or(value.token_start),
                ),
                label: value.label.clone(),
                hint: value.hint.clone(),
                expected_symbols: value.expected_symbols.clone(),
                default_symbols: value.learning_symbols.clone(),
                expected_display_ipa: display_ipa_for_symbols(&value.expected_symbols, false),
                default_display_ipa: display_ipa_for_symbols(&value.learning_symbols, true),
                citation_structure,
                predicted_structure,
                actual_structure,
                divergence: match value.status {
                    ConnectedSpeechExplanationStatus::PossibleByRule => {
                        RhythmDivergenceKind::TeachableRule
                    }
                    ConnectedSpeechExplanationStatus::SupportedByAudio
                    | ConnectedSpeechExplanationStatus::DetectedInAudio
                        if predicted_by_rule =>
                    {
                        RhythmDivergenceKind::TeachableRule
                    }
                    ConnectedSpeechExplanationStatus::SupportedByAudio
                    | ConnectedSpeechExplanationStatus::DetectedInAudio => {
                        RhythmDivergenceKind::ClipSpecific
                    }
                },
                signal_sources,
                evidence_class: RhythmEvidenceClass::HeuristicProxy,
                confidence: value.confidence,
            }
        })
        .collect()
}

fn predicted_audible_structures(
    sentence: Option<&SubtitleSentence>,
    value: &ConnectedSpeechExplanation,
) -> (
    Option<RhythmAudibleStructure>,
    Option<RhythmAudibleStructure>,
) {
    let word_groups = source_word_groups(sentence, value.token_start, value.token_end);
    let citation = (!word_groups.is_empty()).then(|| structure(word_groups.clone(), " | "));

    let predicted_groups = if value.family == ConnectedSpeechFamily::Linking
        && value.evidence.contains("link-consonant-vowel")
        && word_groups.len() == 2
    {
        link_consonant_to_vowel(&word_groups)
    } else if value.family == ConnectedSpeechFamily::Linking
        && value.evidence.contains("link-same-consonant")
        && word_groups.len() == 2
    {
        coalesce_shared_consonant(&word_groups)
    } else if value.family == ConnectedSpeechFamily::Deletion
        && value.evidence.contains("possible-t-d-deletion")
        && word_groups.len() == 2
    {
        delete_final_t_or_d(&word_groups)
    } else if value.family == ConnectedSpeechFamily::Flapping
        && value.evidence.contains("american-flap-t-d")
        && word_groups.len() == 1
    {
        flap_intervocalic_t_or_d(&word_groups)
    } else if !value.learning_symbols.is_empty() {
        vec![RhythmAudibleGroup {
            symbols: value.learning_symbols.clone(),
            display_ipa: display_ipa_for_symbols(&value.learning_symbols, true),
            source_token_indices: token_range(value.token_start, value.token_end),
        }]
    } else {
        Vec::new()
    };
    let predicted = (!predicted_groups.is_empty()).then(|| structure(predicted_groups, "."));
    (citation, predicted)
}

fn actual_audible_structure(value: &ConnectedSpeechExplanation) -> Option<RhythmAudibleStructure> {
    if value.status == ConnectedSpeechExplanationStatus::PossibleByRule
        || value.observed_symbols.is_empty()
    {
        return None;
    }
    Some(structure(
        vec![RhythmAudibleGroup {
            symbols: value.observed_symbols.clone(),
            display_ipa: display_ipa_for_symbols(&value.observed_symbols, false),
            source_token_indices: token_range(value.token_start, value.token_end),
        }],
        ".",
    ))
}

fn source_word_groups(
    sentence: Option<&SubtitleSentence>,
    token_start: Option<u32>,
    token_end: Option<u32>,
) -> Vec<RhythmAudibleGroup> {
    let (Some(sentence), Some(start), Some(end)) = (sentence, token_start, token_end) else {
        return Vec::new();
    };
    sentence
        .tokens
        .iter()
        .filter(|token| {
            token.kind == SubtitleTokenKind::Word && token.index >= start && token.index <= end
        })
        .filter_map(|token| {
            let (symbols, _) = crate::pronunciation_symbols(&token.text, token.index, None);
            (!symbols.is_empty()).then(|| RhythmAudibleGroup {
                display_ipa: display_ipa_for_symbols(&symbols, false),
                symbols,
                source_token_indices: vec![token.index],
            })
        })
        .collect()
}

fn link_consonant_to_vowel(groups: &[RhythmAudibleGroup]) -> Vec<RhythmAudibleGroup> {
    let mut first = groups[0].clone();
    let mut second = groups[1].clone();
    let Some(linked) = first.symbols.pop() else {
        return groups.to_vec();
    };
    first.display_ipa = display_ipa_for_symbols(&first.symbols, false);
    second.symbols.insert(0, linked);
    // Linking changes the audible boundary, not the vowel quality. Keep the
    // citation vowel (e.g. `up` /ʌp/) instead of applying the weak-form AH→ə
    // display convention used by reduction rules.
    second.display_ipa = display_ipa_for_symbols(&second.symbols, false);
    for token in &first.source_token_indices {
        if !second.source_token_indices.contains(token) {
            second.source_token_indices.insert(0, *token);
        }
    }
    [first, second]
        .into_iter()
        .filter(|group| !group.symbols.is_empty())
        .collect()
}

fn coalesce_shared_consonant(groups: &[RhythmAudibleGroup]) -> Vec<RhythmAudibleGroup> {
    let mut first = groups[0].clone();
    let mut second = groups[1].clone();
    if first.symbols.last().map(|value| strip_stress(value))
        == second.symbols.first().map(|value| strip_stress(value))
    {
        first.symbols.pop();
        first.display_ipa = display_ipa_for_symbols(&first.symbols, false);
        for token in &first.source_token_indices {
            if !second.source_token_indices.contains(token) {
                second.source_token_indices.insert(0, *token);
            }
        }
    }
    [first, second]
        .into_iter()
        .filter(|group| !group.symbols.is_empty())
        .collect()
}

fn delete_final_t_or_d(groups: &[RhythmAudibleGroup]) -> Vec<RhythmAudibleGroup> {
    let mut predicted = groups.to_vec();
    let first = &mut predicted[0];
    if first
        .symbols
        .last()
        .is_some_and(|symbol| matches!(strip_stress(symbol).as_str(), "T" | "D"))
    {
        first.symbols.pop();
        first.display_ipa = display_ipa_for_symbols(&first.symbols, false);
    }
    predicted
        .into_iter()
        .filter(|group| !group.symbols.is_empty())
        .collect()
}

fn flap_intervocalic_t_or_d(groups: &[RhythmAudibleGroup]) -> Vec<RhythmAudibleGroup> {
    let mut predicted = groups.to_vec();
    let group = &mut predicted[0];
    for index in 1..group.symbols.len().saturating_sub(1) {
        if matches!(strip_stress(&group.symbols[index]).as_str(), "T" | "D")
            && crate::arpabet_is_vowel(&group.symbols[index - 1])
            && crate::arpabet_is_vowel(&group.symbols[index + 1])
        {
            group.symbols[index] = "DX".into();
        }
    }
    group.display_ipa = display_ipa_for_symbols(&group.symbols, false);
    predicted
}

fn structure(groups: Vec<RhythmAudibleGroup>, separator: &str) -> RhythmAudibleStructure {
    let displays = groups
        .iter()
        .map(|group| group.display_ipa.as_str())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    RhythmAudibleStructure {
        display_ipa: displays.join(separator),
        learner_cue: displays.join("-"),
        groups,
    }
}

fn token_range(start: Option<u32>, end: Option<u32>) -> Vec<u32> {
    let (Some(start), Some(end)) = (start, end.or(start)) else {
        return Vec::new();
    };
    (start..=end).collect()
}

fn display_ipa_for_symbols(symbols: &[String], connected: bool) -> String {
    symbols
        .iter()
        .map(|symbol| {
            let display: String = if connected && strip_stress(symbol) == "AH" {
                "ə".into()
            } else {
                arpabet_display(symbol)
            };
            display.to_ascii_lowercase()
        })
        .collect::<Vec<_>>()
        .join("")
}

fn connected_surface_text(
    sentence: Option<&SubtitleSentence>,
    token_start: Option<u32>,
    token_end: Option<u32>,
) -> String {
    let (Some(sentence), Some(start), Some(end)) = (sentence, token_start, token_end) else {
        return String::new();
    };
    sentence
        .tokens
        .iter()
        .filter(|token| {
            token.kind == SubtitleTokenKind::Word && token.index >= start && token.index <= end
        })
        .map(|token| token.text.as_str())
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{SubtitleSentenceId, SubtitleToken, TimeMs};

    fn sentence(text: &str) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("s").unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1000),
            original_text: text.into(),
            display_text: text.into(),
            tokens: text
                .split_whitespace()
                .enumerate()
                .map(|(index, text)| SubtitleToken {
                    index: index as u32,
                    kind: SubtitleTokenKind::Word,
                    text: text.into(),
                    normalized: Some(crate::normalize_word(text)),
                    start_char: 0,
                    end_char: text.len() as u32,
                })
                .collect(),
        }
    }

    #[test]
    fn linking_prediction_resegments_written_words_into_audible_groups() {
        let sentence = sentence("pick up");
        let predictions = crate::connected_speech_rules::predict_default_connected(&sentence);
        let linking = predictions
            .iter()
            .find(|value| value.family == ConnectedSpeechFamily::Linking)
            .expect("linking prediction");
        let reference = build_connected_speech_refs(Some(&sentence), std::slice::from_ref(linking))
            .pop()
            .unwrap();

        let citation = reference.citation_structure.unwrap();
        assert_eq!(citation.display_ipa, "pɪk | ʌp");
        assert_eq!(citation.groups[0].source_token_indices, [0]);
        assert_eq!(citation.groups[1].source_token_indices, [1]);

        let predicted = reference.predicted_structure.unwrap();
        assert_eq!(predicted.display_ipa, "pɪ.kʌp");
        assert_eq!(predicted.learner_cue, "pɪ-kʌp");
        assert_eq!(predicted.groups[0].display_ipa, "pɪ");
        assert_eq!(predicted.groups[1].display_ipa, "kʌp");
        assert_eq!(predicted.groups[1].source_token_indices, [0, 1]);
        assert!(reference.actual_structure.is_none());
    }

    #[test]
    fn audio_backed_explanation_keeps_observed_structure_separate_from_prediction() {
        let sentence = sentence("to go");
        let explanation = ConnectedSpeechExplanation {
            family: ConnectedSpeechFamily::WeakForm,
            label: "possible reduction".into(),
            hint: String::new(),
            phone_start: Some(0),
            phone_end: Some(1),
            token_start: Some(0),
            token_end: Some(0),
            confidence: 0.9,
            status: ConnectedSpeechExplanationStatus::DetectedInAudio,
            expected_symbols: vec!["T".into(), "UW".into()],
            learning_symbols: vec!["T".into(), "AH".into()],
            observed_symbols: vec!["T".into(), "AX".into()],
            evidence: "audio".into(),
        };
        let reference = build_connected_speech_refs(Some(&sentence), &[explanation])
            .pop()
            .unwrap();

        assert_eq!(reference.predicted_structure.unwrap().display_ipa, "tə");
        let actual = reference.actual_structure.unwrap();
        assert_eq!(actual.display_ipa, "tə");
        assert_eq!(actual.groups[0].source_token_indices, [0]);
        assert!(
            reference
                .signal_sources
                .contains(&RhythmSignalSource::PhoneSegmental)
        );
    }

    #[test]
    fn deletion_prediction_removes_the_boundary_phone_from_the_full_phrase() {
        let sentence = sentence("last call");
        let predictions = crate::connected_speech_rules::predict_default_connected(&sentence);
        let deletion = predictions
            .iter()
            .find(|value| value.family == ConnectedSpeechFamily::Deletion)
            .expect("deletion prediction");
        let reference =
            build_connected_speech_refs(Some(&sentence), std::slice::from_ref(deletion))
                .pop()
                .unwrap();

        let citation = reference.citation_structure.unwrap();
        let predicted = reference.predicted_structure.unwrap();
        assert_eq!(citation.display_ipa, "læst | kɔl");
        assert_eq!(predicted.display_ipa, "læs.kɔl");
        assert_eq!(predicted.learner_cue, "læs-kɔl");
        assert!(reference.actual_structure.is_none());
    }

    #[test]
    fn flapping_prediction_replaces_the_phone_inside_the_full_word() {
        let sentence = sentence("water bottle");
        let predictions = crate::connected_speech_rules::predict_default_connected(&sentence);
        let flapping = predictions
            .iter()
            .find(|value| {
                value.family == ConnectedSpeechFamily::Flapping && value.token_start == Some(0)
            })
            .expect("flapping prediction");
        let reference =
            build_connected_speech_refs(Some(&sentence), std::slice::from_ref(flapping))
                .pop()
                .unwrap();

        let citation = reference.citation_structure.unwrap();
        let predicted = reference.predicted_structure.unwrap();
        assert!(citation.display_ipa.contains('t'));
        assert!(predicted.display_ipa.contains('ɾ'));
        assert!(!predicted.display_ipa.contains('t'));
        assert_eq!(predicted.groups[0].source_token_indices, [0]);
        assert!(reference.actual_structure.is_none());
    }

    #[test]
    fn complete_rule_symbols_render_weak_contraction_and_assimilation_structures() {
        for (text, family, expected_a, expected_b, expected_cue) in [
            ("to go", ConnectedSpeechFamily::WeakForm, "tu", "tə", "tə"),
            (
                "could have gone",
                ConnectedSpeechFamily::Contraction,
                "kʊd | hæv",
                "kʊdəv",
                "kʊdəv",
            ),
            (
                "did you see",
                ConnectedSpeechFamily::Assimilation,
                "dɪd | ju",
                "dɪdʒu",
                "dɪdʒu",
            ),
            (
                "have to leave",
                ConnectedSpeechFamily::Contraction,
                "hæv | tu",
                "hæftə",
                "hæftə",
            ),
            (
                "let me see",
                ConnectedSpeechFamily::Contraction,
                "lɛt | mi",
                "lɛmi",
                "lɛmi",
            ),
            (
                "out of time",
                ConnectedSpeechFamily::Contraction,
                "aʊt | ʌv",
                "aʊɾə",
                "aʊɾə",
            ),
        ] {
            let sentence = sentence(text);
            let predictions = crate::connected_speech_rules::predict_default_connected(&sentence);
            let prediction = predictions
                .iter()
                .find(|value| value.family == family && value.token_start == Some(0))
                .unwrap_or_else(|| panic!("{family:?} prediction for {text}"));
            let reference =
                build_connected_speech_refs(Some(&sentence), std::slice::from_ref(prediction))
                    .pop()
                    .unwrap();

            assert_eq!(
                reference.citation_structure.unwrap().display_ipa,
                expected_a
            );
            let predicted = reference.predicted_structure.unwrap();
            assert_eq!(predicted.display_ipa, expected_b);
            assert_eq!(predicted.learner_cue, expected_cue);
            assert!(reference.actual_structure.is_none());
        }
    }
}
