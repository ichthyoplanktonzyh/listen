use crate::{
    ApplicationError, MediaAnalysisUseCases, SenseGroup, SenseGroupAnalysis, SenseGroupAnalysisId,
    SenseGroupAnalysisSummary, SenseGroupId, SubtitleSentence, SubtitleToken, SubtitleTrackId,
    SyntacticAnalysis, SyntacticConsumerBatch, SyntacticSenseGroupSpan, TimelineCreator,
    TimelineStatus, WordTimelineId, now_ms, validate_syntactic_analysis,
};
use domain::SenseGroupSource;

impl MediaAnalysisUseCases {
    pub fn list_sense_group_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SenseGroupAnalysis>, ApplicationError> {
        self.sense_groups.list_sense_group_analyses(track_id)
    }

    pub fn summarize_sense_group_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SenseGroupAnalysisSummary>, ApplicationError> {
        let analyses = self.sense_groups.list_sense_group_analyses(track_id)?;
        Ok(analyses.iter().map(sense_group_analysis_summary).collect())
    }

    pub fn get_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<Option<SenseGroupAnalysis>, ApplicationError> {
        self.sense_groups.get_sense_group_analysis(id)
    }

    pub fn generate_sense_group_analysis(
        &self,
        track_id: &SubtitleTrackId,
        requested_status: Option<TimelineStatus>,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.generate_sense_group_analysis_internal(track_id, requested_status, None)
    }

    pub fn persist_sense_group_analysis_from_batch(
        &self,
        track_id: &SubtitleTrackId,
        batch: &SyntacticConsumerBatch,
    ) -> Result<Option<SenseGroupAnalysis>, ApplicationError> {
        if batch
            .sentences
            .iter()
            .all(|sentence| sentence.sense_groups.is_empty())
        {
            return Ok(None);
        }
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let parent_word_timeline_id = self
            .word_timelines
            .active_word_timeline(track_id)?
            .map(|timeline| timeline.id);
        persist_sense_group_analysis_from_batch(
            self.sense_groups.as_ref(),
            &track,
            parent_word_timeline_id,
            batch,
        )
    }

    fn generate_sense_group_analysis_internal(
        &self,
        track_id: &SubtitleTrackId,
        requested_status: Option<TimelineStatus>,
        syntax: Option<&SyntacticAnalysis>,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        let requested_status = requested_status.unwrap_or(TimelineStatus::Candidate);
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        if let Some(syntax) = syntax
            && !validate_syntactic_analysis(syntax, &track.sentences).is_activatable()
        {
            return Err(ApplicationError::Validation(
                "syntactic analysis source snapshot",
            ));
        }
        let config = speech_analysis::audible_structure::SenseGroupPartitionConfig::default();
        let mut groups = Vec::new();
        for sentence in &track.sentences {
            let candidates = self.lexical_learning().phrase_candidates(&sentence.id)?;
            let spans = syntax
                .and_then(|analysis| {
                    analysis
                        .sentences
                        .iter()
                        .find(|syntax| syntax.sentence_id == sentence.id)
                })
                .map(|syntax| {
                    speech_analysis::audible_structure::partition_sentence_with_syntax(
                        sentence,
                        &candidates,
                        &config,
                        syntax,
                    )
                })
                .unwrap_or_else(|| {
                    speech_analysis::audible_structure::partition_sentence(
                        sentence,
                        &candidates,
                        &config,
                    )
                });
            for span in spans {
                let group_index = groups.len() as u32;
                groups.push(sense_group_from_span(sentence, group_index, &span));
            }
        }
        if groups.is_empty() {
            return Err(ApplicationError::Validation("sense group analysis groups"));
        }
        let now = now_ms();
        let (provider_id, provider_version, algorithm) = if syntax.is_some() {
            (
                speech_analysis::audible_structure::SYNTAX_PROVIDER_ID.to_owned(),
                speech_analysis::audible_structure::SYNTAX_PROVIDER_VERSION.to_owned(),
                speech_analysis::audible_structure::SYNTAX_ALGORITHM.to_owned(),
            )
        } else {
            (
                speech_analysis::audible_structure::PROVIDER_ID.to_owned(),
                speech_analysis::audible_structure::PROVIDER_VERSION.to_owned(),
                speech_analysis::audible_structure::ALGORITHM.to_owned(),
            )
        };
        let fingerprint = format!(
            "{}:{}:{}:{}",
            track.id.as_str(),
            provider_version,
            syntax
                .map(|analysis| analysis.id.as_str())
                .unwrap_or("none"),
            serde_json::to_string(&groups).unwrap_or_default()
        );
        let mut analysis = SenseGroupAnalysis {
            id: SenseGroupAnalysisId::from_fingerprint("sense-group-analysis", &fingerprint),
            track_id: track.id.clone(),
            media_id: track.media_id.clone(),
            parent_word_timeline_id: self
                .word_timelines
                .active_word_timeline(track_id)?
                .map(|wt| wt.id),
            provider_id,
            provider_version,
            algorithm,
            status: requested_status,
            created_by: TimelineCreator::Algorithm,
            metrics_json: serde_json::json!({
                "syntactic_analysis_id": syntax.map(|analysis| analysis.id.as_str()),
                "syntactic_provider": syntax.map(|analysis| &analysis.descriptor),
                "chunk_timeline_dependency": false
            })
            .into(),
            groups,
            created_at_ms: now,
            updated_at_ms: now,
        };
        if requested_status == TimelineStatus::Active {
            analysis.status = TimelineStatus::Candidate;
        }
        let analysis = self.sense_groups.save_sense_group_analysis(&analysis)?;
        if requested_status == TimelineStatus::Active {
            self.sense_groups
                .activate_sense_group_analysis(&analysis.id)
        } else {
            Ok(analysis)
        }
    }

    pub fn activate_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.sense_groups.activate_sense_group_analysis(id)
    }

    pub fn archive_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.sense_groups.archive_sense_group_analysis(id)
    }

    pub fn delete_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.sense_groups.delete_sense_group_analysis(id)
    }
}

fn sense_group_from_span(
    sentence: &SubtitleSentence,
    group_index: u32,
    span: &speech_analysis::audible_structure::SenseGroupSpan,
) -> SenseGroup {
    sense_group_from_span_fields(
        sentence,
        group_index,
        span.start_token_index,
        span.end_token_index,
        span.confidence,
        span.sources.clone(),
        span.label.clone(),
        span.head_token_index,
    )
}

fn sense_group_from_syntactic_span(
    sentence: &SubtitleSentence,
    group_index: u32,
    span: &SyntacticSenseGroupSpan,
) -> SenseGroup {
    sense_group_from_span_fields(
        sentence,
        group_index,
        span.start_token_index,
        span.end_token_index,
        span.confidence,
        span.sources.clone(),
        span.label.clone(),
        span.head_token_index,
    )
}

#[allow(clippy::too_many_arguments)]
fn sense_group_from_span_fields(
    sentence: &SubtitleSentence,
    group_index: u32,
    start_token_index: u32,
    end_token_index: u32,
    confidence: f32,
    sources: Vec<SenseGroupSource>,
    label: Option<String>,
    head_token_index: Option<u32>,
) -> SenseGroup {
    let matching_tokens: Vec<&SubtitleToken> = sentence
        .tokens
        .iter()
        .filter(|token| token.index >= start_token_index && token.index <= end_token_index)
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
            start_token_index,
            end_token_index
        ),
    );
    SenseGroup {
        id,
        sentence_id: sentence.id.clone(),
        group_index,
        start_token_index,
        end_token_index,
        text,
        confidence,
        sources,
        label,
        head_token_index,
    }
}

fn persist_sense_group_analysis_from_batch(
    repository: &dyn crate::SenseGroupRepository,
    track: &crate::SubtitleTrack,
    parent_word_timeline_id: Option<WordTimelineId>,
    batch: &SyntacticConsumerBatch,
) -> Result<Option<SenseGroupAnalysis>, ApplicationError> {
    let mut groups = Vec::new();
    let mut syntax_group_count = 0_u64;
    let mut fallback_group_count = 0_u64;
    for result in &batch.sentences {
        let sentence = track
            .sentences
            .iter()
            .find(|sentence| sentence.id == result.sentence_id)
            .ok_or(ApplicationError::Validation(
                "syntactic consumer batch sentence",
            ))?;
        for span in &result.sense_groups {
            if span.syntactic_analysis_id.is_some() {
                syntax_group_count += 1;
            } else {
                fallback_group_count += 1;
            }
            groups.push(sense_group_from_syntactic_span(
                sentence,
                groups.len() as u32,
                span,
            ));
        }
    }
    if groups.is_empty() {
        return Ok(None);
    }

    let has_syntax = syntax_group_count > 0;
    let (provider_id, provider_version, algorithm) = if has_syntax {
        (
            speech_analysis::audible_structure::SYNTAX_PROVIDER_ID,
            speech_analysis::audible_structure::SYNTAX_PROVIDER_VERSION,
            speech_analysis::audible_structure::SYNTAX_ALGORITHM,
        )
    } else {
        (
            speech_analysis::audible_structure::PROVIDER_ID,
            speech_analysis::audible_structure::PROVIDER_VERSION,
            speech_analysis::audible_structure::ALGORITHM,
        )
    };
    let fingerprint = format!(
        "{}:{}:{}:{}",
        track.id.as_str(),
        provider_id,
        provider_version,
        serde_json::to_string(&groups).unwrap_or_default()
    );
    let id = SenseGroupAnalysisId::from_fingerprint("sense-group-analysis", &fingerprint);
    if repository
        .active_sense_group_analysis(&track.id)?
        .is_some_and(|active| active.id == id)
    {
        return Ok(None);
    }

    let analyzed_sentence_count = batch
        .sentences
        .iter()
        .filter(|sentence| sentence.analysis.is_some())
        .count() as u64;
    let fallback_sentence_count = batch.sentences.len() as u64 - analyzed_sentence_count;
    let now = now_ms();
    let analysis = SenseGroupAnalysis {
        id,
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        parent_word_timeline_id,
        provider_id: provider_id.to_owned(),
        provider_version: provider_version.to_owned(),
        algorithm: algorithm.to_owned(),
        status: TimelineStatus::Candidate,
        created_by: TimelineCreator::Algorithm,
        metrics_json: serde_json::json!({
            "analyzed_sentence_count": analyzed_sentence_count,
            "fallback_sentence_count": fallback_sentence_count,
            "provider_source_counts": {
                speech_analysis::audible_structure::SYNTAX_PROVIDER_ID: syntax_group_count,
                speech_analysis::audible_structure::PROVIDER_ID: fallback_group_count,
            },
        })
        .into(),
        groups,
        created_at_ms: now,
        updated_at_ms: now,
    };
    let saved = repository.save_sense_group_analysis(&analysis)?;
    repository
        .activate_sense_group_analysis(&saved.id)
        .map(Some)
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

#[cfg(test)]
mod tests {
    use std::sync::Mutex;

    use domain::{
        LanguageCode, MediaId, SenseGroupSource, SubtitleSentenceId, SubtitleTokenKind,
        SubtitleTrack, SubtitleTrackStatus, SyntacticAnalysis, SyntacticAnalysisId,
        SyntacticProviderDescriptor, TimeMs,
    };

    use super::*;
    use crate::{
        SenseGroupRepository, SyntacticFallbackReason, SyntacticProductQualification,
        SyntacticSentenceConsumers,
    };

    #[derive(Default)]
    struct MemorySenseGroups {
        analyses: Mutex<Vec<SenseGroupAnalysis>>,
    }

    impl SenseGroupRepository for MemorySenseGroups {
        fn save_sense_group_analysis(
            &self,
            analysis: &SenseGroupAnalysis,
        ) -> Result<SenseGroupAnalysis, ApplicationError> {
            let mut analyses = self.analyses.lock().unwrap();
            if let Some(existing) = analyses.iter_mut().find(|item| item.id == analysis.id) {
                *existing = analysis.clone();
            } else {
                analyses.push(analysis.clone());
            }
            Ok(analysis.clone())
        }

        fn list_sense_group_analyses(
            &self,
            track_id: &SubtitleTrackId,
        ) -> Result<Vec<SenseGroupAnalysis>, ApplicationError> {
            Ok(self
                .analyses
                .lock()
                .unwrap()
                .iter()
                .filter(|analysis| analysis.track_id == *track_id)
                .cloned()
                .collect())
        }

        fn get_sense_group_analysis(
            &self,
            id: &SenseGroupAnalysisId,
        ) -> Result<Option<SenseGroupAnalysis>, ApplicationError> {
            Ok(self
                .analyses
                .lock()
                .unwrap()
                .iter()
                .find(|analysis| analysis.id == *id)
                .cloned())
        }

        fn active_sense_group_analysis(
            &self,
            track_id: &SubtitleTrackId,
        ) -> Result<Option<SenseGroupAnalysis>, ApplicationError> {
            Ok(self
                .analyses
                .lock()
                .unwrap()
                .iter()
                .find(|analysis| {
                    analysis.track_id == *track_id && analysis.status == TimelineStatus::Active
                })
                .cloned())
        }

        fn activate_sense_group_analysis(
            &self,
            id: &SenseGroupAnalysisId,
        ) -> Result<SenseGroupAnalysis, ApplicationError> {
            let mut analyses = self.analyses.lock().unwrap();
            let track_id = analyses
                .iter()
                .find(|analysis| analysis.id == *id)
                .map(|analysis| analysis.track_id.clone())
                .ok_or(ApplicationError::NotFound("sense group analysis"))?;
            for analysis in analyses.iter_mut().filter(|analysis| {
                analysis.track_id == track_id && analysis.status == TimelineStatus::Active
            }) {
                analysis.status = TimelineStatus::Candidate;
            }
            let selected = analyses
                .iter_mut()
                .find(|analysis| analysis.id == *id)
                .unwrap();
            selected.status = TimelineStatus::Active;
            Ok(selected.clone())
        }

        fn archive_sense_group_analysis(
            &self,
            id: &SenseGroupAnalysisId,
        ) -> Result<SenseGroupAnalysis, ApplicationError> {
            let mut analyses = self.analyses.lock().unwrap();
            let selected = analyses
                .iter_mut()
                .find(|analysis| analysis.id == *id)
                .ok_or(ApplicationError::NotFound("sense group analysis"))?;
            selected.status = TimelineStatus::Archived;
            Ok(selected.clone())
        }

        fn delete_sense_group_analysis(
            &self,
            id: &SenseGroupAnalysisId,
        ) -> Result<SenseGroupAnalysis, ApplicationError> {
            let mut analyses = self.analyses.lock().unwrap();
            let index = analyses
                .iter()
                .position(|analysis| analysis.id == *id)
                .ok_or(ApplicationError::NotFound("sense group analysis"))?;
            Ok(analyses.remove(index))
        }
    }

    fn sentence(id: &str, index: u32, text: &str) -> SubtitleSentence {
        let mut tokens = Vec::new();
        let mut token_index = 0;
        let mut cursor = 0;
        for (word_index, word) in text.split(' ').enumerate() {
            if word_index > 0 {
                tokens.push(SubtitleToken {
                    index: token_index,
                    kind: SubtitleTokenKind::Whitespace,
                    text: " ".into(),
                    normalized: None,
                    start_char: cursor,
                    end_char: cursor + 1,
                });
                token_index += 1;
                cursor += 1;
            }
            let end = cursor + word.len() as u32;
            tokens.push(SubtitleToken {
                index: token_index,
                kind: SubtitleTokenKind::Word,
                text: word.into(),
                normalized: Some(word.to_lowercase()),
                start_char: cursor,
                end_char: end,
            });
            token_index += 1;
            cursor = end;
        }
        SubtitleSentence {
            id: SubtitleSentenceId::parse(id).unwrap(),
            index,
            start: TimeMs::new(index as u64 * 1_000),
            end: TimeMs::new(index as u64 * 1_000 + 900),
            original_text: text.into(),
            display_text: text.into(),
            tokens,
        }
    }

    fn track() -> SubtitleTrack {
        SubtitleTrack {
            id: SubtitleTrackId::parse("track-sense-groups").unwrap(),
            media_id: MediaId::parse("media-sense-groups").unwrap(),
            fingerprint: "track-fingerprint".into(),
            language: None,
            source: "test".into(),
            status: SubtitleTrackStatus::Available,
            sentences: vec![
                sentence("sentence-one", 0, "We learn quickly"),
                sentence("sentence-two", 1, "Practice makes progress"),
            ],
        }
    }

    fn span(start: u32, end: u32, syntax_id: Option<&str>) -> SyntacticSenseGroupSpan {
        SyntacticSenseGroupSpan {
            start_token_index: start,
            end_token_index: end,
            sources: vec![if syntax_id.is_some() {
                SenseGroupSource::DependencyParse
            } else {
                SenseGroupSource::Rule
            }],
            confidence: if syntax_id.is_some() { 0.9 } else { 0.6 },
            label: syntax_id.map(|_| "clause".into()),
            head_token_index: syntax_id.map(|_| start),
            syntactic_analysis_id: syntax_id.map(|id| SyntacticAnalysisId::parse(id).unwrap()),
        }
    }

    fn sentence_result(
        sentence_id: &str,
        spans: Vec<SyntacticSenseGroupSpan>,
    ) -> SyntacticSentenceConsumers {
        let is_fallback = spans
            .iter()
            .all(|span| span.syntactic_analysis_id.is_none());
        let syntactic_analysis_id = spans
            .iter()
            .find_map(|span| span.syntactic_analysis_id.clone());
        SyntacticSentenceConsumers {
            sentence_id: SubtitleSentenceId::parse(sentence_id).unwrap(),
            analysis: (!is_fallback).then(|| SyntacticAnalysis {
                id: syntactic_analysis_id.unwrap(),
                contract_version: domain::SYNTACTIC_CONTRACT_VERSION,
                descriptor: SyntacticProviderDescriptor {
                    provider_id: "test-syntax".into(),
                    provider_version: "v1".into(),
                    runtime_id: "test".into(),
                    runtime_version: "v1".into(),
                    model_id: "test".into(),
                    model_version: "v1".into(),
                    model_checksum_sha256: "checksum".into(),
                },
                language: LanguageCode::parse("en").unwrap(),
                source_fingerprint: "source".into(),
                profile_fingerprint: "profile".into(),
                sentences: Vec::new(),
            }),
            validation: None,
            fallback_reason: is_fallback.then_some(SyntacticFallbackReason::ProviderNotConfigured),
            reference_b: Vec::new(),
            sense_groups: spans,
            dependency_matches: Vec::new(),
        }
    }

    fn batch(sentences: Vec<SyntacticSentenceConsumers>) -> SyntacticConsumerBatch {
        SyntacticConsumerBatch {
            descriptor: None,
            qualification: SyntacticProductQualification::corrected_v2(),
            probe_request_count: 0,
            analysis_request_count: 0,
            sentences,
        }
    }

    #[test]
    fn mixed_batch_persists_all_sentences_with_syntax_provider_and_metrics() {
        let repository = MemorySenseGroups::default();
        let track = track();
        let batch = batch(vec![
            sentence_result("sentence-one", vec![span(0, 2, Some("syntax-one"))]),
            sentence_result("sentence-two", vec![span(0, 4, None)]),
        ]);

        let analysis = persist_sense_group_analysis_from_batch(&repository, &track, None, &batch)
            .unwrap()
            .unwrap();

        assert_eq!(analysis.status, TimelineStatus::Active);
        assert_eq!(
            analysis.provider_id,
            speech_analysis::audible_structure::SYNTAX_PROVIDER_ID
        );
        assert_eq!(analysis.groups.len(), 2);
        assert_eq!(analysis.groups[0].sentence_id.as_str(), "sentence-one");
        assert_eq!(analysis.groups[1].sentence_id.as_str(), "sentence-two");
        let metrics = analysis.metrics_json.as_object();
        assert_eq!(metrics["analyzed_sentence_count"], 1);
        assert_eq!(metrics["fallback_sentence_count"], 1);
        assert_eq!(
            metrics["provider_source_counts"]
                [speech_analysis::audible_structure::SYNTAX_PROVIDER_ID],
            1
        );
        assert_eq!(
            metrics["provider_source_counts"][speech_analysis::audible_structure::PROVIDER_ID],
            1
        );
    }

    #[test]
    fn fallback_batch_uses_rule_provider() {
        let repository = MemorySenseGroups::default();
        let track = track();
        let batch = batch(vec![sentence_result(
            "sentence-one",
            vec![span(0, 4, None)],
        )]);

        let analysis = persist_sense_group_analysis_from_batch(&repository, &track, None, &batch)
            .unwrap()
            .unwrap();

        assert_eq!(
            analysis.provider_id,
            speech_analysis::audible_structure::PROVIDER_ID
        );
        assert_eq!(
            analysis.provider_version,
            speech_analysis::audible_structure::PROVIDER_VERSION
        );
        assert_eq!(
            analysis.algorithm,
            speech_analysis::audible_structure::ALGORITHM
        );
    }

    #[test]
    fn empty_batch_returns_none_without_writing() {
        let repository = MemorySenseGroups::default();
        let track = track();

        let result =
            persist_sense_group_analysis_from_batch(&repository, &track, None, &batch(Vec::new()))
                .unwrap();

        assert!(result.is_none());
        assert!(
            repository
                .list_sense_group_analyses(&track.id)
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn repeated_batch_returns_none_and_keeps_one_active_analysis() {
        let repository = MemorySenseGroups::default();
        let track = track();
        let batch = batch(vec![sentence_result(
            "sentence-one",
            vec![span(0, 4, Some("syntax-one"))],
        )]);

        assert!(
            persist_sense_group_analysis_from_batch(&repository, &track, None, &batch)
                .unwrap()
                .is_some()
        );
        assert!(
            persist_sense_group_analysis_from_batch(&repository, &track, None, &batch)
                .unwrap()
                .is_none()
        );
        let analyses = repository.list_sense_group_analyses(&track.id).unwrap();
        assert_eq!(analyses.len(), 1);
        assert_eq!(
            analyses
                .iter()
                .filter(|analysis| analysis.status == TimelineStatus::Active)
                .count(),
            1
        );
    }

    #[test]
    fn syntax_batch_takes_over_existing_fallback_active_analysis() {
        let repository = MemorySenseGroups::default();
        let track = track();
        let fallback = batch(vec![sentence_result(
            "sentence-one",
            vec![span(0, 4, None)],
        )]);
        let fallback_id =
            persist_sense_group_analysis_from_batch(&repository, &track, None, &fallback)
                .unwrap()
                .unwrap()
                .id;
        let syntax = batch(vec![sentence_result(
            "sentence-one",
            vec![span(0, 4, Some("syntax-one"))],
        )]);

        let syntax_analysis =
            persist_sense_group_analysis_from_batch(&repository, &track, None, &syntax)
                .unwrap()
                .unwrap();

        assert_ne!(syntax_analysis.id, fallback_id);
        assert_eq!(syntax_analysis.status, TimelineStatus::Active);
        let analyses = repository.list_sense_group_analyses(&track.id).unwrap();
        assert_eq!(analyses.len(), 2);
        assert_eq!(
            analyses
                .iter()
                .find(|analysis| analysis.id == fallback_id)
                .unwrap()
                .status,
            TimelineStatus::Candidate
        );
    }

    #[test]
    fn batch_fallback_mapping_matches_generate_without_syntax_mapping() {
        let repository = MemorySenseGroups::default();
        let track = track();
        let sentence = &track.sentences[0];
        let rule_spans = speech_analysis::audible_structure::partition_sentence(
            sentence,
            &[],
            &speech_analysis::audible_structure::SenseGroupPartitionConfig::default(),
        );
        let expected = rule_spans
            .iter()
            .enumerate()
            .map(|(index, span)| sense_group_from_span(sentence, index as u32, span))
            .collect::<Vec<_>>();
        let batch = batch(vec![sentence_result(
            "sentence-one",
            rule_spans.into_iter().map(Into::into).collect(),
        )]);

        let actual = persist_sense_group_analysis_from_batch(&repository, &track, None, &batch)
            .unwrap()
            .unwrap();

        assert_eq!(actual.groups, expected);
    }
}
