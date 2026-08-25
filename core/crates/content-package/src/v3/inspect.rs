//! Content Package v3 inspection.
//!
//! `inspect_v3_path` / `inspect_v3_path_with_limits` perform bounded,
//! persistence-free inspection of a v3 carrier (directory or deterministic
//! ZIP). A catalog pass reads only the control document and catalogs every
//! entry without opening bodies; a selective pass retains known and present
//! opaque payload blobs (bounded by `max_file_bytes`) while streaming
//! rendition text/media blobs to their size and SHA-256 facts, so embedded
//! text/media can exceed `max_file_bytes` without being retained in memory.
//! The exact, size- and digest-verified payload bytes are exposed on
//! [`V3Inspection::payload_blobs`] keyed by blob digest (never by path) so
//! durable persistence can back every present resource payload.
//!
//! Inspection is total and deterministic: invalid identity, hash, dependency,
//! provenance, anchor, locator, subject, compatibility, or blob-closure facts
//! fail before any installation can mutate durable state. Every blob is
//! declared `embedded` (must be present in the carrier) or `referenced` (may
//! be absent); a missing embedded blob is an invalid carrier, while missing
//! referenced blobs are honest availability facts. No network or persistence
//! work happens here.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;

use serde_json::Value;
use thiserror::Error;

use crate::archive::{
    ArchiveError, CatalogEntry, PackageCatalog, read_package_controls, read_package_selective,
};
use crate::inspect::InspectLimits;
use crate::v2::canonical::{self, CanonicalError};
use crate::v2::inspect::{
    dependency_graph_has_cycle, reachable, sha256_id, validate_digest, validate_quality,
    verify_carrier_consistency, verify_retained_blobs, verify_streamed_blobs,
};
use crate::v2::model::{BLOB_DIRECTORY, BLOB_HASH_ALGORITHM_DIRECTORY};
use crate::v2::validate::validate_language_tag;

use crate::v2::ResourceRole;

use super::model::{
    BlobDeclaration, CompatibilityDeclaration, DocumentRenditionDeclaration,
    MediaRenditionDeclaration, PackageReleaseV3, ProducerDeclaration, RELEASE_SCHEMA_V3,
    RenditionOrigin, ResourceProvenanceV3, SubjectDeclaration,
};
use super::payload::{self, KnownPayloadV3};
use super::validate::validate_payload;

#[derive(Debug, Error)]
pub enum V3Error {
    #[error("could not access package: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid ZIP package: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("package limit exceeded: {0}")]
    Limit(&'static str),
    #[error("invalid package entry path: {0}")]
    UnsafePath(String),
    #[error("symbolic links are not allowed in packages: {0}")]
    Symlink(String),
    #[error("duplicate package entry: {0}")]
    DuplicatePath(String),
    #[error("release.json is missing")]
    MissingRelease,
    #[error("release.json is invalid JSON: {0}")]
    ReleaseJson(serde_json::Error),
    #[error("resource payload {path} is invalid JSON: {source}")]
    PayloadJson {
        path: String,
        #[source]
        source: serde_json::Error,
    },
    #[error("invalid package at {path}: {message}")]
    Invalid { path: String, message: String },
    /// A typed compatibility result, distinct from malformed input: an
    /// unknown required resource, or an unknown optional resource reached
    /// transitively by a required resource, makes the release incompatible
    /// with this runtime.
    #[error(
        "release is incompatible: resource {resource_id} (kind {kind}, schema {schema}) is unsupported"
    )]
    Incompatible {
        resource_id: String,
        kind: String,
        schema: String,
    },
}

impl From<ArchiveError> for V3Error {
    fn from(error: ArchiveError) -> Self {
        match error {
            ArchiveError::Io(source) => Self::Io(source),
            ArchiveError::Zip(source) => Self::Zip(source),
            ArchiveError::Limit(message) => Self::Limit(message),
            ArchiveError::UnsafePath(path) => Self::UnsafePath(path),
            ArchiveError::Symlink(path) => Self::Symlink(path),
            ArchiveError::DuplicatePath(path) => Self::DuplicatePath(path),
            ArchiveError::Invalid { path, message } => Self::Invalid { path, message },
        }
    }
}

impl From<CanonicalError> for V3Error {
    fn from(error: CanonicalError) -> Self {
        Self::Invalid {
            path: "release.json".to_owned(),
            message: error.to_string(),
        }
    }
}

/// The carrier-consistency seam reuses the v2 helper, which only ever fails
/// with its stable invalid-carrier error; every other variant is unreachable
/// from that helper and maps to the same invalid-carrier fact.
impl From<crate::v2::V2Error> for V3Error {
    fn from(error: crate::v2::V2Error) -> Self {
        match error {
            crate::v2::V2Error::Invalid { path, message } => Self::Invalid { path, message },
            _ => Self::Invalid {
                path: "release.json".to_owned(),
                message: "carrier changed between inspection passes".to_owned(),
            },
        }
    }
}

/// The typed result of inspecting a v3 carrier.
#[derive(Debug, Clone)]
pub struct V3Inspection {
    pub release: PackageReleaseV3,
    /// The release identity: `sha256:<hex>` of the canonical release.json.
    pub release_id: String,
    /// The same digest, kept as a plain hex string for compatibility facts.
    pub release_sha256: String,
    pub document_renditions: Vec<DocumentRenditionRecord>,
    pub media_renditions: Vec<MediaRenditionRecord>,
    pub resources: Vec<ResourceRecord>,
    pub opaque_resources: Vec<OpaqueResourceRecord>,
    /// digest -> blob record for every blob referenced by the release.
    pub blobs: BTreeMap<String, BlobRecord>,
    /// Exact raw bytes of every present, size- and digest-verified payload
    /// blob: known resource payloads and present opaque payloads. Keyed by
    /// `sha256:<hex>` digest, never by carrier path, so durable persistence
    /// can store and later verify every present payload body.
    pub payload_blobs: BTreeMap<String, Vec<u8>>,
    /// Exact raw bytes of every present Document/Media Rendition blob, keyed
    /// by `sha256:<hex>` digest, never by carrier path. Core persists these
    /// bodies together with the installation so adopted reading/audio stays
    /// readable after the source carrier is deleted.
    pub rendition_blobs: BTreeMap<String, Vec<u8>>,
    pub missing_blobs: Vec<MissingBlob>,
    pub warnings: Vec<String>,
    pub total_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct DocumentRenditionRecord {
    pub entry: DocumentRenditionDeclaration,
    pub text_present: bool,
}

#[derive(Debug, Clone)]
pub struct MediaRenditionRecord {
    pub entry: MediaRenditionDeclaration,
    pub media_present: bool,
}

#[derive(Debug, Clone)]
pub struct ResourceRecord {
    pub entry: super::model::ReleaseResourceV3,
    pub payload: KnownPayloadV3,
    pub bytes_sha256: String,
}

#[derive(Debug, Clone)]
pub struct OpaqueResourceRecord {
    pub entry: super::model::ReleaseResourceV3,
    pub payload_present: bool,
}

#[derive(Debug, Clone)]
pub struct BlobRecord {
    pub digest: String,
    pub size_bytes: u64,
    /// Whether the blob must be present in the carrier by declaration.
    pub embedded: bool,
    pub present: bool,
}

#[derive(Debug, Clone)]
pub struct MissingBlob {
    pub digest: String,
    pub size_bytes: u64,
    /// A referenced blob may be absent; a missing embedded blob is an
    /// invalid carrier and never reaches this inventory.
    pub embedded: bool,
}

pub fn inspect_v3_path(path: impl AsRef<Path>) -> Result<V3Inspection, V3Error> {
    inspect_v3_path_with_limits(path, InspectLimits::default())
}

pub fn inspect_v3_path_with_limits(
    path: impl AsRef<Path>,
    limits: InspectLimits,
) -> Result<V3Inspection, V3Error> {
    let path = path.as_ref();
    // First pass: read only the control document and catalog every carrier
    // entry (safe name and size) without opening ordinary or text/media
    // bodies.
    let catalog = read_package_controls(path, limits, &["release.json"])?;
    inspect_v3_catalog(path, catalog, limits)
}

fn inspect_v3_catalog(
    path: &Path,
    catalog: PackageCatalog,
    limits: InspectLimits,
) -> Result<V3Inspection, V3Error> {
    let PackageCatalog {
        controls,
        entries,
        total_bytes,
    } = catalog;
    let release_bytes = controls
        .get("release.json")
        .ok_or(V3Error::MissingRelease)?;
    // release.json must be canonical JSON: parse strictly and reject any
    // deviation from the canonical profile. The single parse result backs
    // both the canonical verification and the descriptor identity checks.
    let release_value: Value =
        canonical::parse_canonical_verified(release_bytes).map_err(|error| V3Error::Invalid {
            path: "release.json".to_owned(),
            message: format!("release.json is not canonical JSON: {error}"),
        })?;
    let release: PackageReleaseV3 =
        serde_json::from_slice(release_bytes).map_err(V3Error::ReleaseJson)?;
    if release.schema != RELEASE_SCHEMA_V3 {
        return Err(invalid("release.json", "unsupported release schema"));
    }

    let release_id = sha256_id(release_bytes);
    let release_sha256 = release_id.trim_start_matches("sha256:").to_owned();

    let mut warnings = Vec::new();

    enforce_inventory_limits(&release, limits)?;
    validate_identity(&release)?;
    validate_document_renditions(&release, &release_value)?;
    validate_media_renditions(&release, &release_value)?;
    validate_resource_descriptors(&release, &release_value)?;
    validate_dependency_graph(&release)?;

    // Collect every referenced blob, its declared size, and its carrier
    // contract; reject a single digest declared with conflicting facts.
    let expected = collect_expected_blobs(&release)?;

    // Every carrier entry must be release.json or an exact declared blob
    // path. Reject undeclared files without reading their bodies.
    verify_catalog_inventory(&entries, &expected)?;

    // Second, selective pass: every declared blob that Core may need to
    // persist — known and present opaque payload blobs plus present
    // Document/Media Rendition blobs — stays retained and bounded by
    // max_file_bytes, so adopted content never depends on a carrier re-parse.
    let streamed_paths = streamed_blob_paths(&release);
    let streamed_refs: Vec<&str> = streamed_paths.iter().map(String::as_str).collect();
    let selective = read_package_selective(path, limits, &["release.json"], &streamed_refs)?;

    // The carrier must be exactly the same in both passes: the selective pass
    // must report the same entry names and sizes as the catalog pass, and the
    // second release.json copy must match the first-pass bytes before it is
    // discarded. This prevents mixing facts from two different carrier
    // snapshots when the carrier changes between the passes.
    verify_carrier_consistency(&entries, total_bytes, release_bytes, None, &selective)?;

    let mut retained = selective.files;
    retained.remove("release.json");
    verify_retained_blobs(&retained, &expected_sizes(&expected))?;
    verify_streamed_blobs(&selective.streamed, &expected_sizes(&expected))?;

    // A blob is present when its exact path was found either retained or
    // streamed; both forms were size- and digest-verified above.
    let mut present = retained.keys().cloned().collect::<HashSet<String>>();
    present.extend(selective.streamed.iter().map(|file| file.name.clone()));

    // Blob inventory and the embedded-carrier contract: a declared embedded
    // blob must be present. A missing embedded blob is an invalid blob
    // closure and fails before any installation can mutate durable state;
    // only missing referenced blobs are honest availability facts.
    let mut blobs = BTreeMap::<String, BlobRecord>::new();
    for (digest, (size_bytes, embedded)) in &expected {
        let present_here = present.contains(&blob_path(digest));
        if *embedded && !present_here {
            return Err(invalid(
                digest.clone(),
                "embedded blob is absent from the carrier",
            ));
        }
        blobs.insert(
            digest.clone(),
            BlobRecord {
                digest: digest.clone(),
                size_bytes: *size_bytes,
                embedded: *embedded,
                present: present_here,
            },
        );
    }

    // Decode known payloads; preserve optional unknown resources as opaque.
    // Required unknown resources were already rejected as Incompatible.
    let mut decoded = HashMap::<String, KnownPayloadV3>::new();
    let mut resources = Vec::new();
    let mut opaque_resources = Vec::new();
    for resource in &release.resources {
        let path = blob_path(&resource.descriptor.payload_blob.digest);
        let present_here = present.contains(&path);
        let known = payload::is_known(&resource.descriptor.kind, &resource.descriptor.schema);
        if !known {
            debug_assert!(!resource.required, "required unknown is incompatible");
            opaque_resources.push(OpaqueResourceRecord {
                entry: resource.clone(),
                payload_present: present_here,
            });
            warnings.push(format!(
                "resource {} is opaque (kind/schema unsupported)",
                resource.resource_id
            ));
            continue;
        }
        if !present_here {
            warnings.push(format!(
                "resource {} payload blob is absent from the carrier",
                resource.resource_id
            ));
            continue;
        }
        let bytes = &retained[&path];
        let payload = payload::decode_known(
            &resource.descriptor.kind,
            &resource.descriptor.schema,
            bytes,
        )
        .map_err(|source| V3Error::PayloadJson {
            path: path.clone(),
            source,
        })?
        .expect("known payload must decode");
        let record = ResourceRecord {
            entry: resource.clone(),
            bytes_sha256: sha256_id(bytes),
            payload,
        };
        decoded.insert(resource.resource_id.clone(), record.payload.clone());
        resources.push(record);
    }

    // Structural validation of known payloads against locally checkable
    // in-release references.
    validate_known_payloads(&release, &decoded, &mut warnings)?;

    let document_renditions: Vec<DocumentRenditionRecord> = release
        .document_renditions
        .iter()
        .map(|entry| DocumentRenditionRecord {
            entry: entry.clone(),
            text_present: present.contains(&blob_path(&entry.text_blob.digest)),
        })
        .collect();

    let media_renditions: Vec<MediaRenditionRecord> = release
        .media_renditions
        .iter()
        .map(|entry| MediaRenditionRecord {
            entry: entry.clone(),
            media_present: present.contains(&blob_path(&entry.media_blob.digest)),
        })
        .collect();

    // Exact verified bytes of every present payload blob, keyed by digest.
    // Known payloads were decoded from the retained bodies above; present
    // opaque bodies were retained by the same selective pass. Every key is a
    // digest, never a carrier path, and rendition text/media never appears.
    let mut payload_blobs = BTreeMap::<String, Vec<u8>>::new();
    for record in &resources {
        let digest = &record.entry.descriptor.payload_blob.digest;
        payload_blobs.insert(digest.clone(), retained[&blob_path(digest)].clone());
    }
    for record in &opaque_resources {
        if record.payload_present {
            let digest = &record.entry.descriptor.payload_blob.digest;
            payload_blobs.insert(digest.clone(), retained[&blob_path(digest)].clone());
        }
    }

    // Exact verified bytes of every present rendition blob (document text and
    // media bodies), keyed by digest, so Core can durably persist adopted
    // content without re-parsing the carrier.
    let mut rendition_blobs = BTreeMap::<String, Vec<u8>>::new();
    for record in &document_renditions {
        let digest: &str = &record.entry.text_blob.digest;
        if present.contains(&blob_path(digest)) {
            rendition_blobs.insert(digest.to_owned(), retained[&blob_path(digest)].clone());
        }
    }
    for record in &media_renditions {
        let digest: &str = &record.entry.media_blob.digest;
        if present.contains(&blob_path(digest)) {
            rendition_blobs.insert(digest.to_owned(), retained[&blob_path(digest)].clone());
        }
    }

    let missing_blobs: Vec<MissingBlob> = blobs
        .values()
        .filter(|record| !record.present)
        .map(|record| MissingBlob {
            digest: record.digest.clone(),
            size_bytes: record.size_bytes,
            embedded: record.embedded,
        })
        .collect();

    // total_bytes counts every carrier entry exactly once and comes from the
    // selective pass, which observed retained and streamed bodies alike; the
    // consistency check above guarantees it equals the catalog-pass total.
    let total_bytes = selective.total_bytes;

    if !missing_blobs.is_empty() {
        warnings.push(format!(
            "{} referenced blob(s) are absent from the carrier",
            missing_blobs.len()
        ));
    }

    Ok(V3Inspection {
        release,
        release_id,
        release_sha256,
        document_renditions,
        media_renditions,
        resources,
        opaque_resources,
        blobs,
        payload_blobs,
        rendition_blobs,
        missing_blobs,
        warnings,
        total_bytes,
    })
}

/// Projects the expected blob facts into the size map the shared retained /
/// streamed verifiers consume.
fn expected_sizes(expected: &BTreeMap<String, (u64, bool)>) -> BTreeMap<String, u64> {
    expected
        .iter()
        .map(|(digest, (size_bytes, _))| (digest.clone(), *size_bytes))
        .collect()
}

/// Applies `InspectLimits.max_file_count` to the release resource, rendition,
/// graph, and entry inventories, plus the combined rendition entry count
/// (computed with checked arithmetic). The graph edge budget keeps every
/// closure/traversal check strictly bounded.
fn enforce_inventory_limits(
    release: &PackageReleaseV3,
    limits: InspectLimits,
) -> Result<(), V3Error> {
    let maximum = limits.max_file_count;
    enforce_count(release.resources.len(), maximum, "resource inventory")?;
    enforce_count(
        release.document_renditions.len(),
        maximum,
        "document rendition inventory",
    )?;
    enforce_count(
        release.media_renditions.len(),
        maximum,
        "media rendition inventory",
    )?;
    let combined_renditions = release
        .document_renditions
        .len()
        .checked_add(release.media_renditions.len())
        .ok_or(V3Error::Limit("combined rendition inventory"))?;
    enforce_count(combined_renditions, maximum, "combined rendition inventory")?;
    let combined_entries = combined_renditions
        .checked_add(release.resources.len())
        .ok_or(V3Error::Limit("combined resource and rendition inventory"))?;
    enforce_count(
        combined_entries,
        maximum,
        "combined resource and rendition inventory",
    )?;
    let mut edges = 0_usize;
    for resource in &release.resources {
        enforce_count(
            resource.descriptor.dependencies.len(),
            maximum,
            "resource dependency inventory",
        )?;
        enforce_count(
            resource.descriptor.provenance.input_resource_ids.len(),
            maximum,
            "input resource lineage inventory",
        )?;
        enforce_count(
            resource.descriptor.provenance.input_rendition_ids.len(),
            maximum,
            "input rendition lineage inventory",
        )?;
        enforce_count(
            resource.descriptor.subject.rendition_ids.len(),
            maximum,
            "subject rendition inventory",
        )?;
        enforce_count(
            resource.descriptor.subject.anchor_resource_ids.len(),
            maximum,
            "subject anchor inventory",
        )?;
        if let Some(compatibility) = &resource.descriptor.compatibility {
            enforce_count(
                compatibility.verified_inputs.len(),
                maximum,
                "compatibility input inventory",
            )?;
        }
        edges = edges
            .checked_add(resource.descriptor.dependencies.len())
            .ok_or(V3Error::Limit("dependency graph"))?;
    }
    for rendition in &release.document_renditions {
        if let Some(compatibility) = &rendition.compatibility {
            enforce_count(
                compatibility.verified_inputs.len(),
                maximum,
                "compatibility input inventory",
            )?;
        }
    }
    for rendition in &release.media_renditions {
        if let Some(compatibility) = &rendition.compatibility {
            enforce_count(
                compatibility.verified_inputs.len(),
                maximum,
                "compatibility input inventory",
            )?;
        }
    }
    enforce_count(edges, maximum, "dependency graph")
}

fn enforce_count(count: usize, maximum: usize, label: &'static str) -> Result<(), V3Error> {
    if count > maximum {
        return Err(V3Error::Limit(label));
    }
    Ok(())
}

fn validate_identity(release: &PackageReleaseV3) -> Result<(), V3Error> {
    if release.edition.edition_id.trim().is_empty() {
        return Err(invalid("release.json", "edition_id must not be empty"));
    }
    if release.edition.title.trim().is_empty() {
        return Err(invalid("release.json", "edition title must not be empty"));
    }
    validate_language_tag(&release.edition.target_language)
        .map_err(|message| invalid("release.json", message))?;
    let mut support = HashSet::new();
    for language in &release.edition.support_languages {
        validate_language_tag(language).map_err(|message| invalid("release.json", message))?;
        if !support.insert(language) {
            return Err(invalid(
                "release.json",
                "edition support_languages must be unique",
            ));
        }
    }
    if release.material.material_id.trim().is_empty() {
        return Err(invalid("release.json", "material_id must not be empty"));
    }
    if release.material.material_revision_id.trim().is_empty() {
        return Err(invalid(
            "release.json",
            "material_revision_id must not be empty",
        ));
    }
    if release.material.title.trim().is_empty() {
        return Err(invalid("release.json", "material title must not be empty"));
    }
    Ok(())
}

/// Validates every declared Document Rendition: identity (the canonical
/// `{media_type, language, text_blob}` descriptor digest), origin rules
/// (a Source rendition binds a Source Asset; a Derived rendition records
/// exact producer and compatibility evidence), and blob/producer facts.
fn validate_document_renditions(
    release: &PackageReleaseV3,
    release_value: &Value,
) -> Result<(), V3Error> {
    let mut seen = HashSet::new();
    for (index, rendition) in release.document_renditions.iter().enumerate() {
        validate_digest(&rendition.rendition_id)
            .map_err(|message| invalid(&rendition.rendition_id, message))?;
        if !seen.insert(&rendition.rendition_id) {
            return Err(invalid(&rendition.rendition_id, "duplicate rendition_id"));
        }
        let entry_value = &release_value["document_renditions"][index];
        let identity = serde_json::json!({
            "media_type": entry_value["media_type"],
            "language": entry_value["language"],
            "text_blob": entry_value["text_blob"],
        });
        let canonical =
            canonical::serialize_canonical(&identity).map_err(|error| V3Error::Invalid {
                path: rendition.rendition_id.clone(),
                message: format!("rendition descriptor is not canonical JSON: {error}"),
            })?;
        let expected = sha256_id(&canonical);
        if expected != rendition.rendition_id {
            return Err(invalid(
                &rendition.rendition_id,
                "rendition_id does not match the descriptor canonical JSON",
            ));
        }
        if rendition.media_type.trim().is_empty() {
            return Err(invalid(
                &rendition.rendition_id,
                "document rendition media_type must not be empty",
            ));
        }
        if let Some(language) = &rendition.language {
            validate_language_tag(language)
                .map_err(|message| invalid(&rendition.rendition_id, message))?;
        }
        validate_blob_declaration(&rendition.text_blob)
            .map_err(|message| invalid(&rendition.rendition_id, message))?;
        match rendition.origin {
            RenditionOrigin::Source => {
                let binding = rendition.source_asset_id.as_deref().ok_or_else(|| {
                    invalid(
                        &rendition.rendition_id,
                        "source document rendition must bind a source_asset_id",
                    )
                })?;
                validate_digest(binding)
                    .map_err(|message| invalid(&rendition.rendition_id, message))?;
            }
            RenditionOrigin::Derived => {
                if rendition.source_asset_id.is_some() {
                    return Err(invalid(
                        &rendition.rendition_id,
                        "derived document rendition must not bind a source_asset_id",
                    ));
                }
                let producer = rendition.producer.as_ref().ok_or_else(|| {
                    invalid(
                        &rendition.rendition_id,
                        "derived document rendition requires producer facts",
                    )
                })?;
                validate_producer(&rendition.rendition_id, producer)?;
                let compatibility = rendition.compatibility.as_ref().ok_or_else(|| {
                    invalid(
                        &rendition.rendition_id,
                        "derived document rendition requires compatibility evidence",
                    )
                })?;
                validate_compatibility(release, &rendition.rendition_id, compatibility)?;
            }
        }
    }
    Ok(())
}

/// Validates every declared Media Rendition: identity (the canonical
/// `{kind, media_type, media_blob, media_id, fingerprint}` descriptor
/// digest), kind/media_type family, origin rules (a Source rendition binds a
/// media source; a Derived rendition records exact producer and
/// compatibility evidence), and blob/producer facts.
fn validate_media_renditions(
    release: &PackageReleaseV3,
    release_value: &Value,
) -> Result<(), V3Error> {
    let mut seen = HashSet::new();
    for (index, rendition) in release.media_renditions.iter().enumerate() {
        validate_digest(&rendition.rendition_id)
            .map_err(|message| invalid(&rendition.rendition_id, message))?;
        if !seen.insert(&rendition.rendition_id) {
            return Err(invalid(&rendition.rendition_id, "duplicate rendition_id"));
        }
        let entry_value = &release_value["media_renditions"][index];
        let identity = serde_json::json!({
            "kind": entry_value["kind"],
            "media_type": entry_value["media_type"],
            "media_blob": entry_value["media_blob"],
            "media_id": entry_value["media_id"],
            "fingerprint": entry_value["fingerprint"],
        });
        let canonical =
            canonical::serialize_canonical(&identity).map_err(|error| V3Error::Invalid {
                path: rendition.rendition_id.clone(),
                message: format!("rendition descriptor is not canonical JSON: {error}"),
            })?;
        let expected = sha256_id(&canonical);
        if expected != rendition.rendition_id {
            return Err(invalid(
                &rendition.rendition_id,
                "rendition_id does not match the descriptor canonical JSON",
            ));
        }
        let media_family = match rendition.kind.as_str() {
            "audio" => "audio/",
            "video" => "video/",
            other => {
                return Err(invalid(
                    &rendition.rendition_id,
                    format!("unsupported rendition kind: {other}"),
                ));
            }
        };
        if !rendition.media_type.starts_with(media_family) {
            return Err(invalid(
                &rendition.rendition_id,
                "rendition media_type does not match its kind",
            ));
        }
        if rendition.fingerprint.trim().is_empty() {
            return Err(invalid(
                &rendition.rendition_id,
                "media rendition fingerprint must not be empty",
            ));
        }
        validate_blob_declaration(&rendition.media_blob)
            .map_err(|message| invalid(&rendition.rendition_id, message))?;
        match rendition.origin {
            RenditionOrigin::Source => {
                let binding = rendition.media_id.as_deref().ok_or_else(|| {
                    invalid(
                        &rendition.rendition_id,
                        "source media rendition must bind a media_id",
                    )
                })?;
                if binding.trim().is_empty() {
                    return Err(invalid(
                        &rendition.rendition_id,
                        "media_id must not be empty",
                    ));
                }
            }
            RenditionOrigin::Derived => {
                if rendition.media_id.is_some() {
                    return Err(invalid(
                        &rendition.rendition_id,
                        "derived media rendition must not bind a media_id",
                    ));
                }
                let producer = rendition.producer.as_ref().ok_or_else(|| {
                    invalid(
                        &rendition.rendition_id,
                        "derived media rendition requires producer facts",
                    )
                })?;
                validate_producer(&rendition.rendition_id, producer)?;
                let compatibility = rendition.compatibility.as_ref().ok_or_else(|| {
                    invalid(
                        &rendition.rendition_id,
                        "derived media rendition requires compatibility evidence",
                    )
                })?;
                validate_compatibility(release, &rendition.rendition_id, compatibility)?;
            }
        }
    }
    Ok(())
}

fn validate_producer(owner: &str, producer: &ProducerDeclaration) -> Result<(), V3Error> {
    if producer.tool.id.trim().is_empty() || producer.tool.version.trim().is_empty() {
        return Err(invalid(owner, "producer tool id/version must not be empty"));
    }
    for versioned in [&producer.provider, &producer.model].into_iter().flatten() {
        if versioned.id.trim().is_empty() || versioned.version.trim().is_empty() {
            return Err(invalid(owner, "producer id/version must not be empty"));
        }
    }
    if let Some(digest) = &producer.config_sha256 {
        validate_digest(digest).map_err(|message| invalid(owner, message))?;
    }
    Ok(())
}

/// v3 resource provenance: creation time, tool, optional provider/model with
/// versions, optional config digest, and exact production inputs — declared
/// input Rendition ids and declared input Resource ids, each unique and
/// in-release.
fn validate_provenance_v3(
    release: &PackageReleaseV3,
    resource_id: &str,
    provenance: &ResourceProvenanceV3,
) -> Result<(), V3Error> {
    if provenance.tool.id.trim().is_empty() || provenance.tool.version.trim().is_empty() {
        return Err(invalid(
            resource_id,
            "provenance tool id/version must not be empty",
        ));
    }
    for versioned in [&provenance.provider, &provenance.model]
        .into_iter()
        .flatten()
    {
        if versioned.id.trim().is_empty() || versioned.version.trim().is_empty() {
            return Err(invalid(
                resource_id,
                "provenance producer id/version must not be empty",
            ));
        }
    }
    if let Some(digest) = &provenance.config_sha256 {
        validate_digest(digest).map_err(|message| invalid(resource_id, message))?;
    }
    let mut rendition_lineage = HashSet::new();
    for input in &provenance.input_rendition_ids {
        validate_digest(input).map_err(|message| invalid(resource_id, message))?;
        if !rendition_lineage.insert(input) {
            return Err(invalid(resource_id, "input_rendition_ids must be unique"));
        }
        if !rendition_declared(release, input) {
            return Err(invalid(
                resource_id,
                "input_rendition_ids must reference declared rendition ids",
            ));
        }
    }
    let mut resource_lineage = HashSet::new();
    for input in &provenance.input_resource_ids {
        validate_digest(input).map_err(|message| invalid(resource_id, message))?;
        if !resource_lineage.insert(input) {
            return Err(invalid(resource_id, "input_resource_ids must be unique"));
        }
        if !release
            .resources
            .iter()
            .any(|resource| &resource.resource_id == input)
        {
            return Err(invalid(
                resource_id,
                "input_resource_ids must reference declared resource ids",
            ));
        }
    }
    Ok(())
}

/// Every compatibility input must reference an exact declared rendition and,
/// when present, an exact declared resource; checks are stable non-empty
/// strings.
fn validate_compatibility(
    release: &PackageReleaseV3,
    owner: &str,
    compatibility: &CompatibilityDeclaration,
) -> Result<(), V3Error> {
    let mut seen_inputs = HashSet::new();
    for input in &compatibility.verified_inputs {
        if !rendition_declared(release, &input.rendition_id) {
            return Err(invalid(
                owner,
                "compatibility verified input rendition is not declared",
            ));
        }
        if !seen_inputs.insert(&input.rendition_id) {
            return Err(invalid(
                owner,
                "compatibility verified inputs must be unique",
            ));
        }
        if let Some(resource_id) = &input.resource_id {
            validate_digest(resource_id).map_err(|message| invalid(owner, message))?;
            if !release
                .resources
                .iter()
                .any(|resource| &resource.resource_id == resource_id)
            {
                return Err(invalid(
                    owner,
                    "compatibility verified input resource is not declared",
                ));
            }
        }
    }
    if compatibility
        .checks
        .iter()
        .any(|check| check.trim().is_empty())
    {
        return Err(invalid(owner, "compatibility checks must not be empty"));
    }
    Ok(())
}

fn rendition_declared(release: &PackageReleaseV3, rendition_id: &str) -> bool {
    release
        .document_renditions
        .iter()
        .any(|rendition| rendition.rendition_id == rendition_id)
        || release
            .media_renditions
            .iter()
            .any(|rendition| rendition.rendition_id == rendition_id)
}

fn validate_resource_descriptors(
    release: &PackageReleaseV3,
    release_value: &Value,
) -> Result<(), V3Error> {
    let edition_support: HashSet<&str> = release
        .edition
        .support_languages
        .iter()
        .map(String::as_str)
        .collect();
    let mut seen = HashSet::new();
    for (index, resource) in release.resources.iter().enumerate() {
        validate_digest(&resource.resource_id)
            .map_err(|message| invalid(&resource.resource_id, message))?;
        if !seen.insert(&resource.resource_id) {
            return Err(invalid(&resource.resource_id, "duplicate resource_id"));
        }
        // The descriptor's canonical JSON is the resource identity.
        let descriptor_value = &release_value["resources"][index]["descriptor"];
        let canonical =
            canonical::serialize_canonical(descriptor_value).map_err(|error| V3Error::Invalid {
                path: resource.resource_id.clone(),
                message: format!("descriptor is not canonical JSON: {error}"),
            })?;
        let expected = sha256_id(&canonical);
        if expected != resource.resource_id {
            return Err(invalid(
                &resource.resource_id,
                "resource_id does not match the descriptor canonical JSON",
            ));
        }

        let descriptor = &resource.descriptor;
        if descriptor.schema.is_empty() || descriptor.kind.trim().is_empty() {
            return Err(invalid(
                &resource.resource_id,
                "descriptor schema and kind must not be empty",
            ));
        }
        validate_blob_declaration(&descriptor.payload_blob)
            .map_err(|message| invalid(&resource.resource_id, message))?;
        validate_provenance_v3(release, &resource.resource_id, &descriptor.provenance)?;
        validate_quality(&resource.resource_id, &descriptor.quality)?;
        if let Some(producer) = &descriptor.producer {
            validate_producer(&resource.resource_id, producer)?;
        }
        if let Some(compatibility) = &descriptor.compatibility {
            validate_compatibility(release, &resource.resource_id, compatibility)?;
        }

        // Role and language rules: no default English, no underscore tags.
        match descriptor.role {
            ResourceRole::Base => {
                let language = descriptor.content_language.as_deref().ok_or_else(|| {
                    invalid(
                        &resource.resource_id,
                        "base resource requires content_language",
                    )
                })?;
                validate_language_tag(language)
                    .map_err(|message| invalid(&resource.resource_id, message))?;
                if !descriptor.support_languages.is_empty() {
                    return Err(invalid(
                        &resource.resource_id,
                        "base resource must not declare support_languages",
                    ));
                }
            }
            ResourceRole::Assistance => {
                // Presence is checked on raw JSON: an assistance resource must
                // omit content_language entirely, including null.
                if descriptor_value.get("content_language").is_some() {
                    return Err(invalid(
                        &resource.resource_id,
                        "assistance resource must omit content_language entirely",
                    ));
                }
                if descriptor.support_languages.is_empty() {
                    return Err(invalid(
                        &resource.resource_id,
                        "assistance resource requires at least one support_language",
                    ));
                }
                let mut unique = HashSet::new();
                for language in &descriptor.support_languages {
                    validate_language_tag(language)
                        .map_err(|message| invalid(&resource.resource_id, message))?;
                    if !unique.insert(language) {
                        return Err(invalid(
                            &resource.resource_id,
                            "support_languages must be unique",
                        ));
                    }
                    if !edition_support.contains(language.as_str()) {
                        return Err(invalid(
                            &resource.resource_id,
                            "assistance support_language must belong to the edition support_languages",
                        ));
                    }
                }
            }
        }

        // Subject: always binds the exact material revision id; may bind
        // declared document/media rendition ids and anchor resources.
        validate_subject(release, &resource.resource_id, &descriptor.subject)?;

        // Dependencies: exact in-release ids, closed and unique; Base may not
        // directly depend on Assistance (transitive closure is checked later).
        let mut deps = HashSet::new();
        for dependency in &descriptor.dependencies {
            let target = release
                .resources
                .iter()
                .find(|other| other.resource_id == dependency.resource_id)
                .ok_or_else(|| {
                    invalid(&resource.resource_id, "dependency is not in the release")
                })?;
            if target.resource_id == resource.resource_id {
                return Err(invalid(
                    &resource.resource_id,
                    "resource cannot depend on itself",
                ));
            }
            if !deps.insert(&dependency.resource_id) {
                return Err(invalid(
                    &resource.resource_id,
                    "dependency ids must be unique",
                ));
            }
            if descriptor.role == ResourceRole::Base
                && target.descriptor.role == ResourceRole::Assistance
            {
                return Err(invalid(
                    &resource.resource_id,
                    "base resource cannot depend on an assistance resource",
                ));
            }
        }
    }
    Ok(())
}

/// The subject always binds the exact material revision id and may bind
/// declared document/media rendition ids and anchor resources; every
/// reference is validated.
fn validate_subject(
    release: &PackageReleaseV3,
    resource_id: &str,
    subject: &SubjectDeclaration,
) -> Result<(), V3Error> {
    if subject.material_revision_id != release.material.material_revision_id {
        return Err(invalid(
            resource_id,
            "subject material_revision_id differs from the release",
        ));
    }
    let mut renditions = HashSet::new();
    for rendition_id in &subject.rendition_ids {
        if !rendition_declared(release, rendition_id) {
            return Err(invalid(
                resource_id,
                "subject binds an undeclared rendition_id",
            ));
        }
        if !renditions.insert(rendition_id) {
            return Err(invalid(resource_id, "subject rendition_ids must be unique"));
        }
    }
    let mut anchors = HashSet::new();
    for anchor in &subject.anchor_resource_ids {
        if anchor == resource_id
            || !anchors.insert(anchor)
            || !release
                .resources
                .iter()
                .any(|other| &other.resource_id == anchor)
        {
            return Err(invalid(
                resource_id,
                "subject anchor_resource_ids must be unique, declared, and not self",
            ));
        }
    }
    Ok(())
}

/// Closure + acyclicity over in-release resource dependencies, plus the
/// transitive rules: a Base Resource must not reach an Assistance Resource,
/// a required resource must not reach an unknown optional resource, and an
/// unknown required resource is a typed incompatibility.
fn validate_dependency_graph(release: &PackageReleaseV3) -> Result<(), V3Error> {
    let mut graph = HashMap::<&str, Vec<&str>>::new();
    let mut roles = HashMap::<&str, ResourceRole>::new();
    let mut kinds = HashMap::<&str, &str>::new();
    let mut schemas = HashMap::<&str, &str>::new();
    for resource in &release.resources {
        graph.insert(
            resource.resource_id.as_str(),
            resource
                .descriptor
                .dependencies
                .iter()
                .map(|dependency| dependency.resource_id.as_str())
                .collect(),
        );
        roles.insert(resource.resource_id.as_str(), resource.descriptor.role);
        kinds.insert(
            resource.resource_id.as_str(),
            resource.descriptor.kind.as_str(),
        );
        schemas.insert(
            resource.resource_id.as_str(),
            resource.descriptor.schema.as_str(),
        );
    }

    // Unknown required resources are a typed compatibility result.
    for resource in &release.resources {
        if resource.required
            && !payload::is_known(&resource.descriptor.kind, &resource.descriptor.schema)
        {
            return Err(V3Error::Incompatible {
                resource_id: resource.resource_id.clone(),
                kind: resource.descriptor.kind.clone(),
                schema: resource.descriptor.schema.clone(),
            });
        }
    }

    // Closure: every dependency is an in-release resource id.
    for (resource_id, dependencies) in &graph {
        for dependency in dependencies {
            if !graph.contains_key(*dependency) {
                return Err(invalid(
                    *resource_id,
                    "resource dependency is not in the release",
                ));
            }
        }
    }

    // Transitive: a Base Resource must not reach an Assistance Resource.
    for resource in &release.resources {
        if resource.descriptor.role != ResourceRole::Base {
            continue;
        }
        if reachable(&resource.resource_id, &graph)
            .iter()
            .any(|next| roles[next] == ResourceRole::Assistance)
        {
            return Err(invalid(
                &resource.resource_id,
                "base resource transitively depends on an assistance resource",
            ));
        }
    }

    // Transitive: a required resource must not reach an unknown optional
    // resource (a required unknown resource is itself incompatible above).
    for resource in &release.resources {
        if !resource.required {
            continue;
        }
        let reached = reachable(&resource.resource_id, &graph);
        if let Some(unknown) = reached
            .iter()
            .find(|next| !payload::is_known(kinds[*next], schemas[*next]))
        {
            return Err(V3Error::Incompatible {
                resource_id: (*unknown).to_owned(),
                kind: kinds[*unknown].to_owned(),
                schema: schemas[*unknown].to_owned(),
            });
        }
    }

    // Acyclicity over the (bounded) graph. The borrowed release graph is
    // cloned into owned strings so the same bounded traversal backs the
    // crate-internal cycle test seam.
    let owned_graph: HashMap<String, Vec<String>> = graph
        .iter()
        .map(|(id, dependencies)| {
            (
                (*id).to_owned(),
                dependencies
                    .iter()
                    .map(|dependency| (*dependency).to_owned())
                    .collect(),
            )
        })
        .collect();
    if dependency_graph_has_cycle(&owned_graph) {
        return Err(invalid(
            "resource dependencies",
            "resource dependency graph contains a cycle",
        ));
    }
    Ok(())
}

/// Structural validation of every decoded known payload against locally
/// checkable in-release references.
fn validate_known_payloads(
    release: &PackageReleaseV3,
    decoded: &HashMap<String, KnownPayloadV3>,
    warnings: &mut Vec<String>,
) -> Result<(), V3Error> {
    for resource in &release.resources {
        let Some(payload) = decoded.get(&resource.resource_id) else {
            continue;
        };
        validate_payload(
            release,
            &resource.resource_id,
            &resource.descriptor.kind,
            payload,
            decoded,
            warnings,
        )
        .map_err(|message| invalid(&resource.resource_id, message))?;
    }
    Ok(())
}

/// Collects every referenced blob with its declared size and carrier
/// contract, rejecting a single digest declared with conflicting facts.
fn collect_expected_blobs(
    release: &PackageReleaseV3,
) -> Result<BTreeMap<String, (u64, bool)>, V3Error> {
    let mut expected = BTreeMap::<String, (u64, bool)>::new();
    for rendition in &release.document_renditions {
        insert_blob(&mut expected, &rendition.text_blob, &rendition.rendition_id)?;
    }
    for rendition in &release.media_renditions {
        insert_blob(
            &mut expected,
            &rendition.media_blob,
            &rendition.rendition_id,
        )?;
    }
    for resource in &release.resources {
        insert_blob(
            &mut expected,
            &resource.descriptor.payload_blob,
            &resource.resource_id,
        )?;
    }
    Ok(expected)
}

fn insert_blob(
    expected: &mut BTreeMap<String, (u64, bool)>,
    blob: &BlobDeclaration,
    owner: &str,
) -> Result<(), V3Error> {
    match expected.get(&blob.digest) {
        Some((size, embedded)) if *size != blob.size_bytes => Err(invalid(
            owner,
            "blob digest is declared with conflicting sizes",
        )),
        Some((size, embedded)) if *embedded != blob.embedded => Err(invalid(
            owner,
            "blob digest is declared with conflicting carrier contracts",
        )),
        Some(_) => Ok(()),
        None => {
            expected.insert(blob.digest.clone(), (blob.size_bytes, blob.embedded));
            Ok(())
        }
    }
}

/// Rejects every catalog entry that is not release.json or an exact declared
/// blob path, without reading any body.
fn verify_catalog_inventory(
    entries: &[CatalogEntry],
    expected: &BTreeMap<String, (u64, bool)>,
) -> Result<(), V3Error> {
    for entry in entries {
        if entry.name == "release.json" {
            continue;
        }
        let Some(digest) = blob_digest_from_path(&entry.name) else {
            return Err(invalid(&entry.name, "file is not declared by the release"));
        };
        if !expected.contains_key(&digest) {
            return Err(invalid(
                &entry.name,
                "blob file is not referenced by the release",
            ));
        }
    }
    Ok(())
}

/// Every carrier blob path whose body must be streamed rather than retained.
///
/// Every declared blob that Core may need to persist — resource payloads and
/// present Document/Media Rendition blobs — is retained and bounded by
/// `max_file_bytes`, so this set is empty for the current contract. The seam
/// stays so future large bodies can be streamed without changing the
/// inspection contract.
fn streamed_blob_paths(_release: &PackageReleaseV3) -> Vec<String> {
    Vec::new()
}

/// Parses `blobs/sha256/<64 lowercase hex>` and returns the digest string.
fn blob_digest_from_path(path: &str) -> Option<String> {
    let hex = path.strip_prefix(&format!(
        "{BLOB_DIRECTORY}/{BLOB_HASH_ALGORITHM_DIRECTORY}/"
    ))?;
    if hex.len() != 64
        || !hex
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return None;
    }
    Some(format!("sha256:{hex}"))
}

fn blob_path(digest: &str) -> String {
    format!(
        "{BLOB_DIRECTORY}/{BLOB_HASH_ALGORITHM_DIRECTORY}/{}",
        digest.trim_start_matches("sha256:")
    )
}

fn validate_blob_declaration(blob: &BlobDeclaration) -> Result<(), &'static str> {
    validate_digest(&blob.digest)?;
    if blob.size_bytes == 0 {
        return Err("blob size_bytes must be >= 1");
    }
    Ok(())
}

fn invalid(path: impl Into<String>, message: impl Into<String>) -> V3Error {
    V3Error::Invalid {
        path: path.into(),
        message: message.into(),
    }
}
