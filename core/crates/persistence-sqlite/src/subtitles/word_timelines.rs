use application::{ApplicationError, WordTimelineRepository};
use domain::{
    SubtitleSentenceId, SubtitleTrackId, TimelineStatus, WordTimeline, WordTimelineId, WordTiming,
};
use rusqlite::{Connection, OptionalExtension, params};

use crate::{SqliteRepository, from_json, json, repo};

pub(crate) fn save_word_timeline_in_connection(
    connection: &Connection,
    timeline: &WordTimeline,
) -> Result<(), ApplicationError> {
    super::guard_timeline_ownership(
        connection,
        "word_timeline_runs",
        timeline.id.as_str(),
        &timeline.track_id,
        &timeline.media_id,
    )?;
    connection
        .execute(
            "INSERT INTO word_timeline_runs
             (id,track_id,media_id,status,timeline_json,created_at_ms,updated_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6,?7)
             ON CONFLICT(id) DO UPDATE SET
               status=excluded.status,timeline_json=excluded.timeline_json,
               updated_at_ms=excluded.updated_at_ms",
            params![
                timeline.id.as_str(),
                timeline.track_id.as_str(),
                timeline.media_id.as_str(),
                json(&timeline.status)?,
                json(timeline)?,
                timeline.created_at_ms,
                timeline.updated_at_ms
            ],
        )
        .map(|_| ())
        .map_err(repo)
}

pub(crate) fn replace_legacy_word_timings_in_connection(
    connection: &Connection,
    track_id: &SubtitleTrackId,
    active: Option<&WordTimeline>,
    updated_at_ms: u64,
) -> Result<(), ApplicationError> {
    connection
        .execute(
            "DELETE FROM word_timings
             WHERE sentence_id IN (
               SELECT id FROM subtitle_sentences WHERE track_id=?1
             )",
            [track_id.as_str()],
        )
        .map_err(repo)?;
    let Some(active) = active else {
        return Ok(());
    };
    let mut grouped = std::collections::HashMap::<SubtitleSentenceId, Vec<WordTiming>>::new();
    for word in &active.words {
        grouped
            .entry(word.sentence_id.clone())
            .or_default()
            .push(word.clone());
    }
    for (sentence_id, mut timings) in grouped {
        timings.sort_by_key(|value| (value.start_ms, value.end_ms, value.token_index));
        if let Some(first) = timings.first() {
            connection
                .execute(
                    "INSERT INTO word_timings
                     (sentence_id,timing_source,provider_id,provider_version,timings_json,updated_at_ms)
                     VALUES (?1,?2,?3,?4,?5,?6)
                     ON CONFLICT(sentence_id) DO UPDATE SET
                       timing_source=excluded.timing_source,provider_id=excluded.provider_id,
                       provider_version=excluded.provider_version,timings_json=excluded.timings_json,
                       updated_at_ms=excluded.updated_at_ms",
                    params![
                        sentence_id.as_str(),
                        json(&first.timing_source)?,
                        first.provider_id,
                        first.provider_version,
                        json(&timings)?,
                        updated_at_ms
                    ],
                )
                .map_err(repo)?;
        }
    }
    Ok(())
}

impl WordTimelineRepository for SqliteRepository {
    fn save_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
        timings: &[WordTiming],
    ) -> Result<(), ApplicationError> {
        let Some(first) = timings.first() else {
            return Ok(());
        };
        self.connection
            .lock()
            .execute(
                "INSERT INTO word_timings
                 (sentence_id,timing_source,provider_id,provider_version,timings_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,unixepoch('subsec') * 1000)
                 ON CONFLICT(sentence_id) DO UPDATE SET
                   timing_source=excluded.timing_source,provider_id=excluded.provider_id,
                   provider_version=excluded.provider_version,timings_json=excluded.timings_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    sentence_id.as_str(),
                    json(&first.timing_source)?,
                    first.provider_id,
                    first.provider_version,
                    json(&timings)?
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT timings_json FROM word_timings WHERE sentence_id=?1",
                [sentence_id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map(|value| value.unwrap_or_default())
            .map_err(repo)
    }

    fn save_word_timeline(
        &self,
        timeline: &WordTimeline,
    ) -> Result<WordTimeline, ApplicationError> {
        save_word_timeline_in_connection(&self.connection.lock(), timeline)?;
        Ok(timeline.clone())
    }

    fn list_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimeline>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare(
                "SELECT timeline_json FROM word_timeline_runs
                 WHERE track_id=?1 ORDER BY created_at_ms DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json::<WordTimeline>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT timeline_json FROM word_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn active_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        self.connection
            .lock()
            .query_row(
                "SELECT timeline_json FROM word_timeline_runs
                 WHERE track_id=?1 AND status=?2
                 ORDER BY updated_at_ms DESC LIMIT 1",
                params![track_id.as_str(), json(&TimelineStatus::Active)?],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn activate_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let selected_json = tx
            .query_row(
                "SELECT timeline_json FROM word_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        let mut selected: WordTimeline = from_json(&selected_json).map_err(repo)?;
        if selected.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived word timeline"));
        }
        let now = application::now_ms();
        let mut active_query = tx
            .prepare(
                "SELECT timeline_json FROM word_timeline_runs
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
                |row| from_json::<WordTimeline>(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        drop(active_query);
        for mut timeline in active_timelines {
            timeline.status = TimelineStatus::Candidate;
            timeline.updated_at_ms = now;
            tx.execute(
                "UPDATE word_timeline_runs
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
            "UPDATE word_timeline_runs
             SET status=?2,timeline_json=?3,updated_at_ms=?4 WHERE id=?1",
            params![
                selected.id.as_str(),
                json(&selected.status)?,
                json(&selected)?,
                selected.updated_at_ms
            ],
        )
        .map_err(repo)?;
        replace_legacy_word_timings_in_connection(&tx, &selected.track_id, Some(&selected), now)?;
        tx.commit().map_err(repo)?;
        Ok(selected)
    }

    fn archive_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError> {
        let mut timeline = self
            .get_word_timeline(id)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        let was_active = timeline.status == TimelineStatus::Active;
        timeline.status = TimelineStatus::Archived;
        timeline.updated_at_ms = application::now_ms();
        let timeline = self.save_word_timeline(&timeline)?;
        if was_active {
            self.connection
                .lock()
                .execute(
                    "DELETE FROM word_timings
                     WHERE sentence_id IN (
                       SELECT id FROM subtitle_sentences WHERE track_id=?1
                     )",
                    [timeline.track_id.as_str()],
                )
                .map_err(repo)?;
        }
        Ok(timeline)
    }

    fn delete_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let timeline_json = tx
            .query_row(
                "SELECT timeline_json FROM word_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("word timeline"))?;
        let timeline: WordTimeline = from_json(&timeline_json).map_err(repo)?;
        tx.execute("DELETE FROM word_timeline_runs WHERE id=?1", [id.as_str()])
            .map_err(repo)?;
        if timeline.status == TimelineStatus::Active {
            tx.execute(
                "DELETE FROM word_timings
                 WHERE sentence_id IN (
                   SELECT id FROM subtitle_sentences WHERE track_id=?1
                 )",
                [timeline.track_id.as_str()],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        Ok(timeline)
    }
}
