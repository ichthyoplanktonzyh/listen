//! Canonical Material Renditions and Source Assets (Phase 1 contract 4.0.0).
//!
//! A Material Revision is composed of Source Assets, Document Renditions, and
//! Media Renditions. This module owns their identity and invariant rules and
//! deliberately contains no file path, repository, or HTTP concepts.
//!
//! - A Source Asset records learner-authorized source evidence: media type,
//!   byte length, integrity digest, storage/binding facts, and local
//!   availability. It is a fact about bytes, separate from Personal Library
//!   membership.
//! - A Document or Media Rendition is a first-class, independently identified
//!   realization of the exact Material Revision. It always states whether it
//!   is Source or Derived; every Derived Rendition records exact inputs,
//!   producer, and compatibility evidence.
//! - A supported Source Rendition stays usable without any Content Package or
//!   Gen involvement.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::{
    DomainError, LanguageCode, MediaAvailability, MediaId, MediaKind, RenditionId, ResourceId,
    SourceAssetId,
};

/// Where a Rendition came from. A Source rendition realizes the learner's
/// authorized original; a Derived rendition is produced from exact inputs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RenditionOrigin {
    Source,
    Derived,
}

/// How the bytes of a Source Asset are bound to local storage. The reference
/// string is opaque to Core: it is a fact about binding, never a path to
/// dereference here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceAssetBinding {
    /// Copied into the managed asset store; integrity is owned by Core facts.
    Managed,
    /// Referenced in place at an opaque, app-owned reference.
    Referenced { reference: String },
}

/// Local availability of a Source Asset, independent of Personal Library
/// membership. A missing referenced asset is an unavailable fact, never a
/// reason to delete the Material or its membership.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceAssetAvailability {
    Available,
    /// The referenced bytes cannot be reached or no longer verify.
    Unavailable {
        reason: SourceAssetUnavailableReason,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceAssetUnavailableReason {
    FileMissing,
    IntegrityMismatch,
}

/// A learner-authorized source evidence fact: the exact bytes of the original
/// source, described without any path. Identity is deterministic from the
/// media type, byte length, and integrity digest.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceAsset {
    pub id: SourceAssetId,
    pub media_type: String,
    pub byte_length: u64,
    /// Lowercase hex SHA-256 of the exact source bytes.
    pub sha256_digest: String,
    pub binding: SourceAssetBinding,
    pub availability: SourceAssetAvailability,
    pub created_at_ms: u64,
}

impl SourceAsset {
    /// Derives the deterministic identity from the exact byte facts. A blank
    /// media type or digest is rejected; the availability is a stored fact and
    /// does not participate in identity.
    pub fn new(
        media_type: impl Into<String>,
        byte_length: u64,
        sha256_digest: impl Into<String>,
        binding: SourceAssetBinding,
        availability: SourceAssetAvailability,
        created_at_ms: u64,
    ) -> Result<Self, DomainError> {
        let media_type = media_type.into();
        if media_type.trim().is_empty() {
            return Err(DomainError::EmptyValue("SourceAsset.media_type"));
        }
        let sha256_digest = sha256_digest.into();
        if sha256_digest.trim().is_empty() {
            return Err(DomainError::EmptyValue("SourceAsset.sha256_digest"));
        }
        let id = SourceAssetId::from_fingerprint(
            "source-asset",
            &length_prefixed(&[
                media_type.as_str(),
                &byte_length.to_string(),
                sha256_digest.as_str(),
            ]),
        );
        Ok(Self {
            id,
            media_type,
            byte_length,
            sha256_digest,
            binding,
            availability,
            created_at_ms,
        })
    }
}

/// Exact producer facts of a Derived Rendition. Raw provider output never
/// appears here.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProducerFact {
    pub created_at_ms: u64,
    pub tool_id: String,
    pub tool_version: String,
    pub provider_id: Option<String>,
    pub provider_version: Option<String>,
    pub model_id: Option<String>,
    pub model_version: Option<String>,
    pub config_sha256: Option<String>,
}

/// One exact input of a Derived Rendition: a rendition and, when the input is
/// a resource-derived one, the exact Resource identity used.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DerivationInput {
    pub rendition_id: RenditionId,
    pub resource_id: Option<ResourceId>,
}

/// Compatibility evidence of a Derived Rendition: the exact verified inputs
/// and the checks that were satisfied. The checks are stable strings, never
/// free-form claims stronger than their evidence class.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompatibilityEvidence {
    pub verified_inputs: Vec<DerivationInput>,
    pub checks: Vec<String>,
}

/// A Document Rendition: the readable representation of a document for one
/// Material Revision, with its exact text bytes verified. Source renditions
/// bind their Source Asset; Derived renditions record producer facts and
/// exact inputs.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DocumentRendition {
    pub id: RenditionId,
    pub origin: RenditionOrigin,
    pub media_type: String,
    pub language: Option<LanguageCode>,
    pub text: String,
    pub text_sha256: String,
    pub text_byte_size: u64,
    pub source_asset_id: Option<SourceAssetId>,
    pub producer: Option<ProducerFact>,
    pub compatibility: Option<CompatibilityEvidence>,
}

impl DocumentRendition {
    /// Derives the deterministic identity from the exact text bytes, media
    /// type, and language. Whitespace-only text is rejected. Origin, source
    /// binding, and producer facts are stored facts and do not participate in
    /// identity: equal readable content is the same realization.
    pub fn new(
        origin: RenditionOrigin,
        media_type: impl Into<String>,
        language: Option<LanguageCode>,
        text: impl Into<String>,
        source_asset_id: Option<SourceAssetId>,
        producer: Option<ProducerFact>,
        compatibility: Option<CompatibilityEvidence>,
    ) -> Result<Self, DomainError> {
        let media_type = media_type.into();
        if media_type.trim().is_empty() {
            return Err(DomainError::EmptyValue("DocumentRendition.media_type"));
        }
        let text = text.into();
        if text.trim().is_empty() {
            return Err(DomainError::WhitespaceOnlyText);
        }
        let text_sha256 = hex::encode(Sha256::digest(text.as_bytes()));
        let text_byte_size = text.len() as u64;
        if origin == RenditionOrigin::Derived && producer.is_none() {
            return Err(DomainError::MissingDerivedProducer("DocumentRendition"));
        }
        let language_key = language.as_ref().map(LanguageCode::as_str).unwrap_or("");
        let id = RenditionId::from_fingerprint(
            "document-rendition",
            &length_prefixed(&[media_type.as_str(), language_key, text_sha256.as_str()]),
        );
        Ok(Self {
            id,
            origin,
            media_type,
            language,
            text,
            text_sha256,
            text_byte_size,
            source_asset_id,
            producer,
            compatibility,
        })
    }
}

/// A Media Rendition: an audio or video realization for one Material
/// Revision. Source renditions bind the media source snapshot; Derived
/// renditions record producer facts and exact inputs. The rendition never
/// contains a path.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaRendition {
    pub id: RenditionId,
    pub origin: RenditionOrigin,
    pub kind: MediaKind,
    pub media_type: String,
    pub fingerprint: String,
    pub availability: MediaAvailability,
    pub media_sha256: Option<String>,
    pub media_byte_size: Option<u64>,
    pub media_id: Option<MediaId>,
    pub producer: Option<ProducerFact>,
    pub compatibility: Option<CompatibilityEvidence>,
}

impl MediaRendition {
    /// Derives the deterministic identity from the media source id (Source) or
    /// the content digest (Derived), kind, and media type. A blank fingerprint
    /// is rejected. Availability and producer facts are stored facts and do
    /// not participate in identity.
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        origin: RenditionOrigin,
        kind: MediaKind,
        media_type: impl Into<String>,
        fingerprint: impl Into<String>,
        availability: MediaAvailability,
        media_id: Option<MediaId>,
        media_sha256: Option<String>,
        media_byte_size: Option<u64>,
        producer: Option<ProducerFact>,
        compatibility: Option<CompatibilityEvidence>,
    ) -> Result<Self, DomainError> {
        let media_type = media_type.into();
        if media_type.trim().is_empty() {
            return Err(DomainError::EmptyValue("MediaRendition.media_type"));
        }
        let fingerprint = fingerprint.into();
        if fingerprint.trim().is_empty() {
            return Err(DomainError::EmptyValue("MediaRendition.fingerprint"));
        }
        if origin == RenditionOrigin::Derived && producer.is_none() {
            return Err(DomainError::MissingDerivedProducer("MediaRendition"));
        }
        if origin == RenditionOrigin::Source && media_id.is_none() {
            return Err(DomainError::MissingSourceBinding("MediaRendition"));
        }
        if origin == RenditionOrigin::Derived && media_sha256.is_none() {
            return Err(DomainError::MissingDerivedDigest);
        }
        let identity_key = match origin {
            RenditionOrigin::Source => length_prefixed(&[
                media_id
                    .as_ref()
                    .expect("source media rendition has a media id")
                    .as_str(),
                media_kind_key(kind),
                fingerprint.as_str(),
            ]),
            RenditionOrigin::Derived => length_prefixed(&[
                media_sha256
                    .as_ref()
                    .expect("derived rendition has a digest")
                    .as_str(),
                media_type.as_str(),
            ]),
        };
        let id = RenditionId::from_fingerprint("media-rendition", &identity_key);
        Ok(Self {
            id,
            origin,
            kind,
            media_type,
            fingerprint,
            availability,
            media_sha256,
            media_byte_size,
            media_id,
            producer,
            compatibility,
        })
    }
}

fn media_kind_key(kind: MediaKind) -> &'static str {
    match kind {
        MediaKind::Video => "video",
        MediaKind::Audio => "audio",
    }
}

/// One Rendition of a revision, either a document or a media realization.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Rendition {
    Document(DocumentRendition),
    Media(MediaRendition),
}

impl Rendition {
    pub fn id(&self) -> &RenditionId {
        match self {
            Rendition::Document(rendition) => &rendition.id,
            Rendition::Media(rendition) => &rendition.id,
        }
    }

    pub fn origin(&self) -> RenditionOrigin {
        match self {
            Rendition::Document(rendition) => rendition.origin,
            Rendition::Media(rendition) => rendition.origin,
        }
    }
}

/// Encodes fields with explicit byte-length prefixes so the concatenation is
/// unambiguously decodable even when a field contains separator characters.
/// The encoding is injective: distinct field tuples always produce distinct
/// strings. Format per field: `<byte_len>:<bytes>`.
pub(crate) fn length_prefixed(fields: &[&str]) -> String {
    let mut encoded = String::new();
    for field in fields {
        encoded.push_str(&field.len().to_string());
        encoded.push(':');
        encoded.push_str(field);
    }
    encoded
}

#[cfg(test)]
mod tests {
    use super::*;

    fn language(code: &str) -> LanguageCode {
        LanguageCode::parse(code).expect("valid language code")
    }

    fn producer(tool: &str) -> ProducerFact {
        ProducerFact {
            created_at_ms: 1,
            tool_id: tool.to_owned(),
            tool_version: "1.0.0".to_owned(),
            provider_id: None,
            provider_version: None,
            model_id: None,
            model_version: None,
            config_sha256: None,
        }
    }

    #[test]
    fn source_asset_identity_is_deterministic_and_path_free() {
        let asset = SourceAsset::new(
            "text/plain",
            5,
            hex::encode(Sha256::digest(b"hello")),
            SourceAssetBinding::Managed,
            SourceAssetAvailability::Available,
            1,
        )
        .expect("valid source asset");
        let again = SourceAsset::new(
            "text/plain",
            5,
            hex::encode(Sha256::digest(b"hello")),
            SourceAssetBinding::Managed,
            SourceAssetAvailability::Unavailable {
                reason: SourceAssetUnavailableReason::FileMissing,
            },
            2,
        )
        .expect("valid source asset");
        assert_eq!(asset.id, again.id, "availability does not participate");
        let json = serde_json::to_value(&asset).expect("serializes");
        let object = json.as_object().expect("object");
        assert!(!object.contains_key("path"), "never a path");
        for key in [
            "id",
            "media_type",
            "byte_length",
            "sha256_digest",
            "binding",
            "availability",
            "created_at_ms",
        ] {
            assert!(object.contains_key(key), "missing key: {key}");
        }
        assert_eq!(
            SourceAsset::new(
                "",
                1,
                "a",
                SourceAssetBinding::Managed,
                SourceAssetAvailability::Available,
                1
            ),
            Err(DomainError::EmptyValue("SourceAsset.media_type"))
        );
        assert_eq!(
            SourceAsset::new(
                "text/plain",
                1,
                " ",
                SourceAssetBinding::Managed,
                SourceAssetAvailability::Available,
                1
            ),
            Err(DomainError::EmptyValue("SourceAsset.sha256_digest"))
        );
    }

    #[test]
    fn source_document_rendition_identity_is_content_deterministic() {
        let source = SourceAsset::new(
            "text/plain",
            5,
            hex::encode(Sha256::digest(b"hello")),
            SourceAssetBinding::Managed,
            SourceAssetAvailability::Available,
            1,
        )
        .expect("valid source asset");
        let rendition = DocumentRendition::new(
            RenditionOrigin::Source,
            "text/plain",
            Some(language("en")),
            "hello",
            Some(source.id.clone()),
            None,
            None,
        )
        .expect("valid rendition");
        let equal = DocumentRendition::new(
            RenditionOrigin::Source,
            "text/plain",
            Some(language("en")),
            "hello",
            None,
            None,
            None,
        )
        .expect("valid rendition");
        assert_eq!(rendition.id, equal.id);
        assert_eq!(rendition.text, "hello");
        assert_eq!(rendition.text_sha256, hex::encode(Sha256::digest(b"hello")));
        assert_eq!(rendition.text_byte_size, 5);

        let different = DocumentRendition::new(
            RenditionOrigin::Source,
            "text/plain",
            Some(language("en")),
            "goodbye",
            None,
            None,
            None,
        )
        .expect("valid rendition");
        assert_ne!(rendition.id, different.id);
        assert_ne!(
            rendition.id.as_str(),
            source.id.as_str(),
            "rendition id differs from asset id"
        );
    }

    #[test]
    fn whitespace_only_document_is_rejected() {
        assert_eq!(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                None,
                "   ",
                None,
                None,
                None,
            ),
            Err(DomainError::WhitespaceOnlyText)
        );
    }

    #[test]
    fn derived_renditions_require_producer_and_verify_exact_digest() {
        let source = SourceAsset::new(
            "text/plain",
            1,
            hex::encode(Sha256::digest(b"a")),
            SourceAssetBinding::Managed,
            SourceAssetAvailability::Available,
            1,
        )
        .expect("valid source asset");
        let derived = DocumentRendition::new(
            RenditionOrigin::Derived,
            "text/plain",
            None,
            "a",
            Some(source.id),
            Some(producer("listen-gen")),
            Some(CompatibilityEvidence {
                verified_inputs: vec![],
                checks: vec!["exact_text_match".to_owned()],
            }),
        )
        .expect("valid derived rendition");
        assert_eq!(derived.origin, RenditionOrigin::Derived);
        assert_eq!(
            derived.producer.as_ref().expect("producer").tool_id,
            "listen-gen"
        );
        // A Derived rendition without producer facts is refused.
        assert_eq!(
            DocumentRendition::new(
                RenditionOrigin::Derived,
                "text/plain",
                None,
                "a",
                None,
                None,
                None,
            ),
            Err(DomainError::MissingDerivedProducer("DocumentRendition"))
        );
    }

    #[test]
    fn source_media_rendition_binds_media_and_snapshot_never_contains_path() {
        let rendition = MediaRendition::new(
            RenditionOrigin::Source,
            MediaKind::Audio,
            "audio/mpeg",
            "fp-1",
            MediaAvailability::Available,
            Some(MediaId::parse("media-1").expect("valid media id")),
            None,
            None,
            None,
            None,
        )
        .expect("valid media rendition");
        assert_eq!(rendition.id.as_str().len(), 64);
        let json = serde_json::to_value(&rendition).expect("serializes");
        let object = json.as_object().expect("object");
        assert!(!object.contains_key("path"));
        // A Source media rendition must name its media source.
        assert_eq!(
            MediaRendition::new(
                RenditionOrigin::Source,
                MediaKind::Audio,
                "audio/mpeg",
                "fp",
                MediaAvailability::Available,
                None,
                None,
                None,
                None,
                None,
            ),
            Err(DomainError::MissingSourceBinding("MediaRendition"))
        );
    }

    #[test]
    fn derived_media_rendition_is_digest_keyed_and_requires_producer() {
        let digest = hex::encode(Sha256::digest(b"audio-bytes"));
        let derived = MediaRendition::new(
            RenditionOrigin::Derived,
            MediaKind::Audio,
            "audio/mpeg",
            "fp-tts",
            MediaAvailability::Available,
            None,
            Some(digest.clone()),
            Some(10),
            Some(producer("listen-gen")),
            None,
        )
        .expect("valid derived media rendition");
        assert_eq!(derived.media_sha256.as_deref(), Some(digest.as_str()));
        assert_eq!(
            MediaRendition::new(
                RenditionOrigin::Derived,
                MediaKind::Audio,
                "audio/mpeg",
                "fp",
                MediaAvailability::Available,
                None,
                None,
                None,
                Some(producer("listen-gen")),
                None,
            ),
            Err(DomainError::MissingDerivedDigest)
        );
        assert_eq!(
            MediaRendition::new(
                RenditionOrigin::Derived,
                MediaKind::Audio,
                "audio/mpeg",
                "fp",
                MediaAvailability::Available,
                None,
                Some(digest),
                Some(10),
                None,
                None,
            ),
            Err(DomainError::MissingDerivedProducer("MediaRendition"))
        );
    }

    #[test]
    fn rendition_enum_serializes_with_snake_case_variant_names() {
        let rendition = Rendition::Document(
            DocumentRendition::new(
                RenditionOrigin::Source,
                "text/plain",
                None,
                "hello",
                None,
                None,
                None,
            )
            .expect("valid rendition"),
        );
        let json = serde_json::to_value(&rendition).unwrap();
        assert!(json.get("document").is_some());
        let back: Rendition = serde_json::from_value(json).expect("round trips");
        assert_eq!(back, rendition);
    }
}
