use serde::{Deserialize, Serialize};

use crate::{
    MediaId, ProsodyAnalysisId, SubtitleSentenceId, SubtitleTrackId, TimelineCreator,
    TimelineMetrics, TimelineStatus, WordTimelineId, WordTiming,
};

/// Core domain projection of content-package v1 `prosody_analysis`.
///
/// R3 semantic resolution: this resource is the single semantic source for the
/// Prosodic Chunk foundation slot. The package resource is word-anchored
/// (prominence, lexical stress, utterance role), so the Core projection keeps
/// exactly those anchors and the package-declared prosodic chunk token spans.
/// Playback times are a *derived projection* over those spans plus the Word
/// Timeline (see [`prosody_chunk_projections`]); time semantics are not
/// persisted on this resource.
///
/// The legacy persisted `ChunkTimeline` representation was retired in R5;
/// foundation preparation and corpus projection read prosody through this
/// resource only. Sense Group analysis stays a separate resource family with
/// a separate lifecycle: it is never derived from, or merged into, this type.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProsodyAnalysis {
    pub id: ProsodyAnalysisId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub parent_word_timeline_id: Option<WordTimelineId>,
    pub provider_id: String,
    pub provider_version: String,
    pub algorithm: String,
    pub status: TimelineStatus,
    pub created_by: TimelineCreator,
    #[serde(default)]
    pub metrics_json: TimelineMetrics,
    #[serde(default)]
    pub chunks: Vec<ProsodicChunk>,
    pub anchors: Vec<ProsodyAnchor>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProsodyAnchor {
    pub word_ref: ProsodyWordRef,
    #[serde(default)]
    pub syllable_index: Option<u32>,
    pub lexical_stress: LexicalStress,
    pub realized_prominence: f64,
    pub utterance_role: UtteranceRole,
    #[serde(default)]
    pub evidence: Vec<ProsodyEvidence>,
    pub confidence: f64,
}

/// Word anchor reference inside one Subtitle Text Track. Matches the
/// content-package v1 `TokenRef` shape so projection is lossless.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProsodyWordRef {
    pub sentence_id: SubtitleSentenceId,
    pub token_index: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProsodicChunk {
    pub sentence_id: SubtitleSentenceId,
    pub chunk_index: u32,
    pub start_token_index: u32,
    /// Inclusive end token index in Core domain representation.
    pub end_token_index: u32,
    pub nucleus_token_index: Option<u32>,
    pub confidence: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LexicalStress {
    Primary,
    Secondary,
    Unstressed,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UtteranceRole {
    Nucleus,
    Prenuclear,
    Postnuclear,
    Unmarked,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProsodyEvidence {
    Energy,
    Pitch,
    Duration,
    LexicalStress,
    Context,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProsodyAnalysisSummary {
    pub id: ProsodyAnalysisId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub parent_word_timeline_id: Option<WordTimelineId>,
    pub provider_id: String,
    pub provider_version: String,
    pub algorithm: String,
    pub status: TimelineStatus,
    pub created_by: TimelineCreator,
    pub chunk_count: u32,
    pub anchor_count: u32,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
    pub can_activate: bool,
    pub can_archive: bool,
    pub can_delete: bool,
}

/// One playback-oriented prosodic chunk derived from prosody anchors and Word
/// Timeline timings.
///
/// This is a read-time projection: the chunk carries *derived* times (from the
/// parent Word Timeline) and is never persisted. Chunk boundaries come only
/// from package-declared token spans; Core never infers them from word roles.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProsodicChunkProjection {
    pub sentence_id: SubtitleSentenceId,
    pub chunk_index: u32,
    /// First anchored token in this chunk.
    pub start_token_index: u32,
    /// Last anchored token in this chunk.
    pub end_token_index: u32,
    /// Derived playback range; `None` when no Word Timeline timing covers the
    /// anchored tokens.
    pub start_ms: Option<u64>,
    pub end_ms: Option<u64>,
    pub nucleus_token_index: Option<u32>,
}

/// Derives playback-oriented prosodic chunks by projecting anchors through
/// word timings. Mirrors the `sense_group_playback_range` precedent: times are
/// derived at read time and never persisted on the resource.
pub fn prosody_chunk_projections(
    analysis: &ProsodyAnalysis,
    word_timings: &[WordTiming],
) -> Vec<ProsodicChunkProjection> {
    analysis
        .chunks
        .iter()
        .map(|chunk| {
            let sentence_id = &chunk.sentence_id;
            let start_token_index = chunk.start_token_index;
            let end_token_index = chunk.end_token_index;
            let matching = word_timings
                .iter()
                .filter(|timing| {
                    timing.sentence_id == *sentence_id
                        && timing.token_index >= start_token_index
                        && timing.token_index <= end_token_index
                })
                .collect::<Vec<_>>();
            let (start_ms, end_ms) = if matching.is_empty() {
                (None, None)
            } else {
                (
                    Some(matching.iter().map(|timing| timing.start_ms).min().unwrap()),
                    Some(matching.iter().map(|timing| timing.end_ms).max().unwrap()),
                )
            };
            ProsodicChunkProjection {
                sentence_id: sentence_id.clone(),
                chunk_index: chunk.chunk_index,
                start_token_index,
                end_token_index,
                start_ms,
                end_ms,
                nucleus_token_index: chunk.nucleus_token_index,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{MediaId, SubtitleSentenceId, SubtitleTrackId, TimingSource};

    fn word_timing(sentence_id: &str, index: u32, start: u64, end: u64) -> WordTiming {
        WordTiming {
            sentence_id: SubtitleSentenceId::parse(sentence_id).unwrap(),
            token_index: index,
            text: format!("word{index}"),
            start_ms: start,
            end_ms: end,
            confidence: Some(1.0),
            timing_source: TimingSource::AsrAligned,
            provider_id: "test".into(),
            provider_version: "v1".into(),
        }
    }

    fn anchor(sentence_id: &str, token_index: u32, role: UtteranceRole) -> ProsodyAnchor {
        ProsodyAnchor {
            word_ref: ProsodyWordRef {
                sentence_id: SubtitleSentenceId::parse(sentence_id).unwrap(),
                token_index,
            },
            syllable_index: None,
            lexical_stress: LexicalStress::Unknown,
            realized_prominence: 0.5,
            utterance_role: role,
            evidence: vec![ProsodyEvidence::Pitch],
            confidence: 0.9,
        }
    }

    fn analysis(anchors: Vec<ProsodyAnchor>) -> ProsodyAnalysis {
        ProsodyAnalysis {
            id: ProsodyAnalysisId::parse("prosody-1").unwrap(),
            track_id: SubtitleTrackId::parse("track-1").unwrap(),
            media_id: MediaId::parse("media-1").unwrap(),
            parent_word_timeline_id: None,
            provider_id: "listen-gen".into(),
            provider_version: "0.1.0".into(),
            algorithm: "prosody-v1".into(),
            status: TimelineStatus::Candidate,
            created_by: TimelineCreator::Algorithm,
            metrics_json: TimelineMetrics::default(),
            chunks: if anchors.is_empty() {
                vec![]
            } else {
                vec![ProsodicChunk {
                    sentence_id: anchors[0].word_ref.sentence_id.clone(),
                    chunk_index: 0,
                    start_token_index: anchors.first().unwrap().word_ref.token_index,
                    end_token_index: anchors.last().unwrap().word_ref.token_index,
                    nucleus_token_index: anchors
                        .iter()
                        .find(|anchor| anchor.utterance_role == UtteranceRole::Nucleus)
                        .map(|anchor| anchor.word_ref.token_index),
                    confidence: 0.9,
                }]
            },
            anchors,
            created_at_ms: 1,
            updated_at_ms: 1,
        }
    }

    #[test]
    fn projection_uses_declared_chunk_spans_and_derives_only_times() {
        let timings = vec![
            word_timing("s1", 0, 100, 200),
            word_timing("s1", 1, 210, 350),
            word_timing("s1", 2, 360, 500),
            word_timing("s1", 3, 510, 650),
        ];
        let mut value = analysis(vec![
            anchor("s1", 0, UtteranceRole::Prenuclear),
            anchor("s1", 1, UtteranceRole::Nucleus),
            anchor("s1", 2, UtteranceRole::Postnuclear),
            anchor("s1", 3, UtteranceRole::Nucleus),
        ]);
        value.chunks = vec![
            ProsodicChunk {
                sentence_id: SubtitleSentenceId::parse("s1").unwrap(),
                chunk_index: 0,
                start_token_index: 0,
                end_token_index: 2,
                nucleus_token_index: Some(1),
                confidence: 0.9,
            },
            ProsodicChunk {
                sentence_id: SubtitleSentenceId::parse("s1").unwrap(),
                chunk_index: 1,
                start_token_index: 3,
                end_token_index: 3,
                nucleus_token_index: Some(3),
                confidence: 0.9,
            },
        ];
        let projections = prosody_chunk_projections(&value, &timings);

        assert_eq!(projections.len(), 2);
        assert_eq!(projections[0].chunk_index, 0);
        assert_eq!(projections[0].start_token_index, 0);
        assert_eq!(projections[0].end_token_index, 2);
        assert_eq!(projections[0].nucleus_token_index, Some(1));
        assert_eq!(projections[0].start_ms, Some(100));
        assert_eq!(projections[0].end_ms, Some(500));
        assert_eq!(projections[1].chunk_index, 1);
        assert_eq!(projections[1].start_token_index, 3);
        assert_eq!(projections[1].end_token_index, 3);
        assert_eq!(projections[1].nucleus_token_index, Some(3));
        assert_eq!(projections[1].start_ms, Some(510));
        assert_eq!(projections[1].end_ms, Some(650));
    }

    #[test]
    fn projection_without_nucleus_yields_one_sentence_chunk() {
        let value = analysis(vec![
            anchor("s1", 0, UtteranceRole::Unmarked),
            anchor("s1", 1, UtteranceRole::Unmarked),
        ]);
        let projections = prosody_chunk_projections(&value, &[]);

        assert_eq!(projections.len(), 1);
        assert_eq!(projections[0].nucleus_token_index, None);
        assert_eq!(projections[0].start_ms, None);
        assert_eq!(projections[0].end_ms, None);
    }

    #[test]
    fn projection_uses_declared_span_independently_of_anchor_order() {
        let timings = vec![
            word_timing("s1", 0, 100, 200),
            word_timing("s1", 1, 210, 350),
            word_timing("s1", 2, 360, 500),
        ];
        let mut value = analysis(vec![
            anchor("s1", 2, UtteranceRole::Postnuclear),
            anchor("s1", 0, UtteranceRole::Prenuclear),
            anchor("s1", 1, UtteranceRole::Nucleus),
        ]);
        value.chunks = vec![ProsodicChunk {
            sentence_id: SubtitleSentenceId::parse("s1").unwrap(),
            chunk_index: 0,
            start_token_index: 0,
            end_token_index: 2,
            nucleus_token_index: Some(1),
            confidence: 0.9,
        }];
        let projections = prosody_chunk_projections(&value, &timings);

        assert_eq!(projections.len(), 1);
        assert_eq!(projections[0].start_token_index, 0);
        assert_eq!(projections[0].end_token_index, 2);
        assert_eq!(projections[0].start_ms, Some(100));
        assert_eq!(projections[0].end_ms, Some(500));
    }

    #[test]
    fn projection_separates_sentences() {
        let mut value = analysis(vec![
            anchor("s1", 0, UtteranceRole::Nucleus),
            anchor("s2", 0, UtteranceRole::Nucleus),
        ]);
        value.chunks = vec![
            ProsodicChunk {
                sentence_id: SubtitleSentenceId::parse("s1").unwrap(),
                chunk_index: 0,
                start_token_index: 0,
                end_token_index: 0,
                nucleus_token_index: Some(0),
                confidence: 0.9,
            },
            ProsodicChunk {
                sentence_id: SubtitleSentenceId::parse("s2").unwrap(),
                chunk_index: 0,
                start_token_index: 0,
                end_token_index: 0,
                nucleus_token_index: Some(0),
                confidence: 0.9,
            },
        ];
        let projections = prosody_chunk_projections(&value, &[]);

        assert_eq!(projections.len(), 2);
        assert_ne!(projections[0].sentence_id, projections[1].sentence_id);
    }

    #[test]
    fn analysis_serialization_roundtrip() {
        let value = analysis(vec![anchor("s1", 1, UtteranceRole::Nucleus)]);
        let json = serde_json::to_string(&value).unwrap();
        let deserialized: ProsodyAnalysis = serde_json::from_str(&json).unwrap();
        assert_eq!(value, deserialized);
    }
}
