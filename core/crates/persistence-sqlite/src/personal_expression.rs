use application::{ApplicationError, PersonalExpressionRepository};
use domain::{
    LanguageCode, PersonalExpressionAttempt, UserSentencePatternAsset, UserSentencePatternId,
    UserSentencePatternVersion,
};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl PersonalExpressionRepository for SqliteRepository {
    fn create_pattern(
        &self,
        asset: &UserSentencePatternAsset,
    ) -> Result<UserSentencePatternAsset, ApplicationError> {
        let mut connection = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = connection.transaction().map_err(repo)?;
        tx.execute(
            "INSERT INTO user_sentence_patterns
             (id,language,current_version,current_name,current_pattern_text,created_at_ms,updated_at_ms,asset_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
            params![
                asset.id.as_str(),
                asset.language.as_str(),
                asset.current_version.version,
                asset.current_version.name,
                asset.current_version.pattern_text,
                asset.created_at_ms,
                asset.updated_at_ms,
                json(asset)?,
            ],
        )
        .map_err(repo)?;
        tx.execute(
            "INSERT INTO user_sentence_pattern_versions
             (id,pattern_id,version,created_at_ms,version_json) VALUES (?1,?2,?3,?4,?5)",
            params![
                asset.current_version.id.as_str(),
                asset.id.as_str(),
                asset.current_version.version,
                asset.current_version.created_at_ms,
                json(&asset.current_version)?,
            ],
        )
        .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(asset.clone())
    }

    fn append_pattern_version(
        &self,
        pattern_id: &UserSentencePatternId,
        version: &UserSentencePatternVersion,
        updated_at_ms: u64,
    ) -> Result<UserSentencePatternAsset, ApplicationError> {
        let mut connection = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = connection.transaction().map_err(repo)?;
        let mut asset = tx
            .query_row(
                "SELECT asset_json FROM user_sentence_patterns WHERE id=?1",
                [pattern_id.as_str()],
                |row| from_json::<UserSentencePatternAsset>(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("sentence pattern"))?;
        if version.version != asset.current_version.version + 1 {
            return Err(ApplicationError::Conflict(
                "pattern revision must append the next immutable version",
            ));
        }
        tx.execute(
            "INSERT INTO user_sentence_pattern_versions
             (id,pattern_id,version,created_at_ms,version_json) VALUES (?1,?2,?3,?4,?5)",
            params![
                version.id.as_str(),
                pattern_id.as_str(),
                version.version,
                version.created_at_ms,
                json(version)?,
            ],
        )
        .map_err(repo)?;
        asset.current_version = version.clone();
        asset.updated_at_ms = updated_at_ms;
        tx.execute(
            "UPDATE user_sentence_patterns SET current_version=?2,current_name=?3,
             current_pattern_text=?4,updated_at_ms=?5,asset_json=?6 WHERE id=?1",
            params![
                pattern_id.as_str(),
                version.version,
                version.name,
                version.pattern_text,
                updated_at_ms,
                json(&asset)?,
            ],
        )
        .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(asset)
    }

    fn get_pattern(
        &self,
        id: &UserSentencePatternId,
    ) -> Result<Option<UserSentencePatternAsset>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT asset_json FROM user_sentence_patterns WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_patterns(
        &self,
        language: Option<&LanguageCode>,
        query: Option<&str>,
    ) -> Result<Vec<UserSentencePatternAsset>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let query = query.map(str::trim).filter(|value| !value.is_empty());
        let pattern = query.map(|value| format!("%{value}%"));
        let mut statement = connection
            .prepare(
                "SELECT asset_json FROM user_sentence_patterns
                 WHERE (?1 IS NULL OR language=?1)
                   AND (?2 IS NULL OR current_name LIKE ?2 OR current_pattern_text LIKE ?2)
                 ORDER BY updated_at_ms DESC,id ASC",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![language.map(LanguageCode::as_str), pattern],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn list_pattern_versions(
        &self,
        id: &UserSentencePatternId,
    ) -> Result<Vec<UserSentencePatternVersion>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(
                "SELECT version_json FROM user_sentence_pattern_versions
                 WHERE pattern_id=?1 ORDER BY version ASC",
            )
            .map_err(repo)?;
        statement
            .query_map([id.as_str()], |row| from_json(&row.get::<_, String>(0)?))
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn delete_pattern(&self, id: &UserSentencePatternId) -> Result<bool, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "DELETE FROM user_sentence_patterns WHERE id=?1",
                [id.as_str()],
            )
            .map(|count| count > 0)
            .map_err(repo)
    }

    fn save_personal_expression_attempt(
        &self,
        attempt: &PersonalExpressionAttempt,
    ) -> Result<PersonalExpressionAttempt, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO personal_expression_attempts
                 (id,pattern_id,pattern_version_id,channel,assistance,completed_at_ms,attempt_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)",
                params![
                    attempt.id.as_str(),
                    attempt.pattern_id.as_str(),
                    attempt.pattern_version_id.as_str(),
                    match attempt.channel {
                        domain::PersonalExpressionChannel::Speaking => "speaking",
                        domain::PersonalExpressionChannel::Writing => "writing",
                    },
                    json(&attempt.assistance)?,
                    attempt.completed_at_ms,
                    json(attempt)?,
                ],
            )
            .map_err(repo)?;
        Ok(attempt.clone())
    }

    fn list_personal_expression_attempts(
        &self,
        id: &UserSentencePatternId,
    ) -> Result<Vec<PersonalExpressionAttempt>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(
                "SELECT attempt_json FROM personal_expression_attempts
                 WHERE pattern_id=?1 ORDER BY completed_at_ms DESC,id ASC",
            )
            .map_err(repo)?;
        statement
            .query_map([id.as_str()], |row| from_json(&row.get::<_, String>(0)?))
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
}
