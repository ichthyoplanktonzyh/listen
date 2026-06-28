use serde::{Deserialize, Serialize};

use crate::{
    ChunkId, LanguageCode, LearningStatus, LexicalEntryId, LexicalObservationId, MediaId,
    PracticeAttemptId, PracticeItemId, PracticeSessionId, RecordingAssetId, ReviewAttemptId,
    ReviewItemId, SubtitleSentenceId, SubtitleTrackId,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PracticeMode {
    Intensive,
    Extensive,
    Review,
    Specialty,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PracticeKind {
    Cloze,
    Dictation,
    SubtitleFade,
    Shadowing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PracticeTargetKind {
    Lexical,
    Sentence,
    Chunk,
    Segment,
    ConnectedSpeech,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PracticeAnchorKind {
    LexicalEntry,
    Sentence,
    WordTimeline,
    ChunkTimeline,
    Chunk,
    PhoneTimeline,
    Phone,
    ConnectedSpeech,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PracticeResult {
    Correct,
    Partial,
    Incorrect,
    Skipped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PracticeTokenResult {
    Correct,
    Missing,
    Extra,
    Mismatch,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewSourceKind {
    LexicalEntry,
    PracticeFailure,
    Chunk,
    Sentence,
    ConnectedSpeech,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewItemStatus {
    Active,
    Suspended,
    Archived,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewRating {
    Again,
    Hard,
    Good,
    Easy,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningEventKind {
    ListeningStarted,
    ListeningCompleted,
    PracticeCompleted,
    ReviewCompleted,
    StatusChanged,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningEventSubjectKind {
    Media,
    Sentence,
    Chunk,
    LexicalEntry,
    ReviewItem,
    PracticeAttempt,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CorpusOccurrenceKind {
    Lexical,
    Phrase,
    Chunk,
    SoundPattern,
    ConnectedSpeech,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlayableSegmentAvailability {
    Available,
    MissingMedia,
    MissingTimeline,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum InputFit {
    TooEasy,
    Comprehensible,
    Challenging,
    TooHard,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PracticeSession {
    pub id: PracticeSessionId,
    pub mode: PracticeMode,
    pub media_id: Option<MediaId>,
    pub track_id: Option<SubtitleTrackId>,
    pub source: String,
    pub started_at_ms: u64,
    pub ended_at_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PracticeTarget {
    pub kind: PracticeTargetKind,
    pub id: Option<String>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub chunk_id: Option<ChunkId>,
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PracticeAnchor {
    pub kind: PracticeAnchorKind,
    pub id: String,
    pub label: Option<String>,
    pub lexical_entry_id: Option<LexicalEntryId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PracticeItem {
    pub id: PracticeItemId,
    pub session_id: Option<PracticeSessionId>,
    pub kind: PracticeKind,
    pub target: PracticeTarget,
    pub prompt_snapshot: String,
    pub expected_answer: serde_json::Value,
    pub anchors: Vec<PracticeAnchor>,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PracticeTokenEvaluation {
    pub expected: Option<String>,
    pub actual: Option<String>,
    pub result: PracticeTokenResult,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PracticeEvaluation {
    pub summary: String,
    pub token_results: Vec<PracticeTokenEvaluation>,
    pub extra: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PracticeAttempt {
    pub id: PracticeAttemptId,
    pub item_id: PracticeItemId,
    pub submitted_at_ms: u64,
    pub input: serde_json::Value,
    pub result: PracticeResult,
    pub score: Option<f32>,
    pub evaluation: PracticeEvaluation,
    pub generated_observation_ids: Vec<LexicalObservationId>,
    pub generated_review_item_ids: Vec<ReviewItemId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReviewSource {
    pub kind: ReviewSourceKind,
    pub id: Option<String>,
    pub practice_attempt_id: Option<PracticeAttemptId>,
    pub lexical_entry_id: Option<LexicalEntryId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReviewItem {
    pub id: ReviewItemId,
    pub source: ReviewSource,
    pub anchors: Vec<PracticeAnchor>,
    pub prompt_snapshot: String,
    pub status: ReviewItemStatus,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReviewSchedule {
    pub item_id: ReviewItemId,
    pub algorithm: String,
    pub due_at_ms: u64,
    pub stability: Option<f32>,
    pub difficulty: Option<f32>,
    pub interval_days: Option<f32>,
    pub lapse_count: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReviewAttempt {
    pub id: ReviewAttemptId,
    pub item_id: ReviewItemId,
    pub reviewed_at_ms: u64,
    pub rating: ReviewRating,
    pub practice_attempt_id: Option<PracticeAttemptId>,
    pub next_due_at_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearningEventSubject {
    pub kind: LearningEventSubjectKind,
    pub id: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearningEvent {
    pub id: crate::LearningEventId,
    pub occurred_at_ms: u64,
    pub kind: LearningEventKind,
    pub subject: LearningEventSubject,
    pub payload: serde_json::Value,
    pub session_id: Option<PracticeSessionId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CorpusOccurrence {
    pub id: crate::CorpusOccurrenceId,
    pub language: LanguageCode,
    pub kind: CorpusOccurrenceKind,
    pub normalized_key: Option<String>,
    pub display_text: String,
    pub media_id: Option<MediaId>,
    pub track_id: Option<SubtitleTrackId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub source_snapshot: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PlayableSegment {
    pub media_id: Option<MediaId>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub subtitle_snapshot: String,
    pub availability: PlayableSegmentAvailability,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContentDifficultyProfile {
    pub subject_kind: String,
    pub subject_id: String,
    pub language: LanguageCode,
    pub unknown_density: f32,
    pub known_not_recognized_density: f32,
    pub speech_rate_wpm: Option<f32>,
    pub chunk_complexity: Option<f32>,
    pub connected_speech_density: Option<f32>,
    pub resource_quality: Option<f32>,
    pub fit: InputFit,
    pub computed_at_ms: u64,
    pub input_fingerprint: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearnerProfile {
    pub id: crate::LearnerProfileId,
    pub ui_language: LanguageCode,
    pub l1_language: Option<LanguageCode>,
    pub active_l2_language: Option<LanguageCode>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct L1L2DifficultyProfile {
    pub l1: LanguageCode,
    pub l2: LanguageCode,
    pub difficulty_kinds: Vec<String>,
    pub explanation_templates: serde_json::Value,
    pub specialty_query_rules: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecordingAsset {
    pub id: RecordingAssetId,
    pub file_path: String,
    pub created_at_ms: u64,
    pub duration_ms: u64,
    pub practice_attempt_id: Option<PracticeAttemptId>,
    pub target: PracticeTarget,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingComparison {
    pub attempt_id: PracticeAttemptId,
    pub reference_segment: PlayableSegment,
    pub recording_id: RecordingAssetId,
    pub duration_delta_ms: Option<i64>,
    pub pause_alignment: Option<serde_json::Value>,
    pub waveform_summary: Option<serde_json::Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LexicalStatusPracticeEvidence {
    pub lexical_entry_id: LexicalEntryId,
    pub previous_status: Option<LearningStatus>,
    pub suggested_status: Option<LearningStatus>,
    pub practice_attempt_id: PracticeAttemptId,
}
