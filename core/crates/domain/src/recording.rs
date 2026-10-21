use serde::{Deserialize, Serialize};

use crate::{LanguageCode, MediaId, PracticeTarget, RecordingAssetId};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordingSourceAvailability {
    Available,
    MissingMedia,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecordingSourceSegment {
    pub media_id: Option<MediaId>,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub subtitle_snapshot: String,
    pub availability: RecordingSourceAvailability,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecordingAsset {
    pub id: RecordingAssetId,
    pub file_path: String,
    pub created_at_ms: u64,
    pub duration_ms: u64,
    pub target: PracticeTarget,
    pub source_segment: RecordingSourceSegment,
    pub language: LanguageCode,
    pub audio: RecordingAudioMetadata,
    pub recorder_version: String,
}

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
