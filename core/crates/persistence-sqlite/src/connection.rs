use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};

use fs2::FileExt;
use parking_lot::Mutex;
use rusqlite::{Connection, OpenFlags};

use super::{MIGRATION_VERSION, PersistenceError, migrate};

pub struct SqliteRepository {
    pub(crate) connection: Mutex<Connection>,
    _database_lock: Option<File>,
}

impl SqliteRepository {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, PersistenceError> {
        let path = path.as_ref();
        validate_existing_store(path)?;

        let lock_path = database_lock_path(path);
        let database_lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(lock_path)?;
        database_lock.try_lock_exclusive()?;

        let connection = Connection::open(path)?;
        connection.busy_timeout(std::time::Duration::from_secs(5))?;
        migrate(&connection)?;
        Ok(Self {
            connection: Mutex::new(connection),
            _database_lock: Some(database_lock),
        })
    }

    pub fn in_memory() -> Result<Self, PersistenceError> {
        let connection = Connection::open_in_memory()?;
        migrate(&connection)?;
        Ok(Self {
            connection: Mutex::new(connection),
            _database_lock: None,
        })
    }

    pub fn schema_version(&self) -> Result<u32, PersistenceError> {
        Ok(self
            .connection
            .lock()
            .query_row("PRAGMA user_version", [], |row| row.get(0))?)
    }
}

/// Refuses incompatible files through a read-only connection before creating
/// a lock sidecar or opening the database read/write. An unversioned store is
/// valid only when its schema is empty.
fn validate_existing_store(path: &Path) -> Result<(), PersistenceError> {
    if !path.exists() {
        return Ok(());
    }
    let connection = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    let current: u32 = connection.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if current == MIGRATION_VERSION {
        return Ok(());
    }
    if current != 0 {
        return Err(PersistenceError::UnsupportedSchemaVersion {
            found: current,
            expected: MIGRATION_VERSION,
        });
    }
    let objects: u32 = connection.query_row(
        "SELECT COUNT(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'",
        [],
        |row| row.get(0),
    )?;
    if objects != 0 {
        return Err(PersistenceError::NonEmptyUnversionedDatabase);
    }
    Ok(())
}

fn database_lock_path(path: &Path) -> PathBuf {
    let mut lock = path.as_os_str().to_owned();
    lock.push(".lock");
    PathBuf::from(lock)
}
