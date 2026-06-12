use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::OnceLock;

use domain::{
    LearningResourceId, Phoneme, PronunciationProviderInfo, PronunciationVariant,
    SentencePronunciation, SpeechRuleFinding, SpeechRuleStatus, SubtitleSentence,
    SubtitleTokenKind, TimingSource, WordPronunciation, WordTiming,
};

pub const PROVIDER_ID: &str = "cmudict-deterministic";
pub const PROVIDER_VERSION: &str = "74790861+fallback-v1";
pub const ANALYZER_VERSION: &str = "en-us-rules-v1";
static CMUDICT: OnceLock<HashMap<String, Vec<String>>> = OnceLock::new();

pub fn provider_info() -> PronunciationProviderInfo {
    let cmudict_available = !cmudict().is_empty();
    PronunciationProviderInfo {
        id: PROVIDER_ID.into(),
        display_name: "CMUdict + deterministic fallback".into(),
        version: PROVIDER_VERSION.into(),
        languages: vec!["en".into(), "en-us".into()],
        accents: vec!["en-US".into()],
        phoneme_sets: vec!["arpabet".into()],
        supports_context: false,
        supports_variants: true,
        supports_stress: true,
        supports_token_mapping: true,
        available: true,
        degraded: !cmudict_available,
        diagnostic: (!cmudict_available).then_some(
            "CMUdict is not installed; deterministic fallback pronunciations are in use.".into(),
        ),
    }
}

pub fn lookup(word: &str, token_index: u32) -> WordPronunciation {
    let normalized = normalize_word(word);
    let variants = cmudict()
        .get(&normalized)
        .map(|values| {
            values
                .iter()
                .map(|value| variant(value, token_index, false))
                .collect()
        })
        .or_else(|| {
            builtin(&normalized).map(|values| {
                values
                    .iter()
                    .map(|value| variant(value, token_index, false))
                    .collect()
            })
        })
        .unwrap_or_else(|| vec![variant(&fallback_arpabet(&normalized), token_index, true)]);
    WordPronunciation {
        token_index,
        text: word.into(),
        normalized,
        variants,
    }
}

fn cmudict() -> &'static HashMap<String, Vec<String>> {
    CMUDICT.get_or_init(|| {
        let Some(path) = cmudict_path().filter(|path| path.is_file()) else {
            return HashMap::new();
        };
        let Ok(content) = std::fs::read_to_string(path) else {
            return HashMap::new();
        };
        let mut values: HashMap<String, Vec<String>> = HashMap::new();
        for line in content.lines() {
            if line.starts_with(";;;") || line.trim().is_empty() {
                continue;
            }
            let Some((word, phonemes)) = line.split_once(char::is_whitespace) else {
                continue;
            };
            let word = word
                .split_once('(')
                .map_or(word, |(base, _)| base)
                .to_ascii_lowercase();
            values.entry(word).or_default().push(phonemes.trim().into());
        }
        values
    })
}

fn cmudict_path() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("LLPLAYERNEXT_CMUDICT") {
        return Some(path.into());
    }
    let id = LearningResourceId::from_fingerprint("learning-resource", "cmudict");
    std::env::var_os("HOME").map(|home| {
        PathBuf::from(home)
            .join("Library/Application Support/LLPlayerNext/resources/learning")
            .join(format!("{}.data", id.as_str()))
    })
}

pub fn analyze_sentence(sentence: &SubtitleSentence) -> SentencePronunciation {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .map(|token| lookup(&token.text, token.index))
        .collect::<Vec<_>>();
    let phonemes = words
        .iter()
        .flat_map(|word| {
            word.variants
                .first()
                .into_iter()
                .flat_map(|value| value.phonemes.clone())
        })
        .collect::<Vec<_>>();
    let display_ipa = words
        .iter()
        .filter_map(|word| word.variants.first())
        .map(|value| value.display_ipa.as_str())
        .collect::<Vec<_>>()
        .join(" ");
    SentencePronunciation {
        sentence_id: sentence.id.clone(),
        language: "en".into(),
        accent: "en-US".into(),
        provider_id: PROVIDER_ID.into(),
        provider_version: PROVIDER_VERSION.into(),
        phoneme_set: "arpabet".into(),
        display_ipa,
        words,
        phonemes,
        rules: analyze_rules(sentence),
    }
}

pub fn estimate_word_timings(sentence: &SubtitleSentence) -> Vec<WordTiming> {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .collect::<Vec<_>>();
    if words.is_empty() {
        return vec![];
    }
    let start = sentence.start.get();
    let duration = sentence.end.get().saturating_sub(start);
    let weights = words
        .iter()
        .map(|token| (token.text.chars().count() as u64).clamp(2, 12))
        .collect::<Vec<_>>();
    let total = weights.iter().sum::<u64>().max(1);
    let mut cursor = start;
    words
        .iter()
        .zip(weights)
        .enumerate()
        .map(|(index, (token, weight))| {
            let end = if index + 1 == words.len() {
                sentence.end.get()
            } else {
                cursor + duration.saturating_mul(weight) / total
            };
            let value = WordTiming {
                sentence_id: sentence.id.clone(),
                token_index: token.index,
                text: token.text.clone(),
                start_ms: cursor,
                end_ms: end.max(cursor),
                confidence: Some(0.35),
                timing_source: TimingSource::Estimated,
                provider_id: "subtitle-weighted-estimator".into(),
                provider_version: "v1".into(),
            };
            cursor = end;
            value
        })
        .collect()
}

fn analyze_rules(sentence: &SubtitleSentence) -> Vec<SpeechRuleFinding> {
    let words = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .map(|token| (token.index, normalize_word(&token.text)))
        .collect::<Vec<_>>();
    let mut values = Vec::new();
    for (index, (token_index, word)) in words.iter().enumerate() {
        if matches!(
            word.as_str(),
            "a" | "an" | "and" | "are" | "can" | "for" | "of" | "the" | "to" | "was" | "were"
        ) {
            values.push(rule(
                format!("weak-{word}"),
                "weak_form",
                *token_index,
                *token_index,
                0.72,
                "Function words are often reduced in unstressed connected speech.",
                SpeechRuleStatus::LikelyByContext,
            ));
        }
        let Some((next_index, next)) = words.get(index + 1) else {
            continue;
        };
        if (word == "want" || word == "going") && next == "to" {
            values.push(rule(
                format!("informal-{word}-to"),
                "contraction",
                *token_index,
                *next_index,
                0.78,
                "This common phrase may use an informal reduced pronunciation.",
                SpeechRuleStatus::LikelyByContext,
            ));
        }
        if word == "did" && next == "you" {
            values.push(rule(
                "assimilation-did-you".into(),
                "assimilation",
                *token_index,
                *next_index,
                0.75,
                "/d/ followed by /j/ may assimilate in casual speech.",
                SpeechRuleStatus::LikelyByContext,
            ));
        }
        if ends_consonant(word) && starts_vowel(next) {
            values.push(rule(
                "link-consonant-vowel".into(),
                "linking",
                *token_index,
                *next_index,
                0.68,
                "A final consonant may link smoothly into the following vowel.",
                SpeechRuleStatus::PossibleByRule,
            ));
        }
        if last_letter(word) == first_letter(next) && last_letter(word).is_some() {
            values.push(rule(
                "link-same-consonant".into(),
                "linking",
                *token_index,
                *next_index,
                0.66,
                "Adjacent matching consonants may be held as one longer boundary.",
                SpeechRuleStatus::PossibleByRule,
            ));
        }
        if word.ends_with('t') || word.ends_with('d') {
            values.push(rule(
                "possible-t-d-deletion".into(),
                "deletion",
                *token_index,
                *next_index,
                0.42,
                "Final /t/ or /d/ may be weakened or omitted before another consonant.",
                SpeechRuleStatus::PossibleByRule,
            ));
        }
        if medial_flap_candidate(word) {
            values.push(rule(
                "american-flap-t-d".into(),
                "flapping",
                *token_index,
                *token_index,
                0.58,
                "Intervocalic /t/ or /d/ may be realized as an American English flap.",
                SpeechRuleStatus::PossibleByRule,
            ));
        }
    }
    values
}

fn rule(
    rule_id: String,
    family: &str,
    start: u32,
    end: u32,
    confidence: f32,
    reason: &str,
    status: SpeechRuleStatus,
) -> SpeechRuleFinding {
    SpeechRuleFinding {
        rule_id,
        rule_family: family.into(),
        affected_token_start: start,
        affected_token_end: end,
        canonical_phonemes: vec![],
        suggested_phonemes: vec![],
        confidence,
        reason: reason.into(),
        evidence_source: "deterministic_text_rule".into(),
        status,
    }
}

fn variant(value: &str, token_index: u32, fallback: bool) -> PronunciationVariant {
    let phonemes = value
        .split_whitespace()
        .enumerate()
        .map(|(index, raw)| {
            let (symbol, stress) = split_stress(raw);
            Phoneme {
                symbol: symbol.clone(),
                phoneme_set: "arpabet".into(),
                display_ipa: arpabet_ipa(&symbol).into(),
                stress,
                syllable_index: Some(index as u32),
                token_index: Some(token_index),
                start_ms: None,
                end_ms: None,
                confidence: (!fallback).then_some(1.0),
            }
        })
        .collect::<Vec<_>>();
    PronunciationVariant {
        phonemes: phonemes.clone(),
        display_ipa: phonemes
            .iter()
            .map(|value| value.display_ipa.as_str())
            .collect::<String>(),
        is_fallback: fallback,
    }
}

fn normalize_word(word: &str) -> String {
    word.trim_matches(|c: char| !c.is_ascii_alphanumeric() && c != '\'')
        .to_ascii_lowercase()
}

fn builtin(word: &str) -> Option<&'static [&'static str]> {
    match word {
        "a" => Some(&["AH0", "EY1"]),
        "and" => Some(&["AH0 N D", "AE1 N D"]),
        "can" => Some(&["K AH0 N", "K AE1 N"]),
        "did" => Some(&["D IH1 D"]),
        "going" => Some(&["G OW1 IH0 NG"]),
        "hello" => Some(&["HH AH0 L OW1"]),
        "player" => Some(&["P L EY1 ER0"]),
        "the" => Some(&["DH AH0", "DH IY0"]),
        "to" => Some(&["T AH0", "T UW1"]),
        "want" => Some(&["W AA1 N T"]),
        "world" => Some(&["W ER1 L D"]),
        "you" => Some(&["Y UW1"]),
        _ => None,
    }
}

fn fallback_arpabet(word: &str) -> String {
    word.chars()
        .filter_map(|value| match value {
            'a' => Some("AE1"),
            'e' => Some("EH1"),
            'i' => Some("IH1"),
            'o' => Some("OW1"),
            'u' => Some("AH1"),
            'b' => Some("B"),
            'c' | 'k' | 'q' => Some("K"),
            'd' => Some("D"),
            'f' => Some("F"),
            'g' => Some("G"),
            'h' => Some("HH"),
            'j' => Some("JH"),
            'l' => Some("L"),
            'm' => Some("M"),
            'n' => Some("N"),
            'p' => Some("P"),
            'r' => Some("R"),
            's' | 'x' | 'z' => Some("S"),
            't' => Some("T"),
            'v' => Some("V"),
            'w' => Some("W"),
            'y' => Some("Y"),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn split_stress(value: &str) -> (String, Option<u8>) {
    let bytes = value.as_bytes();
    match bytes.last().copied() {
        Some(stress @ b'0'..=b'2') => (value_without_last(value, 1), Some(stress - b'0')),
        _ => (value.into(), None),
    }
}

fn value_without_last(value: &str, count: usize) -> String {
    value[..value.len().saturating_sub(count)].into()
}

fn arpabet_ipa(value: &str) -> &'static str {
    match value {
        "AA" => "ɑ",
        "AE" => "æ",
        "AH" => "ə",
        "AO" => "ɔ",
        "AW" => "aʊ",
        "AY" => "aɪ",
        "B" => "b",
        "CH" => "tʃ",
        "D" => "d",
        "DH" => "ð",
        "EH" => "ɛ",
        "ER" => "ɝ",
        "EY" => "eɪ",
        "F" => "f",
        "G" => "ɡ",
        "HH" => "h",
        "IH" => "ɪ",
        "IY" => "i",
        "JH" => "dʒ",
        "K" => "k",
        "L" => "l",
        "M" => "m",
        "N" => "n",
        "NG" => "ŋ",
        "OW" => "oʊ",
        "OY" => "ɔɪ",
        "P" => "p",
        "R" => "ɹ",
        "S" => "s",
        "SH" => "ʃ",
        "T" => "t",
        "TH" => "θ",
        "UH" => "ʊ",
        "UW" => "u",
        "V" => "v",
        "W" => "w",
        "Y" => "j",
        "Z" => "z",
        "ZH" => "ʒ",
        _ => "?",
    }
}

fn starts_vowel(value: &str) -> bool {
    first_letter(value).is_some_and(|value| "aeiou".contains(value))
}

fn ends_consonant(value: &str) -> bool {
    last_letter(value).is_some_and(|value| !"aeiou".contains(value))
}

fn first_letter(value: &str) -> Option<char> {
    value.chars().find(|value| value.is_ascii_alphabetic())
}

fn last_letter(value: &str) -> Option<char> {
    value
        .chars()
        .rev()
        .find(|value| value.is_ascii_alphabetic())
}

fn medial_flap_candidate(value: &str) -> bool {
    let chars = value.chars().collect::<Vec<_>>();
    chars.windows(3).any(|value| {
        "aeiou".contains(value[0]) && matches!(value[1], 't' | 'd') && "aeiou".contains(value[2])
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{SubtitleSentenceId, SubtitleToken, TimeMs};

    fn sentence(text: &str) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("s").unwrap(),
            index: 0,
            start: TimeMs::new(100),
            end: TimeMs::new(1100),
            original_text: text.into(),
            display_text: text.into(),
            tokens: subtitle_core_for_test(text),
        }
    }

    fn subtitle_core_for_test(text: &str) -> Vec<SubtitleToken> {
        text.split_whitespace()
            .enumerate()
            .map(|(index, text)| SubtitleToken {
                index: index as u32,
                kind: SubtitleTokenKind::Word,
                text: text.into(),
                normalized: Some(normalize_word(text)),
                start_char: 0,
                end_char: text.len() as u32,
            })
            .collect()
    }

    #[test]
    fn maps_stress_and_ipa() {
        let hello = lookup("hello", 3);
        assert_eq!(hello.variants[0].phonemes[1].stress, Some(0));
        assert!(hello.variants[0].display_ipa.contains("oʊ"));
    }

    #[test]
    fn fallback_is_explicit() {
        assert!(lookup("codex", 0).variants[0].is_fallback);
    }

    #[test]
    fn estimates_monotonic_bounded_timings() {
        let sentence = sentence("a much longer word");
        let values = estimate_word_timings(&sentence);
        assert_eq!(values.first().unwrap().start_ms, 100);
        assert_eq!(values.last().unwrap().end_ms, 1100);
        assert!(
            values
                .windows(2)
                .all(|pair| pair[0].end_ms <= pair[1].start_ms)
        );
    }

    #[test]
    fn rule_hints_are_never_audio_detection() {
        let values = analyze_rules(&sentence("did you want to go"));
        assert!(
            values
                .iter()
                .any(|value| value.rule_id == "assimilation-did-you")
        );
        assert!(
            values
                .iter()
                .all(|value| value.evidence_source == "deterministic_text_rule")
        );
    }
}
