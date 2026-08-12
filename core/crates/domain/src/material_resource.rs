//! Base and Assistance Resources of a Material Revision (Phase 1 contract
//! 4.0.0).
//!
//! Structured Reading is a Base Resource with stable Reading Anchors: it
//! carries ordered hierarchy, blocks/spans, language metadata, and optional
//! mappings into exact Document Rendition Locators. It is never a Document
//! Rendition, an extracted string cache, renderer state, or a file path.
//! Anchor-to-time alignment is a separate Base Resource mapping exact Reading
//! Anchors to exact media-time Rendition Locators.
//!
//! A Reading Anchor is stable only inside the exact Resource identity; this
//! module never promises cross-resource anchor stability.

use serde::{Deserialize, Serialize};

use crate::{DomainError, LanguageCode, ReadingAnchorId, RenditionId, ResourceId};

/// Role of a Resource within a Learning Edition.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceRole {
    /// The learner-facing base content of the Edition.
    Base,
    /// Assistance content (e.g. translations) for a support language.
    Assistance,
}

/// Kind of a Reading Anchor. Anchors identify stable semantic or temporal
/// positions inside a Structured Reading Resource.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnchorKind {
    Block,
    Span,
    Sentence,
}

/// One stable anchor inside the exact Structured Reading Resource identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadingAnchor {
    pub anchor_id: ReadingAnchorId,
    pub kind: AnchorKind,
    /// First byte offset (UTF-8) of the anchored span in the resource text.
    pub start_offset: u64,
    /// One-past-last byte offset (UTF-8) of the anchored span.
    pub end_offset: u64,
}

/// One hierarchical block of the Structured Reading document structure.
/// Blocks reference spans by their exact anchor identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadingBlock {
    pub block_id: String,
    pub span_anchor_ids: Vec<ReadingAnchorId>,
    pub parent_block_id: Option<String>,
}

/// A text span inside the Structured Reading resource. The exact byte window
/// is anchored; spans never carry duplicated extracted strings.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadingSpan {
    pub span_id: String,
    pub anchor_id: ReadingAnchorId,
    pub parent_anchor_id: Option<ReadingAnchorId>,
}

/// Optional mapping of an anchor to an exact Document Rendition Locator. A
/// locator is meaningful only against the exact rendition identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnchorDocumentMapping {
    pub anchor_id: ReadingAnchorId,
    pub rendition_id: RenditionId,
    /// Opaque locator into the rendition, verified against the rendition
    /// identity only.
    pub locator: String,
}

/// A Structured Reading Resource: ordered hierarchy, blocks/spans, language
/// metadata, stable anchors, and optional mappings into exact Document
/// Rendition Locators.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StructuredReadingResource {
    pub id: ResourceId,
    pub language: LanguageCode,
    pub anchors: Vec<ReadingAnchor>,
    pub blocks: Vec<ReadingBlock>,
    pub spans: Vec<ReadingSpan>,
    pub document_mappings: Vec<AnchorDocumentMapping>,
}

impl StructuredReadingResource {
    /// Validates and builds the resource. The [ResourceId] is the exact
    /// package-declared identity; a Reading Anchor is stable only inside this
    /// identity. Rejects empty anchor sets, duplicate anchor ids, spans/blocks
    /// referencing unknown anchors, block cycles, and mappings referencing
    /// unknown anchors or out-of-range offsets.
    pub fn new(
        id: ResourceId,
        language: LanguageCode,
        anchors: Vec<ReadingAnchor>,
        blocks: Vec<ReadingBlock>,
        spans: Vec<ReadingSpan>,
        document_mappings: Vec<AnchorDocumentMapping>,
    ) -> Result<Self, DomainError> {
        if anchors.is_empty() {
            return Err(DomainError::EmptyValue("StructuredReadingResource.anchors"));
        }
        let mut seen: Vec<&str> = Vec::with_capacity(anchors.len());
        for anchor in &anchors {
            if anchor.end_offset < anchor.start_offset {
                return Err(DomainError::InvalidAnchorRange);
            }
            if seen.contains(&anchor.anchor_id.as_str()) {
                return Err(DomainError::DuplicateAnchor(anchor.anchor_id.clone()));
            }
            seen.push(anchor.anchor_id.as_str());
        }
        let anchor_known = |anchor_id: &ReadingAnchorId| seen.contains(&anchor_id.as_str());
        for span in &spans {
            if !anchor_known(&span.anchor_id) {
                return Err(DomainError::UnknownAnchor(span.anchor_id.clone()));
            }
            if span
                .parent_anchor_id
                .as_ref()
                .is_some_and(|parent| !anchor_known(parent))
            {
                return Err(DomainError::UnknownAnchor(
                    span.parent_anchor_id.clone().expect("checked above"),
                ));
            }
        }
        let block_known = |block_id: &str| blocks.iter().any(|block| block.block_id == block_id);
        for block in &blocks {
            if block.span_anchor_ids.is_empty() {
                return Err(DomainError::EmptyValue("ReadingBlock.span_anchor_ids"));
            }
            for span_anchor in &block.span_anchor_ids {
                if !anchor_known(span_anchor) {
                    return Err(DomainError::UnknownAnchor(span_anchor.clone()));
                }
            }
            if block
                .parent_block_id
                .as_ref()
                .is_some_and(|parent| !block_known(parent))
            {
                return Err(DomainError::UnknownBlock(block.block_id.clone()));
            }
        }
        for mapping in &document_mappings {
            if !anchor_known(&mapping.anchor_id) {
                return Err(DomainError::UnknownAnchor(mapping.anchor_id.clone()));
            }
        }
        if block_cycle_exists(&blocks) {
            return Err(DomainError::BlockCycle);
        }
        Ok(Self {
            id,
            language,
            anchors,
            blocks,
            spans,
            document_mappings,
        })
    }
}

fn block_cycle_exists(blocks: &[ReadingBlock]) -> bool {
    fn reachable(from: &str, blocks: &[ReadingBlock], visited: &mut Vec<String>) -> bool {
        for block in blocks {
            if block.block_id == from {
                if let Some(parent) = &block.parent_block_id {
                    if visited.contains(parent) {
                        return true;
                    }
                    visited.push(parent.clone());
                    if reachable(parent, blocks, visited) {
                        return true;
                    }
                    visited.pop();
                }
            }
        }
        false
    }
    blocks
        .iter()
        .any(|block| reachable(&block.block_id, blocks, &mut vec![block.block_id.clone()]))
}

/// One anchor-to-media-time entry: exact anchor, exact media-time Rendition
/// Locator.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnchorTimeAlignmentEntry {
    pub anchor_id: ReadingAnchorId,
    /// Media time in milliseconds. A derived alignment never fabricates time:
    /// entries are exact or absent.
    pub media_time_ms: u64,
}

/// A Base Resource mapping exact Reading Anchors to exact media-time Rendition
/// Locators. The alignment is meaningful only against the exact Structured
/// Reading Resource and the exact Media Rendition it names.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnchorTimeAlignmentResource {
    pub id: ResourceId,
    pub anchor_resource_id: ResourceId,
    pub rendition_id: RenditionId,
    pub alignments: Vec<AnchorTimeAlignmentEntry>,
}

impl AnchorTimeAlignmentResource {
    /// Validates that every aligned anchor is unique and that the alignment is
    /// monotonic (non-decreasing) in media time. The [ResourceId] is the exact
    /// package-declared identity.
    pub fn new(
        id: ResourceId,
        anchor_resource_id: ResourceId,
        rendition_id: RenditionId,
        alignments: Vec<AnchorTimeAlignmentEntry>,
    ) -> Result<Self, DomainError> {
        if alignments.is_empty() {
            return Err(DomainError::EmptyValue(
                "AnchorTimeAlignmentResource.alignments",
            ));
        }
        let mut seen: Vec<&str> = Vec::with_capacity(alignments.len());
        let mut previous_time: Option<u64> = None;
        for entry in &alignments {
            if seen.contains(&entry.anchor_id.as_str()) {
                return Err(DomainError::DuplicateAnchor(entry.anchor_id.clone()));
            }
            seen.push(entry.anchor_id.as_str());
            if previous_time.is_some_and(|previous| entry.media_time_ms < previous) {
                return Err(DomainError::NonMonotonicAlignment);
            }
            previous_time = Some(entry.media_time_ms);
        }
        Ok(Self {
            id,
            anchor_resource_id,
            rendition_id,
            alignments,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn language(code: &str) -> LanguageCode {
        LanguageCode::parse(code).expect("valid language code")
    }

    fn anchor(id: &str, kind: AnchorKind, start: u64, end: u64) -> ReadingAnchor {
        ReadingAnchor {
            anchor_id: ReadingAnchorId::parse(id).expect("valid anchor id"),
            kind,
            start_offset: start,
            end_offset: end,
        }
    }

    fn structured() -> StructuredReadingResource {
        let anchors = vec![
            anchor("anchor-1", AnchorKind::Block, 0, 10),
            anchor("anchor-2", AnchorKind::Span, 0, 5),
            anchor("anchor-3", AnchorKind::Span, 5, 10),
        ];
        StructuredReadingResource::new(
            ResourceId::parse("resource-reading").expect("valid resource id"),
            language("en"),
            anchors,
            vec![ReadingBlock {
                block_id: "block-1".to_owned(),
                span_anchor_ids: vec![
                    ReadingAnchorId::parse("anchor-2").unwrap(),
                    ReadingAnchorId::parse("anchor-3").unwrap(),
                ],
                parent_block_id: None,
            }],
            vec![ReadingSpan {
                span_id: "span-1".to_owned(),
                anchor_id: ReadingAnchorId::parse("anchor-2").unwrap(),
                parent_anchor_id: None,
            }],
            vec![AnchorDocumentMapping {
                anchor_id: ReadingAnchorId::parse("anchor-2").unwrap(),
                rendition_id: RenditionId::parse("rendition-x").expect("valid rendition id"),
                locator: "loc-1".to_owned(),
            }],
        )
        .expect("valid structured reading")
    }

    #[test]
    fn resource_identity_is_the_package_declared_id() {
        let first = structured();
        let second = structured();
        assert_eq!(first.id, second.id);
        // The declared id participates in identity exactly as declared.
        let declared = StructuredReadingResource::new(
            ResourceId::parse("resource-reading-2").expect("valid resource id"),
            first.language.clone(),
            first.anchors.clone(),
            first.blocks.clone(),
            first.spans.clone(),
            first.document_mappings.clone(),
        )
        .expect("valid structured reading");
        assert_ne!(first.id, declared.id);
    }

    #[test]
    fn empty_duplicate_and_unknown_anchors_are_rejected() {
        assert_eq!(
            StructuredReadingResource::new(
                ResourceId::parse("r").expect("valid resource id"),
                language("en"),
                vec![],
                vec![],
                vec![],
                vec![],
            ),
            Err(DomainError::EmptyValue("StructuredReadingResource.anchors"))
        );
        let anchors = vec![
            anchor("same", AnchorKind::Block, 0, 5),
            anchor("same", AnchorKind::Span, 5, 10),
        ];
        assert_eq!(
            StructuredReadingResource::new(
                ResourceId::parse("r").expect("valid resource id"),
                language("en"),
                anchors,
                vec![],
                vec![],
                vec![],
            ),
            Err(DomainError::DuplicateAnchor(
                ReadingAnchorId::parse("same").unwrap()
            ))
        );
        let unknown = vec![ReadingSpan {
            span_id: "s".to_owned(),
            anchor_id: ReadingAnchorId::parse("missing-anchor").unwrap(),
            parent_anchor_id: None,
        }];
        assert_eq!(
            StructuredReadingResource::new(
                ResourceId::parse("r").expect("valid resource id"),
                language("en"),
                vec![anchor("anchor-1", AnchorKind::Block, 0, 5)],
                vec![],
                unknown,
                vec![],
            ),
            Err(DomainError::UnknownAnchor(
                ReadingAnchorId::parse("missing-anchor").unwrap()
            ))
        );
    }

    #[test]
    fn invalid_anchor_range_and_unknown_block_are_rejected() {
        let bad_range = vec![anchor("a-1", AnchorKind::Block, 10, 5)];
        assert_eq!(
            StructuredReadingResource::new(
                ResourceId::parse("r").expect("valid resource id"),
                language("en"),
                bad_range,
                vec![],
                vec![],
                vec![],
            ),
            Err(DomainError::InvalidAnchorRange)
        );
        let orphan_block = vec![ReadingBlock {
            block_id: "block-orphan".to_owned(),
            span_anchor_ids: vec![ReadingAnchorId::parse("a-1").unwrap()],
            parent_block_id: Some("block-missing".to_owned()),
        }];
        assert_eq!(
            StructuredReadingResource::new(
                ResourceId::parse("r").expect("valid resource id"),
                language("en"),
                vec![anchor("a-1", AnchorKind::Block, 0, 5)],
                orphan_block,
                vec![],
                vec![],
            ),
            Err(DomainError::UnknownBlock("block-orphan".to_owned()))
        );
    }

    #[test]
    fn anchor_time_alignment_is_unique_monotonic_and_deterministic() {
        let base = structured();
        let rendition = RenditionId::parse("rendition-audio").expect("valid rendition id");
        let alignment = AnchorTimeAlignmentResource::new(
            ResourceId::parse("alignment-1").expect("valid resource id"),
            base.id.clone(),
            rendition.clone(),
            vec![
                AnchorTimeAlignmentEntry {
                    anchor_id: ReadingAnchorId::parse("anchor-1").unwrap(),
                    media_time_ms: 0,
                },
                AnchorTimeAlignmentEntry {
                    anchor_id: ReadingAnchorId::parse("anchor-3").unwrap(),
                    media_time_ms: 1200,
                },
            ],
        )
        .expect("valid alignment");
        assert_eq!(alignment.id.as_str(), "alignment-1");

        assert_eq!(
            AnchorTimeAlignmentResource::new(
                ResourceId::parse("alignment-2").expect("valid resource id"),
                base.id.clone(),
                RenditionId::parse("r").unwrap(),
                vec![],
            ),
            Err(DomainError::EmptyValue(
                "AnchorTimeAlignmentResource.alignments"
            ))
        );
        let duplicate = vec![
            AnchorTimeAlignmentEntry {
                anchor_id: ReadingAnchorId::parse("anchor-1").unwrap(),
                media_time_ms: 0,
            },
            AnchorTimeAlignmentEntry {
                anchor_id: ReadingAnchorId::parse("anchor-1").unwrap(),
                media_time_ms: 10,
            },
        ];
        assert_eq!(
            AnchorTimeAlignmentResource::new(
                ResourceId::parse("alignment-3").expect("valid resource id"),
                base.id.clone(),
                RenditionId::parse("r").unwrap(),
                duplicate,
            ),
            Err(DomainError::DuplicateAnchor(
                ReadingAnchorId::parse("anchor-1").unwrap()
            ))
        );
        let non_monotonic = vec![
            AnchorTimeAlignmentEntry {
                anchor_id: ReadingAnchorId::parse("anchor-2").unwrap(),
                media_time_ms: 500,
            },
            AnchorTimeAlignmentEntry {
                anchor_id: ReadingAnchorId::parse("anchor-1").unwrap(),
                media_time_ms: 100,
            },
        ];
        assert_eq!(
            AnchorTimeAlignmentResource::new(
                ResourceId::parse("alignment-4").expect("valid resource id"),
                base.id.clone(),
                RenditionId::parse("r").unwrap(),
                non_monotonic,
            ),
            Err(DomainError::NonMonotonicAlignment)
        );
    }
}
