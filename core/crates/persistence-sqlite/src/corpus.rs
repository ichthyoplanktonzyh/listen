use application::{ApplicationError, CorpusIndexRepository};
use domain::*;
use rusqlite::params;

use super::{SqliteRepository, domain_sql, from_json, json, repo};

const SELECT_COLUMNS: &str = "id,language,kind,normalized_key,display_text,media_id,track_id,sentence_id,start_ms,end_ms,source_snapshot";

impl CorpusIndexRepository for SqliteRepository {
    fn replace_corpus_occurrences_for_track(
        &self,
        track_id: &SubtitleTrackId,
        occurrences: &[CorpusOccurrence],
    ) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = conn.transaction().map_err(repo)?;
        tx.execute(
            "DELETE FROM corpus_occurrences WHERE track_id=?1",
            [track_id.as_str()],
        )
        .map_err(repo)?;
        for occurrence in occurrences {
            insert_occurrence(&tx, occurrence)?;
        }
        tx.commit().map_err(repo)
    }

    fn upsert_corpus_occurrence(
        &self,
        occurrence: &CorpusOccurrence,
    ) -> Result<CorpusOccurrence, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        insert_occurrence(&conn, occurrence)?;
        Ok(occurrence.clone())
    }

    fn search_corpus_occurrences(
        &self,
        language: &LanguageCode,
        query: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        let conn = self.connection.lock().expect("sqlite mutex poisoned");
        let normalized = query.trim().to_lowercase();
        let is_phrase = normalized.contains(char::is_whitespace);
        // Giant entries ("the") are round-robin sampled across media instead
        // of returning the first minutes of one file: rows are ranked inside
        // their media and interleaved by rank, so a truncated page still
        // spans diverse sources, speeds, and speakers.
        if is_phrase {
            // FTS5 phrase match over sentence/chunk text (schema v29): word
            // boundary tokenized rather than raw substring, and indexed
            // instead of a LIKE '%…%' full scan. Interior quotes are dropped
            // — they cannot appear in tokenized terms anyway.
            let fts_phrase = format!("\"{}\"", normalized.replace('"', " "));
            let mut statement = conn
                .prepare(
                    &format!(
                        "SELECT {SELECT_COLUMNS} FROM (
                           SELECT c.*, ROW_NUMBER() OVER (PARTITION BY c.media_id ORDER BY c.start_ms, c.id) AS media_rank
                           FROM corpus_occurrences c
                           JOIN (SELECT rowid FROM corpus_occurrences_fts WHERE corpus_occurrences_fts MATCH ?2) f
                             ON f.rowid = c.rowid
                           WHERE c.language=?1 AND c.kind IN (?3,?4)
                         )
                         ORDER BY media_rank, start_ms, id LIMIT ?5 OFFSET ?6",
                    ),
                )
                .map_err(repo)?;
            statement
                .query_map(
                    params![
                        language.as_str(),
                        fts_phrase,
                        json(&CorpusOccurrenceKind::Phrase)?,
                        json(&CorpusOccurrenceKind::Chunk)?,
                        limit,
                        offset
                    ],
                    occurrence_from_row,
                )
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        } else {
            let mut statement = conn
                .prepare(
                    &format!(
                        "SELECT {SELECT_COLUMNS} FROM (
                           SELECT *, ROW_NUMBER() OVER (PARTITION BY media_id ORDER BY start_ms, id) AS media_rank
                           FROM corpus_occurrences
                           WHERE language=?1 AND normalized_key=?2
                         )
                         ORDER BY media_rank, start_ms, id LIMIT ?3 OFFSET ?4",
                    ),
                )
                .map_err(repo)?;
            statement
                .query_map(
                    params![language.as_str(), normalized, limit, offset],
                    occurrence_from_row,
                )
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        }
    }
}

fn occurrence_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<CorpusOccurrence> {
    Ok(CorpusOccurrence {
        id: CorpusOccurrenceId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
        language: LanguageCode::parse(row.get::<_, String>(1)?).map_err(domain_sql)?,
        kind: from_json(&row.get::<_, String>(2)?)?,
        normalized_key: row.get(3)?,
        display_text: row.get(4)?,
        media_id: row
            .get::<_, Option<String>>(5)?
            .map(MediaId::parse)
            .transpose()
            .map_err(domain_sql)?,
        track_id: row
            .get::<_, Option<String>>(6)?
            .map(SubtitleTrackId::parse)
            .transpose()
            .map_err(domain_sql)?,
        sentence_id: row
            .get::<_, Option<String>>(7)?
            .map(SubtitleSentenceId::parse)
            .transpose()
            .map_err(domain_sql)?,
        start_ms: row.get(8)?,
        end_ms: row.get(9)?,
        source_snapshot: row.get(10)?,
    })
}

fn insert_occurrence(
    conn: &rusqlite::Connection,
    occurrence: &CorpusOccurrence,
) -> Result<(), ApplicationError> {
    conn.execute(
        "INSERT INTO corpus_occurrences
         (id,language,kind,normalized_key,display_text,media_id,track_id,sentence_id,start_ms,end_ms,source_snapshot)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)
         ON CONFLICT(id) DO UPDATE SET
           language=excluded.language,kind=excluded.kind,normalized_key=excluded.normalized_key,
           display_text=excluded.display_text,media_id=excluded.media_id,track_id=excluded.track_id,
           sentence_id=excluded.sentence_id,start_ms=excluded.start_ms,end_ms=excluded.end_ms,
           source_snapshot=excluded.source_snapshot",
        params![
            occurrence.id.as_str(), occurrence.language.as_str(), json(&occurrence.kind)?,
            occurrence.normalized_key, occurrence.display_text,
            occurrence.media_id.as_ref().map(MediaId::as_str), occurrence.track_id.as_ref().map(SubtitleTrackId::as_str),
            occurrence.sentence_id.as_ref().map(SubtitleSentenceId::as_str), occurrence.start_ms, occurrence.end_ms, occurrence.source_snapshot,
        ],
    )
    .map(|_| ())
    .map_err(repo)
}
