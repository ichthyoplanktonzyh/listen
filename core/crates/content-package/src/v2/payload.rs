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
    AcousticTrack, PhoneTimeline, ProsodyAnalysis, SenseGroupAnalysis, SpeechActivity,
    SubtitleTextTrack, WordAcoustics, WordTimeline,
};

use super::model::{
    ACOUSTIC_TRACK_SCHEMA_V1, DOCUMENT_TEXT_SCHEMA_V1, PHONE_TIMELINE_SCHEMA_V1,
    PROSODY_ANALYSIS_SCHEMA_V1, SENSE_GROUP_ANALYSIS_SCHEMA_V1, SPEECH_ACTIVITY_SCHEMA_V1,
    SUBTITLE_TEXT_TRACK_SCHEMA_V1, TIMED_TEXT_TRACK_SCHEMA_V2, TRANSLATION_SCHEMA_V1,
    WORD_ACOUSTICS_SCHEMA_V1, WORD_TIMELINE_SCHEMA_V1,
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
    AcousticTrack(AcousticTrack),
    SpeechActivity(SpeechActivity),
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
            Self::AcousticTrack(_) => ACOUSTIC_TRACK_SCHEMA_V1,
            Self::SpeechActivity(_) => SPEECH_ACTIVITY_SCHEMA_V1,
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
            Self::AcousticTrack(_) => "acoustic_track",
            Self::SpeechActivity(_) => "speech_activity",
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
            | ("acoustic_track", ACOUSTIC_TRACK_SCHEMA_V1)
            | ("speech_activity", SPEECH_ACTIVITY_SCHEMA_V1)
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
        ("acoustic_track", ACOUSTIC_TRACK_SCHEMA_V1) => {
            KnownPayload::AcousticTrack(serde_json::from_slice(bytes)?)
        }
        ("speech_activity", SPEECH_ACTIVITY_SCHEMA_V1) => {
            KnownPayload::SpeechActivity(serde_json::from_slice(bytes)?)
        }
        _ => return Ok(None),
    };
    Ok(Some(payload))
}

#[cfg(test)]
mod acoustic_evidence_tests {
    use super::{ACOUSTIC_TRACK_SCHEMA_V1, KnownPayload, SPEECH_ACTIVITY_SCHEMA_V1, decode_known,
        is_known};

    #[test]
    fn recognizes_and_decodes_acoustic_track() {
        assert!(is_known("acoustic_track", ACOUSTIC_TRACK_SCHEMA_V1));
        let bytes = serde_json::to_vec(&serde_json::json!({
            "sample_rate_hz": 16000,
            "frame_step_ms": 10,
            "energy_baseline": "recording_median_dbfs",
            "pitch_baseline": "recording_median_f0_hz",
            "frames": [
                {"time_ms": 0, "energy_dbfs": -55.0, "energy_rel_db": -8.0, "f0_hz": null, "f0_rel_st": null, "voiced": false}
            ]
        }))
        .unwrap();
        let decoded = decode_known("acoustic_track", ACOUSTIC_TRACK_SCHEMA_V1, &bytes).unwrap();
        assert!(matches!(decoded, Some(KnownPayload::AcousticTrack(_))));
    }

    #[test]
    fn recognizes_and_decodes_speech_activity() {
        assert!(is_known("speech_activity", SPEECH_ACTIVITY_SCHEMA_V1));
        let bytes = serde_json::to_vec(&serde_json::json!({
            "spans": [{"start_ms": 0, "end_ms": 100, "activity": "silence"}]
        }))
        .unwrap();
        let decoded = decode_known("speech_activity", SPEECH_ACTIVITY_SCHEMA_V1, &bytes).unwrap();
        assert!(matches!(decoded, Some(KnownPayload::SpeechActivity(_))));
    }
}
