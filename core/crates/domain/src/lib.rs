use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

macro_rules! string_id {
    ($name:ident) => {
        #[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
        #[serde(transparent)]
        pub struct $name(String);

        impl $name {
            pub fn parse(value: impl Into<String>) -> Result<Self, DomainError> {
                let value = value.into();
                if value.trim().is_empty() {
                    return Err(DomainError::EmptyValue(stringify!($name)));
                }
                Ok(Self(value))
            }

            pub fn from_fingerprint(namespace: &str, fingerprint: &str) -> Self {
                let digest = Sha256::digest(format!("{namespace}:{fingerprint}"));
                Self(hex::encode(digest))
            }

            pub fn as_str(&self) -> &str {
                &self.0
            }
        }
    };
}

string_id!(MediaId);
string_id!(SubtitleTrackId);
string_id!(SubtitleSentenceId);
string_id!(WordProfileId);
string_id!(WordObservationId);
string_id!(WordOccurrenceId);
string_id!(WordStatusHistoryId);
string_id!(DictionaryEntryId);
string_id!(TranscriptionJobId);
string_id!(TranscriptionModelId);
string_id!(WordTimelineId);
string_id!(LLTimelineId);
string_id!(LexicalEntryId);
string_id!(LexicalOccurrenceId);
string_id!(LexicalStatusHistoryId);
string_id!(LearningResourceId);
string_id!(PronunciationAnalysisId);
string_id!(PhoneticAnalysisModelId);
string_id!(PhoneticAnalysisJobId);
string_id!(PhoneticAnalysisId);
string_id!(PhoneticFindingId);

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct TimeMs(u64);

impl TimeMs {
    pub const ZERO: Self = Self(0);
    pub const fn new(value: u64) -> Self {
        Self(value)
    }
    pub const fn get(self) -> u64 {
        self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct LanguageCode(String);

impl LanguageCode {
    pub fn parse(value: impl Into<String>) -> Result<Self, DomainError> {
        let value = value.into().trim().to_ascii_lowercase();
        if value.is_empty() {
            return Err(DomainError::EmptyValue("LanguageCode"));
        }
        if !value.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
            return Err(DomainError::InvalidLanguageCode);
        }
        Ok(Self(value))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Video,
    Audio,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaAvailability {
    Available,
    Missing,
    Archived,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaItem {
    pub id: MediaId,
    pub path: String,
    pub fingerprint: String,
    pub title: String,
    pub kind: MediaKind,
    pub duration: Option<TimeMs>,
    pub availability: MediaAvailability,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleTrack {
    pub id: SubtitleTrackId,
    pub media_id: MediaId,
    pub fingerprint: String,
    pub language: Option<LanguageCode>,
    pub source: String,
    pub sentences: Vec<SubtitleSentence>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleSentence {
    pub id: SubtitleSentenceId,
    pub index: u32,
    pub start: TimeMs,
    pub end: TimeMs,
    pub original_text: String,
    pub display_text: String,
    pub tokens: Vec<SubtitleToken>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SubtitleTokenKind {
    Word,
    Whitespace,
    Punctuation,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleToken {
    pub index: u32,
    pub kind: SubtitleTokenKind,
    pub text: String,
    pub normalized: Option<String>,
    pub start_char: u32,
    pub end_char: u32,
}

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

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimingSource {
    AsrReported,
    ForcedAligned,
    Estimated,
    UserAdjusted,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WordTiming {
    pub sentence_id: SubtitleSentenceId,
    pub token_index: u32,
    pub text: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub confidence: Option<f32>,
    pub timing_source: TimingSource,
    pub provider_id: String,
    pub provider_version: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimelineCreator {
    Algorithm,
    User,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimelineStatus {
    Candidate,
    Active,
    Archived,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WordTimeline {
    pub id: WordTimelineId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub config_hash: String,
    pub parent_timeline_id: Option<WordTimelineId>,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    pub metrics_json: serde_json::Value,
    pub words: Vec<WordTiming>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WordTimelineLifecycleStage {
    AlgorithmCandidate,
    UserAdjusted,
    Published,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WordTimelineSummary {
    pub id: WordTimelineId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub parent_timeline_id: Option<WordTimelineId>,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    pub lifecycle_stage: WordTimelineLifecycleStage,
    pub word_count: u32,
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
    pub provider_ids: Vec<String>,
    pub timing_sources: Vec<TimingSource>,
    pub average_confidence: Option<f32>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
    pub can_activate: bool,
    pub can_archive: bool,
    pub can_delete: bool,
}

pub const LLTIMELINE_SCHEMA_V1: &str = "llplayer.timeline.v1";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineDocument {
    pub schema: String,
    pub metadata: LLTimelineMetadata,
    pub segments: Vec<LLTimelineSegment>,
    #[serde(default)]
    pub word_timelines: Vec<WordTimeline>,
    pub active_word_timeline_id: Option<WordTimelineId>,
    #[serde(default)]
    pub phone_timelines: Vec<LLTimelinePhoneTimeline>,
    pub active_phone_timeline_id: Option<LLTimelineId>,
    #[serde(default)]
    pub chunk_timelines: Vec<LLTimelineChunkTimeline>,
    pub active_chunk_timeline_id: Option<LLTimelineId>,
    #[serde(default)]
    pub artifacts: Vec<LLTimelineArtifact>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineMetadata {
    pub created_at_ms: u64,
    pub generator: LLTimelineGenerator,
    pub media: LLTimelineMedia,
    pub language: Option<LanguageCode>,
    pub human_reviewed: bool,
    #[serde(default)]
    pub extra: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LLTimelineGenerator {
    pub id: String,
    pub version: String,
    pub mode: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineMedia {
    pub id: MediaId,
    pub fingerprint: String,
    pub path: Option<String>,
    pub title: String,
    pub duration_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LLTimelineSegment {
    pub id: SubtitleSentenceId,
    pub index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub display_text: String,
    pub tokens: Vec<LLTimelineToken>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LLTimelineToken {
    pub index: u32,
    pub kind: SubtitleTokenKind,
    pub text: String,
    pub normalized: Option<String>,
    pub start_char: u32,
    pub end_char: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelinePhoneTimeline {
    pub id: LLTimelineId,
    pub word_timeline_id: Option<WordTimelineId>,
    pub provider_id: String,
    pub provider_version: String,
    #[serde(default)]
    pub phones: Vec<Phoneme>,
    #[serde(default)]
    pub metrics_json: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineChunkTimeline {
    pub id: LLTimelineId,
    pub word_timeline_id: Option<WordTimelineId>,
    pub algorithm_id: String,
    pub algorithm_version: String,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    #[serde(default)]
    pub chunks: Vec<LLTimelineChunk>,
    #[serde(default)]
    pub metrics_json: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineChunk {
    pub index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    #[serde(default)]
    pub sentence_ids: Vec<SubtitleSentenceId>,
    #[serde(default)]
    pub word_refs: Vec<LLTimelineWordRef>,
    #[serde(default)]
    pub evidence: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LLTimelineWordRef {
    pub sentence_id: SubtitleSentenceId,
    pub token_index: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineArtifact {
    pub kind: String,
    pub provider_id: Option<String>,
    pub provider_version: Option<String>,
    #[serde(default)]
    pub payload: serde_json::Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhoneticModelState {
    Downloadable,
    Installing,
    Installed,
    Custom,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PhoneticAnalysisProviderInfo {
    pub id: String,
    pub display_name: String,
    pub runtime_id: String,
    pub runtime_version: String,
    pub available: bool,
    pub experimental: bool,
    pub supports_timestamps: bool,
    pub supports_confidence: bool,
    pub supported_languages: Vec<String>,
    pub supported_dialects: Vec<String>,
    pub phone_sets: Vec<String>,
    pub diagnostic: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PhoneticAnalysisModelDescriptor {
    pub id: PhoneticAnalysisModelId,
    pub provider_id: String,
    pub display_name: String,
    pub family: String,
    pub revision: String,
    pub checksum_sha256: String,
    pub download_url: Option<String>,
    pub local_path: Option<String>,
    pub size_bytes: u64,
    pub supported_languages: Vec<String>,
    pub supported_dialects: Vec<String>,
    pub phone_sets: Vec<String>,
    pub supports_timestamps: bool,
    pub expected_sample_rate_hz: u32,
    pub context_window_ms: Option<u64>,
    pub state: PhoneticModelState,
    pub installed_bytes: u64,
    pub error: Option<String>,
    pub license: String,
    pub training_data_provenance: String,
    pub distribution_allowed: bool,
    pub application_verified: bool,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhoneticAnalysisScope {
    Sentence,
    Track,
    SelectedRange,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhoneticAnalysisJobStatus {
    Queued,
    Extracting,
    RecognizingPhones,
    Aligning,
    Analyzing,
    Completed,
    Cancelled,
    Failed,
    Interrupted,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PhoneticAnalysisJob {
    pub id: PhoneticAnalysisJobId,
    pub media_id: MediaId,
    pub track_id: SubtitleTrackId,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub scope: PhoneticAnalysisScope,
    pub audio_start_ms: u64,
    pub audio_end_ms: u64,
    pub provider_id: String,
    pub provider_version: String,
    pub runtime_id: String,
    pub runtime_version: String,
    pub model_id: PhoneticAnalysisModelId,
    pub model_revision: String,
    pub model_checksum_sha256: String,
    pub requested_phone_set: String,
    pub settings_json: String,
    pub input_fingerprint: String,
    pub status: PhoneticAnalysisJobStatus,
    pub phase_progress: u8,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub retry_of_job_id: Option<PhoneticAnalysisJobId>,
    pub analysis_id: Option<PhoneticAnalysisId>,
    pub created_at_ms: u64,
    pub started_at_ms: Option<u64>,
    pub completed_at_ms: Option<u64>,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DetectedPhone {
    pub symbol: String,
    pub phone_set: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub confidence: Option<f32>,
    pub token_index: Option<u32>,
    pub provider_id: String,
    pub provider_version: String,
    pub model_revision: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhoneAlignmentKind {
    Match,
    Substitution,
    Insertion,
    Deletion,
    Merge,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PhoneAlignment {
    pub kind: PhoneAlignmentKind,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub canonical_phones: Vec<String>,
    pub detected_phone_start: Option<u32>,
    pub detected_phone_end: Option<u32>,
    pub confidence: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhoneticFindingStatus {
    Uncertain,
    SupportedByAlignment,
    DetectedInAudio,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PhoneticFinding {
    pub id: PhoneticFindingId,
    pub analysis_id: PhoneticAnalysisId,
    pub finding_type: String,
    pub affected_token_start: u32,
    pub affected_token_end: u32,
    pub canonical_phones: Vec<String>,
    pub detected_phones: Vec<String>,
    pub aligned_phone_start: Option<u32>,
    pub aligned_phone_end: Option<u32>,
    pub audio_start_ms: u64,
    pub audio_end_ms: u64,
    pub confidence: f32,
    pub evidence: String,
    pub status: PhoneticFindingStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhoneticFindingFeedbackValue {
    Confirmed,
    Rejected,
    Ignored,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PhoneticFindingFeedback {
    pub finding_id: PhoneticFindingId,
    pub value: PhoneticFindingFeedbackValue,
    pub note: Option<String>,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PhoneticAnalysis {
    pub id: PhoneticAnalysisId,
    pub job_id: PhoneticAnalysisJobId,
    pub media_id: MediaId,
    pub track_id: SubtitleTrackId,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub audio_start_ms: u64,
    pub audio_end_ms: u64,
    pub provider_id: String,
    pub provider_version: String,
    pub model_id: PhoneticAnalysisModelId,
    pub model_revision: String,
    pub model_checksum_sha256: String,
    pub phone_set: String,
    pub detected_phones: Vec<DetectedPhone>,
    pub alignments: Vec<PhoneAlignment>,
    pub findings: Vec<PhoneticFinding>,
    pub analyzer_version: String,
    pub created_at_ms: u64,
}

impl PhoneticAnalysis {
    pub fn validate(&self) -> Result<(), DomainError> {
        if self.audio_start_ms >= self.audio_end_ms {
            return Err(DomainError::InvalidAudioRange);
        }
        let mut previous_end = self.audio_start_ms;
        for phone in &self.detected_phones {
            if phone.symbol.trim().is_empty()
                || phone.phone_set.trim().is_empty()
                || phone.start_ms < self.audio_start_ms
                || phone.end_ms > self.audio_end_ms
                || phone.start_ms >= phone.end_ms
                || phone.start_ms < previous_end
                || phone
                    .confidence
                    .is_some_and(|value| !(0.0..=1.0).contains(&value))
            {
                return Err(DomainError::InvalidDetectedPhoneTimeline);
            }
            previous_end = phone.end_ms;
        }
        for finding in &self.findings {
            if finding.analysis_id != self.id
                || finding.audio_start_ms >= finding.audio_end_ms
                || finding.audio_start_ms < self.audio_start_ms
                || finding.audio_end_ms > self.audio_end_ms
                || !(0.0..=1.0).contains(&finding.confidence)
                || finding.status == PhoneticFindingStatus::DetectedInAudio
                    && finding.confidence < 0.75
            {
                return Err(DomainError::InvalidPhoneticFinding);
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WordStatus {
    UnknownMeaning,
    KnownNotRecognized,
    KnownRecognized,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordProfile {
    pub id: WordProfileId,
    pub language: LanguageCode,
    pub lemma: String,
    pub normalized_lemma: String,
    pub display_form: String,
    pub status: Option<WordStatus>,
    pub updated_at_ms: u64,
    #[serde(default)]
    pub user_definition: Option<String>,
    #[serde(default)]
    pub personal_note: Option<String>,
    #[serde(default)]
    pub learning_updated_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ObservationResult {
    RecognizedInContext,
    NotRecognizedInContext,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordObservation {
    pub id: WordObservationId,
    pub word_profile_id: WordProfileId,
    pub sentence_id: SubtitleSentenceId,
    pub original_form: String,
    pub result: ObservationResult,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordOccurrence {
    pub id: WordOccurrenceId,
    pub source_key: String,
    pub word_profile_id: WordProfileId,
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text_snapshot: String,
    pub media_title_snapshot: String,
    pub media_fingerprint_snapshot: String,
    pub start_ms_snapshot: u64,
    pub end_ms_snapshot: u64,
    pub first_seen_at_ms: u64,
    pub last_seen_at_ms: u64,
    pub encounter_count: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WordChangeSource {
    UserSelection,
    Import,
    LegacyBaseline,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordStatusHistory {
    pub id: WordStatusHistoryId,
    pub word_profile_id: WordProfileId,
    pub previous_status: Option<WordStatus>,
    pub new_status: Option<WordStatus>,
    pub source_occurrence_id: Option<WordOccurrenceId>,
    pub changed_at_ms: u64,
    pub change_source: WordChangeSource,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordDetails {
    pub profile: WordProfile,
    pub history: Vec<WordStatusHistory>,
    pub occurrences: Vec<WordOccurrence>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LexicalEntryKind {
    Word,
    Phrase,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalEntry {
    pub id: LexicalEntryId,
    pub language: LanguageCode,
    pub kind: LexicalEntryKind,
    pub canonical_form: String,
    pub normalized_form: String,
    pub display_form: String,
    pub status: Option<WordStatus>,
    pub user_definition: Option<String>,
    pub personal_note: Option<String>,
    pub normalization_provider: String,
    pub normalization_version: String,
    pub user_corrected: bool,
    pub updated_at_ms: u64,
    pub learning_updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalOccurrence {
    pub id: LexicalOccurrenceId,
    pub source_key: String,
    pub lexical_entry_id: LexicalEntryId,
    pub media_id: Option<MediaId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub original_form: String,
    pub sentence_text_snapshot: String,
    pub media_title_snapshot: String,
    pub media_fingerprint_snapshot: String,
    pub start_ms_snapshot: u64,
    pub end_ms_snapshot: u64,
    pub token_start: Option<u32>,
    pub token_end: Option<u32>,
    pub first_seen_at_ms: u64,
    pub last_seen_at_ms: u64,
    pub encounter_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalStatusHistory {
    pub id: LexicalStatusHistoryId,
    pub lexical_entry_id: LexicalEntryId,
    pub previous_status: Option<WordStatus>,
    pub new_status: Option<WordStatus>,
    pub changed_at_ms: u64,
    pub change_source: WordChangeSource,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalEntryDetails {
    pub entry: LexicalEntry,
    pub history: Vec<LexicalStatusHistory>,
    pub occurrences: Vec<LexicalOccurrence>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PhraseCandidate {
    pub canonical_form: String,
    pub display_form: String,
    pub normalized_form: String,
    pub token_start: u32,
    pub token_end: u32,
    pub reason: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningResourceState {
    Available,
    Installing,
    Installed,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LearningResourceDescriptor {
    pub id: LearningResourceId,
    pub display_name: String,
    pub version: String,
    pub source_url: String,
    pub license: String,
    pub checksum_sha256: String,
    pub size_bytes: u64,
    pub local_path: Option<String>,
    pub state: LearningResourceState,
    pub installed_bytes: u64,
    pub error: Option<String>,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SubtitleSearchResult {
    pub id: String,
    pub file_id: u64,
    pub language: String,
    pub release: String,
    pub source: String,
    pub rating: f64,
    pub download_count: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VocabularyAssetBundle {
    pub version: u16,
    pub exported_at_ms: u64,
    pub profiles: Vec<WordProfile>,
    pub history: Vec<WordStatusHistory>,
    pub occurrences: Vec<WordOccurrence>,
    pub observations: Vec<WordObservation>,
    #[serde(default)]
    pub lexical_entries: Vec<LexicalEntry>,
    #[serde(default)]
    pub lexical_history: Vec<LexicalStatusHistory>,
    #[serde(default)]
    pub lexical_occurrences: Vec<LexicalOccurrence>,
    #[serde(default)]
    pub phonetic_finding_feedback: Vec<PhoneticFindingFeedback>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryEntry {
    pub id: DictionaryEntryId,
    pub language: LanguageCode,
    pub normalized_lemma: String,
    pub provider: String,
    pub payload_json: String,
    pub cached_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryDefinition {
    pub part_of_speech: Option<String>,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryPhonetic {
    pub text: String,
    pub region: Option<String>,
    #[serde(default)]
    pub audio_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryLookup {
    pub query: String,
    pub lemma: String,
    pub definitions: Vec<DictionaryDefinition>,
    pub phonetics: Vec<DictionaryPhonetic>,
    pub provider: String,
    pub cached_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryProviderInfo {
    pub id: String,
    pub display_name: String,
    pub supported_languages: Vec<String>,
    pub provides_definitions: bool,
    pub provides_phonetics: bool,
    pub provides_audio: bool,
    pub offline: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TranscriptionQuality {
    Fast,
    Balanced,
    Accurate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TranscriptionModelState {
    Downloadable,
    Installing,
    Installed,
    Custom,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptionProviderInfo {
    pub id: String,
    pub display_name: String,
    pub runtime_id: String,
    pub runtime_version: String,
    pub available: bool,
    pub supports_translation: bool,
    pub supported_languages: Vec<String>,
    pub diagnostic: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptionRuntimeDescriptor {
    pub id: String,
    pub provider_id: String,
    pub version: String,
    pub available: bool,
    pub supports_translation: bool,
    pub supported_model_families: Vec<String>,
    pub diagnostic: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptionModelDescriptor {
    pub id: TranscriptionModelId,
    pub provider_id: String,
    pub display_name: String,
    pub family: String,
    pub revision: String,
    pub checksum_sha256: String,
    pub download_url: Option<String>,
    pub local_path: Option<String>,
    pub size_bytes: u64,
    pub quality: TranscriptionQuality,
    pub english_only: bool,
    pub supports_translation: bool,
    pub state: TranscriptionModelState,
    pub installed_bytes: u64,
    pub error: Option<String>,
    pub license: String,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TranscriptionDestination {
    Primary,
    Secondary,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TranscriptionPurpose {
    Transcribe,
    TranslateToEnglish,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptionProfile {
    pub preferred_provider_id: Option<String>,
    pub quality: TranscriptionQuality,
    pub language: Option<String>,
    pub purpose: TranscriptionPurpose,
    pub destination: TranscriptionDestination,
    pub audio_track: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptionSegment {
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptionResult {
    pub detected_language: Option<String>,
    pub segments: Vec<TranscriptionSegment>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TranscriptionJobStatus {
    Queued,
    Extracting,
    Transcribing,
    Importing,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptionJob {
    pub id: TranscriptionJobId,
    pub media_id: MediaId,
    pub media_title: String,
    pub media_fingerprint: String,
    pub provider_id: String,
    pub provider_version: String,
    pub runtime_id: String,
    pub runtime_version: String,
    pub model_id: TranscriptionModelId,
    pub model_revision: String,
    pub model_checksum_sha256: String,
    pub destination: TranscriptionDestination,
    pub purpose: TranscriptionPurpose,
    pub requested_language: Option<String>,
    pub detected_language: Option<String>,
    pub audio_track: Option<u32>,
    pub settings_json: String,
    pub input_fingerprint: String,
    pub status: TranscriptionJobStatus,
    pub phase_progress: u8,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub retry_of_job_id: Option<TranscriptionJobId>,
    pub generated_track_id: Option<SubtitleTrackId>,
    pub created_at_ms: u64,
    pub started_at_ms: Option<u64>,
    pub completed_at_ms: Option<u64>,
    pub updated_at_ms: u64,
    #[serde(default)]
    pub archived_at_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleTrackProvenance {
    pub track_id: SubtitleTrackId,
    pub transcription_job_id: TranscriptionJobId,
    pub provider_id: String,
    pub runtime_version: String,
    pub model_id: TranscriptionModelId,
    pub model_revision: String,
    pub model_checksum_sha256: String,
    pub settings_json: String,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryProviderResult {
    pub provider: DictionaryProviderInfo,
    pub lookup: Option<DictionaryLookup>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DictionaryLookupBundle {
    pub query: String,
    pub normalized_lemma: String,
    pub results: Vec<DictionaryProviderResult>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExternalVocabularyEntry {
    pub word: String,
    pub status: Option<WordStatus>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExternalVocabularyImport {
    pub language: String,
    pub entries: Vec<ExternalVocabularyEntry>,
    pub default_status: Option<WordStatus>,
    pub overwrite_existing: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct ExternalVocabularyImportSummary {
    pub created: u64,
    pub initialized: u64,
    pub skipped: u64,
    pub overwritten: u64,
    pub invalid: u64,
}

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
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SentenceDiagnosis {
    pub sentence_id: SubtitleSentenceId,
    pub hints: Vec<DiagnosisHint>,
    pub unclassified_lemmas: Vec<String>,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum DomainError {
    #[error("{0} must not be empty")]
    EmptyValue(&'static str),
    #[error("language code contains unsupported characters")]
    InvalidLanguageCode,
    #[error("audio range must be non-empty")]
    InvalidAudioRange,
    #[error("detected phone timeline must be monotonic, bounded, and valid")]
    InvalidDetectedPhoneTimeline,
    #[error("phonetic finding range, confidence, or status is invalid")]
    InvalidPhoneticFinding,
}

pub fn normalize_lemma(value: &str) -> String {
    value.trim().to_lowercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fingerprint_ids_are_stable_and_namespaced() {
        assert_eq!(
            MediaId::from_fingerprint("media", "abc"),
            MediaId::from_fingerprint("media", "abc")
        );
        assert_ne!(
            MediaId::from_fingerprint("media", "abc").as_str(),
            MediaId::from_fingerprint("other", "abc").as_str()
        );
    }

    #[test]
    fn language_codes_are_normalized() {
        assert_eq!(LanguageCode::parse("EN-us").unwrap().as_str(), "en-us");
    }

    #[test]
    fn lemma_normalization_is_stable() {
        assert_eq!(normalize_lemma("  Can't  "), "can't");
    }

    #[test]
    fn lltimeline_v1_fixture_deserializes() {
        let document: LLTimelineDocument = serde_json::from_str(include_str!(
            "../../../testdata/lltimeline/v1-minimal.lltimeline.json"
        ))
        .unwrap();
        assert_eq!(document.schema, LLTIMELINE_SCHEMA_V1);
        assert_eq!(document.segments.len(), 1);
        assert_eq!(document.word_timelines.len(), 1);
        assert_eq!(
            document.active_word_timeline_id,
            Some(WordTimelineId::parse("timeline-fixture").unwrap())
        );
    }

    #[test]
    fn phonetic_analysis_requires_monotonic_bounded_phones() {
        let mut analysis = phonetic_analysis();
        assert_eq!(analysis.validate(), Ok(()));
        analysis.detected_phones[1].start_ms = 150;
        assert_eq!(
            analysis.validate(),
            Err(DomainError::InvalidDetectedPhoneTimeline)
        );
    }

    #[test]
    fn detected_in_audio_requires_calibrated_confidence() {
        let mut analysis = phonetic_analysis();
        analysis.findings[0].confidence = 0.74;
        analysis.findings[0].status = PhoneticFindingStatus::DetectedInAudio;
        assert_eq!(
            analysis.validate(),
            Err(DomainError::InvalidPhoneticFinding)
        );
    }

    fn phonetic_analysis() -> PhoneticAnalysis {
        let analysis_id = PhoneticAnalysisId::from_fingerprint("analysis", "test");
        PhoneticAnalysis {
            id: analysis_id.clone(),
            job_id: PhoneticAnalysisJobId::from_fingerprint("job", "test"),
            media_id: MediaId::from_fingerprint("media", "test"),
            track_id: SubtitleTrackId::from_fingerprint("track", "test"),
            sentence_id: None,
            audio_start_ms: 100,
            audio_end_ms: 500,
            provider_id: "fake".into(),
            provider_version: "v1".into(),
            model_id: PhoneticAnalysisModelId::from_fingerprint("model", "test"),
            model_revision: "v1".into(),
            model_checksum_sha256: "abc".into(),
            phone_set: "arpabet".into(),
            detected_phones: vec![
                DetectedPhone {
                    symbol: "HH".into(),
                    phone_set: "arpabet".into(),
                    start_ms: 100,
                    end_ms: 200,
                    confidence: Some(0.9),
                    token_index: Some(0),
                    provider_id: "fake".into(),
                    provider_version: "v1".into(),
                    model_revision: "v1".into(),
                },
                DetectedPhone {
                    symbol: "AH".into(),
                    phone_set: "arpabet".into(),
                    start_ms: 200,
                    end_ms: 300,
                    confidence: Some(0.8),
                    token_index: Some(0),
                    provider_id: "fake".into(),
                    provider_version: "v1".into(),
                    model_revision: "v1".into(),
                },
            ],
            alignments: vec![],
            findings: vec![PhoneticFinding {
                id: PhoneticFindingId::from_fingerprint("finding", "test"),
                analysis_id,
                finding_type: "weak_form".into(),
                affected_token_start: 0,
                affected_token_end: 0,
                canonical_phones: vec!["HH".into(), "AH".into()],
                detected_phones: vec!["HH".into(), "AH".into()],
                aligned_phone_start: Some(0),
                aligned_phone_end: Some(1),
                audio_start_ms: 100,
                audio_end_ms: 300,
                confidence: 0.7,
                evidence: "fake".into(),
                status: PhoneticFindingStatus::SupportedByAlignment,
            }],
            analyzer_version: "v1".into(),
            created_at_ms: 1,
        }
    }
}
