use application::{ApplicationError, DifficultyRepository};
use domain::ContentDifficultyProfile;
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl DifficultyRepository for SqliteRepository {
    fn save_difficulty_profile(
        &self,
        profile: &ContentDifficultyProfile,
    ) -> Result<ContentDifficultyProfile, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.execute(
            // Cache semantics: one row per subject, replaced wholesale. Query
            // columns are projections of the JSON snapshot and must be
            // rewritten together with it.
            "INSERT INTO content_difficulty_profiles
             (subject_kind,subject_id,language,algorithm_version,input_fingerprint,
              computed_at_ms,profile_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7)
             ON CONFLICT(subject_kind,subject_id) DO UPDATE SET
               language=excluded.language,
               algorithm_version=excluded.algorithm_version,
               input_fingerprint=excluded.input_fingerprint,
               computed_at_ms=excluded.computed_at_ms,
               profile_json=excluded.profile_json",
            params![
                profile.subject_kind,
                profile.subject_id,
                profile.language.as_str(),
                profile.algorithm_version,
                profile.input_fingerprint,
                profile.computed_at_ms,
                json(profile)?,
            ],
        )
        .map_err(repo)?;
        Ok(profile.clone())
    }

    fn get_difficulty_profile(
        &self,
        subject_kind: &str,
        subject_id: &str,
    ) -> Result<Option<ContentDifficultyProfile>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT profile_json FROM content_difficulty_profiles
             WHERE subject_kind=?1 AND subject_id=?2",
            params![subject_kind, subject_id],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }
}
