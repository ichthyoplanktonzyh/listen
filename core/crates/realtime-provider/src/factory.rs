use std::time::Duration;

use application::{RealtimeConversationAdapter, RealtimeConversationAdapterFactory};
use domain::{RealtimeAdapterKind, RealtimeProviderError, RealtimeProviderProfile};

use crate::{
    LocalCascadeRealtimeAdapter, OpenAiRealtimeAdapter, QwenRealtimeAdapter, RealtimeAdapterConfig,
};

/// Native protocol factory implementing the application-owned realtime seam.
///
/// Provider selection, timeout normalization and credential placement stay
/// here so HTTP transport code never learns a vendor protocol.
#[derive(Debug, Default)]
pub struct NativeRealtimeAdapterFactory;

impl NativeRealtimeAdapterFactory {
    pub fn new() -> Self {
        Self
    }
}

impl RealtimeConversationAdapterFactory for NativeRealtimeAdapterFactory {
    fn build(
        &self,
        profile: &RealtimeProviderProfile,
        credential: Option<String>,
    ) -> Result<Box<dyn RealtimeConversationAdapter>, RealtimeProviderError> {
        if profile.adapter_kind != RealtimeAdapterKind::LocalCascadeRealtime && credential.is_none()
        {
            return Err(RealtimeProviderError::Auth);
        }
        let config = RealtimeAdapterConfig {
            base_url: profile.base_url.clone(),
            model_id: profile.model_id.clone(),
            credential,
            timeout: Duration::from_millis(profile.timeout_ms.clamp(1_000, 120_000)),
            require_loopback: profile.adapter_kind == RealtimeAdapterKind::LocalCascadeRealtime,
        };
        Ok(match profile.adapter_kind {
            RealtimeAdapterKind::OpenAiRealtime => Box::new(OpenAiRealtimeAdapter::new(config)),
            RealtimeAdapterKind::QwenOmniRealtime => Box::new(QwenRealtimeAdapter::new(config)),
            RealtimeAdapterKind::LocalCascadeRealtime => {
                Box::new(LocalCascadeRealtimeAdapter::new(config))
            }
        })
    }
}
