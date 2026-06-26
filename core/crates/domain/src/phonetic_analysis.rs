use serde::{Deserialize, Serialize};

use crate::{
    DomainError, MediaId, PhoneticAnalysisId, PhoneticAnalysisJobId, PhoneticAnalysisModelId,
    PhoneticFindingId, SoundAnalysis, SubtitleSentenceId, SubtitleTrackId,
};

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
    pub display_ipa: String,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sound_analysis: Option<SoundAnalysis>,
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{MediaId, PhoneticAnalysisModelId, SubtitleTrackId};

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
                    display_ipa: "h".into(),
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
                    display_ipa: "ə".into(),
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
            sound_analysis: None,
            analyzer_version: "v1".into(),
            created_at_ms: 1,
        }
    }
}
