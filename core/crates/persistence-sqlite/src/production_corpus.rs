use application::{ApplicationError, ProductionCorpusRepository};
use domain::{
    LanguageCode, MediaId, ProductionChannel, ProductionCorpusDocument, ProductionCorpusDocumentId,
    ProductionCorpusEntry, ProductionCorpusEntryId, ProductionCorpusHit, ProductionCorpusSummary,
    ProductionGapCandidateFacts, RealtimeConversationSessionId, RealtimeConversationTurnId,
    SemanticRubricId, SemanticTaskAttemptId,
};
use rusqlite::{Connection, Row, Transaction, params};

use super::{SqliteRepository, domain_sql, from_json, json, repo};

const DOCUMENT_COLUMNS: &str = "d.id,d.language,d.channel,d.assistance,d.attempt_id,d.rubric_id,d.realtime_turn_id,d.realtime_session_id,d.response_revision,d.activity_kind,d.media_id,d.start_ms,d.end_ms,d.response_text,d.produced_at_ms";

fn document_from_row(row: &Row<'_>, offset: usize) -> rusqlite::Result<ProductionCorpusDocument> {
    Ok(ProductionCorpusDocument {
        id: ProductionCorpusDocumentId::parse(row.get::<_, String>(offset)?).map_err(domain_sql)?,
        language: LanguageCode::parse(row.get::<_, String>(offset + 1)?).map_err(domain_sql)?,
        channel: from_json(&row.get::<_, String>(offset + 2)?)?,
        assistance: from_json(&row.get::<_, String>(offset + 3)?)?,
        attempt_id: row
            .get::<_, Option<String>>(offset + 4)?
            .map(SemanticTaskAttemptId::parse)
            .transpose()
            .map_err(domain_sql)?,
        rubric_id: row
            .get::<_, Option<String>>(offset + 5)?
            .map(SemanticRubricId::parse)
            .transpose()
            .map_err(domain_sql)?,
        realtime_turn_id: row
            .get::<_, Option<String>>(offset + 6)?
            .map(RealtimeConversationTurnId::parse)
            .transpose()
            .map_err(domain_sql)?,
        realtime_session_id: row
            .get::<_, Option<String>>(offset + 7)?
            .map(RealtimeConversationSessionId::parse)
            .transpose()
            .map_err(domain_sql)?,
        response_revision: row.get(offset + 8)?,
        activity_kind: row.get(offset + 9)?,
        media_id: row
            .get::<_, Option<String>>(offset + 10)?
            .map(MediaId::parse)
            .transpose()
            .map_err(domain_sql)?,
        start_ms: row.get(offset + 11)?,
        end_ms: row.get(offset + 12)?,
        response_text: row.get(offset + 13)?,
        produced_at_ms: row.get(offset + 14)?,
    })
}

fn lexical_hit_from_row(row: &Row<'_>) -> rusqlite::Result<ProductionCorpusHit> {
    Ok(ProductionCorpusHit {
        document: document_from_row(row, 6)?,
        entry: Some(ProductionCorpusEntry {
            id: ProductionCorpusEntryId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
            document_id: ProductionCorpusDocumentId::parse(row.get::<_, String>(1)?)
                .map_err(domain_sql)?,
            normalized_key: row.get(2)?,
            display_text: row.get(3)?,
            start_char: row.get(4)?,
            end_char: row.get(5)?,
        }),
    })
}

fn document_hit_from_row(row: &Row<'_>) -> rusqlite::Result<ProductionCorpusHit> {
    Ok(ProductionCorpusHit {
        document: document_from_row(row, 0)?,
        entry: None,
    })
}

fn insert_projection(
    tx: &Transaction<'_>,
    documents: &[ProductionCorpusDocument],
    entries: &[ProductionCorpusEntry],
) -> Result<(), ApplicationError> {
    for document in documents {
        tx.execute(
            "INSERT INTO production_corpus_documents
             (id,language,channel,assistance,attempt_id,rubric_id,realtime_turn_id,realtime_session_id,response_revision,activity_kind,
              media_id,start_ms,end_ms,response_text,produced_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15)",
            params![
                document.id.as_str(),
                document.language.as_str(),
                json(&document.channel)?,
                json(&document.assistance)?,
                document.attempt_id.as_ref().map(SemanticTaskAttemptId::as_str),
                document.rubric_id.as_ref().map(SemanticRubricId::as_str),
                document.realtime_turn_id.as_ref().map(RealtimeConversationTurnId::as_str),
                document.realtime_session_id.as_ref().map(RealtimeConversationSessionId::as_str),
                document.response_revision,
                document.activity_kind,
                document.media_id.as_ref().map(MediaId::as_str),
                document.start_ms,
                document.end_ms,
                document.response_text,
                document.produced_at_ms,
            ],
        )
        .map_err(repo)?;
    }
    for entry in entries {
        tx.execute(
            "INSERT INTO production_corpus_entries
             (id,document_id,normalized_key,display_text,start_char,end_char)
             VALUES (?1,?2,?3,?4,?5,?6)",
            params![
                entry.id.as_str(),
                entry.document_id.as_str(),
                entry.normalized_key,
                entry.display_text,
                entry.start_char,
                entry.end_char,
            ],
        )
        .map_err(repo)?;
    }
    Ok(())
}

fn replace_projection(
    connection: &mut Connection,
    rubric_id: Option<&SemanticRubricId>,
    documents: &[ProductionCorpusDocument],
    entries: &[ProductionCorpusEntry],
) -> Result<(), ApplicationError> {
    let tx = connection.transaction().map_err(repo)?;
    match rubric_id {
        Some(rubric_id) => {
            tx.execute(
                "DELETE FROM production_corpus_documents WHERE rubric_id=?1",
                [rubric_id.as_str()],
            )
            .map_err(repo)?;
        }
        None => {
            tx.execute(
                "DELETE FROM production_corpus_documents WHERE attempt_id IS NOT NULL",
                [],
            )
            .map_err(repo)?;
        }
    }
    insert_projection(&tx, documents, entries)?;
    tx.commit().map_err(repo)
}

impl ProductionCorpusRepository for SqliteRepository {
    fn replace_production_entries_for_rubric(
        &self,
        rubric_id: &SemanticRubricId,
        documents: &[ProductionCorpusDocument],
        entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError> {
        let mut connection = self.connection.lock().expect("sqlite mutex poisoned");
        replace_projection(&mut connection, Some(rubric_id), documents, entries)
    }

    fn replace_all_production_entries(
        &self,
        documents: &[ProductionCorpusDocument],
        entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError> {
        let mut connection = self.connection.lock().expect("sqlite mutex poisoned");
        replace_projection(&mut connection, None, documents, entries)
    }

    fn replace_production_entries_for_realtime_turn(
        &self,
        turn_id: &RealtimeConversationTurnId,
        documents: &[ProductionCorpusDocument],
        entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError> {
        let mut connection = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = connection.transaction().map_err(repo)?;
        tx.execute(
            "DELETE FROM production_corpus_documents WHERE realtime_turn_id=?1",
            [turn_id.as_str()],
        )
        .map_err(repo)?;
        insert_projection(&tx, documents, entries)?;
        tx.commit().map_err(repo)
    }

    fn list_production_entries_by_key(
        &self,
        language: &LanguageCode,
        normalized_key: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ProductionCorpusHit>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(&format!(
                "SELECT e.id,e.document_id,e.normalized_key,e.display_text,e.start_char,e.end_char,
                        {DOCUMENT_COLUMNS}
                 FROM production_corpus_entries e
                 JOIN production_corpus_documents d ON d.id=e.document_id
                 WHERE d.language=?1 AND e.normalized_key=?2
                 ORDER BY d.produced_at_ms DESC,e.start_char,e.id LIMIT ?3 OFFSET ?4"
            ))
            .map_err(repo)?;
        statement
            .query_map(
                params![language.as_str(), normalized_key, limit, offset],
                lexical_hit_from_row,
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn search_production_documents(
        &self,
        language: &LanguageCode,
        query: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ProductionCorpusHit>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let phrase = format!("\"{}\"", query.trim().to_lowercase().replace('"', " "));
        let mut statement = connection
            .prepare(&format!(
                "SELECT {DOCUMENT_COLUMNS}
                 FROM production_corpus_documents d
                 JOIN production_corpus_documents_fts f ON f.document_id=d.id
                 WHERE d.language=?1 AND production_corpus_documents_fts MATCH ?2
                 ORDER BY d.produced_at_ms DESC,d.id LIMIT ?3 OFFSET ?4"
            ))
            .map_err(repo)?;
        statement
            .query_map(
                params![language.as_str(), phrase, limit, offset],
                document_hit_from_row,
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn production_corpus_summary(
        &self,
        language: &LanguageCode,
        channel: ProductionChannel,
    ) -> Result<ProductionCorpusSummary, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        connection
            .query_row(
                "SELECT COUNT(DISTINCT d.id),COUNT(e.id),COUNT(DISTINCT e.normalized_key)
                 FROM production_corpus_documents d
                 LEFT JOIN production_corpus_entries e ON e.document_id=d.id
                 WHERE d.language=?1 AND d.channel=?2",
                params![language.as_str(), json(&channel)?],
                |row| {
                    Ok(ProductionCorpusSummary {
                        document_count: row.get(0)?,
                        token_count: row.get(1)?,
                        lemma_count: row.get(2)?,
                    })
                },
            )
            .map_err(repo)
    }

    fn list_production_gap_candidates(
        &self,
        language: &LanguageCode,
        channel: ProductionChannel,
    ) -> Result<Vec<ProductionGapCandidateFacts>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection.prepare(
            "WITH capability AS (
               SELECT lexical_entry_id,
                 MAX(CASE WHEN capability='\"reading\"' AND
                   COALESCE(json_extract(override_json,'$.conclusion'),json_extract(projection_json,'$.conclusion'))='acquired' THEN 1 ELSE 0 END) reading_acquired,
                 MAX(CASE WHEN capability='\"listening\"' AND
                   COALESCE(json_extract(override_json,'$.conclusion'),json_extract(projection_json,'$.conclusion'))='acquired' THEN 1 ELSE 0 END) listening_acquired,
                 MAX(updated_at_ms) latest_at
               FROM lexical_capability_states
               WHERE capability IN ('\"reading\"','\"listening\"')
               GROUP BY lexical_entry_id
             ), observations AS (
               SELECT lexical_entry_id,
                 SUM(CASE WHEN capability='\"reading\"' AND outcome='\"success\"' THEN 1 ELSE 0 END) reading_successes,
                 SUM(CASE WHEN capability='\"listening\"' AND outcome='\"success\"' THEN 1 ELSE 0 END) listening_successes,
                 MAX(occurred_at_ms) latest_at
               FROM learning_observations
               WHERE capability IN ('\"reading\"','\"listening\"')
               GROUP BY lexical_entry_id
             ), recognition AS (
               SELECT lexical_entry_id,COUNT(*) contexts,MAX(occurred_at_ms) latest_at
               FROM recognition_evidence GROUP BY lexical_entry_id
             )
             SELECT le.id,le.normalized_key,le.display_form,
               COALESCE(c.reading_acquired,0),COALESCE(c.listening_acquired,0),
               COALESCE(o.reading_successes,0),COALESCE(o.listening_successes,0),
               COALESCE(r.contexts,0),
               MAX(COALESCE(c.latest_at,0),COALESCE(o.latest_at,0),COALESCE(r.latest_at,0))
             FROM lexical_entries le
             LEFT JOIN capability c ON c.lexical_entry_id=le.id
             LEFT JOIN observations o ON o.lexical_entry_id=le.id
             LEFT JOIN recognition r ON r.lexical_entry_id=le.id
             WHERE le.language=?1
               AND (COALESCE(c.reading_acquired,0)=1 OR COALESCE(c.listening_acquired,0)=1
                 OR COALESCE(o.reading_successes,0)>0 OR COALESCE(o.listening_successes,0)>0
                 OR COALESCE(r.contexts,0)>0)
               AND NOT EXISTS (
                 SELECT 1 FROM production_corpus_entries pe
                 JOIN production_corpus_documents pd ON pd.id=pe.document_id
                 WHERE pd.language=le.language AND pd.channel=?2
                   AND pe.normalized_key=le.normalized_key)
             ORDER BY le.normalized_key"
        ).map_err(repo)?;
        statement
            .query_map(params![language.as_str(), json(&channel)?], |row| {
                Ok(ProductionGapCandidateFacts {
                    lexical_entry_id: domain::LexicalEntryId::parse(row.get::<_, String>(0)?)
                        .map_err(domain_sql)?,
                    normalized_key: row.get(1)?,
                    display_form: row.get(2)?,
                    reading_acquired: row.get::<_, u32>(3)? != 0,
                    listening_acquired: row.get::<_, u32>(4)? != 0,
                    reading_successes: row.get(5)?,
                    listening_successes: row.get(6)?,
                    recognition_contexts: row.get(7)?,
                    latest_receptive_at_ms: row.get(8)?,
                })
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn list_production_documents(&self) -> Result<Vec<ProductionCorpusDocument>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(&format!(
                "SELECT {DOCUMENT_COLUMNS} FROM production_corpus_documents d
                 ORDER BY d.language,d.produced_at_ms,d.id"
            ))
            .map_err(repo)?;
        statement
            .query_map([], |row| document_from_row(row, 0))
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn list_production_lexemes(
        &self,
        language: &LanguageCode,
        channel: ProductionChannel,
    ) -> Result<Vec<String>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(
                "SELECT DISTINCT e.normalized_key FROM production_corpus_entries e
                 JOIN production_corpus_documents d ON d.id=e.document_id
                 WHERE d.language=?1 AND d.channel=?2 ORDER BY e.normalized_key",
            )
            .map_err(repo)?;
        statement
            .query_map(params![language.as_str(), json(&channel)?], |row| {
                row.get(0)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
}
