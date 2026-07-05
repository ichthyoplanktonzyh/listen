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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SentenceChunkPartition {
    pub sentence_id: SubtitleSentenceId,
    pub chunks: Vec<DisplayChunk>,
    pub partitioner_id: String,
    pub partitioner_version: String,
    pub timing_quality: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DisplayChunk {
    pub index: u32,
    pub token_start: u32,
    pub token_end: u32,
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub boundary_after: Option<DisplayChunkBoundary>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DisplayChunkBoundary {
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub score: f32,
    pub primary_source: String,
    pub evidence: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BoundaryDiagnostic {
    pub left_token_index: u32,
    pub right_token_index: u32,
    pub raw_score: f32,
    pub selection_threshold: f32,
    pub selected: bool,
    pub forced: bool,
    pub primary_source: Option<String>,
    pub evidence: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SentenceChunkDiagnostics {
    pub partition: SentenceChunkPartition,
    pub candidates: Vec<BoundaryDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearnedProsodicProviderInfo {
    pub provider_id: String,
    pub model_revision: String,
    pub license: String,
    pub runtime: String,
    pub available: bool,
    pub optional: bool,
    pub diagnostic: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CreateWordTimeline {
    pub algorithm_id: Option<String>,
    pub algorithm_version: Option<String>,
    pub config_hash: Option<String>,
    pub parent_timeline_id: Option<WordTimelineId>,
    pub created_by: Option<TimelineCreator>,
    pub status: Option<TimelineStatus>,
    pub metrics_json: Option<TimelineMetrics>,
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
    pub acoustic_cue_count: usize,
    pub energy_prominence_cue_count: usize,
    pub pitch_prominence_cue_count: usize,
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
pub struct CreateLexicalObservation {
    pub lexical_entry_id: LexicalEntryId,
    pub sentence_id: SubtitleSentenceId,
    pub original_form: String,
    pub result: ObservationResult,
    pub source: Option<LexicalSourceContext>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreatePracticeSession {
    pub mode: PracticeMode,
    pub media_id: Option<MediaId>,
    pub track_id: Option<SubtitleTrackId>,
    pub source: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreatePracticeItem {
    pub session_id: Option<PracticeSessionId>,
    pub kind: PracticeKind,
    pub target: PracticeTarget,
    pub prompt_snapshot: String,
    pub expected_text: String,
    pub anchors: Vec<PracticeAnchor>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubmitPracticeAttempt {
    pub item_id: PracticeItemId,
    pub text_answer: String,
    pub create_review_item_on_failure: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateReviewItem {
    pub source: ReviewSource,
    pub anchors: Vec<PracticeAnchor>,
    pub prompt_snapshot: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewQueueEntry {
    pub item: ReviewItem,
    pub schedule: ReviewSchedule,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubmitReviewAttempt {
    pub item_id: ReviewItemId,
    pub rating: ReviewRating,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewSubmission {
    pub attempt: ReviewAttempt,
    pub schedule: ReviewSchedule,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DiagnosisHintEvidence {
    pub kind: String,
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordStuckPointInput {
    pub session_id: PracticeSessionId,
    pub target: PracticeTarget,
    pub anchors: Vec<PracticeAnchor>,
    pub label: Option<String>,
    #[serde(default)]
    pub diagnosis_hints: Vec<DiagnosisHintEvidence>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordDiagnosisViewInput {
    pub session_id: PracticeSessionId,
    pub target: PracticeTarget,
    pub anchors: Vec<PracticeAnchor>,
    pub label: Option<String>,
    #[serde(default)]
    pub diagnosis_hints: Vec<DiagnosisHintEvidence>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CloseStuckPointInput {
    pub session_id: PracticeSessionId,
    pub target_key: String,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompletePracticeSessionInput {
    #[serde(default = "default_mark_familiar")]
    pub mark_familiar: bool,
    #[serde(default)]
    pub comprehension_report: Option<ListeningComprehensionReport>,
}

fn default_mark_familiar() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureListeningInboxItemInput {
    pub session_id: PracticeSessionId,
    pub target: PracticeTarget,
    pub anchors: Vec<PracticeAnchor>,
    pub label: Option<String>,
    pub subtitle_snapshot: String,
    pub context_before: Option<String>,
    pub context_after: Option<String>,
    #[serde(default)]
    pub expires_in_days: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProcessListeningInboxItemInput {
    pub resolution: ListeningInboxResolution,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StuckPointStatus {
    Marked,
    ResolvedWithHint,
    ActivelyVerified,
    AddedToReview,
    Skipped,
    Unexplained,
    Closed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StuckPointSummary {
    pub target_key: String,
    pub status: StuckPointStatus,
    pub target: Option<PracticeTarget>,
    pub anchors: Vec<PracticeAnchor>,
    pub label: Option<String>,
    pub marked_at_ms: Option<u64>,
    pub updated_at_ms: u64,
    pub playback_start_ms: Option<u64>,
    pub playback_end_ms: Option<u64>,
    pub practice_attempt_ids: Vec<PracticeAttemptId>,
    pub review_item_ids: Vec<ReviewItemId>,
    pub diagnosis_hints: Vec<DiagnosisHintEvidence>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StuckPointAttribution {
    pub kind: String,
    pub reason: Option<String>,
    pub count: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PracticeSessionSummary {
    pub session: PracticeSession,
    pub stuck_points: Vec<StuckPointSummary>,
    pub stuck_count: u32,
    pub resolved_count: u32,
    pub active_verified_count: u32,
    pub review_count: u32,
    pub unexplained_count: u32,
    pub skipped_count: u32,
    pub closed_count: u32,
    pub open_count: u32,
    pub attribution_counts: Vec<StuckPointAttribution>,
    pub familiar_material_marked: bool,
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
    pub status: Option<LearningStatus>,
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
