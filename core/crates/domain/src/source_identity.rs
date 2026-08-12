//! Source Identity (Phase 1 contract 4.0.0).
//!
//! Discovered items are keyed by a source-scoped canonical identity: the
//! Content Source plus the item identity within it. Feed GUIDs, URLs,
//! enclosure URLs, file hashes, and titles are typed evidence fields — they
//! never silently substitute for one another and never replace the canonical
//! key. Subscription, discovery, acquisition, retention, installation, and
//! adoption remain distinct facts even when one learner action coordinates
//! them.

use serde::{Deserialize, Serialize};

use crate::{DomainError, LearningMaterialId, MaterialRevisionId};

/// Canonical key of a Content Source (e.g. one RSS/Atom feed). The exact
/// canonicalization of a feed identity is a source-adapter fact; Core stores
/// and resolves the key.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ContentSourceId(String);

impl ContentSourceId {
    pub fn parse(value: impl Into<String>) -> Result<Self, DomainError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(DomainError::EmptyValue("ContentSourceId"));
        }
        Ok(Self(value))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Canonical identity of one item inside a Content Source. The item identity
/// is the authoritative match key: re-reading, feed reordering, or metadata
/// changes resolve the same item when this key matches.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct SourceItemId(String);

impl SourceItemId {
    pub fn parse(value: impl Into<String>) -> Result<Self, DomainError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(DomainError::EmptyValue("SourceItemId"));
        }
        Ok(Self(value))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// The canonical identity of one discovered item: source plus item.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct SourceItemIdentity {
    pub source_id: ContentSourceId,
    pub item_id: SourceItemId,
}

/// Typed evidence fields of a discovered item. These are evidence, never
/// interchangeable identity kinds; the canonical key above is the only
/// identity Core matches on.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceItemEvidence {
    /// The feed-declared GUID or Atom id, when present.
    pub feed_item_id: Option<String>,
    /// The item's canonical entry URL, when present.
    pub entry_url: Option<String>,
    /// Authorized enclosure URLs, when present.
    pub enclosure_urls: Vec<String>,
    /// Byte fingerprint of the acquired source, when known.
    pub file_sha256: Option<String>,
    pub title: Option<String>,
}

/// A durable mapping of one discovered item to one Material Revision. Only an
/// explicit acquisition/retention journey records a mapping; discovery alone
/// never maps.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourceIdentityMapping {
    pub source_item: SourceItemIdentity,
    /// The evidence captured when the mapping was recorded.
    pub evidence: SourceItemEvidence,
    pub material_id: LearningMaterialId,
    pub material_revision_id: MaterialRevisionId,
    pub mapped_at_ms: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_identity_is_source_scoped() {
        let source =
            ContentSourceId::parse("rss:https://example.com/feed.xml").expect("valid source");
        let item = SourceItemId::parse("tag:example.com,2026:entry-1").expect("valid item");
        let a = SourceItemIdentity {
            source_id: source.clone(),
            item_id: item.clone(),
        };
        let b = SourceItemIdentity {
            source_id: source.clone(),
            item_id: item.clone(),
        };
        assert_eq!(a, b);
        // The same item id under a different source is a different identity.
        let other_source = SourceItemIdentity {
            source_id: ContentSourceId::parse("rss:https://other.example.com/feed.xml")
                .expect("valid source"),
            item_id: item,
        };
        assert_ne!(a, other_source);
        // Evidence fields never substitute for the canonical key: equal
        // evidence under a different key is a different identity.
        let mapping = |source_id: &str| SourceIdentityMapping {
            source_item: SourceItemIdentity {
                source_id: ContentSourceId::parse(source_id).expect("valid source"),
                item_id: SourceItemId::parse("item-1").expect("valid item"),
            },
            evidence: SourceItemEvidence {
                feed_item_id: Some("same-guid".into()),
                entry_url: Some("https://example.com/entry".into()),
                enclosure_urls: vec!["https://example.com/media.mp3".into()],
                file_sha256: Some("abcd".into()),
                title: Some("Same Title".into()),
            },
            material_id: LearningMaterialId::parse("material-1").expect("valid material id"),
            material_revision_id: MaterialRevisionId::parse("revision-1")
                .expect("valid revision id"),
            mapped_at_ms: 1,
        };
        assert_ne!(mapping("rss:a"), mapping("rss:b"));
        // Source item identities refuse empty keys.
        assert_eq!(
            ContentSourceId::parse("   "),
            Err(DomainError::EmptyValue("ContentSourceId"))
        );
        assert_eq!(
            SourceItemId::parse(""),
            Err(DomainError::EmptyValue("SourceItemId"))
        );
    }
}
