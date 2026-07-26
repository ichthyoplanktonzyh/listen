use serde::{Deserialize, Serialize};

use crate::{
    MediaId, SenseGroupAnalysisId, SenseGroupId, SubtitleSentenceId, SubtitleTrackId,
    TimelineCreator, TimelineMetrics, TimelineStatus, WordTimelineId, WordTiming,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SenseGroupSource {
    DependencyParse,
    PhraseStructure,
    LanguageModel,
    Punctuation,
    LengthLimit,
    Rule,
    User,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SenseGroup {
    pub id: SenseGroupId,
    pub sentence_id: SubtitleSentenceId,
    pub group_index: u32,
    pub start_token_index: u32,
    /// Inclusive end index.
    pub end_token_index: u32,
    pub text: String,
    pub label: Option<String>,
    pub head_token_index: Option<u32>,
    pub confidence: f32,
    #[serde(default)]
    pub sources: Vec<SenseGroupSource>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SenseGroupAnalysis {
    pub id: SenseGroupAnalysisId,
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
    pub groups: Vec<SenseGroup>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SenseGroupAnalysisSummary {
    pub id: SenseGroupAnalysisId,
    pub track_id: SubtitleTrackId,
    pub media_id: MediaId,
    pub parent_word_timeline_id: Option<WordTimelineId>,
    pub provider_id: String,
    pub provider_version: String,
    pub algorithm: String,
    pub status: TimelineStatus,
    pub created_by: TimelineCreator,
    pub group_count: u32,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
    pub can_activate: bool,
    pub can_archive: bool,
    pub can_delete: bool,
}

/// Derives a playback time range for a sense group by projecting its token
/// span through word timings. Returns `None` when no matching timings exist.
pub fn sense_group_playback_range(
    group: &SenseGroup,
    word_timings: &[WordTiming],
) -> Option<(u64, u64)> {
    let matching: Vec<&WordTiming> = word_timings
        .iter()
        .filter(|wt| {
            wt.sentence_id == group.sentence_id
                && wt.token_index >= group.start_token_index
                && wt.token_index <= group.end_token_index
        })
        .collect();

    if matching.is_empty() {
        return None;
    }

    let start = matching.iter().map(|wt| wt.start_ms).min().unwrap();
    let end = matching.iter().map(|wt| wt.end_ms).max().unwrap();
    Some((start, end))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{SubtitleSentenceId, TimingSource};

    fn word_timing(sentence_id: &str, index: u32, start: u64, end: u64) -> WordTiming {
        WordTiming {
            sentence_id: SubtitleSentenceId::parse(sentence_id).unwrap(),
            token_index: index,
            text: format!("word{index}"),
            start_ms: start,
            end_ms: end,
            confidence: Some(1.0),
            timing_source: TimingSource::ForcedAligned,
            provider_id: "test".into(),
            provider_version: "v1".into(),
        }
    }

    fn sense_group(sentence_id: &str, start: u32, end: u32) -> SenseGroup {
        SenseGroup {
            id: SenseGroupId::parse("sg-1").unwrap(),
            sentence_id: SubtitleSentenceId::parse(sentence_id).unwrap(),
            group_index: 0,
            start_token_index: start,
            end_token_index: end,
            text: "test group".into(),
            label: None,
            head_token_index: None,
            confidence: 1.0,
            sources: vec![SenseGroupSource::Rule],
        }
    }

    #[test]
    fn playback_range_projects_through_word_timings() {
        let timings = vec![
            word_timing("s1", 0, 100, 200),
            word_timing("s1", 1, 210, 350),
            word_timing("s1", 2, 360, 500),
            word_timing("s1", 3, 510, 650),
        ];
        let group = sense_group("s1", 1, 2);
        assert_eq!(
            sense_group_playback_range(&group, &timings),
            Some((210, 500))
        );
    }

    #[test]
    fn playback_range_single_token() {
        let timings = vec![
            word_timing("s1", 0, 100, 200),
            word_timing("s1", 1, 210, 350),
        ];
        let group = sense_group("s1", 0, 0);
        assert_eq!(
            sense_group_playback_range(&group, &timings),
            Some((100, 200))
        );
    }

    #[test]
    fn playback_range_no_matching_timings() {
        let timings = vec![word_timing("s2", 0, 100, 200)];
        let group = sense_group("s1", 0, 1);
        assert_eq!(sense_group_playback_range(&group, &timings), None);
    }

    #[test]
    fn playback_range_empty_timings() {
        let group = sense_group("s1", 0, 2);
        assert_eq!(sense_group_playback_range(&group, &[]), None);
    }

    #[test]
    fn sense_group_serialization_roundtrip() {
        let group = SenseGroup {
            id: SenseGroupId::parse("sg-test").unwrap(),
            sentence_id: SubtitleSentenceId::parse("sent-1").unwrap(),
            group_index: 0,
            start_token_index: 0,
            end_token_index: 3,
            text: "the green apple".into(),
            label: Some("NP".into()),
            head_token_index: Some(2),
            confidence: 0.95,
            sources: vec![SenseGroupSource::Rule, SenseGroupSource::Punctuation],
        };
        let json = serde_json::to_string(&group).unwrap();
        let deserialized: SenseGroup = serde_json::from_str(&json).unwrap();
        assert_eq!(group, deserialized);
    }

    #[test]
    fn analysis_serialization_roundtrip() {
        let analysis = SenseGroupAnalysis {
            id: SenseGroupAnalysisId::parse("sga-1").unwrap(),
            track_id: SubtitleTrackId::parse("track-1").unwrap(),
            media_id: MediaId::parse("media-1").unwrap(),
            parent_word_timeline_id: None,
            provider_id: "rule-based-sense-group".into(),
            provider_version: "v1".into(),
            algorithm: "punctuation_rule_v1".into(),
            status: TimelineStatus::Candidate,
            created_by: TimelineCreator::Algorithm,
            metrics_json: TimelineMetrics::default(),
            groups: vec![],
            created_at_ms: 1000,
            updated_at_ms: 1000,
        };
        let json = serde_json::to_string(&analysis).unwrap();
        let deserialized: SenseGroupAnalysis = serde_json::from_str(&json).unwrap();
        assert_eq!(analysis, deserialized);
    }
}
