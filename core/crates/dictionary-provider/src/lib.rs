use std::time::Duration;

use application::{DictionaryProvider, DictionaryProviderError};
use async_trait::async_trait;
use domain::{DictionaryDefinition, DictionaryLookup, DictionaryPhonetic, LanguageCode};

pub struct FreeDictionaryProvider {
    client: reqwest::Client,
    base_url: String,
}

impl FreeDictionaryProvider {
    pub fn new() -> Result<Self, DictionaryProviderError> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .map_err(|error| DictionaryProviderError(error.to_string()))?;
        Ok(Self {
            client,
            base_url: "https://api.dictionaryapi.dev/api/v2/entries".into(),
        })
    }

    #[cfg(test)]
    pub fn with_base_url(base_url: String) -> Result<Self, DictionaryProviderError> {
        let mut value = Self::new()?;
        value.base_url = base_url;
        Ok(value)
    }
}

#[async_trait]
impl DictionaryProvider for FreeDictionaryProvider {
    fn name(&self) -> &'static str {
        "free-dictionary-api"
    }

    async fn lookup(
        &self,
        language: &LanguageCode,
        lemma: &str,
    ) -> Result<Option<DictionaryLookup>, DictionaryProviderError> {
        let url = format!(
            "{}/{}/{}",
            self.base_url,
            language.as_str(),
            url_encode(lemma)
        );
        let response = self
            .client
            .get(url)
            .send()
            .await
            .map_err(|error| DictionaryProviderError(error.to_string()))?;
        if response.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(None);
        }
        let response = response
            .error_for_status()
            .map_err(|error| DictionaryProviderError(error.to_string()))?;
        let payload: serde_json::Value = response
            .json()
            .await
            .map_err(|error| DictionaryProviderError(error.to_string()))?;
        let Some(entry) = payload.as_array().and_then(|entries| entries.first()) else {
            return Ok(None);
        };
        let definitions = entry["meanings"]
            .as_array()
            .into_iter()
            .flatten()
            .flat_map(|meaning| {
                let part = meaning["partOfSpeech"].as_str().map(str::to_owned);
                meaning["definitions"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(move |definition| {
                        definition["definition"]
                            .as_str()
                            .map(|text| DictionaryDefinition {
                                part_of_speech: part.clone(),
                                text: text.to_owned(),
                            })
                    })
            })
            .take(8)
            .collect();
        let phonetics = entry["phonetics"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|value| value["text"].as_str())
            .map(|text| DictionaryPhonetic {
                text: text.to_owned(),
                region: None,
            })
            .collect();
        Ok(Some(DictionaryLookup {
            query: lemma.to_owned(),
            lemma: entry["word"].as_str().unwrap_or(lemma).to_owned(),
            definitions,
            phonetics,
            provider: self.name().into(),
            cached_at_ms: 0,
        }))
    }
}

fn url_encode(value: &str) -> String {
    value
        .bytes()
        .map(|byte| {
            if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
                (byte as char).to_string()
            } else {
                format!("%{byte:02X}")
            }
        })
        .collect()
}
