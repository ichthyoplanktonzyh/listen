//! Phase 3.12 vendor-neutral LLM protocol adapters.
//!
//! This crate is the wire layer. It implements the neutral
//! [`application::LlmChatAdapter`] seam for two *structurally heterogeneous*
//! protocols — OpenAI Chat Completions ([`openai_chat`]) and Anthropic Messages
//! ([`anthropic_messages`]) — and a single generic composition
//! ([`LlmSemanticProvider`]) that turns any adapter into a
//! [`application::SemanticRubricProvider`] / [`application::SemanticJudgeProvider`].
//!
//! Neutrality is proved in `tests/contract.rs`: both adapters are driven
//! through the same scenario suite (success / refusal / schema-invalid /
//! truncated / rate-limit / timeout) and must yield the same neutral outcome
//! even though their wire formats differ in auth headers, system placement,
//! content shape, and structured-output mechanism.
//!
//! Design lineage: the neutral-types approach mirrors rust-genai; the internal
//! contract is deliberately *ours*, so no provider `messages`/content-block
//! type ever surfaces above `LlmChatAdapter`.

pub mod anthropic_messages;
pub mod openai_chat;

mod semantic;
mod wire;

pub use anthropic_messages::AnthropicMessagesAdapter;
pub use openai_chat::OpenAiChatAdapter;
pub use semantic::LlmSemanticProvider;

pub(crate) use wire::{map_reqwest_error, map_status_error, sanitized_protocol};
