use std::fs::{self, File, OpenOptions};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use fs2::FileExt;
use parking_lot::Mutex;
use rusqlite::Connection;

use super::{PersistenceError, migrate};

pub struct SqliteRepository {
    pub(crate) connection: Mutex<Connection>,
    _database_lock: Option<File>,
}

impl SqliteRepository {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, PersistenceError> {
        let path = path.as_ref();
        let lock_path = database_lock_path(path);
        let database_lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(lock_path)?;
        database_lock.try_lock_exclusive()?;
        if path.exists() {
            let current: u32 =
                Connection::open(path)?.query_row("PRAGMA user_version", [], |r| r.get(0))?;
            if current < super::MIGRATION_VERSION {
                preserve_version_backup(path, current)?;
            }
        }
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
            .query_row("PRAGMA user_version", [], |r| r.get(0))?)
    }
}

fn database_lock_path(path: &Path) -> PathBuf {
    let mut lock = path.as_os_str().to_owned();
    lock.push(".lock");
    PathBuf::from(lock)
}

fn backup_path(path: &Path, source_version: u32) -> PathBuf {
    let mut backup = path.as_os_str().to_owned();
    backup.push(format!(".pre-migration-v{source_version}.bak"));
    PathBuf::from(backup)
}

fn legacy_backup_path(path: &Path) -> PathBuf {
    let mut backup = path.as_os_str().to_owned();
    backup.push(".pre-migration.bak");
    PathBuf::from(backup)
}

static BACKUP_TEMP_SEQUENCE: AtomicU64 = AtomicU64::new(0);

fn create_backup_temp(backup: &Path) -> io::Result<(PathBuf, File)> {
    loop {
        let sequence = BACKUP_TEMP_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let mut temporary = backup.as_os_str().to_owned();
        temporary.push(format!(".tmp-{}-{sequence}", std::process::id()));
        let temporary = PathBuf::from(temporary);
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temporary)
        {
            Ok(file) => return Ok((temporary, file)),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
}

fn sync_parent(path: &Path) -> io::Result<()> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    File::open(parent)?.sync_all()
}

fn preserve_legacy_backup_alias(path: &Path, versioned_backup: &Path) -> io::Result<()> {
    let legacy_backup = legacy_backup_path(path);
    match fs::hard_link(versioned_backup, &legacy_backup) {
        Ok(()) => sync_parent(&legacy_backup),
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => Ok(()),
        Err(error) => Err(error),
    }
}

/// Creates `<db>.pre-migration-vN.bak` once per source schema version and never
/// overwrites it. Versioned recovery points preserve the latest subtitle data
/// before each future upgrade without replacing an earlier upgrade's backup. A
/// no-replace hard-link alias keeps the historical fixed path compatible.
fn preserve_version_backup(path: &Path, source_version: u32) -> io::Result<()> {
    let backup = backup_path(path, source_version);
    if backup.exists() {
        return preserve_legacy_backup_alias(path, &backup);
    }

    // Copy into a unique, unpublished file. A crash at any point before the
    // hard link below can leave only a `.tmp-*` file, never a partial final
    // backup that a later startup would mistake for the recovery point.
    let (temporary, mut destination) = create_backup_temp(&backup)?;
    let copy_result = File::open(path)
        .and_then(|mut source| io::copy(&mut source, &mut destination))
        .and_then(|_| destination.sync_all());
    drop(destination);
    if let Err(error) = copy_result {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }

    // hard_link is an atomic no-replace publish: if another process published
    // the first backup concurrently, preserve that winner and discard ours.
    match fs::hard_link(&temporary, &backup) {
        Ok(()) => {
            let remove_result = fs::remove_file(&temporary);
            let sync_result = sync_parent(&backup);
            remove_result.and(sync_result)?;
        }
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
            let _ = fs::remove_file(&temporary);
        }
        Err(error) => {
            let _ = fs::remove_file(&temporary);
            return Err(error);
        }
    }
    preserve_legacy_backup_alias(path, &backup)
}
