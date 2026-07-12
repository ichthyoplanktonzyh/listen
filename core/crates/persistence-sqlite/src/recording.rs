use application::{ApplicationError, RecordingRepository};
use domain::{MediaId, PlayableSegmentAvailability, RecordingAsset, RecordingAssetId};
use rusqlite::{OptionalExtension, params};

use crate::{SqliteRepository, domain_sql, from_json, json, repo};

impl RecordingRepository for SqliteRepository {
    fn save_recording_asset(
        &self,
        asset: &RecordingAsset,
    ) -> Result<RecordingAsset, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        connection
            .execute(
                "INSERT INTO recording_assets
                 (id,practice_attempt_id,media_id,language,file_path,duration_ms,created_at_ms,asset_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
                 ON CONFLICT(id) DO UPDATE SET
                   practice_attempt_id=excluded.practice_attempt_id,
                   media_id=excluded.media_id,
                   language=excluded.language,
                   file_path=excluded.file_path,
                   duration_ms=excluded.duration_ms,
                   asset_json=excluded.asset_json",
                params![
                    asset.id.as_str(),
                    asset.practice_attempt_id.as_ref().map(|id| id.as_str()),
                    asset.source_segment.media_id.as_ref().map(|id| id.as_str()),
                    asset.language.as_str(),
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
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        connection
            .query_row(
                "SELECT media_id,asset_json FROM recording_assets WHERE id=?1",
                params![id.as_str()],
                |row| {
                    let media_id = row
                        .get::<_, Option<String>>(0)?
                        .map(MediaId::parse)
                        .transpose()
                        .map_err(domain_sql)?;
                    let asset_json = row.get::<_, String>(1)?;
                    let mut asset: RecordingAsset = from_json(&asset_json)?;
                    asset.source_segment.media_id = media_id;
                    if asset.source_segment.media_id.is_none() {
                        asset.source_segment.availability =
                            PlayableSegmentAvailability::MissingMedia;
                    }
                    Ok(asset)
                },
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
                .expect("sqlite mutex poisoned")
                .execute(
                    "DELETE FROM recording_assets WHERE id=?1",
                    params![id.as_str()],
                )
                .map_err(repo)?;
        }
        Ok(existing)
    }
}
