use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use application::{
    ApplicationError, DictionaryCacheRepository, MediaRepository, PhoneticAnalysisRepository,
    PlaybackProgressRepository, SourceContext, SubtitleRepository, TranscriptionRepository,
    VocabularyAssetRepository, WordObservationRepository, WordProfileRepository,
};
use domain::*;
use rusqlite::{Connection, OptionalExtension, params};
use sha2::Digest;
use thiserror::Error;

pub const MIGRATION_VERSION: u32 = 10;
mod lexical;

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
    if current < 6 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0006_transcription.sql"))?;
        tx.pragma_update(None, "user_version", 6)?;
        tx.commit()?;
    }
    if current < 7 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0007_lexical_entries.sql"))?;
        tx.pragma_update(None, "user_version", 7)?;
        tx.commit()?;
    }
    if current < 8 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0008_pronunciation.sql"))?;
        tx.pragma_update(None, "user_version", 8)?;
        tx.commit()?;
    }
    if current < 9 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0009_phonetic_analysis.sql"))?;
        tx.pragma_update(None, "user_version", 9)?;
        tx.commit()?;
    }
    if current < 10 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0010_word_timelines.sql"))?;
        tx.pragma_update(None, "user_version", 10)?;
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

impl TranscriptionRepository for SqliteRepository {
    fn upsert_model(
        &self,
        model: &TranscriptionModelDescriptor,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO transcription_models(id,provider_id,descriptor_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4)
                 ON CONFLICT(id) DO UPDATE SET provider_id=excluded.provider_id,
                   descriptor_json=excluded.descriptor_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    model.id.as_str(),
                    model.provider_id,
                    json(model)?,
                    model.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(model.clone())
    }

    fn list_models(&self) -> Result<Vec<TranscriptionModelDescriptor>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare("SELECT descriptor_json FROM transcription_models ORDER BY provider_id,id")
            .map_err(repo)?;
        query
            .query_map([], |row| {
                from_json::<TranscriptionModelDescriptor>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_model(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<Option<TranscriptionModelDescriptor>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT descriptor_json FROM transcription_models WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn delete_model(&self, id: &TranscriptionModelId) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "DELETE FROM transcription_models WHERE id=?1",
                [id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn create_job(&self, job: &TranscriptionJob) -> Result<TranscriptionJob, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO transcription_jobs(id,media_id,input_fingerprint,status,job_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6)",
                params![
                    job.id.as_str(),
                    job.media_id.as_str(),
                    job.input_fingerprint,
                    json(&job.status)?,
                    json(job)?,
                    job.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(job.clone())
    }

    fn update_job(&self, job: &TranscriptionJob) -> Result<TranscriptionJob, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE transcription_jobs SET status=?2,job_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![
                    job.id.as_str(),
                    json(&job.status)?,
                    json(job)?,
                    job.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(job.clone())
    }

    fn get_job(
        &self,
        id: &TranscriptionJobId,
    ) -> Result<Option<TranscriptionJob>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT job_json FROM transcription_jobs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_jobs(&self) -> Result<Vec<TranscriptionJob>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare("SELECT job_json FROM transcription_jobs ORDER BY updated_at_ms DESC")
            .map_err(repo)?;
        query
            .query_map([], |row| {
                from_json::<TranscriptionJob>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map(|jobs| {
                jobs.into_iter()
                    .filter(|job| job.archived_at_ms.is_none())
                    .collect()
            })
            .map_err(repo)
    }

    fn find_completed_job(
        &self,
        input_fingerprint: &str,
    ) -> Result<Option<TranscriptionJob>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT job_json FROM transcription_jobs
                 WHERE input_fingerprint=?1 AND status='\"completed\"'
                 ORDER BY updated_at_ms DESC LIMIT 1",
                [input_fingerprint],
                |row| from_json::<TranscriptionJob>(&row.get::<_, String>(0)?),
            )
            .optional()
            .map(|job| job.filter(|job| job.archived_at_ms.is_none()))
            .map_err(repo)
    }

    fn interrupt_active_jobs(&self, updated_at_ms: u64) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let mut query = tx
            .prepare(
                "SELECT id,job_json FROM transcription_jobs
                 WHERE status IN ('\"queued\"','\"extracting\"','\"transcribing\"','\"importing\"')",
            )
            .map_err(repo)?;
        let jobs = query
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    from_json(&row.get::<_, String>(1)?)?,
                ))
            })
            .map_err(repo)?
            .collect::<Result<Vec<(String, TranscriptionJob)>, _>>()
            .map_err(repo)?;
        drop(query);
        for (id, mut job) in jobs {
            job.status = TranscriptionJobStatus::Failed;
            job.error_code = Some("interrupted".into());
            job.error_message = Some("The local service stopped before this job completed.".into());
            job.completed_at_ms = Some(updated_at_ms);
            job.updated_at_ms = updated_at_ms;
            tx.execute(
                "UPDATE transcription_jobs SET status=?2,job_json=?3,updated_at_ms=?4 WHERE id=?1",
                params![id, json(&job.status)?, json(&job)?, updated_at_ms],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn save_provenance(
        &self,
        provenance: &SubtitleTrackProvenance,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO subtitle_track_provenance(track_id,transcription_job_id,provenance_json)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(track_id) DO UPDATE SET provenance_json=excluded.provenance_json",
                params![
                    provenance.track_id.as_str(),
                    provenance.transcription_job_id.as_str(),
                    json(provenance)?
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }
}

impl PhoneticAnalysisRepository for SqliteRepository {
    fn upsert_phonetic_model(
        &self,
        model: &PhoneticAnalysisModelDescriptor,
    ) -> Result<PhoneticAnalysisModelDescriptor, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO phonetic_analysis_models(id,provider_id,descriptor_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4)
                 ON CONFLICT(id) DO UPDATE SET provider_id=excluded.provider_id,
                   descriptor_json=excluded.descriptor_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    model.id.as_str(),
                    model.provider_id,
                    json(model)?,
                    model.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(model.clone())
    }

    fn list_phonetic_models(
        &self,
    ) -> Result<Vec<PhoneticAnalysisModelDescriptor>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare("SELECT descriptor_json FROM phonetic_analysis_models ORDER BY provider_id,id")
            .map_err(repo)?;
        query
            .query_map([], |row| from_json(&row.get::<_, String>(0)?))
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_phonetic_model(
        &self,
        id: &PhoneticAnalysisModelId,
    ) -> Result<Option<PhoneticAnalysisModelDescriptor>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT descriptor_json FROM phonetic_analysis_models WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn delete_phonetic_model(&self, id: &PhoneticAnalysisModelId) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "DELETE FROM phonetic_analysis_models WHERE id=?1",
                [id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn create_phonetic_job(
        &self,
        job: &PhoneticAnalysisJob,
    ) -> Result<PhoneticAnalysisJob, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO phonetic_analysis_jobs
                 (id,media_id,track_id,sentence_id,input_fingerprint,status,job_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
                params![
                    job.id.as_str(),
                    job.media_id.as_str(),
                    job.track_id.as_str(),
                    job.sentence_id.as_ref().map(SubtitleSentenceId::as_str),
                    job.input_fingerprint,
                    json(&job.status)?,
                    json(job)?,
                    job.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(job.clone())
    }

    fn update_phonetic_job(
        &self,
        job: &PhoneticAnalysisJob,
    ) -> Result<PhoneticAnalysisJob, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE phonetic_analysis_jobs SET status=?2,job_json=?3,updated_at_ms=?4
                 WHERE id=?1",
                params![
                    job.id.as_str(),
                    json(&job.status)?,
                    json(job)?,
                    job.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(job.clone())
    }

    fn get_phonetic_job(
        &self,
        id: &PhoneticAnalysisJobId,
    ) -> Result<Option<PhoneticAnalysisJob>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT job_json FROM phonetic_analysis_jobs WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_phonetic_jobs(&self) -> Result<Vec<PhoneticAnalysisJob>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare("SELECT job_json FROM phonetic_analysis_jobs ORDER BY updated_at_ms DESC")
            .map_err(repo)?;
        query
            .query_map([], |row| from_json(&row.get::<_, String>(0)?))
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn find_completed_phonetic_job(
        &self,
        input_fingerprint: &str,
    ) -> Result<Option<PhoneticAnalysisJob>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT job_json FROM phonetic_analysis_jobs
                 WHERE input_fingerprint=?1 AND status='\"completed\"'
                 ORDER BY updated_at_ms DESC LIMIT 1",
                [input_fingerprint],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn interrupt_active_phonetic_jobs(&self, updated_at_ms: u64) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let active = [
            PhoneticAnalysisJobStatus::Queued,
            PhoneticAnalysisJobStatus::Extracting,
            PhoneticAnalysisJobStatus::RecognizingPhones,
            PhoneticAnalysisJobStatus::Aligning,
            PhoneticAnalysisJobStatus::Analyzing,
        ]
        .into_iter()
        .map(|status| json(&status))
        .collect::<Result<Vec<_>, _>>()?;
        let mut query = tx
            .prepare(
                "SELECT id,job_json FROM phonetic_analysis_jobs
                 WHERE status IN (?1,?2,?3,?4,?5)",
            )
            .map_err(repo)?;
        let jobs = query
            .query_map(
                params![active[0], active[1], active[2], active[3], active[4]],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        from_json(&row.get::<_, String>(1)?)?,
                    ))
                },
            )
            .map_err(repo)?
            .collect::<Result<Vec<(String, PhoneticAnalysisJob)>, _>>()
            .map_err(repo)?;
        drop(query);
        for (id, mut job) in jobs {
            job.status = PhoneticAnalysisJobStatus::Interrupted;
            job.error_code = Some("interrupted".into());
            job.error_message =
                Some("The local service stopped before this analysis completed.".into());
            job.completed_at_ms = Some(updated_at_ms);
            job.updated_at_ms = updated_at_ms;
            tx.execute(
                "UPDATE phonetic_analysis_jobs SET status=?2,job_json=?3,updated_at_ms=?4
                 WHERE id=?1",
                params![id, json(&job.status)?, json(&job)?, updated_at_ms],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn save_phonetic_analysis(
        &self,
        analysis: &PhoneticAnalysis,
    ) -> Result<PhoneticAnalysis, ApplicationError> {
        analysis.validate().map_err(ApplicationError::from)?;
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO phonetic_analyses
                 (id,job_id,media_id,track_id,sentence_id,provider_id,model_id,analysis_json,created_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
                params![
                    analysis.id.as_str(),
                    analysis.job_id.as_str(),
                    analysis.media_id.as_str(),
                    analysis.track_id.as_str(),
                    analysis.sentence_id.as_ref().map(SubtitleSentenceId::as_str),
                    analysis.provider_id,
                    analysis.model_id.as_str(),
                    json(analysis)?,
                    analysis.created_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(analysis.clone())
    }

    fn get_phonetic_analysis(
        &self,
        id: &PhoneticAnalysisId,
    ) -> Result<Option<PhoneticAnalysis>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT analysis_json FROM phonetic_analyses WHERE id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn list_track_phonetic_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneticAnalysis>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare(
                "SELECT analysis_json FROM phonetic_analyses
                 WHERE track_id=?1 ORDER BY created_at_ms DESC,rowid DESC",
            )
            .map_err(repo)?;
        query
            .query_map([track_id.as_str()], |row| {
                from_json(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn save_phonetic_feedback(
        &self,
        feedback: &PhoneticFindingFeedback,
    ) -> Result<PhoneticFindingFeedback, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO phonetic_finding_feedback(finding_id,feedback_json,updated_at_ms)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(finding_id) DO UPDATE SET
                   feedback_json=excluded.feedback_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    feedback.finding_id.as_str(),
                    json(feedback)?,
                    feedback.updated_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(feedback.clone())
    }

    fn get_phonetic_feedback(
        &self,
        finding_id: &PhoneticFindingId,
    ) -> Result<Option<PhoneticFindingFeedback>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT feedback_json FROM phonetic_finding_feedback WHERE finding_id=?1",
                [finding_id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
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

    fn save_pronunciation(&self, analysis: &SentencePronunciation) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO pronunciation_analysis
                 (sentence_id,provider_id,provider_version,analysis_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,unixepoch('subsec') * 1000)
                 ON CONFLICT(sentence_id) DO UPDATE SET
                   provider_id=excluded.provider_id,provider_version=excluded.provider_version,
                   analysis_json=excluded.analysis_json,updated_at_ms=excluded.updated_at_ms",
                params![
                    analysis.sentence_id.as_str(),
                    analysis.provider_id,
                    analysis.provider_version,
                    json(analysis)?
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn save_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        pronunciation: &WordPronunciation,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO pronunciation_cache
                 (language,accent,normalized_text,provider_id,provider_version,
                  pronunciation_json,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,unixepoch('subsec') * 1000)
                 ON CONFLICT(language,accent,normalized_text,provider_id,provider_version)
                 DO UPDATE SET pronunciation_json=excluded.pronunciation_json,
                   updated_at_ms=excluded.updated_at_ms",
                params![
                    language,
                    accent,
                    pronunciation.normalized,
                    provider_id,
                    provider_version,
                    json(pronunciation)?,
                ],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn get_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        normalized_text: &str,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<Option<WordPronunciation>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT pronunciation_json FROM pronunciation_cache
                 WHERE language=?1 AND accent=?2 AND normalized_text=?3
                   AND provider_id=?4 AND provider_version=?5",
                params![
                    language,
                    accent,
                    normalized_text,
                    provider_id,
                    provider_version
                ],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

    fn get_pronunciation(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SentencePronunciation>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT analysis_json FROM pronunciation_analysis WHERE sentence_id=?1",
                [id.as_str()],
                |row| from_json(&row.get::<_, String>(0)?),
            )
            .optional()
            .map_err(repo)
    }

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
            .expect("sqlite mutex poisoned")
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
            .expect("sqlite mutex poisoned")
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
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
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
            .map_err(repo)?;
        Ok(timeline.clone())
    }

    fn list_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimeline>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
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
            .expect("sqlite mutex poisoned")
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
            .expect("sqlite mutex poisoned")
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
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
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
        tx.execute(
            "DELETE FROM word_timings
             WHERE sentence_id IN (
               SELECT id FROM subtitle_sentences WHERE track_id=?1
             )",
            [selected.track_id.as_str()],
        )
        .map_err(repo)?;
        let mut grouped = std::collections::HashMap::<SubtitleSentenceId, Vec<WordTiming>>::new();
        for word in &selected.words {
            grouped
                .entry(word.sentence_id.clone())
                .or_default()
                .push(word.clone());
        }
        for (sentence_id, mut timings) in grouped {
            timings.sort_by_key(|value| (value.start_ms, value.end_ms, value.token_index));
            if let Some(first) = timings.first() {
                tx.execute(
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
                        now
                    ],
                )
                .map_err(repo)?;
            }
        }
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
                .expect("sqlite mutex poisoned")
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
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
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
        let (lexical_entries, lexical_history, lexical_occurrences) =
            self.export_lexical_assets()?;
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        Ok(VocabularyAssetBundle {
            version: 4,
            exported_at_ms: application::now_ms(),
            profiles: read_all_profiles(&conn)?,
            history: read_all_history(&conn)?,
            occurrences: read_all_occurrences(&conn)?,
            observations: read_all_observations(&conn)?,
            lexical_entries,
            lexical_history,
            lexical_occurrences,
            phonetic_finding_feedback: read_all_phonetic_feedback(&conn)?,
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
        for feedback in &bundle.phonetic_finding_feedback {
            tx.execute(
                "INSERT INTO phonetic_finding_feedback(finding_id,feedback_json,updated_at_ms)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(finding_id) DO UPDATE SET
                   feedback_json=CASE
                     WHEN excluded.updated_at_ms>updated_at_ms THEN excluded.feedback_json
                     ELSE feedback_json END,
                   updated_at_ms=MAX(updated_at_ms,excluded.updated_at_ms)",
                params![
                    feedback.finding_id.as_str(),
                    json(feedback)?,
                    feedback.updated_at_ms
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        self.import_lexical_assets(
            &bundle.lexical_entries,
            &bundle.lexical_history,
            &bundle.lexical_occurrences,
        )
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

fn read_all_phonetic_feedback(
    conn: &Connection,
) -> Result<Vec<PhoneticFindingFeedback>, ApplicationError> {
    let mut query = conn
        .prepare(
            "SELECT feedback_json FROM phonetic_finding_feedback ORDER BY updated_at_ms,finding_id",
        )
        .map_err(repo)?;
    query
        .query_map([], |row| from_json(&row.get::<_, String>(0)?))
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
        AppServices, DictionaryProvider, DictionaryProviderError, ImportSubtitle,
        LexicalEntryRepository, RegisterMedia, UpdateWordProfile, UpsertLexicalEntry,
    };
    use async_trait::async_trait;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct FakeDictionary {
        calls: AtomicUsize,
    }

    struct FailingDictionary;

    fn transcription_job(
        id: &str,
        input_fingerprint: &str,
        status: TranscriptionJobStatus,
        updated_at_ms: u64,
    ) -> TranscriptionJob {
        TranscriptionJob {
            id: TranscriptionJobId::parse(id).unwrap(),
            media_id: MediaId::parse("media-1").unwrap(),
            media_title: "Media".into(),
            media_fingerprint: "media-fp".into(),
            provider_id: "test-provider".into(),
            provider_version: "v1".into(),
            runtime_id: "test-runtime".into(),
            runtime_version: "v1".into(),
            model_id: TranscriptionModelId::parse("model-1").unwrap(),
            model_revision: "rev-1".into(),
            model_checksum_sha256: "checksum".into(),
            destination: TranscriptionDestination::Primary,
            purpose: TranscriptionPurpose::Transcribe,
            requested_language: Some("en".into()),
            detected_language: Some("en".into()),
            audio_track: None,
            settings_json: "{}".into(),
            input_fingerprint: input_fingerprint.into(),
            status,
            phase_progress: 100,
            error_code: None,
            error_message: None,
            retry_of_job_id: None,
            generated_track_id: Some(SubtitleTrackId::parse("track-1").unwrap()),
            created_at_ms: 1,
            started_at_ms: Some(2),
            completed_at_ms: Some(3),
            updated_at_ms,
            archived_at_ms: None,
        }
    }

    fn transcription_media() -> MediaItem {
        MediaItem {
            id: MediaId::parse("media-1").unwrap(),
            path: "/tmp/media.mp4".into(),
            fingerprint: "media-fp".into(),
            title: "Media".into(),
            kind: MediaKind::Video,
            duration: Some(TimeMs::new(1_000)),
            availability: MediaAvailability::Available,
            created_at_ms: 1,
            updated_at_ms: 1,
        }
    }

    fn word_timeline_track() -> SubtitleTrack {
        let media_id = MediaId::parse("media-1").unwrap();
        SubtitleTrack {
            id: SubtitleTrackId::parse("track-1").unwrap(),
            media_id,
            fingerprint: "track-fp".into(),
            language: Some(LanguageCode::parse("en").unwrap()),
            source: "test".into(),
            sentences: vec![SubtitleSentence {
                id: SubtitleSentenceId::parse("sentence-1").unwrap(),
                index: 0,
                start: TimeMs::new(100),
                end: TimeMs::new(800),
                original_text: "hello".into(),
                display_text: "hello".into(),
                tokens: vec![SubtitleToken {
                    index: 0,
                    kind: SubtitleTokenKind::Word,
                    text: "hello".into(),
                    normalized: Some("hello".into()),
                    start_char: 0,
                    end_char: 5,
                }],
            }],
        }
    }

    fn word_timeline(
        id: &str,
        track: &SubtitleTrack,
        status: TimelineStatus,
        provider_id: &str,
        start_ms: u64,
        end_ms: u64,
    ) -> WordTimeline {
        let sentence_id = track.sentences[0].id.clone();
        WordTimeline {
            id: WordTimelineId::parse(id).unwrap(),
            track_id: track.id.clone(),
            media_id: track.media_id.clone(),
            algorithm_id: provider_id.into(),
            algorithm_version: "v1".into(),
            config_hash: format!("{provider_id}-config"),
            parent_timeline_id: None,
            created_by: TimelineCreator::Algorithm,
            status,
            metrics_json: serde_json::json!({}),
            words: vec![WordTiming {
                sentence_id,
                token_index: 0,
                text: "hello".into(),
                start_ms,
                end_ms,
                confidence: Some(0.9),
                timing_source: TimingSource::ForcedAligned,
                provider_id: provider_id.into(),
                provider_version: "v1".into(),
            }],
            created_at_ms: start_ms,
            updated_at_ms: start_ms,
        }
    }

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
                    audio_url: None,
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
    fn pronunciation_cache_isolated_by_provider_version() {
        let repo = SqliteRepository::in_memory().unwrap();
        let pronunciation = WordPronunciation {
            token_index: 0,
            text: "Hello".into(),
            normalized: "hello".into(),
            variants: vec![],
        };
        repo.save_word_pronunciation("en", "en-US", &pronunciation, "provider", "v1")
            .unwrap();

        assert!(
            repo.get_word_pronunciation("en", "en-US", "hello", "provider", "v1")
                .unwrap()
                .is_some()
        );
        assert!(
            repo.get_word_pronunciation("en", "en-US", "hello", "provider", "v2")
                .unwrap()
                .is_none()
        );
        assert!(
            repo.get_word_pronunciation("en", "en-GB", "hello", "provider", "v1")
                .unwrap()
                .is_none()
        );
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
    fn upgrades_historical_v5_database_and_adds_transcription_assets() {
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
        connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        connection
            .execute_batch(include_str!("../migrations/0005_learning_experience.sql"))
            .unwrap();
        connection.pragma_update(None, "user_version", 5).unwrap();
        migrate(&connection).unwrap();
        assert_eq!(
            connection
                .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
                .unwrap(),
            MIGRATION_VERSION
        );
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM transcription_jobs", [], |row| row
                    .get::<_, u32>(0))
                .unwrap(),
            0
        );
    }

    #[test]
    fn archived_transcription_jobs_are_hidden_from_list_and_reuse() {
        let repo = SqliteRepository::in_memory().unwrap();
        MediaRepository::upsert(&repo, &transcription_media()).unwrap();
        let mut job =
            transcription_job("job-1", "same-input", TranscriptionJobStatus::Completed, 10);
        repo.create_job(&job).unwrap();

        assert_eq!(repo.list_jobs().unwrap().len(), 1);
        assert_eq!(
            repo.find_completed_job("same-input")
                .unwrap()
                .expect("completed job should be reusable")
                .id,
            job.id
        );

        job.archived_at_ms = Some(20);
        job.updated_at_ms = 20;
        repo.update_job(&job).unwrap();

        assert!(repo.list_jobs().unwrap().is_empty());
        assert!(repo.find_completed_job("same-input").unwrap().is_none());
        assert_eq!(
            repo.get_job(&job.id)
                .unwrap()
                .expect("archive should not delete job")
                .archived_at_ms,
            Some(20)
        );
    }

    #[test]
    fn activating_word_timeline_updates_active_resource_and_compatibility_timings() {
        let repo = SqliteRepository::in_memory().unwrap();
        MediaRepository::upsert(&repo, &transcription_media()).unwrap();
        let track = word_timeline_track();
        let sentence_id = track.sentences[0].id.clone();
        repo.save_track(&track).unwrap();
        let older = word_timeline(
            "timeline-1",
            &track,
            TimelineStatus::Active,
            "whisper-dtw",
            120,
            300,
        );
        let newer = word_timeline(
            "timeline-2",
            &track,
            TimelineStatus::Candidate,
            "mms-fa",
            150,
            260,
        );
        repo.save_word_timeline(&older).unwrap();
        repo.save_word_timeline(&newer).unwrap();

        let active = repo.activate_word_timeline(&newer.id).unwrap();
        assert_eq!(active.status, TimelineStatus::Active);
        assert_eq!(
            repo.active_word_timeline(&track.id).unwrap().unwrap().id,
            newer.id
        );
        assert_eq!(
            repo.get_word_timeline(&older.id).unwrap().unwrap().status,
            TimelineStatus::Candidate
        );

        let compatibility_timings = repo.get_word_timings(&sentence_id).unwrap();
        assert_eq!(compatibility_timings.len(), 1);
        assert_eq!(compatibility_timings[0].provider_id, "mms-fa");
        assert_eq!(compatibility_timings[0].start_ms, 150);
        assert_eq!(compatibility_timings[0].end_ms, 260);
    }

    #[test]
    fn archiving_active_word_timeline_clears_compatibility_timings() {
        let repo = SqliteRepository::in_memory().unwrap();
        MediaRepository::upsert(&repo, &transcription_media()).unwrap();
        let track = word_timeline_track();
        let sentence_id = track.sentences[0].id.clone();
        repo.save_track(&track).unwrap();
        let timeline = word_timeline(
            "timeline-archive-active",
            &track,
            TimelineStatus::Active,
            "mms-fa",
            150,
            260,
        );
        repo.save_word_timeline(&timeline).unwrap();
        repo.activate_word_timeline(&timeline.id).unwrap();

        let archived = repo.archive_word_timeline(&timeline.id).unwrap();
        assert_eq!(archived.status, TimelineStatus::Archived);
        assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
        assert!(repo.get_word_timings(&sentence_id).unwrap().is_empty());
    }

    #[test]
    fn deleting_active_word_timeline_clears_compatibility_timings() {
        let repo = SqliteRepository::in_memory().unwrap();
        MediaRepository::upsert(&repo, &transcription_media()).unwrap();
        let track = word_timeline_track();
        let sentence_id = track.sentences[0].id.clone();
        repo.save_track(&track).unwrap();
        let timeline = word_timeline(
            "timeline-delete-active",
            &track,
            TimelineStatus::Active,
            "mms-fa",
            150,
            260,
        );
        repo.save_word_timeline(&timeline).unwrap();
        repo.activate_word_timeline(&timeline.id).unwrap();

        let deleted = repo.delete_word_timeline(&timeline.id).unwrap();
        assert_eq!(deleted.id, timeline.id);
        assert!(repo.get_word_timeline(&timeline.id).unwrap().is_none());
        assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
        assert!(repo.get_word_timings(&sentence_id).unwrap().is_empty());
    }

    #[test]
    fn upgrades_historical_v6_database_and_migrates_words_to_lexical_entries() {
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
        connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        connection
            .execute_batch(include_str!("../migrations/0005_learning_experience.sql"))
            .unwrap();
        connection
            .execute_batch(include_str!("../migrations/0006_transcription.sql"))
            .unwrap();
        connection.pragma_update(None, "user_version", 6).unwrap();
        connection
            .execute(
                "INSERT INTO word_profiles
             (id,language,lemma,normalized_lemma,display_form,status,updated_at_ms,
              user_definition,personal_note,learning_updated_at_ms)
             VALUES ('legacy','en','went','went','Went','\"known_not_recognized\"',10,
                     'past tense','from a lesson',11)",
                [],
            )
            .unwrap();
        migrate(&connection).unwrap();
        let value: (String, String, Option<String>, Option<String>) = connection
            .query_row(
                "SELECT kind,display_form,user_definition,personal_note
                 FROM lexical_entries WHERE id='legacy'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();
        assert_eq!(
            value,
            (
                "\"word\"".into(),
                "Went".into(),
                Some("past tense".into()),
                Some("from a lesson".into())
            )
        );
    }

    #[test]
    fn upgrades_historical_v7_database_and_preserves_lexical_assets() {
        let connection = Connection::open_in_memory().unwrap();
        for migration in [
            include_str!("../migrations/0001_media.sql"),
            include_str!("../migrations/0002_learning.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection
            .execute_batch("PRAGMA foreign_keys=OFF;")
            .unwrap();
        for migration in [
            include_str!("../migrations/0003_subtitle_identity.sql"),
            include_str!("../migrations/0004_vocabulary_assets.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        for migration in [
            include_str!("../migrations/0005_learning_experience.sql"),
            include_str!("../migrations/0006_transcription.sql"),
            include_str!("../migrations/0007_lexical_entries.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection.pragma_update(None, "user_version", 7).unwrap();
        connection
            .execute(
                "INSERT INTO lexical_entries
                 (id,language,kind,canonical_form,normalized_form,display_form,status,
                  normalization_provider,normalization_version,user_corrected,updated_at_ms,
                  learning_updated_at_ms)
                 VALUES ('asset','en','\"word\"','hello','hello','Hello','\"known_recognized\"',
                         'legacy','v1',0,10,0)",
                [],
            )
            .unwrap();
        migrate(&connection).unwrap();
        assert_eq!(
            connection
                .query_row(
                    "SELECT display_form FROM lexical_entries WHERE id='asset'",
                    [],
                    |row| { row.get::<_, String>(0) }
                )
                .unwrap(),
            "Hello"
        );
        assert_eq!(
            connection
                .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
                .unwrap(),
            MIGRATION_VERSION
        );
    }

    #[test]
    fn upgrades_historical_v8_database_and_adds_phonetic_analysis_assets() {
        let connection = Connection::open_in_memory().unwrap();
        for migration in [
            include_str!("../migrations/0001_media.sql"),
            include_str!("../migrations/0002_learning.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection
            .execute_batch("PRAGMA foreign_keys=OFF;")
            .unwrap();
        for migration in [
            include_str!("../migrations/0003_subtitle_identity.sql"),
            include_str!("../migrations/0004_vocabulary_assets.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        for migration in [
            include_str!("../migrations/0005_learning_experience.sql"),
            include_str!("../migrations/0006_transcription.sql"),
            include_str!("../migrations/0007_lexical_entries.sql"),
            include_str!("../migrations/0008_pronunciation.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection.pragma_update(None, "user_version", 8).unwrap();

        migrate(&connection).unwrap();

        assert_eq!(
            connection
                .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
                .unwrap(),
            MIGRATION_VERSION
        );
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM phonetic_analysis_jobs", [], |row| {
                    row.get::<_, u32>(0)
                })
                .unwrap(),
            0
        );
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM phonetic_analyses", [], |row| {
                    row.get::<_, u32>(0)
                })
                .unwrap(),
            0
        );
    }

    #[test]
    fn upgrades_historical_v9_database_and_adds_word_timeline_assets() {
        let connection = Connection::open_in_memory().unwrap();
        for migration in [
            include_str!("../migrations/0001_media.sql"),
            include_str!("../migrations/0002_learning.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection
            .execute_batch("PRAGMA foreign_keys=OFF;")
            .unwrap();
        for migration in [
            include_str!("../migrations/0003_subtitle_identity.sql"),
            include_str!("../migrations/0004_vocabulary_assets.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        for migration in [
            include_str!("../migrations/0005_learning_experience.sql"),
            include_str!("../migrations/0006_transcription.sql"),
            include_str!("../migrations/0007_lexical_entries.sql"),
            include_str!("../migrations/0008_pronunciation.sql"),
            include_str!("../migrations/0009_phonetic_analysis.sql"),
        ] {
            connection.execute_batch(migration).unwrap();
        }
        connection.pragma_update(None, "user_version", 9).unwrap();

        migrate(&connection).unwrap();

        assert_eq!(
            connection
                .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
                .unwrap(),
            MIGRATION_VERSION
        );
        assert_eq!(
            connection
                .query_row("SELECT count(*) FROM word_timeline_runs", [], |row| {
                    row.get::<_, u32>(0)
                })
                .unwrap(),
            0
        );
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
            identity_salt: None,
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
    fn lexical_words_and_phrases_keep_independent_state_and_sources() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo,
        );
        let phrase = services
            .create_lexical_entry(UpsertLexicalEntry {
                language: "en".into(),
                kind: LexicalEntryKind::Phrase,
                canonical_form: "give up".into(),
                display_form: "give up".into(),
                status: Some(WordStatus::KnownNotRecognized),
                user_definition: Some("stop trying".into()),
                personal_note: None,
                source: Some(application::LexicalSourceContext {
                    media_id: None,
                    sentence_id: None,
                    original_form: "give up".into(),
                    sentence_text: "Never give up.".into(),
                    media_title: "Lesson".into(),
                    media_fingerprint: "lesson".into(),
                    start_ms: 10,
                    end_ms: 20,
                    token_start: Some(1),
                    token_end: Some(2),
                }),
            })
            .unwrap();
        let word = services
            .create_lexical_entry(UpsertLexicalEntry {
                language: "en".into(),
                kind: LexicalEntryKind::Word,
                canonical_form: "give".into(),
                display_form: "give".into(),
                status: Some(WordStatus::KnownRecognized),
                user_definition: None,
                personal_note: None,
                source: None,
            })
            .unwrap();
        assert_ne!(phrase.entry.id, word.entry.id);
        assert_eq!(phrase.occurrences.len(), 1);
        assert_eq!(phrase.entry.status, Some(WordStatus::KnownNotRecognized));
        assert_eq!(word.entry.status, Some(WordStatus::KnownRecognized));
        services
            .update_word_profile(UpdateWordProfile {
                language: "en".into(),
                lemma: "give".into(),
                display_form: "give".into(),
                status: Some(WordStatus::UnknownMeaning),
                source: None,
            })
            .unwrap();
        let words = services
            .list_lexical_entries("en", Some(LexicalEntryKind::Word), None, "give", 10, 0)
            .unwrap();
        assert_eq!(words.len(), 1);
        assert_eq!(words[0].entry.status, Some(WordStatus::UnknownMeaning));
        assert_eq!(
            services
                .normalize_lexical_form("en", "went")
                .unwrap()
                .normalized,
            "go"
        );
        services.correct_lemma("en", "went", "walk").unwrap();
        assert_eq!(
            services
                .normalize_lexical_form("en", "went")
                .unwrap()
                .normalized,
            "walk"
        );
        services
            .create_lexical_entry(UpsertLexicalEntry {
                language: "en".into(),
                kind: LexicalEntryKind::Word,
                canonical_form: "run".into(),
                display_form: "run".into(),
                status: Some(WordStatus::KnownRecognized),
                user_definition: None,
                personal_note: None,
                source: None,
            })
            .unwrap();
        services
            .create_lexical_entry(UpsertLexicalEntry {
                language: "en".into(),
                kind: LexicalEntryKind::Word,
                canonical_form: "jog".into(),
                display_form: "jog".into(),
                status: Some(WordStatus::UnknownMeaning),
                user_definition: None,
                personal_note: None,
                source: None,
            })
            .unwrap();
        assert!(matches!(
            services.correct_lemma("en", "run", "jog"),
            Err(application::ApplicationError::Conflict(_))
        ));
    }

    #[test]
    fn lexical_asset_import_merges_newest_fields_and_remaps_sources() {
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        );
        let local = services
            .create_lexical_entry(UpsertLexicalEntry {
                language: "en".into(),
                kind: LexicalEntryKind::Phrase,
                canonical_form: "give up".into(),
                display_form: "give up".into(),
                status: Some(WordStatus::KnownRecognized),
                user_definition: Some("local definition".into()),
                personal_note: Some("local note".into()),
                source: Some(application::LexicalSourceContext {
                    media_id: None,
                    sentence_id: None,
                    original_form: "give up".into(),
                    sentence_text: "Never give up.".into(),
                    media_title: "Local lesson".into(),
                    media_fingerprint: "lesson".into(),
                    start_ms: 10,
                    end_ms: 20,
                    token_start: Some(1),
                    token_end: Some(2),
                }),
            })
            .unwrap();
        let imported_id = LexicalEntryId::from_fingerprint("import", "give up");
        let mut imported_entry = local.entry.clone();
        imported_entry.id = imported_id.clone();
        imported_entry.status = Some(WordStatus::UnknownMeaning);
        imported_entry.updated_at_ms = local.entry.updated_at_ms;
        imported_entry.user_definition = Some("newer imported definition".into());
        imported_entry.personal_note = Some("newer imported note".into());
        imported_entry.learning_updated_at_ms = local.entry.learning_updated_at_ms + 100;
        let mut imported_occurrence = local.occurrences[0].clone();
        imported_occurrence.lexical_entry_id = imported_id.clone();
        imported_occurrence.first_seen_at_ms =
            imported_occurrence.first_seen_at_ms.saturating_sub(5);
        imported_occurrence.last_seen_at_ms += 100;
        imported_occurrence.encounter_count = 9;
        let imported_history = LexicalStatusHistory {
            id: LexicalStatusHistoryId::from_fingerprint("import-history", "give up"),
            lexical_entry_id: imported_id,
            previous_status: None,
            new_status: Some(WordStatus::UnknownMeaning),
            changed_at_ms: local.entry.updated_at_ms.saturating_sub(1),
            change_source: WordChangeSource::Import,
        };

        repo.import_lexical_assets(
            std::slice::from_ref(&imported_entry),
            std::slice::from_ref(&imported_history),
            std::slice::from_ref(&imported_occurrence),
        )
        .unwrap();
        repo.import_lexical_assets(
            std::slice::from_ref(&imported_entry),
            std::slice::from_ref(&imported_history),
            std::slice::from_ref(&imported_occurrence),
        )
        .unwrap();
        let merged = services.lexical_details(&local.entry.id).unwrap().unwrap();
        assert_eq!(merged.entry.status, Some(WordStatus::KnownRecognized));
        assert_eq!(
            merged.entry.user_definition.as_deref(),
            Some("newer imported definition")
        );
        assert_eq!(merged.occurrences.len(), 1);
        assert_eq!(merged.occurrences[0].encounter_count, 9);
        assert_eq!(
            merged
                .history
                .iter()
                .filter(|value| value.change_source == WordChangeSource::Import)
                .count(),
            1
        );
        assert_eq!(
            merged
                .history
                .iter()
                .find(|value| value.change_source == WordChangeSource::Import)
                .map(|value| &value.lexical_entry_id),
            Some(&local.entry.id)
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
                identity_salt: None,
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
                let lexical_kind = if word % 2 == 0 {
                    "\"word\""
                } else {
                    "\"phrase\""
                };
                tx.execute(
                    "INSERT INTO word_profiles
                     (id,language,lemma,normalized_lemma,display_form,status,updated_at_ms)
                     VALUES (?1,'en',?2,?2,?2,'\"unknown_meaning\"',?3)",
                    params![profile_id, format!("word-{word:05}"), word],
                )
                .unwrap();
                tx.execute(
                    "INSERT INTO lexical_entries
                     (id,language,kind,canonical_form,normalized_form,display_form,status,
                      normalization_provider,normalization_version,user_corrected,
                      updated_at_ms,learning_updated_at_ms)
                     VALUES (?1,'en',?2,?3,?3,?3,'\"unknown_meaning\"','test','v1',0,?4,0)",
                    params![
                        format!("lexical-{word}"),
                        lexical_kind,
                        format!("asset-{word:05}"),
                        word
                    ],
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
        let lexical_started = std::time::Instant::now();
        let lexical = repo
            .list_lexical_entries(
                &LanguageCode::parse("en").unwrap(),
                Some(LexicalEntryKind::Phrase),
                Some(WordStatus::UnknownMeaning),
                "asset-09",
                200,
                0,
            )
            .unwrap();
        assert_eq!(lexical.len(), 200);
        assert!(
            lexical_started.elapsed() < std::time::Duration::from_secs(2),
            "large lexical query took {:?}",
            lexical_started.elapsed()
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
        assert_eq!(services.export_vocabulary().unwrap().version, 4);
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

    #[test]
    fn phonetic_models_jobs_analyses_and_feedback_round_trip() {
        let repo = SqliteRepository::in_memory().unwrap();
        let media = MediaItem {
            id: MediaId::from_fingerprint("media", "phonetic"),
            path: "/tmp/phonetic.wav".into(),
            fingerprint: "phonetic-media".into(),
            title: "Phonetic".into(),
            kind: MediaKind::Audio,
            duration: Some(TimeMs::new(5_000)),
            availability: MediaAvailability::Available,
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        MediaRepository::upsert(&repo, &media).unwrap();
        let sentence_id = SubtitleSentenceId::from_fingerprint("sentence", "phonetic");
        let track = SubtitleTrack {
            id: SubtitleTrackId::from_fingerprint("track", "phonetic"),
            media_id: media.id.clone(),
            fingerprint: "phonetic-track".into(),
            language: Some(LanguageCode::parse("en").unwrap()),
            source: "test".into(),
            sentences: vec![SubtitleSentence {
                id: sentence_id.clone(),
                index: 0,
                start: TimeMs::new(100),
                end: TimeMs::new(500),
                original_text: "Hello".into(),
                display_text: "Hello".into(),
                tokens: vec![],
            }],
        };
        repo.save_track(&track).unwrap();
        let model_id = PhoneticAnalysisModelId::from_fingerprint("model", "fake");
        let model = PhoneticAnalysisModelDescriptor {
            id: model_id.clone(),
            provider_id: "fake".into(),
            display_name: "Fake".into(),
            family: "fake".into(),
            revision: "v1".into(),
            checksum_sha256: "abc".into(),
            download_url: None,
            local_path: None,
            size_bytes: 0,
            supported_languages: vec!["en".into()],
            supported_dialects: vec!["en-US".into()],
            phone_sets: vec!["arpabet".into()],
            supports_timestamps: true,
            expected_sample_rate_hz: 16_000,
            context_window_ms: None,
            state: PhoneticModelState::Custom,
            installed_bytes: 0,
            error: None,
            license: "test".into(),
            training_data_provenance: "synthetic".into(),
            distribution_allowed: false,
            application_verified: false,
            updated_at_ms: 1,
        };
        repo.upsert_phonetic_model(&model).unwrap();
        assert_eq!(repo.get_phonetic_model(&model_id).unwrap(), Some(model));

        let job_id = PhoneticAnalysisJobId::from_fingerprint("job", "fake");
        let mut job = PhoneticAnalysisJob {
            id: job_id.clone(),
            media_id: media.id.clone(),
            track_id: track.id.clone(),
            sentence_id: Some(sentence_id.clone()),
            scope: PhoneticAnalysisScope::Sentence,
            audio_start_ms: 100,
            audio_end_ms: 500,
            provider_id: "fake".into(),
            provider_version: "v1".into(),
            runtime_id: "fake".into(),
            runtime_version: "v1".into(),
            model_id: model_id.clone(),
            model_revision: "v1".into(),
            model_checksum_sha256: "abc".into(),
            requested_phone_set: "arpabet".into(),
            settings_json: "{}".into(),
            input_fingerprint: "input".into(),
            status: PhoneticAnalysisJobStatus::Queued,
            phase_progress: 0,
            error_code: None,
            error_message: None,
            retry_of_job_id: None,
            analysis_id: None,
            created_at_ms: 1,
            started_at_ms: None,
            completed_at_ms: None,
            updated_at_ms: 1,
        };
        repo.create_phonetic_job(&job).unwrap();
        repo.interrupt_active_phonetic_jobs(2).unwrap();
        job = repo.get_phonetic_job(&job_id).unwrap().unwrap();
        assert_eq!(job.status, PhoneticAnalysisJobStatus::Interrupted);

        job.status = PhoneticAnalysisJobStatus::Completed;
        job.updated_at_ms = 3;
        let analysis_id = PhoneticAnalysisId::from_fingerprint("analysis", "fake");
        job.analysis_id = Some(analysis_id.clone());
        repo.update_phonetic_job(&job).unwrap();
        let finding_id = PhoneticFindingId::from_fingerprint("finding", "fake");
        let analysis = PhoneticAnalysis {
            id: analysis_id.clone(),
            job_id,
            media_id: media.id,
            track_id: track.id.clone(),
            sentence_id: Some(sentence_id),
            audio_start_ms: 100,
            audio_end_ms: 500,
            provider_id: "fake".into(),
            provider_version: "v1".into(),
            model_id,
            model_revision: "v1".into(),
            model_checksum_sha256: "abc".into(),
            phone_set: "arpabet".into(),
            detected_phones: vec![DetectedPhone {
                symbol: "HH".into(),
                phone_set: "arpabet".into(),
                start_ms: 100,
                end_ms: 200,
                confidence: Some(0.9),
                token_index: Some(0),
                provider_id: "fake".into(),
                provider_version: "v1".into(),
                model_revision: "v1".into(),
            }],
            alignments: vec![],
            findings: vec![PhoneticFinding {
                id: finding_id.clone(),
                analysis_id: analysis_id.clone(),
                finding_type: "weak_form".into(),
                affected_token_start: 0,
                affected_token_end: 0,
                canonical_phones: vec!["HH".into()],
                detected_phones: vec!["HH".into()],
                aligned_phone_start: Some(0),
                aligned_phone_end: Some(0),
                audio_start_ms: 100,
                audio_end_ms: 200,
                confidence: 0.7,
                evidence: "fake".into(),
                status: PhoneticFindingStatus::SupportedByAlignment,
            }],
            analyzer_version: "v1".into(),
            created_at_ms: 3,
        };
        repo.save_phonetic_analysis(&analysis).unwrap();
        assert_eq!(
            repo.list_track_phonetic_analyses(&track.id).unwrap(),
            vec![analysis.clone()]
        );
        repo.delete_phonetic_model(&analysis.model_id).unwrap();
        assert_eq!(
            repo.list_track_phonetic_analyses(&track.id).unwrap(),
            vec![analysis.clone()]
        );
        let mut revised_analysis = analysis.clone();
        revised_analysis.id = PhoneticAnalysisId::from_fingerprint("analysis", "fake-v2");
        for finding in &mut revised_analysis.findings {
            finding.id = PhoneticFindingId::from_fingerprint("finding", "fake-v2");
            finding.analysis_id = revised_analysis.id.clone();
        }
        revised_analysis.model_revision = "v2".into();
        revised_analysis.created_at_ms = 4;
        repo.save_phonetic_analysis(&revised_analysis).unwrap();
        let versions = repo.list_track_phonetic_analyses(&track.id).unwrap();
        assert_eq!(versions.len(), 2);
        assert!(versions.contains(&analysis));
        assert!(versions.contains(&revised_analysis));
        let feedback = PhoneticFindingFeedback {
            finding_id: finding_id.clone(),
            value: PhoneticFindingFeedbackValue::Rejected,
            note: Some("test".into()),
            updated_at_ms: 4,
        };
        repo.save_phonetic_feedback(&feedback).unwrap();
        assert_eq!(
            repo.get_phonetic_feedback(&finding_id).unwrap(),
            Some(feedback.clone())
        );
        let bundle = repo.export_assets().unwrap();
        assert_eq!(bundle.version, 4);
        assert_eq!(bundle.phonetic_finding_feedback, vec![feedback.clone()]);
        let restored = SqliteRepository::in_memory().unwrap();
        restored.import_assets(&bundle).unwrap();
        assert_eq!(
            restored.get_phonetic_feedback(&finding_id).unwrap(),
            Some(feedback)
        );
    }
}
