use rusqlite::Connection;

use super::PersistenceError;

/// Version 68 is the isolated listening-coach fresh-store schema. Listening
/// main uses version 64; neither branch upgrades the other's store.
pub const MIGRATION_VERSION: u32 = 68;

/// Initializes the listening bootstrap plus the isolated coach tables.
/// Existing schemas are accepted only when they already use the current
/// version; no historical migration or automatic reset is performed.
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
    tx.execute_batch(include_str!("../migrations/0068_learning_coach.sql"))?;
    tx.pragma_update(None, "user_version", MIGRATION_VERSION)?;
    tx.commit()?;
    Ok(())
}
