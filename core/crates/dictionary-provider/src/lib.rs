use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use application::{
    DictionaryProvider, DictionaryProviderError, LexicalNormalizationProvider,
    LexicalNormalizationProviderError,
};
use async_trait::async_trait;
use domain::{
    CharacterBreakdown, DictionaryDefinition, DictionaryLookup, DictionaryPhonetic,
    DictionaryProviderInfo, LanguageCode, PhraseCandidate, SubtitleSentence, SubtitleTokenKind,
    normalize_lemma,
};

pub struct FreeDictionaryProvider {
    client: reqwest::Client,
    base_url: String,
}

impl FreeDictionaryProvider {
    pub fn new() -> Result<Self, DictionaryProviderError> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .map_err(|error| DictionaryProviderError(error.to_string()))?;
        Ok(Self {
            client,
            base_url: "https://api.dictionaryapi.dev/api/v2/entries".into(),
        })
    }

    #[cfg(test)]
    pub fn with_base_url(base_url: String) -> Result<Self, DictionaryProviderError> {
        let mut value = Self::new()?;
        value.base_url = base_url;
        Ok(value)
    }
}

#[async_trait]
impl DictionaryProvider for FreeDictionaryProvider {
    fn info(&self) -> DictionaryProviderInfo {
        DictionaryProviderInfo {
            id: "free-dictionary-api".into(),
            display_name: "Free Dictionary API".into(),
            supported_languages: vec!["en".into()],
            provides_definitions: true,
            provides_phonetics: true,
            provides_audio: true,
            offline: false,
        }
    }

    async fn lookup(
        &self,
        language: &LanguageCode,
        lemma: &str,
    ) -> Result<Option<DictionaryLookup>, DictionaryProviderError> {
        let url = format!(
            "{}/{}/{}",
            self.base_url,
            language.as_str(),
            url_encode(lemma)
        );
        let response = self
            .client
            .get(url)
            .send()
            .await
            .map_err(|error| DictionaryProviderError(error.to_string()))?;
        if response.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(None);
        }
        let response = response
            .error_for_status()
            .map_err(|error| DictionaryProviderError(error.to_string()))?;
        let payload: serde_json::Value = response
            .json()
            .await
            .map_err(|error| DictionaryProviderError(error.to_string()))?;
        let Some(entry) = payload.as_array().and_then(|entries| entries.first()) else {
            return Ok(None);
        };
        let definitions = entry["meanings"]
            .as_array()
            .into_iter()
            .flatten()
            .flat_map(|meaning| {
                let part = meaning["partOfSpeech"].as_str().map(str::to_owned);
                meaning["definitions"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(move |definition| {
                        definition["definition"]
                            .as_str()
                            .map(|text| DictionaryDefinition {
                                part_of_speech: part.clone(),
                                text: text.to_owned(),
                            })
                    })
            })
            .take(8)
            .collect();
        let phonetics = parse_free_dictionary_phonetics(entry);
        Ok(Some(DictionaryLookup {
            query: lemma.to_owned(),
            lemma: entry["word"].as_str().unwrap_or(lemma).to_owned(),
            definitions,
            phonetics,
            character_breakdowns: vec![],
            provider: self.info().id,
            cached_at_ms: 0,
        }))
    }
}

pub struct EcdictProvider {
    path: PathBuf,
    version: String,
    index: Mutex<Option<(ResourceSignature, Arc<EcdictIndex>)>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ResourceSignature {
    len: u64,
    modified: Option<SystemTime>,
}

#[derive(Debug, Default)]
struct EcdictIndex {
    lemmas: HashMap<String, String>,
    phrases: HashSet<String>,
    dictionary: HashMap<String, EcdictEntry>,
}

#[derive(Debug)]
struct EcdictEntry {
    phonetic: String,
    definition: String,
}

impl EcdictProvider {
    pub fn new() -> Self {
        let id = domain::LearningResourceId::from_fingerprint("learning-resource", "ecdict");
        let path = std::env::var_os("LLPLAYERNEXT_RESOURCES_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
                    .join("Library/Application Support/LLPlayerNext/resources/learning")
            })
            .join(format!("{}.data", id.as_str()));
        Self::with_path(path, "bc015ed2")
    }

    pub fn with_path(path: PathBuf, version: impl Into<String>) -> Self {
        Self {
            path,
            version: version.into(),
            index: Mutex::new(None),
        }
    }

    fn load_index(&self) -> Result<Option<Arc<EcdictIndex>>, String> {
        let metadata = match std::fs::metadata(&self.path) {
            Ok(value) => value,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.to_string()),
        };
        let signature = ResourceSignature {
            len: metadata.len(),
            modified: metadata.modified().ok(),
        };
        let mut cached = self.index.lock().expect("ECDICT index mutex poisoned");
        if let Some((cached_signature, index)) = cached.as_ref()
            && *cached_signature == signature
        {
            return Ok(Some(index.clone()));
        }
        let index = Arc::new(read_ecdict_index(&self.path)?);
        *cached = Some((signature, index.clone()));
        Ok(Some(index))
    }
}

impl Default for EcdictProvider {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl DictionaryProvider for EcdictProvider {
    fn info(&self) -> DictionaryProviderInfo {
        DictionaryProviderInfo {
            id: "ecdict".into(),
            display_name: "ECDICT".into(),
            supported_languages: vec!["en".into()],
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
        let Some(index) = self.load_index().map_err(DictionaryProviderError)? else {
            return Ok(None);
        };
        let query = normalize_lemma(lemma);
        let normalized = index
            .lemmas
            .get(&query)
            .cloned()
            .unwrap_or_else(|| query.clone());
        let Some(entry) = index.dictionary.get(&normalized) else {
            return Ok(None);
        };
        Ok(Some(DictionaryLookup {
            query,
            lemma: normalized,
            definitions: (!entry.definition.is_empty())
                .then(|| DictionaryDefinition {
                    part_of_speech: None,
                    text: entry.definition.replace("\\n", "\n"),
                })
                .into_iter()
                .collect(),
            phonetics: (!entry.phonetic.is_empty())
                .then(|| DictionaryPhonetic {
                    text: entry.phonetic.clone(),
                    region: Some("en-US".into()),
                    audio_url: None,
                })
                .into_iter()
                .collect(),
            character_breakdowns: vec![],
            provider: "ecdict".into(),
            cached_at_ms: 0,
        }))
    }
}

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
        let id = domain::LearningResourceId::from_fingerprint("learning-resource", "cc-cedict");
        let path = std::env::var_os("LLPLAYERNEXT_RESOURCES_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
                    .join("Library/Application Support/LLPlayerNext/resources/learning")
            })
            .join(format!("{}.data", id.as_str()));
        Self::with_path(path)
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
        let metadata = std::fs::metadata(&self.path).ok()?;
        let signature = ResourceSignature {
            len: metadata.len(),
            modified: metadata.modified().ok(),
        };
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
    fn resolve(&self, lemma: &str) -> Option<DictionaryLookup> {
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
                    let char_pinyin = syllables
                        .get(i)
                        .copied()
                        .unwrap_or("")
                        .to_owned();
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

/// Japanese dictionary provider. It resolves from an installed JMdict/EDICT2 dump
/// (the EDRDG community dictionary) when present, and falls back to a small
/// built-in seed so common words resolve before any download. Readings are kana
/// (the `ja` profile declares `ja.kana`); glosses are English. It plugs in behind
/// the same `DictionaryProvider` interface as the others and is selected purely by
/// `supported_languages`; an unknown word returns `None`, degraded cleanly. This
/// is the real second-non-English dictionary added to validate that a new language
/// is provider work — it touches no dispatcher branch.
pub struct JapaneseDictionaryProvider {
    seed: HashMap<&'static str, (&'static str, &'static str)>,
    path: PathBuf,
    index: Mutex<Option<(ResourceSignature, Arc<EdictIndex>)>>,
}

/// `(headword, kana_reading, gloss)` built-in fallback. Covers the tokenizer
/// fixtures (私 / は / 学生 / です / 図書館 / 勉強) and common words so the
/// click-to-meaning path works before JMdict/EDICT2 is installed.
const JAPANESE_DICTIONARY_SEED: &[(&str, &str, &str)] = &[
    ("私", "わたし", "I; me"),
    ("あなた", "あなた", "you"),
    ("は", "は", "[topic particle]"),
    ("です", "です", "to be; is (copula)"),
    ("学生", "がくせい", "student"),
    ("先生", "せんせい", "teacher; master"),
    ("図書館", "としょかん", "library"),
    ("勉強", "べんきょう", "study; diligence"),
    ("する", "する", "to do"),
    ("食べる", "たべる", "to eat"),
    ("水", "みず", "water"),
    ("本", "ほん", "book"),
    ("日本語", "にほんご", "Japanese (language)"),
    ("こんにちは", "こんにちは", "hello; good afternoon"),
    ("ありがとう", "ありがとう", "thank you"),
];

#[derive(Debug, Default)]
struct EdictIndex {
    /// Keyed by both the kanji headword(s) and the kana reading.
    entries: HashMap<String, EdictEntry>,
}

#[derive(Debug)]
struct EdictEntry {
    reading: String,
    definition: String,
}

impl JapaneseDictionaryProvider {
    pub fn new() -> Self {
        let id = domain::LearningResourceId::from_fingerprint("learning-resource", "jmdict");
        let path = std::env::var_os("LLPLAYERNEXT_RESOURCES_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
                    .join("Library/Application Support/LLPlayerNext/resources/learning")
            })
            .join(format!("{}.data", id.as_str()));
        Self::with_path(path)
    }

    pub fn with_path(path: PathBuf) -> Self {
        Self {
            seed: JAPANESE_DICTIONARY_SEED
                .iter()
                .map(|(word, reading, gloss)| (*word, (*reading, *gloss)))
                .collect(),
            path,
            index: Mutex::new(None),
        }
    }

    /// Load (and cache) the installed JMdict/EDICT2 index. Returns `None` when the
    /// resource is not installed or unreadable, so lookups degrade to the seed.
    fn load_index(&self) -> Option<Arc<EdictIndex>> {
        let metadata = std::fs::metadata(&self.path).ok()?;
        let signature = ResourceSignature {
            len: metadata.len(),
            modified: metadata.modified().ok(),
        };
        let mut cached = self.index.lock().expect("JMdict index mutex poisoned");
        if let Some((cached_signature, index)) = cached.as_ref()
            && *cached_signature == signature
        {
            return Some(index.clone());
        }
        let index = Arc::new(read_edict_index(&self.path).ok()?);
        *cached = Some((signature, index.clone()));
        Some(index)
    }

    /// Synchronous lookup core. Prefers installed JMdict/EDICT2, then the seed.
    fn resolve(&self, lemma: &str) -> Option<DictionaryLookup> {
        if let Some(index) = self.load_index()
            && let Some(entry) = index.entries.get(lemma)
        {
            return Some(japanese_lookup(lemma, &entry.reading, &entry.definition));
        }
        let (reading, gloss) = self.seed.get(lemma)?;
        Some(japanese_lookup(lemma, reading, gloss))
    }
}

impl Default for JapaneseDictionaryProvider {
    fn default() -> Self {
        Self::new()
    }
}

fn japanese_lookup(lemma: &str, reading: &str, definition: &str) -> DictionaryLookup {
    DictionaryLookup {
        query: lemma.to_owned(),
        lemma: lemma.to_owned(),
        definitions: vec![DictionaryDefinition {
            part_of_speech: None,
            text: definition.to_owned(),
        }],
        phonetics: (!reading.is_empty())
            .then(|| DictionaryPhonetic {
                text: reading.to_owned(),
                region: Some("ja".into()),
                audio_url: None,
            })
            .into_iter()
            .collect(),
        character_breakdowns: vec![],
        provider: "jmdict".into(),
        cached_at_ms: 0,
    }
}

#[async_trait]
impl DictionaryProvider for JapaneseDictionaryProvider {
    fn info(&self) -> DictionaryProviderInfo {
        DictionaryProviderInfo {
            id: "jmdict".into(),
            display_name: "JMdict/EDICT".into(),
            supported_languages: vec!["ja".into()],
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

/// Parse a JMdict/EDICT2 `.data` dump into a lookup index. EDICT2 lines look like
/// `頭 [あたま] /(n) head/EntL1234560X/`; kana-only entries omit the `[...]`
/// reading (`ありがとう /(int) thank you/`); headwords and readings may carry
/// `;`-separated variants. Glosses drop a leading `(pos)` tag and the trailing
/// `EntL...` id. Each entry is indexed by every kanji headword and the first kana
/// reading; the first occurrence of a repeated key wins.
fn read_edict_index(path: &Path) -> Result<EdictIndex, String> {
    let content = std::fs::read_to_string(path).map_err(|error| error.to_string())?;
    let mut index = EdictIndex::default();
    for line in content.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }
        let Some((headwords, reading, definition)) = parse_edict_line(line) else {
            continue;
        };
        let mut keys = headwords.clone();
        if !reading.is_empty() {
            keys.push(reading.clone());
        }
        for key in keys {
            index.entries.entry(key).or_insert_with(|| EdictEntry {
                reading: reading.clone(),
                definition: definition.clone(),
            });
        }
    }
    Ok(index)
}

/// Parse one EDICT2 line into `(kanji_headwords, first_kana_reading, definition)`.
/// The reading is empty for kana-only headwords. Returns `None` for malformed
/// lines or lines whose glosses are entirely stripped.
fn parse_edict_line(line: &str) -> Option<(Vec<String>, String, String)> {
    let (head, rest) = line.split_once(' ')?;
    let (reading, gloss_part) = match rest.strip_prefix('[') {
        Some(after) => {
            let close = after.find(']')?;
            let reading = after[..close]
                .split(';')
                .next()
                .unwrap_or_default()
                .trim()
                .to_owned();
            (reading, after[close + 1..].trim_start())
        }
        None => (String::new(), rest),
    };
    let definition = gloss_part
        .trim()
        .trim_matches('/')
        .split('/')
        .map(str::trim)
        .filter(|part| !part.is_empty() && !part.starts_with("EntL") && *part != "(P)")
        .map(strip_edict_pos)
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("; ");
    if definition.is_empty() {
        return None;
    }
    let headwords = head
        .split(';')
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    if headwords.is_empty() {
        return None;
    }
    Some((headwords, reading, definition))
}

/// Drop a leading EDICT `(pos)` / `(tag)` marker from a gloss, e.g. `(n) head` ->
/// `head`. Only a single leading parenthesized group is stripped.
fn strip_edict_pos(gloss: &str) -> String {
    let trimmed = gloss.trim_start();
    if let Some(rest) = trimmed.strip_prefix('(')
        && let Some(close) = rest.find(')')
    {
        return rest[close + 1..].trim_start().to_owned();
    }
    trimmed.to_owned()
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
fn numbered_pinyin_to_marks(numbered: &str) -> String {
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

fn parse_free_dictionary_phonetics(entry: &serde_json::Value) -> Vec<DictionaryPhonetic> {
    entry["phonetics"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|value| {
            let text = value["text"].as_str().unwrap_or_default().to_owned();
            let audio_url = value["audio"]
                .as_str()
                .filter(|value| !value.is_empty())
                .map(|value| {
                    if value.starts_with("//") {
                        format!("https:{value}")
                    } else {
                        value.to_owned()
                    }
                });
            (!text.is_empty() || audio_url.is_some()).then_some(DictionaryPhonetic {
                text,
                region: None,
                audio_url,
            })
        })
        .collect()
}

impl LexicalNormalizationProvider for EcdictProvider {
    fn provider_id(&self) -> &'static str {
        "ecdict"
    }

    fn version(&self) -> &str {
        &self.version
    }

    fn normalize(
        &self,
        language: &LanguageCode,
        value: &str,
    ) -> Result<Option<String>, LexicalNormalizationProviderError> {
        if !language.as_str().starts_with("en") {
            return Ok(None);
        }
        let Some(index) = self
            .load_index()
            .map_err(LexicalNormalizationProviderError)?
        else {
            return Ok(None);
        };
        Ok(index.lemmas.get(&normalize_lemma(value)).cloned())
    }

    fn phrase_candidates(
        &self,
        language: &LanguageCode,
        sentence: &SubtitleSentence,
    ) -> Result<Vec<PhraseCandidate>, LexicalNormalizationProviderError> {
        if !language.as_str().starts_with("en") {
            return Ok(Vec::new());
        }
        let Some(index) = self
            .load_index()
            .map_err(LexicalNormalizationProviderError)?
        else {
            return Ok(Vec::new());
        };
        let words = sentence
            .tokens
            .iter()
            .filter(|token| token.kind == SubtitleTokenKind::Word)
            .collect::<Vec<_>>();
        let normalized = words
            .iter()
            .map(|token| normalize_lemma(&token.text))
            .collect::<Vec<_>>();
        let mut values = Vec::new();
        for length in 2..=5 {
            for (start, phrase_words) in normalized.windows(length).enumerate() {
                let phrase = phrase_words.join(" ");
                if index.phrases.contains(&phrase) {
                    values.push(PhraseCandidate {
                        canonical_form: phrase.clone(),
                        display_form: words[start..start + length]
                            .iter()
                            .map(|token| token.text.as_str())
                            .collect::<Vec<_>>()
                            .join(" "),
                        normalized_form: phrase,
                        token_start: words[start].index,
                        token_end: words[start + length - 1].index,
                        reason: "ECDICT phrase entry".into(),
                    });
                }
            }
        }
        Ok(values)
    }
}

fn read_ecdict_index(path: &Path) -> Result<EcdictIndex, String> {
    let mut reader = csv::ReaderBuilder::new()
        .flexible(true)
        .from_path(path)
        .map_err(|error| error.to_string())?;
    let headers = reader.headers().map_err(|error| error.to_string())?.clone();
    let column = |name: &str, fallback: usize| {
        headers
            .iter()
            .position(|value| value == name)
            .unwrap_or(fallback)
    };
    let word_column = column("word", 0);
    let phonetic_column = column("phonetic", 1);
    let definition_column = column("definition", 2);
    let exchange_column = column("exchange", 10);
    let mut index = EcdictIndex::default();
    for record in reader.records() {
        let record = record.map_err(|error| error.to_string())?;
        let word = normalize_lemma(record.get(word_column).unwrap_or_default());
        if word.is_empty() {
            continue;
        }
        if word.contains(' ') {
            index.phrases.insert(word.clone());
        }
        index
            .lemmas
            .entry(word.clone())
            .or_insert_with(|| word.clone());
        for exchange in record
            .get(exchange_column)
            .unwrap_or_default()
            .split_whitespace()
        {
            let Some((_, forms)) = exchange.split_once(':') else {
                continue;
            };
            for form in forms.split('/') {
                let form = normalize_lemma(form);
                if !form.is_empty() {
                    index.lemmas.entry(form).or_insert_with(|| word.clone());
                }
            }
        }
        index.dictionary.insert(
            word,
            EcdictEntry {
                phonetic: record.get(phonetic_column).unwrap_or_default().into(),
                definition: record.get(definition_column).unwrap_or_default().into(),
            },
        );
    }
    Ok(index)
}

fn url_encode(value: &str) -> String {
    value
        .bytes()
        .map(|byte| {
            if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
                (byte as char).to_string()
            } else {
                format!("%{byte:02X}")
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs};

    fn fixture() -> tempfile::NamedTempFile {
        tempfile::Builder::new()
            .prefix("llplayernext-ecdict-")
            .suffix(".csv")
            .tempfile()
            .unwrap()
    }

    #[test]
    fn ecdict_normalizes_inflections_and_finds_phrase_entries() {
        let fixture = fixture();
        let path = fixture.path().to_path_buf();
        {
            use std::io::Write;
            let mut writer = std::io::BufWriter::new(fixture.as_file());
            writeln!(writer, "word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio").unwrap();
            writeln!(writer, "go,go,move,,,,,,,,\"p:went/gone i:going 3:goes\",,").unwrap();
            writeln!(writer, "piece of cake,,easy task,,,,,,,,,,").unwrap();
            writer.flush().unwrap();
            fixture.as_file().sync_all().unwrap();
        }
        let provider = EcdictProvider::with_path(path.clone(), "fixture-v1");
        let language = LanguageCode::parse("en-US").unwrap();
        assert_eq!(
            provider.normalize(&language, "went").unwrap().as_deref(),
            Some("go")
        );
        assert_eq!(provider.provider_id(), "ecdict");
        assert_eq!(provider.version(), "fixture-v1");

        let words = ["It", "is", "a", "piece", "of", "cake"];
        let sentence = SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("sentence", "fixture"),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1000),
            original_text: words.join(" "),
            display_text: words.join(" "),
            tokens: words
                .iter()
                .enumerate()
                .map(|(index, value)| SubtitleToken {
                    index: index as u32,
                    kind: SubtitleTokenKind::Word,
                    text: (*value).into(),
                    normalized: Some(normalize_lemma(value)),
                    start_char: 0,
                    end_char: value.len() as u32,
                })
                .collect(),
        };
        let candidates = provider.phrase_candidates(&language, &sentence).unwrap();
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].normalized_form, "piece of cake");
        assert_eq!(candidates[0].token_start, 3);
        assert_eq!(candidates[0].token_end, 5);
    }

    #[test]
    fn chinese_provider_falls_back_to_seed_without_cedict() {
        // No installed CC-CEDICT: lookups come from the built-in seed.
        let provider = ChineseDictionaryProvider::with_path("/nonexistent/cc-cedict.data".into());
        let info = provider.info();
        assert_eq!(info.id, "cc-cedict");
        assert_eq!(info.supported_languages, vec!["zh".to_string()]);
        assert!(info.offline);

        let lookup = provider.resolve("咖啡").expect("known word resolves");
        assert_eq!(lookup.provider, "cc-cedict");
        assert_eq!(lookup.phonetics.len(), 1);
        assert_eq!(lookup.phonetics[0].text, "kā fēi");
        assert_eq!(lookup.phonetics[0].region.as_deref(), Some("zh"));
        assert_eq!(lookup.definitions.len(), 1);
        assert_eq!(lookup.definitions[0].text, "coffee");

        // Single characters that also stand alone resolve too (char-granularity).
        assert_eq!(
            provider.resolve("好").expect("char resolves").phonetics[0].text,
            "hǎo"
        );
        // Unknown words degrade to None rather than failing.
        assert!(provider.resolve("量子力学").is_none());
    }

    #[test]
    fn chinese_provider_reads_installed_cedict() {
        let fixture = tempfile::Builder::new()
            .prefix("llplayernext-cedict-")
            .suffix(".u8")
            .tempfile()
            .unwrap();
        {
            use std::io::Write;
            let mut writer = std::io::BufWriter::new(fixture.as_file());
            writeln!(writer, "# CC-CEDICT").unwrap();
            writeln!(writer, "你好 你好 [ni3 hao3] /hello/hi/").unwrap();
            writeln!(writer, "電影 电影 [dian4 ying3] /film/movie/").unwrap();
            writeln!(writer, "旅行 旅行 [lu:3 xing2] /to travel/journey/").unwrap();
            writer.flush().unwrap();
            fixture.as_file().sync_all().unwrap();
        }
        let provider = ChineseDictionaryProvider::with_path(fixture.path().to_path_buf());

        // Simplified headword: numbered pinyin becomes tone marks, glosses join.
        let lookup = provider.resolve("电影").expect("simplified resolves");
        assert_eq!(lookup.provider, "cc-cedict");
        assert_eq!(lookup.phonetics[0].text, "diàn yǐng");
        assert_eq!(lookup.definitions[0].text, "film; movie");
        // Traditional headword resolves to the same entry.
        assert_eq!(
            provider.resolve("電影").expect("traditional resolves").phonetics[0].text,
            "diàn yǐng"
        );
        // u: becomes ü and carries the tone.
        assert_eq!(provider.resolve("旅行").unwrap().phonetics[0].text, "lǚ xíng");
        // A word absent from the file still resolves from the built-in seed.
        assert_eq!(provider.resolve("咖啡").unwrap().phonetics[0].text, "kā fēi");
    }

    #[test]
    fn japanese_provider_falls_back_to_seed_without_jmdict() {
        // No installed JMdict/EDICT2: lookups come from the built-in seed.
        let provider = JapaneseDictionaryProvider::with_path("/nonexistent/jmdict.data".into());
        let info = provider.info();
        assert_eq!(info.id, "jmdict");
        assert_eq!(info.supported_languages, vec!["ja".to_string()]);
        assert!(info.offline);

        let lookup = provider.resolve("学生").expect("known word resolves");
        assert_eq!(lookup.provider, "jmdict");
        assert_eq!(lookup.phonetics[0].text, "がくせい");
        assert_eq!(lookup.phonetics[0].region.as_deref(), Some("ja"));
        assert_eq!(lookup.definitions[0].text, "student");
        // Unknown words degrade to None rather than borrowing Chinese.
        assert!(provider.resolve("量子力学").is_none());
    }

    #[test]
    fn japanese_provider_reads_installed_edict() {
        let fixture = tempfile::Builder::new()
            .prefix("llplayernext-jmdict-")
            .suffix(".data")
            .tempfile()
            .unwrap();
        {
            use std::io::Write;
            let mut writer = std::io::BufWriter::new(fixture.as_file());
            writeln!(writer, "# JMdict/EDICT2").unwrap();
            writeln!(writer, "頭 [あたま] /(n) head/(P)/EntL1582710X/").unwrap();
            writeln!(writer, "見る;観る [みる] /(v1,vt) to see/to look at/EntL1259290X/").unwrap();
            writeln!(writer, "ありがとう /(int) thank you/EntL1000000X/").unwrap();
            writer.flush().unwrap();
            fixture.as_file().sync_all().unwrap();
        }
        let provider = JapaneseDictionaryProvider::with_path(fixture.path().to_path_buf());

        // Kanji headword: reading and gloss parse; (pos) and EntL are stripped.
        let lookup = provider.resolve("頭").expect("kanji resolves");
        assert_eq!(lookup.provider, "jmdict");
        assert_eq!(lookup.phonetics[0].text, "あたま");
        assert_eq!(lookup.definitions[0].text, "head");
        // Kana reading resolves to the same entry.
        assert_eq!(provider.resolve("あたま").unwrap().definitions[0].text, "head");
        // A ;-separated variant headword resolves; multiple glosses join.
        assert_eq!(
            provider.resolve("観る").unwrap().definitions[0].text,
            "to see; to look at"
        );
        // Kana-only headword carries no separate reading phonetic.
        let thanks = provider.resolve("ありがとう").unwrap();
        assert_eq!(thanks.definitions[0].text, "thank you");
        assert!(thanks.phonetics.is_empty());
        // A word absent from the file still resolves from the built-in seed.
        assert_eq!(provider.resolve("学生").unwrap().phonetics[0].text, "がくせい");
    }

    #[test]
    fn numbered_pinyin_tone_placement_follows_standard_rules() {
        assert_eq!(numbered_pinyin_to_marks("ni3 hao3"), "nǐ hǎo");
        assert_eq!(numbered_pinyin_to_marks("xue2 xi2"), "xué xí");
        assert_eq!(numbered_pinyin_to_marks("dou1"), "dōu"); // ou -> mark o
        assert_eq!(numbered_pinyin_to_marks("guo3"), "guǒ"); // else last vowel
        assert_eq!(numbered_pinyin_to_marks("liu2"), "liú"); // iu -> mark u
        assert_eq!(numbered_pinyin_to_marks("lu:3"), "lǚ"); // u: -> ü
        assert_eq!(numbered_pinyin_to_marks("de5"), "de"); // neutral tone, no mark
    }

    #[test]
    fn free_dictionary_phonetics_preserve_pronunciation_audio() {
        let entry = serde_json::json!({
            "phonetics": [
                {"text": "/həˈloʊ/", "audio": "//example.test/hello-us.mp3"},
                {"text": "/hɛˈləʊ/", "audio": ""}
            ]
        });
        let values = super::parse_free_dictionary_phonetics(&entry);
        assert_eq!(values.len(), 2);
        assert_eq!(
            values[0].audio_url.as_deref(),
            Some("https://example.test/hello-us.mp3")
        );
        assert_eq!(values[1].audio_url, None);
    }

    #[test]
    fn ecdict_phrase_candidates_handle_short_sentences() {
        let mut fixture = fixture();
        let path = fixture.path().to_path_buf();
        use std::io::Write;
        write!(
            fixture,
            "word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio\n\
             piece of cake,,easy task,,,,,,,,,,\n"
        )
        .unwrap();
        fixture.flush().unwrap();
        let provider = EcdictProvider::with_path(path.clone(), "test");
        let sentence = SubtitleSentence {
            id: SubtitleSentenceId::parse("short").unwrap(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1000),
            original_text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: vec![SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "Hello".into(),
                normalized: Some("hello".into()),
                start_char: 0,
                end_char: 5,
            }],
        };
        assert!(
            provider
                .phrase_candidates(&LanguageCode::parse("en").unwrap(), &sentence)
                .unwrap()
                .is_empty()
        );
    }
}
