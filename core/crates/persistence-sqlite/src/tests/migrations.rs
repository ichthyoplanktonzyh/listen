use super::*;

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
