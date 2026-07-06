use super::*;

#[test]
fn new_database_migrates_to_latest() {
    let repo = SqliteRepository::in_memory().unwrap();
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
    let connection = repo.connection.lock().unwrap();
    assert!(!table_exists(&connection, removed_resource_table_name()));
    assert!(table_exists(&connection, "hunting_candidates"));
    assert!(table_exists(&connection, "recognition_evidence"));
    assert!(table_exists(&connection, "upgrade_suggestions"));
}

#[test]
fn current_version_with_legacy_lexical_schema_is_destructively_repaired() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../../migrations/0001_media.sql"),
        include_str!("../../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../../migrations/0003_subtitle_identity.sql"),
        include_str!("../../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../../migrations/0005_learning_experience.sql"),
        include_str!("../../migrations/0006_transcription.sql"),
        LEGACY_PHASE_218_LEXICAL_SCHEMA,
        include_str!("../../migrations/0008_pronunciation.sql"),
        include_str!("../../migrations/0009_phonetic_analysis.sql"),
        include_str!("../../migrations/0010_word_timelines.sql"),
        include_str!("../../migrations/0011_lltimeline_resources.sql"),
        include_str!("../../migrations/0012_subtitle_resource_lifecycle.sql"),
        include_str!("../../migrations/0013_chunk_timelines.sql"),
        include_str!("../../migrations/0014_phone_timelines.sql"),
        include_str!("../../migrations/0015_learning_loop.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute(
            "INSERT INTO lexical_entries
                 (id,language,kind,canonical_form,normalized_form,display_form,status,
                  normalization_provider,normalization_version,user_corrected,updated_at_ms,
                  learning_updated_at_ms)
                 VALUES ('legacy-entry','en','\"word\"','hello','hello','Hello',
                         '\"known_recognized\"','legacy','v1',0,10,0)",
            [],
        )
        .unwrap();
    connection.pragma_update(None, "user_version", 15).unwrap();

    assert_eq!(
        table_column_count(
            &connection,
            "lexical_entries",
            &["granularity", "normalization", "normalized_key"]
        ),
        0
    );
    assert!(!table_exists(&connection, "lexical_observations"));

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        table_column_count(
            &connection,
            "lexical_entries",
            &["granularity", "normalization", "normalized_key"]
        ),
        3
    );
    assert!(table_exists(&connection, "lexical_observations"));
    assert!(!table_exists(&connection, removed_resource_table_name()));
    assert_eq!(
        connection
            .query_row("SELECT COUNT(*) FROM lexical_entries", [], |row| row
                .get::<_, u32>(0))
            .unwrap(),
        0
    );
}

#[test]
fn pronunciation_cache_isolated_by_provider_version() {
    let repo = SqliteRepository::in_memory().unwrap();
    let pronunciation = WordPronunciation {
        token_index: 0,
        text: "Hello".into(),
        normalized: "hello".into(),
        variants: vec![],
    };
    repo.save_word_pronunciation("en", "en-US", &pronunciation, "provider", "v1")
        .unwrap();

    assert!(
        repo.get_word_pronunciation("en", "en-US", "hello", "provider", "v1")
            .unwrap()
            .is_some()
    );
    assert!(
        repo.get_word_pronunciation("en", "en-US", "hello", "provider", "v2")
            .unwrap()
            .is_none()
    );
    assert!(
        repo.get_word_pronunciation("en", "en-GB", "hello", "provider", "v1")
            .unwrap()
            .is_none()
    );
}

#[test]
fn upgrades_historical_v1_database() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../../migrations/0001_media.sql"))
        .unwrap();
    connection.pragma_update(None, "user_version", 1).unwrap();
    migrate(&connection).unwrap();
    let version: u32 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .unwrap();
    assert_eq!(version, MIGRATION_VERSION);
}

#[test]
fn upgrades_historical_v2_database() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../../migrations/0001_media.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../../migrations/0002_learning.sql"))
        .unwrap();
    connection.pragma_update(None, "user_version", 2).unwrap();
    migrate(&connection).unwrap();
    let version: u32 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .unwrap();
    assert_eq!(version, MIGRATION_VERSION);
}

#[test]
fn upgrades_historical_v5_database_and_adds_transcription_assets() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(include_str!("../../migrations/0001_media.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../../migrations/0002_learning.sql"))
        .unwrap();
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    connection
        .execute_batch(include_str!("../../migrations/0003_subtitle_identity.sql"))
        .unwrap();
    connection
        .execute_batch(include_str!("../../migrations/0004_vocabulary_assets.sql"))
        .unwrap();
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    connection
        .execute_batch(include_str!(
            "../../migrations/0005_learning_experience.sql"
        ))
        .unwrap();
    connection.pragma_update(None, "user_version", 5).unwrap();
    migrate(&connection).unwrap();
    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM transcription_jobs", [], |row| row
                .get::<_, u32>(0))
            .unwrap(),
        0
    );
}

#[test]
fn upgrades_historical_v7_database_and_resets_lexical_assets() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../../migrations/0001_media.sql"),
        include_str!("../../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../../migrations/0003_subtitle_identity.sql"),
        include_str!("../../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../../migrations/0005_learning_experience.sql"),
        include_str!("../../migrations/0006_transcription.sql"),
        include_str!("../../migrations/0007_lexical_entries.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.pragma_update(None, "user_version", 7).unwrap();
    connection
        .execute(
            "INSERT INTO lexical_entries
                 (id,language,kind,granularity,normalization,normalized_key,
                  canonical_form,normalized_form,display_form,status,
                  normalization_provider,normalization_version,user_corrected,updated_at_ms,
                  learning_updated_at_ms)
                 VALUES ('asset','en','\"word\"','core.word','core.lemma','hello',
                         'hello','hello','Hello','\"known_recognized\"',
                         'legacy','v1',0,10,0)",
            [],
        )
        .unwrap();
    migrate(&connection).unwrap();
    assert_eq!(
        connection
            .query_row("SELECT COUNT(*) FROM lexical_entries", [], |row| row
                .get::<_, u32>(0))
            .unwrap(),
        0
    );
    assert!(table_exists(&connection, "lexical_observations"));
    assert!(!table_exists(&connection, removed_resource_table_name()));
    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
}

#[test]
fn upgrades_historical_v8_database_and_adds_phonetic_analysis_assets() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../../migrations/0001_media.sql"),
        include_str!("../../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../../migrations/0003_subtitle_identity.sql"),
        include_str!("../../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../../migrations/0005_learning_experience.sql"),
        include_str!("../../migrations/0006_transcription.sql"),
        include_str!("../../migrations/0007_lexical_entries.sql"),
        include_str!("../../migrations/0008_pronunciation.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.pragma_update(None, "user_version", 8).unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM phonetic_analysis_jobs", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM phonetic_analyses", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
}

#[test]
fn upgrades_historical_v9_database_and_adds_word_timeline_assets() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../../migrations/0001_media.sql"),
        include_str!("../../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../../migrations/0003_subtitle_identity.sql"),
        include_str!("../../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../../migrations/0005_learning_experience.sql"),
        include_str!("../../migrations/0006_transcription.sql"),
        include_str!("../../migrations/0007_lexical_entries.sql"),
        include_str!("../../migrations/0008_pronunciation.sql"),
        include_str!("../../migrations/0009_phonetic_analysis.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.pragma_update(None, "user_version", 9).unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM word_timeline_runs", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM lltimeline_resources", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
}

#[test]
fn upgrades_historical_v10_database_and_adds_lltimeline_resources() {
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../../migrations/0001_media.sql"),
        include_str!("../../migrations/0002_learning.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute_batch("PRAGMA foreign_keys=OFF;")
        .unwrap();
    for migration in [
        include_str!("../../migrations/0003_subtitle_identity.sql"),
        include_str!("../../migrations/0004_vocabulary_assets.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
    for migration in [
        include_str!("../../migrations/0005_learning_experience.sql"),
        include_str!("../../migrations/0006_transcription.sql"),
        include_str!("../../migrations/0007_lexical_entries.sql"),
        include_str!("../../migrations/0008_pronunciation.sql"),
        include_str!("../../migrations/0009_phonetic_analysis.sql"),
        include_str!("../../migrations/0010_word_timelines.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection.pragma_update(None, "user_version", 10).unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row("SELECT count(*) FROM lltimeline_resources", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        0
    );
}
