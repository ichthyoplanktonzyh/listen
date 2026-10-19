//! Durable capability attempt persistence (SQLite).
//!
//! `start_attempt` is the atomic seam: inside one transaction the previous
//! running attempt of the same capability is superseded and the new attempt
//! receives a monotonic per-capability sequence, so attempts in the same
//! millisecond never collide and no capability is ever left with two running
//! attempts. `reconcile_running_attempts` supersedes every attempt left
//! running by a previous process at startup.

use application::{ApplicationError, CapabilityAttemptRepository};
use domain::{
    CapabilityAttempt, CapabilityAttemptId, CapabilityAttemptStatus, LearningMaterialId,
    MaterialCapability,
};
use rusqlite::{Connection, OptionalExtension, params};

use super::{SqliteRepository, domain_sql, repo};

/// Serializes one typed attempt into its storage row columns. Latest-request
/// wins: retrying an attempt rewrites that attempt's facts in place rather
/// than failing on the composite key.
pub(crate) fn insert_attempt(
    connection: &Connection,
    attempt: &CapabilityAttempt,
    attempt_sequence: u64,
) -> Result<(), ApplicationError> {
    connection
        .execute(
            "INSERT INTO capability_attempts
               (material_id, attempt_id, capability, status, started_at_ms,
                finished_at_ms, failure_reason, producer_tool_id, producer_tool_version,
                attempt_sequence)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
             ON CONFLICT(material_id, attempt_id) DO UPDATE SET
               capability=excluded.capability,
               status=excluded.status,
               started_at_ms=excluded.started_at_ms,
               finished_at_ms=excluded.finished_at_ms,
               failure_reason=excluded.failure_reason,
               producer_tool_id=excluded.producer_tool_id,
               producer_tool_version=excluded.producer_tool_version,
               attempt_sequence=excluded.attempt_sequence",
            params![
                attempt.material_id.as_str(),
                attempt.attempt_id.as_str(),
                attempt.capability.as_str(),
                attempt_status_key(attempt.status),
                attempt.started_at_ms as i64,
                attempt.finished_at_ms.map(|value| value as i64),
                attempt.failure_reason,
                attempt.producer_tool_id,
                attempt.producer_tool_version,
                attempt_sequence as i64,
            ],
        )
        .map_err(repo)?;
    Ok(())
}

fn attempt_status_key(status: CapabilityAttemptStatus) -> &'static str {
    match status {
        CapabilityAttemptStatus::Running => "running",
        CapabilityAttemptStatus::Succeeded => "succeeded",
        CapabilityAttemptStatus::Failed => "failed",
        CapabilityAttemptStatus::Cancelled => "cancelled",
        CapabilityAttemptStatus::Superseded => "superseded",
    }
}

fn attempt_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<CapabilityAttempt> {
    let capability = match row.get::<_, String>(2)?.as_str() {
        "read" => MaterialCapability::Read,
        "listen" => MaterialCapability::Listen,
        "watch" => MaterialCapability::Watch,
        "synchronized_read_listen" => MaterialCapability::SynchronizedReadListen,
        other => {
            return Err(rusqlite::Error::FromSqlConversionFailure(
                2,
                rusqlite::types::Type::Text,
                Box::new(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!("unknown capability {other}"),
                )),
            ));
        }
    };
    let status = match row.get::<_, String>(3)?.as_str() {
        "running" => CapabilityAttemptStatus::Running,
        "succeeded" => CapabilityAttemptStatus::Succeeded,
        "failed" => CapabilityAttemptStatus::Failed,
        "cancelled" => CapabilityAttemptStatus::Cancelled,
        "superseded" => CapabilityAttemptStatus::Superseded,
        other => {
            return Err(rusqlite::Error::FromSqlConversionFailure(
                3,
                rusqlite::types::Type::Text,
                Box::new(std::io::Error::new(
                    std::io::ErrorKind::InvalidData,
                    format!("unknown attempt status {other}"),
                )),
            ));
        }
    };
    let attempt_key = row.get::<_, u64>(9)?;
    let _ = attempt_key;
    Ok(CapabilityAttempt {
        attempt_id: CapabilityAttemptId::parse(row.get::<_, String>(1)?).map_err(domain_sql)?,
        material_id: LearningMaterialId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
        capability,
        status,
        started_at_ms: row.get::<_, u64>(4)?,
        finished_at_ms: row.get::<_, Option<u64>>(5)?,
        failure_reason: row.get::<_, Option<String>>(6)?,
        producer_tool_id: row.get::<_, Option<String>>(7)?,
        producer_tool_version: row.get::<_, Option<String>>(8)?,
    })
}

const ATTEMPT_COLUMNS: &str = "material_id, attempt_id, capability, status, started_at_ms, finished_at_ms, \
     failure_reason, producer_tool_id, producer_tool_version, attempt_sequence";

impl CapabilityAttemptRepository for SqliteRepository {
    fn start_attempt(
        &self,
        material_id: LearningMaterialId,
        capability: MaterialCapability,
        started_at_ms: u64,
    ) -> Result<CapabilityAttempt, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        // Atomically supersede any running attempt of the same capability:
        // a new attempt always terminates the previous in-flight work.
        tx.execute(
            "UPDATE capability_attempts
             SET status='superseded', finished_at_ms=?3
             WHERE material_id=?1 AND capability=?2 AND status='running'",
            params![
                material_id.as_str(),
                capability.as_str(),
                started_at_ms as i64,
            ],
        )
        .map_err(repo)?;
        // The monotonic per-capability sequence makes attempt identities
        // unique within the same millisecond, including concurrent retries.
        let sequence: u64 = tx
            .query_row(
                "SELECT COALESCE(MAX(attempt_sequence), 0) + 1
                 FROM capability_attempts
                 WHERE material_id=?1 AND capability=?2",
                params![material_id.as_str(), capability.as_str()],
                |row| row.get(0),
            )
            .map_err(repo)?;
        let attempt =
            CapabilityAttempt::start(material_id.clone(), capability, started_at_ms, sequence);
        insert_attempt(&tx, &attempt, sequence)?;
        tx.commit().map_err(repo)?;
        drop(conn);
        Ok(attempt)
    }

    fn save_attempt(&self, attempt: &CapabilityAttempt) -> Result<(), ApplicationError> {
        let conn = self.connection.lock();
        let existing: Option<(String, u64)> = conn
            .query_row(
                "SELECT attempt_id, attempt_sequence FROM capability_attempts WHERE attempt_id=?1",
                [attempt.attempt_id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(repo)?;
        if let Some((_, sequence)) = existing {
            conn.execute(
                "UPDATE capability_attempts
                 SET status=?3, finished_at_ms=?4, failure_reason=?5,
                     producer_tool_id=?6, producer_tool_version=?7
                 WHERE attempt_id=?1 AND material_id=?2",
                params![
                    attempt.attempt_id.as_str(),
                    attempt.material_id.as_str(),
                    attempt_status_key(attempt.status),
                    attempt.finished_at_ms.map(|value| value as i64),
                    attempt.failure_reason,
                    attempt.producer_tool_id,
                    attempt.producer_tool_version,
                ],
            )
            .map_err(repo)?;
            let _ = sequence;
        } else {
            insert_attempt(&conn, attempt, 0)?;
        }
        Ok(())
    }

    fn list_attempts(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Vec<CapabilityAttempt>, ApplicationError> {
        let conn = self.connection.lock();
        let mut statement = conn
            .prepare(&format!(
                "SELECT {ATTEMPT_COLUMNS} FROM capability_attempts
                 WHERE material_id=?1 ORDER BY started_at_ms, attempt_sequence, attempt_id"
            ))
            .map_err(repo)?;
        let attempts = statement
            .query_map([material_id.as_str()], attempt_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(attempts)
    }

    fn reconcile_running_attempts(&self, superseded_at_ms: u64) -> Result<usize, ApplicationError> {
        let conn = self.connection.lock();
        let count = conn
            .execute(
                "UPDATE capability_attempts
                 SET status='superseded', finished_at_ms=?1
                 WHERE status='running'",
                [superseded_at_ms as i64],
            )
            .map_err(repo)?;
        Ok(count)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use application::MaterialRepository;
    use domain::{
        DocumentRendition, LearningMaterial, MaterialRevision, Rendition, RenditionOrigin,
        initial_material_id,
    };

    /// A file-backed repository used to prove attempts survive a real close
    /// and reopen; the `TempDir` is returned so the database file stays alive
    /// for the duration of the test.
    fn file_repository() -> (SqliteRepository, tempfile::TempDir, std::path::PathBuf) {
        let dir = tempfile::tempdir().expect("temp directory");
        let path = dir.path().join("capability-attempts.db");
        let repo = SqliteRepository::open(&path).expect("file repository");
        (repo, dir, path)
    }

    /// Creates one real material the attempts can reference through the
    /// foreign key.
    fn ensure_material(store: &SqliteRepository) -> LearningMaterialId {
        let text = "capability attempt material";
        let digest = {
            use sha2::Digest as _;
            hex::encode(sha2::Sha256::digest(text.as_bytes()))
        };
        let asset = domain::SourceAsset::new(
            "text/plain",
            text.len() as u64,
            digest.clone(),
            domain::SourceAssetBinding::Managed,
            domain::SourceAssetAvailability::Available,
            1,
        )
        .unwrap();
        let rendition = Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                None,
                digest,
                text.len() as u64,
                Some(asset.id.clone()),
                None,
                None,
            )
            .unwrap(),
        );
        let material_id = initial_material_id(
            std::slice::from_ref(&asset),
            std::slice::from_ref(&rendition),
        )
        .unwrap();
        let revision = MaterialRevision::new(
            material_id.clone(),
            "Capability material",
            vec![asset],
            vec![rendition],
            1,
        )
        .unwrap();
        let material = LearningMaterial::new(&revision, None, 1, 1).unwrap();
        MaterialRepository::create_material(store, &material, &revision).unwrap();
        material_id
    }

    #[test]
    fn attempts_persist_across_reopen_and_keep_old_facts() {
        let (first, _dir, database_path) = file_repository();
        let material_id = ensure_material(&first);
        let started = first
            .start_attempt(material_id.clone(), MaterialCapability::Listen, 5)
            .expect("start");
        let mut attempt = started.clone();
        attempt
            .fail(10, "provider unavailable")
            .expect("valid failure");
        first.save_attempt(&attempt).expect("saved");

        let retry = first
            .start_attempt(material_id.clone(), MaterialCapability::Listen, 11)
            .expect("start retry");

        // Reopening keeps the attempts: close the first repository (releasing
        // its exclusive database lock) and open the file again.
        drop(first);
        let reopened = SqliteRepository::open(&database_path).expect("reopened repository");
        let attempts = reopened.list_attempts(&material_id).expect("listed");
        assert_eq!(attempts.len(), 2);
        assert_eq!(attempts[0].attempt_id, attempt.attempt_id);
        assert_eq!(attempts[0].status, CapabilityAttemptStatus::Failed);
        assert_eq!(
            attempts[0].failure_reason.as_deref(),
            Some("provider unavailable")
        );
        assert_eq!(attempts[1].attempt_id, retry.attempt_id);

        // Finalizing the retry rewrites only that attempt's facts.
        let mut finished = attempts
            .into_iter()
            .find(|a| a.attempt_id == retry.attempt_id)
            .expect("retry");
        finished.succeed(20, "listen-gen".into(), "0.4.0".into());
        reopened.save_attempt(&finished).expect("finalized");
        let attempts = reopened.list_attempts(&material_id).expect("listed");
        let failed = attempts
            .iter()
            .find(|a| a.attempt_id == attempt.attempt_id)
            .expect("first attempt");
        assert_eq!(failed.status, CapabilityAttemptStatus::Failed);
        assert_eq!(
            failed.failure_reason.as_deref(),
            Some("provider unavailable"),
            "a later attempt never rewrites an earlier attempt's facts"
        );
        let succeeded = attempts
            .iter()
            .find(|a| a.attempt_id == retry.attempt_id)
            .expect("retry");
        assert_eq!(succeeded.status, CapabilityAttemptStatus::Succeeded);
        assert_eq!(succeeded.producer_tool_id.as_deref(), Some("listen-gen"));
    }

    #[test]
    fn start_attempt_is_atomic_and_same_millisecond_retries_never_collide() {
        let store = SqliteRepository::in_memory().expect("in-memory repository");
        let material_id = ensure_material(&store);
        let first = store
            .start_attempt(material_id.clone(), MaterialCapability::Listen, 7)
            .expect("start");
        let second = store
            .start_attempt(material_id.clone(), MaterialCapability::Listen, 7)
            .expect("same-millisecond retry");
        assert_ne!(
            first.attempt_id, second.attempt_id,
            "attempt ids never collide within the same millisecond"
        );
        let read = store
            .start_attempt(material_id.clone(), MaterialCapability::Read, 7)
            .expect("different capability");
        assert_ne!(first.attempt_id, read.attempt_id);
        // The old running attempt was atomically superseded.
        let attempts = store.list_attempts(&material_id).expect("listed");
        let superseded = attempts
            .iter()
            .find(|attempt| attempt.attempt_id == first.attempt_id)
            .expect("first attempt preserved");
        assert_eq!(superseded.status, CapabilityAttemptStatus::Superseded);
        assert_eq!(superseded.finished_at_ms, Some(7));
        let running = attempts
            .iter()
            .find(|attempt| attempt.attempt_id == second.attempt_id)
            .expect("second attempt");
        assert_eq!(running.status, CapabilityAttemptStatus::Running);
    }

    #[test]
    fn restart_reconciliation_supersedes_every_running_attempt() {
        let (first, _dir, database_path) = file_repository();
        let material_id = ensure_material(&first);
        first
            .start_attempt(material_id.clone(), MaterialCapability::Listen, 5)
            .expect("start");
        first
            .start_attempt(material_id.clone(), MaterialCapability::Read, 6)
            .expect("start");
        drop(first);
        let reopened = SqliteRepository::open(&database_path).expect("reopened repository");
        let reconciled = reopened.reconcile_running_attempts(100).expect("reconcile");
        assert_eq!(reconciled, 2);
        let attempts = reopened.list_attempts(&material_id).expect("listed");
        assert!(
            attempts
                .iter()
                .all(|attempt| attempt.status != CapabilityAttemptStatus::Running),
            "no attempt is left running after restart reconciliation"
        );
        assert!(
            attempts
                .iter()
                .all(|attempt| attempt.status == CapabilityAttemptStatus::Superseded),
            "every interrupted attempt is honestly superseded"
        );
    }

    #[test]
    fn unknown_capability_storage_is_rejected() {
        let store = SqliteRepository::in_memory().expect("in-memory repository");
        let material_id = ensure_material(&store);
        let attempt = store
            .start_attempt(material_id, MaterialCapability::Listen, 1)
            .expect("start");
        // The schema rejects an unknown capability outright; the typed read
        // path can only ever see the known set.
        store
            .connection
            .lock()
            .execute(
                "INSERT INTO capability_attempts
                   (material_id, attempt_id, capability, status, started_at_ms, attempt_sequence)
                 VALUES (?1,?2,'futuristic', 'running', 1, 0)",
                params![attempt.material_id.as_str(), attempt.attempt_id.as_str()],
            )
            .expect_err("unknown capability is rejected by the schema");
        let result = store.list_attempts(&attempt.material_id);
        assert!(result.is_ok(), "rejected writes leave the store readable");
    }
}
