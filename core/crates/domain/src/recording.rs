use serde::{Deserialize, Serialize};

use crate::{
    LanguageCode, MediaId, PracticeAttemptId, PracticeTarget, RecordingAssetId, ShadowingAnalysisId,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlayableSegmentAvailability {
    Available,
    MissingMedia,
    MissingTimeline,
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

/// Transcription-ready facts about a local recording, with a content hash so
/// consumers can detect when its mutable path no longer names the same asset.
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
