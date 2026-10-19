use domain::DomainError;
use thiserror::Error;

use crate::{DictionaryProviderError, LexicalNormalizationProviderError};

#[derive(Debug, Error)]
pub enum ApplicationError {
    #[error("repository failure: {0}")]
    Repository(String),
    #[error("{0} was not found")]
    NotFound(&'static str),
    #[error("{0} must not be empty")]
    Validation(&'static str),
    #[error("invalid input: {0}")]
    Invalid(String),
    #[error(transparent)]
    Domain(#[from] DomainError),
    #[error(transparent)]
    Subtitle(#[from] subtitle_core::SubtitleError),
    #[error(transparent)]
    DictionaryProvider(#[from] DictionaryProviderError),
    #[error(transparent)]
    LexicalNormalizationProvider(#[from] LexicalNormalizationProviderError),
    #[error("{0}")]
    Conflict(&'static str),
    #[error("{0} was cancelled")]
    Cancelled(&'static str),
    #[error("external process failed: {0}")]
    ExternalProcess(String),
    /// The adopted composition's selected content is missing or fails
    /// integrity verification. Never a silent fallback: the App must surface
    /// the honest failure instead of re-reading a carrier.
    #[error("adopted composition content is missing or fails integrity verification")]
    CompositionIntegrity,
    /// A referenced Source Asset behind an adopted composition cannot be
    /// reached. The Material and its adoption stay untouched.
    #[error("a referenced source asset is unavailable")]
    SourceUnavailable,
    /// A vendor LLM provider failed. Carries the standardized, secret-free
    /// taxonomy so HTTP/UI can degrade honestly without ever echoing a
    /// credential (Phase 3.12).
    #[error(transparent)]
    Provider(#[from] domain::LlmProviderError),
    /// A native realtime provider failed through the provider-neutral
    /// application seam. The taxonomy is secret-free by construction.
    #[error(transparent)]
    RealtimeProvider(#[from] domain::RealtimeProviderError),
    #[error(transparent)]
    SecretStore(#[from] crate::SecretStoreError),
}
