use std::sync::Arc;

use crate::{
    ApplicationError, DictionaryCacheRepository, DictionaryEntry, DictionaryEntryId,
    DictionaryLookupBundle, DictionaryProvider, DictionaryProviderResult, LanguageCode, now_ms,
    require_text,
};

const CACHE_TTL_MS: u64 = 30 * 24 * 60 * 60 * 1000;

pub struct DictionaryUseCases {
    cache: Arc<dyn DictionaryCacheRepository>,
}

impl DictionaryUseCases {
    pub(crate) fn new(cache: Arc<dyn DictionaryCacheRepository>) -> Self {
        Self { cache }
    }

    pub async fn lookup_dictionary(
        &self,
        providers: &[Arc<dyn DictionaryProvider>],
        language: &str,
        lemma: &str,
    ) -> Result<DictionaryLookupBundle, ApplicationError> {
        let language = LanguageCode::parse(language.to_owned())?;
        // Normalize the query with the learning language's declared normalization
        // rather than a hardcoded English lemma fold, so a surface-form language
        // (e.g. Chinese) is not silently lowercased. For caseless scripts this is
        // identical to `normalize_lemma`; the difference only surfaces once a
        // case-bearing non-lemma language is added.
        let normalized_lemma = domain::baseline_normalized_key(
            &domain::profile_for(&language).lexical_normalization,
            lemma,
        );
        require_text(&normalized_lemma, "lemma")?;
        let mut results = Vec::with_capacity(providers.len());
        for provider in providers {
            let info = provider.info();
            if !info
                .supported_languages
                .iter()
                .any(|value| value == language.as_str())
            {
                continue;
            }
            if let Some(entry) = self
                .cache
                .get(&language, &normalized_lemma, &info.id)?
                .filter(|entry| now_ms().saturating_sub(entry.cached_at_ms) < CACHE_TTL_MS)
            {
                let lookup = serde_json::from_str(&entry.payload_json)
                    .map_err(|error| ApplicationError::Repository(error.to_string()))?;
                results.push(DictionaryProviderResult {
                    provider: info,
                    lookup: Some(lookup),
                    error: None,
                });
                continue;
            }
            match provider.lookup(&language, &normalized_lemma).await {
                Ok(Some(mut lookup)) => {
                    lookup.cached_at_ms = now_ms();
                    self.cache.put(&DictionaryEntry {
                        id: DictionaryEntryId::from_fingerprint(
                            "dictionary",
                            &format!("{}:{normalized_lemma}:{}", language.as_str(), info.id),
                        ),
                        language: language.clone(),
                        normalized_lemma: normalized_lemma.clone(),
                        provider: info.id.clone(),
                        payload_json: serde_json::to_string(&lookup)
                            .map_err(|error| ApplicationError::Repository(error.to_string()))?,
                        cached_at_ms: lookup.cached_at_ms,
                    })?;
                    results.push(DictionaryProviderResult {
                        provider: info,
                        lookup: Some(lookup),
                        error: None,
                    });
                }
                Ok(None) => results.push(DictionaryProviderResult {
                    provider: info,
                    lookup: None,
                    error: None,
                }),
                Err(error) => results.push(DictionaryProviderResult {
                    provider: info,
                    lookup: None,
                    error: Some(error.to_string()),
                }),
            }
        }
        Ok(DictionaryLookupBundle {
            query: lemma.to_owned(),
            normalized_lemma,
            results,
        })
    }
}
