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
