use crate::{
    ApplicationError, MediaAnalysisUseCases, ProsodicChunkProjection, ProsodyAnalysis,
    ProsodyAnalysisId, ProsodyAnalysisSummary, SubtitleTrackId, TimelineStatus,
};

impl MediaAnalysisUseCases {
    pub fn list_prosody_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ProsodyAnalysis>, ApplicationError> {
        self.prosody.list_prosody_analyses(track_id)
    }

    pub fn summarize_prosody_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ProsodyAnalysisSummary>, ApplicationError> {
        let analyses = self.prosody.list_prosody_analyses(track_id)?;
        Ok(analyses.iter().map(prosody_analysis_summary).collect())
    }

    pub fn get_prosody_analysis(
        &self,
        id: &ProsodyAnalysisId,
    ) -> Result<Option<ProsodyAnalysis>, ApplicationError> {
        self.prosody.get_prosody_analysis(id)
    }

    pub fn activate_prosody_analysis(
        &self,
        id: &ProsodyAnalysisId,
    ) -> Result<ProsodyAnalysis, ApplicationError> {
        let analysis = self.prosody.activate_prosody_analysis(id)?;
        self.reindex_track_corpus(&analysis.track_id)?;
        Ok(analysis)
    }

    pub fn archive_prosody_analysis(
        &self,
        id: &ProsodyAnalysisId,
    ) -> Result<ProsodyAnalysis, ApplicationError> {
        let analysis = self.prosody.archive_prosody_analysis(id)?;
        self.reindex_track_corpus(&analysis.track_id)?;
        Ok(analysis)
    }

    pub fn delete_prosody_analysis(
        &self,
        id: &ProsodyAnalysisId,
    ) -> Result<ProsodyAnalysis, ApplicationError> {
        let analysis = self.prosody.delete_prosody_analysis(id)?;
        self.reindex_track_corpus(&analysis.track_id)?;
        Ok(analysis)
    }

    /// Derived playback projection: prosodic chunks over one prosody analysis,
    /// with times projected through the track's word timings at read time.
    ///
    /// This is the R3 playback projection. Time semantics are never persisted
    /// on the prosody resource; they are derived here from the parent Word
    /// Timeline, mirroring the `sense_group_playback_range` precedent.
    pub fn prosody_chunk_projections_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ProsodicChunkProjection>, ApplicationError> {
        let Some(analysis) = self.prosody.active_prosody_analysis(track_id)? else {
            return Ok(Vec::new());
        };
        let mut timings = Vec::new();
        let mut sentence_ids = analysis
            .anchors
            .iter()
            .map(|anchor| anchor.word_ref.sentence_id.clone())
            .collect::<Vec<_>>();
        sentence_ids.sort_by(|left, right| left.as_str().cmp(right.as_str()));
        sentence_ids.dedup();
        for sentence_id in sentence_ids {
            timings.extend(self.pronunciation().word_timings(&sentence_id)?);
        }
        Ok(domain::prosody_chunk_projections(&analysis, &timings))
    }
}

pub fn prosody_analysis_summary(analysis: &ProsodyAnalysis) -> ProsodyAnalysisSummary {
    ProsodyAnalysisSummary {
        id: analysis.id.clone(),
        track_id: analysis.track_id.clone(),
        media_id: analysis.media_id.clone(),
        parent_word_timeline_id: analysis.parent_word_timeline_id.clone(),
        provider_id: analysis.provider_id.clone(),
        provider_version: analysis.provider_version.clone(),
        algorithm: analysis.algorithm.clone(),
        status: analysis.status,
        created_by: analysis.created_by,
        chunk_count: analysis.chunks.len() as u32,
        anchor_count: analysis.anchors.len() as u32,
        created_at_ms: analysis.created_at_ms,
        updated_at_ms: analysis.updated_at_ms,
        can_activate: analysis.status != TimelineStatus::Archived,
        can_archive: analysis.status != TimelineStatus::Archived,
        can_delete: true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::{
        LanguageCode, MediaId, ProsodyAnchor, ProsodyEvidence, ProsodyWordRef, SubtitleTokenKind,
        SubtitleTrack, SubtitleTrackStatus, TimeMs, TimelineCreator, TimelineMetrics,
        TimelineStatus, TimingSource, UtteranceRole, WordTiming,
    };

    fn word_timing(sentence_id: &str, index: u32, start: u64, end: u64) -> WordTiming {
        WordTiming {
            sentence_id: domain::SubtitleSentenceId::parse(sentence_id).unwrap(),
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

    fn analysis() -> ProsodyAnalysis {
        ProsodyAnalysis {
            id: ProsodyAnalysisId::parse("prosody-summary").unwrap(),
            track_id: domain::SubtitleTrackId::parse("track-1").unwrap(),
            media_id: MediaId::parse("media-1").unwrap(),
            parent_word_timeline_id: None,
            provider_id: "listen-gen".into(),
            provider_version: "0.1.0".into(),
            algorithm: "prosody-v1".into(),
            status: TimelineStatus::Candidate,
            created_by: TimelineCreator::Algorithm,
            metrics_json: TimelineMetrics::default(),
            chunks: vec![domain::ProsodicChunk {
                sentence_id: domain::SubtitleSentenceId::parse("s1").unwrap(),
                chunk_index: 0,
                start_token_index: 0,
                end_token_index: 0,
                nucleus_token_index: Some(0),
                confidence: 0.95,
            }],
            anchors: vec![ProsodyAnchor {
                word_ref: ProsodyWordRef {
                    sentence_id: domain::SubtitleSentenceId::parse("s1").unwrap(),
                    token_index: 0,
                },
                syllable_index: None,
                lexical_stress: domain::LexicalStress::Primary,
                realized_prominence: 0.7,
                utterance_role: UtteranceRole::Nucleus,
                evidence: vec![ProsodyEvidence::Energy],
                confidence: 0.95,
            }],
            created_at_ms: 1,
            updated_at_ms: 1,
        }
    }

    #[test]
    fn summary_reflects_candidate_lifecycle() {
        let summary = prosody_analysis_summary(&analysis());
        assert_eq!(summary.chunk_count, 1);
        assert_eq!(summary.anchor_count, 1);
        assert_eq!(summary.status, TimelineStatus::Candidate);
        assert!(summary.can_activate);
    }

    #[test]
    fn track_context_fixture_compiles() {
        let _track = SubtitleTrack {
            id: domain::SubtitleTrackId::parse("track-1").unwrap(),
            media_id: MediaId::parse("media-1").unwrap(),
            fingerprint: "track-fingerprint".into(),
            language: Some(LanguageCode::parse("en").unwrap()),
            source: "test".into(),
            status: SubtitleTrackStatus::Available,
            sentences: vec![],
        };
        let _ = SubtitleTokenKind::Word;
        let _ = TimeMs::new(0);
    }

    #[test]
    fn projection_uses_word_timings_at_read_time() {
        let value = analysis();
        let timings = vec![word_timing("s1", 0, 100, 200)];
        let projections = domain::prosody_chunk_projections(&value, &timings);
        assert_eq!(projections.len(), 1);
        assert_eq!(projections[0].start_ms, Some(100));
        assert_eq!(projections[0].end_ms, Some(200));
        assert_eq!(projections[0].nucleus_token_index, Some(0));
    }
}
