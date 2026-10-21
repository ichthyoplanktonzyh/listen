use application::{ApplicationError, RecordingRepository};
use domain::{RecordingAsset, RecordingAssetId};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, from_json, json, repo};

impl RecordingRepository for SqliteRepository {
    fn save_recording_asset(
        &self,
        asset: &RecordingAsset,
    ) -> Result<RecordingAsset, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO recording_assets(id,file_path,duration_ms,created_at_ms,asset_json)
                 VALUES (?1,?2,?3,?4,?5)
                 ON CONFLICT(id) DO UPDATE SET file_path=excluded.file_path,
                   duration_ms=excluded.duration_ms,asset_json=excluded.asset_json",
                params![
                    asset.id.as_str(),
                    asset.file_path,
                    asset.duration_ms,
                    asset.created_at_ms,
                    json(asset)?,
                ],
            )
            .map_err(repo)?;
        Ok(asset.clone())
    }

    fn get_recording_asset(
        &self,
        id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT asset_json FROM recording_assets WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn delete_recording_asset(
        &self,
        id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError> {
        let existing = self.get_recording_asset(id)?;
        if existing.is_some() {
            self.connection
                .lock()
                .execute("DELETE FROM recording_assets WHERE id=?1", [id.as_str()])
                .map_err(repo)?;
        }
        Ok(existing)
    }
}
