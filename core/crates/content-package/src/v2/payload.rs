//! Known payload decoding for Content Package v2.
//!
//! The v2 supported schema inventory is: document_text v1, timed_text_track
//! v2, translation v1, and the six generated resource families from v1
//! (subtitle_text_track, word_timeline, phone_timeline, sense_group_analysis,
//! word_acoustics, prosody_analysis) whose payload shapes are reused verbatim
//! under v2 payload-specific identifiers (`listen.payload.*`); the v1
//! `listen.resource.*` full-envelope identifiers are never reinterpreted.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::model::{
    PhoneTimeline, ProsodyAnalysis, SenseGroupAnalysis, SubtitleTextTrack, WordAcoustics,
    WordTimeline,
};

use super::model::{
    DOCUMENT_TEXT_SCHEMA_V1, PHONE_TIMELINE_SCHEMA_V1, PROSODY_ANALYSIS_SCHEMA_V1,
    SENSE_GROUP_ANALYSIS_SCHEMA_V1, SUBTITLE_TEXT_TRACK_SCHEMA_V1, TIMED_TEXT_TRACK_SCHEMA_V2,
    TRANSLATION_SCHEMA_V1, WORD_ACOUSTICS_SCHEMA_V1, WORD_TIMELINE_SCHEMA_V1,
};

/// `document_text` v1: a plain-text document with per-segment BCP47 language
/// tags and text anchors (half-open character spans into the document text).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DocumentText {
    pub language: String,
    pub text: String,
    pub segments: Vec<DocumentTextSegment>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DocumentTextSegment {
    pub id: String,
    pub index: u32,
    pub language: String,
    pub start_char: u32,
    pub end_char: u32,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// `timed_text_track` v2: a timed transcript with per-segment BCP47 language
/// tags and half-open positive time spans. Segment indexes are contiguous.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TimedTextTrack {
    pub language: String,
    pub segments: Vec<TimedTextSegment>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TimedTextSegment {
    pub id: String,
    pub index: u32,
    pub language: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// `translation` v1: an assistance translation anchored to an exact Base
/// Resource (`base_resource_id`) with an explicit support language.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Translation {
    pub support_language: String,
    pub base_resource_id: String,
    pub segments: Vec<TranslationSegment>,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TranslationSegment {
    pub id: String,
    pub index: u32,
    pub text: String,
    pub source_segment_id: String,
    #[serde(default)]
    pub extensions: BTreeMap<String, Value>,
}

/// A decoded, structurally validated known payload.
#[derive(Debug, Clone, PartialEq)]
pub enum KnownPayload {
    DocumentText(DocumentText),
    TimedTextTrack(TimedTextTrack),
    Translation(Translation),
    SubtitleTextTrack(SubtitleTextTrack),
    WordTimeline(WordTimeline),
    PhoneTimeline(PhoneTimeline),
    SenseGroupAnalysis(SenseGroupAnalysis),
    WordAcoustics(WordAcoustics),
    ProsodyAnalysis(ProsodyAnalysis),
}

impl KnownPayload {
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
) -> Result<Option<KnownPayload>, serde_json::Error> {
    let payload = match (kind, schema) {
        ("document_text", DOCUMENT_TEXT_SCHEMA_V1) => {
            KnownPayload::DocumentText(serde_json::from_slice(bytes)?)
        }
        ("timed_text_track", TIMED_TEXT_TRACK_SCHEMA_V2) => {
            KnownPayload::TimedTextTrack(serde_json::from_slice(bytes)?)
        }
        ("translation", TRANSLATION_SCHEMA_V1) => {
            KnownPayload::Translation(serde_json::from_slice(bytes)?)
        }
        ("subtitle_text_track", SUBTITLE_TEXT_TRACK_SCHEMA_V1) => {
            KnownPayload::SubtitleTextTrack(serde_json::from_slice(bytes)?)
        }
        ("word_timeline", WORD_TIMELINE_SCHEMA_V1) => {
            KnownPayload::WordTimeline(serde_json::from_slice(bytes)?)
        }
        ("phone_timeline", PHONE_TIMELINE_SCHEMA_V1) => {
            KnownPayload::PhoneTimeline(serde_json::from_slice(bytes)?)
        }
        ("sense_group_analysis", SENSE_GROUP_ANALYSIS_SCHEMA_V1) => {
            KnownPayload::SenseGroupAnalysis(serde_json::from_slice(bytes)?)
        }
        ("word_acoustics", WORD_ACOUSTICS_SCHEMA_V1) => {
            KnownPayload::WordAcoustics(serde_json::from_slice(bytes)?)
        }
        ("prosody_analysis", PROSODY_ANALYSIS_SCHEMA_V1) => {
            KnownPayload::ProsodyAnalysis(serde_json::from_slice(bytes)?)
        }
        _ => return Ok(None),
    };
    Ok(Some(payload))
}
