use serde::{Deserialize, Serialize};

use crate::{SubtitleSentenceId, WordProfileId};

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
    /// Per-language listening-factor possibilities for this hint, drawn from the
    /// learning language's profile (e.g. `tone_confusion`, `word_boundary` for
    /// Chinese; `weak_form`, `linking` for English). These are contextual
    /// possibilities to consider, not detections from the audio. Empty for hints
    /// other than the recognition barrier and for languages declaring none.
    #[serde(default)]
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SentenceDiagnosis {
    pub sentence_id: SubtitleSentenceId,
    pub hints: Vec<DiagnosisHint>,
    pub unclassified_lemmas: Vec<String>,
}
