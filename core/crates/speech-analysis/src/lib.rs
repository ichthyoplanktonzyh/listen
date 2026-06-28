pub mod asr_timing;
pub mod chunk_detection;
pub mod chunk_partition;
pub mod forced_align;
pub mod learned_prosodic_provider;
pub mod pause_refinement;
pub mod phone_recognition;
pub mod phonetic_alignment;
pub mod phonetic_findings;
pub mod rich_acoustic_evidence;
pub mod sound_analysis;
pub mod text_chunk_detection;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::OnceLock;

use domain::{
    LearningResourceId, Phoneme, PronunciationProviderInfo, PronunciationVariant,
    SentencePronunciation, SpeechRuleFinding, SpeechRuleStatus, SubtitleSentence,
    SubtitleTokenKind, TimingSource, WordPronunciation, WordTiming,
};
use serde::Serialize;

pub const PROVIDER_ID: &str = "cmudict-deterministic";
pub const PROVIDER_VERSION: &str = "74790861+fallback-v1";
pub const ANALYZER_VERSION: &str = "en-us-rules-v1";
static CMUDICT: OnceLock<HashMap<String, Vec<String>>> = OnceLock::new();

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct RuleDefinition {
    pub rule_id: &'static str,
    pub rule_family: &'static str,
    pub description: &'static str,
    pub condition: &'static str,
    pub example: &'static str,
    pub counterexample: &'static str,
    pub canonical_phonemes: &'static [&'static str],
    pub suggested_phonemes: &'static [&'static str],
}

pub fn rule_catalog() -> &'static [RuleDefinition] {
    static RULES: OnceLock<Vec<RuleDefinition>> = OnceLock::new();
    RULES.get_or_init(|| {
        let mut values = [
            ("a", "A cat", "A-frame"),
            ("an", "An apple", "Annual report"),
            ("and", "You and me", "Android phone"),
            ("are", "We are ready", "Area code"),
            ("can", "I can go", "Candy store"),
            ("for", "For a while", "Forest trail"),
            ("of", "A cup of tea", "Office chair"),
            ("the", "The book", "Theme song"),
            ("to", "Go to school", "Today"),
            ("was", "It was good", "Wasp nest"),
            ("were", "They were here", "Werewolf story"),
        ]
        .into_iter()
        .map(|(word, example, counterexample)| RuleDefinition {
            rule_id: Box::leak(format!("weak-{word}").into_boxed_str()),
            rule_family: "weak_form",
            description: "A function word may use its unstressed weak form.",
            condition: "The complete lexical token is a common function word.",
            example,
            counterexample,
            canonical_phonemes: &[],
            suggested_phonemes: &[],
        })
        .collect::<Vec<_>>();
        values.extend([
            RuleDefinition {
                rule_id: "informal-want-to",
                rule_family: "contraction",
                description: "Want to may reduce in informal speech.",
                condition: "The adjacent lexical tokens are want + to.",
                example: "I want to go",
                counterexample: "I want tea",
                canonical_phonemes: &["W AA N T", "T UW"],
                suggested_phonemes: &["W AA N AH"],
            },
            RuleDefinition {
                rule_id: "informal-going-to",
                rule_family: "contraction",
                description: "Going to may reduce in informal speech.",
                condition: "The adjacent lexical tokens are going + to.",
                example: "We are going to leave",
                counterexample: "We are going home",
                canonical_phonemes: &["G OW IH NG", "T UW"],
                suggested_phonemes: &["G AH N AH"],
            },
            RuleDefinition {
                rule_id: "assimilation-did-you",
                rule_family: "assimilation",
                description: "Did you may assimilate at the /d/ + /j/ boundary.",
                condition: "The adjacent lexical tokens are did + you.",
                example: "Did you see it",
                counterexample: "Did they see it",
                canonical_phonemes: &["D IH D", "Y UW"],
                suggested_phonemes: &["D IH D ZH UW"],
            },
            RuleDefinition {
                rule_id: "link-consonant-vowel",
                rule_family: "linking",
                description: "A final consonant may link into a following vowel.",
                condition: "A word ending in a consonant precedes a vowel-initial word.",
                example: "Pick it up",
                counterexample: "See it",
                canonical_phonemes: &[],
                suggested_phonemes: &[],
            },
            RuleDefinition {
                rule_id: "link-same-consonant",
                rule_family: "linking",
                description: "Matching boundary consonants may be held as one boundary.",
                condition: "Adjacent words share the same boundary consonant letter.",
                example: "Big game",
                counterexample: "Big house",
                canonical_phonemes: &[],
                suggested_phonemes: &[],
            },
            RuleDefinition {
                rule_id: "possible-t-d-deletion",
                rule_family: "deletion",
                description: "Final /t/ or /d/ may weaken before a consonant.",
                condition: "A t- or d-final word precedes another word.",
                example: "Last call",
                counterexample: "Last",
                canonical_phonemes: &["T", "D"],
                suggested_phonemes: &[],
            },
            RuleDefinition {
                rule_id: "american-flap-t-d",
                rule_family: "flapping",
                description: "Intervocalic /t/ or /d/ may become an American English flap.",
                condition: "A lexical token contains a vowel + t/d + vowel sequence.",
                example: "Water",
                counterexample: "Tree",
                canonical_phonemes: &["T", "D"],
                suggested_phonemes: &["DX"],
            },
        ]);
        values
    })
}

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
    estimate_word_timings_with_rhythm(sentence, None)
}

pub fn estimate_word_timings_with_rhythm(
    sentence: &SubtitleSentence,
    rhythm_prosody: Option<&str>,
) -> Vec<WordTiming> {
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
    let strategy = EstimationStrategy::from_rhythm(rhythm_prosody);
    let weights = words
        .iter()
        .map(|token| strategy.weight(&token.text))
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
                confidence: Some(strategy.confidence()),
                timing_source: TimingSource::Estimated,
                provider_id: "subtitle-weighted-estimator".into(),
                provider_version: strategy.version().into(),
            };
            cursor = end;
            value
        })
        .collect()
}

enum EstimationStrategy {
    CharWeight,
    SyllableEqual,
    MoraCount,
}

impl EstimationStrategy {
    fn from_rhythm(rhythm_prosody: Option<&str>) -> Self {
        match rhythm_prosody {
            Some(r) if r.contains("syllable") => Self::SyllableEqual,
            Some(r) if r.contains("mora") => Self::MoraCount,
            _ => Self::CharWeight,
        }
    }

    fn weight(&self, text: &str) -> u64 {
        match self {
            Self::CharWeight => (text.chars().count() as u64).clamp(2, 12),
            Self::SyllableEqual => {
                // Each CJK character ≈ one syllable ≈ equal duration.
                // For mixed text, non-CJK chars get char-weighted fallback.
                let chars: Vec<char> = text.chars().collect();
                if chars.iter().all(|c| is_cjk(*c)) {
                    (chars.len() as u64).max(1)
                } else {
                    (chars.len() as u64).clamp(2, 12)
                }
            }
            Self::MoraCount => {
                // Japanese mora: each kana = 1 mora, kanji ≈ 2 mora (approximation),
                // small kana (っ、ゃ、ゅ、ょ etc.) don't count as separate mora.
                let count: u64 = text
                    .chars()
                    .map(|c| {
                        if is_small_kana(c) {
                            0
                        } else if is_kana_char(c) {
                            1
                        } else if is_cjk(c) {
                            2
                        } else {
                            1
                        }
                    })
                    .sum();
                count.max(1)
            }
        }
    }

    fn confidence(&self) -> f32 {
        match self {
            Self::CharWeight => 0.35,
            Self::SyllableEqual => 0.40,
            Self::MoraCount => 0.38,
        }
    }

    fn version(&self) -> &'static str {
        match self {
            Self::CharWeight => "v1",
            Self::SyllableEqual => "v2-syllable",
            Self::MoraCount => "v2-mora",
        }
    }
}

fn is_cjk(c: char) -> bool {
    matches!(c,
        '\u{4E00}'..='\u{9FFF}' |
        '\u{3400}'..='\u{4DBF}' |
        '\u{20000}'..='\u{2A6DF}' |
        '\u{F900}'..='\u{FAFF}'
    )
}

fn is_kana_char(c: char) -> bool {
    matches!(c, '\u{3040}'..='\u{309F}' | '\u{30A0}'..='\u{30FF}')
}

fn is_small_kana(c: char) -> bool {
    matches!(
        c,
        'っ' | 'ッ'
            | 'ゃ'
            | 'ャ'
            | 'ゅ'
            | 'ュ'
            | 'ょ'
            | 'ョ'
            | 'ぁ'
            | 'ァ'
            | 'ぃ'
            | 'ィ'
            | 'ぅ'
            | 'ゥ'
            | 'ぇ'
            | 'ェ'
            | 'ぉ'
            | 'ォ'
    )
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
    let definition = rule_catalog()
        .iter()
        .find(|definition| definition.rule_id == rule_id);
    SpeechRuleFinding {
        rule_id,
        rule_family: family.into(),
        affected_token_start: start,
        affected_token_end: end,
        canonical_phonemes: definition
            .map(|value| {
                value
                    .canonical_phonemes
                    .iter()
                    .map(ToString::to_string)
                    .collect()
            })
            .unwrap_or_default(),
        suggested_phonemes: definition
            .map(|value| {
                value
                    .suggested_phonemes
                    .iter()
                    .map(ToString::to_string)
                    .collect()
            })
            .unwrap_or_default(),
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

    #[test]
    fn rule_catalog_has_fixed_examples_and_counterexamples() {
        let catalog = rule_catalog();
        assert!((15..=25).contains(&catalog.len()));
        let ids = catalog
            .iter()
            .map(|definition| definition.rule_id)
            .collect::<std::collections::HashSet<_>>();
        assert_eq!(ids.len(), catalog.len());
        for definition in catalog {
            assert!(
                analyze_rules(&sentence(definition.example))
                    .iter()
                    .any(|finding| finding.rule_id == definition.rule_id),
                "example did not trigger {}",
                definition.rule_id
            );
            assert!(
                analyze_rules(&sentence(definition.counterexample))
                    .iter()
                    .all(|finding| finding.rule_id != definition.rule_id),
                "counterexample triggered {}",
                definition.rule_id
            );
        }
    }

    #[test]
    fn fixed_en_us_baseline_covers_one_hundred_sentences() {
        let baseline = include_str!("../../../testdata/pronunciation/en-us-baseline.tsv");
        let rows = baseline
            .lines()
            .map(|line| line.split_once('\t').expect("baseline row has category"))
            .collect::<Vec<_>>();
        assert_eq!(rows.len(), 100);
        assert_eq!(
            rows.iter()
                .map(|(category, _)| category)
                .collect::<std::collections::HashSet<_>>()
                .len(),
            10
        );
        for (_, text) in rows {
            let sentence = sentence(text);
            let analysis = analyze_sentence(&sentence);
            assert_eq!(analysis.words.len(), sentence.tokens.len());
            let timings = estimate_word_timings(&sentence);
            assert_eq!(timings.len(), sentence.tokens.len());
            assert!(
                timings
                    .windows(2)
                    .all(|pair| pair[0].end_ms <= pair[1].start_ms)
            );
        }
    }

    // ── Property-based tests ───────────────────────────────────────

    mod proptests {
        use super::*;
        use proptest::prelude::*;

        proptest! {
            /// estimate_word_timings: output count equals word token count.
            #[test]
            fn prop_estimate_output_count_matches_words(
                words in prop::collection::vec("[a-z]{2,12}", 1..50),
            ) {
                let text = words.join(" ");
                let sent = sentence(&text);
                let word_count = sent.tokens.iter()
                    .filter(|t| t.kind == SubtitleTokenKind::Word)
                    .count();
                let timings = estimate_word_timings(&sent);
                prop_assert_eq!(timings.len(), word_count);
            }

            /// estimate_word_timings: every timing has start ≤ end.
            #[test]
            fn prop_estimate_timings_start_le_end(
                words in prop::collection::vec("[a-z]{2,12}", 1..50),
            ) {
                let text = words.join(" ");
                let sent = sentence(&text);
                let timings = estimate_word_timings(&sent);
                for t in &timings {
                    prop_assert!(t.start_ms <= t.end_ms,
                        "start_ms {} > end_ms {}", t.start_ms, t.end_ms);
                }
            }

            /// estimate_word_timings: timings are within sentence boundaries.
            #[test]
            fn prop_estimate_timings_within_bounds(
                words in prop::collection::vec("[a-z]{2,12}", 1..50),
            ) {
                let text = words.join(" ");
                let sent = sentence(&text);
                let timings = estimate_word_timings(&sent);
                if timings.is_empty() {
                    return Ok(());
                }
                prop_assert!(timings[0].start_ms >= sent.start.get());
                prop_assert!(timings.last().unwrap().end_ms <= sent.end.get());
            }

            /// estimate_word_timings: timings are monotonic.
            #[test]
            fn prop_estimate_timings_monotonic(
                words in prop::collection::vec("[a-z]{2,12}", 1..50),
            ) {
                let text = words.join(" ");
                let sent = sentence(&text);
                let timings = estimate_word_timings(&sent);
                for pair in timings.windows(2) {
                    prop_assert!(pair[0].end_ms <= pair[1].start_ms,
                        "non-monotonic: {}..{} then {}..{}",
                        pair[0].start_ms, pair[0].end_ms,
                        pair[1].start_ms, pair[1].end_ms);
                }
            }
        }
    }

    fn chinese_sentence(words: &[&str]) -> SubtitleSentence {
        let full_text = words.join("");
        let mut offset = 0u32;
        SubtitleSentence {
            id: SubtitleSentenceId::parse("s").unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(6000),
            original_text: full_text.clone(),
            display_text: full_text,
            tokens: words
                .iter()
                .enumerate()
                .map(|(i, text)| {
                    let start = offset;
                    let len = text.chars().count() as u32;
                    offset += len;
                    SubtitleToken {
                        index: i as u32,
                        kind: SubtitleTokenKind::Word,
                        text: text.to_string(),
                        normalized: Some(text.to_string()),
                        start_char: start,
                        end_char: start + len,
                    }
                })
                .collect(),
        }
    }

    #[test]
    fn syllable_timed_gives_equal_weight_to_cjk_chars() {
        let sentence = chinese_sentence(&["因为", "我", "不", "知道"]);
        let timings = estimate_word_timings_with_rhythm(&sentence, Some("zh.syllable_tone"));
        assert_eq!(timings.len(), 4);
        // "因为" (2 chars) should get 2x the duration of "我" (1 char)
        let d0 = timings[0].end_ms - timings[0].start_ms;
        let d1 = timings[1].end_ms - timings[1].start_ms;
        assert_eq!(d0, d1 * 2);
        assert_eq!(timings[0].provider_version, "v2-syllable");
    }

    #[test]
    fn mora_timed_counts_kana() {
        let strategy = EstimationStrategy::MoraCount;
        assert_eq!(strategy.weight("たべる"), 3);
        assert_eq!(strategy.weight("きょう"), 2); // ょ is small kana
        assert_eq!(strategy.weight("がっこう"), 3); // っ is small kana
    }

    #[test]
    fn default_rhythm_is_char_weight() {
        let sentence = sentence("hello world");
        let t1 = estimate_word_timings(&sentence);
        let t2 = estimate_word_timings_with_rhythm(&sentence, None);
        assert_eq!(t1.len(), t2.len());
        for (a, b) in t1.iter().zip(t2.iter()) {
            assert_eq!(a.start_ms, b.start_ms);
            assert_eq!(a.end_ms, b.end_ms);
            assert_eq!(a.provider_version, "v1");
        }
    }
}
