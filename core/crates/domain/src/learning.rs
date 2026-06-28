use serde::{Deserialize, Serialize};

use crate::{
    LanguageCode, LexicalEntryId, LexicalObservationId, LexicalOccurrenceId,
    LexicalStatusHistoryId, LexicalUnit, MediaId, SubtitleSentenceId,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningStatus {
    UnknownMeaning,
    KnownNotRecognized,
    KnownRecognized,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObservationResult {
    RecognizedInContext,
    NotRecognizedInContext,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningChangeSource {
    UserSelection,
    Import,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LexicalEntryKind {
    Word,
    Phrase,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalEntry {
    pub id: LexicalEntryId,
    /// Authoritative cross-language identity for this learning asset.
    pub unit: LexicalUnit,
    pub language: LanguageCode,
    pub kind: LexicalEntryKind,
    pub canonical_form: String,
    pub normalized_form: String,
    pub display_form: String,
    pub status: Option<LearningStatus>,
    pub user_definition: Option<String>,
    pub personal_note: Option<String>,
    pub normalization_provider: String,
    pub normalization_version: String,
    pub user_corrected: bool,
    pub updated_at_ms: u64,
    pub learning_updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalOccurrence {
    pub id: LexicalOccurrenceId,
    pub source_key: String,
    pub lexical_entry_id: LexicalEntryId,
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text_snapshot: String,
    pub media_title_snapshot: String,
    pub media_fingerprint_snapshot: String,
    pub start_ms_snapshot: u64,
    pub end_ms_snapshot: u64,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub first_seen_at_ms: u64,
    pub last_seen_at_ms: u64,
    pub encounter_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalStatusHistory {
    pub id: LexicalStatusHistoryId,
    pub lexical_entry_id: LexicalEntryId,
    pub previous_status: Option<LearningStatus>,
    pub new_status: Option<LearningStatus>,
    pub changed_at_ms: u64,
    pub change_source: LearningChangeSource,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalObservation {
    pub id: LexicalObservationId,
    pub lexical_entry_id: LexicalEntryId,
    pub sentence_id: SubtitleSentenceId,
    pub original_form: String,
    pub result: ObservationResult,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalEntryDetails {
    pub entry: LexicalEntry,
    pub history: Vec<LexicalStatusHistory>,
    pub occurrences: Vec<LexicalOccurrence>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PhraseCandidate {
    pub canonical_form: String,
    pub display_form: String,
    pub normalized_form: String,
    pub token_start: u32,
    pub token_end: u32,
    pub reason: String,
}
