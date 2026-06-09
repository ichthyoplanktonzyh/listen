use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use application::{
    ApplicationError, DictionaryCacheRepository, MediaRepository, PlaybackProgressRepository,
    SubtitleRepository, WordObservationRepository, WordProfileRepository,
};
use domain::*;
use rusqlite::{Connection, OptionalExtension, params};
use thiserror::Error;

pub const MIGRATION_VERSION: u32 = 3;

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
    Ok(())
}

impl MediaRepository for SqliteRepository {
    fn upsert(&self, media: &MediaItem) -> Result<MediaItem, ApplicationError> {
        {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
            conn.execute(
                "INSERT INTO media_items
                 (id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                 ON CONFLICT(fingerprint) DO UPDATE SET
                   path=excluded.path, title=excluded.title, kind=excluded.kind,
                   duration_ms=excluded.duration_ms, updated_at_ms=excluded.updated_at_ms",
                params![
                    media.id.as_str(),
                    media.path,
                    media.fingerprint,
                    media.title,
                    json(&media.kind)?,
                    media.duration.map(TimeMs::get),
                    media.created_at_ms,
                    media.updated_at_ms
                ],
            )
            .map_err(repo)?;
        }
        MediaRepository::get(self, &media.id)?
            .ok_or_else(|| ApplicationError::Repository("media upsert returned no row".into()))
    }

    fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        conn.query_row(
            "SELECT id, path, fingerprint, title, kind, duration_ms, created_at_ms, updated_at_ms
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
                })
            },
        )
        .optional()
        .map_err(repo)
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
                 (id, language, lemma, normalized_lemma, display_form, status, updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT(language, normalized_lemma) DO UPDATE SET
                   lemma=excluded.lemma, display_form=excluded.display_form,
                   status=excluded.status, updated_at_ms=excluded.updated_at_ms",
                    params![
                        p.id.as_str(),
                        p.language.as_str(),
                        p.lemma,
                        p.normalized_lemma,
                        p.display_form,
                        p.status.map(|s| json(&s)).transpose()?,
                        p.updated_at_ms
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
                "SELECT id, language, lemma, normalized_lemma, display_form, status, updated_at_ms
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
            "SELECT id, language, lemma, normalized_lemma, display_form, status, updated_at_ms
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
                 (id, word_profile_id, sentence_id, original_form, result, created_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
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
                 FROM word_observations WHERE sentence_id=?1 ORDER BY created_at_ms",
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

    #[async_trait]
    impl DictionaryProvider for FakeDictionary {
        fn name(&self) -> &'static str {
            "fake"
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
                provider: self.name().into(),
                cached_at_ms: 0,
            }))
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
    fn services_are_idempotent_and_persist_state() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
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
            repo,
        );
        let provider = FakeDictionary {
            calls: AtomicUsize::new(0),
        };
        services
            .lookup_dictionary(&provider, "en", "hello")
            .await
            .unwrap();
        services
            .lookup_dictionary(&provider, "en", "hello")
            .await
            .unwrap();
        assert_eq!(provider.calls.load(Ordering::Relaxed), 1);
    }
}
