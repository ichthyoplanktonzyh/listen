//! OpenAI Chat Completions adapter (and any OpenAI-compatible endpoint).
//!
//! Wire shape: flat `messages: [{role, content}]`, `Authorization: Bearer`,
//! native `response_format: {type: json_schema}`. Configurable base URL/model
//! cover local services (Ollama, LM Studio, vLLM) — but endpoint compatibility
//! is not capability equivalence, so [`probe_structured_output`] measures the
//! real behavior instead of trusting the protocol.

use application::{
    LlmChatAdapter, LlmProviderDescriptor, StructuredChatRequest, StructuredChatResponse,
    TokenUsage,
};
use async_trait::async_trait;
use domain::{CapabilityClaim, LlmAdapterKind, LlmProviderError, ProviderCapability};
use serde::Deserialize;
use std::time::Duration;

use crate::{map_reqwest_error, map_status_error, sanitized_protocol};

/// An OpenAI Chat Completions-compatible endpoint. The resolved API key is
/// injected at construction by the caller (which resolved it from the secure
/// store); the adapter never reads it from a profile or environment.
pub struct OpenAiChatAdapter {
    client: reqwest::Client,
    base_url: String,
    model_id: String,
    api_key: Option<String>,
    capability: ProviderCapability,
}

impl OpenAiChatAdapter {
    pub fn new(
        base_url: impl Into<String>,
        model_id: impl Into<String>,
        api_key: Option<String>,
        timeout: Duration,
    ) -> Result<Self, LlmProviderError> {
        let client = reqwest::Client::builder()
            .timeout(timeout)
            .build()
            .map_err(|_| sanitized_protocol("failed to build http client"))?;
        Ok(Self {
            client,
            base_url: normalize_base(base_url.into()),
            model_id: model_id.into(),
            api_key,
            capability: ProviderCapability::unknown(),
        })
    }

    /// Overrides the declared/probed capability descriptor (e.g. after a probe).
    pub fn with_capability(mut self, capability: ProviderCapability) -> Self {
        self.capability = capability;
        self
    }

    fn endpoint(&self) -> String {
        format!("{}/chat/completions", self.base_url)
    }
}

fn normalize_base(base: String) -> String {
    base.trim_end_matches('/').to_string()
}

#[derive(Debug, Deserialize)]
struct ChatResponse {
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    choices: Vec<ChatChoice>,
    #[serde(default)]
    usage: Option<ChatUsage>,
}

#[derive(Debug, Deserialize)]
struct ChatChoice {
    #[serde(default)]
    finish_reason: Option<String>,
    message: ChatMessage,
}

#[derive(Debug, Deserialize)]
struct ChatMessage {
    #[serde(default)]
    content: Option<String>,
    #[serde(default)]
    refusal: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ChatUsage {
    #[serde(default)]
    prompt_tokens: Option<u32>,
    #[serde(default)]
    completion_tokens: Option<u32>,
}

#[async_trait]
impl LlmChatAdapter for OpenAiChatAdapter {
    fn adapter_kind(&self) -> LlmAdapterKind {
        LlmAdapterKind::OpenAiChatCompletions
    }

    fn descriptor(&self) -> LlmProviderDescriptor {
        LlmProviderDescriptor {
            adapter_kind: LlmAdapterKind::OpenAiChatCompletions,
            model_id: self.model_id.clone(),
            capability: self.capability,
        }
    }

    async fn complete_structured(
        &self,
        request: &StructuredChatRequest,
    ) -> Result<StructuredChatResponse, LlmProviderError> {
        let mut body = serde_json::json!({
            "model": self.model_id,
            "messages": [
                { "role": "system", "content": request.system },
                { "role": "user", "content": request.user },
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": request.schema_name,
                    "schema": request.json_schema,
                    "strict": true,
                },
            },
            "max_tokens": request.max_output_tokens,
        });
        if let Some(temperature) = request.temperature {
            body["temperature"] = serde_json::json!(temperature);
        }

        let mut builder = self.client.post(self.endpoint()).json(&body);
        if let Some(key) = &self.api_key {
            builder = builder.bearer_auth(key);
        }
        let response = builder
            .send()
            .await
            .map_err(|error| map_reqwest_error(&error))?;

        let status = response.status();
        if !status.is_success() {
            let retry_after = crate::wire::retry_after_ms(response.headers());
            return Err(map_status_error(status, retry_after));
        }

        let parsed: ChatResponse = response
            .json()
            .await
            .map_err(|_| sanitized_protocol("malformed chat response"))?;
        let choice = parsed
            .choices
            .into_iter()
            .next()
            .ok_or_else(|| sanitized_protocol("chat response had no choices"))?;

        if let Some(reason) = choice.message.refusal.filter(|value| !value.is_empty()) {
            return Err(LlmProviderError::Refusal { reason });
        }
        match choice.finish_reason.as_deref() {
            Some("length") => return Err(LlmProviderError::Truncated),
            Some("content_filter") => {
                return Err(LlmProviderError::Refusal {
                    reason: "content_filter".into(),
                });
            }
            _ => {}
        }

        let json_text = choice
            .message
            .content
            .ok_or_else(|| sanitized_protocol("chat response had no content"))?;

        Ok(StructuredChatResponse {
            json_text,
            model_id: parsed.model.or_else(|| Some(self.model_id.clone())),
            usage: parsed.usage.map(|usage| TokenUsage {
                prompt_tokens: usage.prompt_tokens,
                completion_tokens: usage.completion_tokens,
            }),
        })
    }

    async fn probe_structured_output(&self) -> Result<CapabilityClaim, LlmProviderError> {
        let probe = probe_request();
        match self.complete_structured(&probe).await {
            Ok(response) => Ok(CapabilityClaim::Probed {
                supported: probe_output_is_valid(&response.json_text),
                probed_at_ms: now_ms(),
            }),
            Err(LlmProviderError::SchemaInvalid { .. } | LlmProviderError::Truncated) => {
                Ok(CapabilityClaim::Probed {
                    supported: false,
                    probed_at_ms: now_ms(),
                })
            }
            Err(other) => Err(other),
        }
    }
}

pub(crate) fn probe_request() -> StructuredChatRequest {
    StructuredChatRequest {
        system: "Return only JSON matching the schema.".into(),
        user: "Return {\"ok\": true}.".into(),
        json_schema: serde_json::json!({
            "type": "object",
            "additionalProperties": false,
            "properties": { "ok": { "type": "boolean" } },
            "required": ["ok"],
        }),
        schema_name: "capability_probe".into(),
        max_output_tokens: 64,
        temperature: Some(0.0),
    }
}

pub(crate) fn probe_output_is_valid(json_text: &str) -> bool {
    serde_json::from_str::<serde_json::Value>(json_text)
        .ok()
        .and_then(|value| value.get("ok").and_then(serde_json::Value::as_bool))
        .unwrap_or(false)
}

pub(crate) fn now_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
