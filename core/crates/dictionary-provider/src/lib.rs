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
    DictionaryDefinition, DictionaryLookup, DictionaryPhonetic, DictionaryProviderInfo,
    LanguageCode, PhraseCandidate, SubtitleSentence, SubtitleTokenKind, normalize_lemma,
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
            provider: "ecdict".into(),
            cached_at_ms: 0,
        }))
    }
}

/// Minimal built-in Mandarin dictionary for the Phase 2.6 English + Chinese
/// acceptance set. Each entry carries tone-marked pinyin (the `zh` profile
/// declares `zh.pinyin` + `zh.tone`) and a short gloss, so clicking a Chinese
/// token shows pronunciation and meaning out of the box without installing a
/// resource. It plugs in behind the same `DictionaryProvider` interface as the
/// English providers and is selected purely by `supported_languages`, so a
/// licensed CC-CEDICT-scale source can replace this seed set later without
/// touching any call site. Lookups are exact on the (already normalized) lemma;
/// an unknown word returns `None`, which the dispatcher degrades cleanly.
pub struct ChineseDictionaryProvider {
    entries: HashMap<&'static str, (&'static str, &'static str)>,
}

/// `(word, tone_marked_pinyin, gloss)`. Covers the tokenizer fixtures
/// (我/想/喝/咖啡, plus mixed-sentence neighbours) and common greetings so the
/// click-to-meaning path is demonstrable and testable.
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

impl ChineseDictionaryProvider {
    pub fn new() -> Self {
        Self {
            entries: CHINESE_DICTIONARY_SEED
                .iter()
                .map(|(word, pinyin, gloss)| (*word, (*pinyin, *gloss)))
                .collect(),
        }
    }
}

impl Default for ChineseDictionaryProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl ChineseDictionaryProvider {
    /// Synchronous lookup core (the table is in memory, so the trait's async
    /// `lookup` just wraps this). Kept separate so it is testable without an
    /// async runtime.
    fn resolve(&self, lemma: &str) -> Option<DictionaryLookup> {
        let (pinyin, gloss) = self.entries.get(lemma)?;
        Some(DictionaryLookup {
            query: lemma.to_owned(),
            lemma: lemma.to_owned(),
            definitions: vec![DictionaryDefinition {
                part_of_speech: None,
                text: (*gloss).to_owned(),
            }],
            phonetics: vec![DictionaryPhonetic {
                text: (*pinyin).to_owned(),
                region: Some("zh".into()),
                audio_url: None,
            }],
            provider: "chinese-builtin".into(),
            cached_at_ms: 0,
        })
    }
}

#[async_trait]
impl DictionaryProvider for ChineseDictionaryProvider {
    fn info(&self) -> DictionaryProviderInfo {
        DictionaryProviderInfo {
            id: "chinese-builtin".into(),
            display_name: "Chinese (built-in)".into(),
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
    fn chinese_provider_returns_pinyin_and_gloss_for_known_words() {
        let provider = ChineseDictionaryProvider::new();
        let info = provider.info();
        assert_eq!(info.supported_languages, vec!["zh".to_string()]);
        assert!(info.offline);

        let lookup = provider.resolve("咖啡").expect("known word resolves");
        assert_eq!(lookup.provider, "chinese-builtin");
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
