use std::path::PathBuf;

use domain::*;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SentenceWordTimingDiagnostics {
    pub sentence_id: SubtitleSentenceId,
    pub boundaries: Vec<WordTimingBoundaryDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WordTimingBoundaryDiagnostic {
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub left_end_ms: u64,
    pub right_start_ms: u64,
    pub gap_ms: u64,
    pub left_timing_source: TimingSource,
    pub right_timing_source: TimingSource,
    pub left_provider_id: String,
    pub left_provider_version: String,
    pub right_provider_id: String,
    pub right_provider_version: String,
}

pub type SentenceChunkPartition = speech_analysis::chunk_partition::SentenceChunkPartition;
pub type SentenceChunkDiagnostics = speech_analysis::chunk_partition::SentenceChunkDiagnostics;
pub type LearnedProsodicProviderInfo =
    speech_analysis::learned_prosodic_provider::LearnedProsodicProviderInfo;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CreateWordTimeline {
    pub algorithm_id: Option<String>,
    pub algorithm_version: Option<String>,
    pub config_hash: Option<String>,
    pub parent_timeline_id: Option<WordTimelineId>,
    pub created_by: Option<TimelineCreator>,
    pub status: Option<TimelineStatus>,
    pub metrics_json: Option<serde_json::Value>,
    pub words: Vec<WordTiming>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ForcedAlignSidecar {
    pub python: PathBuf,
    pub script: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordTimelinePipelineResult {
    pub extracted_word_count: usize,
    pub forced_aligned_word_count: usize,
    pub dtw_timeline_id: Option<WordTimelineId>,
    pub forced_aligned_timeline_id: Option<WordTimelineId>,
    pub final_timeline_id: Option<WordTimelineId>,
    pub stored_legacy_word_timings: bool,
}

#[derive(Debug, Clone)]
pub struct RegisterMedia {
    pub path: String,
    pub fingerprint: String,
    pub title: String,
    pub kind: MediaKind,
    pub duration_ms: Option<u64>,
}

#[derive(Debug, Clone)]
pub struct UpdateWordProfile {
    pub language: String,
    pub lemma: String,
    pub display_form: String,
    pub status: Option<WordStatus>,
    pub source: Option<SourceContext>,
}

#[derive(Debug, Clone)]
pub struct CreateWordObservation {
    pub word_profile_id: WordProfileId,
    pub sentence_id: SubtitleSentenceId,
    pub original_form: String,
    pub result: ObservationResult,
    pub source: Option<SourceContext>,
}

#[derive(Debug, Clone)]
pub struct SourceContext {
    pub language: LanguageCode,
    pub normalized_lemma: String,
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text: String,
    pub media_title: String,
    pub media_fingerprint: String,
    pub start_ms: u64,
    pub end_ms: u64,
}

#[derive(Debug, Clone)]
pub struct LexicalSourceContext {
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text: String,
    pub media_title: String,
    pub media_fingerprint: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct UpsertLexicalEntry {
    pub language: String,
    pub kind: LexicalEntryKind,
    pub canonical_form: String,
    pub display_form: String,
    pub status: Option<WordStatus>,
    pub user_definition: Option<String>,
    pub personal_note: Option<String>,
    pub source: Option<LexicalSourceContext>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LexicalNormalization {
    pub original: String,
    pub normalized: String,
    pub provider: String,
    pub version: String,
    pub user_corrected: bool,
}

#[derive(Debug, Clone)]
pub struct ImportSubtitle {
    pub media_id: MediaId,
    pub source_name: String,
    pub content: Vec<u8>,
    pub language: Option<String>,
    pub identity_salt: Option<String>,
}
