use serde::{Deserialize, Serialize};

use crate::{MediaId, SubtitleTrackId, TranscriptionJobId, TranscriptionModelId};

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
