use application::{ApplicationError, RealtimeConversationRepository};
use domain::{
    RealtimeConversationSession, RealtimeConversationSessionId, RealtimeConversationTurn,
    RealtimeConversationTurnId, RealtimeProviderProfile, RealtimeProviderProfileId,
};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

fn enum_value<T: serde::Serialize>(value: &T) -> Result<String, ApplicationError> {
    serde_json::to_value(value)
        .map_err(|error| ApplicationError::Repository(error.to_string()))?
        .as_str()
        .map(ToOwned::to_owned)
        .ok_or_else(|| ApplicationError::Repository("expected enum string".into()))
}

impl RealtimeConversationRepository for SqliteRepository {
    fn upsert_realtime_profile(
        &self,
        profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError> {
        self.connection.lock().expect("sqlite mutex poisoned").execute(
            "INSERT INTO realtime_provider_profiles
             (id,display_name,adapter_kind,base_url,model_id,voice,auth_ref,created_at_ms,profile_json)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)
             ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name,
             adapter_kind=excluded.adapter_kind,base_url=excluded.base_url,model_id=excluded.model_id,
             voice=excluded.voice,auth_ref=excluded.auth_ref,profile_json=excluded.profile_json",
            params![profile.id.as_str(), profile.display_name, profile.adapter_kind.as_str(),
                profile.base_url, profile.model_id, profile.voice, profile.auth_ref.as_str(),
                profile.created_at_ms, json(profile)?],
        ).map_err(repo)?;
        Ok(profile.clone())
    }

    fn get_realtime_profile(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<Option<RealtimeProviderProfile>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT profile_json FROM realtime_provider_profiles WHERE id=?1",
                params![id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_realtime_profiles(&self) -> Result<Vec<RealtimeProviderProfile>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
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
            .expect("sqlite mutex poisoned")
            .execute(
                "DELETE FROM realtime_provider_profiles WHERE id=?1",
                params![id.as_str()],
            )
            .map_err(repo)?;
        Ok(())
    }

    fn save_realtime_session(
        &self,
        session: &RealtimeConversationSession,
    ) -> Result<RealtimeConversationSession, ApplicationError> {
        self.connection.lock().expect("sqlite mutex poisoned").execute(
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
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT session_json FROM realtime_conversation_sessions WHERE id=?1",
                params![id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn save_realtime_turn(
        &self,
        turn: &RealtimeConversationTurn,
    ) -> Result<RealtimeConversationTurn, ApplicationError> {
        self.connection.lock().expect("sqlite mutex poisoned").execute(
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
            .expect("sqlite mutex poisoned")
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
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
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
