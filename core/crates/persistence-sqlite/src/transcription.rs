use application::{ApplicationError, TranscriptionRepository};
use domain::{TranscriptionModelDescriptor, TranscriptionModelId};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl TranscriptionRepository for SqliteRepository {
    fn upsert_model(
        &self,
        model: &TranscriptionModelDescriptor,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO transcription_models(id,provider_id,descriptor_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4)
                 ON CONFLICT(id) DO UPDATE SET provider_id=excluded.provider_id,
                   descriptor_json=excluded.descriptor_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    model.id.as_str(),
                    model.provider_id,
                    json(model)?,
                    model.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(model.clone())
    }

    fn list_models(&self) -> Result<Vec<TranscriptionModelDescriptor>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare("SELECT descriptor_json FROM transcription_models ORDER BY provider_id,id")
            .map_err(repo)?;
        query
            .query_map([], |row| {
                from_json::<TranscriptionModelDescriptor>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_model(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<Option<TranscriptionModelDescriptor>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT descriptor_json FROM transcription_models WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn delete_model(&self, id: &TranscriptionModelId) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "DELETE FROM transcription_models WHERE id=?1",
                [id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }
}
