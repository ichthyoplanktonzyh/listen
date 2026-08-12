//! Durable Source Identity mapping persistence (SQLite).

use application::{ApplicationError, SourceIdentityRepository};
use domain::{
    ContentSourceId, LearningMaterialId, MaterialRevisionId, SourceIdentityMapping,
    SourceItemEvidence, SourceItemId, SourceItemIdentity,
};
use rusqlite::{OptionalExtension, params};

use super::{SqliteRepository, domain_sql, from_json, json, repo};

impl SourceIdentityRepository for SqliteRepository {
    fn save_mapping(&self, mapping: &SourceIdentityMapping) -> Result<(), ApplicationError> {
        let conn = self.connection.lock();
        conn.execute(
            "INSERT INTO source_identity_mappings
               (source_id, item_id, evidence_json, material_id, material_revision_id, mapped_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6)
             ON CONFLICT(source_id, item_id)
             DO UPDATE SET evidence_json=excluded.evidence_json,
                           material_id=excluded.material_id,
                           material_revision_id=excluded.material_revision_id,
                           mapped_at_ms=excluded.mapped_at_ms",
            params![
                mapping.source_item.source_id.as_str(),
                mapping.source_item.item_id.as_str(),
                json(&mapping.evidence)?,
                mapping.material_id.as_str(),
                mapping.material_revision_id.as_str(),
                mapping.mapped_at_ms as i64,
            ],
        )
        .map_err(repo)?;
        Ok(())
    }

    fn resolve(
        &self,
        source_item: &SourceItemIdentity,
    ) -> Result<Option<SourceIdentityMapping>, ApplicationError> {
        let conn = self.connection.lock();
        let row: Option<(String, String, String, String, String, u64)> = conn
            .query_row(
                "SELECT source_id, item_id, evidence_json, material_id, material_revision_id, mapped_at_ms
                 FROM source_identity_mappings WHERE source_id=?1 AND item_id=?2",
                params![source_item.source_id.as_str(), source_item.item_id.as_str()],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, String>(3)?,
                        row.get::<_, String>(4)?,
                        row.get::<_, u64>(5)?,
                    ))
                },
            )
            .optional()
            .map_err(repo)?;
        let Some((source_id, item_id, evidence_json, material_id, revision_id, mapped_at_ms)) = row
        else {
            return Ok(None);
        };
        let parse_id = |value: String, kind: &str| {
            if value.trim().is_empty() {
                Err(ApplicationError::Repository(format!(
                    "stored {kind} identity is empty"
                )))
            } else {
                Ok(value)
            }
        };
        let mapping = SourceIdentityMapping {
            source_item: SourceItemIdentity {
                source_id: ContentSourceId::parse(parse_id(source_id, "source")?)
                    .map_err(|e| ApplicationError::Repository(e.to_string()))?,
                item_id: SourceItemId::parse(parse_id(item_id, "item")?)
                    .map_err(|e| ApplicationError::Repository(e.to_string()))?,
            },
            evidence: from_json(&evidence_json).map_err(repo)?,
            material_id: LearningMaterialId::parse(parse_id(material_id, "material")?)
                .map_err(|e| ApplicationError::Repository(e.to_string()))?,
            material_revision_id: MaterialRevisionId::parse(parse_id(revision_id, "revision")?)
                .map_err(|e| ApplicationError::Repository(e.to_string()))?,
            mapped_at_ms,
        };
        Ok(Some(mapping))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repository() -> SqliteRepository {
        let connection = rusqlite::Connection::open_in_memory().expect("in-memory database");
        super::super::migrate(&connection).expect("migrations run");
        SqliteRepository {
            connection: std::sync::Mutex::new(connection),
            _database_lock: None,
        }
    }

    fn mapping(source: &str, item: &str) -> SourceIdentityMapping {
        SourceIdentityMapping {
            source_item: SourceItemIdentity {
                source_id: ContentSourceId::parse(source).expect("valid source"),
                item_id: SourceItemId::parse(item).expect("valid item"),
            },
            evidence: SourceItemEvidence {
                feed_item_id: Some("guid-1".into()),
                entry_url: Some("https://example.com/entry".into()),
                enclosure_urls: vec!["https://example.com/media.mp3".into()],
                file_sha256: Some("abcd".into()),
                title: Some("Entry".into()),
            },
            material_id: LearningMaterialId::parse("material-1").expect("valid material id"),
            material_revision_id: MaterialRevisionId::parse("revision-1")
                .expect("valid revision id"),
            mapped_at_ms: 10,
        }
    }

    #[test]
    fn mappings_are_source_scoped_and_survive_reopen() {
        let store = repository();
        let first = mapping("rss:https://example.com/feed.xml", "item-1");
        store.save_mapping(&first).expect("saved");

        // Same canonical key under a different source never resolves.
        let other_source = SourceItemIdentity {
            source_id: ContentSourceId::parse("rss:https://other.example.com/feed.xml")
                .expect("valid source"),
            item_id: first.source_item.item_id.clone(),
        };
        assert!(store.resolve(&other_source).expect("resolved").is_none());

        // Reopening keeps the mapping and the recorded evidence.
        let reopened = repository();
        let resolved = reopened
            .resolve(&first.source_item)
            .expect("resolved")
            .expect("mapping");
        assert_eq!(resolved, first);

        // Re-registering converges on the same canonical key with new facts.
        let mut updated = mapping("rss:https://example.com/feed.xml", "item-1");
        updated.mapped_at_ms = 20;
        reopened.save_mapping(&updated).expect("updated");
        let resolved = reopened
            .resolve(&first.source_item)
            .expect("resolved")
            .expect("mapping");
        assert_eq!(resolved.mapped_at_ms, 20);
    }

    #[test]
    fn evidence_fields_are_typed_and_not_identity_substitutes() {
        let store = repository();
        let first = mapping("rss:feed", "item-1");
        store.save_mapping(&first).expect("saved");
        // Equal evidence under a different canonical item key is a different
        // ownership fact.
        let other_item = SourceItemIdentity {
            source_id: first.source_item.source_id.clone(),
            item_id: SourceItemId::parse("item-2").expect("valid item"),
        };
        assert!(store.resolve(&other_item).expect("resolved").is_none());
    }
}
