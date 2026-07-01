use std::collections::HashSet;

use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, ConnectedSpeechFamily,
    SubtitleSentence, SubtitleTokenKind,
};

const RULE_SOURCE: &str = "english_connected_speech_rules_v1";

struct WeakForm {
    word: &'static str,
    canonical: &'static [&'static str],
    reduced: &'static [&'static str],
}

const WEAK_FORMS: &[WeakForm] = &[
    WeakForm {
        word: "a",
        canonical: &["EY"],
        reduced: &["AH"],
    },
    WeakForm {
        word: "am",
        canonical: &["AE", "M"],
        reduced: &["AH", "M"],
    },
    WeakForm {
        word: "an",
        canonical: &["AE", "N"],
        reduced: &["AH", "N"],
    },
    WeakForm {
        word: "and",
        canonical: &["AE", "N", "D"],
        reduced: &["AH", "N", "D"],
    },
    WeakForm {
        word: "are",
        canonical: &["AA", "R"],
        reduced: &["ER"],
    },
    WeakForm {
        word: "as",
        canonical: &["AE", "Z"],
        reduced: &["AH", "Z"],
    },
    WeakForm {
        word: "at",
        canonical: &["AE", "T"],
        reduced: &["AH", "T"],
    },
    WeakForm {
        word: "be",
        canonical: &["B", "IY"],
        reduced: &["B", "IY"],
    },
    WeakForm {
        word: "been",
        canonical: &["B", "IH", "N"],
        reduced: &["B", "AH", "N"],
    },
    WeakForm {
        word: "but",
        canonical: &["B", "AH", "T"],
        reduced: &["B", "AH", "T"],
    },
    WeakForm {
        word: "can",
        canonical: &["K", "AE", "N"],
        reduced: &["K", "AH", "N"],
    },
    WeakForm {
        word: "could",
        canonical: &["K", "UH", "D"],
        reduced: &["K", "AH", "D"],
    },
    WeakForm {
        word: "do",
        canonical: &["D", "UW"],
        reduced: &["D", "AH"],
    },
    WeakForm {
        word: "does",
        canonical: &["D", "AH", "Z"],
        reduced: &["D", "AH", "Z"],
    },
    WeakForm {
        word: "for",
        canonical: &["F", "AO", "R"],
        reduced: &["F", "ER"],
    },
    WeakForm {
        word: "from",
        canonical: &["F", "R", "AH", "M"],
        reduced: &["F", "R", "AH", "M"],
    },
    WeakForm {
        word: "had",
        canonical: &["HH", "AE", "D"],
        reduced: &["AH", "D"],
    },
    WeakForm {
        word: "has",
        canonical: &["HH", "AE", "Z"],
        reduced: &["AH", "Z"],
    },
    WeakForm {
        word: "have",
        canonical: &["HH", "AE", "V"],
        reduced: &["AH", "V"],
    },
    WeakForm {
        word: "he",
        canonical: &["HH", "IY"],
        reduced: &["IY"],
    },
    WeakForm {
        word: "her",
        canonical: &["HH", "ER"],
        reduced: &["ER"],
    },
    WeakForm {
        word: "him",
        canonical: &["HH", "IH", "M"],
        reduced: &["IH", "M"],
    },
    WeakForm {
        word: "his",
        canonical: &["HH", "IH", "Z"],
        reduced: &["IH", "Z"],
    },
    WeakForm {
        word: "is",
        canonical: &["IH", "Z"],
        reduced: &["Z"],
    },
    WeakForm {
        word: "it",
        canonical: &["IH", "T"],
        reduced: &["AH", "T"],
    },
    WeakForm {
        word: "just",
        canonical: &["JH", "AH", "S", "T"],
        reduced: &["JH", "AH", "S"],
    },
    WeakForm {
        word: "me",
        canonical: &["M", "IY"],
        reduced: &["M", "IY"],
    },
    WeakForm {
        word: "must",
        canonical: &["M", "AH", "S", "T"],
        reduced: &["M", "AH", "S"],
    },
    WeakForm {
        word: "my",
        canonical: &["M", "AY"],
        reduced: &["M", "AH"],
    },
    WeakForm {
        word: "of",
        canonical: &["AH", "V"],
        reduced: &["AH"],
    },
    WeakForm {
        word: "or",
        canonical: &["AO", "R"],
        reduced: &["ER"],
    },
    WeakForm {
        word: "our",
        canonical: &["AW", "ER"],
        reduced: &["ER"],
    },
    WeakForm {
        word: "shall",
        canonical: &["SH", "AE", "L"],
        reduced: &["SH", "AH", "L"],
    },
    WeakForm {
        word: "she",
        canonical: &["SH", "IY"],
        reduced: &["SH", "IY"],
    },
    WeakForm {
        word: "should",
        canonical: &["SH", "UH", "D"],
        reduced: &["SH", "AH", "D"],
    },
    WeakForm {
        word: "some",
        canonical: &["S", "AH", "M"],
        reduced: &["S", "AH", "M"],
    },
    WeakForm {
        word: "than",
        canonical: &["DH", "AE", "N"],
        reduced: &["DH", "AH", "N"],
    },
    WeakForm {
        word: "that",
        canonical: &["DH", "AE", "T"],
        reduced: &["DH", "AH", "T"],
    },
    WeakForm {
        word: "the",
        canonical: &["DH", "IY"],
        reduced: &["DH", "AH"],
    },
    WeakForm {
        word: "them",
        canonical: &["DH", "EH", "M"],
        reduced: &["AH", "M"],
    },
    WeakForm {
        word: "there",
        canonical: &["DH", "EH", "R"],
        reduced: &["DH", "ER"],
    },
    WeakForm {
        word: "to",
        canonical: &["T", "UW"],
        reduced: &["T", "AH"],
    },
    WeakForm {
        word: "us",
        canonical: &["AH", "S"],
        reduced: &["AH", "S"],
    },
    WeakForm {
        word: "was",
        canonical: &["W", "AA", "Z"],
        reduced: &["W", "AH", "Z"],
    },
    WeakForm {
        word: "we",
        canonical: &["W", "IY"],
        reduced: &["W", "IY"],
    },
    WeakForm {
        word: "were",
        canonical: &["W", "ER"],
        reduced: &["W", "ER"],
    },
    WeakForm {
        word: "will",
        canonical: &["W", "IH", "L"],
        reduced: &["W", "AH", "L"],
    },
    WeakForm {
        word: "would",
        canonical: &["W", "UH", "D"],
        reduced: &["W", "AH", "D"],
    },
    WeakForm {
        word: "you",
        canonical: &["Y", "UW"],
        reduced: &["Y", "AH"],
    },
    WeakForm {
        word: "your",
        canonical: &["Y", "AO", "R"],
        reduced: &["Y", "ER"],
    },
    WeakForm {
        word: "because",
        canonical: &["B", "IH", "K", "AO", "Z"],
        reduced: &["K", "AH", "Z"],
    },
];

struct PhraseRule {
    id: &'static str,
    first: &'static str,
    second: &'static str,
    family: ConnectedSpeechFamily,
    label: &'static str,
    hint: &'static str,
    canonical: &'static [&'static str],
    reduced: &'static [&'static str],
    confidence: f32,
}

const PHRASE_RULES: &[PhraseRule] = &[
    PhraseRule {
        id: "weak-could-have",
        first: "could",
        second: "have",
        family: ConnectedSpeechFamily::Contraction,
        label: "default connected form",
        hint: "could have often reduces toward could've in connected speech.",
        canonical: &["K", "UH", "D", "HH", "AE", "V"],
        reduced: &["K", "UH", "D", "AH", "V"],
        confidence: 0.82,
    },
    PhraseRule {
        id: "weak-would-have",
        first: "would",
        second: "have",
        family: ConnectedSpeechFamily::Contraction,
        label: "default connected form",
        hint: "would have often reduces toward would've in connected speech.",
        canonical: &["W", "UH", "D", "HH", "AE", "V"],
        reduced: &["W", "UH", "D", "AH", "V"],
        confidence: 0.82,
    },
    PhraseRule {
        id: "weak-should-have",
        first: "should",
        second: "have",
        family: ConnectedSpeechFamily::Contraction,
        label: "default connected form",
        hint: "should have often reduces toward should've in connected speech.",
        canonical: &["SH", "UH", "D", "HH", "AE", "V"],
        reduced: &["SH", "UH", "D", "AH", "V"],
        confidence: 0.82,
    },
    PhraseRule {
        id: "informal-want-to",
        first: "want",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "default connected form",
        hint: "want to may reduce in informal connected speech.",
        canonical: &["W", "AA", "N", "T", "T", "UW"],
        reduced: &["W", "AA", "N", "AH"],
        confidence: 0.78,
    },
    PhraseRule {
        id: "informal-going-to",
        first: "going",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "default connected form",
        hint: "going to may reduce in informal connected speech.",
        canonical: &["G", "OW", "IH", "NG", "T", "UW"],
        reduced: &["G", "AH", "N", "AH"],
        confidence: 0.78,
    },
    PhraseRule {
        id: "assimilation-did-you",
        first: "did",
        second: "you",
        family: ConnectedSpeechFamily::Assimilation,
        label: "default assimilation",
        hint: "did you may assimilate at the /d/ + /y/ boundary.",
        canonical: &["D", "IH", "D", "Y", "UW"],
        reduced: &["D", "IH", "D", "ZH", "UW"],
        confidence: 0.75,
    },
];

#[derive(Debug, Clone)]
struct RuleWord {
    token_index: u32,
    text: String,
    normalized: String,
}

pub fn rule_source() -> &'static str {
    RULE_SOURCE
}

pub fn is_default_rule_explanation(value: &ConnectedSpeechExplanation) -> bool {
    value.evidence.contains("default_connected_rule:")
}

pub fn predict_default_connected(sentence: &SubtitleSentence) -> Vec<ConnectedSpeechExplanation> {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .map(|token| RuleWord {
            token_index: token.index,
            text: token.text.clone(),
            normalized: crate::normalize_word(&token.text),
        })
        .collect::<Vec<_>>();
    let mut values = Vec::new();
    let mut phrase_tokens = HashSet::new();

    for pair in words.windows(2) {
        let first = &pair[0];
        let second = &pair[1];
        if let Some(rule) = PHRASE_RULES
            .iter()
            .find(|rule| rule.first == first.normalized && rule.second == second.normalized)
        {
            phrase_tokens.insert(first.token_index);
            phrase_tokens.insert(second.token_index);
            values.push(explanation(
                rule.family,
                rule.label,
                rule.hint,
                first.token_index,
                second.token_index,
                rule.confidence,
                rule.canonical,
                rule.reduced,
                &format!(
                    "{} {} -> {}",
                    first.text,
                    second.text,
                    rule.reduced.join(" ")
                ),
                rule.id,
            ));
        }
    }

    for (index, word) in words.iter().enumerate() {
        if !phrase_tokens.contains(&word.token_index)
            && index + 1 < words.len()
            && let Some(form) = WEAK_FORMS.iter().find(|form| form.word == word.normalized)
        {
            values.push(explanation(
                ConnectedSpeechFamily::WeakForm,
                "default weak form",
                "This function word often has a lighter connected-speech form.",
                word.token_index,
                word.token_index,
                0.68,
                form.canonical,
                form.reduced,
                &format!("{} -> {}", word.text, form.reduced.join(" ")),
                &format!("weak-{}", form.word),
            ));
        }

        let Some(next) = words.get(index + 1) else {
            continue;
        };
        if phrase_tokens.contains(&word.token_index) || phrase_tokens.contains(&next.token_index) {
            continue;
        }
        if crate::ends_consonant(&word.normalized) && crate::starts_vowel(&next.normalized) {
            values.push(explanation(
                ConnectedSpeechFamily::Linking,
                "default linking",
                "A final consonant can link smoothly into the following vowel.",
                word.token_index,
                next.token_index,
                0.66,
                &[],
                &[],
                &format!("{} + {}", word.text, next.text),
                "link-consonant-vowel",
            ));
        }
        if crate::last_letter(&word.normalized) == crate::first_letter(&next.normalized)
            && crate::last_letter(&word.normalized).is_some()
        {
            values.push(explanation(
                ConnectedSpeechFamily::Linking,
                "default shared consonant",
                "Adjacent matching consonants can be held as one boundary.",
                word.token_index,
                next.token_index,
                0.64,
                &[],
                &[],
                &format!("{} + {}", word.text, next.text),
                "link-same-consonant",
            ));
        }
        if (word.normalized.ends_with('t') || word.normalized.ends_with('d'))
            && crate::ends_consonant(&next.normalized)
        {
            values.push(explanation(
                ConnectedSpeechFamily::Deletion,
                "default t/d weakening",
                "Final /t/ or /d/ may be weakened before another consonant.",
                word.token_index,
                next.token_index,
                0.46,
                &["T", "D"],
                &[],
                &format!("{} + {}", word.text, next.text),
                "possible-t-d-deletion",
            ));
        }
        if crate::medial_flap_candidate(&word.normalized) {
            values.push(explanation(
                ConnectedSpeechFamily::Flapping,
                "default flap",
                "Intervocalic /t/ or /d/ may become an American English flap.",
                word.token_index,
                word.token_index,
                0.58,
                &["T", "D"],
                &["DX"],
                &word.text,
                "american-flap-t-d",
            ));
        }
    }

    values.sort_by_key(|value| {
        (
            value.token_start.unwrap_or(u32::MAX),
            value.token_end.unwrap_or(u32::MAX),
            value.label.clone(),
        )
    });
    values
}

fn explanation(
    family: ConnectedSpeechFamily,
    label: &str,
    hint: &str,
    token_start: u32,
    token_end: u32,
    confidence: f32,
    expected_symbols: &[&str],
    default_symbols: &[&str],
    evidence_detail: &str,
    rule_id: &str,
) -> ConnectedSpeechExplanation {
    ConnectedSpeechExplanation {
        family,
        label: label.into(),
        hint: hint.into(),
        phone_start: None,
        phone_end: None,
        token_start: Some(token_start),
        token_end: Some(token_end),
        confidence,
        status: ConnectedSpeechExplanationStatus::PossibleByRule,
        expected_symbols: expected_symbols.iter().map(ToString::to_string).collect(),
        learning_symbols: default_symbols.iter().map(ToString::to_string).collect(),
        observed_symbols: Vec::new(),
        evidence: format!("{RULE_SOURCE}; default_connected_rule:{rule_id}; {evidence_detail}"),
    }
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
    fn predicts_could_have_as_default_connected_form() {
        let values = predict_default_connected(&sentence("I could have checked the market"));
        let could_have = values
            .iter()
            .find(|value| {
                value.token_start == Some(1)
                    && value.token_end == Some(2)
                    && value.family == ConnectedSpeechFamily::Contraction
            })
            .expect("could have prediction");

        assert_eq!(could_have.learning_symbols, ["K", "UH", "D", "AH", "V"]);
        assert_eq!(
            could_have.status,
            ConnectedSpeechExplanationStatus::PossibleByRule
        );
        assert!(is_default_rule_explanation(could_have));
    }

    #[test]
    fn weak_forms_do_not_duplicate_phrase_rule_tokens() {
        let values = predict_default_connected(&sentence("could have the time"));

        assert_eq!(
            values
                .iter()
                .filter(|value| value.token_start == Some(0) || value.token_start == Some(1))
                .count(),
            1
        );
        assert!(values.iter().any(|value| value.token_start == Some(2)));
    }
}
