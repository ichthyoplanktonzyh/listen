//! Phase 3.12 LLM provider profile persistence.
//!
//! Only routing metadata and the opaque `auth_ref` are stored; `profile_json`
//! serializes an `LlmProviderProfile`, which by construction has no secret
//! field. The raw credential lives solely in the OS keychain (shared context
//! §3.4). Profiles are mutable config, so upsert replaces on conflict.

use application::{ApplicationError, LlmProviderProfileRepository};
use domain::{LlmAuthRef, LlmProviderProfile, LlmProviderProfileId};
use rusqlite::{OptionalExtension, Row, params};

use super::{SqliteRepository, from_json, json, repo};

fn profile_from_row(row: &Row<'_>) -> rusqlite::Result<LlmProviderProfile> {
    from_json(&row.get::<_, String>(0)?)
}

impl LlmProviderProfileRepository for SqliteRepository {
    fn upsert_provider_profile(
        &self,
        profile: &LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO llm_provider_profiles
                 (id,display_name,adapter_kind,base_url,model_id,auth_ref,created_at_ms,profile_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
                 ON CONFLICT(id) DO UPDATE SET
                   display_name=excluded.display_name,
                   adapter_kind=excluded.adapter_kind,
                   base_url=excluded.base_url,
                   model_id=excluded.model_id,
                   auth_ref=excluded.auth_ref,
                   created_at_ms=excluded.created_at_ms,
                   profile_json=excluded.profile_json",
                params![
                    profile.id.as_str(),
                    profile.display_name,
                    profile.adapter_kind.as_str(),
                    profile.base_url,
                    profile.model_id,
                    profile.auth_ref.as_ref().map(LlmAuthRef::as_str),
                    profile.created_at_ms,
                    json(profile)?,
                ],
            )
            .map_err(repo)?;
        Ok(profile.clone())
    }

    fn get_provider_profile(
        &self,
        id: &LlmProviderProfileId,
    ) -> Result<Option<LlmProviderProfile>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT profile_json FROM llm_provider_profiles WHERE id=?1",
                params![id.as_str()],
                profile_from_row,
            )
            .optional()
            .map_err(repo)
    }

    fn list_provider_profiles(&self) -> Result<Vec<LlmProviderProfile>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare("SELECT profile_json FROM llm_provider_profiles ORDER BY created_at_ms, id")
            .map_err(repo)?;
        let rows = statement
            .query_map([], profile_from_row)
            .map_err(repo)?
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(repo)?;
        Ok(rows)
    }

    fn delete_provider_profile(&self, id: &LlmProviderProfileId) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "DELETE FROM llm_provider_profiles WHERE id=?1",
                params![id.as_str()],
            )
            .map_err(repo)?;
        Ok(())
    }
}
