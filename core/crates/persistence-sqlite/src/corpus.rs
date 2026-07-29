use application::{ApplicationError, CorpusIndexRepository};
use domain::{
    CorpusOccurrence, CorpusOccurrenceId, CorpusOccurrenceKind, LanguageCode, MediaId,
    SubtitleSentenceId, SubtitleTrackId,
};
use rusqlite::params;

use super::{SqliteRepository, domain_sql, from_json, json, repo};

const SELECT_COLUMNS: &str = "id,language,kind,normalized_key,display_text,media_id,track_id,sentence_id,start_ms,end_ms,source_snapshot";

impl CorpusIndexRepository for SqliteRepository {
    fn replace_corpus_occurrences_for_track(
        &self,
        track_id: &SubtitleTrackId,
        occurrences: &[CorpusOccurrence],
    ) -> Result<(), ApplicationError> {
        let mut conn = self.connection.lock();
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
        let conn = self.connection.lock();
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
        let conn = self.connection.lock();
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

    fn media_has_corpus_occurrences(
        &self,
        media_id: &MediaId,
        track_id: Option<&SubtitleTrackId>,
    ) -> Result<bool, ApplicationError> {
        let conn = self.connection.lock();
        let count = if let Some(track_id) = track_id {
            conn.query_row(
                "SELECT COUNT(*) FROM corpus_occurrences WHERE media_id=?1 AND track_id=?2",
                params![media_id.as_str(), track_id.as_str()],
                |row| row.get::<_, u32>(0),
            )
        } else {
            conn.query_row(
                "SELECT COUNT(*) FROM corpus_occurrences WHERE media_id=?1",
                [media_id.as_str()],
                |row| row.get::<_, u32>(0),
            )
        }
        .map_err(repo)?;
        Ok(count > 0)
    }

    fn search_corpus_occurrences_in_media(
        &self,
        language: &LanguageCode,
        query: &str,
        media_id: &MediaId,
        track_id: Option<&SubtitleTrackId>,
        limit: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        let conn = self.connection.lock();
        let normalized = query.trim().to_lowercase();
        let track_id = track_id.map(SubtitleTrackId::as_str);
        if normalized.contains(char::is_whitespace) {
            let fts_phrase = format!("\"{}\"", normalized.replace('"', " "));
            let mut statement = conn
                .prepare(&format!(
                    "SELECT {SELECT_COLUMNS} FROM corpus_occurrences c
                     JOIN (SELECT rowid FROM corpus_occurrences_fts WHERE corpus_occurrences_fts MATCH ?2) f
                       ON f.rowid=c.rowid
                     WHERE c.language=?1 AND c.media_id=?3
                       AND (?4 IS NULL OR c.track_id=?4)
                       AND c.kind IN (?5,?6)
                     ORDER BY c.start_ms,c.id LIMIT ?7"
                ))
                .map_err(repo)?;
            statement
                .query_map(
                    params![
                        language.as_str(),
                        fts_phrase,
                        media_id.as_str(),
                        track_id,
                        json(&CorpusOccurrenceKind::Phrase)?,
                        json(&CorpusOccurrenceKind::Chunk)?,
                        limit.min(100)
                    ],
                    occurrence_from_row,
                )
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        } else {
            let mut statement = conn
                .prepare(&format!(
                    "SELECT {SELECT_COLUMNS} FROM corpus_occurrences
                     WHERE language=?1 AND normalized_key=?2 AND media_id=?3
                       AND (?4 IS NULL OR track_id=?4)
                     ORDER BY start_ms,id LIMIT ?5"
                ))
                .map_err(repo)?;
            statement
                .query_map(
                    params![
                        language.as_str(),
                        normalized,
                        media_id.as_str(),
                        track_id,
                        limit.min(100)
                    ],
                    occurrence_from_row,
                )
                .map_err(repo)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(repo)
        }
    }

    fn search_corpus_family_occurrences(
        &self,
        language: &LanguageCode,
        families: &[String],
        media_id: Option<&MediaId>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        if families.is_empty() {
            return Ok(Vec::new());
        }
        let conn = self.connection.lock();
        // Same round-robin-across-media ranking as word search, so one long
        // movie cannot monopolize a specialty page.
        let placeholders = (0..families.len())
            .map(|index| format!("?{}", index + 5))
            .collect::<Vec<_>>()
            .join(",");
        let mut statement = conn
            .prepare(&format!(
                "SELECT {SELECT_COLUMNS} FROM (
                   SELECT *, ROW_NUMBER() OVER (PARTITION BY media_id ORDER BY start_ms, id) AS media_rank
                   FROM corpus_occurrences
                   WHERE language=?1 AND kind=?2
                     AND (?3 IS NULL OR media_id=?3)
                     AND normalized_key IN ({placeholders})
                 )
                 ORDER BY media_rank, start_ms, id LIMIT ?4 OFFSET ?{offset_index}",
                offset_index = families.len() + 5,
            ))
            .map_err(repo)?;
        use rusqlite::types::Value;
        let mut params: Vec<Value> = vec![
            Value::Text(language.as_str().to_owned()),
            Value::Text(json(&CorpusOccurrenceKind::ConnectedSpeech)?),
            media_id
                .map(|id| Value::Text(id.as_str().to_owned()))
                .unwrap_or(Value::Null),
            Value::Integer(i64::from(limit)),
        ];
        for family in families {
            params.push(Value::Text(family.clone()));
        }
        params.push(Value::Integer(i64::from(offset)));
        statement
            .query_map(rusqlite::params_from_iter(params), occurrence_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn get_corpus_occurrence(
        &self,
        id: &CorpusOccurrenceId,
    ) -> Result<Option<CorpusOccurrence>, ApplicationError> {
        use rusqlite::OptionalExtension;
        let conn = self.connection.lock();
        conn.query_row(
            &format!("SELECT {SELECT_COLUMNS} FROM corpus_occurrences WHERE id=?1"),
            [id.as_str()],
            occurrence_from_row,
        )
        .optional()
        .map_err(repo)
    }

    fn list_semantic_corpus_occurrences(&self) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        let conn = self.connection.lock();
        let mut statement = conn
            .prepare(&format!(
                "SELECT {SELECT_COLUMNS} FROM corpus_occurrences
                 WHERE kind IN (?1,?2) ORDER BY language,track_id,start_ms,id"
            ))
            .map_err(repo)?;
        statement
            .query_map(
                params![
                    json(&CorpusOccurrenceKind::Phrase)?,
                    json(&CorpusOccurrenceKind::Chunk)?
                ],
                occurrence_from_row,
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
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

pub(crate) fn insert_occurrence(
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
