//! Content Package v2 inspection.
//!
//! `inspect_v2_path` / `inspect_v2_path_with_limits` perform bounded,
//! persistence-free inspection of a v2 carrier (directory or deterministic
//! ZIP). A catalog pass reads only the control documents and catalogs every
//! entry without opening bodies; a selective pass retains known payload blobs
//! (bounded by `max_file_bytes`) while streaming rendition media and present
//! opaque payload blobs to their size and SHA-256 facts, so embedded media
//! can exceed `max_file_bytes` without being retained in memory. Inspection
//! covers canonical identity verification, blob size/hash verification,
//! provenance/quality checks, dependency/subject/entrypoint invariants
//! (including transitive closure rules), known payload decoding and
//! structural validation, opaque optional preservation, missing-blob
//! inventory, delivery hint validation, and the derived delivery profile. No
//! network or persistence work happens here.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::Path;

use serde_json::Value;
use thiserror::Error;

use crate::archive::{
    ArchiveError, CatalogEntry, PackageCatalog, SelectivePackage, StreamedFile,
    read_package_controls, read_package_selective,
};
use crate::inspect::InspectLimits;
use crate::v2::canonical::{self, CanonicalError};
use crate::v2::model::{
    BLOB_DIRECTORY, BLOB_HASH_ALGORITHM_DIRECTORY, BlobDescriptor, DELIVERY_SCHEMA_V2,
    DeliveryDocument, DeliveryProfile, PackageRelease, Provenance, Quality, RELEASE_SCHEMA_V2,
    RENDITION_AUDIO_SCHEMA_V1, RENDITION_VIDEO_SCHEMA_V1, ReleaseRendition, ReleaseResource,
    ResourceRole,
};
use crate::v2::payload::{self, KnownPayload};
use crate::v2::validate::{self, validate_https_hint, validate_language_tag};

#[derive(Debug, Error)]
pub enum V2Error {
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
    #[error("delivery.json is invalid JSON: {0}")]
    DeliveryJson(serde_json::Error),
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

impl From<ArchiveError> for V2Error {
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

impl From<CanonicalError> for V2Error {
    fn from(error: CanonicalError) -> Self {
        Self::Invalid {
            path: "release.json".to_owned(),
            message: error.to_string(),
        }
    }
}

/// The typed result of inspecting a v2 carrier.
#[derive(Debug, Clone)]
pub struct V2Inspection {
    pub release: PackageRelease,
    /// The release identity: `sha256:<hex>` of the canonical release.json.
    pub release_id: String,
    /// The same digest, kept as a plain hex string for compatibility facts.
    pub release_sha256: String,
    pub delivery: Option<DeliveryDocument>,
    pub resources: Vec<ResourceRecord>,
    pub opaque_resources: Vec<OpaqueResourceRecord>,
    pub renditions: Vec<RenditionRecord>,
    /// digest -> blob record for every blob referenced by the release.
    pub blobs: BTreeMap<String, BlobRecord>,
    pub missing_blobs: Vec<MissingBlob>,
    pub delivery_profile: DeliveryProfile,
    pub warnings: Vec<String>,
    pub total_bytes: u64,
}

#[derive(Debug, Clone)]
pub struct ResourceRecord {
    pub entry: ReleaseResource,
    pub payload: KnownPayload,
    pub bytes_sha256: String,
}

#[derive(Debug, Clone)]
pub struct OpaqueResourceRecord {
    pub entry: ReleaseResource,
    pub payload_present: bool,
}

#[derive(Debug, Clone)]
pub struct RenditionRecord {
    pub entry: ReleaseRendition,
    pub media_present: bool,
}

#[derive(Debug, Clone)]
pub struct BlobRecord {
    pub digest: String,
    pub size_bytes: u64,
    pub present: bool,
    pub hints: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct MissingBlob {
    pub digest: String,
    pub size_bytes: u64,
    pub hints: Vec<String>,
}

pub fn inspect_v2_path(path: impl AsRef<Path>) -> Result<V2Inspection, V2Error> {
    inspect_v2_path_with_limits(path, InspectLimits::default())
}

pub fn inspect_v2_path_with_limits(
    path: impl AsRef<Path>,
    limits: InspectLimits,
) -> Result<V2Inspection, V2Error> {
    let path = path.as_ref();
    // First pass: read only the control documents and catalog every carrier
    // entry (safe name and size) without opening ordinary or media bodies.
    let catalog = read_package_controls(path, limits, &["release.json", "delivery.json"])?;
    inspect_v2_catalog(path, catalog, limits)
}

fn inspect_v2_catalog(
    path: &Path,
    catalog: PackageCatalog,
    limits: InspectLimits,
) -> Result<V2Inspection, V2Error> {
    let PackageCatalog {
        controls,
        entries,
        total_bytes,
    } = catalog;
    let mut controls = controls;
    let release_bytes = controls
        .remove("release.json")
        .ok_or(V2Error::MissingRelease)?;
    // release.json must be canonical JSON: parse strictly and reject any
    // deviation from the canonical profile. The single parse result backs
    // both the canonical verification and the descriptor identity checks.
    let release_value: Value =
        canonical::parse_canonical_verified(&release_bytes).map_err(|error| V2Error::Invalid {
            path: "release.json".to_owned(),
            message: format!("release.json is not canonical JSON: {error}"),
        })?;
    let release: PackageRelease =
        serde_json::from_slice(&release_bytes).map_err(V2Error::ReleaseJson)?;
    if release.schema != RELEASE_SCHEMA_V2 {
        return Err(invalid("release.json", "unsupported release schema"));
    }

    let release_id = sha256_id(&release_bytes);
    let release_sha256 = release_id.trim_start_matches("sha256:").to_owned();

    let mut warnings = Vec::new();

    enforce_inventory_limits(&release, limits)?;
    validate_identity(&release)?;
    validate_entrypoints(&release)?;
    validate_resource_descriptors(&release, &release_value)?;
    validate_rendition_descriptors(&release, &release_value)?;
    validate_dependency_graph(&release)?;

    // Collect every referenced blob and its declared size; reject a single
    // digest declared with conflicting sizes anywhere in the release.
    let expected = collect_expected_blobs(&release)?;

    // The optional delivery document was already read by the control pass;
    // detach it so the inventory comparison does not mistake it for an
    // undeclared carrier file.
    let delivery_bytes = controls.remove("delivery.json");

    // Every carrier entry must be release.json, the optional delivery.json,
    // or an exact declared blob path. Reject undeclared files without reading
    // their bodies.
    verify_catalog_inventory(&entries, &expected, delivery_bytes.is_some())?;

    // Second, selective pass: known payload blobs stay retained and bounded
    // by max_file_bytes; rendition media and present opaque payload blobs are
    // streamed so their bodies never occupy memory.
    let streamed_paths = streamed_blob_paths(&release, &entries);
    let streamed_refs: Vec<&str> = streamed_paths.iter().map(String::as_str).collect();
    let selective = read_package_selective(
        path,
        limits,
        &["release.json", "delivery.json"],
        &streamed_refs,
    )?;

    // The carrier must be exactly the same in both passes: the selective pass
    // must report the same entry names and sizes as the catalog pass, and the
    // second release.json/delivery.json copies must match the first-pass bytes
    // before they are discarded. This prevents mixing facts from two different
    // carrier snapshots when the carrier changes between the passes.
    verify_carrier_consistency(
        &entries,
        total_bytes,
        &release_bytes,
        delivery_bytes.as_deref(),
        &selective,
    )?;

    let mut retained = selective.files;
    retained.remove("release.json");
    retained.remove("delivery.json");
    verify_retained_blobs(&retained, &expected)?;
    verify_streamed_blobs(&selective.streamed, &expected)?;

    // A blob is present when its exact path was found either retained or
    // streamed; both forms were size- and digest-verified above.
    let mut present = retained.keys().cloned().collect::<HashSet<String>>();
    present.extend(selective.streamed.iter().map(|file| file.name.clone()));

    // Blob inventory: present when the exact path exists; otherwise missing.
    let mut blobs = BTreeMap::<String, BlobRecord>::new();
    for (digest, size_bytes) in &expected {
        let path = blob_path(digest);
        let present = present.contains(&path);
        blobs.insert(
            digest.clone(),
            BlobRecord {
                digest: digest.clone(),
                size_bytes: *size_bytes,
                present,
                hints: Vec::new(),
            },
        );
    }

    // Optional delivery.json: canonical, binds the computed release id, and
    // may carry untrusted HTTPS acquisition hints by blob digest. Inspection
    // never fetches them.
    let delivery = match delivery_bytes {
        Some(bytes) => {
            canonical::parse_canonical_verified(&bytes).map_err(|error| V2Error::Invalid {
                path: "delivery.json".to_owned(),
                message: format!("delivery.json is not canonical JSON: {error}"),
            })?;
            let document: DeliveryDocument =
                serde_json::from_slice(&bytes).map_err(V2Error::DeliveryJson)?;
            if document.schema != DELIVERY_SCHEMA_V2 {
                return Err(invalid("delivery.json", "unsupported delivery schema"));
            }
            if document.release_id != release_id {
                return Err(invalid(
                    "delivery.json",
                    "release_id does not match the computed release identity",
                ));
            }
            enforce_count(
                document.blobs.len(),
                limits.max_file_count,
                "delivery blob inventory",
            )?;
            let mut seen_digests = HashSet::new();
            let mut total_hints = 0_usize;
            for blob in &document.blobs {
                let declared_size = expected.get(&blob.digest).copied().ok_or_else(|| {
                    invalid(
                        "delivery.json",
                        "delivery blob digest is not referenced by the release",
                    )
                })?;
                if blob.size_bytes != declared_size {
                    return Err(invalid(
                        "delivery.json",
                        "delivery blob size differs from the release descriptor",
                    ));
                }
                if !seen_digests.insert(&blob.digest) {
                    return Err(invalid(
                        "delivery.json",
                        "delivery blob digests must be unique",
                    ));
                }
                enforce_count(
                    blob.hints.len(),
                    limits.max_file_count,
                    "delivery hint inventory",
                )?;
                total_hints = total_hints
                    .checked_add(blob.hints.len())
                    .ok_or(V2Error::Limit("delivery hint inventory"))?;
                for hint in &blob.hints {
                    validate_https_hint(&hint.url)
                        .map_err(|message| invalid("delivery.json", message))?;
                }
                blobs.get_mut(&blob.digest).expect("declared digest").hints =
                    blob.hints.iter().map(|hint| hint.url.clone()).collect();
            }
            enforce_count(
                total_hints,
                limits.max_file_count,
                "delivery hint inventory",
            )?;
            Some(document)
        }
        None => None,
    };

    let delivery_profile = derive_profile(&blobs);
    if let Some(document) = &delivery
        && document.profile != delivery_profile
    {
        return Err(invalid(
            "delivery.json",
            "delivery profile does not match the derived carrier profile",
        ));
    }

    let mut missing_blobs = Vec::new();
    for record in blobs.values() {
        if !record.present {
            missing_blobs.push(MissingBlob {
                digest: record.digest.clone(),
                size_bytes: record.size_bytes,
                hints: record.hints.clone(),
            });
        }
    }

    // Decode known payloads; preserve optional unknown resources as opaque.
    // Required unknown resources were already rejected as Incompatible.
    let mut decoded = HashMap::<String, KnownPayload>::new();
    let mut resources = Vec::new();
    let mut opaque_resources = Vec::new();
    for resource in &release.resources {
        let path = blob_path(&resource.descriptor.payload_blob.digest);
        let present = present.contains(&path);
        let known = payload::is_known(&resource.descriptor.kind, &resource.descriptor.schema);
        if !known {
            debug_assert!(!resource.required, "required unknown is incompatible");
            opaque_resources.push(OpaqueResourceRecord {
                entry: resource.clone(),
                payload_present: present,
            });
            warnings.push(format!(
                "resource {} is opaque (kind/schema unsupported)",
                resource.resource_id
            ));
            continue;
        }
        if !present {
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
        .map_err(|source| V2Error::PayloadJson {
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

    let mut renditions = Vec::new();
    for rendition in &release.renditions {
        let path = blob_path(&rendition.descriptor.media_blob.digest);
        renditions.push(RenditionRecord {
            entry: rendition.clone(),
            media_present: present.contains(&path),
        });
    }

    // total_bytes counts every carrier entry exactly once and comes from the
    // selective pass, which observed retained and streamed bodies alike; the
    // consistency check above guarantees it equals the catalog-pass total.
    let total_bytes = selective.total_bytes;

    if delivery.is_none() {
        warnings.push("delivery.json is absent".to_owned());
    }
    if !missing_blobs.is_empty() {
        warnings.push(format!(
            "{} referenced blob(s) are absent from the carrier",
            missing_blobs.len()
        ));
    }

    Ok(V2Inspection {
        release,
        release_id,
        release_sha256,
        delivery,
        resources,
        opaque_resources,
        renditions,
        blobs,
        missing_blobs,
        delivery_profile,
        warnings,
        total_bytes,
    })
}

/// Applies `InspectLimits.max_file_count` to the release resource, rendition,
/// entrypoint, graph, and delivery inventories, plus the combined resource +
/// rendition entry count (computed with checked arithmetic). The graph edge
/// budget keeps every closure/traversal check strictly bounded.
fn enforce_inventory_limits(
    release: &PackageRelease,
    limits: InspectLimits,
) -> Result<(), V2Error> {
    let maximum = limits.max_file_count;
    enforce_count(release.resources.len(), maximum, "resource inventory")?;
    enforce_count(release.renditions.len(), maximum, "rendition inventory")?;
    let combined_entries = release
        .resources
        .len()
        .checked_add(release.renditions.len())
        .ok_or(V2Error::Limit("combined resource and rendition inventory"))?;
    enforce_count(
        combined_entries,
        maximum,
        "combined resource and rendition inventory",
    )?;
    enforce_count(release.entrypoints.len(), maximum, "entrypoint inventory")?;
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
            resource.descriptor.subject.rendition_ids.len(),
            maximum,
            "subject rendition inventory",
        )?;
        enforce_count(
            resource.descriptor.subject.anchor_resource_ids.len(),
            maximum,
            "subject anchor inventory",
        )?;
        edges = edges
            .checked_add(resource.descriptor.dependencies.len())
            .ok_or(V2Error::Limit("dependency graph"))?;
    }
    enforce_count(edges, maximum, "dependency graph")
}

fn enforce_count(count: usize, maximum: usize, label: &'static str) -> Result<(), V2Error> {
    if count > maximum {
        return Err(V2Error::Limit(label));
    }
    Ok(())
}

fn validate_identity(release: &PackageRelease) -> Result<(), V2Error> {
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

fn validate_entrypoints(release: &PackageRelease) -> Result<(), V2Error> {
    if release.entrypoints.is_empty() {
        return Err(invalid("release.json", "release declares no entrypoints"));
    }
    let mut ids = HashSet::new();
    let mut has_base_or_rendition = false;
    for entrypoint in &release.entrypoints {
        if entrypoint.entrypoint_id.trim().is_empty() || !ids.insert(&entrypoint.entrypoint_id) {
            return Err(invalid(
                "release.json",
                "entrypoint ids must be non-empty and unique",
            ));
        }
        match (&entrypoint.resource_id, &entrypoint.rendition_id) {
            (Some(resource_id), None) => {
                let resource = release
                    .resources
                    .iter()
                    .find(|resource| &resource.resource_id == resource_id)
                    .ok_or_else(|| {
                        invalid("release.json", "entrypoint resource is not declared")
                    })?;
                if resource.descriptor.role == ResourceRole::Base {
                    has_base_or_rendition = true;
                }
            }
            (None, Some(rendition_id)) => {
                if !release
                    .renditions
                    .iter()
                    .any(|rendition| &rendition.rendition_id == rendition_id)
                {
                    return Err(invalid(
                        "release.json",
                        "entrypoint rendition is not declared",
                    ));
                }
                has_base_or_rendition = true;
            }
            _ => {
                return Err(invalid(
                    "release.json",
                    "entrypoint must reference exactly one of resource_id or rendition_id",
                ));
            }
        }
    }
    if !has_base_or_rendition {
        return Err(invalid(
            "release.json",
            "no entrypoint references a declared Base Resource or Media Rendition",
        ));
    }
    Ok(())
}

fn validate_resource_descriptors(
    release: &PackageRelease,
    release_value: &Value,
) -> Result<(), V2Error> {
    let declared_ids: HashSet<&str> = release
        .resources
        .iter()
        .map(|resource| resource.resource_id.as_str())
        .collect();
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
            canonical::serialize_canonical(descriptor_value).map_err(|error| V2Error::Invalid {
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
        validate_blob_descriptor(&descriptor.payload_blob)
            .map_err(|message| invalid(&resource.resource_id, message))?;
        validate_provenance(&resource.resource_id, &descriptor.provenance, &declared_ids)?;
        validate_quality(&resource.resource_id, &descriptor.quality)?;

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
        // declared rendition ids and anchor resources.
        if descriptor.subject.material_revision_id != release.material.material_revision_id {
            return Err(invalid(
                &resource.resource_id,
                "subject material_revision_id differs from the release",
            ));
        }
        for rendition_id in &descriptor.subject.rendition_ids {
            if !release
                .renditions
                .iter()
                .any(|rendition| &rendition.rendition_id == rendition_id)
            {
                return Err(invalid(
                    &resource.resource_id,
                    "subject binds an undeclared rendition_id",
                ));
            }
        }
        let mut anchors = HashSet::new();
        for anchor in &descriptor.subject.anchor_resource_ids {
            if anchor == &resource.resource_id
                || !anchors.insert(anchor)
                || !release
                    .resources
                    .iter()
                    .any(|other| &other.resource_id == anchor)
            {
                return Err(invalid(
                    &resource.resource_id,
                    "subject anchor_resource_ids must be unique, declared, and not self",
                ));
            }
        }

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

fn validate_provenance(
    resource_id: &str,
    provenance: &Provenance,
    declared_ids: &HashSet<&str>,
) -> Result<(), V2Error> {
    if provenance.tool.id.trim().is_empty() || provenance.tool.version.trim().is_empty() {
        return Err(invalid(
            resource_id,
            "provenance tool id/version must not be empty",
        ));
    }
    for producer in [&provenance.provider, &provenance.model]
        .into_iter()
        .flatten()
    {
        if producer.id.trim().is_empty() || producer.version.trim().is_empty() {
            return Err(invalid(
                resource_id,
                "provenance producer id/version must not be empty",
            ));
        }
    }
    if let Some(digest) = &provenance.config_sha256 {
        validate_digest(digest).map_err(|message| invalid(resource_id, message))?;
    }
    let mut lineage = HashSet::new();
    for input in &provenance.input_resource_ids {
        validate_digest(input).map_err(|message| invalid(resource_id, message))?;
        if !lineage.insert(input) {
            return Err(invalid(resource_id, "input_resource_ids must be unique"));
        }
        if !declared_ids.contains(input.as_str()) {
            return Err(invalid(
                resource_id,
                "input_resource_ids must reference declared resource ids",
            ));
        }
    }
    Ok(())
}

fn validate_quality(resource_id: &str, quality: &Quality) -> Result<(), V2Error> {
    if quality
        .warnings
        .iter()
        .any(|warning| warning.trim().is_empty())
    {
        return Err(invalid(resource_id, "quality warnings must not be empty"));
    }
    Ok(())
}

fn validate_rendition_descriptors(
    release: &PackageRelease,
    release_value: &Value,
) -> Result<(), V2Error> {
    let mut seen = HashSet::new();
    for (index, rendition) in release.renditions.iter().enumerate() {
        validate_digest(&rendition.rendition_id)
            .map_err(|message| invalid(&rendition.rendition_id, message))?;
        if !seen.insert(&rendition.rendition_id) {
            return Err(invalid(&rendition.rendition_id, "duplicate rendition_id"));
        }
        let descriptor_value = &release_value["renditions"][index]["descriptor"];
        let canonical =
            canonical::serialize_canonical(descriptor_value).map_err(|error| V2Error::Invalid {
                path: rendition.rendition_id.clone(),
                message: format!("descriptor is not canonical JSON: {error}"),
            })?;
        let expected = sha256_id(&canonical);
        if expected != rendition.rendition_id {
            return Err(invalid(
                &rendition.rendition_id,
                "rendition_id does not match the descriptor canonical JSON",
            ));
        }
        let descriptor = &rendition.descriptor;
        // The audio/video schema is tied to the kind and the media_type family.
        let (expected_schema, media_family) = match descriptor.kind.as_str() {
            "audio" => (RENDITION_AUDIO_SCHEMA_V1, "audio/"),
            "video" => (RENDITION_VIDEO_SCHEMA_V1, "video/"),
            other => {
                return Err(invalid(
                    &rendition.rendition_id,
                    format!("unsupported rendition kind: {other}"),
                ));
            }
        };
        if descriptor.schema != expected_schema {
            return Err(invalid(
                &rendition.rendition_id,
                "rendition schema does not match its kind",
            ));
        }
        if !descriptor.media_type.starts_with(media_family) {
            return Err(invalid(
                &rendition.rendition_id,
                "rendition media_type does not match its kind",
            ));
        }
        if descriptor.material_revision_id != release.material.material_revision_id {
            return Err(invalid(
                &rendition.rendition_id,
                "rendition material_revision_id differs from the release",
            ));
        }
        validate_blob_descriptor(&descriptor.media_blob)
            .map_err(|message| invalid(&rendition.rendition_id, message))?;
    }
    Ok(())
}

/// Closure + acyclicity over in-release resource dependencies, plus the
/// transitive rules: a Base Resource must not reach an Assistance Resource,
/// a required resource must not reach an unknown optional resource, and an
/// unknown required resource is a typed incompatibility.
fn validate_dependency_graph(release: &PackageRelease) -> Result<(), V2Error> {
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
            return Err(V2Error::Incompatible {
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
            return Err(V2Error::Incompatible {
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

/// Acyclicity over a (bounded) dependency graph, exposed as a test seam that
/// mirrors the v1 `inspect::validate_dependency_graph` seam. Full-package
/// inspection reaches it with identity-bearing descriptors; tests exercise it
/// with synthetic graphs because a real cycle cannot be serialized: every
/// dependency edge is a digest inside an identity-bearing descriptor.
pub(crate) fn dependency_graph_has_cycle(graph: &HashMap<String, Vec<String>>) -> bool {
    fn visit<'a>(
        id: &'a str,
        graph: &'a HashMap<String, Vec<String>>,
        visiting: &mut HashSet<&'a str>,
        visited: &mut HashSet<&'a str>,
    ) -> bool {
        if visited.contains(id) {
            return false;
        }
        if !visiting.insert(id) {
            return true;
        }
        if graph[id]
            .iter()
            .any(|next| visit(next, graph, visiting, visited))
        {
            return true;
        }
        visiting.remove(id);
        visited.insert(id);
        false
    }
    let mut visiting = HashSet::new();
    let mut visited = HashSet::new();
    graph
        .keys()
        .any(|id| visit(id, graph, &mut visiting, &mut visited))
}

/// Every node reachable from `start` through dependency edges (excluding the
/// start node itself). Bounded: the graph is closed with at most the enforced
/// node/edge budget, and each node is visited once.
fn reachable<'a>(start: &'a str, graph: &HashMap<&'a str, Vec<&'a str>>) -> Vec<&'a str> {
    let mut seen = HashSet::new();
    seen.insert(start);
    let mut pending = vec![start];
    let mut reached = Vec::new();
    while let Some(next) = pending.pop() {
        for dependency in &graph[next] {
            if seen.insert(dependency) {
                reached.push(*dependency);
                pending.push(*dependency);
            }
        }
    }
    reached
}

fn validate_known_payloads(
    release: &PackageRelease,
    decoded: &HashMap<String, KnownPayload>,
    warnings: &mut Vec<String>,
) -> Result<(), V2Error> {
    for resource in &release.resources {
        let Some(payload) = decoded.get(&resource.resource_id) else {
            continue;
        };
        let owner = resource.resource_id.clone();
        // Anchors are resolved through the complete descriptor dependency
        // closure and must be unique, mirroring v1's anchored transcript rule.
        let subtitle_anchors = anchored_payloads(resource, release, decoded, "subtitle_text_track");
        if subtitle_anchors.len() > 1 {
            return Err(invalid(
                &owner,
                "resource resolves more than one subtitle anchor",
            ));
        }
        let timeline_anchors = anchored_payloads(resource, release, decoded, "word_timeline");
        if timeline_anchors.len() > 1 {
            return Err(invalid(
                &owner,
                "resource resolves more than one word timeline anchor",
            ));
        }
        let subtitle = subtitle_anchors.first().and_then(|anchor| match anchor {
            KnownPayload::SubtitleTextTrack(track) => Some(track),
            _ => None,
        });
        let timeline = timeline_anchors.first().and_then(|anchor| match anchor {
            KnownPayload::WordTimeline(track) => Some(track),
            _ => None,
        });
        let result = match payload {
            KnownPayload::DocumentText(value) => validate::validate_document_text(value),
            KnownPayload::TimedTextTrack(value) => validate::validate_timed_text_track(value),
            KnownPayload::Translation(value) => {
                validate::validate_translation(resource, release, decoded, value, warnings)
            }
            KnownPayload::SubtitleTextTrack(value) => validate::validate_subtitle_text_track(value),
            KnownPayload::WordTimeline(value) => validate::validate_word_timeline(value, subtitle),
            KnownPayload::PhoneTimeline(value) => {
                validate::validate_phone_timeline(value, subtitle, timeline)
            }
            KnownPayload::SenseGroupAnalysis(value) => {
                validate::validate_sense_group_analysis(value, subtitle)
            }
            KnownPayload::WordAcoustics(value) => {
                validate::validate_word_acoustics(value, subtitle, timeline)
            }
            KnownPayload::ProsodyAnalysis(value) => {
                validate::validate_prosody_analysis(value, subtitle, timeline)
            }
        };
        result.map_err(|message| invalid(&resource.resource_id, message))?;
    }
    Ok(())
}

/// Every payload of `kind` reachable from `resource` through the descriptor
/// dependency closure. Each resource id is visited once, so the traversal is
/// bounded by the enforced graph inventory.
fn anchored_payloads<'a>(
    resource: &ReleaseResource,
    release: &PackageRelease,
    decoded: &'a HashMap<String, KnownPayload>,
    expected_kind: &str,
) -> Vec<&'a KnownPayload> {
    let mut pending = resource
        .descriptor
        .dependencies
        .iter()
        .map(|dependency| dependency.resource_id.as_str())
        .collect::<Vec<_>>();
    let mut seen = HashSet::new();
    let mut found = Vec::new();
    while let Some(next) = pending.pop() {
        if !seen.insert(next) {
            continue;
        }
        let Some(payload) = decoded.get(next) else {
            continue;
        };
        if payload.kind() == expected_kind
            && !found.iter().any(|existing| {
                std::ptr::eq(
                    *existing as *const KnownPayload,
                    payload as *const KnownPayload,
                )
            })
        {
            found.push(payload);
        }
        if let Some(dependency) = release
            .resources
            .iter()
            .find(|candidate| candidate.resource_id == next)
        {
            pending.extend(
                dependency
                    .descriptor
                    .dependencies
                    .iter()
                    .map(|item| item.resource_id.as_str()),
            );
        }
    }
    found
}

/// Collects every referenced blob with its declared size, rejecting a single
/// digest declared with conflicting sizes.
fn collect_expected_blobs(release: &PackageRelease) -> Result<BTreeMap<String, u64>, V2Error> {
    let mut expected = BTreeMap::<String, u64>::new();
    for resource in &release.resources {
        insert_blob_size(
            &mut expected,
            &resource.descriptor.payload_blob,
            &resource.resource_id,
        )?;
    }
    for rendition in &release.renditions {
        insert_blob_size(
            &mut expected,
            &rendition.descriptor.media_blob,
            &rendition.rendition_id,
        )?;
    }
    Ok(expected)
}

fn insert_blob_size(
    expected: &mut BTreeMap<String, u64>,
    blob: &BlobDescriptor,
    owner: &str,
) -> Result<(), V2Error> {
    match expected.get(&blob.digest) {
        Some(size) if *size != blob.size_bytes => Err(invalid(
            owner,
            "blob digest is declared with conflicting sizes",
        )),
        Some(_) => Ok(()),
        None => {
            expected.insert(blob.digest.clone(), blob.size_bytes);
            Ok(())
        }
    }
}

/// Rejects every catalog entry that is not release.json, the optional
/// delivery.json, or an exact declared blob path, without reading any body.
fn verify_catalog_inventory(
    entries: &[CatalogEntry],
    expected: &BTreeMap<String, u64>,
    delivery_present: bool,
) -> Result<(), V2Error> {
    for entry in entries {
        if entry.name == "release.json" || (delivery_present && entry.name == "delivery.json") {
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

/// Verifies every retained carrier file is an exact declared blob path with
/// the declared size and raw-byte digest.
fn verify_retained_blobs(
    files: &BTreeMap<String, Vec<u8>>,
    expected: &BTreeMap<String, u64>,
) -> Result<(), V2Error> {
    for path in files.keys() {
        let Some(digest) = blob_digest_from_path(path) else {
            return Err(invalid(path, "file is not declared by the release"));
        };
        let declared_size = expected
            .get(&digest)
            .copied()
            .ok_or_else(|| invalid(path, "blob file is not referenced by the release"))?;
        let bytes = &files[path];
        // Verify size before hash.
        if bytes.len() as u64 != declared_size {
            return Err(invalid(
                path,
                "blob file size does not match the descriptor",
            ));
        }
        let actual_digest = format!("sha256:{}", sha256_hex(bytes));
        if actual_digest != digest {
            return Err(invalid(path, "blob file digest does not match its content"));
        }
    }
    Ok(())
}

/// Verifies every streamed entry is an exact declared blob path whose
/// observed size and SHA-256 match the descriptor. Bodies were never
/// retained; only the size and digest facts are available to check.
fn verify_streamed_blobs(
    streamed: &[StreamedFile],
    expected: &BTreeMap<String, u64>,
) -> Result<(), V2Error> {
    for file in streamed {
        let Some(digest) = blob_digest_from_path(&file.name) else {
            return Err(invalid(&file.name, "file is not declared by the release"));
        };
        let declared_size = expected
            .get(&digest)
            .copied()
            .ok_or_else(|| invalid(&file.name, "blob file is not referenced by the release"))?;
        // Verify size before hash, mirroring the retained-blob order.
        if file.size != declared_size {
            return Err(invalid(
                &file.name,
                "blob file size does not match the descriptor",
            ));
        }
        if file.sha256 != digest {
            return Err(invalid(
                &file.name,
                "blob file digest does not match its content",
            ));
        }
    }
    Ok(())
}

/// Verifies the second, selective pass observed exactly the same carrier as
/// the first catalog pass. Every entry — release.json, the optional
/// delivery.json, retained blobs, and streamed blobs — must appear with the
/// same name and size in both passes, the selective copies of the control
/// documents must match the first-pass bytes before they are discarded (this
/// catches same-size mutation of release.json or delivery.json), a delivery
/// presence change must fail, and the two observed totals must agree. Any
/// change fails with the stable `carrier changed between inspection passes`
/// error so facts from two different carrier snapshots are never mixed.
pub(crate) fn verify_carrier_consistency(
    catalog_entries: &[CatalogEntry],
    catalog_total_bytes: u64,
    release_bytes: &[u8],
    delivery_bytes: Option<&[u8]>,
    selective: &SelectivePackage,
) -> Result<(), V2Error> {
    let selective_sizes = selective_entry_sizes(&selective.files, &selective.streamed);
    for entry in catalog_entries {
        if selective_sizes.get(entry.name.as_str()) != Some(&entry.size) {
            return Err(carrier_changed(&entry.name));
        }
    }
    for name in selective_sizes.keys() {
        if !catalog_entries.iter().any(|entry| entry.name == *name) {
            return Err(carrier_changed(name));
        }
    }
    match selective.files.get("release.json") {
        Some(bytes) if bytes == release_bytes => {}
        _ => return Err(carrier_changed("release.json")),
    }
    match (delivery_bytes, selective.files.get("delivery.json")) {
        (Some(first), Some(second)) if first == second => {}
        (None, None) => {}
        _ => return Err(carrier_changed("delivery.json")),
    }
    if selective.total_bytes != catalog_total_bytes {
        return Err(carrier_changed("package"));
    }
    Ok(())
}

/// Every selective-pass file, retained and streamed, mapped to its observed
/// size by safe entry name.
fn selective_entry_sizes<'a>(
    files: &'a BTreeMap<String, Vec<u8>>,
    streamed: &'a [StreamedFile],
) -> BTreeMap<&'a str, u64> {
    let mut sizes = BTreeMap::new();
    for (name, bytes) in files {
        sizes.insert(name.as_str(), bytes.len() as u64);
    }
    for file in streamed {
        sizes.insert(file.name.as_str(), file.size);
    }
    sizes
}

fn carrier_changed(name: &str) -> V2Error {
    V2Error::Invalid {
        path: name.to_owned(),
        message: "carrier changed between inspection passes".to_owned(),
    }
}

/// Every carrier blob path whose body must be streamed rather than retained:
/// rendition media blobs and present optional opaque payload blobs, excluding
/// any path whose digest is already retained as a known payload. Known-payload
/// retention takes precedence so a shared digest stays decodable and bounded
/// by `max_file_bytes`.
fn streamed_blob_paths(release: &PackageRelease, entries: &[CatalogEntry]) -> Vec<String> {
    let known_paths: HashSet<String> = release
        .resources
        .iter()
        .filter(|resource| {
            payload::is_known(&resource.descriptor.kind, &resource.descriptor.schema)
        })
        .map(|resource| blob_path(&resource.descriptor.payload_blob.digest))
        .collect();
    let present: HashSet<&str> = entries.iter().map(|entry| entry.name.as_str()).collect();
    let mut streamed = Vec::new();
    let mut seen = HashSet::new();
    for rendition in &release.renditions {
        let path = blob_path(&rendition.descriptor.media_blob.digest);
        if !known_paths.contains(&path) && seen.insert(path.clone()) {
            streamed.push(path);
        }
    }
    for resource in &release.resources {
        let path = blob_path(&resource.descriptor.payload_blob.digest);
        if !resource.required
            && !known_paths.contains(&path)
            && present.contains(path.as_str())
            && seen.insert(path.clone())
        {
            streamed.push(path);
        }
    }
    streamed
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

fn derive_profile(blobs: &BTreeMap<String, BlobRecord>) -> DeliveryProfile {
    let referenced = blobs.len();
    if referenced == 0 {
        return DeliveryProfile::Embedded;
    }
    let present = blobs.values().filter(|blob| blob.present).count();
    if present == referenced {
        DeliveryProfile::Embedded
    } else if present == 0 {
        DeliveryProfile::Referenced
    } else {
        DeliveryProfile::Hybrid
    }
}

fn validate_digest(value: &str) -> Result<(), &'static str> {
    let Some(hex) = value.strip_prefix("sha256:") else {
        return Err("identity must start with sha256:");
    };
    if hex.len() != 64
        || !hex
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err("identity must contain a lowercase SHA-256 hex digest");
    }
    Ok(())
}

fn validate_blob_descriptor(blob: &BlobDescriptor) -> Result<(), &'static str> {
    validate_digest(&blob.digest)?;
    if blob.size_bytes == 0 {
        return Err("blob size_bytes must be >= 1");
    }
    Ok(())
}

fn sha256_id(bytes: &[u8]) -> String {
    format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
}

fn sha256_hex(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

fn invalid(path: impl Into<String>, message: impl Into<String>) -> V2Error {
    V2Error::Invalid {
        path: path.into(),
        message: message.into(),
    }
}

use sha2::{Digest as _, Sha256};
