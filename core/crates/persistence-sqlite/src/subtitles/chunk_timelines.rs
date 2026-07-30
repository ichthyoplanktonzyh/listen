use application::{ApplicationError, ChunkTimelineRepository};
use domain::{ChunkTimeline, ChunkTimelineId, SubtitleTrackId, TimelineStatus, WordTimelineId};
use rusqlite::{Connection, OptionalExtension, params};

use crate::{SqliteRepository, from_json, json, repo};

pub(crate) fn save_chunk_timeline_in_connection(
    connection: &Connection,
    timeline: &ChunkTimeline,
) -> Result<(), ApplicationError> {
    super::guard_timeline_ownership(
        connection,
        "chunk_timeline_runs",
        timeline.id.as_str(),
        &timeline.track_id,
        &timeline.media_id,
    )?;
    connection
        .execute(
            "INSERT INTO chunk_timeline_runs
             (id,track_id,media_id,parent_word_timeline_id,status,timeline_json,created_at_ms,updated_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8)
             ON CONFLICT(id) DO UPDATE SET
               parent_word_timeline_id=excluded.parent_word_timeline_id,
               status=excluded.status,timeline_json=excluded.timeline_json,
               updated_at_ms=excluded.updated_at_ms",
            params![
                timeline.id.as_str(),
                timeline.track_id.as_str(),
                timeline.media_id.as_str(),
                timeline
                    .parent_word_timeline_id
                    .as_ref()
                    .map(WordTimelineId::as_str),
                json(&timeline.status)?,
                json(timeline)?,
                timeline.created_at_ms,
                timeline.updated_at_ms
            ],
        )
        .map(|_| ())
        .map_err(repo)
}

impl ChunkTimelineRepository for SqliteRepository {
    fn save_chunk_timeline(
        &self,
        timeline: &ChunkTimeline,
    ) -> Result<ChunkTimeline, ApplicationError> {
        save_chunk_timeline_in_connection(&self.connection.lock(), timeline)?;
        Ok(timeline.clone())
    }

    fn list_chunk_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ChunkTimeline>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare(
                "SELECT timeline_json FROM chunk_timeline_runs
                 WHERE track_id=?1 ORDER BY created_at_ms DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json::<ChunkTimeline>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT timeline_json FROM chunk_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn active_chunk_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT timeline_json FROM chunk_timeline_runs
                 WHERE track_id=?1 AND status=?2
                 ORDER BY updated_at_ms DESC LIMIT 1",
                params![track_id.as_str(), json(&TimelineStatus::Active)?],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn activate_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let selected_json = tx
            .query_row(
                "SELECT timeline_json FROM chunk_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("chunk timeline"))?;
        let mut selected: ChunkTimeline = from_json(&selected_json).map_err(repo)?;
        if selected.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived chunk timeline"));
        }
        let now = application::now_ms();
        let mut active_query = tx
            .prepare(
                "SELECT timeline_json FROM chunk_timeline_runs
                 WHERE track_id=?1 AND status=?2 AND id<>?3",
            )
            .map_err(repo)?;
        let active_timelines = active_query
            .query_map(
                params![
                    selected.track_id.as_str(),
                    json(&TimelineStatus::Active)?,
                    selected.id.as_str()
                ],
                |row| from_json::<ChunkTimeline>(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        drop(active_query);
        for mut timeline in active_timelines {
            timeline.status = TimelineStatus::Candidate;
            timeline.updated_at_ms = now;
            tx.execute(
                "UPDATE chunk_timeline_runs
                 SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![
                    timeline.id.as_str(),
                    json(&timeline.status)?,
                    json(&timeline)?,
                    timeline.updated_at_ms
                ],
            )
            .map_err(repo)?;
        }

        selected.status = TimelineStatus::Active;
        selected.updated_at_ms = now;
        tx.execute(
            "UPDATE chunk_timeline_runs
             SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
            params![
                selected.id.as_str(),
                json(&selected.status)?,
                json(&selected)?,
                selected.updated_at_ms
            ],
        )
        .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(selected)
    }

    fn archive_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let mut timeline = self
            .get_chunk_timeline(id)?
            .ok_or(ApplicationError::NotFound("chunk timeline"))?;
        timeline.status = TimelineStatus::Archived;
        timeline.updated_at_ms = application::now_ms();
        self.save_chunk_timeline(&timeline)
    }

    fn delete_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let timeline_json = tx
            .query_row(
                "SELECT timeline_json FROM chunk_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("chunk timeline"))?;
        let timeline: ChunkTimeline = from_json(&timeline_json).map_err(repo)?;
        tx.execute("DELETE FROM chunk_timeline_runs WHERE id=?1", [id.as_str()])
            .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(timeline)
    }
}
