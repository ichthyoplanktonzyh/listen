use crate::*;

impl AppServices {
    pub fn list_phone_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneTimeline>, ApplicationError> {
        self.subtitles.list_phone_timelines(track_id)
    }

    pub fn summarize_phone_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneTimelineSummary>, ApplicationError> {
        let timelines = self.subtitles.list_phone_timelines(track_id)?;
        Ok(timelines.iter().map(phone_timeline_summary).collect())
    }

    pub fn get_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError> {
        self.subtitles.get_phone_timeline(id)
    }

    pub fn create_phone_timeline_from_analysis(
        &self,
        analysis: &PhoneticAnalysis,
        requested_status: Option<TimelineStatus>,
    ) -> Result<PhoneTimeline, ApplicationError> {
        analysis.validate().map_err(ApplicationError::from)?;
        if analysis.detected_phones.is_empty() {
            return Err(ApplicationError::Validation("phone timeline phones"));
        }
        let requested_status = requested_status.unwrap_or(TimelineStatus::Candidate);
        let parent_word_timeline_id = self
            .subtitles
            .active_word_timeline(&analysis.track_id)?
            .map(|timeline| timeline.id);
        let now = now_ms();
        let precision = phone_timeline_precision_for_analysis(analysis);
        let fingerprint = format!(
            "{}:{}:{}:{}",
            analysis.track_id.as_str(),
            analysis.id.as_str(),
            analysis.model_revision,
            serde_json::to_string(&analysis.detected_phones).unwrap_or_default()
        );
        let mut timeline = PhoneTimeline {
            id: PhoneTimelineId::from_fingerprint("phone-timeline", &fingerprint),
            track_id: analysis.track_id.clone(),
            media_id: analysis.media_id.clone(),
            sentence_id: analysis.sentence_id.clone(),
            parent_word_timeline_id,
            parent_phonetic_analysis_id: Some(analysis.id.clone()),
            provider_id: analysis.provider_id.clone(),
            provider_version: analysis.provider_version.clone(),
            model_id: Some(analysis.model_id.clone()),
            model_revision: Some(analysis.model_revision.clone()),
            phone_set: analysis.phone_set.clone(),
            precision,
            created_by: TimelineCreator::Algorithm,
            status: requested_status,
            metrics_json: serde_json::json!({
                "parent_phonetic_analysis_id": analysis.id.as_str(),
                "analysis_audio_start_ms": analysis.audio_start_ms,
                "analysis_audio_end_ms": analysis.audio_end_ms,
                "analyzer_version": analysis.analyzer_version,
                "model_checksum_sha256": analysis.model_checksum_sha256,
                "synthetic": analysis.provider_id == "research-fixture",
            }),
            phones: analysis.detected_phones.clone(),
            alignments: analysis.alignments.clone(),
            findings: analysis.findings.clone(),
            created_at_ms: now,
            updated_at_ms: now,
        };
        if requested_status == TimelineStatus::Active {
            timeline.status = TimelineStatus::Candidate;
        }
        let timeline = self.subtitles.save_phone_timeline(&timeline)?;
        if requested_status == TimelineStatus::Active {
            self.subtitles.activate_phone_timeline(&timeline.id)
        } else {
            Ok(timeline)
        }
    }

    pub fn activate_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        self.subtitles.activate_phone_timeline(id)
    }

    pub fn archive_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        self.subtitles.archive_phone_timeline(id)
    }

    pub fn delete_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        self.subtitles.delete_phone_timeline(id)
    }
}

fn phone_timeline_precision_for_analysis(analysis: &PhoneticAnalysis) -> PhoneTimelinePrecision {
    if analysis.provider_id == "research-fixture" {
        PhoneTimelinePrecision::Approximate
    } else if analysis
        .findings
        .iter()
        .any(|finding| finding.status == PhoneticFindingStatus::DetectedInAudio)
    {
        PhoneTimelinePrecision::Detected
    } else {
        PhoneTimelinePrecision::Aligned
    }
}

fn phone_timeline_summary(timeline: &PhoneTimeline) -> PhoneTimelineSummary {
    let phone_count = timeline.phones.len() as u32;
    let start_ms = timeline.phones.first().map(|phone| phone.start_ms);
    let end_ms = timeline.phones.last().map(|phone| phone.end_ms);
    let confidences = timeline
        .phones
        .iter()
        .filter_map(|phone| phone.confidence)
        .collect::<Vec<_>>();
    let average_confidence = if confidences.is_empty() {
        None
    } else {
        Some(confidences.iter().sum::<f32>() / confidences.len() as f32)
    };
    PhoneTimelineSummary {
        id: timeline.id.clone(),
        track_id: timeline.track_id.clone(),
        media_id: timeline.media_id.clone(),
        sentence_id: timeline.sentence_id.clone(),
        parent_word_timeline_id: timeline.parent_word_timeline_id.clone(),
        parent_phonetic_analysis_id: timeline.parent_phonetic_analysis_id.clone(),
        provider_id: timeline.provider_id.clone(),
        provider_version: timeline.provider_version.clone(),
        model_id: timeline.model_id.clone(),
        model_revision: timeline.model_revision.clone(),
        phone_set: timeline.phone_set.clone(),
        precision: timeline.precision,
        created_by: timeline.created_by,
        status: timeline.status,
        phone_count,
        finding_count: timeline.findings.len() as u32,
        start_ms,
        end_ms,
        average_confidence,
        created_at_ms: timeline.created_at_ms,
        updated_at_ms: timeline.updated_at_ms,
        can_activate: timeline.status == TimelineStatus::Candidate,
        can_archive: timeline.status != TimelineStatus::Archived,
        can_delete: timeline.status != TimelineStatus::Active,
    }
}
