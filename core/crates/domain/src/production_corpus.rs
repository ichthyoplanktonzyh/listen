use serde::{Deserialize, Serialize};

use crate::{
    LanguageCode, MediaId, ProductionCorpusDocumentId, ProductionCorpusEntryId, SemanticRubricId,
    SemanticTaskAttemptId, SemanticTaskKind,
};

/// Which learner-output channel produced a corpus document.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProductionChannel {
    Written,
    Spoken,
}

/// Factual provenance about what surrounded the learner's wording.
///
/// This is deliberately not an `autonomous: bool` verdict. A source
/// reconstruction, a revision, or a prompted response is still learner output;
/// later reviews may weight these facts differently without rewriting them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProductionAssistance {
    /// A response to source meaning, without a claim that exact wording was
    /// supplied (summary/opinion tasks in Phase 3.15).
    ContentAnchored,
    /// A reconstruction after hearing/reading source wording (dictogloss).
    SourceReconstruction,
    /// A later learner-authored revision of an earlier response.
    LearnerRevision,
    /// A specific target expression was shown or requested.
    ExplicitTarget,
    /// A model suggestion was available while composing this wording.
    ModelSuggested,
    /// The occurrence is a direct imitation/echo of supplied wording.
    DirectImitation,
    /// Provenance was not captured strongly enough to classify.
    Unknown,
}

/// One learner response revision in the rebuildable production corpus.
///
/// The response text is stored once here; token occurrences below cite spans
/// instead of duplicating the complete response for every word.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProductionCorpusDocument {
    pub id: ProductionCorpusDocumentId,
    pub language: LanguageCode,
    pub channel: ProductionChannel,
    pub assistance: ProductionAssistance,
    pub attempt_id: SemanticTaskAttemptId,
    pub rubric_id: SemanticRubricId,
    pub response_revision: u32,
    pub task_kind: SemanticTaskKind,
    pub media_id: Option<MediaId>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub response_text: String,
    pub produced_at_ms: u64,
}

/// One lemma-keyed token occurrence inside a production document.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProductionCorpusEntry {
    pub id: ProductionCorpusEntryId,
    pub document_id: ProductionCorpusDocumentId,
    pub normalized_key: String,
    pub display_text: String,
    /// Unicode-scalar half-open span in `ProductionCorpusDocument.response_text`.
    pub start_char: u32,
    pub end_char: u32,
}

/// Read model returned by lemma/FTS queries. `entry` is absent for a phrase
/// document hit and present for an exact lemma occurrence.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProductionCorpusHit {
    pub document: ProductionCorpusDocument,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub entry: Option<ProductionCorpusEntry>,
}
