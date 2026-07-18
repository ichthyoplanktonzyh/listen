use serde::{Deserialize, Serialize};

use crate::{LanguageCode, MediaId, ProductionChannel, SubtitleSentenceId, SubtitleTrackId};

pub const SEMANTIC_INDEX_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EmbeddingPurpose {
    Query,
    Document,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EmbeddingModelDescriptor {
    pub provider_id: String,
    pub model_id: String,
    pub model_version: String,
    pub runtime_version: String,
    pub artifact_sha256: String,
    pub dimension: u32,
    pub normalization: String,
    pub purpose_contract: String,
    pub index_schema_version: u32,
    pub model_fingerprint: String,
    pub local: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticEmbeddingStatus {
    NotInstalled,
    Ready,
    Stale,
    Failed,
    Disabled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SemanticEmbeddingCapability {
    pub status: SemanticEmbeddingStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub descriptor: Option<EmbeddingModelDescriptor>,
    pub indexed_source_count: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub indexed_fingerprint: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SemanticEmbeddingSourceKind {
    MediaCorpus,
    ProductionDocument,
    ProductionLexeme,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SemanticEmbeddingSource {
    pub kind: SemanticEmbeddingSourceKind,
    pub source_id: String,
    pub language: LanguageCode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel: Option<ProductionChannel>,
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub media_id: Option<MediaId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub track_id: Option<SubtitleTrackId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sentence_id: Option<SubtitleSentenceId>,
    #[serde(default)]
    pub start_ms: u64,
    #[serde(default)]
    pub end_ms: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub produced_at_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SemanticEmbeddingIndexRecord {
    pub source_kind: SemanticEmbeddingSourceKind,
    pub source_id: String,
    pub language: LanguageCode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel: Option<ProductionChannel>,
    pub text_sha256: String,
    pub model_fingerprint: String,
    pub dimension: u32,
    pub vector: Vec<f32>,
    pub indexed_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SemanticSearchHit {
    pub source: SemanticEmbeddingSource,
    pub similarity: f32,
    pub model_fingerprint: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SemanticSearchResult {
    pub capability: SemanticEmbeddingCapability,
    pub query: String,
    pub hits: Vec<SemanticSearchHit>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct NearSemanticProductionMatch {
    pub normalized_key: String,
    pub similarity: f32,
    pub model_fingerprint: String,
    pub explanation: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProductionGapSemanticEnrichment {
    pub lexical_entry_id: String,
    pub target_normalized_key: String,
    pub matches: Vec<NearSemanticProductionMatch>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SemanticallyEnrichedProductionGapReview {
    pub review: crate::ProductionGapReview,
    pub semantic_capability: SemanticEmbeddingCapability,
    pub enrichments: Vec<ProductionGapSemanticEnrichment>,
    pub threshold: f32,
}
