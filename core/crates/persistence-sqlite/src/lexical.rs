use application::{ApplicationError, LexicalEntryRepository, LexicalSourceContext};
use domain::*;
use rusqlite::{OptionalExtension, params};
use std::collections::HashMap;

use super::{SqliteRepository, from_json, json, repo};

type LexicalAssets = (
    Vec<LexicalEntry>,
    Vec<LexicalStatusHistory>,
    Vec<LexicalOccurrence>,
);

impl SqliteRepository {
    pub(super) fn export_lexical_assets(&self) -> Result<LexicalAssets, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let entries = {
            let mut statement = conn
                .prepare(
                    "SELECT id,language,kind,canonical_form,normalized_form,display_form,status,
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
        Ok((entries, history, occurrences))
    }

    pub(super) fn import_lexical_assets(
        &self,
        entries: &[LexicalEntry],
        history: &[LexicalStatusHistory],
        occurrences: &[LexicalOccurrence],
    ) -> Result<(), ApplicationError> {
        let mut imported_ids = HashMap::new();
        for entry in entries {
            let local =
                self.lexical_entry_by_key(&entry.language, entry.kind, &entry.normalized_form)?;
            let merged = merge_imported_entry(local.as_ref(), entry);
            let details = self.upsert_lexical_entry(&merged, None, WordChangeSource::Import)?;
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

impl LexicalEntryRepository for SqliteRepository {
    fn upsert_lexical_entry(
        &self,
        entry: &LexicalEntry,
        source: Option<&LexicalSourceContext>,
        change_source: WordChangeSource,
    ) -> Result<LexicalEntryDetails, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let effective_id = tx
            .query_row(
                "SELECT id FROM lexical_entries
                 WHERE language=?1 AND kind=?2 AND normalized_form=?3",
                params![
                    entry.language.as_str(),
                    json(&entry.kind)?,
                    entry.normalized_form
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
             (id,language,kind,canonical_form,normalized_form,display_form,status,
              user_definition,personal_note,normalization_provider,normalization_version,
              user_corrected,updated_at_ms,learning_updated_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14)
             ON CONFLICT(language,kind,normalized_form) DO UPDATE SET
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
                entry.canonical_form,
                entry.normalized_form,
                entry.display_form,
                entry.status.map(|value| json(&value)).transpose()?,
                entry.user_definition,
                entry.personal_note,
                entry.normalization_provider,
                entry.normalization_version,
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
                "SELECT id,language,kind,canonical_form,normalized_form,display_form,status,
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
        Ok(Some(LexicalEntryDetails {
            entry,
            history,
            occurrences,
        }))
    }

    fn list_lexical_entries(
        &self,
        language: &LanguageCode,
        kind: Option<LexicalEntryKind>,
        status: Option<WordStatus>,
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
                       AND (?4='' OR e.normalized_form LIKE '%'||?4||'%' OR e.display_form LIKE '%'||?4||'%')
                     GROUP BY e.id
                     ORDER BY COALESCE(MAX(o.last_seen_at_ms),e.updated_at_ms) DESC,e.normalized_form
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
                "SELECT id,language,kind,canonical_form,normalized_form,display_form,status,
                        user_definition,personal_note,normalization_provider,normalization_version,
                        user_corrected,updated_at_ms,learning_updated_at_ms
                 FROM lexical_entries
                 WHERE language=?1 AND kind=?2 AND normalized_form=?3",
                params![language.as_str(), json(&kind)?, normalized_form],
                lexical_entry_row,
            )
            .optional()
            .map_err(repo)
    }
}

fn lexical_entry_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LexicalEntry> {
    Ok(LexicalEntry {
        id: LexicalEntryId::parse(row.get::<_, String>(0)?).map_err(super::domain_sql)?,
        language: LanguageCode::parse(row.get::<_, String>(1)?).map_err(super::domain_sql)?,
        kind: from_json(&row.get::<_, String>(2)?)?,
        canonical_form: row.get(3)?,
        normalized_form: row.get(4)?,
        display_form: row.get(5)?,
        status: row
            .get::<_, Option<String>>(6)?
            .map(|value| from_json(&value))
            .transpose()?,
        user_definition: row.get(7)?,
        personal_note: row.get(8)?,
        normalization_provider: row.get(9)?,
        normalization_version: row.get(10)?,
        user_corrected: row.get(11)?,
        updated_at_ms: row.get(12)?,
        learning_updated_at_ms: row.get(13)?,
    })
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
