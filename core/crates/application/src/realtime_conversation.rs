//! Provider-neutral realtime speech seam.
//!
//! This contract describes the hard common lifecycle shared by native
//! speech-to-speech providers. It intentionally does not expose either
//! provider's JSON events or use provider item ids as domain identity.

use std::sync::Arc;

use async_trait::async_trait;
use domain::{
    LanguageCode, RealtimeConversationSession as ConversationSession,
    RealtimeConversationSessionId, RealtimeConversationTurn, RealtimeProviderError,
    RealtimeProviderProfile, RealtimeProviderProfileId,
};

use crate::{ApplicationError, RealtimeConversationRepository, SecretStore};
use serde::{Deserialize, Serialize};

pub struct RealtimeConversationUseCases {
    repository: Arc<dyn RealtimeConversationRepository>,
}

impl RealtimeConversationUseCases {
    pub(crate) fn new(repository: Arc<dyn RealtimeConversationRepository>) -> Self {
        Self { repository }
    }

    pub fn register_profile(
        &self,
        mut profile: RealtimeProviderProfile,
        secret: &str,
        secret_store: &dyn SecretStore,
    ) -> Result<RealtimeProviderProfile, ApplicationError> {
        profile.auth_ref = secret_store.store(secret)?;
        self.repository.upsert_realtime_profile(&profile)
    }

    pub fn list_profiles(&self) -> Result<Vec<RealtimeProviderProfile>, ApplicationError> {
        self.repository.list_realtime_profiles()
    }

    pub fn profile(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<Option<RealtimeProviderProfile>, ApplicationError> {
        self.repository.get_realtime_profile(id)
    }

    pub fn resolve_secret(
        &self,
        profile: &RealtimeProviderProfile,
        secret_store: &dyn SecretStore,
    ) -> Result<Option<String>, ApplicationError> {
        Ok(secret_store.resolve(&profile.auth_ref)?)
    }

    pub fn delete_profile(
        &self,
        id: &RealtimeProviderProfileId,
        secret_store: &dyn SecretStore,
    ) -> Result<(), ApplicationError> {
        if let Some(profile) = self.repository.get_realtime_profile(id)? {
            secret_store.delete(&profile.auth_ref)?;
        }
        self.repository.delete_realtime_profile(id)
    }

    pub fn save_session(
        &self,
        session: ConversationSession,
    ) -> Result<ConversationSession, ApplicationError> {
        let terminal = matches!(
            session.status,
            domain::RealtimeSessionStatus::Completed
                | domain::RealtimeSessionStatus::Interrupted
                | domain::RealtimeSessionStatus::Failed
        );
        if terminal != session.ended_at_ms.is_some() {
            return Err(ApplicationError::Validation(
                "consistent realtime session lifecycle",
            ));
        }
        self.repository.save_realtime_session(&session)
    }

    pub fn session(
        &self,
        id: &RealtimeConversationSessionId,
    ) -> Result<Option<ConversationSession>, ApplicationError> {
        self.repository.get_realtime_session(id)
    }

    pub fn save_turn(
        &self,
        turn: RealtimeConversationTurn,
    ) -> Result<RealtimeConversationTurn, ApplicationError> {
        if turn.role == domain::RealtimeTurnRole::Learner
            && turn.status == domain::RealtimeTurnStatus::Finalized
            && !turn.is_authoritative_learner_output()
        {
            return Err(ApplicationError::Validation(
                "local transcript authority for finalized learner turn",
            ));
        }
        if turn.local_transcript.is_some() && !turn.is_authoritative_learner_output() {
            return Err(ApplicationError::Validation(
                "local transcript only on finalized learner turn",
            ));
        }
        self.repository.save_realtime_turn(&turn)
    }

    pub fn turns(
        &self,
        session_id: &RealtimeConversationSessionId,
    ) -> Result<Vec<RealtimeConversationTurn>, ApplicationError> {
        self.repository.list_realtime_turns(session_id)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RealtimeAudioFormat {
    Pcm16Mono24Khz,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RealtimeTurnDetection {
    ServerVad,
    Manual,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RealtimeSessionRequest {
    pub instructions: String,
    pub language: LanguageCode,
    pub voice: String,
    pub input_audio: RealtimeAudioFormat,
    pub output_audio: RealtimeAudioFormat,
    pub turn_detection: RealtimeTurnDetection,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RealtimeProviderDescriptor {
    pub adapter_kind: String,
    pub model_id: String,
    pub protocol_version: String,
    pub supports_server_vad: bool,
    pub supports_manual_turns: bool,
    pub supports_function_calls: bool,
}

/// Opaque provider ids correlate wire events only. They are never promoted to
/// conversation session/turn identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RealtimeEvent {
    SessionReady {
        provider_session_id: Option<String>,
    },
    SpeechStarted {
        provider_item_id: Option<String>,
    },
    SpeechStopped {
        provider_item_id: Option<String>,
    },
    TurnCommitted {
        provider_item_id: Option<String>,
    },
    ProviderTranscriptPreview {
        provider_item_id: Option<String>,
        text: String,
    },
    ProviderTranscriptFinal {
        provider_item_id: Option<String>,
        transcript: String,
    },
    AssistantTranscriptDelta {
        provider_item_id: Option<String>,
        delta: String,
    },
    AssistantTranscriptFinal {
        provider_item_id: Option<String>,
        transcript: String,
    },
    AssistantAudioDelta {
        provider_item_id: Option<String>,
        pcm16_mono_24khz: Vec<u8>,
    },
    ResponseDone {
        provider_response_id: Option<String>,
    },
    RateLimit {
        retry_after_ms: Option<u64>,
    },
}

#[async_trait]
pub trait RealtimeConversationSession: Send {
    async fn send_audio(&mut self, pcm16_mono_24khz: &[u8]) -> Result<(), RealtimeProviderError>;
    async fn commit_turn(&mut self) -> Result<(), RealtimeProviderError>;
    async fn cancel_response(&mut self) -> Result<(), RealtimeProviderError>;
    async fn next_event(&mut self) -> Result<Option<RealtimeEvent>, RealtimeProviderError>;
    async fn close(&mut self) -> Result<(), RealtimeProviderError>;
}

#[async_trait]
pub trait RealtimeConversationAdapter: Send + Sync {
    fn descriptor(&self) -> RealtimeProviderDescriptor;
    async fn connect(
        &self,
        request: &RealtimeSessionRequest,
    ) -> Result<Box<dyn RealtimeConversationSession>, RealtimeProviderError>;
}
