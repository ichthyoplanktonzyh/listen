use application::{ApplicationError, SubtitleTrackRepository};
use domain::*;
use rusqlite::{OptionalExtension, params};

use crate::{SqliteRepository, domain_sql, from_json, json, repo};

impl SubtitleTrackRepository for SqliteRepository {
    fn save_track(&self, track: &SubtitleTrack) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        tx.execute(
            "INSERT INTO subtitle_tracks(id, media_id, fingerprint, language, source, status)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(media_id, fingerprint) DO UPDATE SET
               language=excluded.language, source=excluded.source, status=excluded.status",
            params![
                track.id.as_str(),
                track.media_id.as_str(),
                track.fingerprint,
                track.language.as_ref().map(LanguageCode::as_str),
                track.source,
                json(&track.status)?
            ],
        )
        .map_err(repo)?;
        tx.execute(
            "DELETE FROM subtitle_sentences WHERE track_id=?1",
            [track.id.as_str()],
        )
        .map_err(repo)?;
        for sentence in &track.sentences {
            tx.execute(
                "INSERT INTO subtitle_sentences
                 (id, track_id, cue_index, start_ms, end_ms, original_text, display_text, tokens_json)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                params![
                    sentence.id.as_str(),
                    track.id.as_str(),
                    sentence.index,
                    sentence.start.get(),
                    sentence.end.get(),
                    sentence.original_text,
                    sentence.display_text,
                    json(&sentence.tokens)?
                ],
            )
            .map_err(repo)?;
            tx.execute(
                "UPDATE lexical_occurrences SET sentence_id=?1
                 WHERE sentence_id IS NULL
                   AND media_id=?2
                   AND start_ms_snapshot=?3
                   AND end_ms_snapshot=?4
                   AND sentence_text_snapshot=?5",
                params![
                    sentence.id.as_str(),
                    track.media_id.as_str(),
                    sentence.start.get(),
                    sentence.end.get(),
                    sentence.display_text
                ],
            )
            .map_err(repo)?;
            tx.execute(
                "UPDATE lexical_observations SET sentence_id=?1
                 WHERE sentence_id IS NULL AND sentence_id_snapshot=?1",
                [sentence.id.as_str()],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn get_track(&self, id: &SubtitleTrackId) -> Result<Option<SubtitleTrack>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut track = conn
            .query_row(
                "SELECT id, media_id, fingerprint, language, source, status FROM subtitle_tracks WHERE id=?1",
                [id.as_str()],
                |r| {
                    Ok(SubtitleTrack {
                        id: SubtitleTrackId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                        media_id: MediaId::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
                        fingerprint: r.get(2)?,
                        language: r
                            .get::<_, Option<String>>(3)?
                            .map(LanguageCode::parse)
                            .transpose()
                            .map_err(domain_sql)?,
                        source: r.get(4)?,
                        status: from_json(&r.get::<_, String>(5)?)?,
                        sentences: vec![],
                    })
                },
            )
            .optional()
            .map_err(repo)?;
        let Some(track_value) = track.as_mut() else {
            return Ok(None);
        };
        let mut query = conn
            .prepare(
                "SELECT id, cue_index, start_ms, end_ms, original_text, display_text, tokens_json
                 FROM subtitle_sentences WHERE track_id=?1 ORDER BY cue_index",
            )
            .map_err(repo)?;
        track_value.sentences = query
            .query_map([id.as_str()], |r| {
                Ok(SubtitleSentence {
                    id: SubtitleSentenceId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                    index: r.get(1)?,
                    start: TimeMs::new(r.get(2)?),
                    end: TimeMs::new(r.get(3)?),
                    original_text: r.get(4)?,
                    display_text: r.get(5)?,
                    tokens: from_json(&r.get::<_, String>(6)?)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(track)
    }

    fn list_tracks_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Vec<SubtitleTrack>, ApplicationError> {
        let ids = {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
            let mut query = conn
                .prepare("SELECT id FROM subtitle_tracks WHERE media_id=?1 ORDER BY rowid DESC")
                .map_err(repo)?;
            query
                .query_map([media_id.as_str()], |row| row.get::<_, String>(0))
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        ids.into_iter()
            .map(SubtitleTrackId::parse)
            .map(|id| id.map_err(ApplicationError::from))
            .map(|id| id.and_then(|id| self.get_track(&id)))
            .collect::<Result<Vec<_>, _>>()
            .map(|tracks| tracks.into_iter().flatten().collect())
    }

    fn set_track_status(
        &self,
        id: &SubtitleTrackId,
        status: SubtitleTrackStatus,
    ) -> Result<SubtitleTrack, ApplicationError> {
        let updated = self
            .connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE subtitle_tracks SET status=?2 WHERE id=?1",
                params![id.as_str(), json(&status)?],
            )
            .map_err(repo)?;
        if updated == 0 {
            return Err(ApplicationError::NotFound("subtitle track"));
        }
        self.get_track(id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))
    }

    fn set_track_language(
        &self,
        id: &SubtitleTrackId,
        language: &LanguageCode,
    ) -> Result<SubtitleTrack, ApplicationError> {
        let updated = self
            .connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE subtitle_tracks SET language=?2 WHERE id=?1",
                params![id.as_str(), language.as_str()],
            )
            .map_err(repo)?;
        if updated == 0 {
            return Err(ApplicationError::NotFound("subtitle track"));
        }
        self.get_track(id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))
    }

    fn delete_track(
        &self,
        id: &SubtitleTrackId,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        let existing = self.get_track(id)?;
        if existing.is_none() {
            return Ok(None);
        }
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        // Clear the FTS companion rows before the FK cascade removes the
        // corpus projection rows: coherence must not depend on whether
        // cascade deletes fire the corpus_occurrences triggers.
        tx.execute(
            "DELETE FROM corpus_occurrences_fts WHERE rowid IN
               (SELECT rowid FROM corpus_occurrences WHERE track_id=?1)",
            [id.as_str()],
        )
        .map_err(repo)?;
        tx.execute("DELETE FROM subtitle_tracks WHERE id=?1", [id.as_str()])
            .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(existing)
    }

    fn get_by_media_fingerprint(
        &self,
        media_id: &MediaId,
        fingerprint: &str,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        let id = {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
            conn.query_row(
                "SELECT id FROM subtitle_tracks WHERE media_id=?1 AND fingerprint=?2",
                params![media_id.as_str(), fingerprint],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
        };
        id.map(SubtitleTrackId::parse)
            .transpose()?
            .map(|id| self.get_track(&id))
            .transpose()
            .map(Option::flatten)
    }
    fn get_sentence(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SubtitleSentence>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT id, cue_index, start_ms, end_ms, original_text, display_text, tokens_json
                 FROM subtitle_sentences WHERE id=?1",
                [id.as_str()],
                |row| {
                    Ok(SubtitleSentence {
                        id: SubtitleSentenceId::parse(row.get::<_, String>(0)?)
                            .map_err(domain_sql)?,
                        index: row.get(1)?,
                        start: TimeMs::new(row.get(2)?),
                        end: TimeMs::new(row.get(3)?),
                        original_text: row.get(4)?,
                        display_text: row.get(5)?,
                        tokens: from_json(&row.get::<_, String>(6)?)?,
                    })
                },
            )
            .optional()
            .map_err(repo)
    }

    fn sentence_track_language(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<LanguageCode>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT t.language FROM subtitle_sentences s
                 JOIN subtitle_tracks t ON t.id = s.track_id
                 WHERE s.id = ?1",
                [id.as_str()],
                |row| row.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(repo)?
            .flatten()
            .map(LanguageCode::parse)
            .transpose()
            .map_err(ApplicationError::from)
    }

    fn sentence_track_id(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SubtitleTrackId>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT track_id FROM subtitle_sentences WHERE id = ?1",
                [id.as_str()],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .map(SubtitleTrackId::parse)
            .transpose()
            .map_err(ApplicationError::from)
    }
}
