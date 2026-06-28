use serde::{Deserialize, Serialize};

use crate::{
    MediaId, SubtitleSentenceId, SubtitleTrackId, TimelineCreator, TimelineMetrics, TimelineStatus,
    WordTimelineId,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TimingSource {
    AsrReported,
    AsrAligned,
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
    pub metrics_json: TimelineMetrics,
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
