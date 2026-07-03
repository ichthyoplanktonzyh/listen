use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, ConnectedSpeechFamily,
    DetectedPhone, PhoneAlignment, PhoneAlignmentKind, SoundLearningPhone, SubtitleSentence,
};

use super::helpers::{is_vowel, overlaps_token_range, strip_stress};
use super::phones::observed_slice;

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

pub(super) fn connected_speech_with_default(
    sentence: Option<&SubtitleSentence>,
    audio_connected_speech: Vec<ConnectedSpeechExplanation>,
) -> Vec<ConnectedSpeechExplanation> {
    let mut default_connected = sentence
        .map(crate::connected_speech_rules::predict_default_connected)
        .unwrap_or_default();
    if default_connected.is_empty() {
        return audio_connected_speech;
    }

    let mut values = Vec::new();
    for audio in audio_connected_speech {
        if let Some(default_index) = default_connected
            .iter()
            .position(|candidate| connected_speech_rule_matches(candidate, &audio))
        {
            let mut merged = default_connected.remove(default_index);
            merged.status = audio.status;
            merged.phone_start = audio.phone_start;
            merged.phone_end = audio.phone_end;
            if !audio.expected_symbols.is_empty() {
                merged.expected_symbols = audio.expected_symbols;
            }
            if !audio.learning_symbols.is_empty() {
                merged.learning_symbols = audio.learning_symbols;
            }
            merged.observed_symbols = audio.observed_symbols;
            merged.confidence = merged.confidence.max(audio.confidence);
            merged.evidence = format!("{}; {}", merged.evidence, audio.evidence);
            values.push(merged);
        } else {
            values.push(audio);
        }
    }
    values.extend(default_connected);
    values.sort_by_key(|value| {
        (
            value.token_start.unwrap_or(u32::MAX),
            value.token_end.unwrap_or(u32::MAX),
            value.label.clone(),
        )
    });
    values
}

fn connected_speech_rule_matches(
    default_rule: &ConnectedSpeechExplanation,
    audio: &ConnectedSpeechExplanation,
) -> bool {
    default_rule.family == audio.family
        && overlaps_token_range(
            default_rule.token_start,
            default_rule.token_end.or(default_rule.token_start),
            audio.token_start,
            audio.token_end.or(audio.token_start),
        )
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
        // A raw CTC insertion is not enough evidence for learner-facing linking.
        // Real linking needs cross-token boundary context; otherwise every extra
        // observed phone becomes a noisy "possible linking" marker.
        PhoneAlignmentKind::Insertion => None,
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

fn normalize_phone_symbol(symbol: &str) -> String {
    strip_stress(symbol).to_ascii_uppercase()
}
