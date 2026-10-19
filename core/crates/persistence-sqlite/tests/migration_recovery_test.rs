//! Characterization tests for the migration backup / failure-recovery behavior.
//!
//! These pin down what `SqliteRepository::open` actually does around the
//! versioned pre-migration backups (`<path>.pre-migration-vN.bak`) so a future
//! refactor of the migration system cannot silently change the safety net. They
//! assert observed behavior, not an idealized design.

use std::path::{Path, PathBuf};

use persistence_sqlite::{MIGRATION_VERSION, SqliteRepository};
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

fn marker(path: &Path) -> String {
    Connection::open(path)
        .expect("open db file")
        .query_row("SELECT value FROM _recovery_marker", [], |row| row.get(0))
        .expect("read recovery marker")
}

/// Mirror of the production `backup_path` in `connection.rs`.
fn backup_of(path: &Path, source_version: u32) -> PathBuf {
    let mut raw = path.as_os_str().to_owned();
    raw.push(format!(".pre-migration-v{source_version}.bak"));
    PathBuf::from(raw)
}

fn legacy_backup_of(path: &Path) -> PathBuf {
    let mut raw = path.as_os_str().to_owned();
    raw.push(".pre-migration.bak");
    PathBuf::from(raw)
}

fn stale_backup_temp_of(path: &Path, source_version: u32) -> PathBuf {
    let mut raw = backup_of(path, source_version).into_os_string();
    raw.push(".tmp-stale");
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

    let backup = backup_of(&path, 0);
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
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
    assert!(has_table(&path, "lexical_capability_states"));
    assert!(has_table(&path, "learning_observations"));
    assert!(has_table(&path, "content_difficulty_profiles"));
    assert!(has_table(&path, "sense_group_analysis_runs"));

    let backup = backup_of(&path, 21);
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
        !backup_of(&path, 0).exists(),
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
        !backup_of(&path, first).exists(),
        "no backup is taken when the db is already current"
    );
}

#[test]
fn a_database_has_one_live_repository_owner() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("db.sqlite");
    let first = SqliteRepository::open(&path).expect("first owner");

    assert!(
        SqliteRepository::open(&path).is_err(),
        "another process/repository must not promote live secret reservations"
    );

    drop(first);
    SqliteRepository::open(&path).expect("lock is released with repository");
}

#[test]
fn an_existing_versioned_backup_is_never_replaced() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("versioned-backup.sqlite");
    let backup = backup_of(&path, 0);
    {
        let conn = Connection::open(&backup).expect("create existing backup");
        conn.execute_batch(
            "CREATE TABLE _recovery_marker (value TEXT NOT NULL);
             INSERT INTO _recovery_marker VALUES ('original');",
        )
        .expect("seed existing backup");
    }
    {
        let conn = Connection::open(&path).expect("create live db");
        conn.execute_batch("CREATE TABLE media_items (id TEXT);")
            .expect("seed migration collision");
    }

    assert!(SqliteRepository::open(&path).is_err());
    assert_eq!(marker(&backup), "original");
    assert_eq!(user_version(&backup), 0);
}

#[test]
fn a_legacy_fixed_backup_is_preserved_without_blocking_a_versioned_backup() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("legacy-backup.sqlite");
    let legacy_backup = legacy_backup_of(&path);
    {
        let conn = Connection::open(&legacy_backup).expect("create legacy backup");
        conn.execute_batch(
            "CREATE TABLE _recovery_marker (value TEXT NOT NULL);
             INSERT INTO _recovery_marker VALUES ('legacy');",
        )
        .expect("seed legacy backup");
    }
    {
        let conn = Connection::open(&path).expect("create live db");
        conn.execute_batch(
            "CREATE TABLE _recovery_marker (value TEXT NOT NULL);
             INSERT INTO _recovery_marker VALUES ('current');",
        )
        .expect("seed live database");
    }

    SqliteRepository::open(&path).expect("publish versioned backup and migrate");

    assert_eq!(marker(&legacy_backup), "legacy");
    assert_eq!(
        marker(&backup_of(&path, 0)),
        "current",
        "the legacy fixed backup must not suppress the source-version recovery point"
    );
}

#[test]
fn a_truncated_temporary_backup_is_never_published_as_the_final_backup() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("stale-temp.sqlite");
    {
        let conn = Connection::open(&path).expect("create live db");
        conn.execute_batch(
            "CREATE TABLE _recovery_marker (value TEXT NOT NULL);
             INSERT INTO _recovery_marker VALUES ('complete');",
        )
        .expect("seed live database");
    }

    let backup = backup_of(&path, 0);
    let stale_temp = stale_backup_temp_of(&path, 0);
    std::fs::write(&stale_temp, b"truncated").expect("seed interrupted temporary backup");
    assert!(!backup.exists(), "temporary data is not the final backup");

    let repo = SqliteRepository::open(&path).expect("publish complete backup and migrate");
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
    assert_eq!(
        marker(&backup),
        "complete",
        "the published final backup is a complete SQLite database"
    );
    assert_eq!(
        std::fs::read(&stale_temp).unwrap(),
        b"truncated",
        "an unrelated crash remnant is ignored rather than published"
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

    let backup = backup_of(&path, 0);
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

#[test]
fn retry_after_a_late_migration_failure_does_not_overwrite_the_first_backup() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("late-failure.sqlite");

    // Migration 1 can commit, while this deliberately incompatible v2 table
    // makes migration 2 fail. This models a real late migration failure where
    // the live database is left partially advanced between startup attempts.
    {
        let conn = Connection::open(&path).expect("create db");
        conn.execute_batch(
            r#"
            CREATE TABLE _recovery_marker (value TEXT NOT NULL);
            INSERT INTO _recovery_marker VALUES ('original');
            CREATE TABLE subtitle_tracks (collision TEXT);
            "#,
        )
        .expect("seed late migration collision");
    }

    assert!(SqliteRepository::open(&path).is_err());
    assert_eq!(
        user_version(&path),
        1,
        "migration 1 committed before v2 failed"
    );
    let original_backup = backup_of(&path, 0);
    assert_eq!(user_version(&original_backup), 0);
    assert_eq!(marker(&original_backup), "original");

    // Distinguish the now-partially-migrated live file from the original
    // recovery point before retrying startup.
    Connection::open(&path)
        .expect("open partial db")
        .execute("UPDATE _recovery_marker SET value = 'partial'", [])
        .expect("mark partial state");

    assert!(SqliteRepository::open(&path).is_err());
    assert_eq!(marker(&path), "partial");
    assert_eq!(
        marker(&original_backup),
        "original",
        "a later source-version backup must preserve the original recovery point"
    );
    assert_eq!(
        user_version(&original_backup),
        0,
        "the original backup remains the true pre-upgrade schema"
    );
    let partial_backup = backup_of(&path, 1);
    assert_eq!(
        marker(&partial_backup),
        "partial",
        "a later source schema version receives its own recovery point"
    );
    assert_eq!(
        user_version(&partial_backup),
        1,
        "the versioned backup records the schema version it precedes"
    );
}
