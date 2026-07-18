use application::{ApplicationError, SemanticEmbeddingIndexRepository};
use domain::{LanguageCode, SemanticEmbeddingIndexRecord, SemanticEmbeddingSourceKind};
use rusqlite::{Row, params};

use super::{SqliteRepository, domain_sql, from_json, json, repo};

impl SemanticEmbeddingIndexRepository for SqliteRepository {
    fn replace_semantic_embedding_index(
        &self,
        model_fingerprint: &str,
        records: &[SemanticEmbeddingIndexRecord],
    ) -> Result<(), ApplicationError> {
        if records
            .iter()
            .any(|record| record.model_fingerprint != model_fingerprint)
        {
            return Err(ApplicationError::Invalid(
                "semantic index replacement mixed model fingerprints".into(),
            ));
        }
        let mut connection = self.connection.lock().expect("sqlite mutex poisoned");
        let tx = connection.transaction().map_err(repo)?;
        // Only a committed complete rebuild becomes visible. Old vector spaces
        // are removed in this transaction; a provider/encode failure happens
        // before entry and a SQL failure rolls everything back.
        tx.execute("DELETE FROM semantic_embedding_index", [])
            .map_err(repo)?;
        for record in records {
            tx.execute(
                "INSERT INTO semantic_embedding_index
                 (source_kind,source_id,language,channel,text_sha256,model_fingerprint,
                  dimension,vector_f32le,indexed_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
                params![
                    json(&record.source_kind)?,
                    record.source_id,
                    record.language.as_str(),
                    record.channel.map(|value| json(&value)).transpose()?,
                    record.text_sha256,
                    record.model_fingerprint,
                    record.dimension,
                    encode_f32le(&record.vector),
                    record.indexed_at_ms,
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)
    }

    fn list_semantic_embedding_records(
        &self,
        model_fingerprint: &str,
    ) -> Result<Vec<SemanticEmbeddingIndexRecord>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(
                "SELECT source_kind,source_id,language,channel,text_sha256,model_fingerprint,
                        dimension,vector_f32le,indexed_at_ms
                 FROM semantic_embedding_index WHERE model_fingerprint=?1
                 ORDER BY source_kind,source_id",
            )
            .map_err(repo)?;
        statement
            .query_map([model_fingerprint], record_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn semantic_embedding_index_summary(&self) -> Result<Vec<(String, u32)>, ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        let mut statement = connection
            .prepare(
                "SELECT model_fingerprint,COUNT(*) FROM semantic_embedding_index
                 GROUP BY model_fingerprint ORDER BY model_fingerprint",
            )
            .map_err(repo)?;
        statement
            .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)
    }

    fn delete_semantic_embedding_index(&self) -> Result<(), ApplicationError> {
        let connection = self.connection.lock().expect("sqlite mutex poisoned");
        connection
            .execute("DELETE FROM semantic_embedding_index", [])
            .map(|_| ())
            .map_err(repo)
    }
}

fn record_from_row(row: &Row<'_>) -> rusqlite::Result<SemanticEmbeddingIndexRecord> {
    let source_kind: SemanticEmbeddingSourceKind = from_json(&row.get::<_, String>(0)?)?;
    let channel = row
        .get::<_, Option<String>>(3)?
        .map(|value| from_json(&value))
        .transpose()?;
    let dimension = row.get::<_, u32>(6)?;
    let bytes = row.get::<_, Vec<u8>>(7)?;
    let vector = decode_f32le(&bytes).map_err(|message| {
        rusqlite::Error::FromSqlConversionFailure(
            7,
            rusqlite::types::Type::Blob,
            Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                message,
            )),
        )
    })?;
    if vector.len() != dimension as usize {
        return Err(rusqlite::Error::FromSqlConversionFailure(
            7,
            rusqlite::types::Type::Blob,
            Box::new(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "stored embedding dimension {dimension} does not match {} values",
                    vector.len()
                ),
            )),
        ));
    }
    Ok(SemanticEmbeddingIndexRecord {
        source_kind,
        source_id: row.get(1)?,
        language: LanguageCode::parse(row.get::<_, String>(2)?).map_err(domain_sql)?,
        channel,
        text_sha256: row.get(4)?,
        model_fingerprint: row.get(5)?,
        dimension,
        vector,
        indexed_at_ms: row.get(8)?,
    })
}

fn encode_f32le(vector: &[f32]) -> Vec<u8> {
    vector
        .iter()
        .flat_map(|value| value.to_le_bytes())
        .collect()
}

fn decode_f32le(bytes: &[u8]) -> Result<Vec<f32>, &'static str> {
    if !bytes.len().is_multiple_of(4) {
        return Err("float32 vector blob length is not divisible by four");
    }
    Ok(bytes
        .chunks_exact(4)
        .map(|chunk| f32::from_le_bytes(chunk.try_into().expect("exact chunk")))
        .collect())
}

#[cfg(test)]
mod tests {
    use super::{decode_f32le, encode_f32le};

    #[test]
    fn float32_little_endian_codec_round_trips() {
        let vector = vec![0.0, -1.25, 3.5, f32::MIN_POSITIVE];
        assert_eq!(decode_f32le(&encode_f32le(&vector)).unwrap(), vector);
        assert!(decode_f32le(&[0, 1, 2]).is_err());
    }
}
