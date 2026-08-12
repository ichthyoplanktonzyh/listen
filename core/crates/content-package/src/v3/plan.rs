//! Pure Installation Plan for Content Package v3.
//!
//! The plan is a projection of an inspection result with no I/O, no
//! persistence, and no activation/selection vocabulary. It reports the
//! release/edition/revision identity, a per-resource
//! candidate/opaque/missing disposition in release order, per-rendition
//! availability with origin and producer facts, and the missing-blob
//! inventory.

use serde::{Deserialize, Serialize};

use super::inspect::V3Inspection;
use super::model::{PLAN_SCHEMA_V3, RenditionOrigin};
use crate::v2::plan::{PlanMissingBlob, PlanResource, ResourceDisposition};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct V3InstallationPlan {
    pub schema: String,
    pub release_id: String,
    pub edition_id: String,
    pub material_id: String,
    pub material_revision_id: String,
    pub resources: Vec<PlanResource>,
    pub document_renditions: Vec<PlanDocumentRendition>,
    pub media_renditions: Vec<PlanMediaRendition>,
    pub missing_blobs: Vec<PlanMissingBlob>,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanDocumentRendition {
    pub rendition_id: String,
    pub origin: RenditionOrigin,
    pub media_type: String,
    pub language: Option<String>,
    pub available: bool,
    pub text_digest: String,
    pub text_size_bytes: u64,
    pub producer: Option<PlanProducer>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanMediaRendition {
    pub rendition_id: String,
    pub origin: RenditionOrigin,
    pub kind: String,
    pub media_type: String,
    pub available: bool,
    pub media_digest: String,
    pub media_size_bytes: u64,
    pub media_id: Option<String>,
    pub producer: Option<PlanProducer>,
}

/// Exact producer facts of a Derived rendition, shaped for durable package
/// facts. Raw provider output never appears here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlanProducer {
    pub created_at_ms: u64,
    pub tool_id: String,
    pub tool_version: String,
    pub provider_id: Option<String>,
    pub provider_version: Option<String>,
    pub model_id: Option<String>,
    pub model_version: Option<String>,
    pub config_sha256: Option<String>,
}

/// Builds the pure installation plan from an inspection. Never performs I/O,
/// persistence, activation, or selection.
pub fn installation_plan_v3(inspection: &V3Inspection) -> V3InstallationPlan {
    let candidate_ids: Vec<&str> = inspection
        .resources
        .iter()
        .map(|record| record.entry.resource_id.as_str())
        .collect();
    let opaque_ids: Vec<&str> = inspection
        .opaque_resources
        .iter()
        .map(|record| record.entry.resource_id.as_str())
        .collect();

    // Preserve release resource order while emitting candidate/opaque/missing
    // items.
    let resources = inspection
        .release
        .resources
        .iter()
        .map(|entry| {
            let (kind, schema, disposition) = if candidate_ids.contains(&entry.resource_id.as_str())
            {
                (
                    entry.descriptor.kind.clone(),
                    entry.descriptor.schema.clone(),
                    ResourceDisposition::Candidate,
                )
            } else if opaque_ids.contains(&entry.resource_id.as_str()) {
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

    let document_renditions = inspection
        .document_renditions
        .iter()
        .map(|record| PlanDocumentRendition {
            rendition_id: record.entry.rendition_id.clone(),
            origin: record.entry.origin,
            media_type: record.entry.media_type.clone(),
            language: record.entry.language.clone(),
            available: record.text_present,
            text_digest: record.entry.text_blob.digest.clone(),
            text_size_bytes: record.entry.text_blob.size_bytes,
            producer: record.entry.producer.as_ref().map(plan_producer),
        })
        .collect();

    let media_renditions = inspection
        .media_renditions
        .iter()
        .map(|record| PlanMediaRendition {
            rendition_id: record.entry.rendition_id.clone(),
            origin: record.entry.origin,
            kind: record.entry.kind.clone(),
            media_type: record.entry.media_type.clone(),
            available: record.media_present,
            media_digest: record.entry.media_blob.digest.clone(),
            media_size_bytes: record.entry.media_blob.size_bytes,
            media_id: record.entry.media_id.clone(),
            producer: record.entry.producer.as_ref().map(plan_producer),
        })
        .collect();

    let missing_blobs = inspection
        .missing_blobs
        .iter()
        .map(|blob| PlanMissingBlob {
            digest: blob.digest.clone(),
            size_bytes: blob.size_bytes,
            hints: Vec::new(),
        })
        .collect();

    V3InstallationPlan {
        schema: PLAN_SCHEMA_V3.to_owned(),
        release_id: inspection.release_id.clone(),
        edition_id: inspection.release.edition.edition_id.clone(),
        material_id: inspection.release.material.material_id.clone(),
        material_revision_id: inspection.release.material.material_revision_id.clone(),
        resources,
        document_renditions,
        media_renditions,
        missing_blobs,
        warnings: inspection.warnings.clone(),
    }
}

fn plan_producer(producer: &super::model::ProducerDeclaration) -> PlanProducer {
    PlanProducer {
        created_at_ms: producer.created_at_ms,
        tool_id: producer.tool.id.clone(),
        tool_version: producer.tool.version.clone(),
        provider_id: producer
            .provider
            .as_ref()
            .map(|versioned| versioned.id.clone()),
        provider_version: producer
            .provider
            .as_ref()
            .map(|versioned| versioned.version.clone()),
        model_id: producer
            .model
            .as_ref()
            .map(|versioned| versioned.id.clone()),
        model_version: producer
            .model
            .as_ref()
            .map(|versioned| versioned.version.clone()),
        config_sha256: producer.config_sha256.clone(),
    }
}
