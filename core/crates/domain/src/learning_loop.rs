use serde::{Deserialize, Serialize};

use crate::{
    CapabilityAssessment, ChunkId, HuntingCandidateId, HuntingTargetId, LanguageCode,
    LearningStatus, LexicalCapability, LexicalEntryId, LexicalObservationId, ListeningInboxItemId,
    MediaId, PracticeAttemptId, PracticeItemId, PracticeSessionId, RecognitionEvidenceId,
    RecordingAssetId, ReviewAttemptId, ReviewItemId, ShadowingAnalysisId, SubtitleSentenceId,
    SubtitleTrackId, UpgradeSuggestionId,
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

/// Anki's four scheduler states. This is deliberately derived from durable
/// schedule facts instead of stored independently, so imports and native
/// cards cannot drift into contradictory states.
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
pub enum HuntingCandidateStatus {
    Active,
    Consumed,
    Dismissed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HuntingTargetSourceKind {
    Manual,
    ReviewCandidate,
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
pub enum RecognitionEvidenceSourceKind {
    Practice,
    Review,
    LexicalObservation,
    Hunting,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UpgradeSuggestionStatus {
    Pending,
    Accepted,
    Rejected,
    Obsolete,
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
    FamiliarMaterialMarked,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlayableSegmentAvailability {
    Available,
    MissingMedia,
    MissingTimeline,
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
    /// Number of completed reviews. Unlike `stability`, this preserves the
    /// new/learning distinction for imported Anki learning cards.
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

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HuntingCandidate {
    pub id: HuntingCandidateId,
    pub lexical_entry_id: LexicalEntryId,
    pub review_item_id: ReviewItemId,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub media_id: Option<MediaId>,
    pub track_id: Option<SubtitleTrackId>,
    pub target_snapshot: String,
    pub prompt_snapshot: String,
    pub failure_count: u32,
    pub status: HuntingCandidateStatus,
    pub created_at_ms: u64,
    pub last_failed_at_ms: u64,
}

/// A learner-confirmed listening target. Review failures remain candidates
/// until explicitly promoted into this list.
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
pub struct RecognitionEvidence {
    pub id: RecognitionEvidenceId,
    pub lexical_entry_id: LexicalEntryId,
    pub context_key: String,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub media_id: Option<MediaId>,
    pub source_kind: RecognitionEvidenceSourceKind,
    pub source_id: String,
    pub occurred_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UpgradeSuggestion {
    pub id: UpgradeSuggestionId,
    pub lexical_entry_id: LexicalEntryId,
    pub lexical_display_form: String,
    pub previous_status: LearningStatus,
    pub suggested_status: LearningStatus,
    pub status: UpgradeSuggestionStatus,
    pub evidence_context_count: u32,
    pub evidence_ids: Vec<RecognitionEvidenceId>,
    pub threshold: u32,
    pub evidence_class: String,
    pub created_at_ms: u64,
    pub resolved_at_ms: Option<u64>,
    pub cooldown_until_ms: Option<u64>,
    #[serde(default)]
    pub capability: Option<LexicalCapability>,
    #[serde(default)]
    pub previous_assessment: Option<CapabilityAssessment>,
    #[serde(default)]
    pub suggested_assessment: Option<CapabilityAssessment>,
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
pub struct PlayableSegment {
    pub media_id: Option<MediaId>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub subtitle_snapshot: String,
    pub availability: PlayableSegmentAvailability,
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
    pub source_segment: PlayableSegment,
    pub language: LanguageCode,
    pub audio: RecordingAudioMetadata,
    pub recorder_version: String,
}

/// Transcription-ready facts about a locally recorded audio file. The hash
/// and byte length let later consumers detect missing/replaced files without
/// treating the mutable path as asset identity.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecordingAudioMetadata {
    pub container: String,
    pub codec: String,
    pub sample_rate_hz: u32,
    pub channels: u16,
    pub sample_format: String,
    pub byte_length: u64,
    pub content_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingComparison {
    pub attempt_id: PracticeAttemptId,
    pub reference_segment: PlayableSegment,
    pub recording_id: RecordingAssetId,
    pub duration_delta_ms: i64,
    pub pause_alignment: ShadowingPauseAlignment,
    pub reference_waveform: AudioWaveformSummary,
    pub recording_waveform: AudioWaveformSummary,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub analysis_v2: Option<ShadowingAnalysis>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingAnalysis {
    pub provider_id: String,
    pub provider_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phone_provider: Option<ShadowingProviderInfo>,
    pub coverage: f32,
    pub confidence: f32,
    pub evidence_coverage: ShadowingEvidenceCoverage,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prosody: Option<ShadowingProsodyComparison>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audio_quality: Option<AudioQualitySummary>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub abstain_reason: Option<ShadowingAbstainReason>,
    pub word_details: Vec<ShadowingWordDetail>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub unassigned_phone_alignments: Vec<ShadowingPhoneAlignmentDetail>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShadowingProviderInfo {
    pub provider_id: String,
    pub provider_version: String,
    pub model_revision: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingEvidenceCoverage {
    pub word_alignment: f32,
    pub phone_alignment: f32,
    pub stress: f32,
    pub rhythm: f32,
    pub f0: f32,
    pub energy: f32,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub missing: Vec<ShadowingMissingEvidence>,
}

impl Default for ShadowingEvidenceCoverage {
    fn default() -> Self {
        Self {
            word_alignment: 0.0,
            phone_alignment: 0.0,
            stress: 0.0,
            rhythm: 0.0,
            f0: 0.0,
            energy: 0.0,
            missing: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShadowingMissingEvidence {
    pub component: ShadowingEvidenceComponent,
    pub reason: ShadowingMissingEvidenceReason,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShadowingEvidenceComponent {
    ReferenceTimeline,
    PhoneRecognition,
    WordAlignment,
    Stress,
    Rhythm,
    F0,
    Energy,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShadowingMissingEvidenceReason {
    ReferenceTimelineUnavailable,
    ProviderUnavailable,
    ProviderFailed,
    InsufficientCoverage,
    AcousticExtractionFailed,
    NoVoicedFrames,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingProsodyComparison {
    pub reference_pause_count: u32,
    pub recording_pause_count: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pause_alignment_offset_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mean_word_duration_ratio: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rhythm_similarity: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub f0_contour_similarity: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub energy_prominence_similarity: Option<f32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShadowingAbstainReason {
    LowAudioQuality,
    LowConfidence,
    MismatchedSpeech,
    AudioTooShort,
    MissingReferenceTimeline,
    ProviderUnavailable,
    ProviderFailure,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShadowingWordStatus {
    Unassessed,
    Match,
    Substituted,
    Deleted,
    Inserted,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingWordDetail {
    pub token_index: u32,
    pub text: String,
    pub status: ShadowingWordStatus,
    pub reference_duration_ms: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recording_duration_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reference_stress: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recording_stress: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reference_f0_hz: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recording_f0_hz: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reference_f0_range_semitones: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recording_f0_range_semitones: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reference_pitch_reset_after: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recording_pitch_reset_after: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reference_energy_prominence: Option<f32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recording_energy_prominence: Option<f32>,
    pub phone_alignments: Vec<ShadowingPhoneAlignmentDetail>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingPhoneAlignmentDetail {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reference_phone: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recording_phone: Option<String>,
    pub status: ShadowingPhoneAlignmentStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShadowingPhoneAlignmentStatus {
    Match,
    Substitution,
    Insertion,
    Deletion,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingAnalysisRecord {
    pub id: ShadowingAnalysisId,
    pub recording_id: RecordingAssetId,
    pub attempt_id: PracticeAttemptId,
    pub reference_audio_sha256: String,
    pub created_at_ms: u64,
    pub analysis: ShadowingAnalysis,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct AudioQualitySummary {
    pub snr_db: f32,
    pub clipping_ratio: f32,
    pub dc_offset: f32,
    pub sample_rate_hz: u32,
    pub channels: u16,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioPauseInterval {
    pub start_ms: u64,
    pub end_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AudioWaveformSummary {
    pub duration_ms: u64,
    pub bucket_ms: u64,
    pub peaks: Vec<f32>,
    pub rms: Vec<f32>,
}

/// Objective facts extracted from one learner recording. These are acoustic
/// measurements only and never imply speaking quality or correctness.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecordingAudioFacts {
    pub recording_id: RecordingAssetId,
    pub duration_ms: u64,
    pub pauses: Vec<AudioPauseInterval>,
    pub waveform: AudioWaveformSummary,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShadowingPauseAlignment {
    pub reference_pauses: Vec<AudioPauseInterval>,
    pub recording_pauses: Vec<AudioPauseInterval>,
    pub mean_absolute_offset_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LexicalStatusPracticeEvidence {
    pub lexical_entry_id: LexicalEntryId,
    pub previous_status: Option<LearningStatus>,
    pub suggested_status: Option<LearningStatus>,
    pub practice_attempt_id: PracticeAttemptId,
}
