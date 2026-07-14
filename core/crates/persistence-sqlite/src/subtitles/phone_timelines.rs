use application::{ApplicationError, PhoneTimelineRepository};
use domain::*;
use rusqlite::{OptionalExtension, params};

use crate::{SqliteRepository, from_json, json, repo};

impl PhoneTimelineRepository for SqliteRepository {
    fn save_phone_timeline(
        &self,
        timeline: &PhoneTimeline,
    ) -> Result<PhoneTimeline, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO phone_timeline_runs
                 (id,track_id,media_id,sentence_id,parent_word_timeline_id,
                  parent_phonetic_analysis_id,status,timeline_json,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
                 ON CONFLICT(id) DO UPDATE SET
                   sentence_id=excluded.sentence_id,
                   parent_word_timeline_id=excluded.parent_word_timeline_id,
                   parent_phonetic_analysis_id=excluded.parent_phonetic_analysis_id,
                   status=excluded.status,timeline_json=excluded.timeline_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    timeline.id.as_str(),
                    timeline.track_id.as_str(),
                    timeline.media_id.as_str(),
                    timeline
                        .sentence_id
                        .as_ref()
                        .map(SubtitleSentenceId::as_str),
                    timeline
                        .parent_word_timeline_id
                        .as_ref()
                        .map(WordTimelineId::as_str),
                    timeline
                        .parent_phonetic_analysis_id
                        .as_ref()
                        .map(PhoneticAnalysisId::as_str),
                    json(&timeline.status)?,
                    json(timeline)?,
                    timeline.created_at_ms,
                    timeline.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(timeline.clone())
    }

    fn list_phone_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneTimeline>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare(
                "SELECT timeline_json FROM phone_timeline_runs
                 WHERE track_id=?1 ORDER BY created_at_ms DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json::<PhoneTimeline>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timeline_json FROM phone_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn active_phone_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT timeline_json FROM phone_timeline_runs
                 WHERE track_id=?1 AND status=?2
                 ORDER BY updated_at_ms DESC LIMIT 1",
                params![track_id.as_str(), json(&TimelineStatus::Active)?],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn activate_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let selected_json = tx
            .query_row(
                "SELECT timeline_json FROM phone_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("phone timeline"))?;
        let mut selected: PhoneTimeline = from_json(&selected_json).map_err(repo)?;
        if selected.status == TimelineStatus::Archived {
            return Err(ApplicationError::Validation("archived phone timeline"));
        }
        let now = application::now_ms();
        let mut active_query = tx
            .prepare(
                "SELECT timeline_json FROM phone_timeline_runs
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
                |row| from_json::<PhoneTimeline>(&row.get::<_, String>(0)?),
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        drop(active_query);
        for mut timeline in active_timelines {
            timeline.status = TimelineStatus::Candidate;
            timeline.updated_at_ms = now;
            tx.execute(
                "UPDATE phone_timeline_runs
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
            "UPDATE phone_timeline_runs
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

    fn archive_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        let mut timeline = self
            .get_phone_timeline(id)?
            .ok_or(ApplicationError::NotFound("phone timeline"))?;
        timeline.status = TimelineStatus::Archived;
        timeline.updated_at_ms = application::now_ms();
        self.save_phone_timeline(&timeline)
    }

    fn delete_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let timeline_json = tx
            .query_row(
                "SELECT timeline_json FROM phone_timeline_runs WHERE id=?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .ok_or(ApplicationError::NotFound("phone timeline"))?;
        let timeline: PhoneTimeline = from_json(&timeline_json).map_err(repo)?;
        tx.execute("DELETE FROM phone_timeline_runs WHERE id=?1", [id.as_str()])
            .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(timeline)
    }
}
