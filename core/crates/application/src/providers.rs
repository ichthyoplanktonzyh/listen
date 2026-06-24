use async_trait::async_trait;
use domain::*;
use thiserror::Error;

#[async_trait]
pub trait DictionaryProvider: Send + Sync {
    fn info(&self) -> DictionaryProviderInfo;
    async fn lookup(
        &self,
        language: &LanguageCode,
        lemma: &str,
    ) -> Result<Option<DictionaryLookup>, DictionaryProviderError>;
}

#[derive(Debug, Error)]
#[error("dictionary provider failed: {0}")]
pub struct DictionaryProviderError(pub String);

pub trait LexicalNormalizationProvider: Send + Sync {
    fn provider_id(&self) -> &'static str;
    fn version(&self) -> &str;
    fn normalize(
        &self,
        language: &LanguageCode,
        value: &str,
    ) -> Result<Option<String>, LexicalNormalizationProviderError>;
    fn phrase_candidates(
        &self,
        language: &LanguageCode,
        sentence: &SubtitleSentence,
    ) -> Result<Vec<PhraseCandidate>, LexicalNormalizationProviderError>;
}

#[derive(Debug, Error)]
#[error("lexical normalization provider failed: {0}")]
pub struct LexicalNormalizationProviderError(pub String);

pub trait PronunciationProvider: Send + Sync {
    fn info(&self) -> PronunciationProviderInfo;
    fn analyze_sentence(&self, sentence: &SubtitleSentence) -> Option<SentencePronunciation>;
    fn lookup_word(&self, word: &str, token_index: u32) -> Option<WordPronunciation>;
    fn rule_catalog(&self) -> serde_json::Value {
        serde_json::json!([])
    }
}
