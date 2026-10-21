use rusqlite::Connection;

use super::PersistenceError;

/// Version 65 adds the opt-in AI conversation store to listening schema 64.
/// Schema 64 is rejected; this branch uses its own default database file.
pub const MIGRATION_VERSION: u32 = 65;

/// Initializes an empty AI-conversation database from the listening bootstrap
/// plus its isolated conversation tables. Existing schemas are accepted only
/// when they already use version 65; no prior store is migrated or reset.
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
    tx.execute_batch(include_str!("../migrations/0065_ai_conversation.sql"))?;
    tx.pragma_update(None, "user_version", MIGRATION_VERSION)?;
    tx.commit()?;
    Ok(())
}
