use application::{
    ApplicationError, LearningObservationRepository, LexicalCapabilityRepository,
    LexicalContentRepository, LexicalEntryRepository, LexicalSourceContext,
    VocabularyAssetRepository,
};
use domain::{
    CapabilityAssessment, CapabilityDimensionState, CapabilityFilter, CapabilityOverride,
    CapabilityProjection, CapabilityStateChangeKind, LanguageCode, LearningChangeSource,
    LearningObservation, LearningStatus, LexicalCapability, LexicalCapabilityHistory,
    LexicalCapabilityProfile, LexicalEntry, LexicalEntryDetails, LexicalEntryId, LexicalEntryKind,
    LexicalObservation, LexicalOccurrence, LexicalOccurrenceId, LexicalSenseFolder, LexicalSenseId,
    LexicalStatusHistory, LexicalStatusHistoryId, MediaId, ProjectionDecision, ProjectionProposal,
    ProjectionProposalId, ProjectionProposalStatus, SubtitleSentenceId, VocabularyAssetBundle,
};
use rusqlite::{OptionalExtension, params, params_from_iter};

use super::{SqliteRepository, from_json, json, repo};

type LexicalAssets = (
    Vec<LexicalEntry>,
    Vec<LexicalStatusHistory>,
    Vec<LexicalOccurrence>,
    Vec<LexicalObservation>,
);

mod capability;
mod import_export;
mod rows;

use capability::{capability_history_row, read_capability_profile, sense_key};
use capability::{read_capability_state, write_capability_history, write_capability_state};
use rows::{
    learning_observation_row, lexical_entry_row, lexical_history_row, lexical_observation_row,
    lexical_occurrence_row, read_all_lexical_sense_folder_occurrences,
    read_all_lexical_sense_folders, read_all_phonetic_feedback, read_lexical_sense_folder,
    read_lexical_sense_folder_details,
};

impl LexicalCapabilityRepository for SqliteRepository {
    fn lexical_capability_profile(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
    ) -> Result<Option<LexicalCapabilityProfile>, ApplicationError> {
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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

    fn save_projection_proposal(
        &self,
        proposal: &ProjectionProposal,
    ) -> Result<ProjectionProposal, ApplicationError> {
        let conn = self.connection.lock();
        conn.execute(
            "INSERT OR IGNORE INTO projection_proposals
             (id,lexical_entry_id,capability,algorithm_version,evidence_as_of_ms,proposal_json,created_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6,?7)",
            params![proposal.id.as_str(), proposal.lexical_entry_id.as_str(), json(&proposal.capability)?,
                proposal.algorithm_version, proposal.evidence_as_of_ms, json(proposal)?, proposal.created_at_ms],
        ).map_err(repo)?;
        drop(conn);
        self.projection_proposal(&proposal.id)?.ok_or_else(|| {
            ApplicationError::Repository("projection proposal was not persisted".into())
        })
    }

    fn projection_proposal(
        &self,
        id: &ProjectionProposalId,
    ) -> Result<Option<ProjectionProposal>, ApplicationError> {
        let conn = self.connection.lock();
        read_projection_proposal(&conn, id)
    }

    fn list_projection_proposals(
        &self,
        lexical_entry_id: &LexicalEntryId,
        capability: Option<LexicalCapability>,
    ) -> Result<Vec<ProjectionProposal>, ApplicationError> {
        let conn = self.connection.lock();
        let capability_json = capability.map(|value| json(&value)).transpose()?;
        let mut statement = conn.prepare(
            "SELECT p.proposal_json,d.decision_json,
                    EXISTS(SELECT 1 FROM projection_proposals newer
                      WHERE newer.lexical_entry_id=p.lexical_entry_id AND newer.capability=p.capability
                        AND (newer.evidence_as_of_ms>p.evidence_as_of_ms
                          OR (newer.evidence_as_of_ms=p.evidence_as_of_ms AND newer.created_at_ms>p.created_at_ms)))
             FROM projection_proposals p LEFT JOIN projection_decisions d ON d.proposal_id=p.id
             WHERE p.lexical_entry_id=?1 AND (?2 IS NULL OR p.capability=?2)
             ORDER BY p.created_at_ms DESC,p.id DESC"
        ).map_err(repo)?;
        statement
            .query_map(params![lexical_entry_id.as_str(), capability_json], |row| {
                let mut proposal: ProjectionProposal = from_json(&row.get::<_, String>(0)?)?;
                let decision = row
                    .get::<_, Option<String>>(1)?
                    .map(|value| from_json::<ProjectionDecision>(&value))
                    .transpose()?;
                proposal.status = match decision.map(|value| value.decision) {
                    Some(domain::ProjectionDecisionKind::Confirm) => {
                        ProjectionProposalStatus::Confirmed
                    }
                    Some(domain::ProjectionDecisionKind::Reject) => {
                        ProjectionProposalStatus::Rejected
                    }
                    None if row.get::<_, bool>(2)? => ProjectionProposalStatus::Superseded,
                    None => ProjectionProposalStatus::Pending,
                };
                Ok(proposal)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn resolve_projection_proposal(
        &self,
        decision: &ProjectionDecision,
        proposal: &ProjectionProposal,
        confirmed_projection: Option<CapabilityProjection>,
    ) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        tx.execute(
            "INSERT INTO projection_decisions(id,proposal_id,decision_json,decided_at_ms) VALUES (?1,?2,?3,?4)",
            params![decision.id.as_str(), decision.proposal_id.as_str(), json(decision)?, decision.decided_at_ms],
        ).map_err(repo)?;
        if let Some(projection) = confirmed_projection {
            let previous =
                read_capability_state(&tx, &proposal.lexical_entry_id, None, proposal.capability)?
                    .unwrap_or_default();
            let mut next = previous.clone();
            next.projection = Some(projection);
            if previous != next {
                write_capability_state(
                    &tx,
                    &proposal.lexical_entry_id,
                    None,
                    proposal.capability,
                    &next,
                    decision.decided_at_ms,
                )?;
                write_capability_history(
                    &tx,
                    &proposal.lexical_entry_id,
                    None,
                    proposal.capability,
                    &previous,
                    &next,
                    CapabilityStateChangeKind::ProjectionUpdated,
                    decision.decided_at_ms,
                )?;
            }
        }
        tx.commit().map_err(repo)?;
        Ok(())
    }
}

fn read_projection_proposal(
    conn: &rusqlite::Connection,
    id: &ProjectionProposalId,
) -> Result<Option<ProjectionProposal>, ApplicationError> {
    conn.query_row(
        "SELECT p.proposal_json,d.decision_json FROM projection_proposals p
         LEFT JOIN projection_decisions d ON d.proposal_id=p.id WHERE p.id=?1",
        [id.as_str()],
        |row| {
            let mut proposal: ProjectionProposal = from_json(&row.get::<_, String>(0)?)?;
            let decision = row
                .get::<_, Option<String>>(1)?
                .map(|value| from_json::<ProjectionDecision>(&value))
                .transpose()?;
            proposal.status = match decision.map(|value| value.decision) {
                Some(domain::ProjectionDecisionKind::Confirm) => {
                    ProjectionProposalStatus::Confirmed
                }
                Some(domain::ProjectionDecisionKind::Reject) => ProjectionProposalStatus::Rejected,
                None => ProjectionProposalStatus::Pending,
            };
            Ok(proposal)
        },
    )
    .optional()
    .map_err(repo)
}

impl LexicalEntryRepository for SqliteRepository {
    fn upsert_lexical_entry(
        &self,
        entry: &LexicalEntry,
        source: Option<&LexicalSourceContext>,
        change_source: LearningChangeSource,
    ) -> Result<LexicalEntryDetails, ApplicationError> {
        entry.validate_unit_coherence()?;
        let mut conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let capability_profile = read_capability_profile(&conn, id, None)?;
        let sense_folders = read_lexical_sense_folder_details(&conn, id)?;
        Ok(Some(LexicalEntryDetails {
            entry,
            history,
            occurrences,
            sense_folders,
            capability_profile,
        }))
    }

    fn list_lexical_entries(
        &self,
        language: &LanguageCode,
        kind: Option<LexicalEntryKind>,
        status: Option<LearningStatus>,
        capability_filter: Option<CapabilityFilter>,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError> {
        let ids: Vec<String> = {
            let conn = self.connection.lock();
            match capability_filter {
                None => {
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
                }
                Some(filter) => {
                    // The effective assessment is override-over-projection, with
                    // absence meaning unassessed. The conclusion lives inside the
                    // JSON state blobs, so it is compared via json_extract rather
                    // than a first-class column. Entry-level state uses sense_id=''.
                    let assessment = match filter.assessment {
                        CapabilityAssessment::Unassessed => "unassessed",
                        CapabilityAssessment::NotAcquired => "not_acquired",
                        CapabilityAssessment::Acquired => "acquired",
                    };
                    let mut statement = conn
                        .prepare(
                            "SELECT e.id FROM lexical_entries e
                             LEFT JOIN lexical_occurrences o ON o.lexical_entry_id=e.id
                             LEFT JOIN lexical_capability_states c
                               ON c.lexical_entry_id=e.id AND c.sense_id='' AND c.capability=?7
                             WHERE e.language=?1
                               AND (?2 IS NULL OR e.kind=?2)
                               AND (?3 IS NULL OR e.status=?3)
                               AND (?4='' OR e.normalized_key LIKE '%'||?4||'%' OR e.display_form LIKE '%'||?4||'%')
                               AND (
                                 (?8='unassessed' AND c.lexical_entry_id IS NULL)
                                 OR (?8<>'unassessed' AND COALESCE(
                                       json_extract(c.override_json,'$.conclusion'),
                                       json_extract(c.projection_json,'$.conclusion')
                                     )=?8)
                               )
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
                                json(&filter.capability)?,
                                assessment,
                            ],
                            |row| row.get::<_, String>(0),
                        )
                        .map_err(repo)?
                        .collect::<Result<Vec<_>, _>>()
                        .map_err(repo)?
                }
            }
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
        let conn = self.connection.lock();
        let mut statement = conn.prepare(&sql).map_err(repo)?;
        statement
            .query_map(params_from_iter(values), lexical_entry_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn lexical_vocabulary_watermark(
        &self,
        language: &LanguageCode,
    ) -> Result<(u64, u64), ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT COUNT(*), COALESCE(MAX(learning_updated_at_ms), 0)
             FROM lexical_entries WHERE language=?1",
            [language.as_str()],
            |row| Ok((row.get::<_, u64>(0)?, row.get::<_, u64>(1)?)),
        )
        .map_err(repo)
    }
}

impl LearningObservationRepository for SqliteRepository {
    fn create_lexical_observation(
        &self,
        observation: &LexicalObservation,
    ) -> Result<LexicalObservation, ApplicationError> {
        self.connection
            .lock()
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
            .execute(
                "UPDATE lexical_observations SET cleared_at_ms=unixepoch('subsec') * 1000
                 WHERE lexical_entry_id=?1 AND sentence_id=?2",
                params![lexical_entry_id.as_str(), sentence_id.as_str()],
            )
            .map(|_| ())
            .map_err(repo)
    }
}

impl LexicalContentRepository for SqliteRepository {
    fn update_lexical_learning_content(
        &self,
        id: &LexicalEntryId,
        user_definition: Option<String>,
        personal_note: Option<String>,
        updated_at_ms: u64,
    ) -> Result<LexicalEntryDetails, ApplicationError> {
        self.connection
            .lock()
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

    fn create_lexical_sense_folder(
        &self,
        folder: &LexicalSenseFolder,
    ) -> Result<LexicalSenseFolder, ApplicationError> {
        self.connection
            .lock()
            .execute(
                "INSERT INTO lexical_sense_folders
                 (id,lexical_entry_id,label,definition,gloss,external_ref,created_at_ms,updated_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
                params![
                    folder.id.as_str(),
                    folder.lexical_entry_id.as_str(),
                    folder.label,
                    folder.definition,
                    folder.gloss,
                    folder.external_ref,
                    folder.created_at_ms,
                    folder.updated_at_ms,
                ],
            )
            .map_err(repo)?;
        Ok(folder.clone())
    }

    fn update_lexical_sense_folder(
        &self,
        folder: &LexicalSenseFolder,
    ) -> Result<LexicalSenseFolder, ApplicationError> {
        let changed = self
            .connection
            .lock()
            .execute(
                "UPDATE lexical_sense_folders
                 SET label=?3,definition=?4,gloss=?5,external_ref=?6,updated_at_ms=?7
                 WHERE id=?1 AND lexical_entry_id=?2",
                params![
                    folder.id.as_str(),
                    folder.lexical_entry_id.as_str(),
                    folder.label,
                    folder.definition,
                    folder.gloss,
                    folder.external_ref,
                    folder.updated_at_ms,
                ],
            )
            .map_err(repo)?;
        if changed == 0 {
            return Err(ApplicationError::NotFound("lexical sense folder"));
        }
        let conn = self.connection.lock();
        read_lexical_sense_folder(&conn, &folder.id)?
            .ok_or(ApplicationError::NotFound("lexical sense folder"))
    }

    fn delete_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
    ) -> Result<(), ApplicationError> {
        let changed = self
            .connection
            .lock()
            .execute(
                "DELETE FROM lexical_sense_folders WHERE id=?1 AND lexical_entry_id=?2",
                params![sense_id.as_str(), lexical_entry_id.as_str()],
            )
            .map_err(repo)?;
        if changed == 0 {
            return Err(ApplicationError::NotFound("lexical sense folder"));
        }
        Ok(())
    }

    fn assign_occurrence_to_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
        occurrence_id: &LexicalOccurrenceId,
    ) -> Result<(), ApplicationError> {
        let changed = self
            .connection
            .lock()
            .execute(
                "INSERT INTO lexical_sense_folder_occurrences(lexical_sense_id,lexical_occurrence_id)
                 SELECT ?1,?2
                 WHERE EXISTS(SELECT 1 FROM lexical_sense_folders WHERE id=?1 AND lexical_entry_id=?3)
                   AND EXISTS(SELECT 1 FROM lexical_occurrences WHERE id=?2 AND lexical_entry_id=?3)
                 ON CONFLICT(lexical_occurrence_id)
                 DO UPDATE SET lexical_sense_id=excluded.lexical_sense_id",
                params![sense_id.as_str(), occurrence_id.as_str(), lexical_entry_id.as_str()],
            )
            .map_err(repo)?;
        if changed == 0 {
            return Err(ApplicationError::NotFound(
                "lexical sense folder or occurrence",
            ));
        }
        Ok(())
    }

    fn unassign_occurrence_from_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
        occurrence_id: &LexicalOccurrenceId,
    ) -> Result<(), ApplicationError> {
        let conn = self.connection.lock();
        let folder_exists = conn
            .query_row(
                "SELECT 1 FROM lexical_sense_folders WHERE id=?1 AND lexical_entry_id=?2",
                params![sense_id.as_str(), lexical_entry_id.as_str()],
                |_| Ok(()),
            )
            .optional()
            .map_err(repo)?
            .is_some();
        if !folder_exists {
            return Err(ApplicationError::NotFound("lexical sense folder"));
        }
        conn.execute(
            "DELETE FROM lexical_sense_folder_occurrences
             WHERE lexical_sense_id=?1 AND lexical_occurrence_id=?2",
            params![sense_id.as_str(), occurrence_id.as_str()],
        )
        .map_err(repo)?;
        Ok(())
    }
}

impl VocabularyAssetRepository for SqliteRepository {
    fn export_assets(&self) -> Result<VocabularyAssetBundle, ApplicationError> {
        let (lexical_entries, lexical_history, lexical_occurrences, lexical_observations) =
            self.export_lexical_assets()?;
        let capability_profiles = self.export_all_capability_profiles()?;
        let learning_observations = self.export_all_learning_observations()?;
        let conn = self.connection.lock();
        let lexical_sense_folders = read_all_lexical_sense_folders(&conn)?;
        let lexical_sense_folder_occurrences = read_all_lexical_sense_folder_occurrences(&conn)?;
        Ok(VocabularyAssetBundle {
            version: 7,
            exported_at_ms: application::now_ms(),
            lexical_entries,
            lexical_history,
            lexical_occurrences,
            lexical_sense_folders,
            lexical_sense_folder_occurrences,
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
        self.import_lexical_sense_folder_assets(
            &bundle.lexical_sense_folders,
            &bundle.lexical_sense_folder_occurrences,
        )?;
        for profile in &bundle.capability_profiles {
            self.import_capability_profile(profile)?;
        }
        // Append-only ids make observation merge trivially idempotent
        // (ADR 0017 decision 6); rows for entries absent locally are skipped
        // by the same existence rule as capability profiles.
        for observation in &bundle.learning_observations {
            let exists = {
                let conn = self.connection.lock();
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
        let mut conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
            let needs_new = profiles
                .last()
                .is_none_or(|last| last.lexical_entry_id != entry_id || last.sense_id != sense_id);
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
