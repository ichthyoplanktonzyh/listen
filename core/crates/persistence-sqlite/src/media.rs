use application::{ApplicationError, MediaRepository};
use domain::{MediaAvailability, MediaId, MediaItem, MediaTriageIntent, TimeMs};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, domain_sql, from_json, json, repo};

impl MediaRepository for SqliteRepository {
    fn upsert(&self, media: &MediaItem) -> Result<MediaItem, ApplicationError> {
        {
            let conn = self.connection.lock();
            conn.execute(
                "INSERT INTO media_items
                 (id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms, availability)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
                 ON CONFLICT(fingerprint) DO UPDATE SET
                   path=excluded.path, title=excluded.title, kind=excluded.kind,
                   duration_ms=excluded.duration_ms, updated_at_ms=excluded.updated_at_ms,
                   availability=excluded.availability",
                params![
                    media.id.as_str(),
                    media.path,
                    media.fingerprint,
                    media.title,
                    json(&media.kind)?,
                    media.duration.map(TimeMs::get),
                    media.created_at_ms,
                    media.updated_at_ms,
                    json(&media.availability)?
                ],
            )
            .map_err(repo)?;
            conn.execute(
                "UPDATE lexical_occurrences SET media_id=?1
                 WHERE media_id IS NULL AND media_fingerprint_snapshot=?2",
                params![media.id.as_str(), media.fingerprint],
            )
            .map_err(repo)?;
            conn.execute(
                "UPDATE lexical_occurrences
                 SET sentence_id=(
                   SELECT s.id FROM subtitle_sentences s
                   JOIN subtitle_tracks t ON t.id=s.track_id
                   WHERE t.media_id=?1
                     AND s.start_ms=lexical_occurrences.start_ms_snapshot
                     AND s.end_ms=lexical_occurrences.end_ms_snapshot
                     AND s.display_text=lexical_occurrences.sentence_text_snapshot
                   LIMIT 1
                 )
                 WHERE media_id=?1 AND sentence_id IS NULL",
                [media.id.as_str()],
            )
            .map_err(repo)?;
            conn.execute(
                "UPDATE lexical_observations
                 SET sentence_id=sentence_id_snapshot
                 WHERE sentence_id IS NULL
                   AND EXISTS (
                     SELECT 1 FROM subtitle_sentences s
                     JOIN subtitle_tracks t ON t.id=s.track_id
                     WHERE s.id=lexical_observations.sentence_id_snapshot AND t.media_id=?1
                   )",
                [media.id.as_str()],
            )
            .map_err(repo)?;
        }
        MediaRepository::get(self, &media.id)?
            .ok_or_else(|| ApplicationError::Repository("media upsert returned no row".into()))
    }

    fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms, availability
             FROM media_items WHERE id=?1",
            [id.as_str()],
            |r| {
                Ok(MediaItem {
                    id: MediaId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                    path: r.get(1)?,
                    fingerprint: r.get(2)?,
                    title: r.get(3)?,
                    kind: from_json(&r.get::<_, String>(4)?)?,
                    duration: r.get::<_, Option<u64>>(5)?.map(TimeMs::new),
                    created_at_ms: r.get(6)?,
                    updated_at_ms: r.get(7)?,
                    availability: from_json(&r.get::<_, String>(8)?)?,
                })
            },
        )
        .optional()
        .map_err(repo)
    }

    fn list(&self) -> Result<Vec<MediaItem>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare(
                "SELECT id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms, availability
                 FROM media_items ORDER BY updated_at_ms DESC, id",
            )
            .map_err(repo)?;
        let items = query
            .query_map([], |r| {
                Ok(MediaItem {
                    id: MediaId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                    path: r.get(1)?,
                    fingerprint: r.get(2)?,
                    title: r.get(3)?,
                    kind: from_json(&r.get::<_, String>(4)?)?,
                    duration: r.get::<_, Option<u64>>(5)?.map(TimeMs::new),
                    created_at_ms: r.get(6)?,
                    updated_at_ms: r.get(7)?,
                    availability: from_json(&r.get::<_, String>(8)?)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(items)
    }

    fn set_triage_intent(
        &self,
        media_id: &MediaId,
        intent: Option<MediaTriageIntent>,
        updated_at_ms: u64,
    ) -> Result<(), ApplicationError> {
        let conn = self.connection.lock();
        match intent {
            Some(intent) => conn
                .execute(
                    "INSERT INTO media_triage_intents (media_id, intent, updated_at_ms)
                     VALUES (?1, ?2, ?3)
                     ON CONFLICT(media_id) DO UPDATE SET
                       intent=excluded.intent, updated_at_ms=excluded.updated_at_ms",
                    params![media_id.as_str(), json(&intent)?, updated_at_ms],
                )
                .map_err(repo)?,
            None => conn
                .execute(
                    "DELETE FROM media_triage_intents WHERE media_id=?1",
                    [media_id.as_str()],
                )
                .map_err(repo)?,
        };
        Ok(())
    }

    fn get_triage_intent(
        &self,
        media_id: &MediaId,
    ) -> Result<Option<MediaTriageIntent>, ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT intent FROM media_triage_intents WHERE media_id=?1",
            [media_id.as_str()],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .optional()
        .map_err(repo)
    }

    fn list_triage_intents(&self) -> Result<Vec<(MediaId, MediaTriageIntent)>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare("SELECT media_id, intent FROM media_triage_intents")
            .map_err(repo)?;
        let intents = query
            .query_map([], |row| {
                Ok((
                    MediaId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
                    from_json(&row.get::<_, String>(1)?)?,
                ))
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(intents)
    }

    fn set_availability(
        &self,
        id: &MediaId,
        availability: MediaAvailability,
    ) -> Result<MediaItem, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        tx.execute(
                "UPDATE media_items SET availability=?2, updated_at_ms=unixepoch('subsec') * 1000 WHERE id=?1",
                params![id.as_str(), json(&availability)?],
            )
            .map_err(repo)?;
        if availability != MediaAvailability::Available {
            tx.execute(
                "UPDATE lexical_observations SET sentence_id=NULL
                 WHERE sentence_id IN (
                   SELECT s.id FROM subtitle_sentences s
                   JOIN subtitle_tracks t ON t.id=s.track_id
                   WHERE t.media_id=?1
                 )",
                [id.as_str()],
            )
            .map_err(repo)?;
            tx.execute(
                "UPDATE lexical_occurrences SET media_id=NULL, sentence_id=NULL WHERE media_id=?1",
                [id.as_str()],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        MediaRepository::get(self, id)?.ok_or(ApplicationError::NotFound("media"))
    }
}
