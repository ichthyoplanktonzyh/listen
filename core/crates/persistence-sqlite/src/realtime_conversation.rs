use application::{ApplicationError, RealtimeConversationRepository};
use domain::{
    RealtimeConversationSession, RealtimeConversationSessionId, RealtimeConversationTurn,
    RealtimeConversationTurnId, RealtimeProviderProfile, RealtimeProviderProfileId, SecretRef,
};
use rusqlite::{Connection, OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

fn enum_value<T: serde::Serialize>(value: &T) -> Result<String, ApplicationError> {
    serde_json::to_value(value)
        .map_err(|error| ApplicationError::Repository(error.to_string()))?
        .as_str()
        .map(ToOwned::to_owned)
        .ok_or_else(|| ApplicationError::Repository("expected enum string".into()))
}

fn upsert_profile(
    connection: &Connection,
    profile: &RealtimeProviderProfile,
) -> Result<(), ApplicationError> {
    connection
        .execute(
            "INSERT INTO realtime_provider_profiles
         (id,display_name,adapter_kind,base_url,model_id,voice,auth_ref,created_at_ms,profile_json)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)
         ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name,
         adapter_kind=excluded.adapter_kind,base_url=excluded.base_url,model_id=excluded.model_id,
         voice=excluded.voice,auth_ref=excluded.auth_ref,profile_json=excluded.profile_json",
            params![
                profile.id.as_str(),
                profile.display_name,
                profile.adapter_kind.as_str(),
                profile.base_url,
                profile.model_id,
                profile.voice,
                profile.auth_ref.as_ref().map(SecretRef::as_str),
                profile.created_at_ms,
                json(profile)?
            ],
        )
        .map_err(repo)?;
    Ok(())
}

impl RealtimeConversationRepository for SqliteRepository {
    fn upsert_realtime_profile(
        &self,
        profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError> {
        upsert_profile(&self.connection.lock(), profile)?;
        Ok(profile.clone())
    }

    fn get_realtime_profile(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<Option<RealtimeProviderProfile>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT profile_json FROM realtime_provider_profiles WHERE id=?1",
                params![id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_realtime_profiles(&self) -> Result<Vec<RealtimeProviderProfile>, ApplicationError> {
        let connection = self.connection.lock();
        let mut statement = connection
            .prepare(
                "SELECT profile_json FROM realtime_provider_profiles ORDER BY created_at_ms,id",
            )
            .map_err(repo)?;
        statement
            .query_map([], |row| from_json(&row.get::<_, String>(0)?))
            .map_err(repo)?
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(repo)
    }

    fn delete_realtime_profile(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "DELETE FROM realtime_provider_profiles WHERE id=?1",
                params![id.as_str()],
            )
            .map_err(repo)?;
        Ok(())
    }

    fn upsert_realtime_profile_preserving_credential(
        &self,
        profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError> {
        let mut connection = self.connection.lock();
        let transaction = connection.transaction().map_err(repo)?;
        let mut saved = profile.clone();
        let existing_auth_ref = transaction
            .query_row(
                "SELECT auth_ref FROM realtime_provider_profiles WHERE id=?1",
                [profile.id.as_str()],
                |row| row.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(repo)?;
        if let Some(existing_auth_ref) = existing_auth_ref {
            saved.auth_ref = existing_auth_ref.map(SecretRef::new);
        }
        upsert_profile(&transaction, &saved)?;
        transaction.commit().map_err(repo)?;
        Ok(saved)
    }

    fn upsert_realtime_profile_and_schedule_cleanup(
        &self,
        profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError> {
        let mut connection = self.connection.lock();
        let transaction = connection.transaction().map_err(repo)?;
        let stale_auth_ref = transaction
            .query_row(
                "SELECT auth_ref FROM realtime_provider_profiles WHERE id=?1",
                [profile.id.as_str()],
                |row| row.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(repo)?
            .flatten()
            .map(SecretRef::new);
        upsert_profile(&transaction, profile)?;
        if let Some(active_auth_ref) = profile.auth_ref.as_ref() {
            transaction
                .execute(
                    "DELETE FROM pending_secret_cleanups WHERE auth_ref=?1",
                    [active_auth_ref.as_str()],
                )
                .map_err(repo)?;
        }
        if let Some(auth_ref) = stale_auth_ref
            .as_ref()
            .filter(|stale| Some(*stale) != profile.auth_ref.as_ref())
        {
            transaction
                .execute(
                    "INSERT INTO pending_secret_cleanups (auth_ref,queued_at_ms,state)
                     VALUES (?1,?2,'ready')
                     ON CONFLICT(auth_ref) DO UPDATE SET state='ready'",
                    params![auth_ref.as_str(), application::now_ms()],
                )
                .map_err(repo)?;
        }
        transaction.commit().map_err(repo)?;
        Ok(profile.clone())
    }

    fn delete_realtime_profile_and_schedule_cleanup(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<(), ApplicationError> {
        let mut connection = self.connection.lock();
        let transaction = connection.transaction().map_err(repo)?;
        let stale_auth_ref = transaction
            .query_row(
                "SELECT auth_ref FROM realtime_provider_profiles WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(repo)?
            .flatten()
            .map(SecretRef::new);
        transaction
            .execute(
                "DELETE FROM realtime_provider_profiles WHERE id=?1",
                [id.as_str()],
            )
            .map_err(repo)?;
        if let Some(auth_ref) = stale_auth_ref.as_ref() {
            transaction
                .execute(
                    "INSERT INTO pending_secret_cleanups (auth_ref,queued_at_ms,state)
                     VALUES (?1,?2,'ready')
                     ON CONFLICT(auth_ref) DO UPDATE SET state='ready'",
                    params![auth_ref.as_str(), application::now_ms()],
                )
                .map_err(repo)?;
        }
        transaction.commit().map_err(repo)?;
        Ok(())
    }

    fn save_realtime_session(
        &self,
        session: &RealtimeConversationSession,
    ) -> Result<RealtimeConversationSession, ApplicationError> {
        self.connection.lock().execute(
            "INSERT INTO realtime_conversation_sessions (id,profile_id,language,status,started_at_ms,ended_at_ms,session_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(id) DO UPDATE SET
             status=excluded.status,ended_at_ms=excluded.ended_at_ms,session_json=excluded.session_json",
            params![session.id.as_str(),session.profile_id.as_str(),session.language.as_str(),enum_value(&session.status)?,session.started_at_ms,session.ended_at_ms,json(session)?]
        ).map_err(repo)?;
        Ok(session.clone())
    }

    fn get_realtime_session(
        &self,
        id: &RealtimeConversationSessionId,
    ) -> Result<Option<RealtimeConversationSession>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT session_json FROM realtime_conversation_sessions WHERE id=?1",
                params![id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_realtime_sessions(&self) -> Result<Vec<RealtimeConversationSession>, ApplicationError> {
        let connection = self.connection.lock();
        let mut statement = connection
            .prepare(
                "SELECT session_json FROM realtime_conversation_sessions
                 ORDER BY started_at_ms DESC, id DESC LIMIT 50",
            )
            .map_err(repo)?;
        statement
            .query_map([], |row| from_json(&row.get::<_, String>(0)?))
            .map_err(repo)?
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(repo)
    }

    fn save_realtime_turn(
        &self,
        turn: &RealtimeConversationTurn,
    ) -> Result<RealtimeConversationTurn, ApplicationError> {
        self.connection.lock().execute(
            "INSERT INTO realtime_conversation_turns (id,session_id,sequence,role,status,recording_asset_id,turn_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7) ON CONFLICT(id) DO UPDATE SET
             status=excluded.status,recording_asset_id=excluded.recording_asset_id,turn_json=excluded.turn_json",
            params![turn.id.as_str(),turn.session_id.as_str(),turn.sequence,enum_value(&turn.role)?,enum_value(&turn.status)?,turn.recording_asset_id.as_ref().map(|id| id.as_str()),json(turn)?]
        ).map_err(repo)?;
        Ok(turn.clone())
    }

    fn get_realtime_turn(
        &self,
        id: &RealtimeConversationTurnId,
    ) -> Result<Option<RealtimeConversationTurn>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT turn_json FROM realtime_conversation_turns WHERE id=?1",
                params![id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_realtime_turns(
        &self,
        session_id: &RealtimeConversationSessionId,
    ) -> Result<Vec<RealtimeConversationTurn>, ApplicationError> {
        let connection = self.connection.lock();
        let mut statement = connection.prepare("SELECT turn_json FROM realtime_conversation_turns WHERE session_id=?1 ORDER BY sequence").map_err(repo)?;
        statement
            .query_map(params![session_id.as_str()], |row| {
                from_json(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(repo)
    }
}
