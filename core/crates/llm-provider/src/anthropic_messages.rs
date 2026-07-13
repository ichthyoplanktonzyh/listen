//! Anthropic Messages adapter.
//!
//! Wire shape that is deliberately heterogeneous to OpenAI Chat Completions:
//! auth via `x-api-key` + `anthropic-version` (not `Bearer`), `system` as a
//! top-level field (not a message), `content` as a block array (not a string),
//! and structured output forced through a `tool_use` block (no
//! `response_format`). If our neutral seam survives *this* asymmetry against
//! the OpenAI one under the same contract suite, the domain layer is not
//! captured by either wire format.

use application::{
    LlmChatAdapter, LlmProviderDescriptor, StructuredChatRequest, StructuredChatResponse,
    TokenUsage,
};
use async_trait::async_trait;
use domain::{CapabilityClaim, LlmAdapterKind, LlmProviderError, ProviderCapability};
use serde::Deserialize;
use std::time::Duration;

use crate::openai_chat::{now_ms, probe_output_is_valid, probe_request};
use crate::{map_reqwest_error, map_status_error, sanitized_protocol};

const DEFAULT_ANTHROPIC_VERSION: &str = "2023-06-01";

pub struct AnthropicMessagesAdapter {
    client: reqwest::Client,
    base_url: String,
    model_id: String,
    api_key: Option<String>,
    anthropic_version: String,
    capability: ProviderCapability,
}

impl AnthropicMessagesAdapter {
    pub fn new(
        base_url: impl Into<String>,
        model_id: impl Into<String>,
        api_key: Option<String>,
        protocol_version: Option<String>,
        timeout: Duration,
    ) -> Result<Self, LlmProviderError> {
        let client = reqwest::Client::builder()
            .timeout(timeout)
            .build()
            .map_err(|_| sanitized_protocol("failed to build http client"))?;
        Ok(Self {
            client,
            base_url: base_url.into().trim_end_matches('/').to_string(),
            model_id: model_id.into(),
            api_key,
            anthropic_version: protocol_version
                .unwrap_or_else(|| DEFAULT_ANTHROPIC_VERSION.to_string()),
            capability: ProviderCapability::unknown(),
        })
    }

    pub fn with_capability(mut self, capability: ProviderCapability) -> Self {
        self.capability = capability;
        self
    }

    fn endpoint(&self) -> String {
        format!("{}/v1/messages", self.base_url)
    }
}

#[derive(Debug, Deserialize)]
struct MessagesResponse {
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    stop_reason: Option<String>,
    #[serde(default)]
    content: Vec<ContentBlock>,
    #[serde(default)]
    usage: Option<MessagesUsage>,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
enum ContentBlock {
    #[serde(rename = "tool_use")]
    ToolUse {
        name: String,
        input: serde_json::Value,
    },
    #[serde(rename = "text")]
    Text {
        #[allow(dead_code)]
        text: String,
    },
    #[serde(other)]
    Other,
}

#[derive(Debug, Deserialize)]
struct MessagesUsage {
    #[serde(default)]
    input_tokens: Option<u32>,
    #[serde(default)]
    output_tokens: Option<u32>,
}

#[async_trait]
impl LlmChatAdapter for AnthropicMessagesAdapter {
    fn adapter_kind(&self) -> LlmAdapterKind {
        LlmAdapterKind::AnthropicMessages
    }

    fn descriptor(&self) -> LlmProviderDescriptor {
        LlmProviderDescriptor {
            adapter_kind: LlmAdapterKind::AnthropicMessages,
            model_id: self.model_id.clone(),
            capability: self.capability,
        }
    }

    async fn complete_structured(
        &self,
        request: &StructuredChatRequest,
    ) -> Result<StructuredChatResponse, LlmProviderError> {
        // Anthropic has no native json-schema response_format; force structured
        // output through a single-tool choice whose input_schema is our schema.
        let mut body = serde_json::json!({
            "model": self.model_id,
            "system": request.system,
            "messages": [ { "role": "user", "content": request.user } ],
            "max_tokens": request.max_output_tokens,
            "tools": [ {
                "name": request.schema_name,
                "description": "Return the structured result for this task.",
                "input_schema": request.json_schema,
            } ],
            "tool_choice": { "type": "tool", "name": request.schema_name },
        });
        if let Some(temperature) = request.temperature {
            body["temperature"] = serde_json::json!(temperature);
        }

        let mut builder = self
            .client
            .post(self.endpoint())
            .header("anthropic-version", &self.anthropic_version)
            .json(&body);
        if let Some(key) = &self.api_key {
            builder = builder.header("x-api-key", key);
        }
        let response = builder.send().await.map_err(|error| map_reqwest_error(&error))?;

        let status = response.status();
        if !status.is_success() {
            let retry_after = crate::wire::retry_after_ms(response.headers());
            return Err(map_status_error(status, retry_after));
        }

        let parsed: MessagesResponse = response
            .json()
            .await
            .map_err(|_| sanitized_protocol("malformed messages response"))?;

        match parsed.stop_reason.as_deref() {
            Some("max_tokens") => return Err(LlmProviderError::Truncated),
            Some("refusal") => {
                return Err(LlmProviderError::Refusal {
                    reason: "refusal".into(),
                });
            }
            _ => {}
        }

        let tool_input = parsed
            .content
            .into_iter()
            .find_map(|block| match block {
                ContentBlock::ToolUse { name, input } if name == request.schema_name => Some(input),
                _ => None,
            })
            .ok_or_else(|| sanitized_protocol("messages response had no matching tool_use block"))?;
        let json_text = serde_json::to_string(&tool_input)
            .map_err(|_| sanitized_protocol("tool_use input was not serializable"))?;

        Ok(StructuredChatResponse {
            json_text,
            model_id: parsed.model.or_else(|| Some(self.model_id.clone())),
            usage: parsed.usage.map(|usage| TokenUsage {
                prompt_tokens: usage.input_tokens,
                completion_tokens: usage.output_tokens,
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
