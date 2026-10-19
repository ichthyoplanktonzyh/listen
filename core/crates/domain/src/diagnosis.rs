use serde::{Deserialize, Serialize};

use crate::{LanguageCode, LexicalEntryId, SubtitleSentenceId};

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
    pub lexical_entry_ids: Vec<LexicalEntryId>,
    /// Per-language listening-factor possibilities for this hint, drawn from the
    /// learning language's profile (e.g. `tone_confusion`, `word_boundary` for
    /// Chinese; `weak_form`, `linking` for English). These are contextual
    /// possibilities to consider, not detections from the audio. Empty for hints
    /// other than the recognition barrier and for languages declaring none.
    #[serde(default)]
    pub reasons: Vec<String>,
}

/// A replayable audio span backing one L1 difficulty hint (Phase 3.9). Spans
/// come from the sentence's own rhythm frame, so "listen again" always lands
/// on real audio — a hint without spans must not be produced.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct L1DiagnosisSpan {
    /// Evidence family key, e.g. `rhythm.weak_group`, `cs.deletion`.
    pub family: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub surface_text: String,
}

/// A short L1-transfer possibility attached to a diagnosed sentence when the
/// learner declared an L1 and the (L1, L2) pair has a difficulty profile.
/// Like `DiagnosisHint.reasons`, these are possibilities to consider and
/// replay, never detections about this learner.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct L1DiagnosisHint {
    /// Stable difficulty category id (e.g. `weak_function_words`); clients
    /// localize wording by this id.
    pub difficulty_kind: String,
    /// Neutral English reference explanation from the difficulty profile.
    pub message: String,
    pub families: Vec<String>,
    pub spans: Vec<L1DiagnosisSpan>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum L1DiagnosisSupport {
    Supported,
    /// The learner declared an L1 but no difficulty profile exists for this
    /// (L1, L2) pair; clients show a language-neutral note, never generic
    /// stereotype content.
    UnsupportedPair,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct L1DiagnosisContext {
    pub l1: LanguageCode,
    pub l2: LanguageCode,
    pub support: L1DiagnosisSupport,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SentenceDiagnosis {
    pub sentence_id: SubtitleSentenceId,
    pub hints: Vec<DiagnosisHint>,
    pub unclassified_lemmas: Vec<String>,
    /// L1-aware additions (Phase 3.9). Both stay empty/absent when the
    /// learner never set an L1, keeping baseline diagnosis byte-identical.
    #[serde(default)]
    pub l1_hints: Vec<L1DiagnosisHint>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub l1_context: Option<L1DiagnosisContext>,
}
