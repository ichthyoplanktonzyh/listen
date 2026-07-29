//! Builds a semantic provider from a stored profile + a resolved secret.
//!
//! This is the one place adapter kind maps to a concrete adapter. Adding a
//! protocol is a new match arm here plus a new adapter module — the rubric and
//! judgment contracts above do not change (Phase 3.12 exit signal).

use std::time::Duration;

use application::{
    OutputFeedbackProvider, SemanticJudgeProvider, SemanticLlmRuntime, SemanticLlmRuntimeFactory,
    SemanticRubricProvider, SenseGroupPartitionProvider,
};
use domain::{CapabilityClaim, LlmAdapterKind, LlmProviderError, LlmProviderProfile};

use crate::{AnthropicMessagesAdapter, LlmSemanticProvider, OpenAiChatAdapter};

/// A built provider, keyed by protocol. Exposes both application seams plus the
/// capability probe over one constructed adapter.
enum BuiltSemanticProvider {
    OpenAi(LlmSemanticProvider<OpenAiChatAdapter>),
    Anthropic(LlmSemanticProvider<AnthropicMessagesAdapter>),
}

impl BuiltSemanticProvider {
    /// Constructs the provider for `profile`, injecting the already-resolved
    /// `api_key` (from the secure store). `None` is a keyless/local endpoint.
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

    fn as_judge(&self) -> &dyn SemanticJudgeProvider {
        match self {
            Self::OpenAi(provider) => provider,
            Self::Anthropic(provider) => provider,
        }
    }

    fn as_rubric(&self) -> &dyn SemanticRubricProvider {
        match self {
            Self::OpenAi(provider) => provider,
            Self::Anthropic(provider) => provider,
        }
    }

    fn as_feedback(&self) -> &dyn OutputFeedbackProvider {
        match self {
            Self::OpenAi(provider) => provider,
            Self::Anthropic(provider) => provider,
        }
    }

    fn as_sense_groups(&self) -> &dyn SenseGroupPartitionProvider {
        match self {
            Self::OpenAi(provider) => provider,
            Self::Anthropic(provider) => provider,
        }
    }

    /// Measures real structured-output support against the endpoint.
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
    fn rubric(&self) -> &dyn SemanticRubricProvider {
        self.as_rubric()
    }

    fn judge(&self) -> &dyn SemanticJudgeProvider {
        self.as_judge()
    }

    fn feedback(&self) -> &dyn OutputFeedbackProvider {
        self.as_feedback()
    }

    fn sense_groups(&self) -> &dyn SenseGroupPartitionProvider {
        self.as_sense_groups()
    }

    async fn probe_structured_output(&self) -> Result<CapabilityClaim, LlmProviderError> {
        self.probe().await
    }
}

/// Adapter-crate implementation of the application-owned runtime factory.
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
