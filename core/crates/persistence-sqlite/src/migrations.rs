use rusqlite::Connection;

use super::PersistenceError;

/// Version 64 is the first listening-focused fresh-store schema. Earlier
/// development schemas are intentionally unsupported and are never rewritten.
pub const MIGRATION_VERSION: u32 = 64;

/// Initializes an empty SQLite database from the single listening-focused
/// bootstrap. Existing schemas are accepted only when they already use the
/// current version; no historical migration or automatic reset is performed.
pub fn migrate(connection: &Connection) -> Result<(), PersistenceError> {
    connection.execute_batch("PRAGMA foreign_keys = ON;")?;
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

    let tx = connection.unchecked_transaction()?;
    tx.execute_batch(include_str!("../migrations/0064_listening_focus.sql"))?;
    tx.pragma_update(None, "user_version", MIGRATION_VERSION)?;
    tx.commit()?;
    Ok(())
}
