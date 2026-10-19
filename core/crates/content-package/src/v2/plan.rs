//! Pure Installation Plan for Content Package v2.
//!
//! The plan is a projection of an inspection result with no I/O, no
//! persistence, and no activation/selection vocabulary. It reports the
//! release/edition/revision identity, the derived delivery profile, a
//! per-resource candidate/opaque/missing disposition in release order,
//! rendition availability, and the missing-blob inventory.

use std::collections::{HashMap, HashSet};

use serde::{Deserialize, Serialize};

use super::inspect::{OpaqueResourceRecord, ResourceRecord, V2Inspection};
use super::model::{DeliveryProfile, PLAN_SCHEMA_V2, ResourceRole};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InstallationPlan {
    pub schema: String,
    pub release_id: String,
    pub edition_id: String,
    pub material_id: String,
    pub material_revision_id: String,
    pub delivery_profile: DeliveryProfile,
    pub resources: Vec<PlanResource>,
    pub renditions: Vec<PlanRendition>,
    pub missing_blobs: Vec<PlanMissingBlob>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanResource {
    pub resource_id: String,
    pub kind: String,
    pub schema: String,
    pub role: ResourceRole,
    pub required: bool,
    pub disposition: ResourceDisposition,
    pub payload_digest: String,
    pub payload_size_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceDisposition {
    /// Known payload schema, embedded, and structurally validated.
    Candidate,
    /// Unknown payload schema, preserved as a verified opaque resource.
    Opaque,
    /// Known payload schema but the payload blob is absent from the carrier.
    Missing,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanRendition {
    pub rendition_id: String,
    pub kind: String,
    pub media_type: String,
    pub available: bool,
    pub media_digest: String,
    pub media_size_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanMissingBlob {
    pub digest: String,
    pub size_bytes: u64,
    pub hints: Vec<String>,
}

/// Builds the pure installation plan from an inspection. Never performs I/O,
/// persistence, activation, or selection.
pub fn installation_plan(inspection: &V2Inspection) -> InstallationPlan {
    let candidates: HashMap<&str, &ResourceRecord> = inspection
        .resources
        .iter()
        .map(|record| (record.entry.resource_id.as_str(), record))
        .collect();
    let opaque: HashSet<&str> = inspection
        .opaque_resources
        .iter()
        .map(|record: &OpaqueResourceRecord| record.entry.resource_id.as_str())
        .collect();

    // Preserve release resource order while emitting candidate/opaque/missing
    // items.
    let resources = inspection
        .release
        .resources
        .iter()
        .map(|entry| {
            let (kind, schema, disposition) =
                if let Some(record) = candidates.get(entry.resource_id.as_str()) {
                    (
                        record.payload.kind().to_owned(),
                        record.payload.schema().to_owned(),
                        ResourceDisposition::Candidate,
                    )
                } else if opaque.contains(entry.resource_id.as_str()) {
                    (
                        entry.descriptor.kind.clone(),
                        entry.descriptor.schema.clone(),
                        ResourceDisposition::Opaque,
                    )
                } else {
                    (
                        entry.descriptor.kind.clone(),
                        entry.descriptor.schema.clone(),
                        ResourceDisposition::Missing,
                    )
                };
            PlanResource {
                resource_id: entry.resource_id.clone(),
                kind,
                schema,
                role: entry.descriptor.role,
                required: entry.required,
                disposition,
                payload_digest: entry.descriptor.payload_blob.digest.clone(),
                payload_size_bytes: entry.descriptor.payload_blob.size_bytes,
            }
        })
        .collect();

    let renditions = inspection
        .renditions
        .iter()
        .map(|record| PlanRendition {
            rendition_id: record.entry.rendition_id.clone(),
            kind: record.entry.descriptor.kind.clone(),
            media_type: record.entry.descriptor.media_type.clone(),
            available: record.media_present,
            media_digest: record.entry.descriptor.media_blob.digest.clone(),
            media_size_bytes: record.entry.descriptor.media_blob.size_bytes,
        })
        .collect();

    let missing_blobs = inspection
        .missing_blobs
        .iter()
        .map(|blob| PlanMissingBlob {
            digest: blob.digest.clone(),
            size_bytes: blob.size_bytes,
            hints: blob.hints.clone(),
        })
        .collect();

    InstallationPlan {
        schema: PLAN_SCHEMA_V2.to_owned(),
        release_id: inspection.release_id.clone(),
        edition_id: inspection.release.edition.edition_id.clone(),
        material_id: inspection.release.material.material_id.clone(),
        material_revision_id: inspection.release.material.material_revision_id.clone(),
        delivery_profile: inspection.delivery_profile,
        resources,
        renditions,
        missing_blobs,
        warnings: inspection.warnings.clone(),
    }
}
