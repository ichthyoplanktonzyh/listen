//! Durable, user-owned personal expression assets (Phase 3.16).
//!
//! A pattern is explicit user intent. It is neither a canonical construction
//! nor a projection of production-corpus or embedding rows. Source identifiers
//! are optional navigation hints; the immutable snapshot is authoritative when
//! the source disappears.

use serde::{Deserialize, Serialize};

use crate::{
    ConstructionId, LanguageCode, MediaId, PersonalExpressionAttemptId, RecordingAssetId,
    SemanticTaskAttemptId, SubtitleSentenceId, SubtitleTrackId, UserSentencePatternId,
    UserSentencePatternVersionId,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PatternSourceKind {
    Transcript,
    DictionaryOccurrence,
    Reading,
    SpeakingAttempt,
    WritingAttempt,
    ProductionCorpus,
    SemanticCandidate,
    Manual,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PatternSourceSnapshot {
    pub kind: PatternSourceKind,
    pub text: String,
    pub title: Option<String>,
    pub media_id: Option<MediaId>,
    pub media_fingerprint: Option<String>,
    pub track_id: Option<SubtitleTrackId>,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub semantic_attempt_id: Option<SemanticTaskAttemptId>,
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
    /// Additive provenance for a corpus/vector hit. It never owns identity.
    pub candidate_ref: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserSentencePatternSlot {
    pub name: String,
    pub prompt: Option<String>,
    pub example_value: Option<String>,
    pub required: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserSentencePatternVersion {
    pub id: UserSentencePatternVersionId,
    pub pattern_id: UserSentencePatternId,
    pub version: u32,
    pub name: String,
    pub pattern_text: String,
    pub slots: Vec<UserSentencePatternSlot>,
    pub note: Option<String>,
    /// Suggestion only. It may be absent and cannot replace pattern text.
    pub system_construction_id: Option<ConstructionId>,
    pub created_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserSentencePatternAsset {
    pub id: UserSentencePatternId,
    pub language: LanguageCode,
    pub source: PatternSourceSnapshot,
    pub current_version: UserSentencePatternVersion,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PersonalExpressionChannel {
    Speaking,
    Writing,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PersonalExpressionAssistance {
    TemplateVisible,
    SlotHints,
    Keywords,
    NoText,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PersonalExpressionSelfAssessment {
    NeedsWork,
    PartlyExpressed,
    Expressed,
}

/// One immutable completed use of one immutable pattern version. This is the
/// 3.17 handoff fact; it is not an observation, proposal, or projection.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PersonalExpressionAttempt {
    pub id: PersonalExpressionAttemptId,
    pub pattern_id: UserSentencePatternId,
    pub pattern_version_id: UserSentencePatternVersionId,
    pub channel: PersonalExpressionChannel,
    pub assistance: PersonalExpressionAssistance,
    pub response_text: String,
    pub raw_transcript: Option<String>,
    pub recording_asset_id: Option<RecordingAssetId>,
    /// Constructed Speaking Task that owns the transcript and recording facts.
    /// Historical pre-3.19.1 rows deserialize without the relationship.
    #[serde(default)]
    pub semantic_attempt_id: Option<SemanticTaskAttemptId>,
    pub self_assessment: PersonalExpressionSelfAssessment,
    pub context_note: Option<String>,
    pub completed_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PersonalExpressionExportPattern {
    pub asset: UserSentencePatternAsset,
    pub versions: Vec<UserSentencePatternVersion>,
    pub attempts: Vec<PersonalExpressionAttempt>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PersonalExpressionExportBundle {
    pub schema: String,
    pub exported_at_ms: u64,
    pub patterns: Vec<PersonalExpressionExportPattern>,
}

pub fn validate_pattern_version(value: &UserSentencePatternVersion) -> Result<(), String> {
    if value.version == 0 || value.name.trim().is_empty() || value.pattern_text.trim().is_empty() {
        return Err("pattern version requires version, name, and pattern_text".into());
    }
    let mut names = std::collections::HashSet::new();
    for slot in &value.slots {
        let name = slot.name.trim().to_ascii_lowercase();
        if name.is_empty() || !names.insert(name) {
            return Err("pattern slot names must be non-empty and unique".into());
        }
    }
    Ok(())
}

pub fn validate_personal_expression_attempt(
    value: &PersonalExpressionAttempt,
) -> Result<(), String> {
    if value.response_text.trim().is_empty() {
        return Err("learner response must not be empty".into());
    }
    match value.channel {
        PersonalExpressionChannel::Writing => {
            if value.raw_transcript.is_some()
                || value.recording_asset_id.is_some()
                || value.semantic_attempt_id.is_some()
            {
                return Err("writing use cannot carry speaking recording facts".into());
            }
        }
        PersonalExpressionChannel::Speaking => {
            if value.recording_asset_id.is_none() || value.semantic_attempt_id.is_none() {
                return Err("speaking use requires a recording asset and semantic attempt".into());
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn channels_do_not_accept_each_others_facts() {
        let attempt = PersonalExpressionAttempt {
            id: PersonalExpressionAttemptId::parse("a").unwrap(),
            pattern_id: UserSentencePatternId::parse("p").unwrap(),
            pattern_version_id: UserSentencePatternVersionId::parse("v").unwrap(),
            channel: PersonalExpressionChannel::Writing,
            assistance: PersonalExpressionAssistance::NoText,
            response_text: "I ended up fixing it on Sunday.".into(),
            raw_transcript: Some("raw".into()),
            recording_asset_id: None,
            semantic_attempt_id: None,
            self_assessment: PersonalExpressionSelfAssessment::Expressed,
            context_note: None,
            completed_at_ms: 1,
        };
        assert!(validate_personal_expression_attempt(&attempt).is_err());
    }

    #[test]
    fn speaking_use_references_its_authoritative_semantic_attempt() {
        let attempt = PersonalExpressionAttempt {
            id: PersonalExpressionAttemptId::parse("a").unwrap(),
            pattern_id: UserSentencePatternId::parse("p").unwrap(),
            pattern_version_id: UserSentencePatternVersionId::parse("v").unwrap(),
            channel: PersonalExpressionChannel::Speaking,
            assistance: PersonalExpressionAssistance::NoText,
            response_text: "I ended up fixing it on Sunday.".into(),
            raw_transcript: Some("raw".into()),
            recording_asset_id: Some(RecordingAssetId::parse("recording").unwrap()),
            semantic_attempt_id: None,
            self_assessment: PersonalExpressionSelfAssessment::Expressed,
            context_note: None,
            completed_at_ms: 1,
        };
        assert!(
            validate_personal_expression_attempt(&attempt)
                .unwrap_err()
                .contains("semantic attempt")
        );
    }
}
