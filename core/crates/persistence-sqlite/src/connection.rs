use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use rusqlite::Connection;

use super::{PersistenceError, migrate};

pub struct SqliteRepository {
    pub(crate) connection: Mutex<Connection>,
}

impl SqliteRepository {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, PersistenceError> {
        let path = path.as_ref();
        if path.exists() {
            let current: u32 =
                Connection::open(path)?.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            if current < super::MIGRATION_VERSION {
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
