use application::{ApplicationError, PlaybackProgressRepository};
use domain::{MediaId, TimeMs};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, repo};

impl PlaybackProgressRepository for SqliteRepository {
    fn load(&self, media_id: &MediaId) -> Result<Option<TimeMs>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT position_ms FROM playback_progress WHERE media_id=?1",
                [media_id.as_str()],
                |r| r.get::<_, u64>(0).map(TimeMs::new),
            )
            .optional()
            .map_err(repo)
    }

    fn save(&self, media_id: &MediaId, position: TimeMs) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO playback_progress(media_id, position_ms, updated_at_ms)
                 VALUES (?1, ?2, unixepoch('subsec') * 1000)
                 ON CONFLICT(media_id) DO UPDATE SET
                   position_ms=excluded.position_ms, updated_at_ms=excluded.updated_at_ms",
                params![media_id.as_str(), position.get()],
            )
            .map(|_| ())
            .map_err(repo)
    }
}
