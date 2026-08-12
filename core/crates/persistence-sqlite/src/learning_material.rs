//! Durable learning-material persistence (SQLite).
//!
//! This module owns persistence for the Phase 1 learning-material graph:
//! `learning_materials`, `material_revisions`, `material_source_assets`,
//! `material_document_renditions`, `material_media_renditions`, and
//! `material_media_bindings`. It hosts the [`MaterialRepository`]
//! implementation that serves the application layer plus the v59 legacy-media
//! backfill.
//!
//! ## Repository semantics
//!
//! Every create/append/membership write runs in one transaction that also
//! synchronizes membership to every bound registered `media_items` row, so the
//! legacy media library projection follows material membership through a
//! single authority. Writes use plain `INSERT`/`UPDATE` targeted at the row's
//! uniqueness identity: equal-content retries converge idempotently on the
//! stored aggregate, while a conflicting insert surfaces as an
//! [`ApplicationError::Conflict`] that rolls back the whole operation.
//!
//! The domain structs have public fields and serde can bypass their
//! constructors, so every create/append candidate is first rebuilt with the
//! domain constructors (`SourceAsset::new`, `DocumentRendition::new`,
//! `MediaRendition::new`, `MaterialRevision::new`, and for creates
//! `LearningMaterial::new`) and required to equal the candidate exactly before
//! any row is read or written. Forged, non-canonical, or internally
//! inconsistent candidates are rejected as [`ApplicationError::Repository`]
//! with no writes. Reads rehydrate typed domain values through the same
//! constructor validation and additionally validate stored ids, ordering, and
//! the deterministic revision identity, surfacing corruption as
//! [`ApplicationError::Repository`] instead of returning inconsistent data.
//!
//! ## v59 legacy-media backfill
//!
//! The v59 migration creates the legacy material schema. Legacy `media_items`
//! rows (Personal Library members and Temporary Material) are backfilled into
//! the graph inside the same transaction, before `user_version` advances. The
//! v61 migration then converts every legacy `media_rendition` asset row into
//! the canonical media rendition table, so fresh and upgraded databases agree
//! on the same canonical model.
//!
//! Membership mirrors `media_items.retained_at_ms` exactly: NULL stays
//! temporary (no `retained_at_ms` on the material), a timestamp stays retained
//! with that exact timestamp. Historical rows whose stored title is blank or
//! whitespace-only fall back to [`LEGACY_BLANK_TITLE_FALLBACK`], so the
//! revision title invariant (never blank) holds without inventing per-row
//! content.

use application::{ApplicationError, MaterialRepository};
use domain::{
    DocumentRendition, DomainError, LearningMaterial, LearningMaterialId, MaterialRevision,
    MaterialRevisionId, MediaAvailability, MediaId, MediaItem, MediaKind, MediaRendition,
    Rendition, RenditionOrigin, SourceAsset, SourceAssetAvailability, SourceAssetBinding,
    initial_material_id,
};
use rusqlite::{Connection, OptionalExtension, Transaction, params};

use super::{
    PersistenceError, SqliteRepository, domain_sql, from_json, json, migrations::table_exists, repo,
};

/// Deterministic fallback title for historical `media_items` rows whose stored
/// title is blank or whitespace-only.
///
/// `MaterialRevision` rejects blank titles and the backfill must not invent
/// per-row content, so every such row substitutes this single fixed,
/// documented constant. The fallback is content-independent, which keeps
/// upgrade behavior deterministic and reversible.
pub(crate) const LEGACY_BLANK_TITLE_FALLBACK: &str = "Media item";

struct LegacyMediaRow {
    media_id: MediaId,
    fingerprint: String,
    title: String,
    kind: MediaKind,
    availability: MediaAvailability,
    retained_at_ms: Option<u64>,
    created_at_ms: u64,
    updated_at_ms: u64,
}

/// Backfills every valid legacy `media_items` row into the learning-material
/// graph. Runs inside the v59 migration transaction, before `user_version`
/// advances, so the whole graph is always persisted atomically with the v59
/// schema and version bump. The v61 migration then migrates the legacy
/// `material_assets` rows into the canonical media rendition table.
pub(crate) fn backfill_legacy_media_materials(
    transaction: &Transaction<'_>,
) -> Result<(), PersistenceError> {
    if !table_exists(transaction, "media_items")? {
        return Ok(());
    }
    let rows = {
        let mut statement = transaction.prepare(
            "SELECT id, fingerprint, title, kind, availability,
                    retained_at_ms, created_at_ms, updated_at_ms
             FROM media_items",
        )?;
        statement
            .query_map([], |row| {
                let media_id = MediaId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?;
                let kind = from_json(&row.get::<_, String>(3)?)?;
                let availability = from_json(&row.get::<_, String>(4)?)?;
                Ok(LegacyMediaRow {
                    media_id,
                    fingerprint: row.get::<_, String>(1)?,
                    title: row.get::<_, String>(2)?,
                    kind,
                    availability,
                    retained_at_ms: row.get::<_, Option<u64>>(5)?,
                    created_at_ms: row.get::<_, u64>(6)?,
                    updated_at_ms: row.get::<_, u64>(7)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?
    };
    for row in rows {
        let title = if row.title.trim().is_empty() {
            LEGACY_BLANK_TITLE_FALLBACK.to_owned()
        } else {
            row.title
        };
        let rendition = MediaRendition::new(
            RenditionOrigin::Source,
            row.kind,
            media_type_for_kind(row.kind),
            row.fingerprint,
            row.availability,
            Some(row.media_id.clone()),
            None,
            None,
            None,
            None,
        )
        .map_err(domain_sql)?;
        let renditions = vec![Rendition::Media(rendition.clone())];
        let material_id = initial_material_id(&[], &renditions).map_err(domain_sql)?;
        let revision = MaterialRevision::new(
            material_id.clone(),
            title,
            Vec::new(),
            renditions,
            row.created_at_ms,
        )
        .map_err(domain_sql)?;
        let material = LearningMaterial::new(
            &revision,
            row.retained_at_ms,
            row.created_at_ms,
            row.updated_at_ms,
        )
        .map_err(domain_sql)?;
        let asset_json = serde_json::to_string(&rendition).map_err(json_sql)?;
        transaction.execute(
            "INSERT INTO learning_materials
               (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
             VALUES (?1,?2,?3,?4,?5)
             ON CONFLICT(id) DO NOTHING",
            params![
                material.id.as_str(),
                material.current_revision_id.as_str(),
                material.retained_at_ms,
                material.created_at_ms,
                material.updated_at_ms,
            ],
        )?;
        transaction.execute(
            "INSERT INTO material_revisions
               (id,material_id,title,created_at_ms)
             VALUES (?1,?2,?3,?4)
             ON CONFLICT(id) DO NOTHING",
            params![
                revision.id.as_str(),
                revision.material_id.as_str(),
                revision.title,
                revision.created_at_ms,
            ],
        )?;
        transaction.execute(
            "INSERT INTO material_assets
               (revision_id,ordinal,asset_id,asset_kind,asset_json)
             VALUES (?1,0,?2,'media_rendition',?3)
             ON CONFLICT(revision_id, ordinal) DO NOTHING",
            params![revision.id.as_str(), rendition.id.as_str(), asset_json],
        )?;
        transaction.execute(
            "INSERT INTO material_media_bindings
               (media_id,material_id)
             VALUES (?1,?2)
             ON CONFLICT(media_id) DO NOTHING",
            params![row.media_id.as_str(), material.id.as_str()],
        )?;
    }
    Ok(())
}

fn media_type_for_kind(kind: MediaKind) -> String {
    match kind {
        MediaKind::Video => "video/mp4".to_owned(),
        MediaKind::Audio => "audio/mpeg".to_owned(),
    }
}

/// Ensures the deterministic learning-material graph exists for a persisted
/// `media_items` row and reconciles membership between the media and its
/// material.
///
/// Called from the legacy [`MediaRepository`](application::MediaRepository)
/// write paths (`upsert_media_in_transaction`,
/// `set_library_membership`) inside the same transaction, so a media write and
/// its canonical material graph are committed together or not at all. The
/// caller passes the ACTUAL persisted row.
///
/// Every row is derived through the domain constructors with the same
/// validation conventions as the v59 backfill: one material keyed on the media
/// id, one initial revision, one Source media rendition snapshotting only
/// id/kind/fingerprint/availability (never the path), and one binding.
/// Repeated registration and managed-path rebinding converge on the stored
/// aggregate without appending a revision or rewriting identity, creation
/// time, the current pointer, or learner state. A media already bound to a
/// different material is a conflict that rolls back the whole operation.
pub(crate) fn ensure_media_material_in_transaction(
    tx: &Transaction<'_>,
    media: &MediaItem,
) -> Result<(), ApplicationError> {
    let title = if media.title.trim().is_empty() {
        LEGACY_BLANK_TITLE_FALLBACK.to_owned()
    } else {
        media.title.clone()
    };
    let rendition = MediaRendition::new(
        RenditionOrigin::Source,
        media.kind,
        media_type_for_kind(media.kind),
        media.fingerprint.clone(),
        media.availability,
        Some(media.id.clone()),
        None,
        None,
        None,
        None,
    )
    .map_err(media_graph_error)?;
    let renditions = vec![Rendition::Media(rendition)];
    let material_id = initial_material_id(&[], &renditions).map_err(media_graph_error)?;
    let revision = MaterialRevision::new(
        material_id.clone(),
        title,
        Vec::new(),
        renditions,
        media.created_at_ms,
    )
    .map_err(media_graph_error)?;
    let material = LearningMaterial::new(
        &revision,
        media.retained_at_ms,
        media.created_at_ms,
        media.updated_at_ms,
    )
    .map_err(media_graph_error)?;

    let existing: Option<String> = tx
        .query_row(
            "SELECT material_id FROM material_media_bindings WHERE media_id=?1",
            [media.id.as_str()],
            |row| row.get(0),
        )
        .optional()
        .map_err(repo)?;
    match existing {
        Some(bound) if bound == material.id.as_str() => {
            // The deterministic graph already exists: converge on the stored
            // aggregate. Binding facts (path, title, kind) that changed
            // through the legacy register API never append a revision or
            // rewrite identity, creation time, the current pointer, or
            // learner state.
            let stored = query_material(tx, material.id.as_str())?.ok_or_else(|| {
                ApplicationError::Repository(format!(
                    "media {} is bound to missing material {}",
                    media.id.as_str(),
                    material.id.as_str()
                ))
            })?;
            let stored_revision = query_revision(tx, stored.current_revision_id.as_str())?
                .ok_or_else(|| {
                    ApplicationError::Repository(format!(
                        "material {} current revision {} is missing",
                        stored.id.as_str(),
                        stored.current_revision_id.as_str()
                    ))
                })?;
            return Ok(());
        }
        Some(_) => {
            return Err(ApplicationError::Conflict(
                "media rendition belongs to another material",
            ));
        }
        None => {}
    }

    insert_revision(tx, &revision)?;
    insert_components(tx, &revision)?;
    tx.execute(
        "INSERT INTO material_media_bindings (media_id, material_id)
         VALUES (?1,?2)",
        params![media.id.as_str(), material.id.as_str()],
    )
    .map_err(repo)?;
    tx.execute(
        "INSERT INTO learning_materials
           (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
         VALUES (?1,?2,?3,?4,?5)",
        params![
            material.id.as_str(),
            material.current_revision_id.as_str(),
            material.retained_at_ms,
            material.created_at_ms,
            material.updated_at_ms,
        ],
    )
    .map_err(|error| {
        if is_primary_key_violation(&error) {
            ApplicationError::Conflict("media rendition belongs to another material")
        } else {
            repo(error)
        }
    })?;
    Ok(())
}

fn media_graph_error(error: DomainError) -> ApplicationError {
    ApplicationError::Repository(format!("legacy media material graph is invalid: {error}"))
}

/// Reconciles the membership of the material bound to `media_id` from the
/// media's membership, mirroring the legacy projection when the material
/// exists.
pub(crate) fn reconcile_media_material_membership(
    tx: &Transaction<'_>,
    media: &MediaItem,
) -> Result<(), ApplicationError> {
    let Some(material_id) = tx
        .query_row(
            "SELECT material_id FROM material_media_bindings WHERE media_id=?1",
            [media.id.as_str()],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(repo)?
    else {
        return Ok(());
    };
    tx.execute(
        "UPDATE learning_materials SET retained_at_ms=?2, updated_at_ms=?3 WHERE id=?1",
        params![material_id, media.retained_at_ms, media.updated_at_ms],
    )
    .map_err(repo)?;
    Ok(())
}

/// Applies the aggregate's membership to every media currently bound to the
/// material, inside the caller's transaction.
pub(crate) fn apply_media_membership_in_transaction(
    tx: &Transaction<'_>,
    material_id: &str,
    retained_at_ms: Option<u64>,
    updated_at_ms: u64,
) -> Result<(), ApplicationError> {
    tx.execute(
        "UPDATE media_items
         SET retained_at_ms=?2, updated_at_ms=?3
         WHERE id IN (SELECT media_id FROM material_media_bindings WHERE material_id=?1)",
        params![material_id, retained_at_ms, updated_at_ms],
    )
    .map_err(repo)?;
    Ok(())
}

fn json_sql(error: serde_json::Error) -> rusqlite::Error {
    rusqlite::Error::ToSqlConversionFailure(Box::new(error))
}

/// The `learning_materials` columns in storage order, used by every read that
/// rehydrates a typed [`LearningMaterial`].
const MATERIAL_COLUMNS: &str =
    "id, current_revision_id, retained_at_ms, created_at_ms, updated_at_ms";

/// Maps one `learning_materials` row (in [`MATERIAL_COLUMNS`] order) into a
/// typed [`LearningMaterial`]. Stored identifiers must parse as typed ids;
/// anything else is corruption.
fn material_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<LearningMaterial> {
    Ok(LearningMaterial {
        id: LearningMaterialId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
        current_revision_id: MaterialRevisionId::parse(row.get::<_, String>(1)?)
            .map_err(domain_sql)?,
        retained_at_ms: row.get::<_, Option<u64>>(2)?,
        created_at_ms: row.get::<_, u64>(3)?,
        updated_at_ms: row.get::<_, u64>(4)?,
    })
}

/// Reads one material row by id, or `None` when the material does not exist.
fn query_material(
    connection: &Connection,
    material_id: &str,
) -> Result<Option<LearningMaterial>, ApplicationError> {
    connection
        .query_row(
            &format!("SELECT {MATERIAL_COLUMNS} FROM learning_materials WHERE id=?1"),
            [material_id],
            material_from_row,
        )
        .optional()
        .map_err(repo)
}

/// Loads a revision's Source Assets in canonical id order, validating each
/// stored row.
fn load_source_assets(
    connection: &Connection,
    revision_id: &str,
) -> Result<Vec<SourceAsset>, ApplicationError> {
    let mut statement = connection
        .prepare(
            "SELECT asset_id, media_type, byte_length, sha256_digest,
                    binding_json, availability_json, created_at_ms
             FROM material_source_assets WHERE revision_id=?1 ORDER BY asset_id",
        )
        .map_err(repo)?;
    let rows = statement
        .query_map([revision_id], |row| {
            let binding: SourceAssetBinding =
                from_json(&row.get::<_, String>(4)?).map_err(|error| {
                    rusqlite::Error::FromSqlConversionFailure(
                        4,
                        rusqlite::types::Type::Text,
                        Box::new(error),
                    )
                })?;
            let availability: SourceAssetAvailability = from_json(&row.get::<_, String>(5)?)
                .map_err(|error| {
                    rusqlite::Error::FromSqlConversionFailure(
                        5,
                        rusqlite::types::Type::Text,
                        Box::new(error),
                    )
                })?;
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, u64>(2)?,
                row.get::<_, String>(3)?,
                binding,
                availability,
                row.get::<_, u64>(6)?,
            ))
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)?;
    let mut assets = Vec::with_capacity(rows.len());
    for (asset_id, media_type, byte_length, sha256_digest, binding, availability, created_at_ms) in
        rows
    {
        let rebuilt = SourceAsset::new(
            media_type,
            byte_length,
            sha256_digest,
            binding,
            availability,
            created_at_ms,
        )
        .map_err(|error| {
            ApplicationError::Repository(format!(
                "revision {revision_id} stored source asset is corrupt: {error}"
            ))
        })?;
        if rebuilt.id.as_str() != asset_id {
            return Err(ApplicationError::Repository(format!(
                "revision {revision_id} stored source asset id does not match its facts"
            )));
        }
        assets.push(rebuilt);
    }
    Ok(assets)
}

/// Loads a revision's Document Renditions in canonical id order, validating
/// each stored row through the domain constructor.
fn load_document_renditions(
    connection: &Connection,
    revision_id: &str,
) -> Result<Vec<DocumentRendition>, ApplicationError> {
    let mut statement = connection
        .prepare(
            "SELECT rendition_id, origin, media_type, language, text_bytes,
                    text_sha256, text_byte_size, source_asset_id, producer_json,
                    compatibility_json
             FROM material_document_renditions WHERE revision_id=?1 ORDER BY rendition_id",
        )
        .map_err(repo)?;
    let rows = statement
        .query_map([revision_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, Option<String>>(3)?,
                row.get::<_, Vec<u8>>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, u64>(6)?,
                row.get::<_, Option<String>>(7)?,
                row.get::<_, Option<String>>(8)?,
                row.get::<_, Option<String>>(9)?,
            ))
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)?;
    let mut renditions = Vec::with_capacity(rows.len());
    for (
        rendition_id,
        origin,
        media_type,
        language,
        text_bytes,
        text_sha256,
        text_byte_size,
        source_asset_id,
        producer_json,
        compatibility_json,
    ) in rows
    {
        let origin = match origin.as_str() {
            "source" => RenditionOrigin::Source,
            "derived" => RenditionOrigin::Derived,
            other => {
                return Err(ApplicationError::Repository(format!(
                    "revision {revision_id} stored document rendition has unknown origin {other}"
                )));
            }
        };
        let language = language
            .map(|code| {
                domain::LanguageCode::parse(code)
                    .map_err(|error| ApplicationError::Repository(error.to_string()))
            })
            .transpose()?;
        let text = String::from_utf8(text_bytes).map_err(|_| {
            ApplicationError::Repository(format!(
                "revision {revision_id} stored document rendition text is not UTF-8"
            ))
        })?;
        use sha2::Digest as _;
        if text_sha256 != hex::encode(sha2::Sha256::digest(text.as_bytes())) {
            return Err(ApplicationError::Repository(format!(
                "revision {revision_id} stored document rendition digest does not match its text"
            )));
        }
        if text_byte_size != text.len() as u64 {
            return Err(ApplicationError::Repository(format!(
                "revision {revision_id} stored document rendition byte size does not match its text"
            )));
        }
        let producer = producer_json
            .map(|json| from_json::<domain::ProducerFact>(&json).map_err(repo))
            .transpose()?;
        let compatibility = compatibility_json
            .map(|json| from_json::<domain::CompatibilityEvidence>(&json).map_err(repo))
            .transpose()?;
        let source_asset_id = source_asset_id
            .map(|id| {
                domain::SourceAssetId::parse(id)
                    .map_err(|error| ApplicationError::Repository(error.to_string()))
            })
            .transpose()?;
        let rebuilt = DocumentRendition::new(
            origin,
            media_type,
            language,
            text,
            source_asset_id,
            producer,
            compatibility,
        )
        .map_err(|error| {
            ApplicationError::Repository(format!(
                "revision {revision_id} stored document rendition is corrupt: {error}"
            ))
        })?;
        if rebuilt.id.as_str() != rendition_id {
            return Err(ApplicationError::Repository(format!(
                "revision {revision_id} stored document rendition id does not match its content"
            )));
        }
        renditions.push(rebuilt);
    }
    Ok(renditions)
}

/// Loads a revision's Media Renditions in canonical id order, validating each
/// stored row through the domain constructor.
fn load_media_renditions(
    connection: &Connection,
    revision_id: &str,
) -> Result<Vec<MediaRendition>, ApplicationError> {
    let mut statement = connection
        .prepare(
            "SELECT rendition_id, origin, kind, media_type, fingerprint, availability,
                    media_sha256, media_byte_size, media_id, producer_json, compatibility_json
             FROM material_media_renditions WHERE revision_id=?1 ORDER BY rendition_id",
        )
        .map_err(repo)?;
    let rows = statement
        .query_map([revision_id], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, String>(5)?,
                row.get::<_, Option<String>>(6)?,
                row.get::<_, Option<u64>>(7)?,
                row.get::<_, Option<String>>(8)?,
                row.get::<_, Option<String>>(9)?,
                row.get::<_, Option<String>>(10)?,
            ))
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)?;
    let mut renditions = Vec::with_capacity(rows.len());
    for (
        rendition_id,
        origin,
        kind,
        media_type,
        fingerprint,
        availability,
        media_sha256,
        media_byte_size,
        media_id,
        producer_json,
        compatibility_json,
    ) in rows
    {
        let origin = match origin.as_str() {
            "source" => RenditionOrigin::Source,
            "derived" => RenditionOrigin::Derived,
            other => {
                return Err(ApplicationError::Repository(format!(
                    "revision {revision_id} stored media rendition has unknown origin {other}"
                )));
            }
        };
        let kind = match kind.as_str() {
            "audio" => MediaKind::Audio,
            "video" => MediaKind::Video,
            other => {
                return Err(ApplicationError::Repository(format!(
                    "revision {revision_id} stored media rendition has unknown kind {other}"
                )));
            }
        };
        let availability = match availability.as_str() {
            "available" => MediaAvailability::Available,
            "missing" => MediaAvailability::Missing,
            "archived" => MediaAvailability::Archived,
            other => {
                return Err(ApplicationError::Repository(format!(
                    "revision {revision_id} stored media rendition has unknown availability {other}"
                )));
            }
        };
        let media_id = media_id
            .map(|id| {
                MediaId::parse(id).map_err(|error| ApplicationError::Repository(error.to_string()))
            })
            .transpose()?;
        let producer = producer_json
            .map(|json| from_json::<domain::ProducerFact>(&json).map_err(repo))
            .transpose()?;
        let compatibility = compatibility_json
            .map(|json| from_json::<domain::CompatibilityEvidence>(&json).map_err(repo))
            .transpose()?;
        let rebuilt = MediaRendition::new(
            origin,
            kind,
            media_type,
            fingerprint,
            availability,
            media_id,
            media_sha256,
            media_byte_size,
            producer,
            compatibility,
        )
        .map_err(|error| {
            ApplicationError::Repository(format!(
                "revision {revision_id} stored media rendition is corrupt: {error}"
            ))
        })?;
        if rebuilt.id.as_str() != rendition_id {
            return Err(ApplicationError::Repository(format!(
                "revision {revision_id} stored media rendition id does not match its content"
            )));
        }
        renditions.push(rebuilt);
    }
    Ok(renditions)
}

/// Maps a stored revision into a typed [`MaterialRevision`].
///
/// The stored title, components, and created timestamp must reconstruct the
/// same deterministic revision identity as the stored revision id; anything
/// else is corruption surfaced as [`ApplicationError::Repository`].
fn query_revision(
    connection: &Connection,
    revision_id: &str,
) -> Result<Option<MaterialRevision>, ApplicationError> {
    let Some((material_id, title, created_at_ms)) = connection
        .query_row(
            "SELECT material_id, title, created_at_ms FROM material_revisions WHERE id=?1",
            [revision_id],
            |row| {
                Ok((
                    LearningMaterialId::parse(row.get::<_, String>(0)?).map_err(domain_sql)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, u64>(2)?,
                ))
            },
        )
        .optional()
        .map_err(repo)?
    else {
        return Ok(None);
    };
    let source_assets = load_source_assets(connection, revision_id)?;
    let document_renditions = load_document_renditions(connection, revision_id)?;
    let media_renditions = load_media_renditions(connection, revision_id)?;
    let renditions: Vec<Rendition> = document_renditions
        .into_iter()
        .map(Rendition::Document)
        .chain(media_renditions.into_iter().map(Rendition::Media))
        .collect();
    let rehydrated =
        MaterialRevision::new(material_id, title, source_assets, renditions, created_at_ms)
            .map_err(|error| {
                ApplicationError::Repository(format!(
                    "stored revision {revision_id} is corrupt: {error}"
                ))
            })?;
    if rehydrated.id.as_str() != revision_id {
        return Err(ApplicationError::Repository(format!(
            "stored revision {revision_id} identity does not match its components"
        )));
    }
    Ok(Some(rehydrated))
}

/// Persists one binding per Source media rendition. The binding deliberately
/// carries no foreign key to `media_items`, so it stays durable when the media
/// is not registered. A media already bound to the same material is an
/// idempotent re-bind (revisions may repeat an earlier rendition); a media
/// bound to another material is a conflict that rolls back the whole
/// operation.
fn insert_bindings(
    connection: &Connection,
    revision: &MaterialRevision,
) -> Result<(), ApplicationError> {
    for rendition in &revision.renditions {
        let Rendition::Media(media) = rendition else {
            continue;
        };
        let Some(media_id) = &media.media_id else {
            continue;
        };
        let existing: Option<String> = connection
            .query_row(
                "SELECT material_id FROM material_media_bindings WHERE media_id=?1",
                [media_id.as_str()],
                |row| row.get(0),
            )
            .optional()
            .map_err(repo)?;
        match existing {
            Some(material_id) if material_id == revision.material_id.as_str() => {
                // Already bound to this material: nothing to write.
            }
            Some(_) => {
                return Err(ApplicationError::Conflict(
                    "media rendition belongs to another material",
                ));
            }
            None => {
                connection
                    .execute(
                        "INSERT INTO material_media_bindings (media_id, material_id)
                         VALUES (?1,?2)",
                        params![media_id.as_str(), revision.material_id.as_str()],
                    )
                    .map_err(|error| {
                        if is_primary_key_violation(&error) {
                            ApplicationError::Conflict(
                                "media rendition belongs to another material",
                            )
                        } else {
                            repo(error)
                        }
                    })?;
            }
        }
    }
    Ok(())
}

/// Persists one immutable revision row. A duplicate revision id is a conflict,
/// never a silent rewrite.
fn insert_revision(
    connection: &Connection,
    revision: &MaterialRevision,
) -> Result<(), ApplicationError> {
    connection
        .execute(
            "INSERT INTO material_revisions (id, material_id, title, created_at_ms)
             VALUES (?1,?2,?3,?4)",
            params![
                revision.id.as_str(),
                revision.material_id.as_str(),
                revision.title,
                revision.created_at_ms,
            ],
        )
        .map_err(|error| {
            if is_primary_key_violation(&error) {
                ApplicationError::Conflict("revision already exists")
            } else {
                repo(error)
            }
        })?;
    Ok(())
}

/// Persists the revision's typed components: Source Assets, Document
/// Renditions, and Media Renditions, each in canonical id order.
fn insert_components(
    connection: &Connection,
    revision: &MaterialRevision,
) -> Result<(), ApplicationError> {
    let mut source_assets = revision.source_assets.clone();
    source_assets.sort_by(|a, b| a.id.as_str().cmp(b.id.as_str()));
    for asset in &source_assets {
        connection
            .execute(
                "INSERT INTO material_source_assets
                   (revision_id, asset_id, media_type, byte_length, sha256_digest,
                    binding_json, availability_json, created_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
                params![
                    revision.id.as_str(),
                    asset.id.as_str(),
                    asset.media_type,
                    asset.byte_length as i64,
                    asset.sha256_digest,
                    json(&asset.binding)?,
                    json(&asset.availability)?,
                    asset.created_at_ms as i64,
                ],
            )
            .map_err(repo)?;
    }
    let mut document_renditions: Vec<&DocumentRendition> = revision
        .renditions
        .iter()
        .filter_map(|component| match component {
            Rendition::Document(rendition) => Some(rendition),
            Rendition::Media(_) => None,
        })
        .collect();
    document_renditions.sort_by(|a, b| a.id.as_str().cmp(b.id.as_str()));
    for rendition in document_renditions {
        connection
            .execute(
                "INSERT INTO material_document_renditions
                   (revision_id, rendition_id, origin, media_type, language, text_bytes,
                    text_sha256, text_byte_size, source_asset_id, producer_json,
                    compatibility_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)",
                params![
                    revision.id.as_str(),
                    rendition.id.as_str(),
                    match rendition.origin {
                        RenditionOrigin::Source => "source",
                        RenditionOrigin::Derived => "derived",
                    },
                    rendition.media_type,
                    rendition
                        .language
                        .as_ref()
                        .map(domain::LanguageCode::as_str),
                    rendition.text.as_bytes(),
                    rendition.text_sha256,
                    rendition.text_byte_size as i64,
                    rendition
                        .source_asset_id
                        .as_ref()
                        .map(domain::SourceAssetId::as_str),
                    serde_json::to_string(&rendition.producer).ok(),
                    serde_json::to_string(&rendition.compatibility).ok(),
                ],
            )
            .map_err(repo)?;
    }
    let mut media_renditions: Vec<&MediaRendition> = revision
        .renditions
        .iter()
        .filter_map(|component| match component {
            Rendition::Media(rendition) => Some(rendition),
            Rendition::Document(_) => None,
        })
        .collect();
    media_renditions.sort_by(|a, b| a.id.as_str().cmp(b.id.as_str()));
    for rendition in media_renditions {
        connection
            .execute(
                "INSERT INTO material_media_renditions
                   (revision_id, rendition_id, origin, kind, media_type, fingerprint,
                    availability, media_sha256, media_byte_size, media_id, producer_json,
                    compatibility_json)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)",
                params![
                    revision.id.as_str(),
                    rendition.id.as_str(),
                    match rendition.origin {
                        RenditionOrigin::Source => "source",
                        RenditionOrigin::Derived => "derived",
                    },
                    match rendition.kind {
                        MediaKind::Video => "video",
                        MediaKind::Audio => "audio",
                    },
                    rendition.media_type,
                    rendition.fingerprint,
                    match rendition.availability {
                        MediaAvailability::Available => "available",
                        MediaAvailability::Missing => "missing",
                        MediaAvailability::Archived => "archived",
                    },
                    rendition.media_sha256,
                    rendition.media_byte_size.map(|size| size as i64),
                    rendition.media_id.as_ref().map(MediaId::as_str),
                    serde_json::to_string(&rendition.producer).ok(),
                    serde_json::to_string(&rendition.compatibility).ok(),
                ],
            )
            .map_err(repo)?;
    }
    Ok(())
}

fn is_primary_key_violation(error: &rusqlite::Error) -> bool {
    matches!(
        error,
        rusqlite::Error::SqliteFailure(ffi_error, _)
            if ffi_error.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_PRIMARYKEY
    )
}

/// Rebuilds a typed component with its domain constructor and requires exact
/// equality with the candidate.
///
/// The domain structs have public fields and serde can bypass their
/// constructors, so a candidate may carry a forged id, digest, byte size, or
/// other field that no longer derives from the content it claims. Rebuilding
/// the component from its own fields recomputes every derived fact and
/// rejects anything that is not the exact canonical form.
fn validate_component(component: &Rendition) -> Result<Rendition, ApplicationError> {
    match component {
        Rendition::Document(rendition) => {
            let rebuilt = DocumentRendition::new(
                rendition.origin,
                rendition.media_type.clone(),
                rendition.language.clone(),
                rendition.text.clone(),
                rendition.source_asset_id.clone(),
                rendition.producer.clone(),
                rendition.compatibility.clone(),
            )
            .map_err(|error| {
                ApplicationError::Repository(format!(
                    "typed document rendition is invalid: {error}"
                ))
            })?;
            if &rebuilt != rendition {
                return Err(ApplicationError::Repository(
                    "typed document rendition is not canonical".into(),
                ));
            }
            Ok(Rendition::Document(rebuilt))
        }
        Rendition::Media(rendition) => {
            let rebuilt = MediaRendition::new(
                rendition.origin,
                rendition.kind,
                rendition.media_type.clone(),
                rendition.fingerprint.clone(),
                rendition.availability,
                rendition.media_id.clone(),
                rendition.media_sha256.clone(),
                rendition.media_byte_size,
                rendition.producer.clone(),
                rendition.compatibility.clone(),
            )
            .map_err(|error| {
                ApplicationError::Repository(format!("typed media rendition is invalid: {error}"))
            })?;
            if &rebuilt != rendition {
                return Err(ApplicationError::Repository(
                    "typed media rendition is not canonical".into(),
                ));
            }
            Ok(Rendition::Media(rebuilt))
        }
    }
}

/// Rebuilds a candidate revision from its parts with the domain constructors
/// and requires exact typed equality with the candidate.
///
/// `MaterialRevision::new` re-canonicalizes the components and re-derives the
/// deterministic identity, so a forged title, a non-canonical component order,
/// forged component fields, or any internally inconsistent combination is
/// rejected as [`ApplicationError::Repository`]. Equal-content retries at a
/// different time still pass because `created_at_ms` is not part of revision
/// identity.
fn validate_revision(revision: &MaterialRevision) -> Result<MaterialRevision, ApplicationError> {
    let mut source_assets = Vec::with_capacity(revision.source_assets.len());
    for asset in &revision.source_assets {
        let rebuilt = SourceAsset::new(
            asset.media_type.clone(),
            asset.byte_length,
            asset.sha256_digest.clone(),
            asset.binding.clone(),
            asset.availability.clone(),
            asset.created_at_ms,
        )
        .map_err(|error| {
            ApplicationError::Repository(format!("typed source asset is invalid: {error}"))
        })?;
        if &rebuilt != asset {
            return Err(ApplicationError::Repository(
                "typed source asset is not canonical".into(),
            ));
        }
        source_assets.push(rebuilt);
    }
    let mut renditions = Vec::with_capacity(revision.renditions.len());
    for component in &revision.renditions {
        renditions.push(validate_component(component)?);
    }
    let rebuilt = MaterialRevision::new(
        revision.material_id.clone(),
        revision.title.clone(),
        source_assets,
        renditions,
        revision.created_at_ms,
    )
    .map_err(|error| {
        ApplicationError::Repository(format!("candidate revision is invalid: {error}"))
    })?;
    if &rebuilt != revision {
        return Err(ApplicationError::Repository(
            "candidate revision is not canonical".into(),
        ));
    }
    Ok(rebuilt)
}

/// Rebuilds a new material from the validated revision plus the candidate
/// membership, creation, and update timestamps, requiring exact equality with
/// the candidate.
///
/// `LearningMaterial::new` re-derives the material id from the initial
/// components, points `current_revision_id` at the validated revision, and
/// enforces the timestamp relations. This catches a forged material id, a
/// forged `current_revision_id` pointer, or an inconsistent timestamp
/// relation before any existing-row check or write can act on the candidate.
fn validate_material(
    material: &LearningMaterial,
    revision: &MaterialRevision,
) -> Result<LearningMaterial, ApplicationError> {
    let rebuilt = LearningMaterial::new(
        revision,
        material.retained_at_ms,
        material.created_at_ms,
        material.updated_at_ms,
    )
    .map_err(|error| {
        ApplicationError::Repository(format!("candidate material is invalid: {error}"))
    })?;
    if &rebuilt != material {
        return Err(ApplicationError::Repository(
            "candidate material is not canonical".into(),
        ));
    }
    Ok(rebuilt)
}

impl MaterialRepository for SqliteRepository {
    fn create_material(
        &self,
        material: &LearningMaterial,
        revision: &MaterialRevision,
    ) -> Result<LearningMaterial, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let revision = validate_revision(revision)?;
        let material = validate_material(material, &revision)?;
        if let Some(stored) = query_material(&tx, material.id.as_str())? {
            if stored.current_revision_id != revision.id {
                return Err(ApplicationError::Conflict(
                    "material already exists with a different current revision",
                ));
            }
            query_revision(&tx, revision.id.as_str())?.ok_or_else(|| {
                ApplicationError::Repository(format!(
                    "current revision {} is missing",
                    revision.id.as_str()
                ))
            })?;
            return Ok(stored);
        }
        tx.execute(
            "INSERT INTO learning_materials
               (id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms)
             VALUES (?1,?2,?3,?4,?5)",
            params![
                material.id.as_str(),
                material.current_revision_id.as_str(),
                material.retained_at_ms,
                material.created_at_ms,
                material.updated_at_ms,
            ],
        )
        .map_err(repo)?;
        insert_revision(&tx, &revision)?;
        insert_components(&tx, &revision)?;
        insert_bindings(&tx, &revision)?;
        tx.commit().map_err(repo)?;
        Ok(material)
    }

    fn append_revision(
        &self,
        material_id: &LearningMaterialId,
        revision: &MaterialRevision,
        updated_at_ms: u64,
    ) -> Result<LearningMaterial, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let revision = validate_revision(revision)?;
        if revision.material_id != *material_id {
            return Err(ApplicationError::Conflict(
                "revision belongs to another material",
            ));
        }
        let material = query_material(&tx, material_id.as_str())?
            .ok_or(ApplicationError::NotFound("material"))?;
        if material.current_revision_id == revision.id {
            query_revision(&tx, revision.id.as_str())?.ok_or_else(|| {
                ApplicationError::Repository(format!(
                    "current revision {} is missing",
                    revision.id.as_str()
                ))
            })?;
            return Ok(material);
        }
        insert_revision(&tx, &revision)?;
        insert_components(&tx, &revision)?;
        insert_bindings(&tx, &revision)?;
        let updated = tx
            .query_row(
                "UPDATE learning_materials
                 SET current_revision_id=?2, updated_at_ms=?3
                 WHERE id=?1
                 RETURNING id, current_revision_id, retained_at_ms, created_at_ms, updated_at_ms",
                params![material_id.as_str(), revision.id.as_str(), updated_at_ms],
                material_from_row,
            )
            .map_err(repo)?;
        tx.commit().map_err(repo)?;
        Ok(updated)
    }

    fn get_material(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Option<LearningMaterial>, ApplicationError> {
        let conn = self.connection.lock();
        query_material(&conn, material_id.as_str())
    }

    fn get_revision(
        &self,
        revision_id: &MaterialRevisionId,
    ) -> Result<Option<MaterialRevision>, ApplicationError> {
        let conn = self.connection.lock();
        query_revision(&conn, revision_id.as_str())
    }

    fn list_retained_materials(&self) -> Result<Vec<LearningMaterial>, ApplicationError> {
        let conn = self.connection.lock();
        let mut statement = conn
            .prepare(&format!(
                "SELECT {MATERIAL_COLUMNS} FROM learning_materials
                 WHERE retained_at_ms IS NOT NULL ORDER BY id"
            ))
            .map_err(repo)?;
        let rows = statement
            .query_map([], material_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(rows)
    }

    fn set_library_membership(
        &self,
        material_id: &LearningMaterialId,
        retained_at_ms: Option<u64>,
        updated_at_ms: u64,
    ) -> Result<LearningMaterial, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let material = query_material(&tx, material_id.as_str())?
            .ok_or(ApplicationError::NotFound("material"))?;
        let updated = tx
            .query_row(
                "UPDATE learning_materials
                 SET retained_at_ms=?2, updated_at_ms=?3
                 WHERE id=?1
                 RETURNING id, current_revision_id, retained_at_ms, created_at_ms, updated_at_ms",
                params![material_id.as_str(), retained_at_ms, updated_at_ms],
                material_from_row,
            )
            .map_err(repo)?;
        apply_media_membership_in_transaction(
            &tx,
            material_id.as_str(),
            retained_at_ms,
            updated_at_ms,
        )?;
        tx.commit().map_err(repo)?;
        Ok(updated)
    }

    fn material_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Option<LearningMaterial>, ApplicationError> {
        let conn = self.connection.lock();
        let material_id: Option<String> = conn
            .query_row(
                "SELECT material_id FROM material_media_bindings WHERE media_id=?1",
                [media_id.as_str()],
                |row| row.get(0),
            )
            .optional()
            .map_err(repo)?;
        let Some(material_id) = material_id else {
            return Ok(None);
        };
        query_material(&conn, &material_id)
    }

    fn set_source_asset_availability(
        &self,
        material_id: &LearningMaterialId,
        source_asset_id: &domain::SourceAssetId,
        availability: SourceAssetAvailability,
    ) -> Result<Option<MaterialRevision>, ApplicationError> {
        let conn = self.connection.lock();
        let Some(material) = query_material(&conn, material_id.as_str())? else {
            return Ok(None);
        };
        let changed = conn
            .execute(
                "UPDATE material_source_assets
                 SET availability_json=?3
                 WHERE revision_id=?1 AND asset_id=?2",
                params![
                    material.current_revision_id.as_str(),
                    source_asset_id.as_str(),
                    json(&availability)?,
                ],
            )
            .map_err(repo)?;
        if changed == 0 {
            return Ok(None);
        }
        query_revision(&conn, material.current_revision_id.as_str())
    }
}
