use serde::{Deserialize, Serialize};

use crate::{
    ChunkId, ChunkTimelineId, MediaId, SubtitleSentenceId, SubtitleTrackId, TimelineCreator,
    TimelineStatus, WordTimelineId,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChunkTimelinePrecision {
    Precise,
    Approximate,
    TextOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChunkBoundarySource {
    Pause,
    Punctuation,
    Semantic,
    Lengthening,
    Learned,
    User,
    LengthLimit,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkTimeline {
    pub id: ChunkTimelineId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub parent_word_timeline_id: Option<WordTimelineId>,
    pub provider_id: String,
    pub provider_version: String,
    pub algorithm: String,
    pub precision: ChunkTimelinePrecision,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    #[serde(default)]
    pub metrics_json: serde_json::Value,
    pub chunks: Vec<ChunkTimelineChunk>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkTimelineChunk {
    pub id: ChunkId,
    pub sentence_id: SubtitleSentenceId,
    pub chunk_index: u32,
    pub start_word_index: u32,
    pub end_word_index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    #[serde(default)]
    pub boundary_sources: Vec<ChunkBoundarySource>,
    pub confidence: f32,
    #[serde(default)]
    pub warnings: Vec<String>,
    #[serde(default)]
    pub evidence_json: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChunkTimelineSummary {
    pub id: ChunkTimelineId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub parent_word_timeline_id: Option<WordTimelineId>,
    pub provider_id: String,
    pub provider_version: String,
    pub algorithm: String,
    pub precision: ChunkTimelinePrecision,
    pub created_by: TimelineCreator,
    pub status: TimelineStatus,
    pub chunk_count: u32,
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
    pub average_confidence: Option<f32>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
    pub can_activate: bool,
    pub can_archive: bool,
    pub can_delete: bool,
}
