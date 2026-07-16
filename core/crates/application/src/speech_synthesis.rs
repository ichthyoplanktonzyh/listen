use std::fmt;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpeechSynthesisProviderDescriptor {
    pub id: String,
    pub display_name: String,
    pub version: String,
    pub locality: SpeechSynthesisLocality,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SpeechSynthesisLocality {
    Local,
    Remote,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpeechSynthesisVoice {
    pub id: String,
    pub provider_id: String,
    pub display_name: String,
    pub language: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProviderSynthesisRequest {
    pub text: String,
    pub language: String,
    pub voice_id: String,
    pub rate_words_per_minute: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProviderSynthesisOutput {
    pub bytes: Vec<u8>,
    pub file_extension: String,
    pub mime_type: String,
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum SpeechSynthesisError {
    #[error("speech synthesis is unavailable: {0}")]
    Unavailable(String),
    #[error("speech synthesis does not support language {0}")]
    UnsupportedLanguage(String),
    #[error("speech synthesis voice {0} is unavailable")]
    VoiceUnavailable(String),
    #[error("speech synthesis request is invalid: {0}")]
    InvalidRequest(String),
    #[error("speech synthesis provider failed: {0}")]
    Provider(String),
    #[error("speech synthesis cache failed: {0}")]
    Cache(String),
}

#[async_trait]
pub trait SpeechSynthesisProvider: Send + Sync + fmt::Debug {
    fn descriptor(&self) -> SpeechSynthesisProviderDescriptor;
    async fn voices(&self) -> Result<Vec<SpeechSynthesisVoice>, SpeechSynthesisError>;
    async fn synthesize(
        &self,
        request: &ProviderSynthesisRequest,
    ) -> Result<ProviderSynthesisOutput, SpeechSynthesisError>;
}
