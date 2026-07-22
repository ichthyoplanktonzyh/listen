use application::{ApplicationError, LearnerProfileRepository};
use domain::{LanguageCode, LearnerProfile, LearnerProfileId};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, domain_sql, repo};

impl LearnerProfileRepository for SqliteRepository {
    fn save_learner_profile(
        &self,
        profile: &LearnerProfile,
    ) -> Result<LearnerProfile, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO learner_profiles
                 (id,ui_language,l1_language,active_l2_language,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6)
                 ON CONFLICT(id) DO UPDATE SET
                   ui_language=excluded.ui_language,
                   l1_language=excluded.l1_language,
                   active_l2_language=excluded.active_l2_language,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    profile.id.as_str(),
                    profile.ui_language.as_str(),
                    profile.l1_language.as_ref().map(LanguageCode::as_str),
                    profile
                        .active_l2_language
                        .as_ref()
                        .map(LanguageCode::as_str),
                    profile.created_at_ms,
                    profile.updated_at_ms,
                ],
            )
            .map_err(repo)?;
        Ok(profile.clone())
    }

    fn get_learner_profile(
        &self,
        id: &LearnerProfileId,
    ) -> Result<Option<LearnerProfile>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT id,ui_language,l1_language,active_l2_language,created_at_ms,updated_at_ms
                 FROM learner_profiles WHERE id=?1",
                [id.as_str()],
                |row| {
                    Ok(LearnerProfile {
                        id: LearnerProfileId::parse(row.get::<_, String>(0)?)
                            .map_err(domain_sql)?,
                        ui_language: LanguageCode::parse(row.get::<_, String>(1)?)
                            .map_err(domain_sql)?,
                        l1_language: row
                            .get::<_, Option<String>>(2)?
                            .map(LanguageCode::parse)
                            .transpose()
                            .map_err(domain_sql)?,
                        active_l2_language: row
                            .get::<_, Option<String>>(3)?
                            .map(LanguageCode::parse)
                            .transpose()
                            .map_err(domain_sql)?,
                        created_at_ms: row.get(4)?,
                        updated_at_ms: row.get(5)?,
                    })
                },
            )
            .optional()
            .map_err(repo)
    }
}
