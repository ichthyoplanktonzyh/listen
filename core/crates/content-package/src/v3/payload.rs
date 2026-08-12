//! Known payload decoding for Content Package v3.
//!
//! The v3 supported schema inventory is the shared v2 payload families
//! (document_text v1, timed_text_track v2, translation v1, and the six
//! generated v1 resource families) plus the v3 structured reading and
//! anchor-to-time alignment payloads. The v3 payload shapes are owned here;
//! the shared v2 shapes are reused verbatim.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::model::{
    PhoneTimeline, ProsodyAnalysis, SenseGroupAnalysis, SubtitleTextTrack, WordAcoustics,
    WordTimeline,
};
use crate::v2::{
    DOCUMENT_TEXT_SCHEMA_V1, DocumentText, PHONE_TIMELINE_SCHEMA_V1, PROSODY_ANALYSIS_SCHEMA_V1,
    SENSE_GROUP_ANALYSIS_SCHEMA_V1, SUBTITLE_TEXT_TRACK_SCHEMA_V1, TIMED_TEXT_TRACK_SCHEMA_V2,
    TRANSLATION_SCHEMA_V1, TimedTextTrack, Translation, WORD_ACOUSTICS_SCHEMA_V1,
    WORD_TIMELINE_SCHEMA_V1,
};

use super::model::{ANCHOR_TIME_ALIGNMENT_SCHEMA_V1, STRUCTURED_READING_SCHEMA_V1};

/// `structured_reading` v1: ordered hierarchy, blocks/spans, language
/// metadata, stable anchors, and optional mappings into exact Document
/// Rendition Locators. A Reading Anchor is stable only inside the exact
/// Resource identity; this schema never promises cross-resource anchor
/// stability.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StructuredReading {
    pub language: String,
    pub anchors: Vec<ReadingAnchor>,
    #[serde(default)]
    pub blocks: Vec<ReadingBlock>,
    #[serde(default)]
    pub spans: Vec<ReadingSpan>,
    #[serde(default)]
    pub document_mappings: Vec<AnchorDocumentMapping>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
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
#[serde(deny_unknown_fields)]
pub struct ReadingAnchor {
    pub anchor_id: String,
    pub kind: AnchorKind,
    /// First byte offset (UTF-8) of the anchored span in the resource text.
    pub start_offset: u64,
    /// One-past-last byte offset (UTF-8) of the anchored span.
    pub end_offset: u64,
}

/// One hierarchical block of the Structured Reading document structure.
/// Blocks reference spans by their exact anchor identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadingBlock {
    pub block_id: String,
    pub span_anchor_ids: Vec<String>,
    #[serde(default)]
    pub parent_block_id: Option<String>,
}

/// A text span inside the Structured Reading resource. The exact byte window
/// is anchored; spans never carry duplicated extracted strings.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReadingSpan {
    pub span_id: String,
    pub anchor_id: String,
    #[serde(default)]
    pub parent_anchor_id: Option<String>,
}

/// Optional mapping of an anchor to an exact Document Rendition Locator. A
/// locator is meaningful only against the exact rendition identity.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnchorDocumentMapping {
    pub anchor_id: String,
    pub rendition_id: String,
    /// Opaque locator into the rendition, verified against the rendition
    /// identity only.
    pub locator: String,
}

/// `anchor_time_alignment` v1: a Base Resource mapping exact Reading Anchors
/// to exact media-time Rendition Locators. The alignment is meaningful only
/// against the exact Structured Reading Resource and the exact Media
/// Rendition it names.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnchorTimeAlignment {
    pub anchor_resource_id: String,
    pub rendition_id: String,
    pub alignments: Vec<AnchorTimeAlignmentEntry>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// One anchor-to-media-time entry: exact anchor, exact media-time Rendition
/// Locator. A derived alignment never fabricates time: entries are exact or
/// absent.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnchorTimeAlignmentEntry {
    pub anchor_id: String,
    /// Media time in milliseconds.
    pub media_time_ms: u64,
}

/// A decoded, structurally validated known payload.
#[derive(Debug, Clone, PartialEq)]
pub enum KnownPayloadV3 {
    DocumentText(DocumentText),
    TimedTextTrack(TimedTextTrack),
    Translation(Translation),
    SubtitleTextTrack(SubtitleTextTrack),
    WordTimeline(WordTimeline),
    PhoneTimeline(PhoneTimeline),
    SenseGroupAnalysis(SenseGroupAnalysis),
    WordAcoustics(WordAcoustics),
    ProsodyAnalysis(ProsodyAnalysis),
    StructuredReading(StructuredReading),
    AnchorTimeAlignment(AnchorTimeAlignment),
}

impl KnownPayloadV3 {
    pub fn schema(&self) -> &'static str {
        match self {
            Self::DocumentText(_) => DOCUMENT_TEXT_SCHEMA_V1,
            Self::TimedTextTrack(_) => TIMED_TEXT_TRACK_SCHEMA_V2,
            Self::Translation(_) => TRANSLATION_SCHEMA_V1,
            Self::SubtitleTextTrack(_) => SUBTITLE_TEXT_TRACK_SCHEMA_V1,
            Self::WordTimeline(_) => WORD_TIMELINE_SCHEMA_V1,
            Self::PhoneTimeline(_) => PHONE_TIMELINE_SCHEMA_V1,
            Self::SenseGroupAnalysis(_) => SENSE_GROUP_ANALYSIS_SCHEMA_V1,
            Self::WordAcoustics(_) => WORD_ACOUSTICS_SCHEMA_V1,
            Self::ProsodyAnalysis(_) => PROSODY_ANALYSIS_SCHEMA_V1,
            Self::StructuredReading(_) => STRUCTURED_READING_SCHEMA_V1,
            Self::AnchorTimeAlignment(_) => ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
        }
    }

    pub fn kind(&self) -> &'static str {
        match self {
            Self::DocumentText(_) => "document_text",
            Self::TimedTextTrack(_) => "timed_text_track",
            Self::Translation(_) => "translation",
            Self::SubtitleTextTrack(_) => "subtitle_text_track",
            Self::WordTimeline(_) => "word_timeline",
            Self::PhoneTimeline(_) => "phone_timeline",
            Self::SenseGroupAnalysis(_) => "sense_group_analysis",
            Self::WordAcoustics(_) => "word_acoustics",
            Self::ProsodyAnalysis(_) => "prosody_analysis",
            Self::StructuredReading(_) => "structured_reading",
            Self::AnchorTimeAlignment(_) => "anchor_time_alignment",
        }
    }
}

/// Whether `(kind, schema)` identifies a known payload in this inventory.
pub(crate) fn is_known(kind: &str, schema: &str) -> bool {
    matches!(
        (kind, schema),
        ("document_text", DOCUMENT_TEXT_SCHEMA_V1)
            | ("timed_text_track", TIMED_TEXT_TRACK_SCHEMA_V2)
            | ("translation", TRANSLATION_SCHEMA_V1)
            | ("subtitle_text_track", SUBTITLE_TEXT_TRACK_SCHEMA_V1)
            | ("word_timeline", WORD_TIMELINE_SCHEMA_V1)
            | ("phone_timeline", PHONE_TIMELINE_SCHEMA_V1)
            | ("sense_group_analysis", SENSE_GROUP_ANALYSIS_SCHEMA_V1)
            | ("word_acoustics", WORD_ACOUSTICS_SCHEMA_V1)
            | ("prosody_analysis", PROSODY_ANALYSIS_SCHEMA_V1)
            | ("structured_reading", STRUCTURED_READING_SCHEMA_V1)
            | ("anchor_time_alignment", ANCHOR_TIME_ALIGNMENT_SCHEMA_V1)
    )
}

/// Decodes a known payload from its raw JSON bytes, matching the descriptor's
/// kind/schema pair. Returns `None` for unknown kinds; unknown *optional*
/// resources stay opaque and unknown *required* resources are handled by the
/// caller as incompatible.
pub(crate) fn decode_known(
    kind: &str,
    schema: &str,
    bytes: &[u8],
) -> Result<Option<KnownPayloadV3>, serde_json::Error> {
    let payload = match (kind, schema) {
        ("document_text", DOCUMENT_TEXT_SCHEMA_V1) => {
            KnownPayloadV3::DocumentText(serde_json::from_slice(bytes)?)
        }
        ("timed_text_track", TIMED_TEXT_TRACK_SCHEMA_V2) => {
            KnownPayloadV3::TimedTextTrack(serde_json::from_slice(bytes)?)
        }
        ("translation", TRANSLATION_SCHEMA_V1) => {
            KnownPayloadV3::Translation(serde_json::from_slice(bytes)?)
        }
        ("subtitle_text_track", SUBTITLE_TEXT_TRACK_SCHEMA_V1) => {
            KnownPayloadV3::SubtitleTextTrack(serde_json::from_slice(bytes)?)
        }
        ("word_timeline", WORD_TIMELINE_SCHEMA_V1) => {
            KnownPayloadV3::WordTimeline(serde_json::from_slice(bytes)?)
        }
        ("phone_timeline", PHONE_TIMELINE_SCHEMA_V1) => {
            KnownPayloadV3::PhoneTimeline(serde_json::from_slice(bytes)?)
        }
        ("sense_group_analysis", SENSE_GROUP_ANALYSIS_SCHEMA_V1) => {
            KnownPayloadV3::SenseGroupAnalysis(serde_json::from_slice(bytes)?)
        }
        ("word_acoustics", WORD_ACOUSTICS_SCHEMA_V1) => {
            KnownPayloadV3::WordAcoustics(serde_json::from_slice(bytes)?)
        }
        ("prosody_analysis", PROSODY_ANALYSIS_SCHEMA_V1) => {
            KnownPayloadV3::ProsodyAnalysis(serde_json::from_slice(bytes)?)
        }
        ("structured_reading", STRUCTURED_READING_SCHEMA_V1) => {
            KnownPayloadV3::StructuredReading(serde_json::from_slice(bytes)?)
        }
        ("anchor_time_alignment", ANCHOR_TIME_ALIGNMENT_SCHEMA_V1) => {
            KnownPayloadV3::AnchorTimeAlignment(serde_json::from_slice(bytes)?)
        }
        _ => return Ok(None),
    };
    Ok(Some(payload))
}
