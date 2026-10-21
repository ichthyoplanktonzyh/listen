use std::sync::Arc;

use domain::{
    PersonalExpressionAttempt, UserSentencePatternAsset, UserSentencePatternId,
    UserSentencePatternVersion, validate_pattern_version, validate_personal_expression_attempt,
};

use crate::{ApplicationError, PersonalExpressionRepository};

#[derive(Clone)]
pub struct PersonalExpressionUseCases {
    repository: Arc<dyn PersonalExpressionRepository>,
}

impl PersonalExpressionUseCases {
    pub fn new(repository: Arc<dyn PersonalExpressionRepository>) -> Self {
        Self { repository }
    }

    pub fn create(
        &self,
        asset: UserSentencePatternAsset,
    ) -> Result<UserSentencePatternAsset, ApplicationError> {
        validate_pattern_version(&asset.current_version).map_err(ApplicationError::Invalid)?;
        if asset.source.text.trim().is_empty()
            || asset.current_version.pattern_id != asset.id
            || asset.current_version.version != 1
        {
            return Err(ApplicationError::Invalid(
                "new pattern requires a source snapshot and version 1 owned by the asset".into(),
            ));
        }
        self.repository.create_pattern(&asset)
    }

    pub fn revise(
        &self,
        pattern_id: &UserSentencePatternId,
        version: UserSentencePatternVersion,
        updated_at_ms: u64,
    ) -> Result<UserSentencePatternAsset, ApplicationError> {
        validate_pattern_version(&version).map_err(ApplicationError::Invalid)?;
        let current = self
            .repository
            .get_pattern(pattern_id)?
            .ok_or(ApplicationError::NotFound("sentence pattern"))?;
        if version.pattern_id != *pattern_id
            || version.version != current.current_version.version + 1
        {
            return Err(ApplicationError::Conflict(
                "pattern revision must append the next immutable version",
            ));
        }
        self.repository
            .append_pattern_version(pattern_id, &version, updated_at_ms)
    }

    pub fn get(
        &self,
        id: &UserSentencePatternId,
    ) -> Result<UserSentencePatternAsset, ApplicationError> {
        self.repository
            .get_pattern(id)?
            .ok_or(ApplicationError::NotFound("sentence pattern"))
    }

    pub fn list(
        &self,
        language: Option<&domain::LanguageCode>,
        query: Option<&str>,
    ) -> Result<Vec<UserSentencePatternAsset>, ApplicationError> {
        self.repository.list_patterns(language, query)
    }

    pub fn versions(
        &self,
        id: &UserSentencePatternId,
    ) -> Result<Vec<UserSentencePatternVersion>, ApplicationError> {
        self.repository.list_pattern_versions(id)
    }

    pub fn delete(&self, id: &UserSentencePatternId) -> Result<(), ApplicationError> {
        if self.repository.delete_pattern(id)? {
            Ok(())
        } else {
            Err(ApplicationError::NotFound("sentence pattern"))
        }
    }

    pub fn record_attempt(
        &self,
        attempt: PersonalExpressionAttempt,
    ) -> Result<PersonalExpressionAttempt, ApplicationError> {
        validate_personal_expression_attempt(&attempt).map_err(ApplicationError::Invalid)?;
        let asset = self.get(&attempt.pattern_id)?;
        let version_exists = self
            .repository
            .list_pattern_versions(&attempt.pattern_id)?
            .iter()
            .any(|version| version.id == attempt.pattern_version_id);
        if !version_exists || asset.id != attempt.pattern_id {
            return Err(ApplicationError::Invalid(
                "attempt must reference an immutable version of its pattern".into(),
            ));
        }
        self.repository.save_personal_expression_attempt(&attempt)
    }

    pub fn attempts(
        &self,
        id: &UserSentencePatternId,
    ) -> Result<Vec<PersonalExpressionAttempt>, ApplicationError> {
        self.repository.list_personal_expression_attempts(id)
    }

    pub fn export(
        &self,
        language: Option<&domain::LanguageCode>,
        exported_at_ms: u64,
    ) -> Result<domain::PersonalExpressionExportBundle, ApplicationError> {
        let assets = self.repository.list_patterns(language, None)?;
        let mut patterns = Vec::with_capacity(assets.len());
        for asset in assets {
            patterns.push(domain::PersonalExpressionExportPattern {
                versions: self.repository.list_pattern_versions(&asset.id)?,
                attempts: self
                    .repository
                    .list_personal_expression_attempts(&asset.id)?,
                asset,
            });
        }
        Ok(domain::PersonalExpressionExportBundle {
            schema: "llplayer.personal-expression.v1".into(),
            exported_at_ms,
            patterns,
        })
    }
}
