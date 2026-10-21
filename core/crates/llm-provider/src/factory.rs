//! Builds the subtitle-analysis runtime from a stored provider profile and a resolved secret.

use std::time::Duration;

use application::{SemanticLlmRuntime, SemanticLlmRuntimeFactory, SenseGroupPartitionProvider};
use domain::{CapabilityClaim, LlmAdapterKind, LlmProviderError, LlmProviderProfile};

use crate::{AnthropicMessagesAdapter, LlmSemanticProvider, OpenAiChatAdapter};

enum BuiltSemanticProvider {
    OpenAi(LlmSemanticProvider<OpenAiChatAdapter>),
    Anthropic(LlmSemanticProvider<AnthropicMessagesAdapter>),
}

impl BuiltSemanticProvider {
    fn build(
        profile: &LlmProviderProfile,
        api_key: Option<String>,
    ) -> Result<Self, LlmProviderError> {
        let timeout = Duration::from_millis(profile.timeout_ms);
        match profile.adapter_kind {
            LlmAdapterKind::OpenAiChatCompletions => {
                let adapter = OpenAiChatAdapter::new_with_pool(
                    &profile.base_url,
                    &profile.model_id,
                    api_key,
                    timeout,
                    profile.batch_policy.max_idle_connections_per_host,
                )?
                .with_capability(profile.capability);
                Ok(Self::OpenAi(LlmSemanticProvider::new(adapter)))
            }
            LlmAdapterKind::AnthropicMessages => {
                let adapter = AnthropicMessagesAdapter::new_with_pool(
                    &profile.base_url,
                    &profile.model_id,
                    api_key,
                    profile.protocol_version.clone(),
                    timeout,
                    profile.batch_policy.max_idle_connections_per_host,
                )?
                .with_capability(profile.capability);
                Ok(Self::Anthropic(LlmSemanticProvider::new(adapter)))
            }
        }
    }

    fn as_sense_groups(&self) -> &dyn SenseGroupPartitionProvider {
        match self {
            Self::OpenAi(provider) => provider,
            Self::Anthropic(provider) => provider,
        }
    }

    async fn probe(&self) -> Result<CapabilityClaim, LlmProviderError> {
        use application::LlmChatAdapter;
        match self {
            Self::OpenAi(provider) => provider.adapter().probe_structured_output().await,
            Self::Anthropic(provider) => provider.adapter().probe_structured_output().await,
        }
    }
}

#[async_trait::async_trait]
impl SemanticLlmRuntime for BuiltSemanticProvider {
    fn sense_groups(&self) -> &dyn SenseGroupPartitionProvider {
        self.as_sense_groups()
    }

    async fn probe_structured_output(&self) -> Result<CapabilityClaim, LlmProviderError> {
        self.probe().await
    }
}

#[derive(Debug, Default)]
pub struct LlmSemanticRuntimeFactory;

impl LlmSemanticRuntimeFactory {
    pub fn new() -> Self {
        Self
    }
}

impl SemanticLlmRuntimeFactory for LlmSemanticRuntimeFactory {
    fn build(
        &self,
        profile: &LlmProviderProfile,
        secret: Option<String>,
    ) -> Result<Box<dyn SemanticLlmRuntime>, LlmProviderError> {
        BuiltSemanticProvider::build(profile, secret)
            .map(|runtime| Box::new(runtime) as Box<dyn SemanticLlmRuntime>)
    }
}
