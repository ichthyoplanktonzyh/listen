//! Row deserialization + sense-folder/observation readers for lexical assets.
//! Split out of `lexical.rs` (mechanical decomposition).

use application::ApplicationError;
use domain::{
    LanguageCode, LearningObservation, LearningObservationId, LexicalEntry, LexicalEntryId,
    LexicalObservation, LexicalObservationId, LexicalOccurrence, LexicalOccurrenceId,
    LexicalSenseFolder, LexicalSenseFolderDetails, LexicalSenseFolderOccurrence, LexicalSenseId,
    LexicalStatusHistory, LexicalStatusHistoryId, LexicalUnit, MediaId, PhoneticFindingFeedback,
    SubtitleSentenceId,
};
use rusqlite::OptionalExtension;

use crate::{from_json, repo};

pub(super) fn lexical_entry_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LexicalEntry> {
    let language = LanguageCode::parse(row.get::<_, String>(1)?).map_err(crate::domain_sql)?;
    let kind = from_json(&row.get::<_, String>(2)?)?;
    let granularity = row.get::<_, String>(3)?;
    let normalization = row.get::<_, String>(4)?;
    let normalized_key = row.get::<_, String>(5)?;
    let display_form = row.get::<_, String>(8)?;
    let entry = LexicalEntry {
        id: LexicalEntryId::parse(row.get::<_, String>(0)?).map_err(crate::domain_sql)?,
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
    entry.validate_unit_coherence().map_err(crate::domain_sql)?;
    Ok(entry)
}

pub(super) fn lexical_history_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<LexicalStatusHistory> {
    Ok(LexicalStatusHistory {
        id: LexicalStatusHistoryId::parse(row.get::<_, String>(0)?).map_err(crate::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(crate::domain_sql)?,
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

pub(super) fn lexical_occurrence_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<LexicalOccurrence> {
    Ok(LexicalOccurrence {
        id: LexicalOccurrenceId::parse(row.get::<_, String>(0)?).map_err(crate::domain_sql)?,
        source_key: row.get(1)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(2)?)
            .map_err(crate::domain_sql)?,
        media_id: row
            .get::<_, Option<String>>(3)?
            .map(MediaId::parse)
            .transpose()
            .map_err(crate::domain_sql)?,
        sentence_id: row
            .get::<_, Option<String>>(4)?
            .map(SubtitleSentenceId::parse)
            .transpose()
            .map_err(crate::domain_sql)?,
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

pub(super) fn lexical_sense_folder_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<LexicalSenseFolder> {
    Ok(LexicalSenseFolder {
        id: LexicalSenseId::parse(row.get::<_, String>(0)?).map_err(crate::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(crate::domain_sql)?,
        label: row.get(2)?,
        definition: row.get(3)?,
        gloss: row.get(4)?,
        external_ref: row.get(5)?,
        created_at_ms: row.get(6)?,
        updated_at_ms: row.get(7)?,
    })
}

pub(super) fn read_lexical_sense_folder(
    conn: &rusqlite::Connection,
    sense_id: &LexicalSenseId,
) -> Result<Option<LexicalSenseFolder>, ApplicationError> {
    conn.query_row(
        "SELECT id,lexical_entry_id,label,definition,gloss,external_ref,created_at_ms,updated_at_ms
         FROM lexical_sense_folders WHERE id=?1",
        [sense_id.as_str()],
        lexical_sense_folder_row,
    )
    .optional()
    .map_err(repo)
}

pub(super) fn read_lexical_sense_folder_details(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
) -> Result<Vec<LexicalSenseFolderDetails>, ApplicationError> {
    let folders = {
        let mut statement = conn
            .prepare(
                "SELECT id,lexical_entry_id,label,definition,gloss,external_ref,created_at_ms,updated_at_ms
                 FROM lexical_sense_folders WHERE lexical_entry_id=?1 ORDER BY created_at_ms ASC",
            )
            .map_err(repo)?;
        statement
            .query_map([lexical_entry_id.as_str()], lexical_sense_folder_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?
    };
    folders
        .into_iter()
        .map(|folder| {
            let mut statement = conn
                .prepare(
                    "SELECT o.id,o.source_key,o.lexical_entry_id,o.media_id,o.sentence_id,o.original_form,
                            o.sentence_text_snapshot,o.media_title_snapshot,o.media_fingerprint_snapshot,
                            o.start_ms_snapshot,o.end_ms_snapshot,o.token_start,o.token_end,o.first_seen_at_ms,
                            o.last_seen_at_ms,o.encounter_count
                     FROM lexical_sense_folder_occurrences a
                     JOIN lexical_occurrences o ON o.id=a.lexical_occurrence_id
                     WHERE a.lexical_sense_id=?1 ORDER BY o.last_seen_at_ms DESC",
                )
                .map_err(repo)?;
            let occurrences = statement
                .query_map([folder.id.as_str()], lexical_occurrence_row)
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)?;
            Ok(LexicalSenseFolderDetails { folder, occurrences })
        })
        .collect()
}

pub(super) fn read_all_lexical_sense_folders(
    conn: &rusqlite::Connection,
) -> Result<Vec<LexicalSenseFolder>, ApplicationError> {
    let mut statement = conn
        .prepare(
            "SELECT id,lexical_entry_id,label,definition,gloss,external_ref,created_at_ms,updated_at_ms
             FROM lexical_sense_folders ORDER BY created_at_ms ASC",
        )
        .map_err(repo)?;
    statement
        .query_map([], lexical_sense_folder_row)
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

pub(super) fn read_all_lexical_sense_folder_occurrences(
    conn: &rusqlite::Connection,
) -> Result<Vec<LexicalSenseFolderOccurrence>, ApplicationError> {
    let mut statement = conn
        .prepare(
            "SELECT lexical_sense_id,lexical_occurrence_id
             FROM lexical_sense_folder_occurrences",
        )
        .map_err(repo)?;
    statement
        .query_map([], |row| {
            Ok(LexicalSenseFolderOccurrence {
                lexical_sense_id: LexicalSenseId::parse(row.get::<_, String>(0)?)
                    .map_err(crate::domain_sql)?,
                lexical_occurrence_id: LexicalOccurrenceId::parse(row.get::<_, String>(1)?)
                    .map_err(crate::domain_sql)?,
            })
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

pub(super) fn lexical_observation_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<LexicalObservation> {
    Ok(LexicalObservation {
        id: LexicalObservationId::parse(row.get::<_, String>(0)?).map_err(crate::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(crate::domain_sql)?,
        sentence_id: SubtitleSentenceId::parse(row.get::<_, String>(2)?)
            .map_err(crate::domain_sql)?,
        original_form: row.get(3)?,
        result: from_json(&row.get::<_, String>(4)?)?,
        created_at_ms: row.get(5)?,
    })
}

pub(super) fn learning_observation_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<LearningObservation> {
    let sense_id = row.get::<_, String>(2)?;
    Ok(LearningObservation {
        id: LearningObservationId::parse(row.get::<_, String>(0)?).map_err(crate::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(crate::domain_sql)?,
        sense_id: if sense_id.is_empty() {
            None
        } else {
            Some(LexicalSenseId::parse(sense_id).map_err(crate::domain_sql)?)
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
            .map_err(crate::domain_sql)?,
        media_id: row
            .get::<_, Option<String>>(9)?
            .map(MediaId::parse)
            .transpose()
            .map_err(crate::domain_sql)?,
        origin: from_json(&row.get::<_, String>(10)?)?,
        source_ref: row.get(11)?,
        occurred_at_ms: row.get(12)?,
    })
}

pub(super) fn read_all_phonetic_feedback(
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
