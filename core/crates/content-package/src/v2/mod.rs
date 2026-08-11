//! Content Package v2: an explicit v2 interface beside the unchanged v1.
//!
//! Public surface:
//! - `inspect_v2_path` / `inspect_v2_path_with_limits`
//! - `installation_plan` (pure; no persistence or activation)
//! - `serialize_canonical` (pure canonical JSON helper for identities/fixtures)

mod canonical;
mod inspect;
mod model;
mod payload;
mod plan;
mod validate;

#[cfg(test)]
mod tests;

pub use canonical::{CanonicalError, serialize_canonical};
pub use inspect::{
    BlobRecord, MissingBlob, OpaqueResourceRecord, RenditionRecord, ResourceRecord, V2Error,
    V2Inspection, inspect_v2_path, inspect_v2_path_with_limits,
};
pub use model::{
    BLOB_DIRECTORY, BLOB_HASH_ALGORITHM_DIRECTORY, BlobDescriptor, DELIVERY_SCHEMA_V2,
    DOCUMENT_TEXT_SCHEMA_V1, DeliveryBlob, DeliveryDocument, DeliveryHint, DeliveryProfile,
    EditionIdentity, Entrypoint, MaterialIdentity, PHONE_TIMELINE_SCHEMA_V1, PLAN_SCHEMA_V2,
    PROSODY_ANALYSIS_SCHEMA_V1, PackageRelease, Provenance, Quality, RELEASE_SCHEMA_V2,
    RENDITION_AUDIO_SCHEMA_V1, RENDITION_VIDEO_SCHEMA_V1, ReleaseRendition, ReleaseResource,
    RenditionDescriptor, ResourceDependency, ResourceDescriptor, ResourceRole, ResourceSubject,
    ReviewStatus, SENSE_GROUP_ANALYSIS_SCHEMA_V1, SUBTITLE_TEXT_TRACK_SCHEMA_V1,
    TIMED_TEXT_TRACK_SCHEMA_V2, TRANSLATION_SCHEMA_V1, VersionedProducer, WORD_ACOUSTICS_SCHEMA_V1,
    WORD_TIMELINE_SCHEMA_V1,
};
pub use payload::{
    DocumentText, DocumentTextSegment, KnownPayload, TimedTextSegment, TimedTextTrack, Translation,
    TranslationSegment,
};
pub use plan::{
    InstallationPlan, PlanMissingBlob, PlanRendition, PlanResource, ResourceDisposition,
    installation_plan,
};
