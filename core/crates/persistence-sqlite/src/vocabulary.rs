use application::{
    ApplicationError, SourceContext, VocabularyAssetRepository, WordObservationRepository,
    WordProfileRepository,
};
use domain::*;
use rusqlite::{Connection, OptionalExtension, params};
use sha2::Digest;

use super::{SqliteRepository, domain_sql, from_json, json, repo};

impl WordProfileRepository for SqliteRepository {
    fn upsert(&self, p: &WordProfile) -> Result<WordProfile, ApplicationError> {
        {
            self.connection
                .lock()
                .expect("sqlite mutex poisoned")
                .execute(
                "INSERT INTO word_profiles
                 (id, language, lemma, normalized_lemma, display_form, status, updated_at_ms,
                  user_definition, personal_note, learning_updated_at_ms)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
                 ON CONFLICT(language, normalized_lemma) DO UPDATE SET
                   lemma=excluded.lemma, display_form=excluded.display_form,
                   status=excluded.status, updated_at_ms=excluded.updated_at_ms,
                   user_definition=CASE WHEN excluded.learning_updated_at_ms>=learning_updated_at_ms
                     THEN excluded.user_definition ELSE user_definition END,
                   personal_note=CASE WHEN excluded.learning_updated_at_ms>=learning_updated_at_ms
                     THEN excluded.personal_note ELSE personal_note END,
                   learning_updated_at_ms=MAX(learning_updated_at_ms,excluded.learning_updated_at_ms)",
                    params![
                        p.id.as_str(),
                        p.language.as_str(),
                        p.lemma,
                        p.normalized_lemma,
                        p.display_form,
                        p.status.map(|s| json(&s)).transpose()?,
                        p.updated_at_ms,
                        p.user_definition,
                        p.personal_note,
                        p.learning_updated_at_ms
                    ],
                )
                .map_err(repo)?;
        }
        self.get_by_key(&p.language, &p.normalized_lemma)?
            .ok_or_else(|| ApplicationError::Repository("word upsert returned no row".into()))
    }

    fn get_by_key(
        &self,
        language: &LanguageCode,
        normalized_lemma: &str,
    ) -> Result<Option<WordProfile>, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .query_row(
                "SELECT id, language, lemma, normalized_lemma, display_form, status, updated_at_ms,
                        user_definition, personal_note, learning_updated_at_ms
                 FROM word_profiles WHERE language=?1 AND normalized_lemma=?2",
                params![language.as_str(), normalized_lemma],
                |r| {
                    Ok(WordProfile {
                        id: WordProfileId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                        language: LanguageCode::parse(r.get::<_, String>(1)?)
                            .map_err(domain_sql)?,
                        lemma: r.get(2)?,
                        normalized_lemma: r.get(3)?,
                        display_form: r.get(4)?,
                        status: r
                            .get::<_, Option<String>>(5)?
                            .map(|s| from_json(&s))
                            .transpose()?,
                        updated_at_ms: r.get(6)?,
                        user_definition: r.get(7)?,
                        personal_note: r.get(8)?,
                        learning_updated_at_ms: r.get(9)?,
                    })
                },
            )
            .optional()
            .map_err(repo)
    }

    fn get_many(
        &self,
        language: &LanguageCode,
        normalized_lemmas: &[String],
    ) -> Result<Vec<WordProfile>, ApplicationError> {
        if normalized_lemmas.is_empty() {
            return Ok(vec![]);
        }
        let placeholders = std::iter::repeat_n("?", normalized_lemmas.len())
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!(
            "SELECT id, language, lemma, normalized_lemma, display_form, status, updated_at_ms,
                    user_definition, personal_note, learning_updated_at_ms
             FROM word_profiles WHERE language=? AND normalized_lemma IN ({placeholders})"
        );
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn.prepare(&sql).map_err(repo)?;
        let values =
            std::iter::once(language.as_str()).chain(normalized_lemmas.iter().map(String::as_str));
        query
            .query_map(rusqlite::params_from_iter(values), |r| {
                Ok(WordProfile {
                    id: WordProfileId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
                    language: LanguageCode::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
                    lemma: r.get(2)?,
                    normalized_lemma: r.get(3)?,
                    display_form: r.get(4)?,
                    status: r
                        .get::<_, Option<String>>(5)?
                        .map(|s| from_json(&s))
                        .transpose()?,
                    updated_at_ms: r.get(6)?,
                    user_definition: r.get(7)?,
                    personal_note: r.get(8)?,
                    learning_updated_at_ms: r.get(9)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
}

impl WordObservationRepository for SqliteRepository {
    fn create(&self, o: &WordObservation) -> Result<WordObservation, ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "INSERT INTO word_observations
                 (id, word_profile_id, sentence_id, sentence_id_snapshot, original_form, result, created_at_ms, cleared_at_ms)
                 VALUES (?1, ?2, ?3, ?3, ?4, ?5, ?6, NULL)
                 ON CONFLICT(word_profile_id, sentence_id) DO UPDATE SET
                   id=excluded.id, original_form=excluded.original_form, result=excluded.result,
                   created_at_ms=excluded.created_at_ms, cleared_at_ms=NULL",
                params![
                    o.id.as_str(),
                    o.word_profile_id.as_str(),
                    o.sentence_id.as_str(),
                    o.original_form,
                    json(&o.result)?,
                    o.created_at_ms
                ],
            )
            .map_err(repo)?;
        Ok(o.clone())
    }

    fn list_by_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordObservation>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let mut query = conn
            .prepare(
                "SELECT id, word_profile_id, sentence_id, original_form, result, created_at_ms
                 FROM word_observations WHERE sentence_id=?1 AND cleared_at_ms IS NULL ORDER BY created_at_ms",
            )
            .map_err(repo)?;
        query
            .query_map([sentence_id.as_str()], |row| {
                Ok(WordObservation {
                    id: WordObservationId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
                    word_profile_id: WordProfileId::parse(row.get::<_, String>(1)?)
                        .map_err(domain_sql)?,
                    sentence_id: SubtitleSentenceId::parse(row.get::<_, String>(2)?)
                        .map_err(domain_sql)?,
                    original_form: row.get(3)?,
                    result: from_json(&row.get::<_, String>(4)?)?,
                    created_at_ms: row.get(5)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn clear(
        &self,
        word_profile_id: &WordProfileId,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError> {
        self.connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE word_observations SET cleared_at_ms=unixepoch('subsec') * 1000
                 WHERE word_profile_id=?1 AND sentence_id=?2",
                params![word_profile_id.as_str(), sentence_id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }
}

impl VocabularyAssetRepository for SqliteRepository {
    fn apply_status(
        &self,
        profile: &WordProfile,
        source: Option<&SourceContext>,
        change_source: WordChangeSource,
    ) -> Result<WordDetails, ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let previous = tx
            .query_row(
                "SELECT status FROM word_profiles WHERE language=?1 AND normalized_lemma=?2",
                params![profile.language.as_str(), profile.normalized_lemma],
                |r| r.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(repo)?
            .flatten()
            .map(|value| from_json(&value))
            .transpose()
            .map_err(repo)?;
        tx.execute(
            "INSERT INTO word_profiles
             (id, language, lemma, normalized_lemma, display_form, status, updated_at_ms)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT(language, normalized_lemma) DO UPDATE SET
               lemma=excluded.lemma, display_form=excluded.display_form,
               status=excluded.status, updated_at_ms=excluded.updated_at_ms",
            params![
                profile.id.as_str(),
                profile.language.as_str(),
                profile.lemma,
                profile.normalized_lemma,
                profile.display_form,
                profile.status.map(|s| json(&s)).transpose()?,
                profile.updated_at_ms
            ],
        )
        .map_err(repo)?;
        let occurrence_id = source
            .map(|source| upsert_occurrence(&tx, profile, source, profile.updated_at_ms))
            .transpose()?;
        if previous != profile.status {
            let id = WordStatusHistoryId::from_fingerprint(
                "word-status-history",
                &format!(
                    "{}:{}:{previous:?}:{:?}",
                    profile.id.as_str(),
                    profile.updated_at_ms,
                    profile.status
                ),
            );
            tx.execute(
                "INSERT OR IGNORE INTO word_status_history
                 (id, word_profile_id, previous_status, new_status, source_occurrence_id,
                  changed_at_ms, change_source)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    id.as_str(),
                    profile.id.as_str(),
                    previous.map(|s| json(&s)).transpose()?,
                    profile.status.map(|s| json(&s)).transpose()?,
                    occurrence_id.as_ref().map(WordOccurrenceId::as_str),
                    profile.updated_at_ms,
                    json(&change_source)?
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        self.details(&profile.id)?
            .ok_or_else(|| ApplicationError::Repository("word details missing after update".into()))
    }

    fn capture_occurrence(
        &self,
        profile: &WordProfile,
        source: &SourceContext,
    ) -> Result<WordOccurrence, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let id = upsert_occurrence(&conn, profile, source, application::now_ms())?;
        read_occurrence(&conn, &id)?
            .ok_or_else(|| ApplicationError::Repository("occurrence missing after capture".into()))
    }

    fn list_vocabulary(
        &self,
        language: &LanguageCode,
        status: WordStatus,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<WordDetails>, ApplicationError> {
        let ids = {
            let conn = self.connection.lock().expect("sqlite mutex poisoned");
            let mut query = conn
                .prepare(
                    "SELECT p.id FROM word_profiles p
                     LEFT JOIN word_occurrences o ON o.word_profile_id=p.id
                     WHERE p.language=?1 AND p.status=?2
                       AND (?3='' OR p.normalized_lemma LIKE '%' || ?3 || '%'
                            OR p.display_form LIKE '%' || ?3 || '%')
                     GROUP BY p.id
                     ORDER BY COALESCE(MAX(o.last_seen_at_ms), p.updated_at_ms) DESC, p.normalized_lemma
                     LIMIT ?4 OFFSET ?5",
                )
                .map_err(repo)?;
            query
                .query_map(
                    params![language.as_str(), json(&status)?, search, limit, offset],
                    |r| r.get::<_, String>(0),
                )
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?
        };
        ids.into_iter()
            .map(|id| {
                let id = WordProfileId::parse(id)?;
                self.details(&id)?
                    .ok_or_else(|| ApplicationError::Repository("listed word missing".into()))
            })
            .collect()
    }

    fn details(&self, id: &WordProfileId) -> Result<Option<WordDetails>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let Some(profile) = read_profile_by_id(&conn, id)? else {
            return Ok(None);
        };
        Ok(Some(WordDetails {
            profile,
            history: read_history(&conn, id)?,
            occurrences: read_occurrences(&conn, id)?,
        }))
    }

    fn export_assets(&self) -> Result<VocabularyAssetBundle, ApplicationError> {
        let (lexical_entries, lexical_history, lexical_occurrences) =
            self.export_lexical_assets()?;
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        Ok(VocabularyAssetBundle {
            version: 4,
            exported_at_ms: application::now_ms(),
            profiles: read_all_profiles(&conn)?,
            history: read_all_history(&conn)?,
            occurrences: read_all_occurrences(&conn)?,
            observations: read_all_observations(&conn)?,
            lexical_entries,
            lexical_history,
            lexical_occurrences,
            phonetic_finding_feedback: read_all_phonetic_feedback(&conn)?,
        })
    }

    fn import_assets(&self, bundle: &VocabularyAssetBundle) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        for profile in &bundle.profiles {
            let previous = tx
                .query_row(
                    "SELECT status,updated_at_ms FROM word_profiles WHERE language=?1 AND normalized_lemma=?2",
                    params![profile.language.as_str(), profile.normalized_lemma],
                    |r| Ok((r.get::<_, Option<String>>(0)?, r.get::<_, u64>(1)?)),
                )
                .optional()
                .map_err(repo)?;
            tx.execute(
                "INSERT INTO word_profiles(id, language, lemma, normalized_lemma, display_form, status,
                  updated_at_ms,user_definition,personal_note,learning_updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)
                 ON CONFLICT(language, normalized_lemma) DO UPDATE SET
                   lemma=CASE WHEN excluded.updated_at_ms>updated_at_ms THEN excluded.lemma ELSE lemma END,
                   display_form=CASE WHEN excluded.updated_at_ms>updated_at_ms THEN excluded.display_form ELSE display_form END,
                   status=CASE WHEN excluded.updated_at_ms>updated_at_ms THEN excluded.status ELSE status END,
                   updated_at_ms=MAX(updated_at_ms, excluded.updated_at_ms),
                   user_definition=CASE WHEN excluded.learning_updated_at_ms>learning_updated_at_ms
                     THEN excluded.user_definition ELSE user_definition END,
                   personal_note=CASE WHEN excluded.learning_updated_at_ms>learning_updated_at_ms
                     THEN excluded.personal_note ELSE personal_note END,
                   learning_updated_at_ms=MAX(learning_updated_at_ms,excluded.learning_updated_at_ms)",
                params![profile.id.as_str(), profile.language.as_str(), profile.lemma,
                    profile.normalized_lemma, profile.display_form,
                    profile.status.map(|s| json(&s)).transpose()?, profile.updated_at_ms,
                    profile.user_definition,profile.personal_note,profile.learning_updated_at_ms],
            ).map_err(repo)?;
            let imported_status_json = profile.status.map(|value| json(&value)).transpose()?;
            let import_changes_status = match previous.as_ref() {
                None => profile.status.is_some(),
                Some((status, updated_at_ms)) => {
                    profile.updated_at_ms > *updated_at_ms && status != &imported_status_json
                }
            };
            if import_changes_status {
                let previous_status: Option<WordStatus> = previous
                    .as_ref()
                    .and_then(|(status, _)| status.as_ref())
                    .map(|value| from_json(value))
                    .transpose()
                    .map_err(repo)?;
                let history_id = WordStatusHistoryId::from_fingerprint(
                    "word-status-import",
                    &format!("{}:{}", profile.id.as_str(), bundle.exported_at_ms),
                );
                tx.execute(
                    "INSERT OR IGNORE INTO word_status_history
                     (id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source)
                     VALUES (?1,?2,?3,?4,NULL,?5,?6)",
                    params![
                        history_id.as_str(),
                        profile.id.as_str(),
                        previous_status.map(|s| json(&s)).transpose()?,
                        profile.status.map(|s| json(&s)).transpose()?,
                        bundle.exported_at_ms,
                        json(&WordChangeSource::Import)?
                    ],
                )
                .map_err(repo)?;
            }
        }
        for occurrence in &bundle.occurrences {
            tx.execute(
                "INSERT INTO word_occurrences
                 (id,source_key,word_profile_id,media_id,sentence_id,original_form,sentence_text_snapshot,
                  media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,end_ms_snapshot,
                  first_seen_at_ms,last_seen_at_ms,encounter_count)
                 VALUES (?1,?2,?3,NULL,NULL,?4,?5,?6,?7,?8,?9,?10,?11,?12)
                 ON CONFLICT(word_profile_id,source_key) DO UPDATE SET
                   first_seen_at_ms=MIN(first_seen_at_ms,excluded.first_seen_at_ms),
                   last_seen_at_ms=MAX(last_seen_at_ms,excluded.last_seen_at_ms),
                   encounter_count=MAX(encounter_count,excluded.encounter_count)",
                params![occurrence.id.as_str(), occurrence.source_key, occurrence.word_profile_id.as_str(),
                    occurrence.original_form, occurrence.sentence_text_snapshot, occurrence.media_title_snapshot,
                    occurrence.media_fingerprint_snapshot, occurrence.start_ms_snapshot, occurrence.end_ms_snapshot,
                    occurrence.first_seen_at_ms, occurrence.last_seen_at_ms, occurrence.encounter_count],
            ).map_err(repo)?;
        }
        for history in &bundle.history {
            tx.execute(
                "INSERT OR IGNORE INTO word_status_history
                 (id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source)
                 VALUES (?1,?2,?3,?4,?5,?6,?7)",
                params![history.id.as_str(), history.word_profile_id.as_str(),
                    history.previous_status.map(|s| json(&s)).transpose()?,
                    history.new_status.map(|s| json(&s)).transpose()?,
                    history.source_occurrence_id.as_ref().map(WordOccurrenceId::as_str),
                    history.changed_at_ms, json(&history.change_source)?],
            ).map_err(repo)?;
        }
        for observation in &bundle.observations {
            tx.execute(
                "INSERT OR IGNORE INTO word_observations
                 (id,word_profile_id,sentence_id,sentence_id_snapshot,original_form,result,created_at_ms,cleared_at_ms)
                 VALUES (?1,?2,NULL,?3,?4,?5,?6,NULL)",
                params![
                    observation.id.as_str(),
                    observation.word_profile_id.as_str(),
                    observation.sentence_id.as_str(),
                    observation.original_form,
                    json(&observation.result)?,
                    observation.created_at_ms
                ],
            )
            .map_err(repo)?;
        }
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
        tx.commit().map_err(repo)?;
        drop(conn);
        self.import_lexical_assets(
            &bundle.lexical_entries,
            &bundle.lexical_history,
            &bundle.lexical_occurrences,
        )
    }

    fn update_learning_content(
        &self,
        id: &WordProfileId,
        user_definition: Option<String>,
        personal_note: Option<String>,
        updated_at_ms: u64,
    ) -> Result<WordDetails, ApplicationError> {
        let changed = self
            .connection
            .lock()
            .expect("sqlite mutex poisoned")
            .execute(
                "UPDATE word_profiles SET user_definition=?2,personal_note=?3,learning_updated_at_ms=?4
                 WHERE id=?1",
                params![id.as_str(), user_definition, personal_note, updated_at_ms],
            )
            .map_err(repo)?;
        if changed == 0 {
            return Err(ApplicationError::NotFound("word profile"));
        }
        self.details(id)?
            .ok_or(ApplicationError::NotFound("word profile"))
    }

    fn import_external(
        &self,
        input: &ExternalVocabularyImport,
        imported_at_ms: u64,
    ) -> Result<ExternalVocabularyImportSummary, ApplicationError> {
        let language = LanguageCode::parse(input.language.clone())?;
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        let mut summary = ExternalVocabularyImportSummary::default();
        let mut seen = std::collections::BTreeSet::new();
        for entry in &input.entries {
            let normalized = normalize_lemma(&entry.word);
            if normalized.is_empty() || !seen.insert(normalized.clone()) {
                summary.invalid += 1;
                continue;
            }
            let status = entry.status.or(input.default_status);
            let previous = tx
                .query_row(
                    "SELECT id,status FROM word_profiles WHERE language=?1 AND normalized_lemma=?2",
                    params![language.as_str(), normalized],
                    |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)),
                )
                .optional()
                .map_err(repo)?;
            match previous {
                None => {
                    let id = WordProfileId::from_fingerprint(
                        "word-profile",
                        &format!("{}:{normalized}", language.as_str()),
                    );
                    tx.execute(
                        "INSERT INTO word_profiles
                         (id,language,lemma,normalized_lemma,display_form,status,updated_at_ms,
                          user_definition,personal_note,learning_updated_at_ms)
                         VALUES (?1,?2,?3,?4,?3,?5,?6,NULL,NULL,0)",
                        params![
                            id.as_str(),
                            language.as_str(),
                            entry.word.trim(),
                            normalized,
                            status.map(|value| json(&value)).transpose()?,
                            imported_at_ms
                        ],
                    )
                    .map_err(repo)?;
                    if status.is_some() {
                        insert_import_history(&tx, &id, None, status, imported_at_ms)?;
                    }
                    summary.created += 1;
                }
                Some((id, previous_json)) => {
                    let previous_status = previous_json
                        .as_ref()
                        .map(|value| from_json(value))
                        .transpose()
                        .map_err(repo)?;
                    if previous_status.is_some() && !input.overwrite_existing {
                        summary.skipped += 1;
                        continue;
                    }
                    if previous_status == status {
                        summary.skipped += 1;
                        continue;
                    }
                    tx.execute(
                        "UPDATE word_profiles SET status=?2,updated_at_ms=?3 WHERE id=?1",
                        params![
                            id,
                            status.map(|value| json(&value)).transpose()?,
                            imported_at_ms
                        ],
                    )
                    .map_err(repo)?;
                    let id = WordProfileId::parse(id)?;
                    insert_import_history(&tx, &id, previous_status, status, imported_at_ms)?;
                    if previous_status.is_none() {
                        summary.initialized += 1;
                    } else {
                        summary.overwritten += 1;
                    }
                }
            }
        }
        tx.commit().map_err(repo)?;
        Ok(summary)
    }
}

fn source_key(source: &SourceContext) -> String {
    hex::encode(sha2::Sha256::digest(format!(
        "{}:{}:{}:{}",
        source.media_fingerprint, source.start_ms, source.end_ms, source.sentence_text
    )))
}

fn insert_import_history(
    conn: &Connection,
    id: &WordProfileId,
    previous_status: Option<WordStatus>,
    new_status: Option<WordStatus>,
    changed_at_ms: u64,
) -> Result<(), ApplicationError> {
    let history_id = WordStatusHistoryId::from_fingerprint(
        "word-status-import",
        &format!("{}:{changed_at_ms}:{new_status:?}", id.as_str()),
    );
    conn.execute(
        "INSERT OR IGNORE INTO word_status_history
         (id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source)
         VALUES (?1,?2,?3,?4,NULL,?5,?6)",
        params![
            history_id.as_str(),
            id.as_str(),
            previous_status.map(|value| json(&value)).transpose()?,
            new_status.map(|value| json(&value)).transpose()?,
            changed_at_ms,
            json(&WordChangeSource::Import)?
        ],
    )
    .map(|_| ())
    .map_err(repo)
}

fn upsert_occurrence(
    conn: &Connection,
    profile: &WordProfile,
    source: &SourceContext,
    now: u64,
) -> Result<WordOccurrenceId, ApplicationError> {
    let key = source_key(source);
    let id = WordOccurrenceId::from_fingerprint(
        "word-occurrence",
        &format!("{}:{key}", profile.id.as_str()),
    );
    conn.execute(
        "INSERT INTO word_occurrences
         (id,source_key,word_profile_id,media_id,sentence_id,original_form,sentence_text_snapshot,
          media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,end_ms_snapshot,
          first_seen_at_ms,last_seen_at_ms,encounter_count)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?12,1)
         ON CONFLICT(word_profile_id,source_key) DO UPDATE SET
           media_id=COALESCE(excluded.media_id,media_id),
           sentence_id=COALESCE(excluded.sentence_id,sentence_id),
           original_form=excluded.original_form,
           sentence_text_snapshot=excluded.sentence_text_snapshot,
           media_title_snapshot=excluded.media_title_snapshot,
           media_fingerprint_snapshot=excluded.media_fingerprint_snapshot,
           last_seen_at_ms=excluded.last_seen_at_ms,
           encounter_count=encounter_count+1",
        params![
            id.as_str(),
            key,
            profile.id.as_str(),
            source.media_id.as_ref().map(MediaId::as_str),
            source.sentence_id.as_ref().map(SubtitleSentenceId::as_str),
            source.original_form,
            source.sentence_text,
            source.media_title,
            source.media_fingerprint,
            source.start_ms,
            source.end_ms,
            now
        ],
    )
    .map_err(repo)?;
    Ok(id)
}

fn read_profile_by_id(
    conn: &Connection,
    id: &WordProfileId,
) -> Result<Option<WordProfile>, ApplicationError> {
    conn.query_row(
        "SELECT id,language,lemma,normalized_lemma,display_form,status,updated_at_ms,
                user_definition,personal_note,learning_updated_at_ms
         FROM word_profiles WHERE id=?1",
        [id.as_str()],
        profile_row,
    )
    .optional()
    .map_err(repo)
}

fn profile_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<WordProfile> {
    Ok(WordProfile {
        id: WordProfileId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
        language: LanguageCode::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
        lemma: r.get(2)?,
        normalized_lemma: r.get(3)?,
        display_form: r.get(4)?,
        status: r
            .get::<_, Option<String>>(5)?
            .map(|s| from_json(&s))
            .transpose()?,
        updated_at_ms: r.get(6)?,
        user_definition: r.get(7)?,
        personal_note: r.get(8)?,
        learning_updated_at_ms: r.get(9)?,
    })
}

fn occurrence_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<WordOccurrence> {
    Ok(WordOccurrence {
        id: WordOccurrenceId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
        source_key: r.get(1)?,
        word_profile_id: WordProfileId::parse(r.get::<_, String>(2)?).map_err(domain_sql)?,
        media_id: r
            .get::<_, Option<String>>(3)?
            .map(MediaId::parse)
            .transpose()
            .map_err(domain_sql)?,
        sentence_id: r
            .get::<_, Option<String>>(4)?
            .map(SubtitleSentenceId::parse)
            .transpose()
            .map_err(domain_sql)?,
        original_form: r.get(5)?,
        sentence_text_snapshot: r.get(6)?,
        media_title_snapshot: r.get(7)?,
        media_fingerprint_snapshot: r.get(8)?,
        start_ms_snapshot: r.get(9)?,
        end_ms_snapshot: r.get(10)?,
        first_seen_at_ms: r.get(11)?,
        last_seen_at_ms: r.get(12)?,
        encounter_count: r.get(13)?,
    })
}

fn read_occurrence(
    conn: &Connection,
    id: &WordOccurrenceId,
) -> Result<Option<WordOccurrence>, ApplicationError> {
    conn.query_row(
        "SELECT id,source_key,word_profile_id,media_id,sentence_id,original_form,
         sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,
         start_ms_snapshot,end_ms_snapshot,first_seen_at_ms,last_seen_at_ms,encounter_count
         FROM word_occurrences WHERE id=?1",
        [id.as_str()],
        occurrence_row,
    )
    .optional()
    .map_err(repo)
}

fn read_occurrences(
    conn: &Connection,
    id: &WordProfileId,
) -> Result<Vec<WordOccurrence>, ApplicationError> {
    let mut q = conn
        .prepare(
            "SELECT id,source_key,word_profile_id,media_id,sentence_id,original_form,
         sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,
         start_ms_snapshot,end_ms_snapshot,first_seen_at_ms,last_seen_at_ms,encounter_count
         FROM word_occurrences WHERE word_profile_id=?1 ORDER BY last_seen_at_ms DESC",
        )
        .map_err(repo)?;
    q.query_map([id.as_str()], occurrence_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

fn history_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<WordStatusHistory> {
    Ok(WordStatusHistory {
        id: WordStatusHistoryId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
        word_profile_id: WordProfileId::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
        previous_status: r
            .get::<_, Option<String>>(2)?
            .map(|s| from_json(&s))
            .transpose()?,
        new_status: r
            .get::<_, Option<String>>(3)?
            .map(|s| from_json(&s))
            .transpose()?,
        source_occurrence_id: r
            .get::<_, Option<String>>(4)?
            .map(WordOccurrenceId::parse)
            .transpose()
            .map_err(domain_sql)?,
        changed_at_ms: r.get(5)?,
        change_source: from_json(&r.get::<_, String>(6)?)?,
    })
}

fn read_history(
    conn: &Connection,
    id: &WordProfileId,
) -> Result<Vec<WordStatusHistory>, ApplicationError> {
    let mut q = conn.prepare(
        "SELECT id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source
         FROM word_status_history WHERE word_profile_id=?1 ORDER BY changed_at_ms DESC",
    ).map_err(repo)?;
    q.query_map([id.as_str()], history_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

fn read_all_profiles(conn: &Connection) -> Result<Vec<WordProfile>, ApplicationError> {
    let mut q = conn.prepare("SELECT id,language,lemma,normalized_lemma,display_form,status,updated_at_ms,user_definition,personal_note,learning_updated_at_ms FROM word_profiles").map_err(repo)?;
    q.query_map([], profile_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}
fn read_all_occurrences(conn: &Connection) -> Result<Vec<WordOccurrence>, ApplicationError> {
    let mut q = conn.prepare("SELECT id,source_key,word_profile_id,media_id,sentence_id,original_form,sentence_text_snapshot,media_title_snapshot,media_fingerprint_snapshot,start_ms_snapshot,end_ms_snapshot,first_seen_at_ms,last_seen_at_ms,encounter_count FROM word_occurrences").map_err(repo)?;
    q.query_map([], occurrence_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}
fn read_all_history(conn: &Connection) -> Result<Vec<WordStatusHistory>, ApplicationError> {
    let mut q = conn.prepare("SELECT id,word_profile_id,previous_status,new_status,source_occurrence_id,changed_at_ms,change_source FROM word_status_history").map_err(repo)?;
    q.query_map([], history_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}
fn read_all_observations(conn: &Connection) -> Result<Vec<WordObservation>, ApplicationError> {
    let mut q = conn.prepare("SELECT id,word_profile_id,COALESCE(sentence_id,sentence_id_snapshot),original_form,result,created_at_ms FROM word_observations WHERE cleared_at_ms IS NULL").map_err(repo)?;
    q.query_map([], |r| {
        Ok(WordObservation {
            id: WordObservationId::parse(r.get::<_, String>(0)?).map_err(domain_sql)?,
            word_profile_id: WordProfileId::parse(r.get::<_, String>(1)?).map_err(domain_sql)?,
            sentence_id: SubtitleSentenceId::parse(r.get::<_, String>(2)?).map_err(domain_sql)?,
            original_form: r.get(3)?,
            result: from_json(&r.get::<_, String>(4)?)?,
            created_at_ms: r.get(5)?,
        })
    })
    .map_err(repo)?
    .collect::<Result<Vec<_>, _>>()
    .map_err(repo)
}

fn read_all_phonetic_feedback(
    conn: &Connection,
) -> Result<Vec<PhoneticFindingFeedback>, ApplicationError> {
    let mut query = conn
        .prepare(
            "SELECT feedback_json FROM phonetic_finding_feedback ORDER BY updated_at_ms,finding_id",
        )
        .map_err(repo)?;
    query
        .query_map([], |row| from_json(&row.get::<_, String>(0)?))
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}
