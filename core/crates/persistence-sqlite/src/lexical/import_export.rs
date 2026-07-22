//! Bulk import/export and capability-state persistence for lexical assets.
//! Split out of `lexical.rs` (mechanical decomposition).

use application::{ApplicationError, LexicalCapabilityRepository, LexicalEntryRepository};
use domain::{
    CapabilityDimensionState, CapabilityStateChangeKind, LearningChangeSource, LearningObservation,
    LexicalCapability, LexicalCapabilityProfile, LexicalEntry, LexicalEntryId, LexicalObservation,
    LexicalOccurrence, LexicalOccurrenceId, LexicalSenseFolder, LexicalSenseFolderOccurrence,
    LexicalSenseId, LexicalStatusHistory, lexical_observation_id,
};
use rusqlite::{OptionalExtension, params};
use std::collections::HashMap;

use super::LexicalAssets;
use super::capability::{
    merge_capability_dimension, read_capability_state, write_capability_history,
    write_capability_state,
};
use super::rows::{
    learning_observation_row, lexical_entry_row, lexical_history_row, lexical_observation_row,
    lexical_occurrence_row,
};
use crate::{SqliteRepository, json, repo};

impl SqliteRepository {
    pub(super) fn import_lexical_sense_folder_assets(
        &self,
        folders: &[LexicalSenseFolder],
        assignments: &[LexicalSenseFolderOccurrence],
    ) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        for folder in folders {
            let entry_exists = tx
                .query_row(
                    "SELECT 1 FROM lexical_entries WHERE id=?1",
                    [folder.lexical_entry_id.as_str()],
                    |_| Ok(()),
                )
                .optional()
                .map_err(repo)?
                .is_some();
            if !entry_exists {
                continue;
            }
            tx.execute(
                "INSERT OR IGNORE INTO lexical_sense_folders
                 (id,lexical_entry_id,label,definition,gloss,external_ref,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
                params![
                    folder.id.as_str(), folder.lexical_entry_id.as_str(), folder.label,
                    folder.definition, folder.gloss, folder.external_ref, folder.created_at_ms,
                    folder.updated_at_ms,
                ],
            )
            .map_err(repo)?;
        }
        for assignment in assignments {
            // Missing or cross-entry imported edges are skipped rather than
            // fabricating data. The entry-agreement predicate must live here in
            // the SELECT: the migration triggers RAISE(ABORT), which `OR
            // IGNORE` does not downgrade, so relying on them would fail the
            // whole import instead of skipping the one corrupt edge.
            tx.execute(
                "INSERT OR IGNORE INTO lexical_sense_folder_occurrences
                 (lexical_sense_id,lexical_occurrence_id)
                 SELECT ?1,?2
                 WHERE (SELECT lexical_entry_id FROM lexical_sense_folders WHERE id=?1)
                     = (SELECT lexical_entry_id FROM lexical_occurrences WHERE id=?2)",
                params![
                    assignment.lexical_sense_id.as_str(),
                    assignment.lexical_occurrence_id.as_str(),
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    pub(crate) fn export_lexical_assets(&self) -> Result<LexicalAssets, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let entries = {
            let mut statement = conn
                .prepare(
                    "SELECT id,language,kind,granularity,normalization,normalized_key,
                            canonical_form,normalized_form,display_form,status,
                            user_definition,personal_note,normalization_provider,normalization_version,
                            user_corrected,updated_at_ms,learning_updated_at_ms FROM lexical_entries",
                )
                .map_err(repo)?;
            statement
                .query_map([], lexical_entry_row)
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        let history = {
            let mut statement = conn
                .prepare(
                    "SELECT id,lexical_entry_id,previous_status,new_status,changed_at_ms,change_source
                     FROM lexical_status_history",
                )
                .map_err(repo)?;
            statement
                .query_map([], lexical_history_row)
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        let occurrences = {
            let mut statement = conn
                .prepare(
                    "SELECT id,source_key,lexical_entry_id,media_id,sentence_id,original_form,
                            sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,
                            start_ms_snapshot,end_ms_snapshot,token_start,token_end,first_seen_at_ms,
                            last_seen_at_ms,encounter_count FROM lexical_occurrences",
                )
                .map_err(repo)?;
            statement
                .query_map([], lexical_occurrence_row)
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        let observations = {
            let mut statement = conn
                .prepare(
                    "SELECT id,lexical_entry_id,COALESCE(sentence_id,sentence_id_snapshot),
                            original_form,result,created_at_ms
                     FROM lexical_observations WHERE cleared_at_ms IS NULL",
                )
                .map_err(repo)?;
            statement
                .query_map([], lexical_observation_row)
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        Ok((entries, history, occurrences, observations))
    }

    pub(crate) fn import_lexical_assets(
        &self,
        entries: &[LexicalEntry],
        history: &[LexicalStatusHistory],
        occurrences: &[LexicalOccurrence],
        observations: &[LexicalObservation],
    ) -> Result<(), ApplicationError> {
        let mut imported_ids = HashMap::new();
        for entry in entries {
            let local =
                self.lexical_entry_by_key(&entry.language, entry.kind, &entry.unit.normalized_key)?;
            let merged = merge_imported_entry(local.as_ref(), entry);
            let details = self.upsert_lexical_entry(&merged, None, LearningChangeSource::Import)?;
            imported_ids.insert(entry.id.clone(), details.entry.id);
        }
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        for value in history {
            let lexical_entry_id = imported_ids
                .get(&value.lexical_entry_id)
                .unwrap_or(&value.lexical_entry_id);
            tx.execute(
                "INSERT OR IGNORE INTO lexical_status_history
                 (id,lexical_entry_id,previous_status,new_status,changed_at_ms,change_source)
                 VALUES (?1,?2,?3,?4,?5,?6)",
                params![
                    value.id.as_str(),
                    lexical_entry_id.as_str(),
                    value.previous_status.map(|item| json(&item)).transpose()?,
                    value.new_status.map(|item| json(&item)).transpose()?,
                    value.changed_at_ms,
                    json(&value.change_source)?,
                ],
            )
            .map_err(repo)?;
        }
        for value in occurrences {
            let lexical_entry_id = imported_ids
                .get(&value.lexical_entry_id)
                .unwrap_or(&value.lexical_entry_id);
            let id = LexicalOccurrenceId::from_fingerprint(
                "lexical-occurrence",
                &format!("{}:{}", lexical_entry_id.as_str(), value.source_key),
            );
            tx.execute(
                "INSERT INTO lexical_occurrences
                 (id,source_key,lexical_entry_id,media_id,sentence_id,original_form,
                  sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,
                  start_ms_snapshot,end_ms_snapshot,token_start,token_end,first_seen_at_ms,
                  last_seen_at_ms,encounter_count)
                 VALUES (?1,?2,?3,NULL,NULL,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)
                 ON CONFLICT(lexical_entry_id,source_key) DO UPDATE SET
                   original_form=CASE WHEN excluded.last_seen_at_ms>last_seen_at_ms
                                      THEN excluded.original_form ELSE original_form END,
                   sentence_text_snapshot=CASE WHEN excluded.last_seen_at_ms>last_seen_at_ms
                                               THEN excluded.sentence_text_snapshot
                                               ELSE sentence_text_snapshot END,
                   media_title_snapshot=CASE WHEN excluded.last_seen_at_ms>last_seen_at_ms
                                             THEN excluded.media_title_snapshot
                                             ELSE media_title_snapshot END,
                   media_fingerprint_snapshot=CASE WHEN excluded.last_seen_at_ms>last_seen_at_ms
                                                   THEN excluded.media_fingerprint_snapshot
                                                   ELSE media_fingerprint_snapshot END,
                   start_ms_snapshot=CASE WHEN excluded.last_seen_at_ms>last_seen_at_ms
                                          THEN excluded.start_ms_snapshot ELSE start_ms_snapshot END,
                   end_ms_snapshot=CASE WHEN excluded.last_seen_at_ms>last_seen_at_ms
                                        THEN excluded.end_ms_snapshot ELSE end_ms_snapshot END,
                   token_start=COALESCE(token_start,excluded.token_start),
                   token_end=COALESCE(token_end,excluded.token_end),
                   first_seen_at_ms=MIN(first_seen_at_ms,excluded.first_seen_at_ms),
                   last_seen_at_ms=MAX(last_seen_at_ms,excluded.last_seen_at_ms),
                   encounter_count=MAX(encounter_count,excluded.encounter_count)",
                params![
                    id.as_str(),
                    value.source_key,
                    lexical_entry_id.as_str(),
                    value.original_form,
                    value.sentence_text_snapshot,
                    value.media_title_snapshot,
                    value.media_fingerprint_snapshot,
                    value.start_ms_snapshot,
                    value.end_ms_snapshot,
                    value.token_start,
                    value.token_end,
                    value.first_seen_at_ms,
                    value.last_seen_at_ms,
                    value.encounter_count,
                ],
            )
            .map_err(repo)?;
        }
        for value in observations {
            let lexical_entry_id = imported_ids
                .get(&value.lexical_entry_id)
                .unwrap_or(&value.lexical_entry_id);
            let id = lexical_observation_id(lexical_entry_id, &value.sentence_id);
            tx.execute(
                "INSERT OR IGNORE INTO lexical_observations
                 (id,lexical_entry_id,sentence_id,sentence_id_snapshot,original_form,result,
                  created_at_ms,cleared_at_ms)
                 VALUES (?1,?2,NULL,?3,?4,?5,?6,NULL)",
                params![
                    id.as_str(),
                    lexical_entry_id.as_str(),
                    value.sentence_id.as_str(),
                    value.original_form,
                    json(&value.result)?,
                    value.created_at_ms,
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }
}

pub(super) fn merge_imported_entry(
    local: Option<&LexicalEntry>,
    imported: &LexicalEntry,
) -> LexicalEntry {
    let Some(local) = local else {
        return imported.clone();
    };
    let mut merged = if imported.updated_at_ms > local.updated_at_ms {
        imported.clone()
    } else {
        local.clone()
    };
    merged.id = local.id.clone();
    if imported.learning_updated_at_ms > local.learning_updated_at_ms {
        merged.user_definition = imported.user_definition.clone();
        merged.personal_note = imported.personal_note.clone();
        merged.learning_updated_at_ms = imported.learning_updated_at_ms;
    } else {
        merged.user_definition = local.user_definition.clone();
        merged.personal_note = local.personal_note.clone();
        merged.learning_updated_at_ms = local.learning_updated_at_ms;
    }
    merged
}

impl SqliteRepository {
    pub(super) fn export_all_learning_observations(
        &self,
    ) -> Result<Vec<LearningObservation>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT id,lexical_entry_id,sense_id,capability,task_type,outcome,assistance,
                        surface_form,sentence_id,media_id,origin,source_ref,occurred_at_ms
                 FROM learning_observations
                 ORDER BY occurred_at_ms, id",
            )
            .map_err(repo)?;
        statement
            .query_map([], learning_observation_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    pub(super) fn import_capability_profile(
        &self,
        imported: &LexicalCapabilityProfile,
    ) -> Result<(), ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let exists = conn
            .query_row(
                "SELECT 1 FROM lexical_entries WHERE id=?1",
                [imported.lexical_entry_id.as_str()],
                |_| Ok(()),
            )
            .optional()
            .map_err(repo)?
            .is_some();
        if !exists {
            return Ok(());
        }
        for capability in LexicalCapability::ALL {
            let imported_dim = imported.dimension(capability);
            if imported_dim.projection.is_none() && imported_dim.user_override.is_none() {
                continue;
            }
            let local = read_capability_state(
                &conn,
                &imported.lexical_entry_id,
                imported.sense_id.as_ref(),
                capability,
            )?
            .unwrap_or_default();
            let merged = merge_capability_dimension(&local, imported_dim);
            if merged != local {
                let ts = merged
                    .user_override
                    .as_ref()
                    .map(|value| value.updated_at_ms)
                    .or_else(|| merged.projection.as_ref().map(|value| value.updated_at_ms))
                    .unwrap_or(0);
                write_capability_state(
                    &conn,
                    &imported.lexical_entry_id,
                    imported.sense_id.as_ref(),
                    capability,
                    &merged,
                    ts,
                )?;
            }
        }
        Ok(())
    }

    pub(super) fn update_capability_state(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
        capability: LexicalCapability,
        changed_at_ms: u64,
        change_kind: CapabilityStateChangeKind,
        update: impl FnOnce(&mut CapabilityDimensionState),
    ) -> Result<LexicalCapabilityProfile, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let exists = tx
            .query_row(
                "SELECT 1 FROM lexical_entries WHERE id=?1",
                [lexical_entry_id.as_str()],
                |_| Ok(()),
            )
            .optional()
            .map_err(repo)?
            .is_some();
        if !exists {
            return Err(ApplicationError::NotFound("lexical entry"));
        }

        let previous_state =
            read_capability_state(&tx, lexical_entry_id, sense_id, capability)?.unwrap_or_default();
        let mut new_state = previous_state.clone();
        update(&mut new_state);
        if previous_state != new_state {
            write_capability_state(
                &tx,
                lexical_entry_id,
                sense_id,
                capability,
                &new_state,
                changed_at_ms,
            )?;
            write_capability_history(
                &tx,
                lexical_entry_id,
                sense_id,
                capability,
                &previous_state,
                &new_state,
                change_kind,
                changed_at_ms,
            )?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        self.lexical_capability_profile(lexical_entry_id, sense_id)?
            .ok_or(ApplicationError::NotFound("lexical entry"))
    }
}
