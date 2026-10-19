// EDICT provider: Japanese dictionary.
// Split out of lib.rs (mechanical decomposition).

use crate::support::ResourceSignature;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use application::{DictionaryProvider, DictionaryProviderError};
use async_trait::async_trait;
use domain::{
    DictionaryDefinition, DictionaryLookup, DictionaryPhonetic, DictionaryProviderInfo,
    LanguageCode,
};
use learning_resource_runtime::learning_resource_path;

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
        Self::with_path(learning_resource_path("jmdict"))
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
        let signature = ResourceSignature::read(&self.path).ok()??;
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
    pub(crate) fn resolve(&self, lemma: &str) -> Option<DictionaryLookup> {
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
