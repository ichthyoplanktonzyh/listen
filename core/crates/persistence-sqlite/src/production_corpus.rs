use application::{ApplicationError, ProductionCorpusRepository};
use domain::{
    LanguageCode, MediaId, ProductionCorpusDocument, ProductionCorpusDocumentId,
    ProductionCorpusEntry, ProductionCorpusEntryId, ProductionCorpusHit, SemanticRubricId,
    SemanticTaskAttemptId,
};
use rusqlite::{Connection, Row, Transaction, params};

use super::{SqliteRepository, domain_sql, from_json, json, repo};

const DOCUMENT_COLUMNS: &str = "d.id,d.language,d.channel,d.assistance,d.attempt_id,d.rubric_id,d.response_revision,d.task_kind,d.media_id,d.start_ms,d.end_ms,d.response_text,d.produced_at_ms";

fn document_from_row(row: &Row<'_>, offset: usize) -> rusqlite::Result<ProductionCorpusDocument> {
    Ok(ProductionCorpusDocument {
        id: ProductionCorpusDocumentId::parse(row.get::<_, String>(offset)?).map_err(domain_sql)?,
        language: LanguageCode::parse(row.get::<_, String>(offset + 1)?).map_err(domain_sql)?,
        channel: from_json(&row.get::<_, String>(offset + 2)?)?,
        assistance: from_json(&row.get::<_, String>(offset + 3)?)?,
        attempt_id: SemanticTaskAttemptId::parse(row.get::<_, String>(offset + 4)?)
            .map_err(domain_sql)?,
        rubric_id: SemanticRubricId::parse(row.get::<_, String>(offset + 5)?)
            .map_err(domain_sql)?,
        response_revision: row.get(offset + 6)?,
        task_kind: from_json(&row.get::<_, String>(offset + 7)?)?,
        media_id: row
            .get::<_, Option<String>>(offset + 8)?
            .map(MediaId::parse)
            .transpose()
            .map_err(domain_sql)?,
        start_ms: row.get(offset + 9)?,
        end_ms: row.get(offset + 10)?,
        response_text: row.get(offset + 11)?,
        produced_at_ms: row.get(offset + 12)?,
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
             (id,language,channel,assistance,attempt_id,rubric_id,response_revision,task_kind,
              media_id,start_ms,end_ms,response_text,produced_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13)",
            params![
                document.id.as_str(),
                document.language.as_str(),
                json(&document.channel)?,
                json(&document.assistance)?,
                document.attempt_id.as_str(),
                document.rubric_id.as_str(),
                document.response_revision,
                json(&document.task_kind)?,
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
            tx.execute("DELETE FROM production_corpus_documents", [])
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
}
