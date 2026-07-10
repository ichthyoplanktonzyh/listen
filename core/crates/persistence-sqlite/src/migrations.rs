use domain::{
    CapabilityDimensionState, CapabilityStateChangeKind, LearningStatus, LexicalCapability,
    LexicalCapabilityHistory, LexicalCapabilityHistoryId, LexicalCapabilityProfile, LexicalEntryId,
    ObservationOrigin, ObservationResult, learning_observation_id, observation_spec_for_marking,
};
use rusqlite::{Connection, params};

use super::PersistenceError;

// v25 is reserved by Phase 3.4.2 (independent branch); this repository jumps
// 24 -> 26 per the "later lander renumbers" rule recorded in the 3.5 plan.
pub const MIGRATION_VERSION: u32 = 30;

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
    Ok(())
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
