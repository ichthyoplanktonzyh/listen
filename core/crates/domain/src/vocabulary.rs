use serde::{Deserialize, Serialize};

use crate::{
    LearningResourceId, LearningStatus, LexicalCapabilityProfile, LexicalEntry,
    LexicalObservation, LexicalOccurrence, LexicalStatusHistory, PhoneticFindingFeedback,
};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VocabularyAssetBundle {
    pub version: u16,
    pub exported_at_ms: u64,
    pub lexical_entries: Vec<LexicalEntry>,
    pub lexical_history: Vec<LexicalStatusHistory>,
    pub lexical_occurrences: Vec<LexicalOccurrence>,
    #[serde(default)]
    pub lexical_observations: Vec<LexicalObservation>,
    #[serde(default)]
    pub phonetic_finding_feedback: Vec<PhoneticFindingFeedback>,
    #[serde(default)]
    pub capability_profiles: Vec<LexicalCapabilityProfile>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExternalVocabularyEntry {
    pub word: String,
    pub status: Option<LearningStatus>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExternalVocabularyImport {
    pub language: String,
    pub entries: Vec<ExternalVocabularyEntry>,
    pub default_status: Option<LearningStatus>,
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
pub enum LearningResourceState {
    Available,
    Installing,
    Installed,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LearningResourceDescriptor {
    pub id: LearningResourceId,
    pub display_name: String,
    pub version: String,
    pub source_url: String,
    pub license: String,
    pub checksum_sha256: String,
    pub size_bytes: u64,
    pub local_path: Option<String>,
    pub state: LearningResourceState,
    pub installed_bytes: u64,
    pub error: Option<String>,
    pub updated_at_ms: u64,
}
