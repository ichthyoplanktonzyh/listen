//! Phase 3.12 vendor-neutral LLM provider contract (domain layer).
//!
//! These types are wire-agnostic on purpose: nothing here names OpenAI
//! `messages`, Anthropic content blocks, or Gemini `contents/parts`. Protocol
//! adapters (crate `llm-provider`) map external APIs onto the neutral
//! `LlmChatAdapter` seam defined in the `application` crate; this module only
//! carries the profile, capability, auth-reference, and error taxonomy the
//! whole system agrees on.
//!
//! Secrets never live here. `LlmProviderProfile` stores an opaque
//! [`LlmAuthRef`] pointing into the OS keychain; the raw key is written once
//! through a write-only endpoint and never round-trips through this profile,
//! SQLite, logs, or any portable bundle (shared context §3.4).

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::LlmProviderProfileId;

/// Closed on purpose: one variant per supported protocol family. The first
/// batch proves neutrality with two *structurally heterogeneous* protocols;
/// adding a variant is adapter-only work and must not touch the semantic
/// rubric/judgment contract (Phase 3.12 exit signal).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LlmAdapterKind {
    /// OpenAI Chat Completions and any compatible service reachable by a
    /// custom base URL (Ollama, LM Studio, vLLM, ...). Endpoint compatibility
    /// is **not** capability equivalence — see [`ProviderCapability`].
    ///
    /// Pinned to the conventional spelling so the serde wire form matches
    /// [`LlmAdapterKind::as_str`] (default snake_case would emit
    /// `open_ai_chat_completions`, diverging the JSON blob from the DB column).
    #[serde(rename = "openai_chat_completions")]
    OpenAiChatCompletions,
    /// Anthropic Messages: a different content-block protocol with different
    /// auth headers and no native `response_format` json-schema switch.
    AnthropicMessages,
    // Deferred (Slice 4, adapter-only): OpenAiResponses, GeminiNative.
}

impl LlmAdapterKind {
    pub fn as_str(self) -> &'static str {
        match self {
            LlmAdapterKind::OpenAiChatCompletions => "openai_chat_completions",
            LlmAdapterKind::AnthropicMessages => "anthropic_messages",
        }
    }
}

/// What a provider profile is allowed to be used for. A profile that lacks a
/// use may never be dispatched for it, even if the protocol technically could.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LlmUse {
    RubricGeneration,
    SemanticJudgment,
}

/// User-declared data-retention expectation for content leaving the device.
/// Honestly recorded, never assumed: a custom endpoint's true retention is
/// whatever the operator configured, so [`DataRetentionPreference::Unknown`]
/// is a first-class value, not a bug.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DataRetentionPreference {
    /// Provider asserts inputs are not retained/trained on.
    NoRetention,
    /// Provider default retention applies.
    ProviderDefault,
    /// Retention is unknown (typical for self-hosted / custom endpoints).
    Unknown,
}

/// Opaque reference into the OS secure store. This is **not** the secret and
/// must be safe to persist and log; the real credential is resolved at call
/// time by a `SecretStore` and never enters this type.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct SecretRef(String);

impl SecretRef {
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Backward-compatible category name for the shared opaque keychain handle.
pub type LlmAuthRef = SecretRef;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct CostBudget {
    pub max_usd: Option<f64>,
    pub max_requests: Option<u32>,
}

/// One capability claim. The whole point of Phase 3.12 is that OpenAI-compatible
/// endpoints (esp. local ones) must have their real capability *probed*, not
/// assumed from protocol compatibility. `Declared` is config/catalog truth;
/// `Probed` is measured truth; `Unknown` is honest ignorance.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "state")]
pub enum CapabilityClaim {
    /// Configured/cataloged but not verified against this endpoint.
    Declared { supported: bool },
    /// Actually measured against this endpoint at `probed_at_ms`.
    Probed { supported: bool, probed_at_ms: u64 },
    /// Not declared and not yet probed.
    Unknown,
}

impl CapabilityClaim {
    /// Whether a dispatcher may rely on this capability. Only measured support
    /// counts as usable for hard requirements; declared support is advisory.
    pub fn is_usable(self) -> bool {
        matches!(
            self,
            CapabilityClaim::Probed {
                supported: true,
                ..
            }
        )
    }
}

/// Provider capability descriptor (taxonomy borrowed from LiteLLM's model
/// catalog; probe discipline is stricter than any surveyed reference). Protocol
/// compatibility does not imply capability equivalence — every field is a
/// claim with provenance, never a silent assumption.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct ProviderCapability {
    pub structured_output: CapabilityClaim,
    pub streaming: CapabilityClaim,
    pub multilingual: CapabilityClaim,
    pub audio_input: CapabilityClaim,
    pub max_context_tokens: Option<u32>,
}

impl ProviderCapability {
    /// A conservative default before any probe: everything unknown.
    pub fn unknown() -> Self {
        Self {
            structured_output: CapabilityClaim::Unknown,
            streaming: CapabilityClaim::Unknown,
            multilingual: CapabilityClaim::Unknown,
            audio_input: CapabilityClaim::Unknown,
            max_context_tokens: None,
        }
    }
}

/// A configured LLM endpoint. Identity is a fingerprint of the durable routing
/// fields (adapter/base URL/model), so re-adding the same endpoint is
/// idempotent. Secrets are referenced, never embedded.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LlmProviderProfile {
    pub id: LlmProviderProfileId,
    pub display_name: String,
    pub adapter_kind: LlmAdapterKind,
    /// Protocol version pin where the wire format requires one (e.g. the
    /// Anthropic `anthropic-version` header). `None` for protocols that do not.
    pub protocol_version: Option<String>,
    pub base_url: String,
    pub model_id: String,
    /// `None` = no credential (typical local endpoint). `Some` = a keychain
    /// reference; the secret itself is never stored on the profile.
    pub auth_ref: Option<LlmAuthRef>,
    pub timeout_ms: u64,
    pub max_retries: u32,
    pub cost_budget: Option<CostBudget>,
    pub retention: DataRetentionPreference,
    pub allowed_uses: Vec<LlmUse>,
    pub capability: ProviderCapability,
    pub created_at_ms: u64,
}

impl LlmProviderProfile {
    pub fn allows(&self, use_case: LlmUse) -> bool {
        self.allowed_uses.contains(&use_case)
    }
}

/// Identity of a provider profile: adapter kind + base URL + model. Two
/// profiles differing only by display name or budget are the same endpoint.
pub fn llm_provider_profile_id(
    adapter_kind: LlmAdapterKind,
    base_url: &str,
    model_id: &str,
) -> LlmProviderProfileId {
    LlmProviderProfileId::from_fingerprint(
        "llm-provider-profile",
        &format!("{}:{base_url}:{model_id}", adapter_kind.as_str()),
    )
}

/// Standardized provider error taxonomy (shared context §3.4 / final §7.4).
///
/// Guardrail: no variant carries a credential, auth header, or raw endpoint
/// secret. `Auth` is deliberately payload-free so an auth failure can never
/// echo the key back into an error message, log, or HTTP response.
#[derive(Debug, Clone, PartialEq, Eq, Error, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum LlmProviderError {
    #[error("provider is offline or unreachable")]
    Offline,
    /// Authentication failed. Never carries the credential.
    #[error("provider authentication failed")]
    Auth,
    #[error("provider rate limited the request")]
    RateLimit { retry_after_ms: Option<u64> },
    #[error("provider request timed out")]
    Timeout,
    /// The model declined to answer. The reason is the model's, not the key's.
    #[error("provider refused the request: {reason}")]
    Refusal { reason: String },
    /// The response was cut off before completion; no judgment may be written.
    #[error("provider response was truncated")]
    Truncated,
    /// Output did not match the requested structured schema.
    #[error("provider output failed schema validation: {detail}")]
    SchemaInvalid { detail: String },
    /// A required capability is not supported by this endpoint.
    #[error("provider does not support required capability: {capability}")]
    UnsupportedCapability { capability: String },
    /// Any other wire-level failure that is not one of the above. `detail` is
    /// sanitized by adapters and must never include auth material.
    #[error("provider protocol error: {detail}")]
    Protocol { detail: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn profile_identity_ignores_display_and_budget() {
        let a = llm_provider_profile_id(
            LlmAdapterKind::OpenAiChatCompletions,
            "https://api.example.com/v1",
            "gpt-x",
        );
        let b = llm_provider_profile_id(
            LlmAdapterKind::OpenAiChatCompletions,
            "https://api.example.com/v1",
            "gpt-x",
        );
        assert_eq!(a, b);
        let c = llm_provider_profile_id(
            LlmAdapterKind::AnthropicMessages,
            "https://api.example.com/v1",
            "gpt-x",
        );
        assert_ne!(a.as_str(), c.as_str());
    }

    #[test]
    fn only_probed_support_is_usable() {
        assert!(
            CapabilityClaim::Probed {
                supported: true,
                probed_at_ms: 1
            }
            .is_usable()
        );
        assert!(!CapabilityClaim::Declared { supported: true }.is_usable());
        assert!(!CapabilityClaim::Unknown.is_usable());
        assert!(
            !CapabilityClaim::Probed {
                supported: false,
                probed_at_ms: 1
            }
            .is_usable()
        );
    }

    #[test]
    fn auth_error_serializes_without_any_payload() {
        let json = serde_json::to_string(&LlmProviderError::Auth).unwrap();
        assert_eq!(json, r#"{"kind":"auth"}"#);
    }

    #[test]
    fn allowed_uses_gate_dispatch() {
        let profile = LlmProviderProfile {
            id: llm_provider_profile_id(
                LlmAdapterKind::AnthropicMessages,
                "https://api.anthropic.com",
                "claude-x",
            ),
            display_name: "test".into(),
            adapter_kind: LlmAdapterKind::AnthropicMessages,
            protocol_version: Some("2023-06-01".into()),
            base_url: "https://api.anthropic.com".into(),
            model_id: "claude-x".into(),
            auth_ref: Some(LlmAuthRef::new("kc://llm/abc")),
            timeout_ms: 30_000,
            max_retries: 1,
            cost_budget: None,
            retention: DataRetentionPreference::Unknown,
            allowed_uses: vec![LlmUse::SemanticJudgment],
            capability: ProviderCapability::unknown(),
            created_at_ms: 0,
        };
        assert!(profile.allows(LlmUse::SemanticJudgment));
        assert!(!profile.allows(LlmUse::RubricGeneration));
    }
}
