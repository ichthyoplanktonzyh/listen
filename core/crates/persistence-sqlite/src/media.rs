use application::{ApplicationError, MediaRepository};
use domain::{MediaAvailability, MediaId, MediaItem, MediaTriageIntent, TimeMs};
use rusqlite::{OptionalExtension, Transaction, params};

use super::{
    SqliteRepository, domain_sql, from_json, json,
    learning_material::{
        apply_media_membership_in_transaction, ensure_media_material_in_transaction,
    },
    repo,
};

/// The `media_items` columns in storage order, used by every read that
/// rehydrates a typed [`MediaItem`].
const MEDIA_COLUMNS: &str = "id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms, availability, retained_at_ms";

/// Maps one `media_items` row (in [`MEDIA_COLUMNS`] order) into a typed
/// [`MediaItem`]. Stored identifiers must parse as typed ids; anything else is
/// corruption.
fn media_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<MediaItem> {
    Ok(MediaItem {
        id: MediaId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
        path: row.get(1)?,
        fingerprint: row.get(2)?,
        title: row.get(3)?,
        kind: from_json(&row.get::<_, String>(4)?)?,
        duration: row.get::<_, Option<u64>>(5)?.map(TimeMs::new),
        created_at_ms: row.get(6)?,
        updated_at_ms: row.get(7)?,
        availability: from_json(&row.get::<_, String>(8)?)?,
        retained_at_ms: row.get(9)?,
    })
}

/// Reads one media row inside an active transaction by an arbitrary `WHERE`
/// predicate, returning [`ApplicationError::Repository`] when the row is
/// missing. Used to re-read the ACTUAL persisted row after an upsert: the
/// fingerprint conflict key can keep a stored id (and, via COALESCE,
/// membership) that differ from the input.
fn query_media_in_transaction(
    tx: &Transaction<'_>,
    where_clause: &str,
    key: &str,
) -> Result<MediaItem, ApplicationError> {
    tx.query_row(
        &format!("SELECT {MEDIA_COLUMNS} FROM media_items WHERE {where_clause}"),
        [key],
        media_from_row,
    )
    .optional()
    .map_err(repo)?
    .ok_or_else(|| ApplicationError::Repository("media row is missing".into()))
}

pub(crate) fn upsert_media_in_transaction(
    tx: &Transaction<'_>,
    media: &MediaItem,
) -> Result<MediaItem, ApplicationError> {
    tx.execute(
        "INSERT INTO media_items
                 (id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms, availability, retained_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
                 ON CONFLICT(fingerprint) DO UPDATE SET
                   path=excluded.path, title=excluded.title, kind=excluded.kind,
                   duration_ms=excluded.duration_ms, updated_at_ms=excluded.updated_at_ms,
                   availability=excluded.availability,
                   retained_at_ms=COALESCE(media_items.retained_at_ms, excluded.retained_at_ms)",
        params![
            media.id.as_str(),
            media.path,
            media.fingerprint,
            media.title,
            json(&media.kind)?,
            media.duration.map(TimeMs::get),
            media.created_at_ms,
            media.updated_at_ms,
            json(&media.availability)?,
            media.retained_at_ms,
        ],
    )
    .map_err(repo)?;
    // The upsert key is the fingerprint: a conflict keeps the stored id,
    // creation time, and (via COALESCE) membership while the input id may
    // differ. The durable learning-material graph and every linkage must
    // follow the ACTUAL row that won, so re-read it before touching any
    // derived state.
    let persisted = query_media_in_transaction(tx, "fingerprint=?1", &media.fingerprint)?;
    tx.execute(
        "UPDATE lexical_occurrences SET media_id=?1
                 WHERE media_id IS NULL AND media_fingerprint_snapshot=?2",
        params![persisted.id.as_str(), persisted.fingerprint],
    )
    .map_err(repo)?;
    tx.execute(
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
        [persisted.id.as_str()],
    )
    .map_err(repo)?;
    tx.execute(
        "UPDATE lexical_observations
                 SET sentence_id=sentence_id_snapshot
                 WHERE sentence_id IS NULL
                   AND EXISTS (
                     SELECT 1 FROM subtitle_sentences s
                     JOIN subtitle_tracks t ON t.id=s.track_id
                     WHERE s.id=lexical_observations.sentence_id_snapshot AND t.media_id=?1
                   )",
        [persisted.id.as_str()],
    )
    .map_err(repo)?;
    // The media registration and its canonical material graph commit
    // together: a graph failure rolls back the media row and the rest of the
    // enclosing import.
    ensure_media_material_in_transaction(tx, &persisted)?;
    Ok(persisted)
}

impl MediaRepository for SqliteRepository {
    fn upsert(&self, media: &MediaItem) -> Result<MediaItem, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let persisted = upsert_media_in_transaction(&tx, media)?;
        tx.commit().map_err(repo)?;
        drop(conn);
        Ok(persisted)
    }

    fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms, availability, retained_at_ms
             FROM media_items WHERE id=?1",
            [id.as_str()],
            media_from_row,
        )
        .optional()
        .map_err(repo)
    }

    fn list(&self) -> Result<Vec<MediaItem>, ApplicationError> {
        let conn = self.connection.lock();
        let mut query = conn
            .prepare(
                "SELECT id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms, availability, retained_at_ms
                 FROM media_items ORDER BY updated_at_ms DESC, id",
            )
            .map_err(repo)?;
        let items = query
            .query_map([], media_from_row)
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

    fn set_library_membership(
        &self,
        id: &MediaId,
        retained_at_ms: Option<u64>,
        updated_at_ms: u64,
    ) -> Result<MediaItem, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        // Membership mutation touches exactly two columns: `retained_at_ms`
        // and `updated_at_ms`. Media identity, availability, path, progress,
        // subtitles, resources, and every learner-owned record stay intact.
        let changed = tx
            .execute(
                "UPDATE media_items SET retained_at_ms=?2, updated_at_ms=?3 WHERE id=?1",
                params![id.as_str(), retained_at_ms, updated_at_ms],
            )
            .map_err(repo)?;
        if changed == 0 {
            return Err(ApplicationError::NotFound("media"));
        }
        // Defensively ensure the canonical material graph from the actual
        // persisted row (a media row registered without the graph may lack
        // one), then apply the membership to the material and synchronize
        // every media bound to it — all inside this transaction.
        let persisted = query_media_in_transaction(&tx, "id=?1", id.as_str())?;
        ensure_media_material_in_transaction(&tx, &persisted)?;
        apply_media_membership_in_transaction(&tx, id.as_str(), retained_at_ms, updated_at_ms)?;
        tx.commit().map_err(repo)?;
        drop(conn);
        MediaRepository::get(self, id)?.ok_or(ApplicationError::NotFound("media"))
    }
}
