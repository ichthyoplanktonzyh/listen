use rusqlite::Connection;

use super::PersistenceError;

/// Version 67 is the document-material recovery branch's fresh-store schema.
/// It extends the listening bootstrap with the document rendition table;
/// stores from other scope branches are intentionally unsupported.
pub const MIGRATION_VERSION: u32 = 67;

/// Initializes an empty SQLite database from the listening bootstrap and the
/// document material schema. Existing schemas are accepted only when they
/// already use this branch's version; no historical migration or automatic
/// reset is performed.
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
    tx.execute_batch(include_str!("../migrations/0067_document_materials.sql"))?;
    tx.pragma_update(None, "user_version", MIGRATION_VERSION)?;
    tx.commit()?;
    Ok(())
}
