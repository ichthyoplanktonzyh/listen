use application::{ApplicationError, LLTimelineResourceRepository};
use domain::{LLTimelineArtifact, LLTimelineMetadata, SubtitleTrackId};
use rusqlite::{OptionalExtension, params};

use crate::{SqliteRepository, from_json, json, repo};

impl LLTimelineResourceRepository for SqliteRepository {
    fn save_lltimeline_resource(
        &self,
        track_id: &SubtitleTrackId,
        metadata: &LLTimelineMetadata,
        artifacts: &[LLTimelineArtifact],
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO lltimeline_resources
                 (track_id,metadata_json,artifacts_json,updated_at_ms)
                 VALUES (?1,?2,?3,unixepoch('subsec') * 1000)
                 ON CONFLICT(track_id) DO UPDATE SET
                   metadata_json=excluded.metadata_json,
                   artifacts_json=excluded.artifacts_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![track_id.as_str(), json(metadata)?, json(artifacts)?],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get_lltimeline_resource(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<(LLTimelineMetadata, Vec<LLTimelineArtifact>)>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT metadata_json, artifacts_json FROM lltimeline_resources
                 WHERE track_id=?1",
                [track_id.as_str()],
                |row| {
                    Ok((
                        from_json(&row.get::<_, String>(0)?)?,
                        from_json(&row.get::<_, String>(1)?)?,
                    ))
                },
            )
            .optional()
            .map_err(repo)
    }
}
