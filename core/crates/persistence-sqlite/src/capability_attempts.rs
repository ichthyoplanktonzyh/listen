//! Durable capability attempt persistence (SQLite).

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
) -> Result<(), ApplicationError> {
    connection
        .execute(
            "INSERT INTO capability_attempts
               (material_id, attempt_id, capability, status, started_at_ms,
                finished_at_ms, failure_reason, producer_tool_id, producer_tool_version)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)
             ON CONFLICT(material_id, attempt_id) DO UPDATE SET
               capability=excluded.capability,
               status=excluded.status,
               started_at_ms=excluded.started_at_ms,
               finished_at_ms=excluded.finished_at_ms,
               failure_reason=excluded.failure_reason,
               producer_tool_id=excluded.producer_tool_id,
               producer_tool_version=excluded.producer_tool_version",
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
     failure_reason, producer_tool_id, producer_tool_version";

impl CapabilityAttemptRepository for SqliteRepository {
    fn save_attempt(&self, attempt: &CapabilityAttempt) -> Result<(), ApplicationError> {
        let conn = self.connection.lock();
        let existing: Option<String> = conn
            .query_row(
                "SELECT attempt_id FROM capability_attempts WHERE attempt_id=?1",
                [attempt.attempt_id.as_str()],
                |row| row.get(0),
            )
            .optional()
            .map_err(repo)?;
        if existing.is_some() {
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
        } else {
            insert_attempt(&conn, attempt)?;
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
                 WHERE material_id=?1 ORDER BY started_at_ms, attempt_id"
            ))
            .map_err(repo)?;
        let attempts = statement
            .query_map([material_id.as_str()], attempt_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(attempts)
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
        let rendition = Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                None,
                "capability attempt material",
                None,
                None,
                None,
            )
            .unwrap(),
        );
        let material_id = initial_material_id(&[], std::slice::from_ref(&rendition)).unwrap();
        let revision = MaterialRevision::new(
            material_id.clone(),
            "Capability material",
            Vec::new(),
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
        let mut attempt =
            CapabilityAttempt::start(material_id.clone(), MaterialCapability::Listen, 5);
        attempt
            .fail(10, "provider unavailable")
            .expect("valid failure");
        first.save_attempt(&attempt).expect("saved");

        let retry = CapabilityAttempt::start(material_id.clone(), MaterialCapability::Listen, 11);
        first.save_attempt(&retry).expect("saved retry");

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
    fn unknown_capability_storage_is_rejected() {
        let store = SqliteRepository::in_memory().expect("in-memory repository");
        let material_id = ensure_material(&store);
        let attempt = CapabilityAttempt::start(material_id, MaterialCapability::Listen, 1);
        // The schema rejects an unknown capability outright; the typed read
        // path can only ever see the known set.
        store
            .connection
            .lock()
            .execute(
                "INSERT INTO capability_attempts
                   (material_id, attempt_id, capability, status, started_at_ms)
                 VALUES (?1,?2,'futuristic', 'running', 1)",
                params![attempt.material_id.as_str(), attempt.attempt_id.as_str()],
            )
            .expect_err("unknown capability is rejected by the schema");
        let result = store.list_attempts(&attempt.material_id);
        assert!(result.is_ok(), "rejected writes leave the store readable");
    }
}
