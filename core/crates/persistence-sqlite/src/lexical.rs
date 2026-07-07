use application::{ApplicationError, LearningAssetRepository, LexicalSourceContext};
use domain::*;
use rusqlite::{OptionalExtension, params, params_from_iter};
use std::collections::HashMap;

use super::{SqliteRepository, from_json, json, repo};

type LexicalAssets = (
    Vec<LexicalEntry>,
    Vec<LexicalStatusHistory>,
    Vec<LexicalOccurrence>,
    Vec<LexicalObservation>,
);

impl SqliteRepository {
    pub(super) fn export_lexical_assets(&self) -> Result<LexicalAssets, ApplicationError> {
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

    pub(super) fn import_lexical_assets(
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

fn merge_imported_entry(local: Option<&LexicalEntry>, imported: &LexicalEntry) -> LexicalEntry {
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

impl LearningAssetRepository for SqliteRepository {
    fn lexical_capability_profile(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
    ) -> Result<Option<LexicalCapabilityProfile>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        read_capability_profile(&conn, lexical_entry_id, sense_id)
    }

    fn set_lexical_capability_projection(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
        capability: LexicalCapability,
        projection: Option<CapabilityProjection>,
        changed_at_ms: u64,
    ) -> Result<LexicalCapabilityProfile, ApplicationError> {
        let changed_at_ms = projection
            .as_ref()
            .map_or(changed_at_ms, |value| value.updated_at_ms);
        self.update_capability_state(
            lexical_entry_id,
            sense_id,
            capability,
            changed_at_ms,
            CapabilityStateChangeKind::ProjectionUpdated,
            |state| state.projection = projection,
        )
    }

    fn set_lexical_capability_override(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
        capability: LexicalCapability,
        user_override: Option<CapabilityOverride>,
        changed_at_ms: u64,
    ) -> Result<LexicalCapabilityProfile, ApplicationError> {
        let changed_at_ms = user_override
            .as_ref()
            .map_or(changed_at_ms, |value| value.updated_at_ms);
        let change_kind = if user_override.is_some() {
            CapabilityStateChangeKind::OverrideSet
        } else {
            CapabilityStateChangeKind::OverrideCleared
        };
        self.update_capability_state(
            lexical_entry_id,
            sense_id,
            capability,
            changed_at_ms,
            change_kind,
            |state| state.user_override = user_override,
        )
    }

    fn lexical_capability_history(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
    ) -> Result<Vec<LexicalCapabilityHistory>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT id,lexical_entry_id,sense_id,capability,previous_state_json,
                        new_state_json,change_kind,changed_at_ms
                 FROM lexical_capability_history
                 WHERE lexical_entry_id=?1 AND sense_id=?2
                 ORDER BY changed_at_ms DESC,id DESC",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![lexical_entry_id.as_str(), sense_key(sense_id)],
                capability_history_row,
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn upsert_lexical_entry(
        &self,
        entry: &LexicalEntry,
        source: Option<&LexicalSourceContext>,
        change_source: LearningChangeSource,
    ) -> Result<LexicalEntryDetails, ApplicationError> {
        entry.validate_unit_coherence()?;
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let effective_id = tx
            .query_row(
                "SELECT id FROM lexical_entries
                 WHERE language=?1 AND granularity=?2 AND normalization=?3 AND normalized_key=?4",
                params![
                    entry.unit.language.as_str(),
                    entry.unit.granularity.as_str(),
                    entry.unit.normalization.as_str(),
                    entry.unit.normalized_key.as_str()
                ],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(repo)?
            .map(LexicalEntryId::parse)
            .transpose()?
            .unwrap_or_else(|| entry.id.clone());
        let previous = tx
            .query_row(
                "SELECT status FROM lexical_entries WHERE id=?1",
                [effective_id.as_str()],
                |row| row.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(repo)?
            .flatten()
            .map(|value| from_json(&value))
            .transpose()
            .map_err(repo)?;
        tx.execute(
            "INSERT INTO lexical_entries
             (id,language,kind,granularity,normalization,normalized_key,
              canonical_form,normalized_form,display_form,status,
              user_definition,personal_note,normalization_provider,normalization_version,
              user_corrected,updated_at_ms,learning_updated_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17)
             ON CONFLICT(language,granularity,normalization,normalized_key) DO UPDATE SET
               kind=excluded.kind,
               canonical_form=excluded.canonical_form,
               display_form=excluded.display_form,status=excluded.status,
               user_definition=COALESCE(excluded.user_definition,user_definition),
               personal_note=COALESCE(excluded.personal_note,personal_note),
               normalization_provider=excluded.normalization_provider,
               normalization_version=excluded.normalization_version,
               user_corrected=excluded.user_corrected,
               updated_at_ms=excluded.updated_at_ms,
               learning_updated_at_ms=MAX(learning_updated_at_ms,excluded.learning_updated_at_ms)",
            params![
                effective_id.as_str(),
                entry.language.as_str(),
                json(&entry.kind)?,
                entry.unit.granularity.as_str(),
                entry.unit.normalization.as_str(),
                entry.unit.normalized_key.as_str(),
                entry.canonical_form.as_str(),
                entry.normalized_form.as_str(),
                entry.display_form.as_str(),
                entry.status.map(|value| json(&value)).transpose()?,
                entry.user_definition.as_deref(),
                entry.personal_note.as_deref(),
                entry.normalization_provider.as_str(),
                entry.normalization_version.as_str(),
                entry.user_corrected,
                entry.updated_at_ms,
                entry.learning_updated_at_ms,
            ],
        )
        .map_err(repo)?;
        if previous != entry.status {
            let id = LexicalStatusHistoryId::from_fingerprint(
                "lexical-status-history",
                &format!(
                    "{}:{}:{:?}",
                    effective_id.as_str(),
                    entry.updated_at_ms,
                    entry.status
                ),
            );
            tx.execute(
                "INSERT OR IGNORE INTO lexical_status_history
                 (id,lexical_entry_id,previous_status,new_status,changed_at_ms,change_source)
                 VALUES (?1,?2,?3,?4,?5,?6)",
                params![
                    id.as_str(),
                    effective_id.as_str(),
                    previous.map(|value| json(&value)).transpose()?,
                    entry.status.map(|value| json(&value)).transpose()?,
                    entry.updated_at_ms,
                    json(&change_source)?,
                ],
            )
            .map_err(repo)?;
        }
        if let Some(source) = source {
            let source_key = format!(
                "{}:{}:{}:{}",
                source.media_fingerprint,
                source.start_ms,
                source.end_ms,
                source
                    .token_start
                    .map_or_else(|| "-".into(), |v| v.to_string())
            );
            let id = LexicalOccurrenceId::from_fingerprint(
                "lexical-occurrence",
                &format!("{}:{source_key}", effective_id.as_str()),
            );
            tx.execute(
                "INSERT INTO lexical_occurrences
                 (id,source_key,lexical_entry_id,media_id,sentence_id,original_form,
                  sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,
                  start_ms_snapshot,end_ms_snapshot,token_start,token_end,first_seen_at_ms,
                  last_seen_at_ms,encounter_count)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?14,1)
                 ON CONFLICT(lexical_entry_id,source_key) DO UPDATE SET
                   last_seen_at_ms=excluded.last_seen_at_ms,
                   encounter_count=encounter_count+1",
                params![
                    id.as_str(),
                    source_key,
                    effective_id.as_str(),
                    source.media_id.as_ref().map(MediaId::as_str),
                    source.sentence_id.as_ref().map(SubtitleSentenceId::as_str),
                    source.original_form,
                    source.sentence_text,
                    source.media_title,
                    source.media_fingerprint,
                    source.start_ms,
                    source.end_ms,
                    source.token_start,
                    source.token_end,
                    entry.updated_at_ms,
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        self.lexical_details(&effective_id)?.ok_or_else(|| {
            ApplicationError::Repository("lexical entry missing after update".into())
        })
    }

    fn lexical_details(
        &self,
        id: &LexicalEntryId,
    ) -> Result<Option<LexicalEntryDetails>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let entry = conn
            .query_row(
                "SELECT id,language,kind,granularity,normalization,normalized_key,
                        canonical_form,normalized_form,display_form,status,
                        user_definition,personal_note,normalization_provider,normalization_version,
                        user_corrected,updated_at_ms,learning_updated_at_ms
                 FROM lexical_entries WHERE id=?1",
                [id.as_str()],
                lexical_entry_row,
            )
            .optional()
            .map_err(repo)?;
        let Some(entry) = entry else { return Ok(None) };
        let history = {
            let mut statement = conn
                .prepare(
                    "SELECT id,lexical_entry_id,previous_status,new_status,changed_at_ms,change_source
                     FROM lexical_status_history WHERE lexical_entry_id=?1 ORDER BY changed_at_ms DESC",
                )
                .map_err(repo)?;
            statement
                .query_map([id.as_str()], lexical_history_row)
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
                            last_seen_at_ms,encounter_count
                     FROM lexical_occurrences WHERE lexical_entry_id=?1 ORDER BY last_seen_at_ms DESC",
                )
                .map_err(repo)?;
            statement
                .query_map([id.as_str()], lexical_occurrence_row)
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        let capability_profile = read_capability_profile(&conn, &id, None)?;
        Ok(Some(LexicalEntryDetails {
            entry,
            history,
            occurrences,
            capability_profile,
        }))
    }

    fn list_lexical_entries(
        &self,
        language: &LanguageCode,
        kind: Option<LexicalEntryKind>,
        status: Option<LearningStatus>,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError> {
        let ids = {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
            let mut statement = conn
                .prepare(
                    "SELECT e.id FROM lexical_entries e
                     LEFT JOIN lexical_occurrences o ON o.lexical_entry_id=e.id
                     WHERE e.language=?1
                       AND (?2 IS NULL OR e.kind=?2)
                       AND (?3 IS NULL OR e.status=?3)
                       AND (?4='' OR e.normalized_key LIKE '%'||?4||'%' OR e.display_form LIKE '%'||?4||'%')
                     GROUP BY e.id
                     ORDER BY COALESCE(MAX(o.last_seen_at_ms),e.updated_at_ms) DESC,e.normalized_key
                     LIMIT ?5 OFFSET ?6",
                )
                .map_err(repo)?;
            statement
                .query_map(
                    params![
                        language.as_str(),
                        kind.map(|value| json(&value)).transpose()?,
                        status.map(|value| json(&value)).transpose()?,
                        search,
                        limit,
                        offset,
                    ],
                    |row| row.get::<_, String>(0),
                )
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        ids.into_iter()
            .map(|id| {
                self.lexical_details(&LexicalEntryId::parse(id)?)?
                    .ok_or_else(|| {
                        ApplicationError::Repository("listed lexical entry missing".into())
                    })
            })
            .collect()
    }

    fn set_lemma_override(
        &self,
        language: &LanguageCode,
        original_normalized: &str,
        corrected_normalized: &str,
        updated_at_ms: u64,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO lemma_overrides(language,original_normalized,corrected_normalized,updated_at_ms)
                 VALUES (?1,?2,?3,?4)
                 ON CONFLICT(language,original_normalized) DO UPDATE SET
                   corrected_normalized=excluded.corrected_normalized,updated_at_ms=excluded.updated_at_ms",
                params![language.as_str(), original_normalized, corrected_normalized, updated_at_ms],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn lemma_override(
        &self,
        language: &LanguageCode,
        original_normalized: &str,
    ) -> Result<Option<String>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT corrected_normalized FROM lemma_overrides WHERE language=?1 AND original_normalized=?2",
                params![language.as_str(), original_normalized],
                |row| row.get(0),
            )
            .optional()
            .map_err(repo)
    }

    fn lexical_entry_by_key(
        &self,
        language: &LanguageCode,
        kind: LexicalEntryKind,
        normalized_form: &str,
    ) -> Result<Option<LexicalEntry>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT id,language,kind,granularity,normalization,normalized_key,
                        canonical_form,normalized_form,display_form,status,
                        user_definition,personal_note,normalization_provider,normalization_version,
                        user_corrected,updated_at_ms,learning_updated_at_ms
                 FROM lexical_entries
                 WHERE language=?1 AND kind=?2 AND normalized_key=?3",
                params![language.as_str(), json(&kind)?, normalized_form],
                lexical_entry_row,
            )
            .optional()
            .map_err(repo)
    }

    fn lexical_entries_by_keys(
        &self,
        language: &LanguageCode,
        kind: LexicalEntryKind,
        normalized_forms: &[String],
    ) -> Result<Vec<LexicalEntry>, ApplicationError> {
        if normalized_forms.is_empty() {
            return Ok(Vec::new());
        }
        let placeholders = std::iter::repeat_n("?", normalized_forms.len())
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!(
            "SELECT id,language,kind,granularity,normalization,normalized_key,
                    canonical_form,normalized_form,display_form,status,
                    user_definition,personal_note,normalization_provider,normalization_version,
                    user_corrected,updated_at_ms,learning_updated_at_ms
             FROM lexical_entries
             WHERE language=? AND kind=? AND normalized_key IN ({placeholders})"
        );
        let mut values = vec![language.as_str().to_owned(), json(&kind)?];
        values.extend(normalized_forms.iter().cloned());
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn.prepare(&sql).map_err(repo)?;
        statement
            .query_map(params_from_iter(values), lexical_entry_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn create_lexical_observation(
        &self,
        observation: &LexicalObservation,
    ) -> Result<LexicalObservation, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO lexical_observations
                 (id,lexical_entry_id,sentence_id,sentence_id_snapshot,original_form,result,
                  created_at_ms,cleared_at_ms)
                 VALUES (?1,?2,?3,?3,?4,?5,?6,NULL)
                 ON CONFLICT(lexical_entry_id,sentence_id) DO UPDATE SET
                   id=excluded.id,
                   original_form=excluded.original_form,
                   result=excluded.result,
                   created_at_ms=excluded.created_at_ms,
                   cleared_at_ms=NULL",
                params![
                    observation.id.as_str(),
                    observation.lexical_entry_id.as_str(),
                    observation.sentence_id.as_str(),
                    observation.original_form,
                    json(&observation.result)?,
                    observation.created_at_ms,
                ],
            )
            .map_err(repo)?;
        Ok(observation.clone())
    }

    fn list_lexical_observations_by_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<LexicalObservation>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT id,lexical_entry_id,COALESCE(sentence_id,sentence_id_snapshot),
                        original_form,result,created_at_ms
                 FROM lexical_observations
                 WHERE sentence_id=?1 AND cleared_at_ms IS NULL
                 ORDER BY created_at_ms",
            )
            .map_err(repo)?;
        statement
            .query_map([sentence_id.as_str()], lexical_observation_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn append_learning_observation(
        &self,
        observation: &LearningObservation,
    ) -> Result<LearningObservation, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT OR IGNORE INTO learning_observations
                 (id,lexical_entry_id,sense_id,capability,task_type,outcome,assistance,
                  surface_form,sentence_id,media_id,origin,source_ref,occurred_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)",
                params![
                    observation.id.as_str(),
                    observation.lexical_entry_id.as_str(),
                    observation
                        .sense_id
                        .as_ref()
                        .map(|value| value.as_str())
                        .unwrap_or(""),
                    json(&observation.capability)?,
                    json(&observation.task_type)?,
                    json(&observation.outcome)?,
                    json(&observation.assistance)?,
                    observation.surface_form,
                    observation.sentence_id.as_ref().map(|value| value.as_str()),
                    observation.media_id.as_ref().map(|value| value.as_str()),
                    json(&observation.origin)?,
                    observation.source_ref,
                    observation.occurred_at_ms,
                ],
            )
            .map_err(repo)?;
        Ok(observation.clone())
    }

    fn list_learning_observations(
        &self,
        lexical_entry_id: &LexicalEntryId,
        capability: Option<LexicalCapability>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LearningObservation>, ApplicationError> {
        let capability_json = capability.map(|value| json(&value)).transpose()?;
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT id,lexical_entry_id,sense_id,capability,task_type,outcome,assistance,
                        surface_form,sentence_id,media_id,origin,source_ref,occurred_at_ms
                 FROM learning_observations
                 WHERE lexical_entry_id=?1 AND (?2 IS NULL OR capability=?2)
                 ORDER BY occurred_at_ms DESC, id
                 LIMIT ?3 OFFSET ?4",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![lexical_entry_id.as_str(), capability_json, limit, offset],
                learning_observation_row,
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn clear_lexical_observation(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE lexical_observations SET cleared_at_ms=unixepoch('subsec') * 1000
                 WHERE lexical_entry_id=?1 AND sentence_id=?2",
                params![lexical_entry_id.as_str(), sentence_id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }

    fn update_lexical_learning_content(
        &self,
        id: &LexicalEntryId,
        user_definition: Option<String>,
        personal_note: Option<String>,
        updated_at_ms: u64,
    ) -> Result<LexicalEntryDetails, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE lexical_entries
                 SET user_definition=?2,personal_note=?3,learning_updated_at_ms=?4
                 WHERE id=?1",
                params![
                    id.as_str(),
                    user_definition.as_deref(),
                    personal_note.as_deref(),
                    updated_at_ms,
                ],
            )
            .map_err(repo)?;
        self.lexical_details(id)?
            .ok_or(ApplicationError::NotFound("lexical entry"))
    }

    fn export_assets(&self) -> Result<VocabularyAssetBundle, ApplicationError> {
        let (lexical_entries, lexical_history, lexical_occurrences, lexical_observations) =
            self.export_lexical_assets()?;
        let capability_profiles = self.export_all_capability_profiles()?;
        let learning_observations = self.export_all_learning_observations()?;
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        Ok(VocabularyAssetBundle {
            version: 6,
            exported_at_ms: application::now_ms(),
            lexical_entries,
            lexical_history,
            lexical_occurrences,
            lexical_observations,
            phonetic_finding_feedback: read_all_phonetic_feedback(&conn)?,
            capability_profiles,
            learning_observations,
        })
    }

    fn import_assets(&self, bundle: &VocabularyAssetBundle) -> Result<(), ApplicationError> {
        self.import_lexical_assets(
            &bundle.lexical_entries,
            &bundle.lexical_history,
            &bundle.lexical_occurrences,
            &bundle.lexical_observations,
        )?;
        for profile in &bundle.capability_profiles {
            self.import_capability_profile(profile)?;
        }
        // Append-only ids make observation merge trivially idempotent
        // (ADR 0017 decision 6); rows for entries absent locally are skipped
        // by the same existence rule as capability profiles.
        for observation in &bundle.learning_observations {
            let exists = {
                let conn = self.connection.lock().expect("sqlite mutex poisoned");
                conn.query_row(
                    "SELECT 1 FROM lexical_entries WHERE id=?1",
                    [observation.lexical_entry_id.as_str()],
                    |_| Ok(()),
                )
                .optional()
                .map_err(repo)?
                .is_some()
            };
            if exists {
                self.append_learning_observation(observation)?;
            }
        }
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        for feedback in &bundle.phonetic_finding_feedback {
            tx.execute(
                "INSERT INTO phonetic_finding_feedback(finding_id,feedback_json,updated_at_ms)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(finding_id) DO UPDATE SET
                   feedback_json=CASE
                     WHEN excluded.updated_at_ms>updated_at_ms THEN excluded.feedback_json
                     ELSE feedback_json END,
                   updated_at_ms=MAX(updated_at_ms,excluded.updated_at_ms)",
                params![
                    feedback.finding_id.as_str(),
                    json(feedback)?,
                    feedback.updated_at_ms
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn export_all_capability_profiles(
        &self,
    ) -> Result<Vec<LexicalCapabilityProfile>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = conn
            .prepare(
                "SELECT lexical_entry_id,sense_id,capability,projection_json,override_json
                 FROM lexical_capability_states
                 ORDER BY lexical_entry_id,sense_id,capability",
            )
            .map_err(repo)?;
        let rows = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    from_json::<LexicalCapability>(&row.get::<_, String>(2)?)?,
                    row.get::<_, Option<String>>(3)?
                        .map(|value| from_json(&value))
                        .transpose()?,
                    row.get::<_, Option<String>>(4)?
                        .map(|value| from_json(&value))
                        .transpose()?,
                ))
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;

        let mut profiles: Vec<LexicalCapabilityProfile> = Vec::new();
        for (entry_id_str, sense_id_str, capability, projection, user_override) in rows {
            let entry_id = LexicalEntryId::parse(entry_id_str)?;
            let sense_id = if sense_id_str.is_empty() {
                None
            } else {
                Some(LexicalSenseId::parse(sense_id_str)?)
            };
            let needs_new = profiles.last().is_none_or(|last| {
                last.lexical_entry_id != entry_id || last.sense_id != sense_id
            });
            if needs_new {
                let mut profile = LexicalCapabilityProfile::unassessed(entry_id);
                profile.sense_id = sense_id;
                profiles.push(profile);
            }
            let profile = profiles.last_mut().unwrap();
            *profile.dimension_mut(capability) = CapabilityDimensionState {
                projection,
                user_override,
            };
        }
        Ok(profiles)
    }
}

impl SqliteRepository {
    fn export_all_learning_observations(
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

    fn import_capability_profile(
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

    fn update_capability_state(
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

fn sense_key(sense_id: Option<&LexicalSenseId>) -> &str {
    sense_id.map_or("", LexicalSenseId::as_str)
}

fn read_capability_profile(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
    sense_id: Option<&LexicalSenseId>,
) -> Result<Option<LexicalCapabilityProfile>, ApplicationError> {
    let exists = conn
        .query_row(
            "SELECT 1 FROM lexical_entries WHERE id=?1",
            [lexical_entry_id.as_str()],
            |_| Ok(()),
        )
        .optional()
        .map_err(repo)?
        .is_some();
    if !exists {
        return Ok(None);
    }
    let mut profile = LexicalCapabilityProfile::unassessed(lexical_entry_id.clone());
    profile.sense_id = sense_id.cloned();
    let mut statement = conn
        .prepare(
            "SELECT capability,projection_json,override_json
             FROM lexical_capability_states
             WHERE lexical_entry_id=?1 AND sense_id=?2",
        )
        .map_err(repo)?;
    let rows = statement
        .query_map(
            params![lexical_entry_id.as_str(), sense_key(sense_id)],
            |row| {
                Ok((
                    from_json::<LexicalCapability>(&row.get::<_, String>(0)?)?,
                    row.get::<_, Option<String>>(1)?
                        .map(|value| from_json(&value))
                        .transpose()?,
                    row.get::<_, Option<String>>(2)?
                        .map(|value| from_json(&value))
                        .transpose()?,
                ))
            },
        )
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)?;
    for (capability, projection, user_override) in rows {
        *profile.dimension_mut(capability) = CapabilityDimensionState {
            projection,
            user_override,
        };
    }
    Ok(Some(profile))
}

fn read_capability_state(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
    sense_id: Option<&LexicalSenseId>,
    capability: LexicalCapability,
) -> Result<Option<CapabilityDimensionState>, ApplicationError> {
    conn.query_row(
        "SELECT projection_json,override_json FROM lexical_capability_states
         WHERE lexical_entry_id=?1 AND sense_id=?2 AND capability=?3",
        params![
            lexical_entry_id.as_str(),
            sense_key(sense_id),
            json(&capability)?
        ],
        |row| {
            Ok(CapabilityDimensionState {
                projection: row
                    .get::<_, Option<String>>(0)?
                    .map(|value| from_json(&value))
                    .transpose()?,
                user_override: row
                    .get::<_, Option<String>>(1)?
                    .map(|value| from_json(&value))
                    .transpose()?,
            })
        },
    )
    .optional()
    .map_err(repo)
}

fn write_capability_state(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
    sense_id: Option<&LexicalSenseId>,
    capability: LexicalCapability,
    state: &CapabilityDimensionState,
    changed_at_ms: u64,
) -> Result<(), ApplicationError> {
    if state.projection.is_none() && state.user_override.is_none() {
        conn.execute(
            "DELETE FROM lexical_capability_states
             WHERE lexical_entry_id=?1 AND sense_id=?2 AND capability=?3",
            params![
                lexical_entry_id.as_str(),
                sense_key(sense_id),
                json(&capability)?
            ],
        )
        .map_err(repo)?;
        return Ok(());
    }
    conn.execute(
        "INSERT INTO lexical_capability_states
         (lexical_entry_id,sense_id,capability,projection_json,override_json,updated_at_ms)
         VALUES (?1,?2,?3,?4,?5,?6)
         ON CONFLICT(lexical_entry_id,sense_id,capability) DO UPDATE SET
           projection_json=excluded.projection_json,
           override_json=excluded.override_json,
           updated_at_ms=excluded.updated_at_ms",
        params![
            lexical_entry_id.as_str(),
            sense_key(sense_id),
            json(&capability)?,
            state.projection.as_ref().map(json).transpose()?,
            state.user_override.as_ref().map(json).transpose()?,
            changed_at_ms,
        ],
    )
    .map_err(repo)?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn write_capability_history(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
    sense_id: Option<&LexicalSenseId>,
    capability: LexicalCapability,
    previous_state: &CapabilityDimensionState,
    new_state: &CapabilityDimensionState,
    change_kind: CapabilityStateChangeKind,
    changed_at_ms: u64,
) -> Result<(), ApplicationError> {
    let fingerprint = format!(
        "{}:{}:{:?}:{:?}:{}:{}",
        lexical_entry_id.as_str(),
        sense_key(sense_id),
        capability,
        change_kind,
        changed_at_ms,
        json(new_state)?
    );
    let id =
        LexicalCapabilityHistoryId::from_fingerprint("lexical-capability-history", &fingerprint);
    conn.execute(
        "INSERT OR IGNORE INTO lexical_capability_history
         (id,lexical_entry_id,sense_id,capability,previous_state_json,new_state_json,
          change_kind,changed_at_ms)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
        params![
            id.as_str(),
            lexical_entry_id.as_str(),
            sense_key(sense_id),
            json(&capability)?,
            json(previous_state)?,
            json(new_state)?,
            json(&change_kind)?,
            changed_at_ms,
        ],
    )
    .map_err(repo)?;
    Ok(())
}

fn capability_history_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LexicalCapabilityHistory> {
    let sense_id = row.get::<_, String>(2)?;
    Ok(LexicalCapabilityHistory {
        id: LexicalCapabilityHistoryId::parse(row.get::<_, String>(0)?)
            .map_err(super::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(super::domain_sql)?,
        sense_id: if sense_id.is_empty() {
            None
        } else {
            Some(LexicalSenseId::parse(sense_id).map_err(super::domain_sql)?)
        },
        capability: from_json(&row.get::<_, String>(3)?)?,
        previous_state: from_json(&row.get::<_, String>(4)?)?,
        new_state: from_json(&row.get::<_, String>(5)?)?,
        change_kind: from_json(&row.get::<_, String>(6)?)?,
        changed_at_ms: row.get(7)?,
    })
}

fn lexical_entry_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LexicalEntry> {
    let language = LanguageCode::parse(row.get::<_, String>(1)?).map_err(super::domain_sql)?;
    let kind = from_json(&row.get::<_, String>(2)?)?;
    let granularity = row.get::<_, String>(3)?;
    let normalization = row.get::<_, String>(4)?;
    let normalized_key = row.get::<_, String>(5)?;
    let display_form = row.get::<_, String>(8)?;
    let entry = LexicalEntry {
        id: LexicalEntryId::parse(row.get::<_, String>(0)?).map_err(super::domain_sql)?,
        unit: LexicalUnit::new(
            language.clone(),
            granularity,
            normalization,
            normalized_key,
            display_form.clone(),
        ),
        language,
        kind,
        canonical_form: row.get(6)?,
        normalized_form: row.get(7)?,
        display_form,
        status: row
            .get::<_, Option<String>>(9)?
            .map(|value| from_json(&value))
            .transpose()?,
        user_definition: row.get(10)?,
        personal_note: row.get(11)?,
        normalization_provider: row.get(12)?,
        normalization_version: row.get(13)?,
        user_corrected: row.get(14)?,
        updated_at_ms: row.get(15)?,
        learning_updated_at_ms: row.get(16)?,
    };
    // Reject rows whose stored kind/normalized_form projections have drifted
    // from the authoritative unit columns instead of returning divergent data.
    entry.validate_unit_coherence().map_err(super::domain_sql)?;
    Ok(entry)
}

fn lexical_history_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LexicalStatusHistory> {
    Ok(LexicalStatusHistory {
        id: LexicalStatusHistoryId::parse(row.get::<_, String>(0)?).map_err(super::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(super::domain_sql)?,
        previous_status: row
            .get::<_, Option<String>>(2)?
            .map(|value| from_json(&value))
            .transpose()?,
        new_status: row
            .get::<_, Option<String>>(3)?
            .map(|value| from_json(&value))
            .transpose()?,
        changed_at_ms: row.get(4)?,
        change_source: from_json(&row.get::<_, String>(5)?)?,
    })
}

fn lexical_occurrence_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LexicalOccurrence> {
    Ok(LexicalOccurrence {
        id: LexicalOccurrenceId::parse(row.get::<_, String>(0)?).map_err(super::domain_sql)?,
        source_key: row.get(1)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(2)?)
            .map_err(super::domain_sql)?,
        media_id: row
            .get::<_, Option<String>>(3)?
            .map(MediaId::parse)
            .transpose()
            .map_err(super::domain_sql)?,
        sentence_id: row
            .get::<_, Option<String>>(4)?
            .map(SubtitleSentenceId::parse)
            .transpose()
            .map_err(super::domain_sql)?,
        original_form: row.get(5)?,
        sentence_text_snapshot: row.get(6)?,
        media_title_snapshot: row.get(7)?,
        media_fingerprint_snapshot: row.get(8)?,
        start_ms_snapshot: row.get(9)?,
        end_ms_snapshot: row.get(10)?,
        token_start: row.get(11)?,
        token_end: row.get(12)?,
        first_seen_at_ms: row.get(13)?,
        last_seen_at_ms: row.get(14)?,
        encounter_count: row.get(15)?,
    })
}

fn lexical_observation_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LexicalObservation> {
    Ok(LexicalObservation {
        id: LexicalObservationId::parse(row.get::<_, String>(0)?).map_err(super::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(super::domain_sql)?,
        sentence_id: SubtitleSentenceId::parse(row.get::<_, String>(2)?)
            .map_err(super::domain_sql)?,
        original_form: row.get(3)?,
        result: from_json(&row.get::<_, String>(4)?)?,
        created_at_ms: row.get(5)?,
    })
}

fn learning_observation_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LearningObservation> {
    let sense_id = row.get::<_, String>(2)?;
    Ok(LearningObservation {
        id: LearningObservationId::parse(row.get::<_, String>(0)?).map_err(super::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(super::domain_sql)?,
        sense_id: if sense_id.is_empty() {
            None
        } else {
            Some(LexicalSenseId::parse(sense_id).map_err(super::domain_sql)?)
        },
        capability: from_json(&row.get::<_, String>(3)?)?,
        task_type: from_json(&row.get::<_, String>(4)?)?,
        outcome: from_json(&row.get::<_, String>(5)?)?,
        assistance: from_json(&row.get::<_, String>(6)?)?,
        surface_form: row.get(7)?,
        sentence_id: row
            .get::<_, Option<String>>(8)?
            .map(SubtitleSentenceId::parse)
            .transpose()
            .map_err(super::domain_sql)?,
        media_id: row
            .get::<_, Option<String>>(9)?
            .map(MediaId::parse)
            .transpose()
            .map_err(super::domain_sql)?,
        origin: from_json(&row.get::<_, String>(10)?)?,
        source_ref: row.get(11)?,
        occurred_at_ms: row.get(12)?,
    })
}

fn merge_capability_dimension(
    local: &CapabilityDimensionState,
    imported: &CapabilityDimensionState,
) -> CapabilityDimensionState {
    let projection = match (&local.projection, &imported.projection) {
        (None, p) => p.clone(),
        (p, None) => p.clone(),
        (Some(l), Some(i)) => {
            if i.updated_at_ms > l.updated_at_ms {
                Some(i.clone())
            } else {
                Some(l.clone())
            }
        }
    };
    let user_override = match (&local.user_override, &imported.user_override) {
        (None, o) => o.clone(),
        (o @ Some(_), None) => o.clone(),
        (Some(l), Some(i)) => {
            if i.updated_at_ms > l.updated_at_ms {
                Some(i.clone())
            } else {
                Some(l.clone())
            }
        }
    };
    CapabilityDimensionState {
        projection,
        user_override,
    }
}

fn read_all_phonetic_feedback(
    conn: &rusqlite::Connection,
) -> Result<Vec<PhoneticFindingFeedback>, ApplicationError> {
    let mut statement = conn
        .prepare(
            "SELECT feedback_json FROM phonetic_finding_feedback ORDER BY updated_at_ms,finding_id",
        )
        .map_err(repo)?;
    statement
        .query_map([], |row| from_json(&row.get::<_, String>(0)?))
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}
