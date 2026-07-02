use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, RhythmConnectedSpeechRef,
    RhythmDivergenceKind, RhythmEvidenceClass, RhythmFrameReferences, RhythmReference,
    RhythmSignalSource, SubtitleSentence, SubtitleTokenKind,
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
