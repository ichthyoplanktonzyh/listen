use crate::*;

impl AppServices {
    pub fn list_sense_group_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SenseGroupAnalysis>, ApplicationError> {
        self.timelines.list_sense_group_analyses(track_id)
    }

    pub fn summarize_sense_group_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SenseGroupAnalysisSummary>, ApplicationError> {
        let analyses = self.timelines.list_sense_group_analyses(track_id)?;
        Ok(analyses.iter().map(sense_group_analysis_summary).collect())
    }

    pub fn get_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<Option<SenseGroupAnalysis>, ApplicationError> {
        self.timelines.get_sense_group_analysis(id)
    }

    pub fn generate_sense_group_analysis(
        &self,
        track_id: &SubtitleTrackId,
        requested_status: Option<TimelineStatus>,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        let requested_status = requested_status.unwrap_or(TimelineStatus::Candidate);
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = speech_analysis::sense_group_partition::SenseGroupPartitionConfig::default();
        let mut groups = Vec::new();
        for sentence in &track.sentences {
            let candidates = self.phrase_candidates(&sentence.id)?;
            let spans = speech_analysis::sense_group_partition::partition_sentence(
                sentence,
                &candidates,
                &config,
            );
            for span in spans {
                let group_index = groups.len() as u32;
                groups.push(sense_group_from_span(sentence, group_index, &span));
            }
        }
        if groups.is_empty() {
            return Err(ApplicationError::Validation("sense group analysis groups"));
        }
        let now = now_ms();
        let provider_id = speech_analysis::sense_group_partition::PROVIDER_ID.to_owned();
        let provider_version = speech_analysis::sense_group_partition::PROVIDER_VERSION.to_owned();
        let algorithm = speech_analysis::sense_group_partition::ALGORITHM.to_owned();
        let fingerprint = format!(
            "{}:{}:{}",
            track.id.as_str(),
            provider_version,
            serde_json::to_string(&groups).unwrap_or_default()
        );
        let mut analysis = SenseGroupAnalysis {
            id: SenseGroupAnalysisId::from_fingerprint("sense-group-analysis", &fingerprint),
            track_id: track.id.clone(),
            media_id: track.media_id.clone(),
            parent_word_timeline_id: self
                .timelines
                .active_word_timeline(track_id)?
                .map(|wt| wt.id),
            provider_id,
            provider_version,
            algorithm,
            status: requested_status,
            created_by: TimelineCreator::Algorithm,
            metrics_json: serde_json::json!({}).into(),
            groups,
            created_at_ms: now,
            updated_at_ms: now,
        };
        if requested_status == TimelineStatus::Active {
            analysis.status = TimelineStatus::Candidate;
        }
        let analysis = self.timelines.save_sense_group_analysis(&analysis)?;
        if requested_status == TimelineStatus::Active {
            self.timelines.activate_sense_group_analysis(&analysis.id)
        } else {
            Ok(analysis)
        }
    }

    pub fn activate_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.timelines.activate_sense_group_analysis(id)
    }

    pub fn archive_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.timelines.archive_sense_group_analysis(id)
    }

    pub fn delete_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.timelines.delete_sense_group_analysis(id)
    }
}

fn sense_group_from_span(
    sentence: &SubtitleSentence,
    group_index: u32,
    span: &speech_analysis::sense_group_partition::SenseGroupSpan,
) -> SenseGroup {
    let matching_tokens: Vec<&SubtitleToken> = sentence
        .tokens
        .iter()
        .filter(|t| t.index >= span.start_token_index && t.index <= span.end_token_index)
        .collect();
    let text = if let (Some(first), Some(last)) = (matching_tokens.first(), matching_tokens.last())
    {
        sentence
            .original_text
            .get(first.start_char as usize..last.end_char as usize)
            .unwrap_or("")
            .to_owned()
    } else {
        String::new()
    };
    let id = SenseGroupId::from_fingerprint(
        "sense-group",
        &format!(
            "{}:{}:{}",
            sentence.id.as_str(),
            span.start_token_index,
            span.end_token_index
        ),
    );
    SenseGroup {
        id,
        sentence_id: sentence.id.clone(),
        group_index,
        start_token_index: span.start_token_index,
        end_token_index: span.end_token_index,
        text,
        label: None,
        head_token_index: None,
        confidence: span.confidence,
        sources: span.sources.clone(),
    }
}

fn sense_group_analysis_summary(analysis: &SenseGroupAnalysis) -> SenseGroupAnalysisSummary {
    SenseGroupAnalysisSummary {
        id: analysis.id.clone(),
        track_id: analysis.track_id.clone(),
        media_id: analysis.media_id.clone(),
        parent_word_timeline_id: analysis.parent_word_timeline_id.clone(),
        provider_id: analysis.provider_id.clone(),
        provider_version: analysis.provider_version.clone(),
        algorithm: analysis.algorithm.clone(),
        status: analysis.status,
        created_by: analysis.created_by,
        group_count: analysis.groups.len() as u32,
        created_at_ms: analysis.created_at_ms,
        updated_at_ms: analysis.updated_at_ms,
        can_activate: analysis.status != TimelineStatus::Archived,
        can_archive: analysis.status != TimelineStatus::Archived,
        can_delete: true,
    }
}
