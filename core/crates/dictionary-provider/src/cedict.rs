// CC-CEDICT providers: Chinese dictionary and pinyin pronunciation.
// Split out of lib.rs (mechanical decomposition).

use crate::support::ResourceSignature;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use application::{DictionaryProvider, DictionaryProviderError, PronunciationProvider};
use async_trait::async_trait;
use domain::{
    CharacterBreakdown, DictionaryDefinition, DictionaryLookup, DictionaryPhonetic,
    DictionaryProviderInfo, LanguageCode, Phoneme, PronunciationProviderInfo, PronunciationVariant,
    SentencePronunciation, SubtitleSentence, SubtitleTokenKind, WordPronunciation,
};
use learning_resource_runtime::learning_resource_path;

/// Mandarin dictionary provider. It resolves from CC-CEDICT when that resource
/// is installed (the full ~120k-entry community dictionary), and falls back to a
/// small built-in seed so common words still resolve out of the box before any
/// download. Both sources carry tone-marked pinyin (the `zh` profile declares
/// `zh.pinyin` + `zh.tone`) and a gloss. It plugs in behind the same
/// `DictionaryProvider` interface as the English providers and is selected purely
/// by `supported_languages`; an unknown word returns `None`, which the dispatcher
/// degrades cleanly.
pub struct ChineseDictionaryProvider {
    seed: HashMap<&'static str, (&'static str, &'static str)>,
    path: PathBuf,
    index: Mutex<Option<(ResourceSignature, Arc<CedictIndex>)>>,
}

/// `(word, tone_marked_pinyin, gloss)` built-in fallback. Covers the tokenizer
/// fixtures (我/想/喝/咖啡, plus mixed-sentence neighbours) and common greetings
/// so the click-to-meaning path works before CC-CEDICT is installed.
const CHINESE_DICTIONARY_SEED: &[(&str, &str, &str)] = &[
    ("我", "wǒ", "I; me"),
    ("我们", "wǒ men", "we; us"),
    ("你", "nǐ", "you"),
    ("好", "hǎo", "good; well"),
    ("你好", "nǐ hǎo", "hello"),
    ("想", "xiǎng", "to want; to think"),
    ("喝", "hē", "to drink"),
    ("咖啡", "kā fēi", "coffee"),
    ("茶", "chá", "tea"),
    ("水", "shuǐ", "water"),
    ("谢谢", "xiè xie", "thanks; thank you"),
    ("再见", "zài jiàn", "goodbye"),
    ("是", "shì", "to be; is/are"),
    ("不", "bù", "not; no"),
    ("吃", "chī", "to eat"),
    ("饭", "fàn", "cooked rice; meal"),
    ("说", "shuō", "to speak; to say"),
    ("听", "tīng", "to listen"),
    ("看", "kàn", "to look; to watch; to read"),
    ("中文", "zhōng wén", "Chinese (language)"),
    ("学习", "xué xí", "to study; to learn"),
    ("老师", "lǎo shī", "teacher"),
    ("朋友", "péng you", "friend"),
    ("今天", "jīn tiān", "today"),
    ("电影", "diàn yǐng", "film; movie"),
];

#[derive(Debug, Default)]
struct CedictIndex {
    /// Keyed by both the simplified and traditional headword.
    entries: HashMap<String, CedictEntry>,
}

#[derive(Debug)]
struct CedictEntry {
    pinyin: String,
    definition: String,
}

impl ChineseDictionaryProvider {
    pub fn new() -> Self {
        Self::with_path(learning_resource_path("cc-cedict"))
    }

    pub fn with_path(path: PathBuf) -> Self {
        Self {
            seed: CHINESE_DICTIONARY_SEED
                .iter()
                .map(|(word, pinyin, gloss)| (*word, (*pinyin, *gloss)))
                .collect(),
            path,
            index: Mutex::new(None),
        }
    }

    /// Load (and cache) the installed CC-CEDICT index. Returns `None` when the
    /// resource is not installed or cannot be read, so lookups degrade to the
    /// built-in seed.
    fn load_index(&self) -> Option<Arc<CedictIndex>> {
        let signature = ResourceSignature::read(&self.path).ok()??;
        let mut cached = self.index.lock().expect("CC-CEDICT index mutex poisoned");
        if let Some((cached_signature, index)) = cached.as_ref()
            && *cached_signature == signature
        {
            return Some(index.clone());
        }
        let index = Arc::new(read_cedict_index(&self.path).ok()?);
        *cached = Some((signature, index.clone()));
        Some(index)
    }

    /// Synchronous lookup core, kept separate from the async trait method so it
    /// is testable without a runtime. Prefers installed CC-CEDICT, then the seed.
    pub(crate) fn resolve(&self, lemma: &str) -> Option<DictionaryLookup> {
        let (pinyin, definition) = if let Some(index) = self.load_index()
            && let Some(entry) = index.entries.get(lemma)
        {
            (entry.pinyin.clone(), entry.definition.clone())
        } else {
            let (p, g) = self.seed.get(lemma)?;
            (p.to_string(), g.to_string())
        };
        let mut lookup = chinese_lookup(lemma, &pinyin, &definition);
        let chars: Vec<String> = lemma.chars().map(|ch| ch.to_string()).collect();
        if chars.len() >= 2 {
            let syllables: Vec<&str> = pinyin.split_whitespace().collect();
            let index = self.load_index();
            let breakdowns: Vec<CharacterBreakdown> = chars
                .iter()
                .enumerate()
                .map(|(i, ch)| {
                    let char_pinyin = syllables.get(i).copied().unwrap_or("").to_owned();
                    let meaning = self.resolve_single_char(ch, index.as_deref());
                    CharacterBreakdown {
                        character: ch.clone(),
                        phonetic: char_pinyin,
                        meaning,
                    }
                })
                .collect();
            lookup.character_breakdowns = breakdowns;
        }
        Some(lookup)
    }

    fn resolve_single_char(&self, ch: &str, index: Option<&CedictIndex>) -> String {
        if let Some(index) = index
            && let Some(entry) = index.entries.get(ch)
        {
            return entry.definition.clone();
        }
        self.seed
            .get(ch)
            .map(|(_, gloss)| gloss.to_string())
            .unwrap_or_default()
    }
}

impl Default for ChineseDictionaryProvider {
    fn default() -> Self {
        Self::new()
    }
}

fn chinese_lookup(lemma: &str, pinyin: &str, definition: &str) -> DictionaryLookup {
    DictionaryLookup {
        query: lemma.to_owned(),
        lemma: lemma.to_owned(),
        definitions: vec![DictionaryDefinition {
            part_of_speech: None,
            text: definition.to_owned(),
        }],
        phonetics: vec![DictionaryPhonetic {
            text: pinyin.to_owned(),
            region: Some("zh".into()),
            audio_url: None,
        }],
        character_breakdowns: vec![],
        provider: "cc-cedict".into(),
        cached_at_ms: 0,
    }
}

#[async_trait]
impl DictionaryProvider for ChineseDictionaryProvider {
    fn info(&self) -> DictionaryProviderInfo {
        DictionaryProviderInfo {
            id: "cc-cedict".into(),
            display_name: "CC-CEDICT".into(),
            supported_languages: vec!["zh".into()],
            provides_definitions: true,
            provides_phonetics: true,
            provides_audio: false,
            offline: true,
        }
    }

    async fn lookup(
        &self,
        _language: &LanguageCode,
        lemma: &str,
    ) -> Result<Option<DictionaryLookup>, DictionaryProviderError> {
        Ok(self.resolve(lemma))
    }
}

// ---------------------------------------------------------------------------
// Chinese Pronunciation Provider (Pinyin from CC-CEDICT)
// ---------------------------------------------------------------------------

pub struct ChinesePronunciationProvider {
    seed: HashMap<&'static str, (&'static str, &'static str)>,
    path: PathBuf,
    index: Mutex<Option<(ResourceSignature, Arc<CedictIndex>)>>,
}

const CHINESE_PRONUNCIATION_PROVIDER_ID: &str = "cedict-pinyin";
const CHINESE_PRONUNCIATION_PROVIDER_VERSION: &str = "1.0";

impl ChinesePronunciationProvider {
    pub fn new() -> Self {
        let path = learning_resource_path("cc-cedict");
        Self {
            seed: CHINESE_DICTIONARY_SEED
                .iter()
                .map(|(word, pinyin, gloss)| (*word, (*pinyin, *gloss)))
                .collect(),
            path,
            index: Mutex::new(None),
        }
    }

    fn load_index(&self) -> Option<Arc<CedictIndex>> {
        let signature = ResourceSignature::read(&self.path).ok()??;
        let mut cached = self.index.lock().expect("CC-CEDICT index mutex poisoned");
        if let Some((cached_signature, index)) = cached.as_ref()
            && *cached_signature == signature
        {
            return Some(index.clone());
        }
        let index = Arc::new(read_cedict_index(&self.path).ok()?);
        *cached = Some((signature, index.clone()));
        Some(index)
    }

    fn lookup_pinyin(&self, word: &str) -> Option<String> {
        if let Some(index) = self.load_index()
            && let Some(entry) = index.entries.get(word)
        {
            return Some(entry.pinyin.clone());
        }
        self.seed.get(word).map(|(pinyin, _)| pinyin.to_string())
    }

    fn lookup_pinyin_single_char(&self, ch: &str) -> Option<String> {
        if let Some(index) = self.load_index()
            && let Some(entry) = index.entries.get(ch)
        {
            return Some(entry.pinyin.clone());
        }
        self.seed.get(ch).map(|(pinyin, _)| pinyin.to_string())
    }

    fn word_pronunciation(&self, word: &str, token_index: u32) -> WordPronunciation {
        let pinyin = self.lookup_pinyin(word).unwrap_or_else(|| {
            word.chars()
                .filter_map(|ch| self.lookup_pinyin_single_char(&ch.to_string()))
                .collect::<Vec<_>>()
                .join(" ")
        });
        let syllables: Vec<&str> = pinyin.split_whitespace().collect();
        let phonemes: Vec<Phoneme> = syllables
            .iter()
            .enumerate()
            .map(|(i, syllable)| Phoneme {
                symbol: syllable.to_string(),
                phoneme_set: "pinyin".into(),
                display_ipa: syllable.to_string(),
                stress: None,
                syllable_index: Some(i as u32),
                token_index: Some(token_index),
                start_ms: None,
                end_ms: None,
                confidence: None,
            })
            .collect();
        let display_ipa = pinyin.clone();
        WordPronunciation {
            token_index,
            text: word.to_owned(),
            normalized: word.to_owned(),
            variants: vec![PronunciationVariant {
                phonemes,
                display_ipa,
                is_fallback: pinyin.is_empty(),
            }],
        }
    }
}

impl Default for ChinesePronunciationProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl PronunciationProvider for ChinesePronunciationProvider {
    fn info(&self) -> PronunciationProviderInfo {
        PronunciationProviderInfo {
            id: CHINESE_PRONUNCIATION_PROVIDER_ID.into(),
            display_name: "CC-CEDICT Pinyin".into(),
            version: CHINESE_PRONUNCIATION_PROVIDER_VERSION.into(),
            languages: vec!["zh".into()],
            accents: vec!["zh-CN".into()],
            phoneme_sets: vec!["pinyin".into()],
            supports_context: false,
            supports_variants: false,
            supports_stress: false,
            supports_token_mapping: true,
            available: true,
            degraded: false,
            diagnostic: None,
        }
    }

    fn analyze_sentence(&self, sentence: &SubtitleSentence) -> Option<SentencePronunciation> {
        let words: Vec<WordPronunciation> = sentence
            .tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
            .map(|token| self.word_pronunciation(&token.text, token.index))
            .collect();
        let phonemes: Vec<Phoneme> = words
            .iter()
            .flat_map(|word| {
                word.variants
                    .first()
                    .into_iter()
                    .flat_map(|v| v.phonemes.clone())
            })
            .collect();
        let display_ipa = words
            .iter()
            .filter_map(|word| word.variants.first())
            .map(|v| v.display_ipa.as_str())
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join(" ");
        Some(SentencePronunciation {
            sentence_id: sentence.id.clone(),
            language: "zh".into(),
            accent: "zh-CN".into(),
            provider_id: CHINESE_PRONUNCIATION_PROVIDER_ID.into(),
            provider_version: CHINESE_PRONUNCIATION_PROVIDER_VERSION.into(),
            phoneme_set: "pinyin".into(),
            display_ipa,
            words,
            phonemes,
            rules: vec![],
        })
    }

    fn lookup_word(&self, word: &str, token_index: u32) -> Option<WordPronunciation> {
        let pronunciation = self.word_pronunciation(word, token_index);
        if pronunciation
            .variants
            .first()
            .is_some_and(|v| !v.display_ipa.is_empty())
        {
            Some(pronunciation)
        } else {
            None
        }
    }
}

/// Parse a CC-CEDICT `.u8` file into a lookup index. The format is
/// `Traditional Simplified [pin1 yin1] /gloss/gloss/`, one entry per line, with
/// `#` comments. Pinyin tone numbers are converted to tone marks. When a
/// headword repeats (multiple readings), the first entry wins.
fn read_cedict_index(path: &Path) -> Result<CedictIndex, String> {
    let content = std::fs::read_to_string(path).map_err(|error| error.to_string())?;
    let mut index = CedictIndex::default();
    for line in content.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        let Some((traditional, simplified, pinyin, definition)) = parse_cedict_line(line) else {
            continue;
        };
        for headword in [simplified, traditional] {
            index
                .entries
                .entry(headword)
                .or_insert_with(|| CedictEntry {
                    pinyin: pinyin.clone(),
                    definition: definition.clone(),
                });
        }
    }
    Ok(index)
}

/// Parse one CC-CEDICT line into `(traditional, simplified, tone_marked_pinyin,
/// definition)`. Returns `None` for malformed lines so they are skipped.
fn parse_cedict_line(line: &str) -> Option<(String, String, String, String)> {
    let (traditional, rest) = line.split_once(' ')?;
    let (simplified, rest) = rest.split_once(' ')?;
    let open = rest.find('[')?;
    let close = rest[open + 1..].find(']')? + open + 1;
    let definition = rest[close + 1..]
        .trim()
        .trim_matches('/')
        .split('/')
        .filter(|part| !part.trim().is_empty())
        .collect::<Vec<_>>()
        .join("; ");
    if definition.is_empty() {
        return None;
    }
    let pinyin = numbered_pinyin_to_marks(&rest[open + 1..close]);
    Some((
        traditional.to_owned(),
        simplified.to_owned(),
        pinyin,
        definition,
    ))
}

/// Convert space-separated tone-numbered pinyin ("ni3 hao3") to tone marks
/// ("nǐ hǎo"). `u:` becomes `ü`; tone 5 (and missing tones) carry no mark.
pub(crate) fn numbered_pinyin_to_marks(numbered: &str) -> String {
    numbered
        .split_whitespace()
        .map(pinyin_syllable_to_marks)
        .collect::<Vec<_>>()
        .join(" ")
}

fn pinyin_syllable_to_marks(syllable: &str) -> String {
    let body = syllable.replace("u:", "ü").replace("U:", "Ü");
    let tone = body.chars().last().and_then(|c| c.to_digit(10));
    let body = match tone {
        Some(_) => &body[..body.len() - 1],
        None => body.as_str(),
    };
    match tone {
        Some(tone @ 1..=4) => apply_tone_mark(body, tone as usize),
        _ => body.to_owned(),
    }
}

/// Place the tone mark on the correct vowel: `a` and `e` always take it; in `ou`
/// the `o` takes it; otherwise the last vowel does (standard pinyin rule).
fn apply_tone_mark(body: &str, tone: usize) -> String {
    let lower: Vec<char> = body.to_lowercase().chars().collect();
    let target = lower
        .iter()
        .position(|&c| c == 'a')
        .or_else(|| lower.iter().position(|&c| c == 'e'))
        .or_else(|| {
            lower
                .windows(2)
                .position(|pair| pair[0] == 'o' && pair[1] == 'u')
        })
        .or_else(|| lower.iter().rposition(|&c| is_pinyin_vowel(c)));
    let Some(index) = target else {
        return body.to_owned();
    };
    body.chars()
        .enumerate()
        .map(|(position, original)| {
            if position == index {
                tone_marked_vowel(original, tone)
            } else {
                original
            }
        })
        .collect()
}

fn is_pinyin_vowel(value: char) -> bool {
    matches!(value, 'a' | 'e' | 'i' | 'o' | 'u' | 'ü')
}

fn tone_marked_vowel(vowel: char, tone: usize) -> char {
    let table: &[char; 4] = match vowel.to_ascii_lowercase() {
        'a' => &['ā', 'á', 'ǎ', 'à'],
        'e' => &['ē', 'é', 'ě', 'è'],
        'i' => &['ī', 'í', 'ǐ', 'ì'],
        'o' => &['ō', 'ó', 'ǒ', 'ò'],
        'u' => &['ū', 'ú', 'ǔ', 'ù'],
        _ if vowel == 'ü' || vowel == 'Ü' => &['ǖ', 'ǘ', 'ǚ', 'ǜ'],
        _ => return vowel,
    };
    let marked = table[tone - 1];
    if vowel.is_uppercase() {
        marked.to_uppercase().next().unwrap_or(marked)
    } else {
        marked
    }
}
