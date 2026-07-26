use application::{ApplicationError, PronunciationRepository};
use domain::{SentencePronunciation, SubtitleSentenceId, WordPronunciation};
use rusqlite::{OptionalExtension, params};

use crate::{SqliteRepository, from_json, json, repo};

impl PronunciationRepository for SqliteRepository {
    fn save_pronunciation(&self, analysis: &SentencePronunciation) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO pronunciation_analysis
                 (sentence_id,provider_id,provider_version,analysis_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,unixepoch('subsec') * 1000)
                 ON CONFLICT(sentence_id) DO UPDATE SET
                   provider_id=excluded.provider_id,provider_version=excluded.provider_version,
                   analysis_json=excluded.analysis_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    analysis.sentence_id.as_str(),
                    analysis.provider_id,
                    analysis.provider_version,
                    json(analysis)?
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn save_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        pronunciation: &WordPronunciation,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO pronunciation_cache
                 (language,accent,normalized_text,provider_id,provider_version,
                  pronunciation_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,unixepoch('subsec') * 1000)
                 ON CONFLICT(language,accent,normalized_text,provider_id,provider_version)
                 DO UPDATE SET pronunciation_json=excluded.pronunciation_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    language,
                    accent,
                    pronunciation.normalized,
                    provider_id,
                    provider_version,
                    json(pronunciation)?,
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        normalized_text: &str,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<Option<WordPronunciation>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT pronunciation_json FROM pronunciation_cache
                 WHERE language=?1 AND accent=?2 AND normalized_text=?3
                   AND provider_id=?4 AND provider_version=?5",
                params![
                    language,
                    accent,
                    normalized_text,
                    provider_id,
                    provider_version
                ],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn get_pronunciation(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SentencePronunciation>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT analysis_json FROM pronunciation_analysis WHERE sentence_id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }
}
