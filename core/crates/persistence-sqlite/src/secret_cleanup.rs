use application::{ApplicationError, SecretCleanupRepository, now_ms};
use domain::SecretRef;
use rusqlite::params;

use super::{SqliteRepository, repo};

impl SecretCleanupRepository for SqliteRepository {
    fn reserve_secret_cleanup(&self, auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT OR IGNORE INTO pending_secret_cleanups
                 (auth_ref,queued_at_ms,state) VALUES (?1,?2,'reserved')",
                params![auth_ref.as_str(), now_ms()],
            )
            .map_err(repo)?;
        Ok(())
    }

    fn schedule_secret_cleanup(&self, auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO pending_secret_cleanups (auth_ref,queued_at_ms,state)
                 VALUES (?1,?2,'ready')
                 ON CONFLICT(auth_ref) DO UPDATE SET state='ready'",
                params![auth_ref.as_str(), now_ms()],
            )
            .map_err(repo)?;
        Ok(())
    }

    fn recover_secret_cleanup_reservations(&self) -> Result<usize, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "UPDATE pending_secret_cleanups SET state='ready' WHERE state='reserved'",
                [],
            )
            .map_err(repo)
    }

    fn pending_secret_cleanups(&self) -> Result<Vec<SecretRef>, ApplicationError> {
        let connection = self.connection.lock();
        let mut statement = connection
            .prepare(
                "SELECT auth_ref FROM pending_secret_cleanups
                 WHERE state='ready' ORDER BY queued_at_ms,auth_ref",
            )
            .map_err(repo)?;
        statement
            .query_map([], |row| row.get::<_, String>(0).map(SecretRef::new))
            .map_err(repo)?
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(repo)
    }

    fn complete_secret_cleanup(&self, auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .execute(
                "DELETE FROM pending_secret_cleanups WHERE auth_ref=?1",
                [auth_ref.as_str()],
            )
            .map_err(repo)?;
        Ok(())
    }
}
