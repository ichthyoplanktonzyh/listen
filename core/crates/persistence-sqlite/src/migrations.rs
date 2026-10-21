use rusqlite::Connection;

use super::PersistenceError;

/// Version 66 is the fresh store for the parked learning-channel experiment.
pub const MIGRATION_VERSION: u32 = 66;

/// Initializes an empty branch-specific store from the listening foundation
/// plus the channel and imported-card schema. Existing schemas are accepted
/// only when they already use this branch's version.
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
    tx.execute_batch(include_str!(
        "../migrations/0066_other_learning_channels.sql"
    ))?;
    tx.pragma_update(None, "user_version", MIGRATION_VERSION)?;
    tx.commit()?;
    Ok(())
}
