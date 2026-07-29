use std::fs::{self, File, OpenOptions};
use std::io;
use std::path::{Path, PathBuf};

use parking_lot::Mutex;
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
                preserve_first_backup(path)?;
            }
        }
        let connection = Connection::open(path)?;
        connection.busy_timeout(std::time::Duration::from_secs(5))?;
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
            .query_row("PRAGMA user_version", [], |r| r.get(0))?)
    }
}

fn backup_path(path: &Path) -> PathBuf {
    let mut backup = path.as_os_str().to_owned();
    backup.push(".pre-migration.bak");
    PathBuf::from(backup)
}

/// Creates the historical `<db>.pre-migration.bak` once and never overwrites
/// it. A later startup may observe a database where earlier migrations already
/// committed before a later migration failed; preserving the first copy keeps
/// the actual pre-upgrade recovery point instead of replacing it with that
/// partially migrated state.
fn preserve_first_backup(path: &Path) -> io::Result<()> {
    let backup = backup_path(path);
    let mut destination = match OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&backup)
    {
        Ok(destination) => destination,
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => return Ok(()),
        Err(error) => return Err(error),
    };
    let mut source = File::open(path)?;
    if let Err(error) = io::copy(&mut source, &mut destination).and_then(|_| destination.sync_all())
    {
        // This process created the incomplete backup, so removing it permits a
        // later startup to retry. An already complete backup is never touched.
        drop(destination);
        let _ = fs::remove_file(&backup);
        return Err(error);
    }
    Ok(())
}
