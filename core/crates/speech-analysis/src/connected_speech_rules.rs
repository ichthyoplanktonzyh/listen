use std::collections::HashSet;

use domain::{
    ConnectedSpeechExplanation, ConnectedSpeechExplanationStatus, ConnectedSpeechFamily,
    SubtitleSentence, SubtitleTokenKind,
};

mod context;
use context::{has_punctuation_boundary, phrase_context_allows, weak_form_context_allows};

const RULE_SOURCE: &str = "english_connected_speech_rules_v3";

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
    context: PhraseContext,
}

#[derive(Debug, Clone, Copy)]
enum PhraseContext {
    Always,
    FollowedByLikelyVerb,
    GoingToInfinitive,
    WantToInfinitive,
    UsedToInfinitive,
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
        context: PhraseContext::Always,
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
        context: PhraseContext::Always,
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
        context: PhraseContext::Always,
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
        context: PhraseContext::WantToInfinitive,
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
        context: PhraseContext::GoingToInfinitive,
    },
    PhraseRule {
        id: "informal-got-to",
        first: "got",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible gotta form",
        hint: "Have got to may reduce toward gotta before a verb in informal speech.",
        canonical: &["G", "AA", "T", "T", "UW"],
        reduced: &["G", "AA", "DX", "AH"],
        confidence: 0.72,
        context: PhraseContext::FollowedByLikelyVerb,
    },
    PhraseRule {
        id: "obligation-have-to",
        first: "have",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible hafta form",
        hint: "Obligation have to often has /f/ plus a weak to in connected speech.",
        canonical: &["HH", "AE", "V", "T", "UW"],
        reduced: &["HH", "AE", "F", "T", "AH"],
        confidence: 0.76,
        context: PhraseContext::FollowedByLikelyVerb,
    },
    PhraseRule {
        id: "obligation-has-to",
        first: "has",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible hasta form",
        hint: "Obligation has to often has /s/ plus a weak to in connected speech.",
        canonical: &["HH", "AE", "Z", "T", "UW"],
        reduced: &["HH", "AE", "S", "T", "AH"],
        confidence: 0.74,
        context: PhraseContext::FollowedByLikelyVerb,
    },
    PhraseRule {
        id: "obligation-had-to",
        first: "had",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "connected had-to form",
        hint: "Had to commonly keeps the /d/ while to takes its weak vowel.",
        canonical: &["HH", "AE", "D", "T", "UW"],
        reduced: &["HH", "AE", "D", "T", "AH"],
        confidence: 0.7,
        context: PhraseContext::FollowedByLikelyVerb,
    },
    PhraseRule {
        id: "habitual-used-to",
        first: "used",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "habitual used-to form",
        hint: "Habitual used to uses /st/ plus a weak to; adjectival be used to is different.",
        canonical: &["Y", "UW", "Z", "D", "T", "UW"],
        reduced: &["Y", "UW", "S", "T", "AH"],
        confidence: 0.78,
        context: PhraseContext::UsedToInfinitive,
    },
    PhraseRule {
        id: "supposed-to",
        first: "supposed",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "connected supposed-to form",
        hint: "Supposed to commonly simplifies its boundary cluster before weak to.",
        canonical: &["S", "AH", "P", "OW", "Z", "D", "T", "UW"],
        reduced: &["S", "AH", "P", "OW", "S", "T", "AH"],
        confidence: 0.7,
        context: PhraseContext::FollowedByLikelyVerb,
    },
    PhraseRule {
        id: "ought-to",
        first: "ought",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "connected ought-to form",
        hint: "The matching /t/ boundary may be held once before weak to.",
        canonical: &["AO", "T", "T", "UW"],
        reduced: &["AO", "T", "AH"],
        confidence: 0.7,
        context: PhraseContext::FollowedByLikelyVerb,
    },
    PhraseRule {
        id: "trying-to",
        first: "trying",
        second: "to",
        family: ConnectedSpeechFamily::Contraction,
        label: "connected trying-to form",
        hint: "Trying to commonly carries a weak to; stronger tryna reduction remains audio-dependent.",
        canonical: &["T", "R", "AY", "IH", "NG", "T", "UW"],
        reduced: &["T", "R", "AY", "IH", "NG", "T", "AH"],
        confidence: 0.65,
        context: PhraseContext::FollowedByLikelyVerb,
    },
    PhraseRule {
        id: "informal-let-me",
        first: "let",
        second: "me",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible lemme form",
        hint: "Let me may reduce toward lemme in informal connected speech.",
        canonical: &["L", "EH", "T", "M", "IY"],
        reduced: &["L", "EH", "M", "IY"],
        confidence: 0.7,
        context: PhraseContext::Always,
    },
    PhraseRule {
        id: "informal-give-me",
        first: "give",
        second: "me",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible gimme form",
        hint: "Give me may reduce toward gimme in informal connected speech.",
        canonical: &["G", "IH", "V", "M", "IY"],
        reduced: &["G", "IH", "M", "IY"],
        confidence: 0.68,
        context: PhraseContext::Always,
    },
    PhraseRule {
        id: "informal-kind-of",
        first: "kind",
        second: "of",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible kinda form",
        hint: "Kind of may lose the final /v/ of of in informal connected speech.",
        canonical: &["K", "AY", "N", "D", "AH", "V"],
        reduced: &["K", "AY", "N", "D", "AH"],
        confidence: 0.66,
        context: PhraseContext::Always,
    },
    PhraseRule {
        id: "informal-sort-of",
        first: "sort",
        second: "of",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible sorta form",
        hint: "Sort of may lose the final /v/ of of in informal connected speech.",
        canonical: &["S", "AO", "R", "T", "AH", "V"],
        reduced: &["S", "AO", "R", "T", "AH"],
        confidence: 0.66,
        context: PhraseContext::Always,
    },
    PhraseRule {
        id: "informal-out-of",
        first: "out",
        second: "of",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible outta form",
        hint: "Out of may flap /t/ and lose /v/ in informal American speech.",
        canonical: &["AW", "T", "AH", "V"],
        reduced: &["AW", "DX", "AH"],
        confidence: 0.66,
        context: PhraseContext::Always,
    },
    PhraseRule {
        id: "informal-lot-of",
        first: "lot",
        second: "of",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible lotta form",
        hint: "Lot of may flap /t/ and lose /v/ in informal American speech.",
        canonical: &["L", "AA", "T", "AH", "V"],
        reduced: &["L", "AA", "DX", "AH"],
        confidence: 0.64,
        context: PhraseContext::Always,
    },
    PhraseRule {
        id: "informal-lots-of",
        first: "lots",
        second: "of",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible lotsa form",
        hint: "Lots of may lose the final /v/ of of in informal connected speech.",
        canonical: &["L", "AA", "T", "S", "AH", "V"],
        reduced: &["L", "AA", "T", "S", "AH"],
        confidence: 0.66,
        context: PhraseContext::Always,
    },
    PhraseRule {
        id: "informal-dont-know",
        first: "don't",
        second: "know",
        family: ConnectedSpeechFamily::Contraction,
        label: "possible dunno form",
        hint: "Don't know may reduce toward dunno in informal connected speech.",
        canonical: &["D", "OW", "N", "T", "N", "OW"],
        reduced: &["D", "AH", "N", "OW"],
        confidence: 0.6,
        context: PhraseContext::Always,
    },
];

#[derive(Debug, Clone)]
struct RuleWord {
    token_index: u32,
    text: String,
    normalized: String,
    symbols: Vec<String>,
    stressed_symbols: Vec<String>,
    is_fallback_pronunciation: bool,
}

impl RuleWord {
    fn last_phone(&self) -> Option<&str> {
        self.symbols.last().map(String::as_str)
    }

    fn first_phone(&self) -> Option<&str> {
        self.symbols.first().map(String::as_str)
    }

    fn preferred_symbols(&self, preferred: &[&str]) -> Vec<String> {
        let (symbols, fallback) =
            crate::pronunciation_symbols(&self.text, self.token_index, Some(preferred));
        if fallback {
            crate::normalize_arpabet_symbols(preferred)
        } else {
            symbols
        }
    }

    fn penultimate_phone(&self) -> Option<&str> {
        self.symbols
            .len()
            .checked_sub(2)
            .and_then(|index| self.symbols.get(index))
            .map(String::as_str)
    }
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
        .map(|token| {
            let (symbols, is_fallback_pronunciation) =
                crate::pronunciation_symbols(&token.text, token.index, None);
            let pronunciation = crate::lookup(&token.text, token.index);
            let stressed_symbols = pronunciation
                .variants
                .iter()
                .find(|variant| !variant.is_fallback)
                .or_else(|| pronunciation.variants.first())
                .map(|variant| {
                    variant
                        .phonemes
                        .iter()
                        .map(|phone| match phone.stress {
                            Some(stress) => format!("{}{}", phone.symbol, stress),
                            None => phone.symbol.clone(),
                        })
                        .collect()
                })
                .unwrap_or_default();
            RuleWord {
                token_index: token.index,
                text: token.text.clone(),
                normalized: crate::normalize_word(&token.text),
                symbols,
                stressed_symbols,
                is_fallback_pronunciation,
            }
        })
        .collect::<Vec<_>>();
    let mut values = Vec::new();
    let mut phrase_tokens = HashSet::new();

    for (pair_index, pair) in words.windows(2).enumerate() {
        let first = &pair[0];
        let second = &pair[1];
        if has_punctuation_boundary(sentence, first.token_index, second.token_index) {
            continue;
        }
        if let Some(rule) = PHRASE_RULES
            .iter()
            .find(|rule| rule.first == first.normalized && rule.second == second.normalized)
            .filter(|rule| phrase_context_allows(rule.context, &words, pair_index, sentence))
        {
            phrase_tokens.insert(first.token_index);
            phrase_tokens.insert(second.token_index);
            let expected_symbols = phrase_expected_symbols(first, second, rule);
            let default_symbols = crate::normalize_arpabet_symbols(rule.reduced);
            if same_symbols(&expected_symbols, &default_symbols) {
                continue;
            }
            values.push(explanation(
                rule.family,
                rule.label,
                rule.hint,
                first.token_index,
                second.token_index,
                rule.confidence,
                expected_symbols,
                default_symbols,
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
            && weak_form_context_allows(&words, index, sentence)
            && let Some(form) = WEAK_FORMS.iter().find(|form| form.word == word.normalized)
        {
            let expected_symbols = word.preferred_symbols(form.canonical);
            let default_symbols = crate::normalize_arpabet_symbols(form.reduced);
            if same_symbols(&expected_symbols, &default_symbols) {
                continue;
            }
            values.push(explanation(
                ConnectedSpeechFamily::WeakForm,
                "default weak form",
                "This function word often has a lighter connected-speech form.",
                word.token_index,
                word.token_index,
                0.68,
                expected_symbols,
                default_symbols,
                &format!("{} -> {}", word.text, form.reduced.join(" ")),
                &format!("weak-{}", form.word),
            ));
        }

        let Some(next) = words.get(index + 1) else {
            continue;
        };
        if has_punctuation_boundary(sentence, word.token_index, next.token_index) {
            continue;
        }
        if phrase_tokens.contains(&word.token_index) || phrase_tokens.contains(&next.token_index) {
            continue;
        }
        let last_phone = word.last_phone();
        let next_first_phone = next.first_phone();
        if last_phone.is_some_and(crate::arpabet_is_consonant)
            && next_first_phone.is_some_and(crate::arpabet_is_vowel)
        {
            values.push(explanation(
                ConnectedSpeechFamily::Linking,
                "default linking",
                "A final consonant can link smoothly into the following vowel.",
                word.token_index,
                next.token_index,
                0.66,
                Vec::new(),
                Vec::new(),
                &format!("{} + {}", word.text, next.text),
                "link-consonant-vowel",
            ));
        }
        if let Some((replacement, rule_id, hint)) = last_phone
            .zip(next_first_phone)
            .and_then(|(last, first)| coalescent_yod(last, first))
        {
            let mut expected_symbols = word.symbols.clone();
            expected_symbols.extend(next.symbols.clone());
            let mut predicted_symbols = word.symbols.clone();
            predicted_symbols.pop();
            predicted_symbols.push(replacement.into());
            predicted_symbols.extend(next.symbols.iter().skip(1).cloned());
            values.push(explanation(
                ConnectedSpeechFamily::Assimilation,
                "default yod coalescence",
                hint,
                word.token_index,
                next.token_index,
                0.72,
                expected_symbols,
                predicted_symbols,
                &format!("{} + {}", word.text, next.text),
                rule_id,
            ));
        }
        if let Some((replacement, rule_id, hint)) = last_phone
            .zip(next_first_phone)
            .and_then(|(last, first)| nasal_place_assimilation(last, first))
        {
            let mut expected_symbols = word.symbols.clone();
            expected_symbols.extend(next.symbols.clone());
            let mut predicted_symbols = word.symbols.clone();
            predicted_symbols.pop();
            predicted_symbols.push(replacement.into());
            predicted_symbols.extend(next.symbols.clone());
            values.push(explanation(
                ConnectedSpeechFamily::Assimilation,
                "possible place assimilation",
                hint,
                word.token_index,
                next.token_index,
                0.56,
                expected_symbols,
                predicted_symbols,
                &format!("{} + {}", word.text, next.text),
                rule_id,
            ));
        }
        if let Some((glide, rule_id)) = last_phone
            .zip(next_first_phone)
            .and_then(|(last, first)| vowel_linking_glide(last, first))
        {
            let mut expected_symbols = word.symbols.clone();
            expected_symbols.extend(next.symbols.clone());
            let mut predicted_symbols = word.symbols.clone();
            predicted_symbols.push(glide.into());
            predicted_symbols.extend(next.symbols.clone());
            values.push(explanation(
                ConnectedSpeechFamily::Linking,
                "possible vowel linking glide",
                "A short glide can bridge adjacent vowels in connected speech.",
                word.token_index,
                next.token_index,
                0.54,
                expected_symbols,
                predicted_symbols,
                &format!("{} + {}", word.text, next.text),
                rule_id,
            ));
        }
        if last_phone
            .zip(next_first_phone)
            .is_some_and(|(last, first)| {
                last == first
                    && crate::arpabet_is_consonant(last)
                    && crate::arpabet_is_consonant(first)
            })
        {
            values.push(explanation(
                ConnectedSpeechFamily::Linking,
                "default shared consonant",
                "Adjacent matching consonants can be held as one boundary.",
                word.token_index,
                next.token_index,
                0.64,
                Vec::new(),
                Vec::new(),
                &format!("{} + {}", word.text, next.text),
                "link-same-consonant",
            ));
        }
        if last_phone.is_some_and(|phone| matches!(phone, "T" | "D"))
            && word
                .penultimate_phone()
                .is_some_and(crate::arpabet_is_consonant)
            && next_first_phone.is_some_and(crate::arpabet_is_consonant)
        {
            values.push(explanation(
                ConnectedSpeechFamily::Deletion,
                "default t/d weakening",
                "Final /t/ or /d/ may be weakened before another consonant.",
                word.token_index,
                next.token_index,
                0.46,
                last_phone
                    .map(|phone| vec![phone.to_string()])
                    .unwrap_or_default(),
                Vec::new(),
                &format!("{} + {}", word.text, next.text),
                "possible-t-d-deletion",
            ));
        }
        if !word.is_fallback_pronunciation && has_stress_conditioned_flap(&word.stressed_symbols) {
            values.push(explanation(
                ConnectedSpeechFamily::Flapping,
                "default flap",
                "Intervocalic /t/ or /d/ may become an American English flap.",
                word.token_index,
                word.token_index,
                0.58,
                vec!["T".into(), "D".into()],
                vec!["DX".into()],
                &word.text,
                "american-flap-t-d",
            ));
        }
        if last_phone.is_some_and(|phone| matches!(phone, "T" | "D"))
            && word
                .penultimate_phone()
                .is_some_and(crate::arpabet_is_vowel)
            && next_first_phone.is_some_and(crate::arpabet_is_vowel)
            && WEAK_FORMS.iter().any(|form| form.word == next.normalized)
        {
            let mut expected_symbols = word.symbols.clone();
            expected_symbols.extend(next.symbols.clone());
            let mut predicted_symbols = word.symbols.clone();
            if let Some(last) = predicted_symbols.last_mut() {
                *last = "DX".into();
            }
            predicted_symbols.extend(next.symbols.clone());
            values.push(explanation(
                ConnectedSpeechFamily::Flapping,
                "possible cross-word flap",
                "In American English, final /t/ or /d/ can flap before an unstressed vowel-initial function word.",
                word.token_index,
                next.token_index,
                0.62,
                expected_symbols,
                predicted_symbols,
                &format!("{} + {}", word.text, next.text),
                "american-flap-across-word",
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

fn coalescent_yod(last: &str, next: &str) -> Option<(&'static str, &'static str, &'static str)> {
    match (last, next) {
        ("T", "Y") => Some((
            "CH",
            "yod-coalescence-t-y",
            "/t/ + /j/ may coalesce to /tʃ/.",
        )),
        ("D", "Y") => Some((
            "JH",
            "yod-coalescence-d-y",
            "/d/ + /j/ may coalesce to /dʒ/.",
        )),
        ("S", "Y") => Some((
            "SH",
            "yod-coalescence-s-y",
            "/s/ + /j/ may coalesce to /ʃ/.",
        )),
        ("Z", "Y") => Some((
            "ZH",
            "yod-coalescence-z-y",
            "/z/ + /j/ may coalesce to /ʒ/.",
        )),
        _ => None,
    }
}

fn nasal_place_assimilation(
    last: &str,
    next: &str,
) -> Option<(&'static str, &'static str, &'static str)> {
    match (last, next) {
        ("N", "P" | "B" | "M") => Some((
            "M",
            "place-assimilation-n-bilabial",
            "Alveolar /n/ may anticipate a following bilabial consonant and sound like /m/.",
        )),
        ("N", "K" | "G") => Some((
            "NG",
            "place-assimilation-n-velar",
            "Alveolar /n/ may anticipate a following velar consonant and sound like /ng/.",
        )),
        _ => None,
    }
}

fn vowel_linking_glide(last: &str, next: &str) -> Option<(&'static str, &'static str)> {
    if !crate::arpabet_is_vowel(next) {
        return None;
    }
    match last {
        "IY" | "EY" | "AY" | "OY" => Some(("Y", "link-vowel-vowel-y")),
        "UW" | "OW" | "AW" => Some(("W", "link-vowel-vowel-w")),
        _ => None,
    }
}

fn has_stress_conditioned_flap(symbols: &[String]) -> bool {
    symbols.windows(3).any(|phones| {
        vowel_has_stress(&phones[0])
            && matches!(crate::strip_arpabet_stress(&phones[1]).as_str(), "T" | "D")
            && vowel_is_unstressed(&phones[2])
    })
}

fn vowel_has_stress(symbol: &str) -> bool {
    crate::arpabet_is_vowel(symbol) && (symbol.ends_with('1') || symbol.ends_with('2'))
}

fn vowel_is_unstressed(symbol: &str) -> bool {
    crate::arpabet_is_vowel(symbol)
        && (symbol.ends_with('0') || (!symbol.ends_with('1') && !symbol.ends_with('2')))
}

fn phrase_expected_symbols(first: &RuleWord, second: &RuleWord, rule: &PhraseRule) -> Vec<String> {
    if first.is_fallback_pronunciation || second.is_fallback_pronunciation {
        return crate::normalize_arpabet_symbols(rule.canonical);
    }
    let mut symbols = first.symbols.clone();
    symbols.extend(second.symbols.clone());
    if symbols.is_empty() {
        crate::normalize_arpabet_symbols(rule.canonical)
    } else {
        symbols
    }
}

fn same_symbols(left: &[String], right: &[String]) -> bool {
    left == right
}

fn explanation(
    family: ConnectedSpeechFamily,
    label: &str,
    hint: &str,
    token_start: u32,
    token_end: u32,
    confidence: f32,
    expected_symbols: Vec<String>,
    default_symbols: Vec<String>,
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
        expected_symbols,
        learning_symbols: default_symbols,
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

    fn sentence_with_boundary_punctuation(first: &str, second: &str) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("punctuation").unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1000),
            original_text: format!("{first}, {second}"),
            display_text: format!("{first}, {second}"),
            tokens: vec![
                SubtitleToken {
                    index: 0,
                    kind: SubtitleTokenKind::Word,
                    text: first.into(),
                    normalized: Some(crate::normalize_word(first)),
                    start_char: 0,
                    end_char: first.len() as u32,
                },
                SubtitleToken {
                    index: 1,
                    kind: SubtitleTokenKind::Punctuation,
                    text: ",".into(),
                    normalized: None,
                    start_char: first.len() as u32,
                    end_char: first.len() as u32 + 1,
                },
                SubtitleToken {
                    index: 2,
                    kind: SubtitleTokenKind::Word,
                    text: second.into(),
                    normalized: Some(crate::normalize_word(second)),
                    start_char: first.len() as u32 + 2,
                    end_char: (first.len() + second.len() + 2) as u32,
                },
            ],
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

    #[test]
    fn weak_forms_skip_noop_dictionary_forms() {
        let values = predict_default_connected(&sentence("we were ready"));

        assert!(
            !values
                .iter()
                .any(|value| value.evidence.contains("weak-we"))
        );
        assert!(
            !values
                .iter()
                .any(|value| value.evidence.contains("weak-were"))
        );
    }

    #[test]
    fn t_d_weakening_uses_following_initial_phone() {
        let before_vowel = predict_default_connected(&sentence("last apple"));
        assert!(
            !before_vowel
                .iter()
                .any(|value| value.evidence.contains("possible-t-d-deletion"))
        );

        let before_consonant = predict_default_connected(&sentence("last call"));
        assert!(before_consonant.iter().any(|value| {
            value.evidence.contains("possible-t-d-deletion")
                && value.expected_symbols == ["T"]
                && value.token_start == Some(0)
                && value.token_end == Some(1)
        }));
    }

    #[test]
    fn shared_boundary_requires_same_consonant_phone() {
        let vowel_letters = predict_default_connected(&sentence("see each one"));
        assert!(
            !vowel_letters
                .iter()
                .any(|value| value.evidence.contains("link-same-consonant"))
        );

        let consonants = predict_default_connected(&sentence("big game"));
        assert!(
            consonants
                .iter()
                .any(|value| value.evidence.contains("link-same-consonant"))
        );
    }

    #[test]
    fn linking_uses_phone_boundary_not_spelling_only() {
        let consonant_to_vowel = predict_default_connected(&sentence("pick it up"));
        assert!(consonant_to_vowel.iter().any(|value| {
            value.evidence.contains("link-consonant-vowel")
                && value.token_start == Some(0)
                && value.token_end == Some(1)
        }));

        let vowel_to_vowel = predict_default_connected(&sentence("see it"));
        assert!(
            !vowel_to_vowel
                .iter()
                .any(|value| value.evidence.contains("link-consonant-vowel"))
        );
    }

    #[test]
    fn yod_coalescence_is_generic_across_supported_coronals() {
        assert_eq!(coalescent_yod("T", "Y").map(|value| value.0), Some("CH"));
        assert_eq!(coalescent_yod("D", "Y").map(|value| value.0), Some("JH"));
        assert_eq!(coalescent_yod("S", "Y").map(|value| value.0), Some("SH"));
        assert_eq!(coalescent_yod("Z", "Y").map(|value| value.0), Some("ZH"));

        let values = predict_default_connected(&sentence("did you see"));
        let assimilation = values
            .iter()
            .find(|value| value.evidence.contains("yod-coalescence-d-y"))
            .expect("generic did-you coalescence");
        assert_eq!(assimilation.learning_symbols, ["D", "IH", "JH", "UW"]);
    }

    #[test]
    fn nasal_place_assimilation_distinguishes_bilabial_and_velar_targets() {
        assert_eq!(
            nasal_place_assimilation("N", "B").map(|value| value.0),
            Some("M")
        );
        assert_eq!(
            nasal_place_assimilation("N", "K").map(|value| value.0),
            Some("NG")
        );
        assert_eq!(nasal_place_assimilation("N", "S"), None);

        let values = predict_default_connected(&sentence("ten boys"));
        let assimilation = values
            .iter()
            .find(|value| value.evidence.contains("place-assimilation-n-bilabial"))
            .expect("n-to-m place assimilation");
        assert!(
            assimilation
                .learning_symbols
                .windows(2)
                .any(|pair| pair == ["M", "B"])
        );
    }

    #[test]
    fn vowel_hiatus_uses_front_or_back_linking_glide() {
        assert_eq!(
            vowel_linking_glide("IY", "IH"),
            Some(("Y", "link-vowel-vowel-y"))
        );
        assert_eq!(
            vowel_linking_glide("UW", "AE"),
            Some(("W", "link-vowel-vowel-w"))
        );
        assert_eq!(vowel_linking_glide("AH", "IH"), None);

        let values = predict_default_connected(&sentence("see it"));
        let linking = values
            .iter()
            .find(|value| value.evidence.contains("link-vowel-vowel-y"))
            .expect("front-vowel linking glide");
        assert!(
            linking
                .learning_symbols
                .windows(2)
                .any(|pair| pair == ["IY", "Y"])
        );

        let across_punctuation =
            predict_default_connected(&sentence_with_boundary_punctuation("see", "it"));
        assert!(
            !across_punctuation
                .iter()
                .any(|value| value.evidence.contains("link-vowel-vowel-y"))
        );
    }

    #[test]
    fn lexical_flap_requires_stressed_to_unstressed_vowel_context() {
        assert!(has_stress_conditioned_flap(&[
            "W".into(),
            "AO1".into(),
            "T".into(),
            "ER0".into(),
        ]));
        assert!(!has_stress_conditioned_flap(&[
            "AH0".into(),
            "T".into(),
            "AE1".into(),
            "K".into(),
        ]));
    }

    #[test]
    fn t_d_deletion_requires_a_word_final_consonant_cluster() {
        let cluster = predict_default_connected(&sentence("last call"));
        assert!(
            cluster
                .iter()
                .any(|value| value.evidence.contains("possible-t-d-deletion"))
        );

        let singleton = predict_default_connected(&sentence("good call"));
        assert!(
            !singleton
                .iter()
                .any(|value| value.evidence.contains("possible-t-d-deletion"))
        );
    }

    #[test]
    fn construction_reductions_require_a_plausible_infinitive_complement() {
        let future = predict_default_connected(&sentence("we are going to leave"));
        assert!(
            future
                .iter()
                .any(|value| value.evidence.contains("informal-going-to"))
        );

        for literal_motion in [
            "we are going to London",
            "we are going to the store",
            "we are going to work",
        ] {
            let values = predict_default_connected(&sentence(literal_motion));
            assert!(
                !values
                    .iter()
                    .any(|value| value.evidence.contains("informal-going-to")),
                "literal motion must not trigger gonna: {literal_motion}"
            );
        }

        let obligation = predict_default_connected(&sentence("we have to leave"));
        assert!(
            obligation
                .iter()
                .any(|value| value.evidence.contains("obligation-have-to"))
        );
        let incomplete = predict_default_connected(&sentence("we have to"));
        assert!(
            !incomplete
                .iter()
                .any(|value| value.evidence.contains("obligation-have-to"))
        );
    }

    #[test]
    fn wanna_prediction_conservatively_blocks_wh_extraction_ambiguity() {
        let statement = predict_default_connected(&sentence("I want to leave"));
        assert!(
            statement
                .iter()
                .any(|value| value.evidence.contains("informal-want-to"))
        );

        let question = predict_default_connected(&sentence("Who do you want to win"));
        assert!(
            !question
                .iter()
                .any(|value| value.evidence.contains("informal-want-to"))
        );
    }

    #[test]
    fn habitual_used_to_is_distinct_from_adjectival_be_used_to() {
        let habitual = predict_default_connected(&sentence("I used to swim"));
        assert!(
            habitual
                .iter()
                .any(|value| value.evidence.contains("habitual-used-to"))
        );

        let adjectival = predict_default_connected(&sentence("I am used to it"));
        assert!(
            !adjectival
                .iter()
                .any(|value| value.evidence.contains("habitual-used-to"))
        );
    }

    #[test]
    fn common_lexicalized_reductions_emit_complete_a_to_b_symbols() {
        for (text, rule_id, expected) in [
            (
                "you got to leave",
                "informal-got-to",
                &["G", "AA", "DX", "AH"][..],
            ),
            ("let me see", "informal-let-me", &["L", "EH", "M", "IY"]),
            ("give me that", "informal-give-me", &["G", "IH", "M", "IY"]),
            (
                "kind of strange",
                "informal-kind-of",
                &["K", "AY", "N", "D", "AH"],
            ),
            ("out of time", "informal-out-of", &["AW", "DX", "AH"]),
            (
                "lots of time",
                "informal-lots-of",
                &["L", "AA", "T", "S", "AH"],
            ),
            (
                "I don't know",
                "informal-dont-know",
                &["D", "AH", "N", "OW"],
            ),
        ] {
            let values = predict_default_connected(&sentence(text));
            let reduction = values
                .iter()
                .find(|value| value.evidence.contains(rule_id))
                .unwrap_or_else(|| panic!("missing {rule_id} for {text}"));
            assert_eq!(reduction.learning_symbols, expected, "{rule_id}");
        }
    }

    #[test]
    fn weak_forms_respect_punctuation_initial_h_and_the_before_vowel() {
        let punctuated = predict_default_connected(&sentence_with_boundary_punctuation("to", "it"));
        assert!(
            !punctuated
                .iter()
                .any(|value| value.evidence.contains("weak-to"))
        );

        let initial_h = predict_default_connected(&sentence("he can go"));
        assert!(
            !initial_h
                .iter()
                .any(|value| value.evidence.contains("weak-he"))
        );

        let medial_h = predict_default_connected(&sentence("tell him now"));
        assert!(
            medial_h
                .iter()
                .any(|value| value.evidence.contains("weak-him"))
        );

        let the_vowel = predict_default_connected(&sentence("the apple fell"));
        assert!(
            !the_vowel
                .iter()
                .any(|value| value.evidence.contains("weak-the"))
        );
    }
}
