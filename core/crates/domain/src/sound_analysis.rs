use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SoundPhoneEvidence {
    ExpectedOnly,
    ObservedOnly,
    Match,
    Substitution,
    Merge,
    Deletion,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundLearningPhone {
    pub symbol: String,
    pub display_ipa: String,
    pub phone_set: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub confidence: Option<f32>,
    pub token_index: Option<u32>,
    pub observed_phone_index: Option<u32>,
    pub observed_symbol: Option<String>,
    pub evidence: SoundPhoneEvidence,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyllableStress {
    Primary,
    Secondary,
    Unstressed,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundSyllable {
    pub phones: Vec<u32>,
    pub onset: Vec<u32>,
    pub nucleus: Vec<u32>,
    pub coda: Vec<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub stress: SyllableStress,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProsodicBoundaryEvidence {
    SentenceStart,
    Pause,
    TentativeLengthening,
    SentenceEnd,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundProsodicPhrase {
    pub syllables: Vec<u32>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub boundary_evidence: ProsodicBoundaryEvidence,
    pub confidence: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SoundAnalysis {
    pub provider_id: String,
    pub provider_version: String,
    pub model_revision: Option<String>,
    pub phone_set: String,
    pub generated_from: String,
    pub learning_phones: Vec<SoundLearningPhone>,
    pub syllables: Vec<SoundSyllable>,
    pub prosodic_phrases: Vec<SoundProsodicPhrase>,
}
