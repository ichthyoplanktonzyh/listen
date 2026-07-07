//! Characterization tests for the migration backup / failure-recovery behavior.
//!
//! These pin down what `SqliteRepository::open` actually does around the
//! pre-migration backup (`<path>.pre-migration.bak`) so a future refactor of the
//! migration system cannot silently change the safety net. They assert observed
//! behavior, not an idealized design.

use std::path::{Path, PathBuf};

use persistence_sqlite::SqliteRepository;
use rusqlite::Connection;

fn user_version(path: &Path) -> u32 {
    Connection::open(path)
        .expect("open db file")
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .expect("read user_version")
}

fn has_table(path: &Path, name: &str) -> bool {
    Connection::open(path)
        .expect("open db file")
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?1",
            [name],
            |row| row.get::<_, i64>(0),
        )
        .expect("query sqlite_master")
        > 0
}

/// Mirror of the production `backup_path` in `connection.rs`.
fn backup_of(path: &Path) -> PathBuf {
    let mut raw = path.as_os_str().to_owned();
    raw.push(".pre-migration.bak");
    PathBuf::from(raw)
}

#[test]
fn pre_migration_backup_is_created_when_upgrading_an_existing_db() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("llplayernext.sqlite");

    // An existing, behind-version database (user_version 0) with some content.
    {
        let conn = Connection::open(&path).expect("create db");
        conn.execute_batch("CREATE TABLE _probe(x);")
            .expect("seed probe table");
    }
    assert_eq!(user_version(&path), 0);

    let repo = SqliteRepository::open(&path).expect("open + migrate");
    let current = repo.schema_version().expect("schema version");
    assert!(current > 0, "an existing old db is migrated forward");

    let backup = backup_of(&path);
    assert!(backup.exists(), "a pre-migration backup must be created");
    assert_eq!(
        user_version(&backup),
        0,
        "backup captures the pre-migration version"
    );
    assert!(
        has_table(&backup, "_probe"),
        "backup preserves the original content"
    );
    assert_eq!(
        user_version(&path),
        current,
        "the live db is migrated to the current version"
    );
}

#[test]
fn v21_capability_migration_preserves_a_queryable_pre_migration_backup() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("v21.sqlite");
    {
        let conn = Connection::open(&path).expect("create v21 db");
        conn.execute_batch(
            r#"
            CREATE TABLE lexical_entries (
              id TEXT PRIMARY KEY NOT NULL,
              status TEXT,
              updated_at_ms INTEGER NOT NULL,
              learning_updated_at_ms INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO lexical_entries VALUES
              ('entry', '"known_not_recognized"', 10, 20);
            CREATE TABLE lexical_observations (
              id TEXT PRIMARY KEY NOT NULL,
              lexical_entry_id TEXT NOT NULL,
              sentence_id TEXT,
              sentence_id_snapshot TEXT NOT NULL,
              original_form TEXT NOT NULL,
              result TEXT NOT NULL,
              created_at_ms INTEGER NOT NULL,
              cleared_at_ms INTEGER
            );
            PRAGMA user_version=21;
            "#,
        )
        .expect("seed v21 lexical data");
    }

    let repo = SqliteRepository::open(&path).expect("migrate v21");
    assert_eq!(repo.schema_version().unwrap(), 23);
    assert!(has_table(&path, "lexical_capability_states"));
    assert!(has_table(&path, "learning_observations"));

    let backup = backup_of(&path);
    assert_eq!(user_version(&backup), 21);
    assert!(!has_table(&backup, "lexical_capability_states"));
    let legacy_status: String = Connection::open(&backup)
        .unwrap()
        .query_row(
            "SELECT status FROM lexical_entries WHERE id='entry'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(legacy_status, "\"known_not_recognized\"");
}

#[test]
fn no_backup_is_created_for_a_brand_new_database() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("fresh.sqlite");
    assert!(!path.exists());

    let repo = SqliteRepository::open(&path).expect("open new db");
    assert!(repo.schema_version().expect("schema version") > 0);
    assert!(
        !backup_of(&path).exists(),
        "a brand-new db needs no pre-migration backup"
    );
}

#[test]
fn reopening_a_current_database_is_idempotent_and_makes_no_backup() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("db.sqlite");

    let first = SqliteRepository::open(&path)
        .expect("first open")
        .schema_version()
        .expect("schema version");
    let second = SqliteRepository::open(&path)
        .expect("reopen")
        .schema_version()
        .expect("schema version");

    assert_eq!(
        first, second,
        "reopening a current db keeps the same version"
    );
    assert!(first > 0);
    assert!(
        !backup_of(&path).exists(),
        "no backup is taken when the db is already current"
    );
}

#[test]
fn migration_failure_preserves_the_pre_migration_backup() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("corrupt.sqlite");

    // A version-0 db whose `media_items` table collides with migration 0001
    // (a plain `CREATE TABLE media_items`, so re-creation fails mid-migration).
    {
        let conn = Connection::open(&path).expect("create db");
        conn.execute_batch("CREATE TABLE media_items (id TEXT);")
            .expect("seed colliding table");
    }
    assert_eq!(user_version(&path), 0);

    let result = SqliteRepository::open(&path);
    assert!(
        result.is_err(),
        "migration must fail on the colliding table"
    );

    let backup = backup_of(&path);
    assert!(
        backup.exists(),
        "the original db survives in the backup for recovery"
    );
    assert!(has_table(&backup, "media_items"));
    assert_eq!(user_version(&backup), 0);

    // The live file did not silently advance past the failed migration.
    assert_eq!(
        user_version(&path),
        0,
        "a failed migration leaves the version unadvanced"
    );
}
