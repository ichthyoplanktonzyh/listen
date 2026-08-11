//! Durable package lifecycle persistence (SQLite).
//!
//! This module owns the real `package_installations`,
//! `package_resource_payloads`, and `package_adoptions` storage behind
//! [`PackageLifecycleRepository`]. It hosts the
//! `application::PackageLifecycleRepository` implementation for
//! [`SqliteRepository`] and nothing else: no second persistence port, no
//! product policy.
//!
//! ## Installation semantics
//!
//! `save_installation` runs inside one transaction. Before any write it
//! verifies the target Material exists, its claimed revision exists and
//! belongs to the Material, and — inside the same transaction — that the
//! revision is still the Material's current revision, closing the window
//! between application validation and the actual write. The prepared input
//! (fact lists plus exact payload bytes) is re-validated against the v2
//! invariant (digest, size, kind/schema, resource association, and the
//! availability/body contract) before any row is touched.
//!
//! The installation facts and every payload BLOB are written in that one
//! transaction and committed together: an accepted installation never
//! depends on the source carrier, and a mid-write failure leaves neither an
//! installation-only row nor partial payload rows. A retry with identical
//! immutable facts and identical payload bytes returns the existing
//! installation without rewriting it, preserving the original
//! `installed_at_ms`; any inequality under the same `(material_id,
//! release_id)` fails closed and changes nothing.
//!
//! ## Adoption semantics
//!
//! `commit_adoption` also runs inside one transaction. It re-verifies the
//! Material/revision/current-revision facts, loads the stored installation,
//! recomputes [`domain::adoption_commit_plan`] from the stored facts with the
//! plan's `adopted_at_ms`, and requires the caller's plan to equal the
//! deterministic result exactly — a forged, incomplete, or extra selection is
//! never accepted. Every selected resource must have a durable payload row
//! whose association (kind/schema/digest/size) and SHA-256 match the stored
//! fact, so a single present row with tampered bytes does not count as
//! backing. The adoption and its full selection plan are then written as one
//! row replacement; a failed verification or write rolls the transaction
//! back, preserving any previous adoption, and a re-adopt of the same
//! release returns the existing adoption without rewriting anything.
//!
//! The adapter writes only its own three tables and never touches learner
//! history, materials, media, or legacy content-package state. Error
//! messages never carry payload bytes, JSON snapshots, paths, or SQL
//! parameters; stored corruption surfaces as a stable repository error.

use std::collections::HashMap;

use application::{
    ApplicationError, PackageLifecycleRepository, PreparedPackageInstallation,
    PreparedResourcePayload,
};
use domain::{
    AdoptionCommitPlan, LearningMaterialId, PackageInstallation, PackageReleaseId,
    PackageResourceAvailability, PackageResourceFact, adoption_commit_plan,
};
use rusqlite::{Connection, OptionalExtension, Transaction, params};
use serde::de::DeserializeOwned;
use sha2::{Digest as _, Sha256};

use super::{SqliteRepository, repo};

/// The `package_installations` columns in storage order, used by every read
/// that rehydrates a typed [`PackageInstallation`].
const INSTALLATION_COLUMNS: &str =
    "material_id, release_id, material_revision_id, release_created_at_ms,
     edition_json, resources_json, renditions_json, installed_at_ms";

/// The `package_adoptions` columns in storage order, used by every read that
/// rehydrates a typed [`AdoptionCommitPlan`].
const ADOPTION_COLUMNS: &str = "material_id, release_id, material_revision_id, edition_json,
     selected_resource_ids_json, exclusive_selections_json, selected_rendition_ids_json,
     adopted_at_ms";

/// One stored payload body with the facts that re-verify its association with
/// its resource fact. Payload bytes never leave this module.
pub(crate) struct StoredPayload {
    pub(crate) resource_id: String,
    pub(crate) kind: String,
    pub(crate) schema: String,
    pub(crate) digest: String,
    pub(crate) size_bytes: u64,
    pub(crate) bytes: Vec<u8>,
}

/// Maps a stored identifier that no longer parses as its typed id.
fn parse_error() -> ApplicationError {
    ApplicationError::Repository("stored package lifecycle data is corrupt".into())
}

/// Parses a stored JSON snapshot into a typed value. Failures surface as a
/// stable repository error that never carries the raw snapshot.
fn parse_json<T: DeserializeOwned>(value: &str, kind: &str) -> Result<T, ApplicationError> {
    serde_json::from_str(value)
        .map_err(|_| ApplicationError::Repository(format!("stored {kind} snapshot is corrupt")))
}

/// The deterministic digest string the payload verification compares: always
/// `sha256:<hex>`.
fn sha256_id(bytes: &[u8]) -> String {
    format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
}

/// One `package_installations` row in [`INSTALLATION_COLUMNS`] order.
type InstallationParts = (String, String, String, u64, String, String, String, u64);

/// One `package_adoptions` row in [`ADOPTION_COLUMNS`] order.
type AdoptionParts = (String, String, String, String, String, String, String, u64);

/// The writable adoption row: the adoption columns minus the material id.
type AdoptionRow = (String, String, String, String, String, String, u64);

fn installation_from_parts(
    parts: InstallationParts,
) -> Result<PackageInstallation, ApplicationError> {
    let (
        material_id,
        release_id,
        revision_id,
        release_created_at_ms,
        edition_json,
        resources_json,
        renditions_json,
        installed_at_ms,
    ) = parts;
    Ok(PackageInstallation {
        release_id: PackageReleaseId::parse(release_id).map_err(|_| parse_error())?,
        release_created_at_ms,
        material_id: LearningMaterialId::parse(material_id).map_err(|_| parse_error())?,
        material_revision_id: domain::MaterialRevisionId::parse(revision_id)
            .map_err(|_| parse_error())?,
        edition: parse_json(&edition_json, "package installation")?,
        resources: parse_json(&resources_json, "package installation")?,
        renditions: parse_json(&renditions_json, "package installation")?,
        installed_at_ms,
    })
}

/// Reads one installation row by its primary identity, or `None`.
fn query_installation(
    connection: &Connection,
    material_id: &str,
    release_id: &str,
) -> Result<Option<PackageInstallation>, ApplicationError> {
    let parts: Option<InstallationParts> = connection
        .query_row(
            &format!(
                "SELECT {INSTALLATION_COLUMNS} FROM package_installations
                 WHERE material_id=?1 AND release_id=?2"
            ),
            params![material_id, release_id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                ))
            },
        )
        .optional()
        .map_err(repo)?;
    parts.map(installation_from_parts).transpose()
}

/// Loads every stored payload body of one installation, ordered by resource
/// id. The bytes are compared and hash-verified inside the adapter and never
/// returned.
pub(crate) fn query_payloads(
    connection: &Connection,
    material_id: &str,
    release_id: &str,
) -> Result<Vec<StoredPayload>, ApplicationError> {
    let mut statement = connection
        .prepare(
            "SELECT resource_id, kind, schema, digest, size_bytes, body
             FROM package_resource_payloads
             WHERE material_id=?1 AND release_id=?2
             ORDER BY resource_id",
        )
        .map_err(repo)?;
    let rows = statement
        .query_map(params![material_id, release_id], |row| {
            Ok(StoredPayload {
                resource_id: row.get(0)?,
                kind: row.get(1)?,
                schema: row.get(2)?,
                digest: row.get(3)?,
                size_bytes: row.get::<_, u64>(4)?,
                bytes: row.get(5)?,
            })
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)?;
    Ok(rows)
}

/// The seam's retry equality: identical immutable release facts with the
/// adapter-stamped `installed_at_ms` excluded.
fn immutable_facts_equal(first: &PackageInstallation, second: &PackageInstallation) -> bool {
    let mut first = first.clone();
    let mut second = second.clone();
    first.installed_at_ms = 0;
    second.installed_at_ms = 0;
    first == second
}

/// Whether the stored payload set is byte-for-byte and fact-for-fact equal to
/// the prepared payload input, compared by resource id so no incidental row
/// order matters.
fn stored_payloads_equal(stored: &[StoredPayload], prepared: &[PreparedResourcePayload]) -> bool {
    if stored.len() != prepared.len() {
        return false;
    }
    let stored_by_id: HashMap<&str, &StoredPayload> = stored
        .iter()
        .map(|payload| (payload.resource_id.as_str(), payload))
        .collect();
    if stored_by_id.len() != stored.len() {
        return false;
    }
    prepared.iter().all(|payload| {
        stored_by_id
            .get(payload.resource_id.as_str())
            .is_some_and(|stored| {
                stored.kind == payload.kind
                    && stored.schema == payload.schema
                    && stored.digest == payload.digest
                    && stored.size_bytes == payload.size_bytes
                    && stored.bytes == payload.bytes
            })
    })
}

fn inconsistent_payloads() -> ApplicationError {
    ApplicationError::Repository(
        "package release prepared payloads are internally inconsistent".into(),
    )
}

/// Verifies the prepared input's internal association before any write:
/// resource ids are unique, rendition ids are unique, every payload is
/// associated with an existing resource fact whose kind/schema/digest/size
/// match exactly, the bytes are the right length and digest, an `Available`
/// resource carries exactly one body, a `Missing` resource carries none, an
/// `Opaque` resource carries zero or one, and no extra or misattached body
/// exists. Duplicate identities are detected explicitly (never silently
/// covered by a map overwrite) and fail closed.
fn validate_prepared_input(prepared: &PreparedPackageInstallation) -> Result<(), ApplicationError> {
    // Resource identities must be unique.
    let mut resource_ids: HashMap<&str, ()> = HashMap::new();
    for resource in &prepared.installation.resources {
        if resource_ids
            .insert(resource.resource_id.as_str(), ())
            .is_some()
        {
            return Err(inconsistent_facts());
        }
    }
    // Rendition identities must be unique.
    let mut rendition_ids: HashMap<&str, ()> = HashMap::new();
    for rendition in &prepared.installation.renditions {
        if rendition_ids
            .insert(rendition.rendition_id.as_str(), ())
            .is_some()
        {
            return Err(inconsistent_facts());
        }
    }
    // Payload identities must be unique.
    let mut by_resource: HashMap<&str, &PreparedResourcePayload> = HashMap::new();
    for payload in &prepared.payloads {
        if by_resource
            .insert(payload.resource_id.as_str(), payload)
            .is_some()
        {
            return Err(inconsistent_payloads());
        }
    }
    for resource in &prepared.installation.resources {
        let body = by_resource.get(resource.resource_id.as_str());
        match resource.availability {
            PackageResourceAvailability::Available => {
                let Some(payload) = body else {
                    return Err(inconsistent_payloads());
                };
                validate_payload_facts(resource, payload)?;
            }
            PackageResourceAvailability::Missing => {
                if body.is_some() {
                    return Err(inconsistent_payloads());
                }
            }
            PackageResourceAvailability::Opaque => {
                if let Some(payload) = body {
                    validate_payload_facts(resource, payload)?;
                }
            }
        }
    }
    for resource_id in by_resource.keys() {
        if !prepared
            .installation
            .resources
            .iter()
            .any(|resource| resource.resource_id == **resource_id)
        {
            return Err(inconsistent_payloads());
        }
    }
    Ok(())
}

fn inconsistent_facts() -> ApplicationError {
    ApplicationError::Repository(
        "package release prepared installation facts are internally inconsistent".into(),
    )
}

/// One prepared payload body must agree with its resource fact exactly:
/// kind, schema, digest, declared size, actual byte length, and SHA-256.
fn validate_payload_facts(
    resource: &PackageResourceFact,
    payload: &PreparedResourcePayload,
) -> Result<(), ApplicationError> {
    if payload.kind != resource.kind
        || payload.schema != resource.schema
        || payload.digest != resource.payload_digest
        || payload.size_bytes != resource.payload_size_bytes
        || payload.bytes.len() as u64 != payload.size_bytes
        || payload.digest != sha256_id(&payload.bytes)
    {
        return Err(inconsistent_payloads());
    }
    Ok(())
}

/// Verifies inside the caller's transaction that the Material exists, the
/// claimed revision exists and belongs to the Material, and that the revision
/// is still the Material's current revision, closing the window between
/// application validation and the write.
fn verify_material_revision(
    tx: &Transaction<'_>,
    material_id: &str,
    revision_id: &str,
) -> Result<(), ApplicationError> {
    let current_revision_id: Option<String> = tx
        .query_row(
            "SELECT current_revision_id FROM learning_materials WHERE id=?1",
            [material_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(repo)?;
    let Some(current_revision_id) = current_revision_id else {
        return Err(ApplicationError::NotFound("material"));
    };
    let revision_owner: Option<String> = tx
        .query_row(
            "SELECT material_id FROM material_revisions WHERE id=?1",
            [revision_id],
            |row| row.get(0),
        )
        .optional()
        .map_err(repo)?;
    match revision_owner {
        None => return Err(ApplicationError::NotFound("material revision")),
        Some(owner) if owner != material_id => {
            return Err(ApplicationError::Repository(
                "package release material revision belongs to another material".into(),
            ));
        }
        Some(_) => {}
    }
    if current_revision_id != revision_id {
        return Err(ApplicationError::Invalid(
            "package release material revision is not the material's current revision".into(),
        ));
    }
    Ok(())
}

/// Re-verifies one stored payload body against its resource fact: the kind,
/// schema, digest, size, actual byte length, and SHA-256 must all agree. A
/// present row with tampered bytes does not count as durable backing.
fn payload_backs_fact(payload: &StoredPayload, fact: &PackageResourceFact) -> bool {
    payload.kind == fact.kind
        && payload.schema == fact.schema
        && payload.digest == fact.payload_digest
        && payload.size_bytes == fact.payload_size_bytes
        && payload.bytes.len() as u64 == fact.payload_size_bytes
        && payload.digest == sha256_id(&payload.bytes)
}

/// Every selected resource of the commit plan must have a durable payload
/// row whose association and bytes re-verify against the stored fact.
fn verify_backing(
    tx: &Transaction<'_>,
    installation: &PackageInstallation,
    commit: &AdoptionCommitPlan,
) -> Result<(), ApplicationError> {
    let payloads = query_payloads(tx, commit.material_id.as_str(), commit.release_id.as_str())?;
    let payloads_by_id: HashMap<&str, &StoredPayload> = payloads
        .iter()
        .map(|payload| (payload.resource_id.as_str(), payload))
        .collect();
    for resource_id in &commit.selected_resource_ids {
        let Some(payload) = payloads_by_id.get(resource_id.as_str()) else {
            return Err(ApplicationError::Repository(
                "package release selected resources lack durable payload backing".into(),
            ));
        };
        let fact = installation
            .resources
            .iter()
            .find(|fact| &fact.resource_id == resource_id)
            .ok_or_else(|| {
                ApplicationError::Repository(
                    "package release selected resource fact is missing".into(),
                )
            })?;
        if !payload_backs_fact(payload, fact) {
            return Err(ApplicationError::Repository(
                "package release selected resource payload backing is corrupt".into(),
            ));
        }
    }
    Ok(())
}

fn adoption_from_parts(parts: AdoptionParts) -> Result<AdoptionCommitPlan, ApplicationError> {
    let (
        material_id,
        release_id,
        revision_id,
        edition_json,
        selected_resource_ids_json,
        exclusive_selections_json,
        selected_rendition_ids_json,
        adopted_at_ms,
    ) = parts;
    Ok(AdoptionCommitPlan {
        release_id: PackageReleaseId::parse(release_id).map_err(|_| parse_error())?,
        material_id: LearningMaterialId::parse(material_id).map_err(|_| parse_error())?,
        material_revision_id: domain::MaterialRevisionId::parse(revision_id)
            .map_err(|_| parse_error())?,
        edition: parse_json(&edition_json, "package adoption")?,
        selected_resource_ids: parse_json(&selected_resource_ids_json, "package adoption")?,
        exclusive_selections: parse_json(&exclusive_selections_json, "package adoption")?,
        selected_rendition_ids: parse_json(&selected_rendition_ids_json, "package adoption")?,
        adopted_at_ms,
    })
}

fn query_adoption(
    connection: &Connection,
    material_id: &str,
) -> Result<Option<AdoptionCommitPlan>, ApplicationError> {
    let parts: Option<AdoptionParts> = connection
        .query_row(
            &format!("SELECT {ADOPTION_COLUMNS} FROM package_adoptions WHERE material_id=?1"),
            [material_id],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                    row.get(7)?,
                ))
            },
        )
        .optional()
        .map_err(repo)?;
    parts.map(adoption_from_parts).transpose()
}

/// The full selection plan of a commit, serialized as path-free JSON
/// snapshots.
fn adoption_row(commit: &AdoptionCommitPlan) -> Result<AdoptionRow, ApplicationError> {
    Ok((
        commit.release_id.as_str().to_owned(),
        commit.material_revision_id.as_str().to_owned(),
        json_string(&commit.edition)?,
        json_string(&commit.selected_resource_ids)?,
        json_string(&commit.exclusive_selections)?,
        json_string(&commit.selected_rendition_ids)?,
        commit.adopted_at_ms,
    ))
}

impl PackageLifecycleRepository for SqliteRepository {
    fn save_installation(
        &self,
        prepared: &PreparedPackageInstallation,
    ) -> Result<PackageInstallation, ApplicationError> {
        // The prepared input must be internally consistent before it may
        // influence any row read or write.
        validate_prepared_input(prepared)?;
        let installation = &prepared.installation;
        let material_id = installation.material_id.as_str();
        let release_id = installation.release_id.as_str();
        let revision_id = installation.material_revision_id.as_str();

        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        verify_material_revision(&tx, material_id, revision_id)?;

        if let Some(stored) = query_installation(&tx, material_id, release_id)? {
            // An equal retry converges idempotently on the stored
            // installation and preserves the original installed_at_ms;
            // any inequality under the same identity fails closed.
            if immutable_facts_equal(&stored, installation)
                && stored_payloads_equal(
                    &query_payloads(&tx, material_id, release_id)?,
                    &prepared.payloads,
                )
            {
                return Ok(stored);
            }
            return Err(ApplicationError::Repository(
                "package release installation identity conflicts with an unequal existing installation"
                    .into(),
            ));
        }

        // A fresh installation receives its final `installed_at_ms` from the
        // adapter inside this first-persist transaction: the caller's
        // candidate timestamp is never persisted, so a retry's fresh
        // timestamp can never become part of the equality or rewrite the
        // stored value.
        let persisted = PackageInstallation {
            installed_at_ms: application::now_ms(),
            ..installation.clone()
        };
        tx.execute(
            "INSERT INTO package_installations
               (material_id, release_id, material_revision_id, release_created_at_ms,
                edition_json, resources_json, renditions_json, installed_at_ms)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
            params![
                material_id,
                release_id,
                revision_id,
                persisted.release_created_at_ms,
                json_string(&persisted.edition)?,
                json_string(&persisted.resources)?,
                json_string(&persisted.renditions)?,
                persisted.installed_at_ms,
            ],
        )
        .map_err(repo)?;
        for payload in &prepared.payloads {
            tx.execute(
                "INSERT INTO package_resource_payloads
                   (material_id, release_id, resource_id, kind, schema, digest, size_bytes, body)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
                params![
                    material_id,
                    release_id,
                    payload.resource_id,
                    payload.kind,
                    payload.schema,
                    payload.digest,
                    payload.size_bytes,
                    payload.bytes,
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        Ok(persisted)
    }

    fn get_installation(
        &self,
        material_id: &LearningMaterialId,
        release_id: &PackageReleaseId,
    ) -> Result<Option<PackageInstallation>, ApplicationError> {
        let conn = self.connection.lock();
        query_installation(&conn, material_id.as_str(), release_id.as_str())
    }

    fn list_installations(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Vec<PackageInstallation>, ApplicationError> {
        let conn = self.connection.lock();
        let mut statement = conn
            .prepare(&format!(
                "SELECT {INSTALLATION_COLUMNS} FROM package_installations
                 WHERE material_id=?1 ORDER BY release_id"
            ))
            .map_err(repo)?;
        let parts = statement
            .query_map([material_id.as_str()], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, u64>(3)?,
                    row.get::<_, String>(4)?,
                    row.get::<_, String>(5)?,
                    row.get::<_, String>(6)?,
                    row.get::<_, u64>(7)?,
                ))
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        let mut installations = Vec::with_capacity(parts.len());
        for parts in parts {
            installations.push(installation_from_parts(parts)?);
        }
        Ok(installations)
    }

    fn get_adoption(
        &self,
        material_id: &LearningMaterialId,
    ) -> Result<Option<AdoptionCommitPlan>, ApplicationError> {
        let conn = self.connection.lock();
        query_adoption(&conn, material_id.as_str())
    }

    fn commit_adoption(
        &self,
        commit: &AdoptionCommitPlan,
    ) -> Result<AdoptionCommitPlan, ApplicationError> {
        let mut conn = self.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        verify_material_revision(
            &tx,
            commit.material_id.as_str(),
            commit.material_revision_id.as_str(),
        )?;
        // The adoption may only target an installed release, and the stored
        // installation must agree with the commit plan's immutable facts.
        let stored =
            query_installation(&tx, commit.material_id.as_str(), commit.release_id.as_str())?
                .ok_or(ApplicationError::NotFound("package release installation"))?;
        if stored.material_revision_id != commit.material_revision_id
            || stored.edition != commit.edition
        {
            return Err(ApplicationError::Repository(
                "package adoption plan does not match the installed release".into(),
            ));
        }
        // The caller's selection plan must equal the deterministic rule
        // recomputed from the stored facts: forged, incomplete, or extra
        // selections are never accepted.
        let recomputed = adoption_commit_plan(&stored, commit.adopted_at_ms).map_err(|error| {
            ApplicationError::Invalid(format!("package adoption plan is invalid: {error}"))
        })?;
        if &recomputed != commit {
            return Err(ApplicationError::Repository(
                "package adoption plan is forged or incomplete".into(),
            ));
        }
        verify_backing(&tx, &stored, commit)?;

        // A re-adopt of the already-current release returns the existing
        // adoption without rewriting it, preserving the original
        // adopted_at_ms — but only when the stored adoption row equals the
        // caller's plan in every fact except the timestamp. The
        // adopted_at_ms is normalized on both sides so the comparison is
        // complete: a stored row whose material, revision, edition, or
        // selections were tampered with (while staying valid JSON) is
        // corruption, never silently repaired or rewritten. A switch to
        // another installed release replaces the single adoption row
        // atomically.
        if let Some(existing) = query_adoption(&tx, commit.material_id.as_str())? {
            if existing.release_id == commit.release_id {
                let mut stored_plan = existing.clone();
                stored_plan.adopted_at_ms = 0;
                let mut candidate = commit.clone();
                candidate.adopted_at_ms = 0;
                if stored_plan != candidate {
                    return Err(ApplicationError::Repository(
                        "package adoption plan conflicts with the stored adoption row".into(),
                    ));
                }
                return Ok(existing);
            }
            let (
                release_id,
                revision_id,
                edition_json,
                selected_ids,
                exclusive,
                renditions,
                adopted_at_ms,
            ) = adoption_row(commit)?;
            tx.execute(
                "UPDATE package_adoptions
                 SET release_id=?2, material_revision_id=?3, edition_json=?4,
                     selected_resource_ids_json=?5, exclusive_selections_json=?6,
                     selected_rendition_ids_json=?7, adopted_at_ms=?8
                 WHERE material_id=?1",
                params![
                    commit.material_id.as_str(),
                    release_id,
                    revision_id,
                    edition_json,
                    selected_ids,
                    exclusive,
                    renditions,
                    adopted_at_ms,
                ],
            )
            .map_err(repo)?;
        } else {
            let (
                release_id,
                revision_id,
                edition_json,
                selected_ids,
                exclusive,
                renditions,
                adopted_at_ms,
            ) = adoption_row(commit)?;
            tx.execute(
                "INSERT INTO package_adoptions
                   (material_id, release_id, material_revision_id, edition_json,
                    selected_resource_ids_json, exclusive_selections_json,
                    selected_rendition_ids_json, adopted_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
                params![
                    commit.material_id.as_str(),
                    release_id,
                    revision_id,
                    edition_json,
                    selected_ids,
                    exclusive,
                    renditions,
                    adopted_at_ms,
                ],
            )
            .map_err(repo)?;
        }
        tx.commit().map_err(repo)?;
        drop(conn);
        Ok(commit.clone())
    }
}

fn json_string<T: serde::Serialize>(value: &T) -> Result<String, ApplicationError> {
    serde_json::to_string(value).map_err(|_| {
        ApplicationError::Repository("package release facts could not be serialized".into())
    })
}
