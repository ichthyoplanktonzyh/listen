use crate::batch_governor::{
    BackoffPolicy, BatchCancellationToken, BatchMetrics, CachedPartition, LlmBatchExecution,
    RequestGovernor, SentenceCache,
};
use crate::{
    ApplicationError, MediaAnalysisUseCases, SenseGroup, SenseGroupAnalysis, SenseGroupAnalysisId,
    SenseGroupAnalysisSummary, SenseGroupId, SenseGroupPartitionProvider,
    SenseGroupPartitionRequest, SenseGroupProtectedSpan, SenseGroupTokenInput, SubtitleSentence,
    SubtitleToken, SubtitleTrackId, SyntacticAnalysis, SyntacticConsumerBatch,
    SyntacticSenseGroupSpan, TimelineCreator, TimelineStatus, WordTimelineId, now_ms,
    validate_syntactic_analysis,
};
use domain::{LlmProviderError, SenseGroupSource, SubtitleTokenKind};
use futures_util::{StreamExt, stream};
use std::sync::Arc;

const LLM_PROVIDER_ID: &str = "llm-sense-group";
const LLM_ALGORITHM: &str = "hybrid_rule_llm_partition_v1";
// Per-task concurrency is a local ceiling; the account-level governor provides
// the global bound across all concurrent media tasks.
const LLM_TASK_CONCURRENCY: usize = 1000;
const LLM_SENSE_GROUP_PROMPT_CONTRACT: &str = "sense-group-partition-v1";

pub fn foundation_rule_sense_group_policy() -> (&'static str, &'static str, &'static str) {
    (
        speech_analysis::audible_structure::PROVIDER_ID,
        speech_analysis::audible_structure::PROVIDER_VERSION,
        speech_analysis::audible_structure::ALGORITHM,
    )
}

fn syntactic_complexity<'a>(
    analyses: impl Iterator<Item = &'a SyntacticAnalysis>,
) -> (Option<f32>, Option<f32>) {
    let mut max_depth = 0u32;
    let mut span_total = 0u64;
    let mut span_count = 0u32;
    let mut sentence_count = 0u32;
    for analysis in analyses {
        sentence_count += analysis.sentences.len() as u32;
        for sentence in &analysis.sentences {
            for token in &sentence.tokens {
                if let Some(head) = token.head_parser_token_index {
                    span_total += token.parser_token_index.abs_diff(head) as u64;
                    span_count += 1;
                }
                let mut current = token.parser_token_index;
                let mut depth = 0u32;
                let mut visited = std::collections::HashSet::new();
                while visited.insert(current) {
                    let Some(parent) = sentence
                        .tokens
                        .iter()
                        .find(|candidate| candidate.parser_token_index == current)
                        .and_then(|candidate| candidate.head_parser_token_index)
                    else {
                        break;
                    };
                    if parent == current {
                        break;
                    }
                    depth += 1;
                    current = parent;
                }
                max_depth = max_depth.max(depth);
            }
        }
    }
    (
        (sentence_count > 0).then_some(max_depth as f32),
        (span_count > 0).then_some(span_total as f32 / span_count as f32),
    )
}

struct LlmSentenceOutcome {
    sentence: SubtitleSentence,
    spans: Vec<speech_analysis::audible_structure::SenseGroupSpan>,
    used_llm: bool,
    retry_count: u64,
    prompt_version: Option<String>,
    reported_model: Option<String>,
}

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
        self.generate_sense_group_analysis_internal(track_id, requested_status, None, None)
    }

    /// Builds the deterministic rule partition with preparation provenance.
    pub fn generate_rule_sense_group_analysis(
        &self,
        track_id: &SubtitleTrackId,
        requested_status: Option<TimelineStatus>,
        preparation_input_fingerprint: &str,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        self.generate_sense_group_analysis_internal(
            track_id,
            requested_status,
            None,
            Some(preparation_input_fingerprint),
        )
    }

    /// Generates a candidate analysis through an LLM while keeping rules as a
    /// per-sentence fallback. Model output is boundary indices only; the
    /// server validates it against the immutable token snapshot and constructs
    /// the final spans, so malformed output can never corrupt coverage.
    ///
    /// The governor bounds account-wide in-flight requests; the cancellation
    /// token allows the caller to abort the batch; the sentence cache provides
    /// idempotency for resumed or repeated runs.
    pub async fn generate_sense_group_analysis_via_llm(
        &self,
        track_id: &SubtitleTrackId,
        requested_status: Option<TimelineStatus>,
        provider: &dyn SenseGroupPartitionProvider,
        execution: &LlmBatchExecution,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        let governor = execution.governor();
        let cancellation = execution.cancellation();
        let backoff = execution.backoff();
        let requested_status = requested_status.unwrap_or(TimelineStatus::Candidate);
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let config = speech_analysis::audible_structure::SenseGroupPartitionConfig::default();
        let descriptor = provider.descriptor();
        let cache = SentenceCache::new();
        let metrics = Arc::new(BatchMetrics::new());

        // Repository reads happen before remote work. Once prepared, every
        // sentence is independent and can safely share the provider seam.
        let mut prepared = Vec::with_capacity(track.sentences.len());
        for (sentence_order, sentence) in track.sentences.iter().enumerate() {
            let candidates = self.lexical_learning().phrase_candidates(&sentence.id)?;
            let fallback = speech_analysis::audible_structure::partition_sentence(
                sentence,
                &candidates,
                &config,
            );
            if fallback.is_empty() {
                continue;
            }
            let request =
                llm_partition_request(track.language.clone(), sentence, &candidates, &fallback);
            let request_snapshot = serde_json::to_vec(&request).map_err(|error| {
                ApplicationError::Repository(format!(
                    "failed to fingerprint LLM sentence request: {error}"
                ))
            })?;
            let checkpoint_fingerprint = SentenceCache::fingerprint(
                execution.provider_cache_scope(),
                LLM_SENSE_GROUP_PROMPT_CONTRACT,
                &request_snapshot,
            );
            if let Some(checkpoint) = self
                .sense_groups
                .get_llm_sentence_checkpoint(&checkpoint_fingerprint)?
            {
                cache.insert(checkpoint_fingerprint.clone(), checkpoint);
            }
            prepared.push((
                sentence_order,
                sentence.clone(),
                candidates,
                fallback,
                request,
                checkpoint_fingerprint,
            ));
        }

        cancellation.set_total_count(prepared.len() as u64)?;
        let task_concurrency = LLM_TASK_CONCURRENCY.max(1).min(prepared.len().max(1));
        let config_ref = &config;
        let governor_ref = governor;
        let cancel_ref = cancellation;
        let backoff_ref = backoff;
        let cache_ref = &cache;
        let metrics_ref = &metrics;

        let mut outcomes =
            stream::iter(prepared.into_iter().map(
                |(
                    sentence_order,
                    sentence,
                    candidates,
                    fallback,
                    request,
                    checkpoint_fingerprint,
                )| async move {
                    // Cancellation gate: skip dispatch if already cancelled.
                    if cancel_ref.is_cancelled() {
                        metrics_ref.record_cancelled();
                        return (
                            sentence_order,
                            Ok(LlmSentenceOutcome {
                                sentence,
                                spans: fallback,
                                used_llm: false,
                                retry_count: 0,
                                prompt_version: None,
                                reported_model: None,
                            }),
                        );
                    }
                    let outcome = partition_sentence_via_llm_governed(
                        provider,
                        sentence,
                        &candidates,
                        fallback,
                        request,
                        config_ref,
                        governor_ref,
                        cancel_ref,
                        backoff_ref,
                        cache_ref,
                        metrics_ref,
                        checkpoint_fingerprint,
                    )
                    .await;
                    (sentence_order, outcome)
                },
            ))
            .buffer_unordered(task_concurrency)
            .collect::<Vec<_>>()
            .await;
        // Completion order is deliberately irrelevant to persisted identity.
        outcomes.sort_by_key(|(sentence_order, _)| *sentence_order);

        let checkpointed_at_ms = now_ms();
        for (fingerprint, partition) in cache.snapshot() {
            self.sense_groups.save_llm_sentence_checkpoint(
                &fingerprint,
                &partition,
                checkpointed_at_ms,
            )?;
        }
        if !cancellation.begin_commit() {
            return Err(ApplicationError::Cancelled("LLM sense-group batch"));
        }

        let mut groups = Vec::new();
        let mut llm_sentence_count = 0_u64;
        let mut fallback_sentence_count = 0_u64;
        let mut retry_count = 0_u64;
        let mut prompt_versions = std::collections::BTreeSet::new();
        let mut reported_models = std::collections::BTreeSet::new();
        for (_, outcome) in outcomes {
            let outcome = outcome?;
            if outcome.used_llm {
                llm_sentence_count += 1;
            } else {
                fallback_sentence_count += 1;
            }
            retry_count += outcome.retry_count;
            if let Some(version) = outcome.prompt_version {
                prompt_versions.insert(version);
            }
            if let Some(model) = outcome.reported_model {
                reported_models.insert(model);
            }
            for span in outcome.spans {
                let group_index = groups.len() as u32;
                groups.push(sense_group_from_span(&outcome.sentence, group_index, &span));
            }
        }
        if groups.is_empty() {
            return Err(ApplicationError::Validation("sense group analysis groups"));
        }

        let provider_version = descriptor.model_id;
        let fingerprint = format!(
            "{}:{}:{}:{}:{}",
            track.id.as_str(),
            LLM_PROVIDER_ID,
            provider_version,
            LLM_ALGORITHM,
            serde_json::to_string(&groups).unwrap_or_default()
        );
        let now = now_ms();
        let governor_metrics = metrics.to_json();
        let mut analysis = SenseGroupAnalysis {
            id: SenseGroupAnalysisId::from_fingerprint("sense-group-analysis", &fingerprint),
            track_id: track.id.clone(),
            media_id: track.media_id.clone(),
            parent_word_timeline_id: self
                .word_timelines
                .active_word_timeline(track_id)?
                .map(|timeline| timeline.id),
            provider_id: LLM_PROVIDER_ID.into(),
            provider_version,
            algorithm: LLM_ALGORITHM.into(),
            status: requested_status,
            created_by: TimelineCreator::Algorithm,
            metrics_json: serde_json::json!({
                "llm_sentence_count": llm_sentence_count,
                "fallback_sentence_count": fallback_sentence_count,
                "retry_count": retry_count,
                "batch_sentence_count": llm_sentence_count + fallback_sentence_count,
                "task_concurrency": task_concurrency,
                "prompt_versions": prompt_versions,
                "reported_models": reported_models,
                "chunk_timeline_dependency": false,
                "governor": governor_metrics,
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
        preparation_input_fingerprint: Option<&str>,
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
            let (provider_id, provider_version, algorithm) = foundation_rule_sense_group_policy();
            (
                provider_id.to_owned(),
                provider_version.to_owned(),
                algorithm.to_owned(),
            )
        };
        let mut fingerprint = format!(
            "{}:{}:{}:{}",
            track.id.as_str(),
            provider_version,
            syntax
                .map(|analysis| analysis.id.as_str())
                .unwrap_or("none"),
            serde_json::to_string(&groups).unwrap_or_default()
        );
        if let Some(preparation_input_fingerprint) = preparation_input_fingerprint {
            fingerprint.push_str(":preparation:");
            fingerprint.push_str(preparation_input_fingerprint);
        }
        let (syntax_max_depth, syntax_mean_dependency_span) = syntax
            .map(|analysis| syntactic_complexity(std::iter::once(analysis)))
            .unwrap_or((None, None));
        let mut metrics = serde_json::json!({
            "syntactic_analysis_id": syntax.map(|analysis| analysis.id.as_str()),
            "syntactic_provider": syntax.map(|analysis| &analysis.descriptor),
            "syntax_max_depth": syntax_max_depth,
            "syntax_mean_dependency_span": syntax_mean_dependency_span,
            "chunk_timeline_dependency": false
        });
        if let Some(fingerprint) = preparation_input_fingerprint {
            metrics["preparation_input_fingerprint"] =
                serde_json::Value::String(fingerprint.into());
        }
        let mut analysis = SenseGroupAnalysis {
            id: SenseGroupAnalysisId::from_fingerprint("sense-group-analysis", &fingerprint),
            track_id: track.id.clone(),
            media_id: track.media_id.clone(),
            parent_word_timeline_id: None,
            provider_id,
            provider_version,
            algorithm,
            status: requested_status,
            created_by: TimelineCreator::Algorithm,
            metrics_json: metrics.into(),
            groups,
            created_at_ms: now,
            updated_at_ms: now,
        };
        if requested_status == TimelineStatus::Active {
            analysis.status = TimelineStatus::Candidate;
        }
        let analysis = self.sense_groups.save_sense_group_analysis(&analysis)?;
        if preparation_input_fingerprint.is_some() {
            let active = self
                .sense_groups
                .activate_sense_group_analysis_if_absent(&analysis.id)?;
            if active.id == analysis.id {
                Ok(active)
            } else {
                Ok(analysis)
            }
        } else if requested_status == TimelineStatus::Active {
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

/// Governor-aware per-sentence LLM partition with backoff, cache, and
/// cancellation. Acquires a permit from the shared governor before each
/// attempt, respects Retry-After via the backoff policy, and checks the
/// sentence cache for idempotent results.
#[allow(clippy::too_many_arguments)]
async fn partition_sentence_via_llm_governed(
    provider: &dyn SenseGroupPartitionProvider,
    sentence: SubtitleSentence,
    candidates: &[domain::PhraseCandidate],
    fallback: Vec<speech_analysis::audible_structure::SenseGroupSpan>,
    request: SenseGroupPartitionRequest,
    config: &speech_analysis::audible_structure::SenseGroupPartitionConfig,
    governor: &RequestGovernor,
    cancellation: &BatchCancellationToken,
    backoff: &BackoffPolicy,
    cache: &SentenceCache,
    metrics: &Arc<BatchMetrics>,
    fingerprint: String,
) -> Result<LlmSentenceOutcome, ApplicationError> {
    // Check sentence cache first (idempotency for resumed batches).
    if let Some(cached) = cache.get(&fingerprint) {
        metrics.record_cache_hit();
        if let Ok(spans) = spans_from_llm_boundaries(
            &sentence,
            candidates,
            &cached.boundary_after_token_indices,
            config,
        ) {
            cancellation.record_completion()?;
            return Ok(LlmSentenceOutcome {
                sentence,
                spans,
                used_llm: true,
                retry_count: 0,
                prompt_version: cached.prompt_version,
                reported_model: cached.model_id,
            });
        }
        // Cached result failed validation (stale); fall through to live call.
    }
    metrics.record_cache_miss();

    let mut attempt = 0_u32;
    let mut prompt_version = None;
    let mut reported_model = None;
    loop {
        // Cancellation check before each attempt.
        if cancellation.is_cancelled() {
            metrics.record_cancelled();
            break;
        }

        // Acquire governor permit (bounds account-wide in-flight).
        let Some(permit) = governor.acquire(cancellation, metrics).await else {
            metrics.record_cancelled();
            break;
        };

        let started = std::time::Instant::now();
        let provider_result = provider.partition_sense_groups(&request).await;
        metrics.record_latency(started.elapsed().as_millis() as u64);
        drop(permit);
        match provider_result {
            Ok(draft) => {
                prompt_version = draft.prompt_version;
                reported_model = draft.model_id;
                match spans_from_llm_boundaries(
                    &sentence,
                    candidates,
                    &draft.boundary_after_token_indices,
                    config,
                ) {
                    Ok(spans) => {
                        // Cache the successful result.
                        cache.insert(
                            fingerprint,
                            CachedPartition {
                                boundary_after_token_indices: draft.boundary_after_token_indices,
                                model_id: reported_model.clone(),
                                prompt_version: prompt_version.clone(),
                            },
                        );
                        cancellation.record_completion()?;
                        return Ok(LlmSentenceOutcome {
                            sentence,
                            spans,
                            used_llm: true,
                            retry_count: attempt as u64,
                            prompt_version,
                            reported_model,
                        });
                    }
                    Err(_) if backoff.should_retry(attempt) => {
                        let delay = backoff.delay_for_attempt(attempt, None);
                        attempt += 1;
                        metrics.record_retry();
                        if sleep_or_cancel(delay, cancellation).await {
                            metrics.record_cancelled();
                            break;
                        }
                    }
                    Err(_) => break,
                }
            }
            Err(error) => {
                if let LlmProviderError::RateLimit { retry_after_ms } = &error {
                    metrics.record_rate_limit();
                    if backoff.should_retry(attempt) {
                        let delay = backoff.delay_for_attempt(attempt, *retry_after_ms);
                        attempt += 1;
                        metrics.record_retry();
                        if sleep_or_cancel(delay, cancellation).await {
                            metrics.record_cancelled();
                            break;
                        }
                        continue;
                    }
                } else if retryable_sense_group_error(&error) && backoff.should_retry(attempt) {
                    let delay = backoff.delay_for_attempt(attempt, None);
                    attempt += 1;
                    metrics.record_retry();
                    if sleep_or_cancel(delay, cancellation).await {
                        metrics.record_cancelled();
                        break;
                    }
                    continue;
                }
                break;
            }
        }
    }
    if !cancellation.is_cancelled() {
        metrics.record_fallback();
    }
    Ok(LlmSentenceOutcome {
        sentence,
        spans: fallback,
        used_llm: false,
        retry_count: attempt as u64,
        prompt_version,
        reported_model,
    })
}

async fn sleep_or_cancel(
    delay: std::time::Duration,
    cancellation: &BatchCancellationToken,
) -> bool {
    tokio::select! {
        _ = cancellation.cancelled() => true,
        _ = tokio::time::sleep(delay) => false,
    }
}

fn retryable_sense_group_error(error: &LlmProviderError) -> bool {
    matches!(
        error,
        LlmProviderError::Offline
            | LlmProviderError::RateLimit { .. }
            | LlmProviderError::Timeout
            | LlmProviderError::Truncated
            | LlmProviderError::SchemaInvalid { .. }
            | LlmProviderError::Protocol { .. }
    )
}

fn token_kind_name(kind: SubtitleTokenKind) -> &'static str {
    match kind {
        SubtitleTokenKind::Word => "word",
        SubtitleTokenKind::Whitespace => "whitespace",
        SubtitleTokenKind::Punctuation => "punctuation",
        SubtitleTokenKind::Other => "other",
    }
}

fn llm_partition_request(
    language: Option<domain::LanguageCode>,
    sentence: &SubtitleSentence,
    phrases: &[domain::PhraseCandidate],
    fallback: &[speech_analysis::audible_structure::SenseGroupSpan],
) -> SenseGroupPartitionRequest {
    let final_word_index = sentence
        .tokens
        .iter()
        .rev()
        .find(|token| token.kind == SubtitleTokenKind::Word)
        .map(|token| token.index);
    SenseGroupPartitionRequest {
        language,
        source_text: sentence.display_text.clone(),
        tokens: sentence
            .tokens
            .iter()
            .map(|token| SenseGroupTokenInput {
                index: token.index,
                text: token.text.clone(),
                kind: token_kind_name(token.kind).into(),
            })
            .collect(),
        protected_spans: phrases
            .iter()
            .map(|phrase| SenseGroupProtectedSpan {
                start_token_index: phrase.token_start,
                end_token_index: phrase.token_end,
            })
            .collect(),
        candidate_boundary_after_token_indices: fallback
            .iter()
            .map(|span| span.end_token_index)
            .filter(|index| Some(*index) != final_word_index)
            .collect(),
    }
}

fn spans_from_llm_boundaries(
    sentence: &SubtitleSentence,
    phrases: &[domain::PhraseCandidate],
    boundaries: &[u32],
    config: &speech_analysis::audible_structure::SenseGroupPartitionConfig,
) -> Result<Vec<speech_analysis::audible_structure::SenseGroupSpan>, &'static str> {
    let word_indices = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .map(|token| token.index)
        .collect::<Vec<_>>();
    let Some(&final_word_index) = word_indices.last() else {
        return Ok(Vec::new());
    };
    if boundaries.windows(2).any(|pair| pair[0] >= pair[1]) {
        return Err("boundaries must be strictly increasing");
    }
    for &boundary in boundaries {
        if boundary == final_word_index || !word_indices.contains(&boundary) {
            return Err("boundary must name a non-final word token");
        }
        if phrases
            .iter()
            .any(|phrase| boundary >= phrase.token_start && boundary < phrase.token_end)
        {
            return Err("boundary splits a protected phrase");
        }
    }

    let mut spans = Vec::with_capacity(boundaries.len() + 1);
    let mut start_position = 0_usize;
    for &boundary in boundaries.iter().chain(std::iter::once(&final_word_index)) {
        let end_position = word_indices
            .iter()
            .position(|index| *index == boundary)
            .ok_or("boundary did not resolve to a word")?;
        if end_position < start_position {
            return Err("boundary order produced an empty span");
        }
        let word_count = end_position - start_position + 1;
        if word_count > config.hard_max_words.saturating_mul(2) {
            return Err("sense group exceeds the safety length limit");
        }
        spans.push(speech_analysis::audible_structure::SenseGroupSpan {
            start_token_index: word_indices[start_position],
            end_token_index: boundary,
            sources: vec![SenseGroupSource::LanguageModel],
            confidence: 0.8,
            label: None,
            head_token_index: None,
        });
        start_position = end_position + 1;
    }
    if start_position != word_indices.len() {
        return Err("sense groups did not cover every word");
    }
    Ok(spans)
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
    let (syntax_max_depth, syntax_mean_dependency_span) = syntactic_complexity(
        batch
            .sentences
            .iter()
            .filter_map(|sentence| sentence.analysis.as_ref()),
    );
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
            "syntax_max_depth": syntax_max_depth,
            "syntax_mean_dependency_span": syntax_mean_dependency_span,
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
        checkpoints: Mutex<std::collections::HashMap<String, CachedPartition>>,
    }

    impl SenseGroupRepository for MemorySenseGroups {
        fn get_llm_sentence_checkpoint(
            &self,
            fingerprint: &str,
        ) -> Result<Option<CachedPartition>, ApplicationError> {
            Ok(self.checkpoints.lock().unwrap().get(fingerprint).cloned())
        }

        fn save_llm_sentence_checkpoint(
            &self,
            fingerprint: &str,
            partition: &CachedPartition,
            _updated_at_ms: u64,
        ) -> Result<(), ApplicationError> {
            self.checkpoints
                .lock()
                .unwrap()
                .insert(fingerprint.to_string(), partition.clone());
            Ok(())
        }

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

        fn activate_sense_group_analysis_if_absent(
            &self,
            id: &SenseGroupAnalysisId,
        ) -> Result<SenseGroupAnalysis, ApplicationError> {
            let mut analyses = self.analyses.lock().unwrap();
            let selected = analyses
                .iter()
                .find(|analysis| analysis.id == *id)
                .cloned()
                .ok_or(ApplicationError::NotFound("sense group analysis"))?;
            if selected.status == TimelineStatus::Archived {
                return Err(ApplicationError::Validation(
                    "archived sense group analysis",
                ));
            }
            if let Some(active) = analyses
                .iter()
                .find(|analysis| {
                    analysis.track_id == selected.track_id
                        && analysis.status == TimelineStatus::Active
                })
                .cloned()
            {
                return Ok(active);
            }
            if selected.status != TimelineStatus::Candidate {
                return Err(ApplicationError::Validation(
                    "sense group analysis activation candidate",
                ));
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

    #[test]
    fn llm_boundaries_build_contiguous_server_owned_spans() {
        let sentence = sentence(
            "llm-valid",
            0,
            "When practice becomes regular learners make steady progress",
        );
        let config = speech_analysis::audible_structure::SenseGroupPartitionConfig::default();
        let spans = spans_from_llm_boundaries(&sentence, &[], &[4, 8], &config).unwrap();

        assert_eq!(
            spans
                .iter()
                .map(|span| (span.start_token_index, span.end_token_index))
                .collect::<Vec<_>>(),
            vec![(0, 4), (6, 8), (10, 14)]
        );
        assert!(spans.iter().all(|span| {
            span.sources == vec![SenseGroupSource::LanguageModel]
                && (span.confidence - 0.8).abs() < f32::EPSILON
        }));
    }

    #[test]
    fn llm_boundary_cannot_split_a_protected_phrase() {
        let sentence = sentence(
            "llm-protected",
            0,
            "We should take care of this problem today",
        );
        let phrase = domain::PhraseCandidate {
            canonical_form: "take care of".into(),
            display_form: "take care of".into(),
            normalized_form: "take care of".into(),
            token_start: 4,
            token_end: 8,
            reason: "test".into(),
        };
        let result = spans_from_llm_boundaries(
            &sentence,
            &[phrase],
            &[6],
            &speech_analysis::audible_structure::SenseGroupPartitionConfig::default(),
        );
        assert_eq!(result, Err("boundary splits a protected phrase"));
    }

    #[test]
    fn llm_boundaries_reject_duplicates_unknown_tokens_and_final_boundary() {
        let sentence = sentence("llm-invalid", 0, "one two three four");
        let config = speech_analysis::audible_structure::SenseGroupPartitionConfig::default();

        assert!(spans_from_llm_boundaries(&sentence, &[], &[2, 2], &config).is_err());
        assert!(spans_from_llm_boundaries(&sentence, &[], &[1], &config).is_err());
        assert!(spans_from_llm_boundaries(&sentence, &[], &[6], &config).is_err());
    }
}
