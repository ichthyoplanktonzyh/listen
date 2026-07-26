use application::{ApplicationError, DictionaryCacheRepository};
use domain::{DictionaryEntry, DictionaryEntryId, LanguageCode};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, domain_sql, repo};

impl DictionaryCacheRepository for SqliteRepository {
    fn put(&self, e: &DictionaryEntry) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO dictionary_cache
                 (id, language, normalized_lemma, provider, payload_json, cached_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT(language, normalized_lemma, provider) DO UPDATE SET
                   payload_json=excluded.payload_json, cached_at_ms=excluded.cached_at_ms",
                params![
                    e.id.as_str(),
                    e.language.as_str(),
                    e.normalized_lemma,
                    e.provider,
                    e.payload_json,
                    e.cached_at_ms
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get(
        &self,
        language: &LanguageCode,
        normalized_lemma: &str,
        provider: &str,
    ) -> Result<Option<DictionaryEntry>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT id, language, normalized_lemma, provider, payload_json, cached_at_ms
                 FROM dictionary_cache WHERE language=?1 AND normalized_lemma=?2 AND provider=?3",
                params![language.as_str(), normalized_lemma, provider],
                |r| {
                    Ok(DictionaryEntry {
                        id: DictionaryEntryId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                        language: LanguageCode::parse(r.get::<_, String>(1)?)
                            .map_err(domain_sql)?,
                        normalized_lemma: r.get(2)?,
                        provider: r.get(3)?,
                        payload_json: r.get(4)?,
                        cached_at_ms: r.get(5)?,
                    })
                },
            )
            .optional()
            .map_err(repo)
    }
}
