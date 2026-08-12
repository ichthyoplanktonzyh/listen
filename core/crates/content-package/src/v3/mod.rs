//! Content Package v3: the Phase 1 canonical package schema beside the
//! unchanged v2 interface.
//!
//! Public surface:
//! - `inspect_v3_path` / `inspect_v3_path_with_limits`
//! - `installation_plan_v3` (pure; no persistence or activation)
//! - `probe_release_schema` (lightweight schema dispatch for installers)

mod inspect;
mod model;
mod payload;
mod plan;
mod validate;

#[cfg(test)]
mod tests;

use std::path::Path;

use thiserror::Error;

use crate::archive::read_package_controls;
use crate::inspect::InspectLimits;
use crate::v2::RELEASE_SCHEMA_V2;

pub use inspect::{
    BlobRecord, DocumentRenditionRecord, MediaRenditionRecord, MissingBlob, OpaqueResourceRecord,
    ResourceRecord, V3Error, V3Inspection, inspect_v3_path, inspect_v3_path_with_limits,
};
pub use model::{
    ANCHOR_TIME_ALIGNMENT_SCHEMA_V1, BlobDeclaration, CompatibilityDeclaration, CompatibilityInput,
    DocumentRenditionDeclaration, MediaRenditionDeclaration, PLAN_SCHEMA_V3, PackageReleaseV3,
    ProducerDeclaration, RELEASE_SCHEMA_V3, ReleaseResourceV3, RenditionOrigin,
    ResourceDescriptorV3, STRUCTURED_READING_SCHEMA_V1, SubjectDeclaration,
};
pub use payload::{
    AnchorDocumentMapping, AnchorKind, AnchorTimeAlignment, AnchorTimeAlignmentEntry,
    KnownPayloadV3, ReadingAnchor, ReadingBlock, ReadingSpan, StructuredReading,
};
pub use plan::{
    PlanDocumentRendition, PlanMediaRendition, PlanProducer, V3InstallationPlan,
    installation_plan_v3,
};

/// Which package release schema a carrier declares, without running a full
/// inspection. The catalog pass reads only `release.json`; the schema string
/// is matched against the supported identities so an installer can dispatch
/// to the exact inspection before any persistence work.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReleaseSchema {
    V2,
    V3,
}

#[derive(Debug, Error)]
pub enum ProbeError {
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
    #[error("release.json declares an unsupported schema: {0}")]
    UnsupportedSchema(String),
    #[error("invalid package at {path}: {message}")]
    Invalid { path: String, message: String },
}

impl From<crate::archive::ArchiveError> for ProbeError {
    fn from(error: crate::archive::ArchiveError) -> Self {
        match error {
            crate::archive::ArchiveError::Io(source) => Self::Io(source),
            crate::archive::ArchiveError::Zip(source) => Self::Zip(source),
            crate::archive::ArchiveError::Limit(message) => Self::Limit(message),
            crate::archive::ArchiveError::UnsafePath(path) => Self::UnsafePath(path),
            crate::archive::ArchiveError::Symlink(path) => Self::Symlink(path),
            crate::archive::ArchiveError::DuplicatePath(path) => Self::DuplicatePath(path),
            crate::archive::ArchiveError::Invalid { path, message } => {
                Self::Invalid { path, message }
            }
        }
    }
}

/// Reads the declared release schema of a carrier (directory or ZIP) with
/// default limits. Never opens ordinary or text/media bodies.
pub fn probe_release_schema(path: impl AsRef<Path>) -> Result<ReleaseSchema, ProbeError> {
    probe_release_schema_with_limits(path, InspectLimits::default())
}

/// Reads the declared release schema of a carrier with explicit limits.
pub fn probe_release_schema_with_limits(
    path: impl AsRef<Path>,
    limits: InspectLimits,
) -> Result<ReleaseSchema, ProbeError> {
    let catalog = read_package_controls(path.as_ref(), limits, &["release.json"])?;
    let bytes = catalog
        .controls
        .get("release.json")
        .ok_or(ProbeError::MissingRelease)?;
    let value: serde_json::Value =
        serde_json::from_slice(bytes).map_err(ProbeError::ReleaseJson)?;
    let schema = value
        .get("schema")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| ProbeError::UnsupportedSchema("<missing>".to_owned()))?;
    match schema {
        RELEASE_SCHEMA_V2 => Ok(ReleaseSchema::V2),
        RELEASE_SCHEMA_V3 => Ok(ReleaseSchema::V3),
        other => Err(ProbeError::UnsupportedSchema(other.to_owned())),
    }
}
