//! Durable learning-material persistence (SQLite).
//!
//! This module owns persistence for the Phase 1 learning-material graph:
//! `learning_materials`, `material_revisions`, `material_assets`, and
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
//! domain constructors (`DocumentTextAsset::new`, `MediaRenditionAsset::new`,
//! `MaterialRevision::new`, and for creates `LearningMaterial::new`) and
//! required to equal the candidate exactly before any row is read or written.
//! Forged, non-canonical, or internally inconsistent candidates are rejected
//! as [`ApplicationError::Repository`] with no writes. Reads rehydrate typed
//! domain values through the same constructor validation and additionally
//! validate stored `asset_id`/`asset_kind`, ordinal ordering, and the
//! deterministic revision identity, surfacing corruption as
//! [`ApplicationError::Repository`] instead of returning inconsistent data.
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

use application::{ApplicationError, MaterialRepository};
use domain::{
    DocumentTextAsset, LearningMaterial, LearningMaterialId, MaterialAsset, MaterialRevision,
    MaterialRevisionId, MediaAvailability, MediaId, MediaKind, MediaRenditionAsset,
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

/// Loads a revision's assets in deterministic ordinal order, validating each
/// stored row against its typed JSON.
///
/// Each row must occupy a contiguous ordinal, the stored `asset_kind` must
/// match the parsed variant, the stored `asset_id` must equal the parsed
/// asset's deterministic id, and the ordinal order must equal the canonical
/// id order. Any violation is corruption.
fn load_assets(
    connection: &Connection,
    revision_id: &str,
) -> Result<Vec<MaterialAsset>, ApplicationError> {
    let mut statement = connection
        .prepare(
            "SELECT ordinal, asset_id, asset_kind, asset_json
             FROM material_assets WHERE revision_id=?1 ORDER BY ordinal",
        )
        .map_err(repo)?;
    let rows = statement
        .query_map([revision_id], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)?;
    let mut assets = Vec::with_capacity(rows.len());
    for (index, (ordinal, asset_id, asset_kind, asset_json)) in rows.into_iter().enumerate() {
        if ordinal != index as i64 {
            return Err(ApplicationError::Repository(format!(
                "revision {revision_id} asset ordinals are not contiguous"
            )));
        }
        let asset: MaterialAsset = from_json(&asset_json).map_err(repo)?;
        // Stored typed assets must reconstruct exactly through their domain
        // constructors: a forged digest, byte size, or id that no longer
        // derives from the stored content is corruption.
        let asset = validate_asset(&asset)?;
        let expected_kind = match &asset {
            MaterialAsset::DocumentText(_) => "document_text",
            MaterialAsset::MediaRendition(_) => "media_rendition",
        };
        if expected_kind != asset_kind {
            return Err(ApplicationError::Repository(format!(
                "revision {revision_id} stored asset_kind does not match its JSON"
            )));
        }
        if asset.id().as_str() != asset_id {
            return Err(ApplicationError::Repository(format!(
                "revision {revision_id} stored asset_id does not match its JSON"
            )));
        }
        assets.push(asset);
    }
    let mut canonical = assets.clone();
    canonical.sort_by(|a, b| a.id().as_str().cmp(b.id().as_str()));
    if canonical != assets {
        return Err(ApplicationError::Repository(format!(
            "revision {revision_id} assets are not stored in canonical order"
        )));
    }
    Ok(assets)
}

/// Maps a stored revision into a typed [`MaterialRevision`].
///
/// The stored title, assets, and created timestamp must reconstruct the same
/// deterministic revision identity as the stored revision id; anything else is
/// corruption surfaced as [`ApplicationError::Repository`].
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
    let assets = load_assets(connection, revision_id)?;
    let rehydrated =
        MaterialRevision::new(material_id, title, assets, created_at_ms).map_err(|error| {
            ApplicationError::Repository(format!(
                "stored revision {revision_id} is corrupt: {error}"
            ))
        })?;
    if rehydrated.id.as_str() != revision_id {
        return Err(ApplicationError::Repository(format!(
            "stored revision {revision_id} identity does not match its assets"
        )));
    }
    Ok(Some(rehydrated))
}

/// Persists one binding per media rendition. The binding deliberately carries
/// no foreign key to `media_items`, so it stays durable when the media is not
/// registered. A media already bound to the same material is an idempotent
/// re-bind (revisions may repeat an earlier rendition); a media bound to
/// another material is a conflict that rolls back the whole operation.
fn insert_bindings(
    connection: &Connection,
    revision: &MaterialRevision,
) -> Result<(), ApplicationError> {
    for asset in &revision.assets {
        if let MaterialAsset::MediaRendition(rendition) = asset {
            let existing: Option<String> = connection
                .query_row(
                    "SELECT material_id FROM material_media_bindings WHERE media_id=?1",
                    [rendition.media_id.as_str()],
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
                            params![rendition.media_id.as_str(), revision.material_id.as_str()],
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

/// Persists the revision's typed assets in canonical ordinal order. The typed
/// JSON snapshots the asset only; a media rendition never carries a path.
fn insert_assets(
    connection: &Connection,
    revision: &MaterialRevision,
) -> Result<(), ApplicationError> {
    for (ordinal, asset) in revision.assets.iter().enumerate() {
        let asset_kind = match asset {
            MaterialAsset::DocumentText(_) => "document_text",
            MaterialAsset::MediaRendition(_) => "media_rendition",
        };
        connection
            .execute(
                "INSERT INTO material_assets (revision_id, ordinal, asset_id, asset_kind, asset_json)
                 VALUES (?1,?2,?3,?4,?5)",
                params![
                    revision.id.as_str(),
                    ordinal as i64,
                    asset.id().as_str(),
                    asset_kind,
                    json(asset)?,
                ],
            )
            .map_err(repo)?;
    }
    Ok(())
}

/// One membership authority during material writes: every media currently
/// bound to the material that is also registered in `media_items` follows the
/// aggregate's membership and update time inside the same transaction.
/// Unregistered media keep their durable binding untouched (the UPDATE simply
/// matches no row). The update touches exactly the same two columns as
/// [`MaterialRepository::set_library_membership`].
fn sync_media_membership(
    connection: &Connection,
    material_id: &str,
    retained_at_ms: Option<u64>,
    updated_at_ms: u64,
) -> Result<(), ApplicationError> {
    connection
        .execute(
            "UPDATE media_items
             SET retained_at_ms=?2, updated_at_ms=?3
             WHERE id IN (SELECT media_id FROM material_media_bindings WHERE material_id=?1)",
            params![material_id, retained_at_ms, updated_at_ms],
        )
        .map_err(repo)?;
    Ok(())
}

fn is_primary_key_violation(error: &rusqlite::Error) -> bool {
    matches!(
        error,
        rusqlite::Error::SqliteFailure(ffi_error, _)
            if ffi_error.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_PRIMARYKEY
    )
}

/// Rebuilds a typed asset with its domain constructor and requires exact
/// equality with the candidate.
///
/// The domain structs have public fields and serde can bypass their
/// constructors, so a candidate may carry a forged id, digest, byte size, or
/// other field that no longer derives from the content it claims. Rebuilding
/// the asset from its own fields recomputes every derived fact and rejects
/// anything that is not the exact canonical form.
fn validate_asset(asset: &MaterialAsset) -> Result<MaterialAsset, ApplicationError> {
    match asset {
        MaterialAsset::DocumentText(asset) => {
            let rebuilt = DocumentTextAsset::new(asset.text.clone(), asset.language.clone())
                .map_err(|error| {
                    ApplicationError::Repository(format!(
                        "typed document asset is invalid: {error}"
                    ))
                })?;
            if &rebuilt != asset {
                return Err(ApplicationError::Repository(
                    "typed document asset is not canonical".into(),
                ));
            }
            Ok(MaterialAsset::DocumentText(rebuilt))
        }
        MaterialAsset::MediaRendition(asset) => {
            let rebuilt = MediaRenditionAsset::new(
                asset.media_id.clone(),
                asset.kind,
                asset.fingerprint.clone(),
                asset.availability,
            )
            .map_err(|error| {
                ApplicationError::Repository(format!("typed media rendition is invalid: {error}"))
            })?;
            if &rebuilt != asset {
                return Err(ApplicationError::Repository(
                    "typed media rendition is not canonical".into(),
                ));
            }
            Ok(MaterialAsset::MediaRendition(rebuilt))
        }
    }
}

/// Rebuilds a candidate revision from its parts with the domain constructors
/// and requires exact typed equality with the candidate.
///
/// `MaterialRevision::new` re-canonicalizes the assets and re-derives the
/// deterministic identity, so a forged title, a non-canonical asset order,
/// forged asset fields, or any internally inconsistent combination is
/// rejected as [`ApplicationError::Repository`]. Equal-content retries at a
/// different time still pass because `created_at_ms` is not part of revision
/// identity.
fn validate_revision(revision: &MaterialRevision) -> Result<MaterialRevision, ApplicationError> {
    let mut assets = Vec::with_capacity(revision.assets.len());
    for asset in &revision.assets {
        assets.push(validate_asset(asset)?);
    }
    let rebuilt = MaterialRevision::new(
        revision.material_id.clone(),
        revision.title.clone(),
        assets,
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
/// assets, points `current_revision_id` at the validated revision, and
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
        // A candidate must be the exact canonical domain form before it may
        // influence any existing-row check or write: rebuild the revision
        // from its parts and the material from the revision, and reject
        // forged, non-canonical, or internally inconsistent candidates with
        // no writes.
        let revision = validate_revision(revision)?;
        let material = validate_material(material, &revision)?;
        // An existing material identity must never be silently overwritten: an
        // equal-content retry (already carrying the validated revision as its
        // current revision) returns the actual stored aggregate, while a
        // different revision under the same identity is a conflict.
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
                revision.id.as_str(),
                material.retained_at_ms,
                material.created_at_ms,
                material.updated_at_ms,
            ],
        )
        .map_err(repo)?;
        insert_revision(&tx, &revision)?;
        insert_assets(&tx, &revision)?;
        insert_bindings(&tx, &revision)?;
        sync_media_membership(
            &tx,
            material.id.as_str(),
            material.retained_at_ms,
            material.updated_at_ms,
        )?;
        tx.commit().map_err(repo)?;
        drop(conn);
        self.get_material(&material.id)?.ok_or_else(|| {
            ApplicationError::Repository("create_material returned no material".into())
        })
    }

    fn append_revision(
        &self,
        material_id: &LearningMaterialId,
        revision: &MaterialRevision,
        updated_at_ms: u64,
    ) -> Result<LearningMaterial, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        // The candidate must be the exact canonical domain form before any
        // read-based early return or write: forged, non-canonical, or
        // internally inconsistent revisions are rejected with no writes.
        let revision = validate_revision(revision)?;
        let Some(material) = query_material(&tx, material_id.as_str())? else {
            return Err(ApplicationError::NotFound("material"));
        };
        // A same-current retry is idempotent: nothing is written, so neither
        // timestamps nor history move. `created_at_ms` is not part of
        // revision identity, so the validated retry converges on the stored
        // first-writer revision even though its creation time differs.
        if material.current_revision_id == revision.id {
            query_revision(&tx, revision.id.as_str())?.ok_or_else(|| {
                ApplicationError::Repository(format!(
                    "current revision {} is missing",
                    revision.id.as_str()
                ))
            })?;
            return Ok(material);
        }
        if revision.material_id != *material_id {
            return Err(ApplicationError::Repository(
                "revision material identity does not match the target material".into(),
            ));
        }
        // A revision that already exists but is not current is a duplicate
        // historical write, never a silent pointer rewrite.
        let revision_exists = tx
            .query_row(
                "SELECT 1 FROM material_revisions WHERE id=?1",
                [revision.id.as_str()],
                |_| Ok(()),
            )
            .optional()
            .map_err(repo)?
            .is_some();
        if revision_exists {
            return Err(ApplicationError::Conflict("revision already exists"));
        }
        insert_revision(&tx, &revision)?;
        insert_assets(&tx, &revision)?;
        insert_bindings(&tx, &revision)?;
        // Advance the current pointer and update time while preserving
        // `created_at_ms` and membership; the table CHECK rejects any update
        // before creation.
        tx.execute(
            "UPDATE learning_materials
             SET current_revision_id=?2, updated_at_ms=?3
             WHERE id=?1",
            params![material_id.as_str(), revision.id.as_str(), updated_at_ms],
        )
        .map_err(repo)?;
        // New media bound to an already-retained material immediately follows
        // aggregate membership; the whole append carries the operation's
        // updated timestamp for the legacy media rows.
        sync_media_membership(
            &tx,
            material_id.as_str(),
            material.retained_at_ms,
            updated_at_ms,
        )?;
        tx.commit().map_err(repo)?;
        drop(conn);
        self.get_material(material_id)?
            .ok_or_else(|| ApplicationError::Repository("append_revision lost the material".into()))
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
        let materials = statement
            .query_map([], material_from_row)
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        Ok(materials)
    }

    fn set_library_membership(
        &self,
        material_id: &LearningMaterialId,
        retained_at_ms: Option<u64>,
        updated_at_ms: u64,
    ) -> Result<LearningMaterial, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let changed = tx
            .execute(
                "UPDATE learning_materials
                 SET retained_at_ms=?2, updated_at_ms=?3
                 WHERE id=?1",
                params![material_id.as_str(), retained_at_ms, updated_at_ms],
            )
            .map_err(repo)?;
        if changed == 0 {
            return Err(ApplicationError::NotFound("material"));
        }
        // Membership is one authority: every bound registered media follows
        // the material's membership and update time, exactly the same two
        // columns as the material row.
        sync_media_membership(&tx, material_id.as_str(), retained_at_ms, updated_at_ms)?;
        tx.commit().map_err(repo)?;
        drop(conn);
        self.get_material(material_id)?.ok_or_else(|| {
            ApplicationError::Repository("set_library_membership lost the material".into())
        })
    }

    fn material_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Option<LearningMaterial>, ApplicationError> {
        let conn = self.connection.lock();
        conn.query_row(
            "SELECT l.id, l.current_revision_id, l.retained_at_ms, l.created_at_ms, l.updated_at_ms
             FROM material_media_bindings b
             JOIN learning_materials l ON l.id = b.material_id
             WHERE b.media_id=?1",
            [media_id.as_str()],
            material_from_row,
        )
        .optional()
        .map_err(repo)
    }
}
