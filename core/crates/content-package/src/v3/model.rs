//! Content Package v3 contract models.
//!
//! A v3 carrier holds one immutable Package Release: a canonical
//! `release.json` and content-addressed blobs under `blobs/sha256/<hex>`.
//! Unlike v2 there is no delivery.json: every blob is explicitly declared
//! either `embedded` (must be present in the carrier) or `referenced` (may be
//! absent and acquired later). Renditions are first-class entries that state
//! whether they are Source or Derived; a Derived rendition always records
//! exact producer facts and compatibility evidence. Resource and rendition
//! descriptors are embedded in `release.json`; their identities are the
//! SHA-256 of the descriptor's canonical JSON.
//!
//! v3 deliberately reuses the shared v2 identity, quality, role, producer,
//! and blob vocabulary so one canonical set of meanings stays stable across
//! package schema versions.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::v2::model::{
    BLOB_DIRECTORY, BLOB_HASH_ALGORITHM_DIRECTORY, EditionIdentity, MaterialIdentity, Provenance,
    Quality, ResourceDependency, ResourceRole, VersionedProducer,
};

pub const RELEASE_SCHEMA_V3: &str = "listen.content-package.release.v3";
pub const PLAN_SCHEMA_V3: &str = "listen.content-package.plan.v3";

/// Payload schema identifiers introduced by v3, beside the shared v2 payload
/// families (`listen.payload.document-text.v1`, `listen.payload.timed-text
/// -track.v2`, `listen.payload.translation.v1`, and the six generated v1
/// resource families) that v3 reuses verbatim.
pub const STRUCTURED_READING_SCHEMA_V1: &str = "listen.payload.structured-reading.v1";
pub const ANCHOR_TIME_ALIGNMENT_SCHEMA_V1: &str = "listen.payload.anchor-time-alignment.v1";

/// Where a declared Rendition came from. A Source rendition realizes the
/// learner's authorized original bytes; a Derived rendition is produced from
/// exact inputs and must record producer and compatibility evidence.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RenditionOrigin {
    Source,
    Derived,
}

impl RenditionOrigin {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Source => "source",
            Self::Derived => "derived",
        }
    }
}

/// The release identity document. Its canonical serialization is the release
/// identity; the document itself never contains its own id.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PackageReleaseV3 {
    pub schema: String,
    pub created_at_ms: u64,
    pub edition: EditionIdentity,
    pub material: MaterialIdentity,
    #[serde(default)]
    pub document_renditions: Vec<DocumentRenditionDeclaration>,
    #[serde(default)]
    pub media_renditions: Vec<MediaRenditionDeclaration>,
    /// May be empty when a Media Rendition is the material entrypoint.
    #[serde(default)]
    pub resources: Vec<ReleaseResourceV3>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// One Document Rendition declaration: the readable representation of the
/// exact Material Revision. The rendition identity is the SHA-256 of the
/// canonical `{media_type, language, text_blob}` descriptor; origin, source
/// binding, producer, and compatibility are facts that do not participate in
/// identity, so equal readable content is the same realization.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DocumentRenditionDeclaration {
    pub rendition_id: String,
    pub origin: RenditionOrigin,
    pub media_type: String,
    #[serde(default)]
    pub language: Option<String>,
    pub text_blob: BlobDeclaration,
    /// The declared Source Asset binding for a Source rendition.
    #[serde(default)]
    pub source_asset_id: Option<String>,
    #[serde(default)]
    pub producer: Option<ProducerDeclaration>,
    #[serde(default)]
    pub compatibility: Option<CompatibilityDeclaration>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// One Media Rendition declaration: an audio or video realization for the
/// exact Material Revision. The rendition identity is the SHA-256 of the
/// canonical `{kind, media_type, media_blob, media_id, fingerprint}`
/// descriptor; origin and producer facts do not participate in identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MediaRenditionDeclaration {
    pub rendition_id: String,
    pub origin: RenditionOrigin,
    pub kind: String,
    pub media_type: String,
    pub media_blob: BlobDeclaration,
    /// The bound media source identity for a Source rendition.
    #[serde(default)]
    pub media_id: Option<String>,
    pub fingerprint: String,
    #[serde(default)]
    pub producer: Option<ProducerDeclaration>,
    #[serde(default)]
    pub compatibility: Option<CompatibilityDeclaration>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// A release resource entry. `required` is release policy and lives beside
/// the descriptor so that one shared descriptor identity can be required by
/// one edition and optional in another without changing resource identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReleaseResourceV3 {
    pub resource_id: String,
    pub required: bool,
    pub descriptor: ResourceDescriptorV3,
}

/// Resource descriptor. `resource_id` is the SHA-256 of this descriptor's
/// canonical JSON; the descriptor therefore fully determines resource identity
/// (including the payload blob it references). `schema` is the payload schema
/// identifier and `kind` the resource kind.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceDescriptorV3 {
    pub schema: String,
    pub kind: String,
    pub role: ResourceRole,
    #[serde(default)]
    pub content_language: Option<String>,
    #[serde(default)]
    pub support_languages: Vec<String>,
    pub subject: SubjectDeclaration,
    #[serde(default)]
    pub dependencies: Vec<ResourceDependency>,
    pub provenance: Provenance,
    pub quality: Quality,
    #[serde(default)]
    pub producer: Option<ProducerDeclaration>,
    #[serde(default)]
    pub compatibility: Option<CompatibilityDeclaration>,
    pub payload_blob: BlobDeclaration,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// Resource subject. Always binds the exact `material_revision_id` of the
/// release and may explicitly bind declared rendition ids and anchor
/// resource ids; every reference is validated.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SubjectDeclaration {
    pub material_revision_id: String,
    #[serde(default)]
    pub rendition_ids: Vec<String>,
    #[serde(default)]
    pub anchor_resource_ids: Vec<String>,
}

/// Strict, identity-bearing producer facts of a Derived Rendition or an
/// optional resource producer. `tool` is mandatory; `provider`, `model`, and
/// `config_sha256` are optional. Raw provider output, local paths,
/// credentials, and floating confidence never appear here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProducerDeclaration {
    pub created_at_ms: u64,
    pub tool: VersionedProducer,
    #[serde(default)]
    pub provider: Option<VersionedProducer>,
    #[serde(default)]
    pub model: Option<VersionedProducer>,
    #[serde(default)]
    pub config_sha256: Option<String>,
}

/// Compatibility evidence of a Derived Rendition: the exact verified inputs
/// and the checks that were satisfied. Every input reference is validated
/// against the declared renditions and resources of the release.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CompatibilityDeclaration {
    pub verified_inputs: Vec<CompatibilityInput>,
    pub checks: Vec<String>,
}

/// One exact input of a Derived Rendition: a declared rendition and, when the
/// input is a resource-derived one, the exact declared Resource identity used.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CompatibilityInput {
    pub rendition_id: String,
    #[serde(default)]
    pub resource_id: Option<String>,
}

/// Content-addressed blob declaration: `digest` is `sha256:<hex>` of the raw
/// bytes and `size_bytes` their length (>= 1). `embedded` is a carrier
/// contract: an embedded blob must be present at `blobs/sha256/<hex>`, while
/// a referenced blob may be absent and acquired later.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BlobDeclaration {
    pub digest: String,
    pub size_bytes: u64,
    pub embedded: bool,
}

impl BlobDeclaration {
    /// The fixed embedded blob path `blobs/sha256/<lowercase hex>`.
    pub fn embedded_path(&self) -> Option<String> {
        Some(format!(
            "{BLOB_DIRECTORY}/{BLOB_HASH_ALGORITHM_DIRECTORY}/{}",
            self.digest.strip_prefix("sha256:")?
        ))
    }
}
