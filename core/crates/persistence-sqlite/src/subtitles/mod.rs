mod chunk_timelines;
mod content_package_import;
mod lltimeline_import;
mod lltimeline_resources;
mod phone_timelines;
mod pronunciations;
mod prosody;
mod sense_groups;
mod subtitle_tracks;
mod word_timelines;

use application::ApplicationError;
use domain::{MediaId, SubtitleTrackId};
use rusqlite::{Connection, OptionalExtension};

pub(crate) fn guard_timeline_ownership(
    connection: &Connection,
    table: &str,
    id: &str,
    track_id: &SubtitleTrackId,
    media_id: &MediaId,
) -> Result<(), ApplicationError> {
    let sql = format!("SELECT track_id,media_id FROM {table} WHERE id=?1");
    let existing = connection
        .query_row(&sql, [id], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })
        .optional()
        .map_err(crate::repo)?;
    if existing.is_some_and(|(existing_track, existing_media)| {
        existing_track != track_id.as_str() || existing_media != media_id.as_str()
    }) {
        return Err(ApplicationError::Invalid(
            "timeline id already belongs to another source".into(),
        ));
    }
    Ok(())
}
