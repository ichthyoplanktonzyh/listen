use serde::{Deserialize, Serialize};

use crate::SubtitleSentenceId;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Phoneme {
    pub symbol: String,
    pub phoneme_set: String,
    pub display_ipa: String,
    pub stress: Option<u8>,
    pub syllable_index: Option<u32>,
    pub token_index: Option<u32>,
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
    pub confidence: Option<f32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PronunciationProviderInfo {
    pub id: String,
    pub display_name: String,
    pub version: String,
    pub languages: Vec<String>,
    pub accents: Vec<String>,
    pub phoneme_sets: Vec<String>,
    pub supports_context: bool,
    pub supports_variants: bool,
    pub supports_stress: bool,
    pub supports_token_mapping: bool,
    pub available: bool,
    pub degraded: bool,
    pub diagnostic: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PronunciationVariant {
    pub phonemes: Vec<Phoneme>,
    pub display_ipa: String,
    pub is_fallback: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WordPronunciation {
    pub token_index: u32,
    pub text: String,
    pub normalized: String,
    pub variants: Vec<PronunciationVariant>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpeechRuleStatus {
    PossibleByRule,
    LikelyByContext,
    UserConfirmed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SpeechRuleFinding {
    pub rule_id: String,
    pub rule_family: String,
    pub affected_token_start: u32,
    pub affected_token_end: u32,
    pub canonical_phonemes: Vec<String>,
    pub suggested_phonemes: Vec<String>,
    pub confidence: f32,
    pub reason: String,
    pub evidence_source: String,
    pub status: SpeechRuleStatus,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SentencePronunciation {
    pub sentence_id: SubtitleSentenceId,
    pub language: String,
    pub accent: String,
    pub provider_id: String,
    pub provider_version: String,
    pub phoneme_set: String,
    pub display_ipa: String,
    pub words: Vec<WordPronunciation>,
    pub phonemes: Vec<Phoneme>,
    pub rules: Vec<SpeechRuleFinding>,
}
