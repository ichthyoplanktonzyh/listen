//! Provider-neutral LLM implementation for subtitle sense-group analysis.

use application::{
    LlmChatAdapter, LlmProviderDescriptor, SemanticLlmRuntime, SenseGroupPartitionDraft,
    SenseGroupPartitionProvider, SenseGroupPartitionRequest, StructuredChatRequest,
};
use async_trait::async_trait;
use domain::{LanguageCode, LlmProviderError};
use serde::Deserialize;

const SENSE_GROUP_PROMPT_VERSION: &str = "sense-group-partition/v1";
const SCHEMA_VERSION: &str = "semantic/v1";

/// Turns a protocol adapter into semantic rubric/judge providers.
pub struct LlmSemanticProvider<A: LlmChatAdapter> {
    adapter: A,
}

impl<A: LlmChatAdapter> LlmSemanticProvider<A> {
    pub fn new(adapter: A) -> Self {
        Self { adapter }
    }

    pub fn adapter(&self) -> &A {
        &self.adapter
    }
}

#[async_trait]
impl<A: LlmChatAdapter> SemanticLlmRuntime for LlmSemanticProvider<A> {
    fn sense_groups(&self) -> &dyn SenseGroupPartitionProvider {
        self
    }

    async fn probe_structured_output(&self) -> Result<domain::CapabilityClaim, LlmProviderError> {
        self.adapter.probe_structured_output().await
    }
}

fn sense_group_schema() -> serde_json::Value {
    serde_json::json!({
        "type": "object",
        "additionalProperties": false,
        "properties": {
            "boundary_after_token_indices": {
                "type": "array",
                "items": { "type": "integer", "minimum": 0 }
            }
        },
        "required": ["boundary_after_token_indices"]
    })
}

#[derive(Debug, Deserialize)]
struct SenseGroupOutput {
    boundary_after_token_indices: Vec<u32>,
}

fn sense_group_request(req: &SenseGroupPartitionRequest) -> StructuredChatRequest {
    let language = req
        .language
        .as_ref()
        .map(LanguageCode::as_str)
        .unwrap_or("unknown");
    let tokens = req
        .tokens
        .iter()
        .map(|token| format!("{}:{}:{:?}", token.index, token.kind, token.text))
        .collect::<Vec<_>>()
        .join("\n");
    let protected = req
        .protected_spans
        .iter()
        .map(|span| format!("{}-{}", span.start_token_index, span.end_token_index))
        .collect::<Vec<_>>()
        .join(", ");
    let candidates = req
        .candidate_boundary_after_token_indices
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(", ");
    let system = format!(
        "Partition a {language} subtitle sentence into sense groups for language \
         learning. Each group must be a contiguous, independently understandable \
         meaning unit: keep a predicate with the arguments or complements needed \
         to express its local intention, keep referring noun phrases intact, and \
         avoid fragments made only of function words. Return token indices after \
         which a group ends. Do not return the sentence-final boundary. Never split \
         a protected span. Rule/NLP candidates are hints, not constraints. Do not \
         rewrite, translate, or omit tokens. Return only JSON matching the schema."
    );
    let user = format!(
        "Source text:\n{}\n\nIndexed tokens (index:kind:text):\n{}\n\n\
         Protected spans:\n{}\n\nCandidate boundaries after token indices:\n{}",
        req.source_text,
        tokens,
        if protected.is_empty() {
            "none"
        } else {
            &protected
        },
        if candidates.is_empty() {
            "none"
        } else {
            &candidates
        },
    );
    StructuredChatRequest {
        system,
        user,
        json_schema: sense_group_schema(),
        schema_name: "sense_group_partition".into(),
        max_output_tokens: 512,
        temperature: Some(0.0),
    }
}

#[async_trait]
impl<A: LlmChatAdapter> SenseGroupPartitionProvider for LlmSemanticProvider<A> {
    fn descriptor(&self) -> LlmProviderDescriptor {
        self.adapter.descriptor()
    }

    async fn partition_sense_groups(
        &self,
        request: &SenseGroupPartitionRequest,
    ) -> Result<SenseGroupPartitionDraft, LlmProviderError> {
        let response = self
            .adapter
            .complete_structured(&sense_group_request(request))
            .await?;
        let parsed: SenseGroupOutput =
            serde_json::from_str(&response.json_text).map_err(|error| {
                LlmProviderError::SchemaInvalid {
                    detail: format!("output did not match sense-group schema: {error}"),
                }
            })?;
        Ok(SenseGroupPartitionDraft {
            boundary_after_token_indices: parsed.boundary_after_token_indices,
            model_id: response.model_id,
            prompt_version: Some(SENSE_GROUP_PROMPT_VERSION.into()),
            schema_version: Some(SCHEMA_VERSION.into()),
        })
    }
}
