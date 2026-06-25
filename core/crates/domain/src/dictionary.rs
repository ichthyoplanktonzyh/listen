use serde::{Deserialize, Serialize};

use crate::{DictionaryEntryId, LanguageCode};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryEntry {
    pub id: DictionaryEntryId,
    pub language: LanguageCode,
    pub normalized_lemma: String,
    pub provider: String,
    pub payload_json: String,
    pub cached_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryDefinition {
    pub part_of_speech: Option<String>,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryPhonetic {
    pub text: String,
    pub region: Option<String>,
    #[serde(default)]
    pub audio_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CharacterBreakdown {
    pub character: String,
    pub phonetic: String,
    pub meaning: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryLookup {
    pub query: String,
    pub lemma: String,
    pub definitions: Vec<DictionaryDefinition>,
    pub phonetics: Vec<DictionaryPhonetic>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub character_breakdowns: Vec<CharacterBreakdown>,
    pub provider: String,
    pub cached_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryProviderInfo {
    pub id: String,
    pub display_name: String,
    pub supported_languages: Vec<String>,
    pub provides_definitions: bool,
    pub provides_phonetics: bool,
    pub provides_audio: bool,
    pub offline: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryProviderResult {
    pub provider: DictionaryProviderInfo,
    pub lookup: Option<DictionaryLookup>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryLookupBundle {
    pub query: String,
    pub normalized_lemma: String,
    pub results: Vec<DictionaryProviderResult>,
}
