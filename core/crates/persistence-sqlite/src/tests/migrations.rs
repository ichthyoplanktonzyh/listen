use super::*;
use crate::learning_material::{LEGACY_BLANK_TITLE_FALLBACK, backfill_legacy_media_materials};

#[test]
fn new_database_migrates_to_latest() {
    let repo = SqliteRepository::in_memory().unwrap();
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
    let connection = repo.connection.lock();
    assert!(!table_exists(&connection, removed_resource_table_name()));
    assert!(table_exists(&connection, "hunting_candidates"));
    assert!(table_exists(&connection, "hunting_targets"));
    assert!(table_exists(&connection, "recognition_evidence"));
    assert!(table_exists(&connection, "upgrade_suggestions"));
    assert!(table_exists(&connection, "lexical_capability_states"));
    assert!(table_exists(&connection, "lexical_capability_history"));
}

#[test]
fn v54_marks_legacy_synthetic_lltimeline_media_missing_without_deleting_resources_or_history() {
    let repo = SqliteRepository::in_memory().unwrap();
    let connection = repo.connection.lock();
    connection
        .execute_batch(
            r#"
            INSERT INTO media_items
              (id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms,availability)
            VALUES
              ('detached','lltimeline://detached','detached-fp','Detached','"video"',1000,1,1,'"available"'),
              ('real','/tmp/real.mp4','real-fp','Real','"video"',1000,1,1,'"available"');
            INSERT INTO subtitle_tracks
              (id,media_id,fingerprint,language,source,status)
            VALUES
              ('detached-track','detached','track-fp','en','lltimeline-json-v1','"available"');
            INSERT INTO lltimeline_resources
              (track_id,metadata_json,artifacts_json,updated_at_ms)
            VALUES
              ('detached-track','{"media":{"path":"/old/source.mp4"}}','[]',1);
            INSERT INTO learning_events
              (id,occurred_at_ms,kind,subject_kind,subject_id,session_id,event_json)
            VALUES
              ('history',1,'"familiar_material_marked"','"media"','detached',NULL,'{}');
            PRAGMA user_version=53;
            "#,
        )
        .unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row(
                "SELECT availability FROM media_items WHERE id='detached'",
                [],
                |row| row.get::<_, String>(0),
            )
            .unwrap(),
        "\"missing\""
    );
    assert_eq!(
        connection
            .query_row(
                "SELECT availability FROM media_items WHERE id='real'",
                [],
                |row| row.get::<_, String>(0),
            )
            .unwrap(),
        "\"available\""
    );
    for table in ["subtitle_tracks", "lltimeline_resources", "learning_events"] {
        assert_eq!(
            connection
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                    row.get::<_, u32>(0)
                })
                .unwrap(),
            1,
            "{table} survives availability correction"
        );
    }
}

#[test]
fn v45_removes_role_reply_facts_projections_and_recording_file() {
    let repo = SqliteRepository::in_memory().unwrap();
    let recording_path =
        std::env::temp_dir().join(format!("llplayer-role-reply-{}.wav", std::process::id()));
    std::fs::write(&recording_path, b"role reply audio").unwrap();
    let connection = repo.connection.lock();
    connection
        .execute_batch(&format!(
            r#"
            PRAGMA user_version=44;
            INSERT INTO lexical_entries
              (id,language,kind,granularity,normalization,normalized_key,canonical_form,
               normalized_form,display_form,normalization_provider,normalization_version,
               updated_at_ms,learning_updated_at_ms)
            VALUES ('role-word','en','"word"','word','lemma','ticket','ticket','ticket',
                    'ticket','test','1',1,1);
            INSERT INTO recording_assets
              (id,language,file_path,duration_ms,created_at_ms,asset_json)
            VALUES ('role-recording','en','{}',1000,1,'{{}}');
            INSERT INTO semantic_rubrics
              (id,version,purpose,start_ms,end_ms,source_language,response_language,
               source_sha256,created_at_ms,rubric_json)
            VALUES ('role-rubric',1,'"role_reply"',0,1000,'en','en','hash',1,'{{}}');
            INSERT INTO semantic_task_attempts
              (id,kind,rubric_id,rubric_version,status,started_at_ms,attempt_json)
            VALUES ('role-attempt','"role_reply"','role-rubric',1,'"completed"',2,
                    '{{"responses":[{{"recording_asset_id":"role-recording"}}]}}');
            INSERT INTO semantic_judgments
              (id,attempt_id,response_revision,rubric_id,rubric_version,abstained,
               created_at_ms,judgment_json)
            VALUES ('role-judgment','role-attempt',1,'role-rubric',1,0,3,'{{}}');
            INSERT INTO judgment_adjudications
              (id,judgment_id,point_id,occurred_at_ms,adjudication_json)
            VALUES ('role-adjudication','role-judgment','point',4,'{{}}');
            INSERT INTO learning_observations
              (id,lexical_entry_id,sense_id,capability,task_type,outcome,assistance,
               surface_form,origin,source_ref,occurred_at_ms)
            VALUES ('role-observation','role-word','','"speaking"','"constructed_speaking"',
                    '"success"','"none"','ticket','"practice_task"',
                    'speaking:role-attempt:role-word',5);
            INSERT INTO projection_proposals
              (id,lexical_entry_id,capability,algorithm_version,evidence_as_of_ms,
               proposal_json,created_at_ms)
            VALUES ('role-proposal','role-word','"speaking"','speaking-proposal-v1',5,
                    '{{"evidence":[{{"observation_id":"role-observation"}}]}}',6);
            INSERT INTO projection_decisions
              (id,proposal_id,decision_json,decided_at_ms)
            VALUES ('role-decision','role-proposal','{{"decision":"confirm"}}',7);
            INSERT INTO lexical_capability_states
              (lexical_entry_id,sense_id,capability,projection_json,updated_at_ms)
            VALUES ('role-word','','"speaking"','{{"conclusion":"acquired"}}',7);
            INSERT INTO lexical_capability_history
              (id,lexical_entry_id,sense_id,capability,previous_state_json,new_state_json,
               change_kind,changed_at_ms)
            VALUES ('role-history','role-word','','"speaking"','{{}}','{{}}',
                    '"projection_updated"',7);
            INSERT INTO review_items
              (id,source_kind,status,created_at_ms,updated_at_ms,item_json)
            VALUES ('role-review','"speaking_attempt"','"active"',8,8,
                    '{{"source":{{"id":"role-attempt"}}}}');
            "#,
            recording_path.to_string_lossy().replace('\'', "''")
        ))
        .unwrap();

    migrate(&connection).unwrap();

    for table in [
        "semantic_rubrics",
        "semantic_task_attempts",
        "semantic_judgments",
        "judgment_adjudications",
        "learning_observations",
        "projection_proposals",
        "projection_decisions",
        "lexical_capability_states",
        "lexical_capability_history",
        "review_items",
        "recording_assets",
    ] {
        let count: u32 = connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(count, 0, "{table} retained Role Reply data");
    }
    assert!(!recording_path.exists());
}

#[test]
fn v23_backfills_uncleared_legacy_observations_with_explicit_provenance() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(
            r#"
            CREATE TABLE lexical_entries (
              id TEXT PRIMARY KEY NOT NULL,
              status TEXT,
              updated_at_ms INTEGER NOT NULL,
              learning_updated_at_ms INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO lexical_entries VALUES ('entry', NULL, 1, 0);
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
            INSERT INTO lexical_observations VALUES
              ('legacy-1', 'entry', 's1', 's1', 'went', '"not_recognized_in_context"', 100, NULL),
              ('legacy-2', 'entry', 's2', 's2', 'go', '"recognized_in_context"', 200, NULL),
              ('legacy-cleared', 'entry', 's3', 's3', 'gone', '"recognized_in_context"', 300, 400);
            PRAGMA user_version=21;
            "#,
        )
        .unwrap();

    migrate(&connection).unwrap();

    let rows: Vec<(String, String, String, String, String, u64)> = {
        let mut statement = connection
            .prepare(
                "SELECT capability,task_type,outcome,origin,surface_form,occurred_at_ms
                 FROM learning_observations ORDER BY occurred_at_ms",
            )
            .unwrap();
        statement
            .query_map([], |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                ))
            })
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
    };
    // Cleared legacy markings are retracted judgments, not evidence.
    assert_eq!(rows.len(), 2);
    for (capability, task_type, _, origin, _, _) in &rows {
        assert_eq!(capability, "\"listening\"");
        assert_eq!(task_type, "\"context_marking\"");
        assert_eq!(origin, "\"legacy_backfill\"");
    }
    assert_eq!(rows[0].2, "\"failure\"");
    assert_eq!(rows[0].4, "went");
    assert_eq!(rows[0].5, 100);
    assert_eq!(rows[1].2, "\"success\"");

    // Re-running the backfill must not duplicate rows.
    backfill_legacy_observations(&connection).unwrap();
    assert_eq!(
        connection
            .query_row("SELECT COUNT(*) FROM learning_observations", [], |row| row
                .get::<_, u32>(
                0
            ))
            .unwrap(),
        2
    );
}

#[test]
fn v22_backfills_legacy_status_as_sourced_capability_projections() {
    let connection = Connection::open_in_memory().unwrap();
    connection
        .execute_batch(
            r#"
            CREATE TABLE lexical_entries (
              id TEXT PRIMARY KEY NOT NULL,
              status TEXT,
              updated_at_ms INTEGER NOT NULL,
              learning_updated_at_ms INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO lexical_entries VALUES
              ('none', NULL, 1, 0),
              ('unknown', '"unknown_meaning"', 2, 20),
              ('not-heard', '"known_not_recognized"', 3, 30),
              ('heard', '"known_recognized"', 4, 40);
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
        .unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row(
                "SELECT COUNT(*) FROM lexical_capability_states",
                [],
                |row| { row.get::<_, u32>(0) }
            )
            .unwrap(),
        5
    );
    assert_eq!(
        connection
            .query_row(
                "SELECT COUNT(*) FROM lexical_capability_history",
                [],
                |row| { row.get::<_, u32>(0) }
            )
            .unwrap(),
        5
    );
    let projection: CapabilityProjection = connection
        .query_row(
            "SELECT projection_json FROM lexical_capability_states
             WHERE lexical_entry_id='not-heard' AND capability='\"listening\"'",
            [],
            |row| from_json(&row.get::<_, String>(0)?),
        )
        .unwrap();
    assert_eq!(projection.conclusion, CapabilityConclusion::NotAcquired);
    assert_eq!(
        projection.source,
        CapabilityProjectionSource::LegacyLearningStatusMigration
    );
    assert_eq!(projection.updated_at_ms, 30);
    assert_eq!(
        connection
            .query_row(
                "SELECT status FROM lexical_entries WHERE id='not-heard'",
                [],
                |row| row.get::<_, String>(0)
            )
            .unwrap(),
        "\"known_not_recognized\""
    );
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

#[test]
fn upgrades_v30_database_with_sense_folder_update_guard() {
    let connection = Connection::open_in_memory().unwrap();
    migrate(&connection).unwrap();
    connection
        .execute_batch(
            "DROP TRIGGER validate_lexical_sense_folder_occurrence_parent_update;
             PRAGMA user_version=30;",
        )
        .unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        connection
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger'
                 AND name='validate_lexical_sense_folder_occurrence_parent_update'",
                [],
                |row| row.get::<_, u32>(0),
            )
            .unwrap(),
        1
    );
}

#[test]
fn upgrades_v29_database_with_empty_optional_sense_folders() {
    let connection = Connection::open_in_memory().unwrap();
    migrate(&connection).unwrap();
    connection
        .execute_batch(
            "DROP TRIGGER validate_lexical_sense_folder_occurrence_parent;
             DROP TABLE lexical_sense_folder_occurrences;
             DROP TABLE lexical_sense_folders;
             PRAGMA user_version=29;",
        )
        .unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert!(table_exists(&connection, "lexical_sense_folders"));
    assert!(table_exists(
        &connection,
        "lexical_sense_folder_occurrences"
    ));
}

#[test]
fn v46_seeds_fsrs_without_resetting_legacy_review_progress() {
    let repo = SqliteRepository::in_memory().unwrap();
    let connection = repo.connection.lock();
    connection
        .execute(
            "INSERT INTO review_items
             (id,source_kind,status,created_at_ms,updated_at_ms,item_json)
             VALUES ('legacy-review','\"sentence\"','\"active\"',1,1,'{}')",
            [],
        )
        .unwrap();
    connection
        .execute(
            "INSERT INTO review_schedules(item_id,due_at_ms,algorithm,schedule_json)
             VALUES ('legacy-review',8640000000,'listen_review_v1_heuristic_proxy',?1)",
            [serde_json::json!({
                "item_id": "legacy-review",
                "algorithm": "listen_review_v1_heuristic_proxy",
                "due_at_ms": 8_640_000_000_u64,
                "stability": null,
                "difficulty": null,
                "interval_days": 30.0,
                "lapse_count": 3
            })
            .to_string()],
        )
        .unwrap();
    connection.pragma_update(None, "user_version", 45).unwrap();

    migrate(&connection).unwrap();

    let value: serde_json::Value = serde_json::from_str(
        &connection
            .query_row(
                "SELECT schedule_json FROM review_schedules WHERE item_id='legacy-review'",
                [],
                |row| row.get::<_, String>(0),
            )
            .unwrap(),
    )
    .unwrap();
    assert_eq!(value["algorithm"], "fsrs_6_default_v1");
    assert_eq!(value["interval_days"], 30.0);
    assert_eq!(value["lapse_count"], 3);
    assert_eq!(value["review_count"], 1);
    assert!(value["stability"].as_f64().unwrap() > 0.0);
    assert!(value["difficulty"].as_f64().unwrap() > 0.0);
}

#[test]
fn v57_drops_retired_chunk_timeline_storage_after_upgrade() {
    // R5 retirement: a database that carries the historical 0013
    // `chunk_timeline_runs` table (with rows) must lose that storage when it
    // upgrades, while the rest of the schema upgrades normally. Dropping the
    // table never cascades to learner history: it held replaceable analysis
    // artifacts only.
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../../migrations/0001_media.sql"),
        include_str!("../../migrations/0002_learning.sql"),
        include_str!("../../migrations/0003_subtitle_identity.sql"),
        include_str!("../../migrations/0004_vocabulary_assets.sql"),
        include_str!("../../migrations/0005_learning_experience.sql"),
        include_str!("../../migrations/0006_transcription.sql"),
        include_str!("../../migrations/0007_lexical_entries.sql"),
        include_str!("../../migrations/0008_pronunciation.sql"),
        include_str!("../../migrations/0009_phonetic_analysis.sql"),
        include_str!("../../migrations/0010_word_timelines.sql"),
        include_str!("../../migrations/0011_lltimeline_resources.sql"),
        include_str!("../../migrations/0012_subtitle_resource_lifecycle.sql"),
        include_str!("../../migrations/0013_chunk_timelines.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute(
            "INSERT INTO media_items
               (id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms)
             VALUES ('legacy-media','/tmp/legacy.mp4','fp','Legacy','\"video\"',NULL,1,1)",
            [],
        )
        .unwrap();
    connection
        .execute(
            "INSERT INTO subtitle_tracks (id,media_id,fingerprint,language,source,status)
             VALUES ('legacy-track','legacy-media','fp',NULL,'test','\"available\"')",
            [],
        )
        .unwrap();
    connection
        .execute(
            "INSERT INTO chunk_timeline_runs
               (id,track_id,media_id,status,timeline_json,created_at_ms,updated_at_ms)
             VALUES ('legacy-chunk','legacy-track','legacy-media','\"active\"','{}',1,1)",
            [],
        )
        .unwrap();
    assert!(table_exists(&connection, "chunk_timeline_runs"));
    connection.pragma_update(None, "user_version", 13).unwrap();

    migrate(&connection).unwrap();

    let version: u32 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .unwrap();
    assert_eq!(version, MIGRATION_VERSION);
    assert!(!table_exists(&connection, "chunk_timeline_runs"));
    assert!(table_exists(&connection, "subtitle_tracks"));
    // The row is gone with its table; the track itself survives.
    let count: u32 = connection
        .query_row(
            "SELECT COUNT(*) FROM subtitle_tracks WHERE id='legacy-track'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn fresh_schema_never_retains_chunk_timeline_storage() {
    // A database created from scratch applies the immutable 0013 migration
    // (which is history) and then the forward v57 drop, so the retired table
    // must not survive the final schema.
    let connection = Connection::open_in_memory().unwrap();
    migrate(&connection).unwrap();
    let version: u32 = connection
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .unwrap();
    assert_eq!(version, MIGRATION_VERSION);
    assert!(!table_exists(&connection, "chunk_timeline_runs"));
}

#[test]
fn v58_backfills_preexisting_media_rows_as_retained_with_creation_time() {
    // Upgrade stability: every media row that existed before membership
    // became explicit stays in the Personal Library after v58, with a
    // deterministic membership time equal to its creation time. A row that
    // is registered after the upgrade (Temporary Material) is not affected by
    // the backfill.
    let connection = Connection::open_in_memory().unwrap();
    for migration in [
        include_str!("../../migrations/0001_media.sql"),
        include_str!("../../migrations/0002_learning.sql"),
        include_str!("../../migrations/0003_subtitle_identity.sql"),
        include_str!("../../migrations/0004_vocabulary_assets.sql"),
        include_str!("../../migrations/0005_learning_experience.sql"),
        include_str!("../../migrations/0006_transcription.sql"),
        include_str!("../../migrations/0007_lexical_entries.sql"),
        include_str!("../../migrations/0008_pronunciation.sql"),
        include_str!("../../migrations/0009_phonetic_analysis.sql"),
        include_str!("../../migrations/0010_word_timelines.sql"),
        include_str!("../../migrations/0011_lltimeline_resources.sql"),
        include_str!("../../migrations/0012_subtitle_resource_lifecycle.sql"),
        include_str!("../../migrations/0013_chunk_timelines.sql"),
    ] {
        connection.execute_batch(migration).unwrap();
    }
    connection
        .execute(
            "INSERT INTO media_items
               (id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms)
             VALUES
               ('old-a','/tmp/a.mp4','fp-a','A','\"video\"',NULL,111,222),
               ('old-b','/tmp/b.mp4','fp-b','B','\"audio\"',NULL,333,444)",
            [],
        )
        .unwrap();
    connection.pragma_update(None, "user_version", 13).unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |r| r.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    // Every preexisting row is retained with its creation time.
    let rows: Vec<(String, Option<u64>)> = {
        let mut statement = connection
            .prepare("SELECT id, retained_at_ms FROM media_items ORDER BY id")
            .unwrap();
        statement
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
    };
    assert_eq!(
        rows,
        vec![
            ("old-a".to_owned(), Some(111)),
            ("old-b".to_owned(), Some(333)),
        ]
    );
    // Non-membership columns are untouched by the backfill.
    let (path, created_at_ms): (String, u64) = connection
        .query_row(
            "SELECT path, created_at_ms FROM media_items WHERE id='old-a'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(path, "/tmp/a.mp4");
    assert_eq!(created_at_ms, 111);
}

#[test]
fn fresh_schema_ends_at_v59_with_nullable_membership_column() {
    // A database created from scratch runs the forward v58 migration too, so
    // the latest (v59) schema still carries the nullable `retained_at_ms`
    // membership column on `media_items`, with no rows to backfill.
    let connection = Connection::open_in_memory().unwrap();
    migrate(&connection).unwrap();
    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |r| r.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    assert_eq!(
        table_column_count(&connection, "media_items", &["retained_at_ms"]),
        1,
        "retained_at_ms column must exist"
    );
    let nullable: u8 = connection
        .query_row(
            "SELECT \"notnull\" FROM pragma_table_info('media_items')
             WHERE name='retained_at_ms'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(nullable, 0, "retained_at_ms must be nullable");
}

#[test]
fn fresh_schema_reports_v59_with_learning_material_tables_and_columns() {
    let repo = SqliteRepository::in_memory().unwrap();
    // Read the schema version before locking the connection: `schema_version`
    // acquires the same non-reentrant mutex.
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
    let connection = repo.connection.lock();
    for table in [
        "learning_materials",
        "material_revisions",
        "material_assets",
        "material_media_bindings",
    ] {
        assert!(table_exists(&connection, table), "{table} must exist");
    }
    assert_eq!(
        table_column_count(
            &connection,
            "learning_materials",
            &[
                "id",
                "current_revision_id",
                "retained_at_ms",
                "created_at_ms",
                "updated_at_ms",
            ],
        ),
        5
    );
    assert_eq!(
        table_column_count(
            &connection,
            "material_revisions",
            &["id", "material_id", "title", "created_at_ms"],
        ),
        4
    );
    assert_eq!(
        table_column_count(
            &connection,
            "material_assets",
            &[
                "revision_id",
                "ordinal",
                "asset_id",
                "asset_kind",
                "asset_json"
            ],
        ),
        5
    );
    assert_eq!(
        table_column_count(
            &connection,
            "material_media_bindings",
            &["media_id", "material_id"],
        ),
        2
    );
    // A PRIMARY KEY on a SQLite rowid table does not imply NOT NULL, so the
    // identifier columns must declare it explicitly.
    for (table, column) in [
        ("learning_materials", "id"),
        ("material_revisions", "id"),
        ("material_media_bindings", "media_id"),
    ] {
        let notnull: u8 = connection
            .query_row(
                &format!(
                    "SELECT \"notnull\" FROM pragma_table_info('{table}')
                     WHERE name='{column}'"
                ),
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(notnull, 1, "{table}.{column} must be NOT NULL");
    }
}

#[test]
fn v59_learning_material_schema_enforces_invariants_and_defers_current_revision_foreign_key() {
    let repo = SqliteRepository::in_memory().unwrap();
    let connection = repo.connection.lock();
    // The material/revision reference is circular, so the material row is
    // inserted before its revision exists; the deferred `current_revision_id`
    // foreign key only validates at commit time.
    {
        let tx = connection.unchecked_transaction().unwrap();
        tx.execute_batch(
            r#"
            INSERT INTO learning_materials
              (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
            VALUES ('material-1','revision-1',100,100,100);
            INSERT INTO material_revisions
              (id,material_id,title,created_at_ms)
            VALUES ('revision-1','material-1','First title',100);
            INSERT INTO material_assets
              (revision_id,ordinal,asset_id,asset_kind,asset_json)
            VALUES
              ('revision-1',0,'asset-text','document_text','{"text":"hello"}'),
              ('revision-1',1,'asset-media','media_rendition','{"media_id":"media-1"}');
            INSERT INTO material_media_bindings
              (media_id,material_id)
            VALUES ('media-1','material-1');
            "#,
        )
        .unwrap();
        tx.commit().unwrap();
    }
    // A material whose current revision is never created cannot commit.
    {
        let tx = connection.unchecked_transaction().unwrap();
        tx.execute(
            "INSERT INTO learning_materials
               (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
             VALUES ('orphan','missing-revision',NULL,1,1)",
            [],
        )
        .unwrap();
        assert!(tx.commit().is_err());
    }
    // The failed COMMIT (deferred foreign key violation) left no active
    // transaction behind: the orphan row was rolled back and the connection
    // is clean for the checks below.
    assert_eq!(
        connection
            .query_row(
                "SELECT COUNT(*) FROM learning_materials WHERE id='orphan'",
                [],
                |row| row.get::<_, u32>(0),
            )
            .unwrap(),
        0
    );
    // Timestamp and asset invariants reject invalid rows.
    for (label, sql) in [
        (
            "updated_at_ms precedes created_at_ms",
            "INSERT INTO learning_materials
               (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
             VALUES ('bad-time','revision-1',NULL,200,100)",
        ),
        (
            "retained_at_ms precedes created_at_ms",
            "INSERT INTO learning_materials
               (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
             VALUES ('bad-retained','revision-1',50,100,100)",
        ),
        (
            "retained_at_ms postdates updated_at_ms",
            "INSERT INTO learning_materials
               (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
             VALUES ('bad-retained-late','revision-1',150,100,100)",
        ),
        (
            "negative asset ordinal",
            "INSERT INTO material_assets
               (revision_id,ordinal,asset_id,asset_kind,asset_json)
             VALUES ('revision-1',-1,'asset-bad','document_text','{}')",
        ),
        (
            "unknown asset_kind",
            "INSERT INTO material_assets
               (revision_id,ordinal,asset_id,asset_kind,asset_json)
             VALUES ('revision-1',2,'asset-bad','audio','{}')",
        ),
        (
            "malformed asset_json",
            "INSERT INTO material_assets
               (revision_id,ordinal,asset_id,asset_kind,asset_json)
             VALUES ('revision-1',3,'asset-bad','document_text','{not json}')",
        ),
        // Rowid-table PRIMARY KEYs in SQLite do not imply NOT NULL; the FK
        // references below are valid, so rejection must come from the explicit
        // NOT NULL on the identifier columns.
        (
            "NULL learning_materials identifier",
            "INSERT INTO learning_materials
               (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
             VALUES (NULL,'revision-1',NULL,100,100)",
        ),
        (
            "NULL material_revisions identifier",
            "INSERT INTO material_revisions
               (id,material_id,title,created_at_ms)
             VALUES (NULL,'material-1','Title',100)",
        ),
        (
            "NULL material_media_bindings identifier",
            "INSERT INTO material_media_bindings
               (media_id,material_id)
             VALUES (NULL,'material-1')",
        ),
    ] {
        assert!(
            connection.execute(sql, []).is_err(),
            "{label} must be rejected"
        );
    }
    // RESTRICT (never CASCADE/SET NULL) keeps learner history durable.
    assert!(
        connection
            .execute("DELETE FROM learning_materials WHERE id='material-1'", [])
            .is_err()
    );
    assert!(
        connection
            .execute("DELETE FROM material_revisions WHERE id='revision-1'", [])
            .is_err()
    );
    // Valid rows committed above are readable after the rejected writes.
    let (title, asset_count): (String, u32) = connection
        .query_row(
            "SELECT title, (SELECT COUNT(*) FROM material_assets
                            WHERE revision_id='revision-1')
             FROM material_revisions WHERE id='revision-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(title, "First title");
    assert_eq!(asset_count, 2);
}

#[test]
fn sparse_v58_fixture_without_media_items_upgrades_to_v59_learning_material_schema() {
    // Sparse historical fixtures model a schema that never carried the v1
    // media foundation. The v59 learning-material schema must upgrade such a
    // database cleanly: `material_media_bindings` deliberately has no FK to
    // `media_items`, so materials can reference media that is not registered.
    let connection = Connection::open_in_memory().unwrap();
    migrate(&connection).unwrap();
    // Rebuild the fixture shape: full v58 schema minus the v59 learning-material
    // tables and the v1 media foundation. Dropping a table removes its own
    // indexes, and children are dropped before parents for clarity even though
    // foreign keys are disabled during the rebuild.
    connection
        .execute_batch(
            "PRAGMA foreign_keys=OFF;
             DROP TABLE material_assets;
             DROP TABLE material_media_bindings;
             DROP TABLE material_revisions;
             DROP TABLE learning_materials;
             DROP TABLE media_items;
             PRAGMA foreign_keys=ON;",
        )
        .unwrap();
    connection.pragma_update(None, "user_version", 58).unwrap();
    assert!(!table_exists(&connection, "media_items"));
    assert!(!table_exists(&connection, "learning_materials"));

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );
    for table in [
        "learning_materials",
        "material_revisions",
        "material_assets",
        "material_media_bindings",
    ] {
        assert!(table_exists(&connection, table), "{table} must exist");
    }
}

/// Rebuilds the historical v58 fixture shape inside an already-migrated
/// database: the full latest schema minus the v59 learning-material tables.
/// `media_items` keeps the v58 `retained_at_ms` membership column.
fn drop_v59_learning_material_tables(connection: &Connection) {
    connection
        .execute_batch(
            "PRAGMA foreign_keys=OFF;
             DROP TABLE material_assets;
             DROP TABLE material_media_bindings;
             DROP TABLE material_revisions;
             DROP TABLE learning_materials;
             PRAGMA foreign_keys=ON;",
        )
        .unwrap();
}

/// One legacy media row fixture and the deterministic material/revision the
/// v59 backfill must derive from it, through the same domain constructors the
/// backfill uses.
struct LegacyFixture {
    media_id: &'static str,
    kind: MediaKind,
    fingerprint: &'static str,
    availability: MediaAvailability,
    title: &'static str,
    retained_at_ms: Option<u64>,
    created_at_ms: u64,
    updated_at_ms: u64,
}

impl LegacyFixture {
    fn expected(&self) -> (LearningMaterial, MaterialRevision) {
        let rendition = MediaRenditionAsset::new(
            MediaId::parse(self.media_id).unwrap(),
            self.kind,
            self.fingerprint,
            self.availability,
        )
        .unwrap();
        let assets = vec![MaterialAsset::MediaRendition(rendition)];
        let material_id = initial_material_id(&assets).unwrap();
        let revision =
            MaterialRevision::new(material_id.clone(), self.title, assets, self.created_at_ms)
                .unwrap();
        let material = LearningMaterial::new(
            &revision,
            self.retained_at_ms,
            self.created_at_ms,
            self.updated_at_ms,
        )
        .unwrap();
        (material, revision)
    }
}

#[test]
fn v59_backfills_legacy_media_rows_into_durable_learning_materials() {
    // A representative v58 upgrade: retained and temporary media rows, a
    // whitespace-only historical title, a detached (missing) rendition, plus
    // representative legacy state (media row, playback progress, subtitle
    // track, learner history) that the backfill must never touch.
    let connection = Connection::open_in_memory().unwrap();
    migrate(&connection).unwrap();
    drop_v59_learning_material_tables(&connection);
    connection.pragma_update(None, "user_version", 58).unwrap();
    connection
        .execute_batch(
            r#"
            INSERT INTO media_items
              (id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms,availability,retained_at_ms)
            VALUES
              ('retained-media','/tmp/retained.mp4','fp-retained','Retained Media','"video"',NULL,1000,2000,'"available"',1500),
              ('temp-media','/tmp/temp.mp4','fp-temp','Temporary','"audio"',NULL,3000,4000,'"available"',NULL),
              ('blank-title','/tmp/blank.mp4','fp-blank','   ','"video"',NULL,5000,6000,'"available"',5000),
              ('archived-media','lltimeline://archived','fp-archived','Archived','"audio"',NULL,7000,8000,'"missing"',NULL);
            INSERT INTO playback_progress (media_id,position_ms,updated_at_ms)
              VALUES ('retained-media',1234,1500);
            INSERT INTO subtitle_tracks (id,media_id,fingerprint,language,source,status)
              VALUES ('retained-track','retained-media','track-fp',NULL,'test','"available"');
            INSERT INTO learning_events
              (id,occurred_at_ms,kind,subject_kind,subject_id,event_json)
            VALUES
              ('history-event',1600,'"familiar_material_marked"','"media"','retained-media','{}');
            "#,
        )
        .unwrap();

    migrate(&connection).unwrap();

    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        MIGRATION_VERSION
    );

    // The deterministic expectations: one material per legacy row, with the
    // blank title replaced by the documented fallback and the detached
    // availability snapshot preserved.
    let expected: Vec<(LearningMaterial, MaterialRevision)> = [
        LegacyFixture {
            media_id: "archived-media",
            kind: MediaKind::Audio,
            fingerprint: "fp-archived",
            availability: MediaAvailability::Missing,
            title: "Archived",
            retained_at_ms: None,
            created_at_ms: 7000,
            updated_at_ms: 8000,
        },
        LegacyFixture {
            media_id: "blank-title",
            kind: MediaKind::Video,
            fingerprint: "fp-blank",
            availability: MediaAvailability::Available,
            title: LEGACY_BLANK_TITLE_FALLBACK,
            retained_at_ms: Some(5000),
            created_at_ms: 5000,
            updated_at_ms: 6000,
        },
        LegacyFixture {
            media_id: "retained-media",
            kind: MediaKind::Video,
            fingerprint: "fp-retained",
            availability: MediaAvailability::Available,
            title: "Retained Media",
            retained_at_ms: Some(1500),
            created_at_ms: 1000,
            updated_at_ms: 2000,
        },
        LegacyFixture {
            media_id: "temp-media",
            kind: MediaKind::Audio,
            fingerprint: "fp-temp",
            availability: MediaAvailability::Available,
            title: "Temporary",
            retained_at_ms: None,
            created_at_ms: 3000,
            updated_at_ms: 4000,
        },
    ]
    .into_iter()
    .map(|fixture| fixture.expected())
    .collect();
    let expected_ids: Vec<String> = {
        let mut ids: Vec<String> = expected
            .iter()
            .map(|(material, _)| material.id.as_str().to_owned())
            .collect();
        ids.sort();
        ids
    };
    let stored_ids: Vec<String> = {
        let mut statement = connection
            .prepare("SELECT id FROM learning_materials ORDER BY id")
            .unwrap();
        statement
            .query_map([], |row| row.get::<_, String>(0))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
    };
    assert_eq!(
        stored_ids, expected_ids,
        "graph material ids must be deterministic"
    );

    // Material rows: current revision pointer, exact membership mirroring of
    // `retained_at_ms`, and preserved timestamps.
    for (material, revision) in &expected {
        let (current_revision_id, retained_at_ms, created_at_ms, updated_at_ms): (
            String,
            Option<u64>,
            u64,
            u64,
        ) = connection
            .query_row(
                "SELECT current_revision_id, retained_at_ms, created_at_ms, updated_at_ms
                 FROM learning_materials WHERE id=?1",
                [material.id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();
        assert_eq!(current_revision_id, revision.id.as_str());
        assert_eq!(retained_at_ms, material.retained_at_ms);
        assert_eq!(created_at_ms, material.created_at_ms);
        assert_eq!(updated_at_ms, material.updated_at_ms);
    }

    // Revision rows: exact title (including the blank-title fallback) and the
    // material's own creation timestamp.
    for (material, revision) in &expected {
        let (material_id, title, created_at_ms): (String, String, u64) = connection
            .query_row(
                "SELECT material_id, title, created_at_ms
                 FROM material_revisions WHERE id=?1",
                [revision.id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .unwrap();
        assert_eq!(material_id, material.id.as_str());
        assert_eq!(title, revision.title);
        assert_eq!(created_at_ms, revision.created_at_ms);
    }

    // Asset rows: one media_rendition at ordinal 0 whose typed JSON snapshots
    // id/kind/fingerprint/availability and never carries the media path.
    for (_, revision) in &expected {
        let asset = revision.assets.first().unwrap();
        let MaterialAsset::MediaRendition(rendition) = asset else {
            panic!("legacy backfill must produce a media rendition asset");
        };
        let (ordinal, asset_id, asset_kind, asset_json): (i64, String, String, String) = connection
            .query_row(
                "SELECT ordinal, asset_id, asset_kind, asset_json
                     FROM material_assets WHERE revision_id=?1",
                [revision.id.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();
        assert_eq!(ordinal, 0);
        assert_eq!(asset_id, asset.id().as_str());
        assert_eq!(asset_kind, "media_rendition");
        let parsed: serde_json::Value = serde_json::from_str(&asset_json).unwrap();
        assert_eq!(parsed, serde_json::to_value(asset).unwrap());
        let typed = parsed.get("media_rendition").expect("typed asset JSON");
        assert_eq!(
            typed["media_id"],
            serde_json::to_value(&rendition.media_id).unwrap()
        );
        assert_eq!(typed["kind"], serde_json::to_value(rendition.kind).unwrap());
        assert_eq!(
            typed["fingerprint"],
            serde_json::json!(rendition.fingerprint)
        );
        assert_eq!(
            typed["availability"],
            serde_json::to_value(rendition.availability).unwrap()
        );
        let object = typed.as_object().expect("media rendition object");
        assert!(
            !object.contains_key("path"),
            "asset JSON must never carry the media path"
        );
        for key in ["id", "media_id", "kind", "fingerprint", "availability"] {
            assert!(object.contains_key(key), "missing typed asset key: {key}");
        }
    }

    // Media bindings: every legacy media id resolves to exactly its material,
    // and the binding deliberately carries no FK to `media_items` (only the
    // material parent).
    for (_, revision) in &expected {
        let MaterialAsset::MediaRendition(rendition) = revision.assets.first().unwrap() else {
            unreachable!("legacy backfill produces media renditions only");
        };
        let material_id: String = connection
            .query_row(
                "SELECT material_id FROM material_media_bindings WHERE media_id=?1",
                [rendition.media_id.as_str()],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(material_id, revision.material_id.as_str());
    }
    let binding_fks: Vec<(String, String)> = {
        let mut statement = connection
            .prepare("SELECT \"table\", \"from\" FROM pragma_foreign_key_list('material_media_bindings')")
            .unwrap();
        statement
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap()
    };
    assert_eq!(
        binding_fks,
        vec![("learning_materials".to_owned(), "material_id".to_owned())]
    );

    // Legacy state is untouched: media rows, playback progress, subtitle
    // tracks, and learner history survive the backfill unchanged.
    let (path, retained_at_ms, created_at_ms): (String, Option<u64>, u64) = connection
        .query_row(
            "SELECT path, retained_at_ms, created_at_ms FROM media_items
             WHERE id='retained-media'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(path, "/tmp/retained.mp4");
    assert_eq!(retained_at_ms, Some(1500));
    assert_eq!(created_at_ms, 1000);
    assert_eq!(
        connection
            .query_row(
                "SELECT position_ms FROM playback_progress WHERE media_id='retained-media'",
                [],
                |row| row.get::<_, u64>(0),
            )
            .unwrap(),
        1234
    );
    for (table, expected_count) in [
        ("media_items", 4_u32),
        ("subtitle_tracks", 1),
        ("learning_events", 1),
    ] {
        assert_eq!(
            connection
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                    row.get::<_, u32>(0)
                })
                .unwrap(),
            expected_count,
            "{table} must be preserved"
        );
    }

    // Idempotency: retrying the v59 upgrade (user_version reset) and directly
    // re-running the backfill inside an explicit transaction must not
    // duplicate any graph rows.
    connection.pragma_update(None, "user_version", 58).unwrap();
    migrate(&connection).unwrap();
    {
        let tx = connection.unchecked_transaction().unwrap();
        backfill_legacy_media_materials(&tx).unwrap();
        tx.commit().unwrap();
    }
    for table in [
        "learning_materials",
        "material_revisions",
        "material_assets",
        "material_media_bindings",
    ] {
        assert_eq!(
            connection
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                    row.get::<_, u32>(0)
                })
                .unwrap(),
            4,
            "{table} must stay idempotent across retries"
        );
    }
}

#[test]
fn v59_backfill_rejects_invalid_legacy_media_rows_without_partial_persistence() {
    // A legacy row that cannot become a valid material (blank fingerprint
    // fails `MediaRenditionAsset::new`) converts into the repository migration
    // error path: the whole v59 transaction rolls back atomically instead of
    // silently dropping the invalid row or persisting partial state.
    let connection = Connection::open_in_memory().unwrap();
    migrate(&connection).unwrap();
    drop_v59_learning_material_tables(&connection);
    connection.pragma_update(None, "user_version", 58).unwrap();
    connection
        .execute_batch(
            r#"
            INSERT INTO media_items
              (id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms,availability,retained_at_ms)
            VALUES
              ('good-media','/tmp/good.mp4','fp-good','Good','"video"',NULL,1,2,'"available"',1),
              ('bad-media','/tmp/bad.mp4','','Bad','"video"',NULL,1,2,'"available"',1);
            "#,
        )
        .unwrap();

    assert!(migrate(&connection).is_err());

    // The failed migration rolled back atomically: the schema version never
    // advanced, no graph table (or learning-material schema) survived, and no
    // legacy row was touched.
    assert_eq!(
        connection
            .query_row("PRAGMA user_version", [], |row| row.get::<_, u32>(0))
            .unwrap(),
        58
    );
    for table in [
        "learning_materials",
        "material_revisions",
        "material_assets",
        "material_media_bindings",
    ] {
        assert!(
            !table_exists(&connection, table),
            "{table} must not survive the rolled-back migration"
        );
    }
    assert_eq!(
        connection
            .query_row("SELECT COUNT(*) FROM media_items", [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap(),
        2
    );
}
