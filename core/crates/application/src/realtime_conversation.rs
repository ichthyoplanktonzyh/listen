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

use crate::{
    ApplicationError, RealtimeConversationAdapterFactory, RealtimeConversationRepository,
    SecretStore,
};
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
        let previous_auth_ref = self
            .repository
            .get_realtime_profile(&profile.id)?
            .map(|previous| previous.auth_ref);
        let new_auth_ref = secret_store.store(secret)?;
        profile.auth_ref = new_auth_ref.clone();
        let saved = match self.repository.upsert_realtime_profile(&profile) {
            Ok(saved) => saved,
            Err(error) => {
                if secret_store.delete(&new_auth_ref).is_err() {
                    return Err(crate::SecretStoreError(
                        "credential cleanup failed after realtime profile persistence failed"
                            .into(),
                    )
                    .into());
                }
                return Err(error);
            }
        };
        if let Some(previous_auth_ref) = previous_auth_ref
            && previous_auth_ref != new_auth_ref
            && secret_store.delete(&previous_auth_ref).is_err()
        {
            return Err(crate::SecretStoreError(
                "old credential cleanup failed after realtime profile rotation".into(),
            )
            .into());
        }
        Ok(saved)
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
        let auth_ref = self
            .repository
            .get_realtime_profile(id)?
            .map(|profile| profile.auth_ref);
        self.repository.delete_realtime_profile(id)?;
        if let Some(auth_ref) = auth_ref {
            secret_store.delete(&auth_ref)?;
        }
        Ok(())
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

    pub fn sessions(&self) -> Result<Vec<ConversationSession>, ApplicationError> {
        self.repository.list_realtime_sessions()
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

    /// Resolves a profile and credential, asks the injected adapter factory to
    /// assemble the protocol implementation, validates the requested turn
    /// mode against implemented capabilities, and derives provider-specific
    /// audio formats from the neutral descriptor.
    pub fn prepare_connection(
        &self,
        id: &RealtimeProviderProfileId,
        options: RealtimeConnectionOptions,
        secret_store: &dyn SecretStore,
        factory: &dyn RealtimeConversationAdapterFactory,
    ) -> Result<PreparedRealtimeConnection, ApplicationError> {
        let profile = self
            .profile(id)?
            .ok_or(ApplicationError::NotFound("realtime provider profile"))?;
        let credential = self
            .resolve_secret(&profile, secret_store)?
            .ok_or(RealtimeProviderError::Auth)?;
        let adapter = factory.build(&profile, credential);
        let descriptor = adapter.descriptor();
        if descriptor.adapter_kind != profile.adapter_kind.as_str() {
            return Err(RealtimeProviderError::Protocol {
                detail: "realtime adapter kind did not match the configured profile".into(),
            }
            .into());
        }
        let turn_detection = if options.manual_turns {
            if !descriptor.capabilities.supports_manual_turns {
                return Err(RealtimeProviderError::UnsupportedCapability {
                    capability: "manual turns".into(),
                }
                .into());
            }
            RealtimeTurnDetection::Manual
        } else {
            if !descriptor.capabilities.supports_server_vad {
                return Err(RealtimeProviderError::UnsupportedCapability {
                    capability: "server VAD".into(),
                }
                .into());
            }
            RealtimeTurnDetection::ServerVad
        };
        Ok(PreparedRealtimeConnection {
            adapter,
            request: RealtimeSessionRequest {
                instructions: options.instructions,
                language: options.language,
                voice: profile.voice,
                input_audio: descriptor.capabilities.input_audio,
                output_audio: descriptor.capabilities.output_audio,
                turn_detection,
            },
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RealtimeConnectionOptions {
    pub language: LanguageCode,
    pub instructions: String,
    pub manual_turns: bool,
}

/// A provider-neutral connection plan. HTTP owns only the client WebSocket
/// framing; this module owns provider selection, capability policy and the
/// semantic session request.
pub struct PreparedRealtimeConnection {
    adapter: Box<dyn RealtimeConversationAdapter>,
    request: RealtimeSessionRequest,
}

impl PreparedRealtimeConnection {
    pub async fn connect(
        self,
    ) -> Result<Box<dyn RealtimeConversationSession>, RealtimeProviderError> {
        self.adapter.connect(&self.request).await
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RealtimeAudioFormat {
    Pcm16Mono16Khz,
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
    /// Capabilities implemented by this adapter, not every capability marketed
    /// by the selected provider/model.
    pub capabilities: RealtimeProviderCapabilities,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RealtimeTransportKind {
    WebSocket,
    WebRtc,
    BidirectionalStream,
}

/// Honest feature boundary for a concrete realtime adapter. A `false` value
/// means callers must not infer support from provider documentation alone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RealtimeProviderCapabilities {
    pub transport: RealtimeTransportKind,
    pub input_audio: RealtimeAudioFormat,
    pub output_audio: RealtimeAudioFormat,
    pub supports_server_vad: bool,
    pub supports_manual_turns: bool,
    pub supports_provider_input_transcript: bool,
    pub supports_assistant_transcript: bool,
    pub supports_response_cancel: bool,
    pub supports_output_audio_clear: bool,
    pub supports_conversation_truncate: bool,
    pub supports_function_calls: bool,
    pub supports_image_input: bool,
    pub supports_session_resume: bool,
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
        /// Provider audio-timeline position of the detected speech onset.
        /// Used only for correlation/capture boundaries, never as turn identity.
        audio_start_ms: Option<u64>,
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
    async fn send_audio(&mut self, pcm16_mono: &[u8]) -> Result<(), RealtimeProviderError>;
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

#[cfg(test)]
mod connection_tests {
    use super::*;
    use crate::{InMemorySecretStore, RealtimeConversationAdapterFactory};
    use domain::{
        RealtimeAdapterKind, RealtimeConversationTurnId, RealtimeProviderProfile, SecretRef,
        realtime_provider_profile_id,
    };
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicBool, Ordering};

    struct ProfileRepository {
        profile: Mutex<Option<RealtimeProviderProfile>>,
    }

    impl RealtimeConversationRepository for ProfileRepository {
        fn upsert_realtime_profile(
            &self,
            profile: &RealtimeProviderProfile,
        ) -> Result<RealtimeProviderProfile, ApplicationError> {
            *self.profile.lock().unwrap() = Some(profile.clone());
            Ok(profile.clone())
        }

        fn get_realtime_profile(
            &self,
            id: &RealtimeProviderProfileId,
        ) -> Result<Option<RealtimeProviderProfile>, ApplicationError> {
            Ok(self
                .profile
                .lock()
                .unwrap()
                .clone()
                .filter(|profile| &profile.id == id))
        }

        fn list_realtime_profiles(&self) -> Result<Vec<RealtimeProviderProfile>, ApplicationError> {
            Ok(self.profile.lock().unwrap().clone().into_iter().collect())
        }

        fn delete_realtime_profile(
            &self,
            _id: &RealtimeProviderProfileId,
        ) -> Result<(), ApplicationError> {
            *self.profile.lock().unwrap() = None;
            Ok(())
        }

        fn save_realtime_session(
            &self,
            session: &ConversationSession,
        ) -> Result<ConversationSession, ApplicationError> {
            Ok(session.clone())
        }

        fn get_realtime_session(
            &self,
            _id: &RealtimeConversationSessionId,
        ) -> Result<Option<ConversationSession>, ApplicationError> {
            Ok(None)
        }

        fn list_realtime_sessions(&self) -> Result<Vec<ConversationSession>, ApplicationError> {
            Ok(Vec::new())
        }

        fn save_realtime_turn(
            &self,
            turn: &RealtimeConversationTurn,
        ) -> Result<RealtimeConversationTurn, ApplicationError> {
            Ok(turn.clone())
        }

        fn get_realtime_turn(
            &self,
            _id: &RealtimeConversationTurnId,
        ) -> Result<Option<RealtimeConversationTurn>, ApplicationError> {
            Ok(None)
        }

        fn list_realtime_turns(
            &self,
            _session_id: &RealtimeConversationSessionId,
        ) -> Result<Vec<RealtimeConversationTurn>, ApplicationError> {
            Ok(Vec::new())
        }
    }

    struct FakeSession;

    #[async_trait]
    impl RealtimeConversationSession for FakeSession {
        async fn send_audio(&mut self, _pcm16_mono: &[u8]) -> Result<(), RealtimeProviderError> {
            Ok(())
        }

        async fn commit_turn(&mut self) -> Result<(), RealtimeProviderError> {
            Ok(())
        }

        async fn cancel_response(&mut self) -> Result<(), RealtimeProviderError> {
            Ok(())
        }

        async fn next_event(&mut self) -> Result<Option<RealtimeEvent>, RealtimeProviderError> {
            Ok(None)
        }

        async fn close(&mut self) -> Result<(), RealtimeProviderError> {
            Ok(())
        }
    }

    struct FakeAdapter {
        descriptor: RealtimeProviderDescriptor,
        connect_error: Option<RealtimeProviderError>,
    }

    #[async_trait]
    impl RealtimeConversationAdapter for FakeAdapter {
        fn descriptor(&self) -> RealtimeProviderDescriptor {
            self.descriptor.clone()
        }

        async fn connect(
            &self,
            _request: &RealtimeSessionRequest,
        ) -> Result<Box<dyn RealtimeConversationSession>, RealtimeProviderError> {
            match &self.connect_error {
                Some(error) => Err(error.clone()),
                None => Ok(Box::new(FakeSession)),
            }
        }
    }

    struct FakeFactory {
        descriptor: RealtimeProviderDescriptor,
        connect_error: Option<RealtimeProviderError>,
        received_credential: Arc<AtomicBool>,
    }

    impl RealtimeConversationAdapterFactory for FakeFactory {
        fn build(
            &self,
            _profile: &RealtimeProviderProfile,
            credential: String,
        ) -> Box<dyn RealtimeConversationAdapter> {
            self.received_credential
                .store(!credential.is_empty(), Ordering::SeqCst);
            Box::new(FakeAdapter {
                descriptor: self.descriptor.clone(),
                connect_error: self.connect_error.clone(),
            })
        }
    }

    fn capabilities(
        input_audio: RealtimeAudioFormat,
        supports_manual_turns: bool,
    ) -> RealtimeProviderCapabilities {
        RealtimeProviderCapabilities {
            transport: RealtimeTransportKind::WebSocket,
            input_audio,
            output_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
            supports_server_vad: true,
            supports_manual_turns,
            supports_provider_input_transcript: true,
            supports_assistant_transcript: true,
            supports_response_cancel: true,
            supports_output_audio_clear: false,
            supports_conversation_truncate: false,
            supports_function_calls: false,
            supports_image_input: false,
            supports_session_resume: false,
        }
    }

    fn profile(auth_ref: SecretRef) -> RealtimeProviderProfile {
        let adapter_kind = RealtimeAdapterKind::QwenOmniRealtime;
        let base_url = "wss://provider.invalid/realtime";
        let model_id = "test-model";
        RealtimeProviderProfile {
            id: realtime_provider_profile_id(adapter_kind, base_url, model_id),
            display_name: "Test".into(),
            adapter_kind,
            base_url: base_url.into(),
            model_id: model_id.into(),
            voice: "test-voice".into(),
            auth_ref,
            timeout_ms: 1_000,
            created_at_ms: 1,
        }
    }

    fn options(manual_turns: bool) -> RealtimeConnectionOptions {
        RealtimeConnectionOptions {
            language: LanguageCode::parse("en").unwrap(),
            instructions: "Discuss the source.".into(),
            manual_turns,
        }
    }

    fn setup(
        descriptor: RealtimeProviderDescriptor,
        connect_error: Option<RealtimeProviderError>,
    ) -> (
        RealtimeConversationUseCases,
        InMemorySecretStore,
        FakeFactory,
        RealtimeProviderProfileId,
    ) {
        let secrets = InMemorySecretStore::new();
        let auth_ref = secrets.store("not-observed").unwrap();
        let profile = profile(auth_ref);
        let id = profile.id.clone();
        let repository = Arc::new(ProfileRepository {
            profile: Mutex::new(Some(profile)),
        });
        let received_credential = Arc::new(AtomicBool::new(false));
        (
            RealtimeConversationUseCases::new(repository),
            secrets,
            FakeFactory {
                descriptor,
                connect_error,
                received_credential,
            },
            id,
        )
    }

    #[test]
    fn injected_factory_drives_audio_and_turn_policy_without_vendor_branching() {
        let descriptor = RealtimeProviderDescriptor {
            adapter_kind: "qwen_omni_realtime".into(),
            model_id: "test-model".into(),
            protocol_version: "fake-v1".into(),
            capabilities: capabilities(RealtimeAudioFormat::Pcm16Mono16Khz, true),
        };
        let (use_cases, secrets, factory, id) = setup(descriptor, None);

        let prepared = use_cases
            .prepare_connection(&id, options(true), &secrets, &factory)
            .unwrap();

        assert!(factory.received_credential.load(Ordering::SeqCst));
        assert_eq!(
            prepared.request.input_audio,
            RealtimeAudioFormat::Pcm16Mono16Khz
        );
        assert_eq!(
            prepared.request.output_audio,
            RealtimeAudioFormat::Pcm16Mono24Khz
        );
        assert_eq!(
            prepared.request.turn_detection,
            RealtimeTurnDetection::Manual
        );
    }

    #[test]
    fn unsupported_manual_turns_fail_before_provider_connection() {
        let descriptor = RealtimeProviderDescriptor {
            adapter_kind: "qwen_omni_realtime".into(),
            model_id: "test-model".into(),
            protocol_version: "fake-v1".into(),
            capabilities: capabilities(RealtimeAudioFormat::Pcm16Mono16Khz, false),
        };
        let (use_cases, secrets, factory, id) = setup(descriptor, None);

        let error = use_cases
            .prepare_connection(&id, options(true), &secrets, &factory)
            .err()
            .expect("manual turns rejected");

        assert!(matches!(
            error,
            ApplicationError::RealtimeProvider(RealtimeProviderError::UnsupportedCapability { .. })
        ));
    }

    #[tokio::test]
    async fn provider_connect_errors_keep_the_neutral_taxonomy() {
        let descriptor = RealtimeProviderDescriptor {
            adapter_kind: "qwen_omni_realtime".into(),
            model_id: "test-model".into(),
            protocol_version: "fake-v1".into(),
            capabilities: capabilities(RealtimeAudioFormat::Pcm16Mono16Khz, true),
        };
        let (use_cases, secrets, factory, id) =
            setup(descriptor, Some(RealtimeProviderError::Auth));
        let prepared = use_cases
            .prepare_connection(&id, options(false), &secrets, &factory)
            .unwrap();

        assert_eq!(
            prepared.connect().await.err(),
            Some(RealtimeProviderError::Auth)
        );
    }
}
