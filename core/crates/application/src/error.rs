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
    #[error("external process failed: {0}")]
    ExternalProcess(String),
    /// A vendor LLM provider failed. Carries the standardized, secret-free
    /// taxonomy so HTTP/UI can degrade honestly without ever echoing a
    /// credential (Phase 3.12).
    #[error(transparent)]
    Provider(#[from] domain::LlmProviderError),
    #[error(transparent)]
    SecretStore(#[from] crate::SecretStoreError),
}
