use application::{ApplicationError, ReadingPositionRepository};
use domain::{MediaId, ReadingPosition, SubtitleSentenceId, SubtitleTrackId};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, domain_sql, repo};

impl ReadingPositionRepository for SqliteRepository {
    fn save_reading_position(
        &self,
        position: &ReadingPosition,
    ) -> Result<ReadingPosition, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO reading_positions
                 (track_id,media_id,anchor_cue_id,paragraph_index,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5)
                 ON CONFLICT(track_id) DO UPDATE SET
                   media_id=excluded.media_id,
                   anchor_cue_id=excluded.anchor_cue_id,
                   paragraph_index=excluded.paragraph_index,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    position.track_id.as_str(),
                    position.media_id.as_ref().map(MediaId::as_str),
                    position.anchor_cue_id.as_str(),
                    position.paragraph_index,
                    position.updated_at_ms,
                ],
            )
            .map_err(repo)?;
        Ok(position.clone())
    }

    fn get_reading_position(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<ReadingPosition>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT track_id,media_id,anchor_cue_id,paragraph_index,updated_at_ms
                 FROM reading_positions WHERE track_id=?1",
                [track_id.as_str()],
                |row| {
                    Ok(ReadingPosition {
                        track_id: SubtitleTrackId::parse(row.get::<_, String>(0)?)
                            .map_err(domain_sql)?,
                        media_id: row
                            .get::<_, Option<String>>(1)?
                            .map(MediaId::parse)
                            .transpose()
                            .map_err(domain_sql)?,
                        anchor_cue_id: SubtitleSentenceId::parse(row.get::<_, String>(2)?)
                            .map_err(domain_sql)?,
                        paragraph_index: row.get(3)?,
                        updated_at_ms: row.get(4)?,
                    })
                },
            )
            .optional()
            .map_err(repo)
    }
}
