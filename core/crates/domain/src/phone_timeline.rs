use serde::{Deserialize, Serialize};

use crate::{
    DetectedPhone, MediaId, PhoneAlignment, PhoneTimelineId, PhoneticAnalysisId,
    PhoneticAnalysisModelId, PhoneticFinding, SoundAnalysis, SubtitleSentenceId, SubtitleTrackId,
    TimelineCreator, TimelineMetrics, TimelineStatus, WordTimelineId,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PhoneTimelinePrecision {
    Detected,
    Aligned,
    Approximate,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PhoneTimeline {
    pub id: PhoneTimelineId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub parent_word_timeline_id: Option<WordTimelineId>,
    pub parent_phonetic_analysis_id: Option<PhoneticAnalysisId>,
    pub provider_id: String,
    pub provider_version: String,
    pub model_id: Option<PhoneticAnalysisModelId>,
    pub model_revision: Option<String>,
    pub phone_set: String,
    pub precision: PhoneTimelinePrecision,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    #[serde(default)]
    pub metrics_json: TimelineMetrics,
    #[serde(default)]
    pub phones: Vec<DetectedPhone>,
    #[serde(default)]
    pub alignments: Vec<PhoneAlignment>,
    #[serde(default)]
    pub findings: Vec<PhoneticFinding>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sound_analysis: Option<SoundAnalysis>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PhoneTimelineSummary {
    pub id: PhoneTimelineId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub sentence_id: Option<SubtitleSentenceId>,
    pub parent_word_timeline_id: Option<WordTimelineId>,
    pub parent_phonetic_analysis_id: Option<PhoneticAnalysisId>,
    pub provider_id: String,
    pub provider_version: String,
    pub model_id: Option<PhoneticAnalysisModelId>,
    pub model_revision: Option<String>,
    pub phone_set: String,
    pub precision: PhoneTimelinePrecision,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    pub phone_count: u32,
    pub finding_count: u32,
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
    pub average_confidence: Option<f32>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
    pub can_activate: bool,
    pub can_archive: bool,
    pub can_delete: bool,
}
