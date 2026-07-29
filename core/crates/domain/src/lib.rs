use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

mod language_profile;
pub use language_profile::{
    CapabilitySupport, LanguageLearningProfile, available_languages, profile_for,
};

mod background_job;
pub use background_job::*;

mod lexical_unit;
pub use lexical_unit::{LexicalUnit, baseline_normalized_key};

mod media;
pub use media::*;

mod subtitle;
pub use subtitle::*;

mod pronunciation;
pub use pronunciation::*;

mod timeline_envelope;
pub use timeline_envelope::*;

mod word_timing;
pub use word_timing::*;

mod chunk_timeline;
pub use chunk_timeline::*;

mod sense_group;
pub use sense_group::*;

mod syntactic_analysis;
pub use syntactic_analysis::*;

mod construction;
pub use construction::*;

mod personal_expression;
pub use personal_expression::*;

mod phone_timeline;
pub use phone_timeline::*;

mod sound_analysis;
pub use sound_analysis::*;

mod lltimeline;
pub use lltimeline::*;

mod phonetic_analysis;
pub use phonetic_analysis::*;

mod learning;
pub use learning::*;

mod capability;
pub use capability::*;

mod content_fit;
pub use content_fit::*;

mod learning_loop;
pub use learning_loop::*;

mod learning_observation;
pub use learning_observation::*;

mod listening_projection;
pub use listening_projection::*;

mod projection_review;
pub use projection_review::*;

mod llm_provider;
mod semantic_task;
pub use llm_provider::*;
pub use semantic_task::*;

mod production_corpus;
pub use production_corpus::*;

mod semantic_embedding;
pub use semantic_embedding::*;

mod realtime_conversation;
pub use realtime_conversation::*;

mod writing_feedback;
pub use writing_feedback::*;

mod reading;
pub use reading::*;

mod dictionary;
pub use dictionary::*;

mod transcription;
pub use transcription::*;

mod vocabulary;
pub use vocabulary::*;

mod diagnosis;
pub use diagnosis::*;

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
string_id!(BackgroundJobId);
string_id!(SubtitleTrackId);
string_id!(SubtitleSentenceId);
string_id!(DictionaryEntryId);
string_id!(TranscriptionJobId);
string_id!(RecordingTranscriptionJobId);
string_id!(TranscriptionModelId);
string_id!(WordTimelineId);
string_id!(ChunkTimelineId);
string_id!(ChunkId);
string_id!(PhoneTimelineId);
string_id!(RhythmFrameId);
string_id!(LLTimelineId);
string_id!(LexicalEntryId);
string_id!(LexicalSenseId);
string_id!(LexicalCapabilityHistoryId);
string_id!(LexicalObservationId);
string_id!(LearningObservationId);
string_id!(ProjectionProposalId);
string_id!(ProjectionDecisionId);
string_id!(LexicalOccurrenceId);
string_id!(LexicalStatusHistoryId);
string_id!(LearningResourceId);
string_id!(PracticeSessionId);
string_id!(PracticeItemId);
string_id!(PracticeAttemptId);
string_id!(ReviewItemId);
string_id!(ReviewAttemptId);
string_id!(HuntingCandidateId);
string_id!(HuntingTargetId);
string_id!(RecognitionEvidenceId);
string_id!(UpgradeSuggestionId);
string_id!(LearningEventId);
string_id!(ListeningInboxItemId);
string_id!(CorpusOccurrenceId);
string_id!(LearnerProfileId);
string_id!(SenseGroupAnalysisId);
string_id!(SenseGroupId);
string_id!(SyntacticAnalysisId);
string_id!(SentenceExemplarId);
string_id!(ConstructionId);
string_id!(ConstructionOccurrenceId);
string_id!(UserSentencePatternId);
string_id!(UserSentencePatternVersionId);
string_id!(PersonalExpressionAttemptId);
string_id!(RecordingAssetId);
string_id!(SemanticRubricId);
string_id!(SemanticTaskAttemptId);
string_id!(SemanticJudgmentId);
string_id!(JudgmentAdjudicationId);
string_id!(WritingFeedbackFindingId);
string_id!(WritingFindingDispositionId);
string_id!(LlmProviderProfileId);
string_id!(RealtimeProviderProfileId);
string_id!(RealtimeConversationSessionId);
string_id!(RealtimeConversationTurnId);
string_id!(ProductionCorpusDocumentId);
string_id!(ProductionCorpusEntryId);
string_id!(PronunciationAnalysisId);
string_id!(PhoneticAnalysisModelId);
string_id!(PhoneticAnalysisJobId);
string_id!(PhoneticAnalysisId);
string_id!(PhoneticFindingId);
string_id!(ShadowingAnalysisId);

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
    #[error("lexical entry {0} projection diverges from its lexical unit identity")]
    LexicalUnitMismatch(&'static str),
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
}
