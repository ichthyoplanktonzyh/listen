use serde::{Deserialize, Serialize};

use crate::{RecordingAssetId, RecordingTranscriptionJobId, TranscriptionModelId};

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

/// A short microphone recording transcription is Core's retained transcription
/// path (whole-media transcription jobs were removed): it consumes an existing
/// `RecordingAsset`, never imports a subtitle track, and preserves raw ASR
/// output for later user correction rather than treating it as speaking
/// evidence.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordingTranscriptionStatus {
    Queued,
    Transcribing,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecordingTranscriptProvenance {
    pub provider_id: String,
    pub provider_version: String,
    pub runtime_id: String,
    pub runtime_version: String,
    pub model_id: TranscriptionModelId,
    pub model_revision: String,
    pub model_checksum_sha256: String,
    pub recording_content_sha256: String,
    pub requested_language: Option<String>,
    pub detected_language: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecordingTranscriptionJob {
    pub id: RecordingTranscriptionJobId,
    pub recording_asset_id: RecordingAssetId,
    pub status: RecordingTranscriptionStatus,
    pub raw_transcript: Option<String>,
    pub segments: Vec<TranscriptionSegment>,
    pub provenance: RecordingTranscriptProvenance,
    pub error_code: Option<String>,
    pub error_message: Option<String>,
    pub created_at_ms: u64,
    pub started_at_ms: Option<u64>,
    pub completed_at_ms: Option<u64>,
    pub latency_ms: Option<u64>,
}
