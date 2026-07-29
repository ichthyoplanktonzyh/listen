use domain::{
    CapabilityDimensionState, CapabilityStateChangeKind, LearningStatus, LexicalCapability,
    LexicalCapabilityHistory, LexicalCapabilityHistoryId, LexicalCapabilityProfile, LexicalEntryId,
    ObservationOrigin, ObservationResult, learning_observation_id, observation_spec_for_marking,
};
use rusqlite::{Connection, params};

use super::PersistenceError;

// v25 is reserved by Phase 3.4.2 (independent branch); this repository jumps
// 24 -> 26 per the "later lander renumbers" rule recorded in the 3.5 plan.
// v33 belongs to Phase 3.8 recording_assets; v34 adds the Phase 3.9 learner
// profile after it. v35 adds the Phase 3.11 semantic task fact layer. v38 adds
// Phase 3.15 append-only writing feedback and user disposition facts. v39 adds
// the Phase 3.15.5 rebuildable production-corpus projection. v40 adds Phase
// 3.15.7 realtime provider config and local session/turn facts.
pub const MIGRATION_VERSION: u32 = 52;

pub fn migrate(connection: &Connection) -> Result<(), PersistenceError> {
    connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    let current: u32 = connection.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if current < 1 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0001_media.sql"))?;
        tx.pragma_update(None, "user_version", 1)?;
        tx.commit()?;
    }
    if current < 2 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0002_learning.sql"))?;
        tx.pragma_update(None, "user_version", 2)?;
        tx.commit()?;
    }
    if current < 3 {
        connection.execute_batch("PRAGMA foreign_keys = OFF;")?;
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))?;
        tx.pragma_update(None, "user_version", 3)?;
        tx.commit()?;
        connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    }
    if current < 4 {
        connection.execute_batch("PRAGMA foreign_keys = OFF;")?;
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0004_vocabulary_assets.sql"))?;
        tx.pragma_update(None, "user_version", 4)?;
        tx.commit()?;
        connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    }
    if current < 5 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0005_learning_experience.sql"))?;
        tx.pragma_update(None, "user_version", 5)?;
        tx.commit()?;
    }
    if current < 6 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0006_transcription.sql"))?;
        tx.pragma_update(None, "user_version", 6)?;
        tx.commit()?;
    }
    if current < 7 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0007_lexical_entries.sql"))?;
        tx.pragma_update(None, "user_version", 7)?;
        tx.commit()?;
    }
    if current < 8 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0008_pronunciation.sql"))?;
        tx.pragma_update(None, "user_version", 8)?;
        tx.commit()?;
    }
    if current < 9 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0009_phonetic_analysis.sql"))?;
        tx.pragma_update(None, "user_version", 9)?;
        tx.commit()?;
    }
    if current < 10 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0010_word_timelines.sql"))?;
        tx.pragma_update(None, "user_version", 10)?;
        tx.commit()?;
    }
    if current < 11 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0011_lltimeline_resources.sql"))?;
        tx.pragma_update(None, "user_version", 11)?;
        tx.commit()?;
    }
    if current < 12 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0012_subtitle_resource_lifecycle.sql"
        ))?;
        tx.pragma_update(None, "user_version", 12)?;
        tx.commit()?;
    }
    if current < 13 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0013_chunk_timelines.sql"))?;
        tx.pragma_update(None, "user_version", 13)?;
        tx.commit()?;
    }
    if current < 14 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0014_phone_timelines.sql"))?;
        tx.pragma_update(None, "user_version", 14)?;
        tx.commit()?;
    }
    if current < 15 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0015_learning_loop.sql"))?;
        tx.pragma_update(None, "user_version", 15)?;
        tx.commit()?;
    }
    if current < 16 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0016_destructive_lexical_reset.sql"
        ))?;
        tx.pragma_update(None, "user_version", 16)?;
        tx.commit()?;
    }
    if current < 17 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0017_drop_learning_resources.sql"
        ))?;
        tx.pragma_update(None, "user_version", 17)?;
        tx.commit()?;
    }
    if current < 18 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0018_listening_inbox.sql"))?;
        tx.pragma_update(None, "user_version", 18)?;
        tx.commit()?;
    }
    if current < 19 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0019_review_schedule.sql"))?;
        tx.pragma_update(None, "user_version", 19)?;
        tx.commit()?;
    }
    if current < 20 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0020_hunting_candidates.sql"))?;
        tx.pragma_update(None, "user_version", 20)?;
        tx.commit()?;
    }
    if current < 21 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0021_upgrade_suggestions.sql"))?;
        tx.pragma_update(None, "user_version", 21)?;
        tx.commit()?;
    }
    if current < 22 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0022_lexical_capabilities.sql"))?;
        backfill_legacy_capabilities(&tx)?;
        tx.pragma_update(None, "user_version", 22)?;
        tx.commit()?;
    }
    if current < 23 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0023_learning_observations.sql"))?;
        backfill_legacy_observations(&tx)?;
        tx.pragma_update(None, "user_version", 23)?;
        tx.commit()?;
    }
    if current < 24 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0024_content_difficulty_profiles.sql"
        ))?;
        tx.pragma_update(None, "user_version", 24)?;
        tx.commit()?;
    }
    if current < 25 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0025_sense_group_analyses.sql"))?;
        tx.pragma_update(None, "user_version", 25)?;
        tx.commit()?;
    }
    if current < 26 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0026_media_triage_intents.sql"))?;
        tx.pragma_update(None, "user_version", 26)?;
        tx.commit()?;
    }
    if current < 27 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0027_content_fit_calibrations.sql"
        ))?;
        tx.pragma_update(None, "user_version", 27)?;
        tx.commit()?;
    }
    if current < 28 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0028_corpus_occurrences.sql"))?;
        tx.pragma_update(None, "user_version", 28)?;
        tx.commit()?;
    }
    if current < 29 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0029_corpus_fts.sql"))?;
        tx.pragma_update(None, "user_version", 29)?;
        tx.commit()?;
    }
    if current < 30 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0030_lexical_sense_folders.sql"))?;
        tx.pragma_update(None, "user_version", 30)?;
        tx.commit()?;
    }
    if current < 31 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0031_sense_folder_update_guard.sql"
        ))?;
        tx.pragma_update(None, "user_version", 31)?;
        tx.commit()?;
    }
    if current < 32 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0032_hunting_targets.sql"))?;
        tx.pragma_update(None, "user_version", 32)?;
        tx.commit()?;
    }
    if current < 33 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0033_recording_assets.sql"))?;
        tx.pragma_update(None, "user_version", 33)?;
        tx.commit()?;
    }
    if current < 34 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0034_learner_profile.sql"))?;
        tx.pragma_update(None, "user_version", 34)?;
        tx.commit()?;
    }
    if current < 35 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0035_semantic_tasks.sql"))?;
        tx.pragma_update(None, "user_version", 35)?;
        tx.commit()?;
    }
    if current < 36 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0036_llm_provider_profiles.sql"))?;
        tx.pragma_update(None, "user_version", 36)?;
        tx.commit()?;
    }
    if current < 37 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0037_reading_positions.sql"))?;
        tx.pragma_update(None, "user_version", 37)?;
        tx.commit()?;
    }
    if current < 38 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0038_writing_feedback.sql"))?;
        tx.pragma_update(None, "user_version", 38)?;
        tx.commit()?;
    }
    if current < 39 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0039_production_corpus.sql"))?;
        tx.pragma_update(None, "user_version", 39)?;
        tx.commit()?;
    }
    if current < 40 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0040_realtime_conversations.sql"
        ))?;
        tx.pragma_update(None, "user_version", 40)?;
        tx.commit()?;
    }
    if current < 41 {
        let tx = connection.unchecked_transaction()?;
        // Several migration regression fixtures deliberately lower only
        // `user_version` after constructing the latest schema. Do not rebuild
        // an already-generalized corpus table as though it still had v39's
        // `task_kind` column.
        if !table_has_column(&tx, "production_corpus_documents", "activity_kind")? {
            // Historical minimal-schema fixtures (and equivalently damaged
            // databases) can contain the v30/v31 sense-folder triggers without
            // their referenced v7 `lexical_occurrences` table. SQLite reparses
            // every trigger during ALTER TABLE, so remove those unusable guards
            // before rebuilding this unrelated projection.
            if !table_has_column(&tx, "lexical_occurrences", "id")? {
                tx.execute_batch(
                    "DROP TRIGGER IF EXISTS validate_lexical_sense_folder_occurrence_parent;
                     DROP TRIGGER IF EXISTS validate_lexical_sense_folder_occurrence_parent_update;",
                )?;
            }
            tx.execute_batch(include_str!(
                "../migrations/0041_production_corpus_sources.sql"
            ))?;
        }
        tx.pragma_update(None, "user_version", 41)?;
        tx.commit()?;
    }
    if current < 42 {
        let tx = connection.unchecked_transaction()?;
        // Historical regression fixtures lower only user_version after
        // constructing the latest schema; do not recreate an existing v42
        // projection in that artificial downgrade shape.
        if !table_has_column(&tx, "semantic_embedding_index", "source_kind")? {
            tx.execute_batch(include_str!(
                "../migrations/0042_semantic_embedding_index.sql"
            ))?;
        }
        tx.pragma_update(None, "user_version", 42)?;
        tx.commit()?;
    }
    if current < 43 {
        let tx = connection.unchecked_transaction()?;
        if !table_has_column(&tx, "user_sentence_patterns", "asset_json")? {
            tx.execute_batch(include_str!("../migrations/0043_personal_expression.sql"))?;
        }
        tx.pragma_update(None, "user_version", 43)?;
        tx.commit()?;
    }
    if current < 44 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0044_projection_review.sql"))?;
        tx.pragma_update(None, "user_version", 44)?;
        tx.commit()?;
    }
    if current < 45 {
        let has_complete_base_schema = table_exists(connection, "media_items")?;
        let recording_paths = if has_complete_base_schema {
            role_reply_recording_paths(connection)?
        } else {
            Vec::new()
        };
        let tx = connection.unchecked_transaction()?;
        // Some historical regression fixtures intentionally model a sparse
        // pre-v22 schema and therefore omit the v1 media foundation while
        // still exercising later backfills. Such a database cannot contain a
        // valid Role Reply attempt; advance it without traversing dangling FK
        // references created by the deliberately incomplete fixture.
        if has_complete_base_schema {
            if table_exists(&tx, "review_items")? {
                tx.execute(
                    "DELETE FROM review_items
                     WHERE source_kind = '\"speaking_attempt\"'
                       AND json_extract(item_json, '$.source.id') IN (
                         SELECT id FROM semantic_task_attempts
                         WHERE kind = '\"role_reply\"'
                       )",
                    [],
                )?;
            }
            tx.execute_batch(include_str!("../migrations/0045_remove_role_reply.sql"))?;
        }
        tx.pragma_update(None, "user_version", 45)?;
        tx.commit()?;
        for path in recording_paths {
            let _ = std::fs::remove_file(path);
        }
    }
    if current < 46 {
        let tx = connection.unchecked_transaction()?;
        if table_exists(&tx, "review_schedules")? {
            tx.execute_batch(include_str!("../migrations/0046_fsrs_review_schedule.sql"))?;
        }
        tx.pragma_update(None, "user_version", 46)?;
        tx.commit()?;
    }
    if current < 47 {
        let tx = connection.unchecked_transaction()?;
        if table_exists(&tx, "review_items")? && !table_exists(&tx, "review_settings")? {
            tx.execute_batch(include_str!("../migrations/0047_review_capabilities.sql"))?;
        }
        tx.pragma_update(None, "user_version", 47)?;
        tx.commit()?;
    }
    if current < 48 {
        let tx = connection.unchecked_transaction()?;
        if table_exists(&tx, "anki_review_items")?
            && !table_has_column(&tx, "anki_review_items", "card_ordinal")?
        {
            tx.execute_batch(include_str!("../migrations/0048_anki_card_identity.sql"))?;
        }
        tx.pragma_update(None, "user_version", 48)?;
        tx.commit()?;
    }
    if current < 49 {
        let tx = connection.unchecked_transaction()?;
        if table_exists(&tx, "recording_assets")? && !table_exists(&tx, "shadowing_analyses")? {
            tx.execute_batch(include_str!("../migrations/0049_shadowing_analyses.sql"))?;
        }
        tx.pragma_update(None, "user_version", 49)?;
        tx.commit()?;
    }
    if current < 50 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0050_llm_sentence_checkpoints.sql"
        ))?;
        tx.pragma_update(None, "user_version", 50)?;
        tx.commit()?;
    }
    if current < 51 {
        let tx = connection.unchecked_transaction()?;
        if !table_exists(&tx, "background_jobs")? {
            tx.execute_batch(include_str!("../migrations/0051_background_jobs.sql"))?;
        }
        tx.pragma_update(None, "user_version", 51)?;
        tx.commit()?;
    }
    if current < 52 {
        let tx = connection.unchecked_transaction()?;
        if !table_exists(&tx, "pending_secret_cleanups")? {
            tx.execute_batch(include_str!(
                "../migrations/0052_pending_secret_cleanups.sql"
            ))?;
        }
        tx.pragma_update(None, "user_version", 52)?;
        tx.commit()?;
    }
    Ok(())
}

fn role_reply_recording_paths(connection: &Connection) -> Result<Vec<String>, PersistenceError> {
    if !table_exists(connection, "semantic_task_attempts")?
        || !table_exists(connection, "recording_assets")?
    {
        return Ok(Vec::new());
    }
    let mut statement = connection.prepare(
        "SELECT DISTINCT recording.file_path
         FROM semantic_task_attempts AS attempt,
              json_each(attempt.attempt_json, '$.responses') AS response
         JOIN recording_assets AS recording
           ON recording.id = json_extract(response.value, '$.recording_asset_id')
         WHERE attempt.kind = '\"role_reply\"'",
    )?;
    Ok(statement
        .query_map([], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?)
}

fn table_exists(connection: &Connection, table: &str) -> Result<bool, PersistenceError> {
    Ok(connection.query_row(
        "SELECT EXISTS(
           SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1
         )",
        [table],
        |row| row.get(0),
    )?)
}

fn table_has_column(
    connection: &Connection,
    table: &str,
    column: &str,
) -> Result<bool, PersistenceError> {
    let mut statement = connection.prepare(&format!("PRAGMA table_info({table})"))?;
    let columns = statement
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(columns.iter().any(|name| name == column))
}

/// ADR 0017 decision 5: one channelized observation per legacy uncleared
/// LexicalObservation, marked `legacy_backfill` because the latest-wins legacy
/// table mixed user markings with practice failures and kept no history.
pub(crate) fn backfill_legacy_observations(
    connection: &Connection,
) -> Result<(), PersistenceError> {
    let mut statement = connection.prepare(
        "SELECT id,lexical_entry_id,sentence_id_snapshot,original_form,result,created_at_ms
         FROM lexical_observations WHERE cleared_at_ms IS NULL",
    )?;
    let rows = statement
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                serde_json::from_str::<ObservationResult>(&row.get::<_, String>(4)?)
                    .map_err(json_sql)?,
                row.get::<_, u64>(5)?,
            ))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    for (legacy_id, entry_id, sentence_id, original_form, result, created_at_ms) in rows {
        let entry_id = LexicalEntryId::parse(entry_id).map_err(super::domain_sql)?;
        let spec = observation_spec_for_marking(result);
        let id = learning_observation_id(
            &entry_id,
            spec.task_type,
            spec.outcome,
            Some(&legacy_id),
            created_at_ms,
        );
        connection.execute(
            "INSERT OR IGNORE INTO learning_observations
             (id,lexical_entry_id,sense_id,capability,task_type,outcome,assistance,
              surface_form,sentence_id,media_id,origin,source_ref,occurred_at_ms)
             VALUES (?1,?2,'',?3,?4,?5,?6,?7,?8,NULL,?9,?10,?11)",
            params![
                id.as_str(),
                entry_id.as_str(),
                serde_json::to_string(&spec.capability).map_err(json_sql)?,
                serde_json::to_string(&spec.task_type).map_err(json_sql)?,
                serde_json::to_string(&spec.outcome).map_err(json_sql)?,
                serde_json::to_string(&spec.assistance).map_err(json_sql)?,
                original_form,
                sentence_id,
                serde_json::to_string(&ObservationOrigin::LegacyBackfill).map_err(json_sql)?,
                legacy_id,
                created_at_ms,
            ],
        )?;
    }
    Ok(())
}

fn backfill_legacy_capabilities(connection: &Connection) -> Result<(), PersistenceError> {
    let legacy_entries = {
        let mut statement = connection.prepare(
            "SELECT id,status,CASE WHEN learning_updated_at_ms>0
                                   THEN learning_updated_at_ms ELSE updated_at_ms END
             FROM lexical_entries WHERE status IS NOT NULL",
        )?;
        statement
            .query_map([], |row| {
                let id =
                    LexicalEntryId::parse(row.get::<_, String>(0)?).map_err(super::domain_sql)?;
                let status = serde_json::from_str::<LearningStatus>(&row.get::<_, String>(1)?)
                    .map_err(|error| {
                        rusqlite::Error::FromSqlConversionFailure(
                            1,
                            rusqlite::types::Type::Text,
                            Box::new(error),
                        )
                    })?;
                Ok((id, status, row.get::<_, u64>(2)?))
            })?
            .collect::<Result<Vec<_>, _>>()?
    };

    for (lexical_entry_id, status, migrated_at_ms) in legacy_entries {
        let profile = LexicalCapabilityProfile::from_legacy_status(
            lexical_entry_id.clone(),
            Some(status),
            migrated_at_ms,
        );
        for capability in LexicalCapability::ALL {
            let state = profile.dimension(capability);
            if state.projection.is_none() {
                continue;
            }
            insert_capability_state(
                connection,
                &lexical_entry_id,
                capability,
                state,
                migrated_at_ms,
            )?;
            insert_migration_history(
                connection,
                &lexical_entry_id,
                capability,
                state,
                migrated_at_ms,
            )?;
        }
    }
    Ok(())
}

fn insert_capability_state(
    connection: &Connection,
    lexical_entry_id: &LexicalEntryId,
    capability: LexicalCapability,
    state: &CapabilityDimensionState,
    updated_at_ms: u64,
) -> Result<(), PersistenceError> {
    connection.execute(
        "INSERT INTO lexical_capability_states
         (lexical_entry_id,sense_id,capability,projection_json,override_json,updated_at_ms)
         VALUES (?1,'',?2,?3,NULL,?4)",
        params![
            lexical_entry_id.as_str(),
            serde_json::to_string(&capability).map_err(json_sql)?,
            state
                .projection
                .as_ref()
                .map(serde_json::to_string)
                .transpose()
                .map_err(json_sql)?,
            updated_at_ms,
        ],
    )?;
    Ok(())
}

fn insert_migration_history(
    connection: &Connection,
    lexical_entry_id: &LexicalEntryId,
    capability: LexicalCapability,
    new_state: &CapabilityDimensionState,
    changed_at_ms: u64,
) -> Result<(), PersistenceError> {
    let change_kind = CapabilityStateChangeKind::ProjectionUpdated;
    let history = LexicalCapabilityHistory {
        id: LexicalCapabilityHistoryId::from_fingerprint(
            "lexical-capability-history",
            &format!(
                "{}::{}:{change_kind:?}:{changed_at_ms}",
                lexical_entry_id.as_str(),
                serde_json::to_string(&capability).map_err(json_sql)?
            ),
        ),
        lexical_entry_id: lexical_entry_id.clone(),
        sense_id: None,
        capability,
        previous_state: CapabilityDimensionState::default(),
        new_state: new_state.clone(),
        change_kind,
        changed_at_ms,
    };
    connection.execute(
        "INSERT INTO lexical_capability_history
         (id,lexical_entry_id,sense_id,capability,previous_state_json,new_state_json,
          change_kind,changed_at_ms)
         VALUES (?1,?2,'',?3,?4,?5,?6,?7)",
        params![
            history.id.as_str(),
            lexical_entry_id.as_str(),
            serde_json::to_string(&capability).map_err(json_sql)?,
            serde_json::to_string(&history.previous_state).map_err(json_sql)?,
            serde_json::to_string(&history.new_state).map_err(json_sql)?,
            serde_json::to_string(&change_kind).map_err(json_sql)?,
            changed_at_ms,
        ],
    )?;
    Ok(())
}

fn json_sql(error: serde_json::Error) -> rusqlite::Error {
    rusqlite::Error::ToSqlConversionFailure(Box::new(error))
}
