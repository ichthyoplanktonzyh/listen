//! Durable capability attempt persistence (SQLite).

use application::{ApplicationError, CapabilityAttemptRepository};
use domain::{
    CapabilityAttempt, CapabilityAttemptId, CapabilityAttemptStatus, LearningMaterialId,
    MaterialCapability,
};
use rusqlite::{Connection, OptionalExtension, params};

use super::{SqliteRepository, domain_sql, from_json, repo};

/// Serializes one typed attempt into its storage row columns.
pub(crate) fn insert_attempt(
    connection: &Connection,
    attempt: &CapabilityAttempt,
) -> Result<(), ApplicationError> {
    connection
        .execute(
            "INSERT INTO capability_attempts
               (material_id, attempt_id, capability, status, started_at_ms,
                finished_at_ms, failure_reason, producer_tool_id, producer_tool_version)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
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
        .map_err(|error| {
            if error
                .sqlite_error_code()
                .is_some_and(|code| code == rusqlite::ErrorCode::ConstraintViolation)
            {
                ApplicationError::Conflict("capability attempt already exists")
            } else {
                repo(error)
            }
        })?;
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

    fn repository() -> SqliteRepository {
        let connection = rusqlite::Connection::open_in_memory().expect("in-memory database");
        super::super::migrate(&connection).expect("migrations run");
        SqliteRepository {
            connection: std::sync::Mutex::new(connection),
            _database_lock: None,
        }
    }

    #[test]
    fn attempts_persist_across_reopen_and_keep_old_facts() {
        let first = repository();
        let material_id = LearningMaterialId::parse("material-1").expect("valid material id");
        let mut attempt =
            CapabilityAttempt::start(material_id.clone(), MaterialCapability::Listen, 5);
        attempt
            .fail(10, "provider unavailable")
            .expect("valid failure");
        first.save_attempt(&attempt).expect("saved");

        let retry = CapabilityAttempt::start(material_id.clone(), MaterialCapability::Listen, 11);
        first.save_attempt(&retry).expect("saved retry");

        let reopened = repository();
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
        let connection = rusqlite::Connection::open_in_memory().expect("in-memory database");
        super::super::migrate(&connection).expect("migrations run");
        let store = SqliteRepository {
            connection: std::sync::Mutex::new(connection),
            _database_lock: None,
        };
        let material_id = LearningMaterialId::parse("material-1").expect("valid material id");
        let attempt = CapabilityAttempt::start(material_id, MaterialCapability::Listen, 1);
        // Directly forge an unknown capability row; the typed read must fail.
        store
            .connection
            .lock()
            .execute(
                "INSERT INTO capability_attempts
                   (material_id, attempt_id, capability, status, started_at_ms)
                 VALUES (?1,?2,'futuristic', 'running', 1)",
                params![attempt.material_id.as_str(), attempt.attempt_id.as_str()],
            )
            .expect("forged row");
        let result = store.list_attempts(&attempt.material_id);
        assert!(result.is_err(), "unknown capability is corruption");
    }
}
