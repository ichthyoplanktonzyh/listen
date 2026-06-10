use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use application::{
    ApplicationError, DictionaryCacheRepository, MediaRepository, PlaybackProgressRepository,
    SourceContext, SubtitleRepository, VocabularyAssetRepository, WordObservationRepository,
    WordProfileRepository,
};
use domain::*;
use rusqlite::{Connection, OptionalExtension, params};
use sha2::Digest;
use thiserror::Error;

pub const MIGRATION_VERSION: u32 = 5;

pub struct SqliteRepository {
    connection: Mutex<Connection>,
}

impl SqliteRepository {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, PersistenceError> {
        let path = path.as_ref();
        if path.exists() {
            let current: u32 =
                Connection::open(path)?.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            if current < MIGRATION_VERSION {
                fs::copy(path, backup_path(path))?;
            }
        }
        let connection = Connection::open(path)?;
        migrate(&connection)?;
        Ok(Self {
            connection: Mutex::new(connection),
        })
    }

    pub fn in_memory() -> Result<Self, PersistenceError> {
        let connection = Connection::open_in_memory()?;
        migrate(&connection)?;
        Ok(Self {
            connection: Mutex::new(connection),
        })
    }

    pub fn schema_version(&self) -> Result<u32, PersistenceError> {
        Ok(self
            .connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row("PRAGMA user_version", [], |r| r.get(0))?)
    }
}

fn backup_path(path: &Path) -> PathBuf {
    let mut backup = path.as_os_str().to_owned();
    backup.push(".pre-migration.bak");
    PathBuf::from(backup)
}

pub fn migrate(connection: &Connection) -> Result<(), PersistenceError> {
    connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    let current: u32 = connection.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if current < 1 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0001_media.sql"))?;
        tx.pragma_update(None, "user_version", 1)?;
        tx.commit()?;
    }
    if current < 2 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0002_learning.sql"))?;
        tx.pragma_update(None, "user_version", 2)?;
        tx.commit()?;
    }
    if current < 3 {
        connection.execute_batch("PRAGMA foreign_keys = OFF;")?;
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))?;
        tx.pragma_update(None, "user_version", 3)?;
        tx.commit()?;
        connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    }
    if current < 4 {
        connection.execute_batch("PRAGMA foreign_keys = OFF;")?;
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0004_vocabulary_assets.sql"))?;
        tx.pragma_update(None, "user_version", 4)?;
        tx.commit()?;
        connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    }
    if current < 5 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0005_learning_experience.sql"))?;
        tx.pragma_update(None, "user_version", 5)?;
        tx.commit()?;
    }
    Ok(())
}

impl MediaRepository for SqliteRepository {
    fn upsert(&self, media: &MediaItem) -> Result<MediaItem, ApplicationError> {
        {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
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
                "UPDATE word_occurrences SET media_id=?1
                 WHERE media_id IS NULL AND media_fingerprint_snapshot=?2",
                params![media.id.as_str(), media.fingerprint],
            )
            .map_err(repo)?;
            conn.execute(
                "UPDATE word_occurrences
                 SET sentence_id=(
                   SELECT s.id FROM subtitle_sentences s
                   JOIN subtitle_tracks t ON t.id=s.track_id
                   WHERE t.media_id=?1
                     AND s.start_ms=word_occurrences.start_ms_snapshot
                     AND s.end_ms=word_occurrences.end_ms_snapshot
                     AND s.display_text=word_occurrences.sentence_text_snapshot
                   LIMIT 1
                 )
                 WHERE media_id=?1 AND sentence_id IS NULL",
                [media.id.as_str()],
            )
            .map_err(repo)?;
            conn.execute(
                "UPDATE word_observations
                 SET sentence_id=sentence_id_snapshot
                 WHERE sentence_id IS NULL
                   AND EXISTS (
                     SELECT 1 FROM subtitle_sentences s
                     JOIN subtitle_tracks t ON t.id=s.track_id
                     WHERE s.id=word_observations.sentence_id_snapshot AND t.media_id=?1
                   )",
                [media.id.as_str()],
            )
            .map_err(repo)?;
        }
        MediaRepository::get(self, &media.id)?
            .ok_or_else(|| ApplicationError::Repository("media upsert returned no row".into()))
    }

    fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
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

    fn set_availability(
        &self,
        id: &MediaId,
        availability: MediaAvailability,
    ) -> Result<MediaItem, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        tx.execute(
                "UPDATE media_items SET availability=?2, updated_at_ms=unixepoch('subsec') * 1000 WHERE id=?1",
                params![id.as_str(), json(&availability)?],
            )
            .map_err(repo)?;
        if availability != MediaAvailability::Available {
            tx.execute(
                "UPDATE word_observations SET sentence_id=NULL
                 WHERE sentence_id IN (
                   SELECT s.id FROM subtitle_sentences s
                   JOIN subtitle_tracks t ON t.id=s.track_id
                   WHERE t.media_id=?1
                 )",
                [id.as_str()],
            )
            .map_err(repo)?;
            tx.execute(
                "UPDATE word_occurrences SET media_id=NULL, sentence_id=NULL WHERE media_id=?1",
                [id.as_str()],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        MediaRepository::get(self, id)?.ok_or(ApplicationError::NotFound("media"))
    }
}

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

impl WordProfileRepository for SqliteRepository {
    fn upsert(&self, p: &WordProfile) -> Result<WordProfile, ApplicationError> {
        {
            self.connection
                .lock()
                .expect("sqlite mutex poisoned")
                .execute(
                "INSERT INTO word_profiles
                 (id, language, lemma, normalized_lemma, display_form, status, updated_at_ms,
                  user_definition, personal_note, learning_updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
                 ON CONFLICT(language, normalized_lemma) DO UPDATE SET
                   lemma=excluded.lemma, display_form=excluded.display_form,
                   status=excluded.status, updated_at_ms=excluded.updated_at_ms,
                   user_definition=CASE WHEN excluded.learning_updated_at_ms>=learning_updated_at_ms
                     THEN excluded.user_definition ELSE user_definition END,
                   personal_note=CASE WHEN excluded.learning_updated_at_ms>=learning_updated_at_ms
                     THEN excluded.personal_note ELSE personal_note END,
                   learning_updated_at_ms=MAX(learning_updated_at_ms,excluded.learning_updated_at_ms)",
                    params![
                        p.id.as_str(),
                        p.language.as_str(),
                        p.lemma,
                        p.normalized_lemma,
                        p.display_form,
                        p.status.map(|s| json(&s)).transpose()?,
                        p.updated_at_ms,
                        p.user_definition,
                        p.personal_note,
                        p.learning_updated_at_ms
                    ],
                )
                .map_err(repo)?;
        }
        self.get_by_key(&p.language, &p.normalized_lemma)?
            .ok_or_else(|| ApplicationError::Repository("word upsert returned no row".into()))
    }

    fn get_by_key(
        &self,
        language: &LanguageCode,
        normalized_lemma: &str,
    ) -> Result<Option<WordProfile>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT id, language, lemma, normalized_lemma, display_form, status, updated_at_ms,
                        user_definition, personal_note, learning_updated_at_ms
                 FROM word_profiles WHERE language=?1 AND normalized_lemma=?2",
                params![language.as_str(), normalized_lemma],
                |r| {
                    Ok(WordProfile {
                        id: WordProfileId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                        language: LanguageCode::parse(r.get::<_, String>(1)?)
                            .map_err(domain_sql)?,
                        lemma: r.get(2)?,
                        normalized_lemma: r.get(3)?,
                        display_form: r.get(4)?,
                        status: r
                            .get::<_, Option<String>>(5)?
                            .map(|s| from_json(&s))
                            .transpose()?,
                        updated_at_ms: r.get(6)?,
                        user_definition: r.get(7)?,
                        personal_note: r.get(8)?,
                        learning_updated_at_ms: r.get(9)?,
                    })
                },
            )
            .optional()
            .map_err(repo)
    }

    fn get_many(
        &self,
        language: &LanguageCode,
        normalized_lemmas: &[String],
    ) -> Result<Vec<WordProfile>, ApplicationError> {
        if normalized_lemmas.is_empty() {
            return Ok(vec![]);
        }
        let placeholders = std::iter::repeat_n("?", normalized_lemmas.len())
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!(
            "SELECT id, language, lemma, normalized_lemma, display_form, status, updated_at_ms,
                    user_definition, personal_note, learning_updated_at_ms
             FROM word_profiles WHERE language=? AND normalized_lemma IN ({placeholders})"
        );
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn.prepare(&sql).map_err(repo)?;
        let values =
            std::iter::once(language.as_str()).chain(normalized_lemmas.iter().map(String::as_str));
        query
            .query_map(rusqlite::params_from_iter(values), |r| {
                Ok(WordProfile {
                    id: WordProfileId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                    language: LanguageCode::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
                    lemma: r.get(2)?,
                    normalized_lemma: r.get(3)?,
                    display_form: r.get(4)?,
                    status: r
                        .get::<_, Option<String>>(5)?
                        .map(|s| from_json(&s))
                        .transpose()?,
                    updated_at_ms: r.get(6)?,
                    user_definition: r.get(7)?,
                    personal_note: r.get(8)?,
                    learning_updated_at_ms: r.get(9)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
}

impl WordObservationRepository for SqliteRepository {
    fn create(&self, o: &WordObservation) -> Result<WordObservation, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO word_observations
                 (id, word_profile_id, sentence_id, sentence_id_snapshot, original_form, result, created_at_ms, cleared_at_ms)
                 VALUES (?1, ?2, ?3, ?3, ?4, ?5, ?6, NULL)
                 ON CONFLICT(word_profile_id, sentence_id) DO UPDATE SET
                   id=excluded.id, original_form=excluded.original_form, result=excluded.result,
                   created_at_ms=excluded.created_at_ms, cleared_at_ms=NULL",
                params![
                    o.id.as_str(),
                    o.word_profile_id.as_str(),
                    o.sentence_id.as_str(),
                    o.original_form,
                    json(&o.result)?,
                    o.created_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(o.clone())
    }

    fn list_by_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordObservation>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare(
                "SELECT id, word_profile_id, sentence_id, original_form, result, created_at_ms
                 FROM word_observations WHERE sentence_id=?1 AND cleared_at_ms IS NULL ORDER BY created_at_ms",
            )
            .map_err(repo)?;
        query
            .query_map([sentence_id.as_str()], |row| {
                Ok(WordObservation {
                    id: WordObservationId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
                    word_profile_id: WordProfileId::parse(row.get::<_, String>(1)?)
                        .map_err(domain_sql)?,
                    sentence_id: SubtitleSentenceId::parse(row.get::<_, String>(2)?)
                        .map_err(domain_sql)?,
                    original_form: row.get(3)?,
                    result: from_json(&row.get::<_, String>(4)?)?,
                    created_at_ms: row.get(5)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn clear(
        &self,
        word_profile_id: &WordProfileId,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE word_observations SET cleared_at_ms=unixepoch('subsec') * 1000
                 WHERE word_profile_id=?1 AND sentence_id=?2",
                params![word_profile_id.as_str(), sentence_id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }
}

impl SubtitleRepository for SqliteRepository {
    fn save_track(&self, track: &SubtitleTrack) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        tx.execute(
            "INSERT INTO subtitle_tracks(id, media_id, fingerprint, language, source)
             VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(media_id, fingerprint) DO UPDATE SET
               language=excluded.language, source=excluded.source",
            params![
                track.id.as_str(),
                track.media_id.as_str(),
                track.fingerprint,
                track.language.as_ref().map(LanguageCode::as_str),
                track.source
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
                "UPDATE word_occurrences SET sentence_id=?1
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
                "UPDATE word_observations SET sentence_id=?1
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
                "SELECT id, media_id, fingerprint, language, source FROM subtitle_tracks WHERE id=?1",
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
}

impl VocabularyAssetRepository for SqliteRepository {
    fn apply_status(
        &self,
        profile: &WordProfile,
        source: Option<&SourceContext>,
        change_source: WordChangeSource,
    ) -> Result<WordDetails, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let previous = tx
            .query_row(
                "SELECT status FROM word_profiles WHERE language=?1 AND normalized_lemma=?2",
                params![profile.language.as_str(), profile.normalized_lemma],
                |r| r.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(repo)?
            .flatten()
            .map(|value| from_json(&value))
            .transpose()
            .map_err(repo)?;
        tx.execute(
            "INSERT INTO word_profiles
             (id, language, lemma, normalized_lemma, display_form, status, updated_at_ms)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(language, normalized_lemma) DO UPDATE SET
               lemma=excluded.lemma, display_form=excluded.display_form,
               status=excluded.status, updated_at_ms=excluded.updated_at_ms",
            params![
                profile.id.as_str(),
                profile.language.as_str(),
                profile.lemma,
                profile.normalized_lemma,
                profile.display_form,
                profile.status.map(|s| json(&s)).transpose()?,
                profile.updated_at_ms
            ],
        )
        .map_err(repo)?;
        let occurrence_id = source
            .map(|source| upsert_occurrence(&tx, profile, source, profile.updated_at_ms))
            .transpose()?;
        if previous != profile.status {
            let id = WordStatusHistoryId::from_fingerprint(
                "word-status-history",
                &format!(
                    "{}:{}:{previous:?}:{:?}",
                    profile.id.as_str(),
                    profile.updated_at_ms,
                    profile.status
                ),
            );
            tx.execute(
                "INSERT OR IGNORE INTO word_status_history
                 (id, word_profile_id, previous_status, new_status, source_occurrence_id,
                  changed_at_ms, change_source)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    id.as_str(),
                    profile.id.as_str(),
                    previous.map(|s| json(&s)).transpose()?,
                    profile.status.map(|s| json(&s)).transpose()?,
                    occurrence_id.as_ref().map(WordOccurrenceId::as_str),
                    profile.updated_at_ms,
                    json(&change_source)?
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        self.details(&profile.id)?
            .ok_or_else(|| ApplicationError::Repository("word details missing after update".into()))
    }

    fn capture_occurrence(
        &self,
        profile: &WordProfile,
        source: &SourceContext,
    ) -> Result<WordOccurrence, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let id = upsert_occurrence(&conn, profile, source, application::now_ms())?;
        read_occurrence(&conn, &id)?
            .ok_or_else(|| ApplicationError::Repository("occurrence missing after capture".into()))
    }

    fn list_vocabulary(
        &self,
        language: &LanguageCode,
        status: WordStatus,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<WordDetails>, ApplicationError> {
        let ids = {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
            let mut query = conn
                .prepare(
                    "SELECT p.id FROM word_profiles p
                     LEFT JOIN word_occurrences o ON o.word_profile_id=p.id
                     WHERE p.language=?1 AND p.status=?2
                       AND (?3='' OR p.normalized_lemma LIKE '%' || ?3 || '%'
                            OR p.display_form LIKE '%' || ?3 || '%')
                     GROUP BY p.id
                     ORDER BY COALESCE(MAX(o.last_seen_at_ms), p.updated_at_ms) DESC, p.normalized_lemma
                     LIMIT ?4 OFFSET ?5",
                )
                .map_err(repo)?;
            query
                .query_map(
                    params![language.as_str(), json(&status)?, search, limit, offset],
                    |r| r.get::<_, String>(0),
                )
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        ids.into_iter()
            .map(|id| {
                let id = WordProfileId::parse(id)?;
                self.details(&id)?
                    .ok_or_else(|| ApplicationError::Repository("listed word missing".into()))
            })
            .collect()
    }

    fn details(&self, id: &WordProfileId) -> Result<Option<WordDetails>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let Some(profile) = read_profile_by_id(&conn, id)? else {
            return Ok(None);
        };
        Ok(Some(WordDetails {
            profile,
            history: read_history(&conn, id)?,
            occurrences: read_occurrences(&conn, id)?,
        }))
    }

    fn export_assets(&self) -> Result<VocabularyAssetBundle, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        Ok(VocabularyAssetBundle {
            version: 2,
            exported_at_ms: application::now_ms(),
            profiles: read_all_profiles(&conn)?,
            history: read_all_history(&conn)?,
            occurrences: read_all_occurrences(&conn)?,
            observations: read_all_observations(&conn)?,
        })
    }

    fn import_assets(&self, bundle: &VocabularyAssetBundle) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        for profile in &bundle.profiles {
            let previous = tx
                .query_row(
                    "SELECT status,updated_at_ms FROM word_profiles WHERE language=?1 AND normalized_lemma=?2",
                    params![profile.language.as_str(), profile.normalized_lemma],
                    |r| Ok((r.get::<_, Option<String>>(0)?, r.get::<_, u64>(1)?)),
                )
                .optional()
                .map_err(repo)?;
            tx.execute(
                "INSERT INTO word_profiles(id, language, lemma, normalized_lemma, display_form, status,
                  updated_at_ms,user_definition,personal_note,learning_updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
                 ON CONFLICT(language, normalized_lemma) DO UPDATE SET
                   lemma=CASE WHEN excluded.updated_at_ms>updated_at_ms THEN excluded.lemma ELSE lemma END,
                   display_form=CASE WHEN excluded.updated_at_ms>updated_at_ms THEN excluded.display_form ELSE display_form END,
                   status=CASE WHEN excluded.updated_at_ms>updated_at_ms THEN excluded.status ELSE status END,
                   updated_at_ms=MAX(updated_at_ms, excluded.updated_at_ms),
                   user_definition=CASE WHEN excluded.learning_updated_at_ms>learning_updated_at_ms
                     THEN excluded.user_definition ELSE user_definition END,
                   personal_note=CASE WHEN excluded.learning_updated_at_ms>learning_updated_at_ms
                     THEN excluded.personal_note ELSE personal_note END,
                   learning_updated_at_ms=MAX(learning_updated_at_ms,excluded.learning_updated_at_ms)",
                params![profile.id.as_str(), profile.language.as_str(), profile.lemma,
                    profile.normalized_lemma, profile.display_form,
                    profile.status.map(|s| json(&s)).transpose()?, profile.updated_at_ms,
                    profile.user_definition,profile.personal_note,profile.learning_updated_at_ms],
            ).map_err(repo)?;
            let imported_status_json = profile.status.map(|value| json(&value)).transpose()?;
            let import_changes_status = match previous.as_ref() {
                None => profile.status.is_some(),
                Some((status, updated_at_ms)) => {
                    profile.updated_at_ms > *updated_at_ms && status != &imported_status_json
                }
            };
            if import_changes_status {
                let previous_status: Option<WordStatus> = previous
                    .as_ref()
                    .and_then(|(status, _)| status.as_ref())
                    .map(|value| from_json(value))
                    .transpose()
                    .map_err(repo)?;
                let history_id = WordStatusHistoryId::from_fingerprint(
                    "word-status-import",
                    &format!("{}:{}", profile.id.as_str(), bundle.exported_at_ms),
                );
                tx.execute(
                    "INSERT OR IGNORE INTO word_status_history
                     (id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source)
                     VALUES (?1,?2,?3,?4,NULL,?5,?6)",
                    params![
                        history_id.as_str(),
                        profile.id.as_str(),
                        previous_status.map(|s| json(&s)).transpose()?,
                        profile.status.map(|s| json(&s)).transpose()?,
                        bundle.exported_at_ms,
                        json(&WordChangeSource::Import)?
                    ],
                )
                .map_err(repo)?;
            }
        }
        for occurrence in &bundle.occurrences {
            tx.execute(
                "INSERT INTO word_occurrences
                 (id,source_key,word_profile_id,media_id,sentence_id,original_form,sentence_text_snapshot,
                  media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,end_ms_snapshot,
                  first_seen_at_ms,last_seen_at_ms,encounter_count)
                 VALUES (?1,?2,?3,NULL,NULL,?4,?5,?6,?7,?8,?9,?10,?11,?12)
                 ON CONFLICT(word_profile_id,source_key) DO UPDATE SET
                   first_seen_at_ms=MIN(first_seen_at_ms,excluded.first_seen_at_ms),
                   last_seen_at_ms=MAX(last_seen_at_ms,excluded.last_seen_at_ms),
                   encounter_count=MAX(encounter_count,excluded.encounter_count)",
                params![occurrence.id.as_str(), occurrence.source_key, occurrence.word_profile_id.as_str(),
                    occurrence.original_form, occurrence.sentence_text_snapshot, occurrence.media_title_snapshot,
                    occurrence.media_fingerprint_snapshot, occurrence.start_ms_snapshot, occurrence.end_ms_snapshot,
                    occurrence.first_seen_at_ms, occurrence.last_seen_at_ms, occurrence.encounter_count],
            ).map_err(repo)?;
        }
        for history in &bundle.history {
            tx.execute(
                "INSERT OR IGNORE INTO word_status_history
                 (id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)",
                params![history.id.as_str(), history.word_profile_id.as_str(),
                    history.previous_status.map(|s| json(&s)).transpose()?,
                    history.new_status.map(|s| json(&s)).transpose()?,
                    history.source_occurrence_id.as_ref().map(WordOccurrenceId::as_str),
                    history.changed_at_ms, json(&history.change_source)?],
            ).map_err(repo)?;
        }
        for observation in &bundle.observations {
            tx.execute(
                "INSERT OR IGNORE INTO word_observations
                 (id,word_profile_id,sentence_id,sentence_id_snapshot,original_form,result,created_at_ms,cleared_at_ms)
                 VALUES (?1,?2,NULL,?3,?4,?5,?6,NULL)",
                params![
                    observation.id.as_str(),
                    observation.word_profile_id.as_str(),
                    observation.sentence_id.as_str(),
                    observation.original_form,
                    json(&observation.result)?,
                    observation.created_at_ms
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn update_learning_content(
        &self,
        id: &WordProfileId,
        user_definition: Option<String>,
        personal_note: Option<String>,
        updated_at_ms: u64,
    ) -> Result<WordDetails, ApplicationError> {
        let changed = self
            .connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE word_profiles SET user_definition=?2,personal_note=?3,learning_updated_at_ms=?4
                 WHERE id=?1",
                params![id.as_str(), user_definition, personal_note, updated_at_ms],
            )
            .map_err(repo)?;
        if changed == 0 {
            return Err(ApplicationError::NotFound("word profile"));
        }
        self.details(id)?
            .ok_or(ApplicationError::NotFound("word profile"))
    }

    fn import_external(
        &self,
        input: &ExternalVocabularyImport,
        imported_at_ms: u64,
    ) -> Result<ExternalVocabularyImportSummary, ApplicationError> {
        let language = LanguageCode::parse(input.language.clone())?;
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let mut summary = ExternalVocabularyImportSummary::default();
        let mut seen = std::collections::BTreeSet::new();
        for entry in &input.entries {
            let normalized = normalize_lemma(&entry.word);
            if normalized.is_empty() || !seen.insert(normalized.clone()) {
                summary.invalid += 1;
                continue;
            }
            let status = entry.status.or(input.default_status);
            let previous = tx
                .query_row(
                    "SELECT id,status FROM word_profiles WHERE language=?1 AND normalized_lemma=?2",
                    params![language.as_str(), normalized],
                    |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)),
                )
                .optional()
                .map_err(repo)?;
            match previous {
                None => {
                    let id = WordProfileId::from_fingerprint(
                        "word-profile",
                        &format!("{}:{normalized}", language.as_str()),
                    );
                    tx.execute(
                        "INSERT INTO word_profiles
                         (id,language,lemma,normalized_lemma,display_form,status,updated_at_ms,
                          user_definition,personal_note,learning_updated_at_ms)
                         VALUES (?1,?2,?3,?4,?3,?5,?6,NULL,NULL,0)",
                        params![
                            id.as_str(),
                            language.as_str(),
                            entry.word.trim(),
                            normalized,
                            status.map(|value| json(&value)).transpose()?,
                            imported_at_ms
                        ],
                    )
                    .map_err(repo)?;
                    if status.is_some() {
                        insert_import_history(&tx, &id, None, status, imported_at_ms)?;
                    }
                    summary.created += 1;
                }
                Some((id, previous_json)) => {
                    let previous_status = previous_json
                        .as_ref()
                        .map(|value| from_json(value))
                        .transpose()
                        .map_err(repo)?;
                    if previous_status.is_some() && !input.overwrite_existing {
                        summary.skipped += 1;
                        continue;
                    }
                    if previous_status == status {
                        summary.skipped += 1;
                        continue;
                    }
                    tx.execute(
                        "UPDATE word_profiles SET status=?2,updated_at_ms=?3 WHERE id=?1",
                        params![
                            id,
                            status.map(|value| json(&value)).transpose()?,
                            imported_at_ms
                        ],
                    )
                    .map_err(repo)?;
                    let id = WordProfileId::parse(id)?;
                    insert_import_history(&tx, &id, previous_status, status, imported_at_ms)?;
                    if previous_status.is_none() {
                        summary.initialized += 1;
                    } else {
                        summary.overwritten += 1;
                    }
                }
            }
        }
        tx.commit().map_err(repo)?;
        Ok(summary)
    }
}

impl DictionaryCacheRepository for SqliteRepository {
    fn put(&self, e: &DictionaryEntry) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO dictionary_cache
                 (id, language, normalized_lemma, provider, payload_json, cached_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                 ON CONFLICT(language, normalized_lemma, provider) DO UPDATE SET
                   payload_json=excluded.payload_json, cached_at_ms=excluded.cached_at_ms",
                params![
                    e.id.as_str(),
                    e.language.as_str(),
                    e.normalized_lemma,
                    e.provider,
                    e.payload_json,
                    e.cached_at_ms
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get(
        &self,
        language: &LanguageCode,
        normalized_lemma: &str,
        provider: &str,
    ) -> Result<Option<DictionaryEntry>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT id, language, normalized_lemma, provider, payload_json, cached_at_ms
                 FROM dictionary_cache WHERE language=?1 AND normalized_lemma=?2 AND provider=?3",
                params![language.as_str(), normalized_lemma, provider],
                |r| {
                    Ok(DictionaryEntry {
                        id: DictionaryEntryId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                        language: LanguageCode::parse(r.get::<_, String>(1)?)
                            .map_err(domain_sql)?,
                        normalized_lemma: r.get(2)?,
                        provider: r.get(3)?,
                        payload_json: r.get(4)?,
                        cached_at_ms: r.get(5)?,
                    })
                },
            )
            .optional()
            .map_err(repo)
    }
}

fn source_key(source: &SourceContext) -> String {
    hex::encode(sha2::Sha256::digest(format!(
        "{}:{}:{}:{}",
        source.media_fingerprint, source.start_ms, source.end_ms, source.sentence_text
    )))
}

fn insert_import_history(
    conn: &Connection,
    id: &WordProfileId,
    previous_status: Option<WordStatus>,
    new_status: Option<WordStatus>,
    changed_at_ms: u64,
) -> Result<(), ApplicationError> {
    let history_id = WordStatusHistoryId::from_fingerprint(
        "word-status-import",
        &format!("{}:{changed_at_ms}:{new_status:?}", id.as_str()),
    );
    conn.execute(
        "INSERT OR IGNORE INTO word_status_history
         (id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source)
         VALUES (?1,?2,?3,?4,NULL,?5,?6)",
        params![
            history_id.as_str(),
            id.as_str(),
            previous_status.map(|value| json(&value)).transpose()?,
            new_status.map(|value| json(&value)).transpose()?,
            changed_at_ms,
            json(&WordChangeSource::Import)?
        ],
    )
    .map(|_| ())
    .map_err(repo)
}

fn upsert_occurrence(
    conn: &Connection,
    profile: &WordProfile,
    source: &SourceContext,
    now: u64,
) -> Result<WordOccurrenceId, ApplicationError> {
    let key = source_key(source);
    let id = WordOccurrenceId::from_fingerprint(
        "word-occurrence",
        &format!("{}:{key}", profile.id.as_str()),
    );
    conn.execute(
        "INSERT INTO word_occurrences
         (id,source_key,word_profile_id,media_id,sentence_id,original_form,sentence_text_snapshot,
          media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,end_ms_snapshot,
          first_seen_at_ms,last_seen_at_ms,encounter_count)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?12,1)
         ON CONFLICT(word_profile_id,source_key) DO UPDATE SET
           media_id=COALESCE(excluded.media_id,media_id),
           sentence_id=COALESCE(excluded.sentence_id,sentence_id),
           original_form=excluded.original_form,
           sentence_text_snapshot=excluded.sentence_text_snapshot,
           media_title_snapshot=excluded.media_title_snapshot,
           media_fingerprint_snapshot=excluded.media_fingerprint_snapshot,
           last_seen_at_ms=excluded.last_seen_at_ms,
           encounter_count=encounter_count+1",
        params![
            id.as_str(),
            key,
            profile.id.as_str(),
            source.media_id.as_ref().map(MediaId::as_str),
            source.sentence_id.as_ref().map(SubtitleSentenceId::as_str),
            source.original_form,
            source.sentence_text,
            source.media_title,
            source.media_fingerprint,
            source.start_ms,
            source.end_ms,
            now
        ],
    )
    .map_err(repo)?;
    Ok(id)
}

fn read_profile_by_id(
    conn: &Connection,
    id: &WordProfileId,
) -> Result<Option<WordProfile>, ApplicationError> {
    conn.query_row(
        "SELECT id,language,lemma,normalized_lemma,display_form,status,updated_at_ms,
                user_definition,personal_note,learning_updated_at_ms
         FROM word_profiles WHERE id=?1",
        [id.as_str()],
        profile_row,
    )
    .optional()
    .map_err(repo)
}

fn profile_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<WordProfile> {
    Ok(WordProfile {
        id: WordProfileId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
        language: LanguageCode::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
        lemma: r.get(2)?,
        normalized_lemma: r.get(3)?,
        display_form: r.get(4)?,
        status: r
            .get::<_, Option<String>>(5)?
            .map(|s| from_json(&s))
            .transpose()?,
        updated_at_ms: r.get(6)?,
        user_definition: r.get(7)?,
        personal_note: r.get(8)?,
        learning_updated_at_ms: r.get(9)?,
    })
}

fn occurrence_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<WordOccurrence> {
    Ok(WordOccurrence {
        id: WordOccurrenceId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
        source_key: r.get(1)?,
        word_profile_id: WordProfileId::parse(r.get::<_, String>(2)?).map_err(domain_sql)?,
        media_id: r
            .get::<_, Option<String>>(3)?
            .map(MediaId::parse)
            .transpose()
            .map_err(domain_sql)?,
        sentence_id: r
            .get::<_, Option<String>>(4)?
            .map(SubtitleSentenceId::parse)
            .transpose()
            .map_err(domain_sql)?,
        original_form: r.get(5)?,
        sentence_text_snapshot: r.get(6)?,
        media_title_snapshot: r.get(7)?,
        media_fingerprint_snapshot: r.get(8)?,
        start_ms_snapshot: r.get(9)?,
        end_ms_snapshot: r.get(10)?,
        first_seen_at_ms: r.get(11)?,
        last_seen_at_ms: r.get(12)?,
        encounter_count: r.get(13)?,
    })
}

fn read_occurrence(
    conn: &Connection,
    id: &WordOccurrenceId,
) -> Result<Option<WordOccurrence>, ApplicationError> {
    conn.query_row(
        "SELECT id,source_key,word_profile_id,media_id,sentence_id,original_form,
         sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,
         start_ms_snapshot,end_ms_snapshot,first_seen_at_ms,last_seen_at_ms,encounter_count
         FROM word_occurrences WHERE id=?1",
        [id.as_str()],
        occurrence_row,
    )
    .optional()
    .map_err(repo)
}

fn read_occurrences(
    conn: &Connection,
    id: &WordProfileId,
) -> Result<Vec<WordOccurrence>, ApplicationError> {
    let mut q = conn
        .prepare(
            "SELECT id,source_key,word_profile_id,media_id,sentence_id,original_form,
         sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,
         start_ms_snapshot,end_ms_snapshot,first_seen_at_ms,last_seen_at_ms,encounter_count
         FROM word_occurrences WHERE word_profile_id=?1 ORDER BY last_seen_at_ms DESC",
        )
        .map_err(repo)?;
    q.query_map([id.as_str()], occurrence_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

fn history_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<WordStatusHistory> {
    Ok(WordStatusHistory {
        id: WordStatusHistoryId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
        word_profile_id: WordProfileId::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
        previous_status: r
            .get::<_, Option<String>>(2)?
            .map(|s| from_json(&s))
            .transpose()?,
        new_status: r
            .get::<_, Option<String>>(3)?
            .map(|s| from_json(&s))
            .transpose()?,
        source_occurrence_id: r
            .get::<_, Option<String>>(4)?
            .map(WordOccurrenceId::parse)
            .transpose()
            .map_err(domain_sql)?,
        changed_at_ms: r.get(5)?,
        change_source: from_json(&r.get::<_, String>(6)?)?,
    })
}

fn read_history(
    conn: &Connection,
    id: &WordProfileId,
) -> Result<Vec<WordStatusHistory>, ApplicationError> {
    let mut q = conn.prepare(
        "SELECT id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source
         FROM word_status_history WHERE word_profile_id=?1 ORDER BY changed_at_ms DESC",
    ).map_err(repo)?;
    q.query_map([id.as_str()], history_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

fn read_all_profiles(conn: &Connection) -> Result<Vec<WordProfile>, ApplicationError> {
    let mut q = conn.prepare("SELECT id,language,lemma,normalized_lemma,display_form,status,updated_at_ms,user_definition,personal_note,learning_updated_at_ms FROM word_profiles").map_err(repo)?;
    q.query_map([], profile_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}
fn read_all_occurrences(conn: &Connection) -> Result<Vec<WordOccurrence>, ApplicationError> {
    let mut q = conn.prepare("SELECT id,source_key,word_profile_id,media_id,sentence_id,original_form,sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,end_ms_snapshot,first_seen_at_ms,last_seen_at_ms,encounter_count FROM word_occurrences").map_err(repo)?;
    q.query_map([], occurrence_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}
fn read_all_history(conn: &Connection) -> Result<Vec<WordStatusHistory>, ApplicationError> {
    let mut q = conn.prepare("SELECT id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source FROM word_status_history").map_err(repo)?;
    q.query_map([], history_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}
fn read_all_observations(conn: &Connection) -> Result<Vec<WordObservation>, ApplicationError> {
    let mut q = conn.prepare("SELECT id,word_profile_id,COALESCE(sentence_id,sentence_id_snapshot),original_form,result,created_at_ms FROM word_observations WHERE cleared_at_ms IS NULL").map_err(repo)?;
    q.query_map([], |r| {
        Ok(WordObservation {
            id: WordObservationId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
            word_profile_id: WordProfileId::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
            sentence_id: SubtitleSentenceId::parse(r.get::<_, String>(2)?).map_err(domain_sql)?,
            original_form: r.get(3)?,
            result: from_json(&r.get::<_, String>(4)?)?,
            created_at_ms: r.get(5)?,
        })
    })
    .map_err(repo)?
    .collect::<Result<Vec<_>, _>>()
    .map_err(repo)
}

#[derive(Debug, Error)]
pub enum PersistenceError {
    #[error(transparent)]
    Sqlite(#[from] rusqlite::Error),
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

fn json<T: serde::Serialize>(value: &T) -> Result<String, ApplicationError> {
    serde_json::to_string(value).map_err(|e| ApplicationError::Repository(e.to_string()))
}

fn from_json<T: serde::de::DeserializeOwned>(value: &str) -> rusqlite::Result<T> {
    serde_json::from_str(value).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(
            value.len(),
            rusqlite::types::Type::Text,
            Box::new(e),
        )
    })
}

fn domain_sql(error: DomainError) -> rusqlite::Error {
    rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(error))
}

fn repo(error: rusqlite::Error) -> ApplicationError {
    ApplicationError::Repository(error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use application::{
        AppServices, DictionaryProvider, DictionaryProviderError, ImportSubtitle, RegisterMedia,
        UpdateWordProfile,
    };
    use async_trait::async_trait;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct FakeDictionary {
        calls: AtomicUsize,
    }

    struct FailingDictionary;

    #[async_trait]
    impl DictionaryProvider for FakeDictionary {
        fn info(&self) -> DictionaryProviderInfo {
            DictionaryProviderInfo {
                id: "fake".into(),
                display_name: "Fake".into(),
                supported_languages: vec!["en".into()],
                provides_definitions: true,
                provides_phonetics: true,
                provides_audio: false,
                offline: true,
            }
        }

        async fn lookup(
            &self,
            _language: &LanguageCode,
            lemma: &str,
        ) -> Result<Option<DictionaryLookup>, DictionaryProviderError> {
            self.calls.fetch_add(1, Ordering::Relaxed);
            Ok(Some(DictionaryLookup {
                query: lemma.into(),
                lemma: lemma.into(),
                definitions: vec![DictionaryDefinition {
                    part_of_speech: None,
                    text: "definition".into(),
                }],
                phonetics: vec![DictionaryPhonetic {
                    text: "/test/".into(),
                    region: None,
                }],
                provider: self.info().id,
                cached_at_ms: 0,
            }))
        }
    }

    #[async_trait]
    impl DictionaryProvider for FailingDictionary {
        fn info(&self) -> DictionaryProviderInfo {
            DictionaryProviderInfo {
                id: "failing".into(),
                display_name: "Failing".into(),
                supported_languages: vec!["en".into()],
                provides_definitions: true,
                provides_phonetics: false,
                provides_audio: false,
                offline: false,
            }
        }

        async fn lookup(
            &self,
            _language: &LanguageCode,
            _lemma: &str,
        ) -> Result<Option<DictionaryLookup>, DictionaryProviderError> {
            Err(DictionaryProviderError("offline".into()))
        }
    }

    #[test]
    fn new_database_migrates_to_latest() {
        let repo = SqliteRepository::in_memory().unwrap();
        assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
    }

    #[test]
    fn upgrades_historical_v1_database() {
        let connection = Connection::open_in_memory().unwrap();
        connection
            .execute_batch(include_str!("../migrations/0001_media.sql"))
            .unwrap();
        connection.pragma_update(None, "user_version", 1).unwrap();
        migrate(&connection).unwrap();
        let version: u32 = connection
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, MIGRATION_VERSION);
    }

    #[test]
    fn upgrades_historical_v2_database() {
        let connection = Connection::open_in_memory().unwrap();
        connection
            .execute_batch(include_str!("../migrations/0001_media.sql"))
            .unwrap();
        connection
            .execute_batch(include_str!("../migrations/0002_learning.sql"))
            .unwrap();
        connection.pragma_update(None, "user_version", 2).unwrap();
        migrate(&connection).unwrap();
        let version: u32 = connection
            .query_row("PRAGMA user_version", [], |r| r.get(0))
            .unwrap();
        assert_eq!(version, MIGRATION_VERSION);
    }

    #[test]
    fn upgrades_historical_v3_database_and_creates_legacy_history() {
        let connection = Connection::open_in_memory().unwrap();
        connection
            .execute_batch(include_str!("../migrations/0001_media.sql"))
            .unwrap();
        connection
            .execute_batch(include_str!("../migrations/0002_learning.sql"))
            .unwrap();
        connection
            .execute_batch("PRAGMA foreign_keys=OFF;")
            .unwrap();
        connection
            .execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))
            .unwrap();
        connection.pragma_update(None, "user_version", 3).unwrap();
        connection.execute(
            "INSERT INTO word_profiles VALUES ('p','en','hello','hello','Hello','\"known_recognized\"',10)",
            [],
        ).unwrap();
        migrate(&connection).unwrap();
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM word_status_history", [], |r| r
                    .get::<_, u32>(0))
                .unwrap(),
            1
        );
    }

    #[test]
    fn upgrades_historical_v4_database_and_preserves_profiles() {
        let connection = Connection::open_in_memory().unwrap();
        connection
            .execute_batch(include_str!("../migrations/0001_media.sql"))
            .unwrap();
        connection
            .execute_batch(include_str!("../migrations/0002_learning.sql"))
            .unwrap();
        connection
            .execute_batch("PRAGMA foreign_keys=OFF;")
            .unwrap();
        connection
            .execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))
            .unwrap();
        connection
            .execute_batch(include_str!("../migrations/0004_vocabulary_assets.sql"))
            .unwrap();
        connection.pragma_update(None, "user_version", 4).unwrap();
        connection.execute(
            "INSERT INTO word_profiles VALUES ('p','en','hello','hello','Hello','\"known_recognized\"',10)",
            [],
        ).unwrap();
        migrate(&connection).unwrap();
        let values: (String, Option<String>, u64) = connection.query_row(
            "SELECT display_form,user_definition,learning_updated_at_ms FROM word_profiles WHERE id='p'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        ).unwrap();
        assert_eq!(values, ("Hello".into(), None, 0));
    }

    #[test]
    fn services_are_idempotent_and_persist_state() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        );
        let input = RegisterMedia {
            path: "/tmp/a.mp4".into(),
            fingerprint: "same-content".into(),
            title: "A".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        };
        let first = services.register_media(input.clone()).unwrap();
        let second = services.register_media(input).unwrap();
        assert_eq!(first.id, second.id);
        services.update_progress(&first.id, 1250).unwrap();
        assert_eq!(
            services.read_progress(&first.id).unwrap(),
            Some(TimeMs::new(1250))
        );

        let word = services
            .update_word_profile(UpdateWordProfile {
                language: "en".into(),
                lemma: "Hello".into(),
                display_form: "Hello".into(),
                status: Some(WordStatus::KnownRecognized),
                source: None,
            })
            .unwrap();
        assert_eq!(
            services.read_word_profile("EN", "hello").unwrap(),
            Some(word)
        );

        let subtitle = ImportSubtitle {
            media_id: first.id,
            source_name: "timeline.srt".into(),
            content: include_bytes!("../../../testdata/subtitles/timeline.srt").to_vec(),
            language: Some("en".into()),
        };
        let first_track = services.import_subtitle(subtitle.clone()).unwrap();
        let second_track = services.import_subtitle(subtitle).unwrap();
        assert_eq!(first_track.id, second_track.id);
        assert_eq!(
            services.read_subtitle_track(&first_track.id).unwrap(),
            Some(first_track)
        );
    }

    #[test]
    fn subtitle_save_is_transactional_and_round_trips() {
        let repo = SqliteRepository::in_memory().unwrap();
        let media = MediaItem {
            id: MediaId::from_fingerprint("media", "m"),
            path: "/tmp/m.mp4".into(),
            fingerprint: "m".into(),
            title: "m".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        MediaRepository::upsert(&repo, &media).unwrap();
        let track = SubtitleTrack {
            id: SubtitleTrackId::from_fingerprint("track", "t"),
            media_id: media.id,
            fingerprint: "t".into(),
            language: Some(LanguageCode::parse("en").unwrap()),
            source: "external".into(),
            sentences: vec![SubtitleSentence {
                id: SubtitleSentenceId::from_fingerprint("sentence", "s"),
                index: 0,
                start: TimeMs::new(10),
                end: TimeMs::new(20),
                original_text: "Hello".into(),
                display_text: "Hello".into(),
                tokens: vec![],
            }],
        };
        repo.save_track(&track).unwrap();
        assert_eq!(repo.get_track(&track.id).unwrap(), Some(track));
    }

    #[tokio::test]
    async fn dictionary_lookup_uses_persistent_cache() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo,
        );
        let provider: Arc<dyn DictionaryProvider> = Arc::new(FakeDictionary {
            calls: AtomicUsize::new(0),
        });
        let providers = vec![provider.clone()];
        services
            .lookup_dictionary(&providers, "en", "hello")
            .await
            .unwrap();
        services
            .lookup_dictionary(&providers, "en", "hello")
            .await
            .unwrap();
    }

    #[test]
    fn vocabulary_assets_capture_history_sources_and_restore_without_media() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        );
        let media = services
            .register_media(RegisterMedia {
                path: "/tmp/source.mp4".into(),
                fingerprint: "source-media".into(),
                title: "Source".into(),
                kind: MediaKind::Video,
                duration_ms: Some(5000),
            })
            .unwrap();
        let track = services
            .import_subtitle(ImportSubtitle {
                media_id: media.id.clone(),
                source_name: "timeline.srt".into(),
                content: include_bytes!("../../../testdata/subtitles/timeline.srt").to_vec(),
                language: Some("en".into()),
            })
            .unwrap();
        let sentence = &track.sentences[0];
        let source = SourceContext {
            language: LanguageCode::parse("en").unwrap(),
            normalized_lemma: "hello".into(),
            media_id: Some(media.id),
            sentence_id: Some(sentence.id.clone()),
            original_form: "Hello".into(),
            sentence_text: sentence.display_text.clone(),
            media_title: "Source".into(),
            media_fingerprint: "source-media".into(),
            start_ms: sentence.start.get(),
            end_ms: sentence.end.get(),
        };
        let profile = services
            .update_word_profile(UpdateWordProfile {
                language: "en".into(),
                lemma: "hello".into(),
                display_form: "Hello".into(),
                status: Some(WordStatus::UnknownMeaning),
                source: Some(source.clone()),
            })
            .unwrap();
        services
            .update_word_profile(UpdateWordProfile {
                language: "en".into(),
                lemma: "hello".into(),
                display_form: "Hello".into(),
                status: Some(WordStatus::KnownRecognized),
                source: Some(source),
            })
            .unwrap();
        let details = services.word_details(&profile.id).unwrap().unwrap();
        assert_eq!(details.history.len(), 2);
        assert_eq!(details.occurrences[0].encounter_count, 2);

        services
            .create_observation(application::CreateWordObservation {
                word_profile_id: profile.id.clone(),
                sentence_id: sentence.id.clone(),
                original_form: "Hello".into(),
                result: ObservationResult::RecognizedInContext,
                source: None,
            })
            .unwrap();
        services
            .create_observation(application::CreateWordObservation {
                word_profile_id: profile.id.clone(),
                sentence_id: sentence.id.clone(),
                original_form: "Hello".into(),
                result: ObservationResult::NotRecognizedInContext,
                source: None,
            })
            .unwrap();
        assert_eq!(
            repo.list_by_sentence(&sentence.id).unwrap()[0].result,
            ObservationResult::NotRecognizedInContext
        );
        services
            .clear_observation(&profile.id, &sentence.id)
            .unwrap();
        assert!(repo.list_by_sentence(&sentence.id).unwrap().is_empty());

        services
            .set_media_availability(
                &details.occurrences[0].media_id.clone().unwrap(),
                MediaAvailability::Archived,
            )
            .unwrap();
        assert_eq!(
            services
                .word_details(&profile.id)
                .unwrap()
                .unwrap()
                .occurrences[0]
                .media_id,
            None
        );
        services
            .register_media(RegisterMedia {
                path: "/tmp/moved-source.mp4".into(),
                fingerprint: "source-media".into(),
                title: "Source moved".into(),
                kind: MediaKind::Video,
                duration_ms: Some(5000),
            })
            .unwrap();
        let relinked = services.word_details(&profile.id).unwrap().unwrap();
        assert!(relinked.occurrences[0].media_id.is_some());
        assert!(relinked.occurrences[0].sentence_id.is_some());
        services
            .create_observation(application::CreateWordObservation {
                word_profile_id: profile.id.clone(),
                sentence_id: sentence.id.clone(),
                original_form: "Hello".into(),
                result: ObservationResult::RecognizedInContext,
                source: None,
            })
            .unwrap();

        let bundle = services.export_vocabulary().unwrap();
        assert_eq!(bundle.observations.len(), 1);
        let restored = Arc::new(SqliteRepository::in_memory().unwrap());
        let restored_services = AppServices::new(
            restored.clone(),
            restored.clone(),
            restored.clone(),
            restored.clone(),
            restored.clone(),
            restored.clone(),
            restored,
        );
        restored_services.import_vocabulary(&bundle).unwrap();
        let restored_details = restored_services
            .word_details(&profile.id)
            .unwrap()
            .unwrap();
        assert_eq!(
            restored_details.profile.status,
            Some(WordStatus::KnownRecognized)
        );
        assert_eq!(restored_details.occurrences[0].media_id, None);
        assert_eq!(
            restored_services
                .export_vocabulary()
                .unwrap()
                .observations
                .len(),
            1
        );
        restored_services.import_vocabulary(&bundle).unwrap();
        assert_eq!(
            restored_services
                .word_details(&profile.id)
                .unwrap()
                .unwrap()
                .occurrences
                .len(),
            1
        );
    }

    #[test]
    fn vocabulary_query_handles_ten_thousand_profiles_and_fifty_thousand_sources() {
        let repo = SqliteRepository::in_memory().unwrap();
        {
            let mut conn = repo.connection.lock().unwrap();
            let tx = conn.transaction().unwrap();
            for word in 0..10_000 {
                let profile_id = format!("profile-{word}");
                tx.execute(
                    "INSERT INTO word_profiles
                     (id,language,lemma,normalized_lemma,display_form,status,updated_at_ms)
                     VALUES (?1,'en',?2,?2,?2,'\"unknown_meaning\"',?3)",
                    params![profile_id, format!("word-{word:05}"), word],
                )
                .unwrap();
                for source in 0..5 {
                    tx.execute(
                        "INSERT INTO word_occurrences
                         (id,source_key,word_profile_id,original_form,sentence_text_snapshot,
                          media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,
                          end_ms_snapshot,first_seen_at_ms,last_seen_at_ms,encounter_count)
                         VALUES (?1,?2,?3,?4,?5,'Media',?6,?7,?8,?9,?9,1)",
                        params![
                            format!("occurrence-{word}-{source}"),
                            format!("source-{word}-{source}"),
                            profile_id,
                            format!("word-{word:05}"),
                            format!("Sentence containing word-{word:05}"),
                            format!("media-{source}"),
                            source * 1000,
                            source * 1000 + 900,
                            word * 10 + source
                        ],
                    )
                    .unwrap();
                }
            }
            tx.commit().unwrap();
        }
        let started = std::time::Instant::now();
        let values = repo
            .list_vocabulary(
                &LanguageCode::parse("en").unwrap(),
                WordStatus::UnknownMeaning,
                "word-09",
                200,
                0,
            )
            .unwrap();
        assert_eq!(values.len(), 200);
        assert!(
            started.elapsed() < std::time::Duration::from_secs(2),
            "large vocabulary query took {:?}",
            started.elapsed()
        );
    }

    #[test]
    fn failed_source_capture_rolls_back_profile_and_history() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        );
        let result = services.update_word_profile(UpdateWordProfile {
            language: "en".into(),
            lemma: "rollback".into(),
            display_form: "Rollback".into(),
            status: Some(WordStatus::UnknownMeaning),
            source: Some(SourceContext {
                language: LanguageCode::parse("en").unwrap(),
                normalized_lemma: "rollback".into(),
                media_id: Some(MediaId::parse("missing-media").unwrap()),
                sentence_id: None,
                original_form: "Rollback".into(),
                sentence_text: "Rollback this transaction.".into(),
                media_title: "Broken".into(),
                media_fingerprint: "broken".into(),
                start_ms: 10,
                end_ms: 1000,
            }),
        });
        assert!(result.is_err());
        assert!(
            services
                .read_word_profile("en", "rollback")
                .unwrap()
                .is_none()
        );
        assert!(services.export_vocabulary().unwrap().history.is_empty());
    }

    #[test]
    fn external_import_preserves_existing_status_and_updates_learning_content() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo,
        );
        let summary = services
            .import_external_vocabulary(&ExternalVocabularyImport {
                language: "en".into(),
                entries: vec![
                    ExternalVocabularyEntry {
                        word: "Hello".into(),
                        status: None,
                    },
                    ExternalVocabularyEntry {
                        word: "World".into(),
                        status: Some(WordStatus::UnknownMeaning),
                    },
                    ExternalVocabularyEntry {
                        word: "hello".into(),
                        status: None,
                    },
                ],
                default_status: Some(WordStatus::KnownRecognized),
                overwrite_existing: false,
            })
            .unwrap();
        assert_eq!(summary.created, 2);
        assert_eq!(summary.invalid, 1);
        let hello = services.read_word_profile("en", "hello").unwrap().unwrap();
        let details = services
            .update_word_learning_content(
                &hello.id,
                Some(" greeting ".into()),
                Some(" personal ".into()),
            )
            .unwrap();
        assert_eq!(details.profile.user_definition.as_deref(), Some("greeting"));
        assert_eq!(services.export_vocabulary().unwrap().version, 2);
        let second = services
            .import_external_vocabulary(&ExternalVocabularyImport {
                language: "en".into(),
                entries: vec![ExternalVocabularyEntry {
                    word: "hello".into(),
                    status: Some(WordStatus::UnknownMeaning),
                }],
                default_status: None,
                overwrite_existing: false,
            })
            .unwrap();
        assert_eq!(second.skipped, 1);
        assert_eq!(
            services
                .read_word_profile("en", "hello")
                .unwrap()
                .unwrap()
                .status,
            Some(WordStatus::KnownRecognized)
        );
    }

    #[tokio::test]
    async fn dictionary_aggregation_isolates_provider_failure() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo,
        );
        let providers: Vec<Arc<dyn DictionaryProvider>> = vec![
            Arc::new(FailingDictionary),
            Arc::new(FakeDictionary {
                calls: AtomicUsize::new(0),
            }),
        ];
        let bundle = services
            .lookup_dictionary(&providers, "en", "hello")
            .await
            .unwrap();
        assert_eq!(bundle.results.len(), 2);
        assert_eq!(
            bundle.results[0].error.as_deref(),
            Some("dictionary provider failed: offline")
        );
        assert!(bundle.results[1].lookup.is_some());
    }
}
