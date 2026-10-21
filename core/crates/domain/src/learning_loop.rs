use serde::{Deserialize, Serialize};

use crate::{
    HuntingTargetId, LanguageCode, LearningStatus, LexicalEntryId, LexicalObservationId,
    ListeningInboxItemId, MediaId, PracticeAttemptId, PracticeItemId, PracticeSessionId,
    ReviewAttemptId, ReviewItemId, SubtitleSentenceId, SubtitleTrackId,
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
    /// The activity finished without an objective evaluation. This is a
    /// durable completion fact, not capability evidence.
    Completed,
    Skipped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PracticeTokenResult {
    Correct,
    /// Surface forms differ but a configured language provider resolves both
    /// single tokens to the same lemma (e.g. "goes" ≈ "go"). Scores as correct
    /// but remains distinguishable in the evaluation trace.
    Equivalent,
    Missing,
    Extra,
    Mismatch,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewSourceKind {
    LexicalEntry,
    PracticeFailure,
    ListeningInbox,
    Chunk,
    Sentence,
    ConnectedSpeech,
    SpeakingAttempt,
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

/// FSRS card states, derived from the schedule facts stored by the listening
/// review queue.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewCardState {
    New,
    Learning,
    Review,
    Relearning,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HuntingTargetSourceKind {
    Manual,
    ListeningInbox,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HuntingTargetStatus {
    Active,
    Archived,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningEventKind {
    ListeningStarted,
    ListeningCompleted,
    PracticeCompleted,
    ReviewCompleted,
    StatusChanged,
    StuckPointMarked,
    StuckPointSkipped,
    DiagnosisViewed,
    StuckPointClosed,
    ListeningInboxCaptured,
    ListeningInboxProcessed,
    HuntingCheckAnswered,
    /// A diagnosed sentence hit an L1 difficulty category (Phase 3.9). Event
    /// ids fingerprint (sentence, category) so repeats are idempotent: the
    /// durable record reads "this sentence tripped this category", feeding
    /// the 3.10 difficulty-distribution stats.
    L1DifficultyHit,
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
    PracticeSession,
    ListeningInboxItem,
    HuntingTarget,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HuntingCheckAnswer {
    Recognized,
    NotRecognized,
    NotNoticed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ListeningComprehensionReport {
    UnderstoodAll,
    GotTheGist,
    Unclear,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ListeningInboxStatus {
    Active,
    Archived,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ListeningInboxResolution {
    ReviewItem,
    MicroIntensive,
    Favorite,
    Dismissed,
    Expired,
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
    #[serde(default)]
    pub media_id: Option<MediaId>,
    #[serde(default)]
    pub track_id: Option<SubtitleTrackId>,
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
    /// Timestamp of the review that produced this schedule. Older schedules
    /// omit it and are migrated from their existing due/interval facts.
    #[serde(default)]
    pub last_reviewed_at_ms: Option<u64>,
    /// Number of completed reviews. This preserves the new/learning
    /// distinction for short FSRS learning steps.
    #[serde(default)]
    pub review_count: u32,
}

impl ReviewSchedule {
    pub fn state(&self) -> ReviewCardState {
        if self.review_count == 0 && self.stability.is_none() {
            ReviewCardState::New
        } else if self.interval_days.unwrap_or_default() < 1.0 {
            if self.lapse_count > 0 {
                ReviewCardState::Relearning
            } else {
                ReviewCardState::Learning
            }
        } else {
            ReviewCardState::Review
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ReviewAttempt {
    pub id: ReviewAttemptId,
    pub item_id: ReviewItemId,
    pub reviewed_at_ms: u64,
    pub rating: ReviewRating,
    pub practice_attempt_id: Option<PracticeAttemptId>,
    pub next_due_at_ms: Option<u64>,
    #[serde(default)]
    pub previous_state: Option<ReviewCardState>,
    #[serde(default = "default_true")]
    pub advances_schedule: bool,
}

const fn default_true() -> bool {
    true
}

/// A learner-selected listening target for recurrence practice.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HuntingTarget {
    pub id: HuntingTargetId,
    pub lexical_entry_id: LexicalEntryId,
    pub source_kind: HuntingTargetSourceKind,
    pub source_id: Option<String>,
    pub target_snapshot: String,
    pub status: HuntingTargetStatus,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HuntingOccurrence {
    pub target_id: HuntingTargetId,
    pub lexical_entry_id: LexicalEntryId,
    pub target_snapshot: String,
    pub occurrence: CorpusOccurrence,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HuntingOccurrenceQueryResult {
    pub indexed: bool,
    pub occurrences: Vec<HuntingOccurrence>,
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
pub struct ListeningInboxItem {
    pub id: ListeningInboxItemId,
    pub session_id: Option<PracticeSessionId>,
    pub media_id: Option<MediaId>,
    pub track_id: Option<SubtitleTrackId>,
    pub target: PracticeTarget,
    pub anchors: Vec<PracticeAnchor>,
    pub label: Option<String>,
    pub subtitle_snapshot: String,
    pub context_before: Option<String>,
    pub context_after: Option<String>,
    pub captured_at_ms: u64,
    pub expires_at_ms: Option<u64>,
    pub status: ListeningInboxStatus,
    pub resolution: Option<ListeningInboxResolution>,
    pub review_item_ids: Vec<ReviewItemId>,
    pub practice_item_id: Option<PracticeItemId>,
    pub updated_at_ms: u64,
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
pub struct LexicalStatusPracticeEvidence {
    pub lexical_entry_id: LexicalEntryId,
    pub previous_status: Option<LearningStatus>,
    pub suggested_status: Option<LearningStatus>,
    pub practice_attempt_id: PracticeAttemptId,
}
