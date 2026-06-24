use domain::*;

use crate::PronunciationProvider;

pub struct EnglishPronunciationProvider;

impl PronunciationProvider for EnglishPronunciationProvider {
    fn info(&self) -> PronunciationProviderInfo {
        speech_analysis::provider_info()
    }

    fn analyze_sentence(&self, sentence: &SubtitleSentence) -> Option<SentencePronunciation> {
        Some(speech_analysis::analyze_sentence(sentence))
    }

    fn lookup_word(&self, word: &str, token_index: u32) -> Option<WordPronunciation> {
        Some(speech_analysis::lookup(word, token_index))
    }

    fn rule_catalog(&self) -> serde_json::Value {
        serde_json::json!(speech_analysis::rule_catalog())
    }
}
