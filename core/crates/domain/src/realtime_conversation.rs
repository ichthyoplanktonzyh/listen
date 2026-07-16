//! Provider-neutral realtime speech facts and lifecycle.
//!
//! Provider transcripts are deliberately separate from local learner-output
//! transcripts. A provider event can improve the live experience, but only a
//! completed bundled whisper.cpp result can make a learner turn authoritative.

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    LanguageCode, MediaId, ProductionAssistance, RealtimeConversationSessionId,
    RealtimeConversationTurnId, RealtimeProviderProfileId, RecordingAssetId,
    RecordingTranscriptionJobId,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RealtimeAdapterKind {
    OpenAiRealtime,
    QwenOmniRealtime,
}

impl RealtimeAdapterKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::OpenAiRealtime => "openai_realtime",
            Self::QwenOmniRealtime => "qwen_omni_realtime",
        }
    }
}

pub fn realtime_provider_profile_id(
    adapter_kind: RealtimeAdapterKind,
    base_url: &str,
    model_id: &str,
) -> RealtimeProviderProfileId {
    RealtimeProviderProfileId::from_fingerprint(
        "realtime-provider-profile",
        &format!(
            "{}\n{}\n{}",
            adapter_kind.as_str(),
            base_url.trim(),
            model_id.trim()
        ),
    )
}

/// Category-specific name for the shared opaque keychain handle.
pub type RealtimeAuthRef = crate::SecretRef;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RealtimeProviderProfile {
    pub id: RealtimeProviderProfileId,
    pub display_name: String,
    pub adapter_kind: RealtimeAdapterKind,
    pub base_url: String,
    pub model_id: String,
    pub voice: String,
    pub auth_ref: RealtimeAuthRef,
    pub timeout_ms: u64,
    pub created_at_ms: u64,
}

/// Optional context supplied by one conversation surface. It is not part of
/// session identity, so an open chat or role-play surface can omit it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RealtimeSurfaceContext {
    pub surface_kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_anchor: Option<RealtimeContentAnchor>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RealtimeContentAnchor {
    pub media_id: MediaId,
    pub start_ms: u64,
    pub end_ms: u64,
    pub source_text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RealtimeSessionStatus {
    Connecting,
    Active,
    Completed,
    Interrupted,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RealtimeConversationSession {
    pub id: RealtimeConversationSessionId,
    pub profile_id: RealtimeProviderProfileId,
    pub language: LanguageCode,
    pub context: Option<RealtimeSurfaceContext>,
    pub status: RealtimeSessionStatus,
    pub started_at_ms: u64,
    pub ended_at_ms: Option<u64>,
    pub failure_kind: Option<String>,
}

impl RealtimeConversationSession {
    pub fn activate(&mut self) -> Result<(), RealtimeLifecycleError> {
        if self.status != RealtimeSessionStatus::Connecting {
            return Err(RealtimeLifecycleError::InvalidSessionTransition);
        }
        self.status = RealtimeSessionStatus::Active;
        Ok(())
    }

    pub fn finish(&mut self, at_ms: u64) -> Result<(), RealtimeLifecycleError> {
        if self.status != RealtimeSessionStatus::Active {
            return Err(RealtimeLifecycleError::InvalidSessionTransition);
        }
        self.status = RealtimeSessionStatus::Completed;
        self.ended_at_ms = Some(at_ms);
        Ok(())
    }

    pub fn interrupt(&mut self, at_ms: u64) -> Result<(), RealtimeLifecycleError> {
        if !matches!(
            self.status,
            RealtimeSessionStatus::Connecting | RealtimeSessionStatus::Active
        ) {
            return Err(RealtimeLifecycleError::InvalidSessionTransition);
        }
        self.status = RealtimeSessionStatus::Interrupted;
        self.ended_at_ms = Some(at_ms);
        Ok(())
    }

    pub fn fail(
        &mut self,
        kind: impl Into<String>,
        at_ms: u64,
    ) -> Result<(), RealtimeLifecycleError> {
        if !matches!(
            self.status,
            RealtimeSessionStatus::Connecting | RealtimeSessionStatus::Active
        ) {
            return Err(RealtimeLifecycleError::InvalidSessionTransition);
        }
        self.status = RealtimeSessionStatus::Failed;
        self.failure_kind = Some(kind.into());
        self.ended_at_ms = Some(at_ms);
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RealtimeTurnRole {
    Learner,
    Assistant,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RealtimeTurnStatus {
    Streaming,
    AwaitingLocalTranscript,
    Finalized,
    Interrupted,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderTranscript {
    pub text: String,
    pub provider_item_id: Option<String>,
    pub received_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalLearnerTranscript {
    pub text: String,
    pub recording_asset_id: RecordingAssetId,
    pub transcription_job_id: RecordingTranscriptionJobId,
    pub completed_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RealtimeConversationTurn {
    pub id: RealtimeConversationTurnId,
    pub session_id: RealtimeConversationSessionId,
    pub sequence: u32,
    pub role: RealtimeTurnRole,
    pub status: RealtimeTurnStatus,
    pub assistance: ProductionAssistance,
    pub provider_transcript: Option<ProviderTranscript>,
    pub local_transcript: Option<LocalLearnerTranscript>,
    pub recording_asset_id: Option<RecordingAssetId>,
    pub started_at_ms: u64,
    pub ended_at_ms: Option<u64>,
    pub failure_kind: Option<String>,
}

impl RealtimeConversationTurn {
    pub fn record_provider_transcript(
        &mut self,
        transcript: ProviderTranscript,
    ) -> Result<(), RealtimeLifecycleError> {
        if !matches!(
            self.status,
            RealtimeTurnStatus::Streaming | RealtimeTurnStatus::AwaitingLocalTranscript
        ) {
            return Err(RealtimeLifecycleError::InvalidTurnTransition);
        }
        self.provider_transcript = Some(transcript);
        Ok(())
    }

    pub fn await_local_transcript(
        &mut self,
        recording_asset_id: RecordingAssetId,
        at_ms: u64,
    ) -> Result<(), RealtimeLifecycleError> {
        if self.role != RealtimeTurnRole::Learner || self.status != RealtimeTurnStatus::Streaming {
            return Err(RealtimeLifecycleError::InvalidTurnTransition);
        }
        self.recording_asset_id = Some(recording_asset_id);
        self.status = RealtimeTurnStatus::AwaitingLocalTranscript;
        self.ended_at_ms = Some(at_ms);
        Ok(())
    }

    pub fn finalize_local(
        &mut self,
        transcript: LocalLearnerTranscript,
    ) -> Result<(), RealtimeLifecycleError> {
        if self.role != RealtimeTurnRole::Learner
            || self.status != RealtimeTurnStatus::AwaitingLocalTranscript
            || self.recording_asset_id.as_ref() != Some(&transcript.recording_asset_id)
            || transcript.text.trim().is_empty()
        {
            return Err(RealtimeLifecycleError::LocalAuthorityRequired);
        }
        self.local_transcript = Some(transcript);
        self.status = RealtimeTurnStatus::Finalized;
        Ok(())
    }

    pub fn finalize_assistant(&mut self, at_ms: u64) -> Result<(), RealtimeLifecycleError> {
        if self.role != RealtimeTurnRole::Assistant || self.status != RealtimeTurnStatus::Streaming
        {
            return Err(RealtimeLifecycleError::InvalidTurnTransition);
        }
        self.status = RealtimeTurnStatus::Finalized;
        self.ended_at_ms = Some(at_ms);
        Ok(())
    }

    pub fn interrupt(&mut self, at_ms: u64) -> Result<(), RealtimeLifecycleError> {
        if !matches!(
            self.status,
            RealtimeTurnStatus::Streaming | RealtimeTurnStatus::AwaitingLocalTranscript
        ) {
            return Err(RealtimeLifecycleError::InvalidTurnTransition);
        }
        self.status = RealtimeTurnStatus::Interrupted;
        self.ended_at_ms = Some(at_ms);
        Ok(())
    }

    pub fn is_authoritative_learner_output(&self) -> bool {
        self.role == RealtimeTurnRole::Learner
            && self.status == RealtimeTurnStatus::Finalized
            && self.local_transcript.is_some()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum RealtimeLifecycleError {
    #[error("invalid realtime session lifecycle transition")]
    InvalidSessionTransition,
    #[error("invalid realtime turn lifecycle transition")]
    InvalidTurnTransition,
    #[error("a completed local whisper.cpp transcript is required for learner authority")]
    LocalAuthorityRequired,
}

#[derive(Debug, Clone, PartialEq, Eq, Error, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum RealtimeProviderError {
    #[error("realtime provider is offline or unreachable")]
    Offline,
    #[error("realtime provider authentication failed")]
    Auth,
    #[error("realtime provider rate limited the session")]
    RateLimit { retry_after_ms: Option<u64> },
    #[error("realtime provider timed out")]
    Timeout,
    #[error("realtime provider does not support {capability}")]
    UnsupportedCapability { capability: String },
    #[error("realtime provider disconnected")]
    Disconnected,
    #[error("realtime provider protocol error: {detail}")]
    Protocol { detail: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    fn learner_turn() -> RealtimeConversationTurn {
        RealtimeConversationTurn {
            id: RealtimeConversationTurnId::parse("turn-1").unwrap(),
            session_id: RealtimeConversationSessionId::parse("session-1").unwrap(),
            sequence: 1,
            role: RealtimeTurnRole::Learner,
            status: RealtimeTurnStatus::Streaming,
            assistance: ProductionAssistance::ContentAnchored,
            provider_transcript: None,
            local_transcript: None,
            recording_asset_id: None,
            started_at_ms: 10,
            ended_at_ms: None,
            failure_kind: None,
        }
    }

    #[test]
    fn provider_transcript_never_makes_learner_output_authoritative() {
        let mut turn = learner_turn();
        turn.record_provider_transcript(ProviderTranscript {
            text: "remote guess".into(),
            provider_item_id: Some("opaque-provider-item".into()),
            received_at_ms: 20,
        })
        .unwrap();
        assert!(!turn.is_authoritative_learner_output());
        assert!(matches!(
            turn.finalize_local(LocalLearnerTranscript {
                text: "remote guess".into(),
                recording_asset_id: RecordingAssetId::parse("missing-recording").unwrap(),
                transcription_job_id: RecordingTranscriptionJobId::parse("job-1").unwrap(),
                completed_at_ms: 30,
            }),
            Err(RealtimeLifecycleError::LocalAuthorityRequired)
        ));
    }

    #[test]
    fn matching_recording_and_local_transcript_finalize_learner_output() {
        let mut turn = learner_turn();
        let recording_id = RecordingAssetId::parse("recording-1").unwrap();
        turn.await_local_transcript(recording_id.clone(), 25)
            .unwrap();
        turn.finalize_local(LocalLearnerTranscript {
            text: "learner words".into(),
            recording_asset_id: recording_id,
            transcription_job_id: RecordingTranscriptionJobId::parse("job-1").unwrap(),
            completed_at_ms: 40,
        })
        .unwrap();
        assert!(turn.is_authoritative_learner_output());
    }

    #[test]
    fn interrupted_turn_cannot_become_authoritative() {
        let mut turn = learner_turn();
        turn.interrupt(20).unwrap();
        assert!(!turn.is_authoritative_learner_output());
        assert!(
            turn.await_local_transcript(RecordingAssetId::parse("recording-1").unwrap(), 30)
                .is_err()
        );
    }
}
