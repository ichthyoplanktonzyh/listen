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
}
