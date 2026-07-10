use application::{ApplicationError, CorpusIndexRepository};
use domain::*;
use rusqlite::params;

use super::{SqliteRepository, domain_sql, from_json, json, repo};

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
        let phrase_like = format!("%{normalized}%");
        let is_phrase = normalized.contains(char::is_whitespace);
        let mut statement = conn
            .prepare(
                "SELECT id,language,kind,normalized_key,display_text,media_id,track_id,sentence_id,start_ms,end_ms,source_snapshot
                 FROM corpus_occurrences
                 WHERE language=?1 AND (
                   (?3=0 AND normalized_key=?2)
                   OR (?3=1 AND kind IN (?4,?5) AND source_snapshot LIKE ?6 COLLATE NOCASE)
                 )
                 ORDER BY start_ms, id LIMIT ?7 OFFSET ?8",
            )
            .map_err(repo)?;
        statement
            .query_map(
                params![
                    language.as_str(),
                    normalized,
                    is_phrase as u8,
                    json(&CorpusOccurrenceKind::Phrase)?,
                    json(&CorpusOccurrenceKind::Chunk)?,
                    phrase_like,
                    limit,
                    offset
                ],
                |row| {
                    Ok(CorpusOccurrence {
                        id: CorpusOccurrenceId::parse(row.get::<_, String>(0)?)
                            .map_err(domain_sql)?,
                        language: LanguageCode::parse(row.get::<_, String>(1)?)
                            .map_err(domain_sql)?,
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
                },
            )
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }
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
