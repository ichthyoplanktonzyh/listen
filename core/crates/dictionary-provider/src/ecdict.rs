// ECDICT CSV provider: EN-ZH dictionary and lexical normalization.
// Split out of lib.rs (mechanical decomposition).

use crate::support::ResourceSignature;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use application::{
    DictionaryProvider, DictionaryProviderError, LexicalNormalizationProvider,
    LexicalNormalizationProviderError,
};
use async_trait::async_trait;
use domain::{
    DictionaryDefinition, DictionaryLookup, DictionaryPhonetic, DictionaryProviderInfo,
    LanguageCode, PhraseCandidate, SubtitleSentence, SubtitleTokenKind, normalize_lemma,
};

pub struct EcdictProvider {
    path: PathBuf,
    version: String,
    index: Mutex<Option<(ResourceSignature, Arc<EcdictIndex>)>>,
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
    bnc_rank: Option<u32>,
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

    fn frequency_rank(&self, language: &LanguageCode, lemma: &str) -> Option<u32> {
        if !language.as_str().starts_with("en") {
            return None;
        }
        let index = self.load_index().ok()??;
        let query = normalize_lemma(lemma);
        let normalized = index.lemmas.get(&query).unwrap_or(&query);
        index.dictionary.get(normalized)?.bnc_rank
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
    let bnc_column = column("bnc", 8);
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
                bnc_rank: record
                    .get(bnc_column)
                    .and_then(|value| value.parse::<u32>().ok())
                    .filter(|rank| *rank > 0),
            },
        );
    }
    Ok(index)
}
