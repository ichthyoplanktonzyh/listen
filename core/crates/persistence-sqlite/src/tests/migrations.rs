use super::*;
use std::fs;
use std::path::PathBuf;

#[test]
fn fresh_database_bootstraps_listening_schema_and_review_budget() {
    let repo = SqliteRepository::in_memory().unwrap();
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);

    let connection = repo.connection.lock();
    for table in [
        "media_items",
        "subtitle_tracks",
        "subtitle_sentences",
        "learning_materials",
        "material_revisions",
        "material_media_renditions",
        "package_installations",
        "package_adoptions",
        "learning_events",
        "learning_observations",
        "lexical_capability_states",
        "lexical_capability_history",
        "listening_inbox_items",
        "practice_sessions",
        "review_items",
        "review_schedules",
        "review_settings",
        "hunting_targets",
        "corpus_occurrences",
        "recording_assets",
        "transcription_models",
        "realtime_provider_profiles",
        "realtime_conversation_sessions",
        "realtime_conversation_turns",
    ] {
        assert!(table_exists(&connection, table), "{table} must exist");
    }
    for retired in [
        "semantic_task_attempts",
        "personal_expression_attempts",
        "reading_positions",
        "content_difficulty_profiles",
        "content_fit_calibrations",
        "projection_proposals",
        "projection_decisions",
        "recognition_evidence",
        "upgrade_suggestions",
        "hunting_candidates",
        "anki_review_items",
        "anki_review_history",
        "material_document_renditions",
        "transcription_jobs",
    ] {
        assert!(
            !table_exists(&connection, retired),
            "{retired} must be absent"
        );
    }
    let budget: (u32, u32) = connection
        .query_row(
            "SELECT new_cards_per_day, reviews_per_day FROM review_settings WHERE singleton=1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(budget, (20, 200));
    let mut foreign_key_check = connection.prepare("PRAGMA foreign_key_check").unwrap();
    assert!(
        foreign_key_check
            .query([])
            .unwrap()
            .next()
            .unwrap()
            .is_none()
    );
}

#[test]
fn fresh_file_store_reopens_without_reapplying_defaults() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("listen-ai.sqlite");
    {
        let repo = SqliteRepository::open(&path).unwrap();
        assert_eq!(repo.schema_version().unwrap(), 65);
        repo.connection
            .lock()
            .execute(
                "UPDATE review_settings SET new_cards_per_day=31,reviews_per_day=71 WHERE singleton=1",
                [],
            )
            .unwrap();
    }
    {
        let repo = SqliteRepository::open(&path).unwrap();
        assert_eq!(repo.schema_version().unwrap(), 65);
        let budget: (u32, u32) = repo
            .connection
            .lock()
            .query_row(
                "SELECT new_cards_per_day,reviews_per_day FROM review_settings WHERE singleton=1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(budget, (31, 71));
    }
}

#[test]
fn rejects_old_store_read_only_without_backup_or_lock_sidecar() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("old.sqlite");
    {
        let connection = Connection::open(&path).unwrap();
        connection
            .execute_batch(
                "CREATE TABLE learner_facts(id TEXT PRIMARY KEY, body TEXT NOT NULL);
                 INSERT INTO learner_facts VALUES ('kept','opaque');
                 PRAGMA user_version=63;",
            )
            .unwrap();
    }
    let original = fs::read(&path).unwrap();
    let error = match SqliteRepository::open(&path) {
        Ok(_) => panic!("old schema must be rejected"),
        Err(error) => error,
    };
    assert!(matches!(
        error,
        PersistenceError::UnsupportedSchemaVersion {
            found: 63,
            expected: 65
        }
    ));
    assert_eq!(fs::read(&path).unwrap(), original);
    assert!(!PathBuf::from(format!("{}.lock", path.display())).exists());
    assert!(!PathBuf::from(format!("{}.pre-migration-v63.bak", path.display())).exists());
}

#[test]
fn refuses_unversioned_nonempty_database() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch("CREATE TABLE sentinel(id INTEGER PRIMARY KEY);")
        .unwrap();
    let error = migrate(&connection).unwrap_err();
    assert!(matches!(
        error,
        PersistenceError::NonEmptyUnversionedDatabase
    ));
    let objects: u32 = connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(objects, 1);
    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        0
    );
}

#[test]
fn failed_fresh_bootstrap_rolls_back_schema_and_version() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch("PRAGMA max_page_count=1;")
        .unwrap();
    let result = migrate(&connection);
    assert!(result.is_err(), "the page limit should interrupt bootstrap");
    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        0
    );
    let objects: u32 = connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(objects, 0);
}
