use serde::{Deserialize, Serialize};

use crate::{
    LanguageCode, MediaId, PhoneTimeline, PhoneTimelineId, ProsodyAnalysis, ProsodyAnalysisId,
    RhythmFrame, RhythmFrameId, SenseGroupAnalysis, SenseGroupAnalysisId, SubtitleSentenceId,
    SubtitleTokenKind, SubtitleTrackId, TimelineMetrics, TimelineStatus, WordTimeline,
    WordTimelineId,
};

pub const LLTIMELINE_SCHEMA_V1: &str = "llplayer.timeline.v1";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineDocument {
    pub schema: String,
    pub metadata: LLTimelineMetadata,
    pub segments: Vec<LLTimelineSegment>,
    #[serde(default)]
    pub word_timelines: Vec<WordTimeline>,
    pub active_word_timeline_id: Option<WordTimelineId>,
    #[serde(default)]
    pub phone_timelines: Vec<PhoneTimeline>,
    pub active_phone_timeline_id: Option<PhoneTimelineId>,
    #[serde(default)]
    pub rhythm_frames: Vec<LLTimelineRhythmFrame>,
    #[serde(default)]
    pub sense_group_analyses: Vec<SenseGroupAnalysis>,
    #[serde(default)]
    pub active_sense_group_analysis_id: Option<SenseGroupAnalysisId>,
    #[serde(default)]
    pub prosody_analyses: Vec<ProsodyAnalysis>,
    #[serde(default)]
    pub active_prosody_analysis_id: Option<ProsodyAnalysisId>,
    #[serde(default)]
    pub artifacts: Vec<LLTimelineArtifact>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineMetadata {
    pub created_at_ms: u64,
    pub generator: LLTimelineGenerator,
    pub media: LLTimelineMedia,
    pub language: Option<LanguageCode>,
    pub human_reviewed: bool,
    #[serde(default)]
    pub extra: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LLTimelineGenerator {
    pub id: String,
    pub version: String,
    pub mode: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineMedia {
    pub id: MediaId,
    pub fingerprint: String,
    pub path: Option<String>,
    pub title: String,
    pub duration_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LLTimelineSegment {
    pub id: SubtitleSentenceId,
    pub index: u32,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub display_text: String,
    pub tokens: Vec<LLTimelineToken>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LLTimelineToken {
    pub index: u32,
    pub kind: SubtitleTokenKind,
    pub text: String,
    pub normalized: Option<String>,
    pub start_char: u32,
    pub end_char: u32,
}

pub type LLTimelinePhoneTimeline = PhoneTimeline;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineRhythmFrame {
    pub id: RhythmFrameId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub sentence_id: SubtitleSentenceId,
    pub parent_word_timeline_id: Option<WordTimelineId>,
    pub provider_id: String,
    pub provider_version: String,
    pub status: TimelineStatus,
    #[serde(default)]
    pub metrics_json: TimelineMetrics,
    pub rhythm_frame: RhythmFrame,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LLTimelineWordRef {
    pub sentence_id: SubtitleSentenceId,
    pub token_index: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LLTimelineArtifact {
    pub kind: String,
    pub provider_id: Option<String>,
    pub provider_version: Option<String>,
    #[serde(default)]
    pub payload: serde_json::Value,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::WordTimelineId;

    #[test]
    fn lltimeline_v1_fixture_deserializes() {
        let document: LLTimelineDocument = serde_json::from_str(include_str!(
            "../../../testdata/lltimeline/v1-minimal.lltimeline.json"
        ))
        .unwrap();
        assert_eq!(document.schema, LLTIMELINE_SCHEMA_V1);
        assert_eq!(document.segments.len(), 1);
        assert_eq!(document.word_timelines.len(), 1);
        assert_eq!(
            document.active_word_timeline_id,
            Some(WordTimelineId::parse("timeline-fixture").unwrap())
        );
        assert!(document.sense_group_analyses.is_empty());
        assert_eq!(document.active_sense_group_analysis_id, None);
        assert!(document.prosody_analyses.is_empty());
        assert_eq!(document.active_prosody_analysis_id, None);
    }

    #[test]
    fn lltimeline_v1_legacy_document_defaults_missing_sense_group_fields() {
        let mut fixture: serde_json::Value = serde_json::from_str(include_str!(
            "../../../testdata/lltimeline/v1-minimal.lltimeline.json"
        ))
        .unwrap();
        let object = fixture.as_object_mut().unwrap();
        object.remove("sense_group_analyses");
        object.remove("active_sense_group_analysis_id");
        object.remove("prosody_analyses");
        object.remove("active_prosody_analysis_id");

        let document: LLTimelineDocument = serde_json::from_value(fixture).unwrap();

        assert!(document.sense_group_analyses.is_empty());
        assert_eq!(document.active_sense_group_analysis_id, None);
        assert!(document.prosody_analyses.is_empty());
        assert_eq!(document.active_prosody_analysis_id, None);
        let serialized = serde_json::to_value(document).unwrap();
        assert_eq!(serialized["sense_group_analyses"], serde_json::json!([]));
        assert_eq!(
            serialized["active_sense_group_analysis_id"],
            serde_json::Value::Null
        );
        assert_eq!(serialized["prosody_analyses"], serde_json::json!([]));
        assert_eq!(
            serialized["active_prosody_analysis_id"],
            serde_json::Value::Null
        );
    }
}
