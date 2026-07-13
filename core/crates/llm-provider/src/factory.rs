//! Builds a semantic provider from a stored profile + a resolved secret.
//!
//! This is the one place adapter kind maps to a concrete adapter. Adding a
//! protocol is a new match arm here plus a new adapter module — the rubric and
//! judgment contracts above do not change (Phase 3.12 exit signal).

use std::time::Duration;

use application::{SemanticJudgeProvider, SemanticRubricProvider};
use domain::{CapabilityClaim, LlmAdapterKind, LlmProviderError, LlmProviderProfile};

use crate::{AnthropicMessagesAdapter, LlmSemanticProvider, OpenAiChatAdapter};

/// A built provider, keyed by protocol. Exposes both application seams plus the
/// capability probe over one constructed adapter.
pub enum BuiltSemanticProvider {
    OpenAi(LlmSemanticProvider<OpenAiChatAdapter>),
    Anthropic(LlmSemanticProvider<AnthropicMessagesAdapter>),
}

impl BuiltSemanticProvider {
    /// Constructs the provider for `profile`, injecting the already-resolved
    /// `api_key` (from the secure store). `None` is a keyless/local endpoint.
    pub fn build(
        profile: &LlmProviderProfile,
        api_key: Option<String>,
    ) -> Result<Self, LlmProviderError> {
        let timeout = Duration::from_millis(profile.timeout_ms);
        match profile.adapter_kind {
            LlmAdapterKind::OpenAiChatCompletions => {
                let adapter =
                    OpenAiChatAdapter::new(&profile.base_url, &profile.model_id, api_key, timeout)?
                        .with_capability(profile.capability);
                Ok(Self::OpenAi(LlmSemanticProvider::new(adapter)))
            }
            LlmAdapterKind::AnthropicMessages => {
                let adapter = AnthropicMessagesAdapter::new(
                    &profile.base_url,
                    &profile.model_id,
                    api_key,
                    profile.protocol_version.clone(),
                    timeout,
                )?
                .with_capability(profile.capability);
                Ok(Self::Anthropic(LlmSemanticProvider::new(adapter)))
            }
        }
    }

    pub fn as_judge(&self) -> &dyn SemanticJudgeProvider {
        match self {
            Self::OpenAi(provider) => provider,
            Self::Anthropic(provider) => provider,
        }
    }

    pub fn as_rubric(&self) -> &dyn SemanticRubricProvider {
        match self {
            Self::OpenAi(provider) => provider,
            Self::Anthropic(provider) => provider,
        }
    }

    /// Measures real structured-output support against the endpoint.
    pub async fn probe_structured_output(&self) -> Result<CapabilityClaim, LlmProviderError> {
        use application::LlmChatAdapter;
        match self {
            Self::OpenAi(provider) => provider.adapter().probe_structured_output().await,
            Self::Anthropic(provider) => provider.adapter().probe_structured_output().await,
        }
    }
}
