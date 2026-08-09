//! Durable learning-material persistence (SQLite).
//!
//! This module owns persistence for the Phase 1 learning-material graph:
//! `learning_materials`, `material_revisions`, `material_assets`, and
//! `material_media_bindings`. It currently hosts the v59 legacy-media
//! backfill; the `MaterialRepository` implementation that serves the
//! application layer lands here in a later slice.
//!
//! ## v59 legacy-media backfill
//!
//! The v59 migration creates the durable learning-material schema. Legacy
//! `media_items` rows (Personal Library members and Temporary Material) are
//! the first class of material a learner owns, so the migration backfills
//! every valid row into the graph inside the same transaction, before
//! `user_version` advances. Each legacy row becomes one material with a single
//! initial revision carrying exactly one `media_rendition` asset that
//! snapshots the authoritative media id, kind, fingerprint, and availability.
//! The media path is deliberately never selected, serialized, or copied into
//! `material_assets`: a rendition is a typed snapshot, not a file reference.
//!
//! Membership mirrors `media_items.retained_at_ms` exactly: NULL stays
//! temporary (no `retained_at_ms` on the material), a timestamp stays retained
//! with that exact timestamp. `created_at_ms` and `updated_at_ms` are
//! preserved verbatim. Historical rows whose stored title is blank or
//! whitespace-only fall back to [`LEGACY_BLANK_TITLE_FALLBACK`], so the
//! revision title invariant (never blank) holds without inventing per-row
//! content.
//!
//! All identities are derived through the domain model
//! ([`MediaRenditionAsset`], [`domain::initial_material_id`],
//! [`MaterialRevision`], [`LearningMaterial`]). Every write targets the row's
//! uniqueness identity with `INSERT ... ON CONFLICT DO NOTHING`, so retries,
//! downgrade/upgrade cycles, and manual re-runs converge idempotently on the
//! same graph rows, while NOT NULL, CHECK, and foreign-key failures still
//! surface as migration errors instead of being silently suppressed. Domain or
//! serde failures convert into the repository migration error path and abort
//! the upgrade atomically instead of silently dropping learner-visible
//! material. The helper requires an active transaction so the whole graph is
//! always persisted atomically with the v59 schema and version bump.

use domain::{
    LearningMaterial, MaterialAsset, MaterialRevision, MediaAvailability, MediaId, MediaKind,
    MediaRenditionAsset, initial_material_id,
};
use rusqlite::{Transaction, params};

use super::{PersistenceError, domain_sql, from_json, migrations::table_exists};

/// Deterministic fallback title for historical `media_items` rows whose stored
/// title is blank or whitespace-only.
///
/// `MaterialRevision` rejects blank titles and the backfill must not invent
/// per-row content, so every such row substitutes this single fixed,
/// documented constant. The fallback is content-independent, which keeps
/// retries and upgrades convergent on the same material and revision identity.
pub(crate) const LEGACY_BLANK_TITLE_FALLBACK: &str = "Untitled media";

/// The legacy media row fields the v59 backfill reads from `media_items`.
///
/// The `path` column is deliberately not selected: a media rendition asset is
/// a typed snapshot of id/kind/fingerprint/availability and never a file
/// reference, so the path cannot be serialized or copied into
/// `material_assets`.
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

/// Backfills every valid legacy `media_items` row into the durable
/// learning-material graph.
///
/// Called by the v59 migration inside its transaction, after
/// `0059_learning_materials.sql` has created the schema and before
/// `user_version` advances to 59. Databases without `media_items` (sparse
/// historical fixtures) migrate cleanly without touching the graph.
///
/// The helper requires an active transaction: it must never run against a bare
/// connection, because the graph rows, the v59 schema, and the version bump
/// are committed together or not at all. Retry safety comes from
/// `INSERT ... ON CONFLICT DO NOTHING` targeted at each table's uniqueness
/// identity (`learning_materials(id)`, `material_revisions(id)`,
/// `material_assets(revision_id, ordinal)`, `material_media_bindings(media_id)`):
/// only a repeated row is ignored, while NOT NULL, CHECK, and foreign-key
/// failures still fail loudly and roll back the upgrade.
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
        let rendition = MediaRenditionAsset::new(
            row.media_id.clone(),
            row.kind,
            row.fingerprint,
            row.availability,
        )
        .map_err(domain_sql)?;
        let assets = vec![MaterialAsset::MediaRendition(rendition)];
        let material_id = initial_material_id(&assets).map_err(domain_sql)?;
        let revision = MaterialRevision::new(material_id.clone(), title, assets, row.created_at_ms)
            .map_err(domain_sql)?;
        let material = LearningMaterial::new(
            &revision,
            row.retained_at_ms,
            row.created_at_ms,
            row.updated_at_ms,
        )
        .map_err(domain_sql)?;
        let asset = revision
            .assets
            .first()
            .expect("legacy media backfill always yields exactly one rendition asset");
        let asset_json = serde_json::to_string(asset).map_err(json_sql)?;
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
            params![revision.id.as_str(), asset.id().as_str(), asset_json],
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

fn json_sql(error: serde_json::Error) -> rusqlite::Error {
    rusqlite::Error::ToSqlConversionFailure(Box::new(error))
}
