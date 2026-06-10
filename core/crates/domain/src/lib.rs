use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

macro_rules! string_id {
    ($name:ident) => {
        #[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
        #[serde(transparent)]
        pub struct $name(String);

        impl $name {
            pub fn parse(value: impl Into<String>) -> Result<Self, DomainError> {
                let value = value.into();
                if value.trim().is_empty() {
                    return Err(DomainError::EmptyValue(stringify!($name)));
                }
                Ok(Self(value))
            }

            pub fn from_fingerprint(namespace: &str, fingerprint: &str) -> Self {
                let digest = Sha256::digest(format!("{namespace}:{fingerprint}"));
                Self(hex::encode(digest))
            }

            pub fn as_str(&self) -> &str {
                &self.0
            }
        }
    };
}

string_id!(MediaId);
string_id!(SubtitleTrackId);
string_id!(SubtitleSentenceId);
string_id!(WordProfileId);
string_id!(WordObservationId);
string_id!(WordOccurrenceId);
string_id!(WordStatusHistoryId);
string_id!(DictionaryEntryId);

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct TimeMs(u64);

impl TimeMs {
    pub const ZERO: Self = Self(0);
    pub const fn new(value: u64) -> Self {
        Self(value)
    }
    pub const fn get(self) -> u64 {
        self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct LanguageCode(String);

impl LanguageCode {
    pub fn parse(value: impl Into<String>) -> Result<Self, DomainError> {
        let value = value.into().trim().to_ascii_lowercase();
        if value.is_empty() {
            return Err(DomainError::EmptyValue("LanguageCode"));
        }
        if !value.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
            return Err(DomainError::InvalidLanguageCode);
        }
        Ok(Self(value))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Video,
    Audio,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaAvailability {
    Available,
    Missing,
    Archived,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaItem {
    pub id: MediaId,
    pub path: String,
    pub fingerprint: String,
    pub title: String,
    pub kind: MediaKind,
    pub duration: Option<TimeMs>,
    pub availability: MediaAvailability,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleTrack {
    pub id: SubtitleTrackId,
    pub media_id: MediaId,
    pub fingerprint: String,
    pub language: Option<LanguageCode>,
    pub source: String,
    pub sentences: Vec<SubtitleSentence>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleSentence {
    pub id: SubtitleSentenceId,
    pub index: u32,
    pub start: TimeMs,
    pub end: TimeMs,
    pub original_text: String,
    pub display_text: String,
    pub tokens: Vec<SubtitleToken>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SubtitleTokenKind {
    Word,
    Whitespace,
    Punctuation,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleToken {
    pub index: u32,
    pub kind: SubtitleTokenKind,
    pub text: String,
    pub normalized: Option<String>,
    pub start_char: u32,
    pub end_char: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WordStatus {
    UnknownMeaning,
    KnownNotRecognized,
    KnownRecognized,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordProfile {
    pub id: WordProfileId,
    pub language: LanguageCode,
    pub lemma: String,
    pub normalized_lemma: String,
    pub display_form: String,
    pub status: Option<WordStatus>,
    pub updated_at_ms: u64,
    #[serde(default)]
    pub user_definition: Option<String>,
    #[serde(default)]
    pub personal_note: Option<String>,
    #[serde(default)]
    pub learning_updated_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObservationResult {
    RecognizedInContext,
    NotRecognizedInContext,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordObservation {
    pub id: WordObservationId,
    pub word_profile_id: WordProfileId,
    pub sentence_id: SubtitleSentenceId,
    pub original_form: String,
    pub result: ObservationResult,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordOccurrence {
    pub id: WordOccurrenceId,
    pub source_key: String,
    pub word_profile_id: WordProfileId,
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text_snapshot: String,
    pub media_title_snapshot: String,
    pub media_fingerprint_snapshot: String,
    pub start_ms_snapshot: u64,
    pub end_ms_snapshot: u64,
    pub first_seen_at_ms: u64,
    pub last_seen_at_ms: u64,
    pub encounter_count: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WordChangeSource {
    UserSelection,
    Import,
    LegacyBaseline,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordStatusHistory {
    pub id: WordStatusHistoryId,
    pub word_profile_id: WordProfileId,
    pub previous_status: Option<WordStatus>,
    pub new_status: Option<WordStatus>,
    pub source_occurrence_id: Option<WordOccurrenceId>,
    pub changed_at_ms: u64,
    pub change_source: WordChangeSource,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordDetails {
    pub profile: WordProfile,
    pub history: Vec<WordStatusHistory>,
    pub occurrences: Vec<WordOccurrence>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VocabularyAssetBundle {
    pub version: u16,
    pub exported_at_ms: u64,
    pub profiles: Vec<WordProfile>,
    pub history: Vec<WordStatusHistory>,
    pub occurrences: Vec<WordOccurrence>,
    pub observations: Vec<WordObservation>,
}

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
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryLookup {
    pub query: String,
    pub lemma: String,
    pub definitions: Vec<DictionaryDefinition>,
    pub phonetics: Vec<DictionaryPhonetic>,
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExternalVocabularyEntry {
    pub word: String,
    pub status: Option<WordStatus>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExternalVocabularyImport {
    pub language: String,
    pub entries: Vec<ExternalVocabularyEntry>,
    pub default_status: Option<WordStatus>,
    pub overwrite_existing: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ExternalVocabularyImportSummary {
    pub created: u64,
    pub initialized: u64,
    pub skipped: u64,
    pub overwritten: u64,
    pub invalid: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DiagnosisKind {
    MeaningBarrier,
    RecognitionBarrier,
    InsufficientInformation,
    OtherFactors,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiagnosisHint {
    pub kind: DiagnosisKind,
    pub message: String,
    pub word_profile_ids: Vec<WordProfileId>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SentenceDiagnosis {
    pub sentence_id: SubtitleSentenceId,
    pub hints: Vec<DiagnosisHint>,
    pub unclassified_lemmas: Vec<String>,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum DomainError {
    #[error("{0} must not be empty")]
    EmptyValue(&'static str),
    #[error("language code contains unsupported characters")]
    InvalidLanguageCode,
}

pub fn normalize_lemma(value: &str) -> String {
    value.trim().to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fingerprint_ids_are_stable_and_namespaced() {
        assert_eq!(
            MediaId::from_fingerprint("media", "abc"),
            MediaId::from_fingerprint("media", "abc")
        );
        assert_ne!(
            MediaId::from_fingerprint("media", "abc").as_str(),
            MediaId::from_fingerprint("other", "abc").as_str()
        );
    }

    #[test]
    fn language_codes_are_normalized() {
        assert_eq!(LanguageCode::parse("EN-us").unwrap().as_str(), "en-us");
    }

    #[test]
    fn lemma_normalization_is_stable() {
        assert_eq!(normalize_lemma("  Can't  "), "can't");
    }
}
