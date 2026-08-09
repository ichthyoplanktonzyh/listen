//! Content Package v2 contract models.
//!
//! A v2 carrier holds one immutable Package Release: a canonical
//! `release.json`, an optional canonical `delivery.json`, and content-addressed
//! blobs under `blobs/sha256/<hex>`. Resource and rendition descriptors are
//! embedded in `release.json`; their identities are the SHA-256 of the
//! descriptor's canonical JSON.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const RELEASE_SCHEMA_V2: &str = "listen.content-package.release.v2";
pub const DELIVERY_SCHEMA_V2: &str = "listen.content-package.delivery.v2";
pub const PLAN_SCHEMA_V2: &str = "listen.content-package.plan.v2";

/// Payload schema identifiers. V2 uses payload-specific stable identifiers
/// under `listen.payload.*`; the v1 `listen.resource.*` full-envelope
/// identifiers are never reinterpreted here. The six generated resource
/// families keep their v1 payload *shapes* verbatim while the envelope
/// changes in v2.
pub const DOCUMENT_TEXT_SCHEMA_V1: &str = "listen.payload.document-text.v1";
pub const TIMED_TEXT_TRACK_SCHEMA_V2: &str = "listen.payload.timed-text-track.v2";
pub const TRANSLATION_SCHEMA_V1: &str = "listen.payload.translation.v1";
pub const SUBTITLE_TEXT_TRACK_SCHEMA_V1: &str = "listen.payload.subtitle-text-track.v1";
pub const WORD_TIMELINE_SCHEMA_V1: &str = "listen.payload.word-timeline.v1";
pub const PHONE_TIMELINE_SCHEMA_V1: &str = "listen.payload.phone-timeline.v1";
pub const SENSE_GROUP_ANALYSIS_SCHEMA_V1: &str = "listen.payload.sense-group-analysis.v1";
pub const WORD_ACOUSTICS_SCHEMA_V1: &str = "listen.payload.word-acoustics.v1";
pub const PROSODY_ANALYSIS_SCHEMA_V1: &str = "listen.payload.prosody-analysis.v1";

/// Media rendition descriptor schema identifiers (v2 release entries only).
pub const RENDITION_AUDIO_SCHEMA_V1: &str = "listen.rendition.audio.v1";
pub const RENDITION_VIDEO_SCHEMA_V1: &str = "listen.rendition.video.v1";

pub const BLOB_DIRECTORY: &str = "blobs";
pub const BLOB_HASH_ALGORITHM_DIRECTORY: &str = "sha256";

/// Release identity document. Its canonical serialization is the release
/// identity; the document itself never contains its own id.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackageRelease {
    pub schema: String,
    pub created_at_ms: u64,
    pub edition: EditionIdentity,
    pub material: MaterialIdentity,
    pub entrypoints: Vec<Entrypoint>,
    /// May be empty when a Media Rendition is the material entrypoint.
    pub resources: Vec<ReleaseResource>,
    #[serde(default)]
    pub renditions: Vec<ReleaseRendition>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// Edition identity. `target_language` and `support_languages` are explicit
/// BCP47-shaped tags; there is never a default language. `support_languages`
/// is required by release.schema.json and must be present in the JSON.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EditionIdentity {
    pub edition_id: String,
    pub title: String,
    pub target_language: String,
    pub support_languages: Vec<String>,
}

/// Material identity. `material_id`, `material_revision_id`, and `edition_id`
/// are nonempty stable strings, not forced SHA-256 digests.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MaterialIdentity {
    pub material_id: String,
    pub material_revision_id: String,
    pub title: String,
}

/// A material entrypoint references a declared Base Resource or Media
/// Rendition (normative rule 8).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Entrypoint {
    pub entrypoint_id: String,
    #[serde(default)]
    pub resource_id: Option<String>,
    #[serde(default)]
    pub rendition_id: Option<String>,
}

/// A release resource entry. `required` is release policy and lives beside the
/// descriptor so that one shared descriptor identity can be required by one
/// edition and optional in another without changing resource identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReleaseResource {
    pub resource_id: String,
    pub required: bool,
    pub descriptor: ResourceDescriptor,
}

/// Resource descriptor. `resource_id` is the SHA-256 of this descriptor's
/// canonical JSON; the descriptor therefore fully determines resource identity
/// (including the payload blob it references). `schema` is the payload schema
/// identifier and `kind` the resource kind.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceDescriptor {
    pub schema: String,
    pub kind: String,
    pub role: ResourceRole,
    #[serde(default)]
    pub content_language: Option<String>,
    #[serde(default)]
    pub support_languages: Vec<String>,
    pub subject: ResourceSubject,
    #[serde(default)]
    pub dependencies: Vec<ResourceDependency>,
    pub provenance: Provenance,
    pub quality: Quality,
    pub payload_blob: BlobDescriptor,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceRole {
    Base,
    Assistance,
}

impl ResourceRole {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Base => "base",
            Self::Assistance => "assistance",
        }
    }
}

/// Resource subject. Always binds the exact `material_revision_id` of the
/// release and may explicitly bind declared rendition ids and anchor
/// resource ids; every reference is validated. `material_revision_id` is
/// mandatory: a subject is never default-constructible.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceSubject {
    pub material_revision_id: String,
    #[serde(default)]
    pub rendition_ids: Vec<String>,
    #[serde(default)]
    pub anchor_resource_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceDependency {
    pub resource_id: String,
}

/// Strict, identity-bearing provenance. `created_at_ms`, `tool`,
/// `input_resource_ids`, and `extensions` are mandatory; `provider`, `model`,
/// and `config_sha256` are optional. `input_resource_ids` are
/// production-lineage edges (distinct from runtime dependencies) that must
/// reference exact declared resource ids in the release. Raw provider output,
/// local paths, credentials, and floating confidence never appear here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Provenance {
    pub created_at_ms: u64,
    pub tool: VersionedProducer,
    #[serde(default)]
    pub provider: Option<VersionedProducer>,
    #[serde(default)]
    pub model: Option<VersionedProducer>,
    #[serde(default)]
    pub config_sha256: Option<String>,
    pub input_resource_ids: Vec<String>,
    pub extensions: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VersionedProducer {
    pub id: String,
    pub version: String,
}

/// Immutable quality facts attached to every resource. `review_status`,
/// `warnings`, and `extensions` are all mandatory.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Quality {
    pub review_status: ReviewStatus,
    pub warnings: Vec<String>,
    pub extensions: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReviewStatus {
    Unreviewed,
    MachineChecked,
    HumanReviewed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReleaseRendition {
    pub rendition_id: String,
    pub descriptor: RenditionDescriptor,
}

/// Media rendition descriptor. Binds the exact release `material_revision_id`,
/// ties audio/video schema to kind, and validates the media_type family. Its
/// raw media bytes are a blob that may be absent from the carrier.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RenditionDescriptor {
    pub schema: String,
    pub kind: String,
    pub media_type: String,
    pub material_revision_id: String,
    pub media_blob: BlobDescriptor,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// Content-addressed blob reference: `digest` is `sha256:<hex>` of the raw
/// bytes and `size_bytes` their length (>= 1). Embedded bytes live at
/// `blobs/sha256/<hex>`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BlobDescriptor {
    pub digest: String,
    pub size_bytes: u64,
}

impl BlobDescriptor {
    /// The fixed embedded blob path `blobs/sha256/<lowercase hex>`.
    pub fn embedded_path(&self) -> Option<String> {
        Some(format!(
            "{BLOB_DIRECTORY}/{BLOB_HASH_ALGORITHM_DIRECTORY}/{}",
            self.digest.strip_prefix("sha256:")?
        ))
    }
}

/// Optional delivery document. Canonical; binds the computed release id and
/// may carry untrusted HTTPS acquisition hints by blob digest. Inspection
/// never fetches the hints.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeliveryDocument {
    pub schema: String,
    pub release_id: String,
    pub profile: DeliveryProfile,
    #[serde(default)]
    pub blobs: Vec<DeliveryBlob>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeliveryBlob {
    pub digest: String,
    pub size_bytes: u64,
    #[serde(default)]
    pub hints: Vec<DeliveryHint>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeliveryHint {
    pub url: String,
}

/// Derived delivery classification of a carrier.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DeliveryProfile {
    /// Every referenced blob is present in the carrier.
    Embedded,
    /// No referenced blob is present in the carrier.
    Referenced,
    /// Some referenced blobs are present and some are absent.
    Hybrid,
}

impl DeliveryProfile {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Embedded => "embedded",
            Self::Referenced => "referenced",
            Self::Hybrid => "hybrid",
        }
    }
}
