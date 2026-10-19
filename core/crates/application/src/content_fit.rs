use std::collections::HashMap;

use crate::{
    ApplicationError, ColdStartWordCandidate, LanguageCode, LearningStatus, LexicalEntryKind,
    MediaAnalysisUseCases, SubtitleSentenceId, SubtitleTokenKind, SubtitleTrack, SubtitleTrackId,
    WordTiming, now_ms,
};
use domain::{
    CALIBRATION_SAMPLE_MIN_FEEDBACK, CONTENT_FIT_ALGORITHM_VERSION, CalibrationSample,
    ContentDifficultyProfile, ContentFitFeatureSnapshot, ContentFitWeights, FeatureCoverage,
    FitEvidenceGrade, LLTimelineDocument, MeaningFitInputs, SenseGroupAnalysis, SoundFitInputs,
    TimingSource, apply_sound_fit_calibration, calibration_observed_difficulty,
    content_fit_fingerprint, meaning_fit, sound_fit, sound_fit_calibration_outcome,
    weighted_meaning_fit, weighted_sound_fit,
};

struct PhraseFeatures {
    expression_density: Option<f32>,
    unknown_density: Option<f32>,
    unassessed_density: Option<f32>,
}

impl MediaAnalysisUseCases {
    /// Cached read path: returns the stored profile when its fingerprint
    /// still matches the current inputs, otherwise recomputes and saves.
    /// The fingerprint check is cheap (no transcript normalization, no
    /// document assembly); a vocabulary change anywhere in the language
    /// invalidates every cached profile of that language — coarse but never
    /// stale (ADR 0018 decision 5).
    pub fn content_fit_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<ContentDifficultyProfile, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let language = track
            .language
            .clone()
            .ok_or(ApplicationError::Validation("subtitle track language"))?;
        let fingerprint = self.content_fit_input_fingerprint(track_id, &track, &language)?;
        if let Some(cached) = self
            .difficulty
            .get_difficulty_profile("media", track.media_id.as_str())?
            && cached.input_fingerprint == fingerprint
            && cached.algorithm_version == CONTENT_FIT_ALGORITHM_VERSION
        {
            return Ok(cached);
        }
        let profile = self.compute_content_fit_for_track(track_id)?;
        self.difficulty.save_difficulty_profile(&profile)
    }

    /// Canonical input identity for cache invalidation: algorithm version,
    /// track content, active word timeline, active prosody analysis, and the
    /// language-wide vocabulary watermark. Must stay the single composition
    /// point shared by the cached and compute paths.
    fn content_fit_input_fingerprint(
        &self,
        track_id: &SubtitleTrackId,
        track: &SubtitleTrack,
        language: &LanguageCode,
    ) -> Result<String, ApplicationError> {
        let word_timeline = self.word_timelines.active_word_timeline(track_id)?;
        let prosody_analysis = self.prosody.active_prosody_analysis(track_id)?;
        let sense_groups = self.sense_groups.active_sense_group_analysis(track_id)?;
        let (vocab_count, vocab_watermark_ms) = self
            .lexical_entries
            .lexical_vocabulary_watermark(language)?;
        // The calibration watermark makes new usage feedback invalidate the
        // cached profile; the record itself is durable evidence and is never
        // touched by recomputes (Slice 7).
        let calibration_watermark_ms = self
            .difficulty
            .get_fit_calibration("media", track.media_id.as_str())?
            .map(|calibration| calibration.updated_at_ms)
            .unwrap_or(0);
        let canonical_input = format!(
            "{}|lang:{}|track:{}:{}|wt:{}:{}|pa:{}:{}|sg:{}:{}|vocab:{}:{}|cal:{}",
            CONTENT_FIT_ALGORITHM_VERSION,
            language.as_str(),
            track.id.as_str(),
            track.fingerprint,
            word_timeline.as_ref().map(|t| t.id.as_str()).unwrap_or(""),
            word_timeline.as_ref().map(|t| t.updated_at_ms).unwrap_or(0),
            prosody_analysis
                .as_ref()
                .map(|a| a.id.as_str())
                .unwrap_or(""),
            prosody_analysis
                .as_ref()
                .map(|a| a.updated_at_ms)
                .unwrap_or(0),
            sense_groups.as_ref().map(|a| a.id.as_str()).unwrap_or(""),
            sense_groups.as_ref().map(|a| a.updated_at_ms).unwrap_or(0),
            vocab_count,
            vocab_watermark_ms,
            calibration_watermark_ms,
        );
        Ok(content_fit_fingerprint(&canonical_input))
    }

    /// Computes the media-level dual-dimension content fit profile from a
    /// track's transcript, timelines, and the learner's vocabulary profile
    /// (ADR 0018). Deterministic in (timeline document, vocabulary snapshot,
    /// algorithm version); `input_fingerprint` captures those identities so
    /// persistence can reuse cached profiles until an input changes.
    ///
    /// Meaning knowledge is read through `LexicalEntry::status`, the
    /// documented conservative compat view of the four-channel profile's
    /// effective assessments (`legacy_status_view`), so overrides are already
    /// folded in and no per-entry profile fan-out is needed.
    ///
    /// v3 (Issue #94): builds a full feature snapshot, uses weighted banding,
    /// and persists both the snapshot and its coverage summary.
    pub fn compute_content_fit_for_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<ContentDifficultyProfile, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let language = track
            .language
            .clone()
            .ok_or(ApplicationError::Validation("subtitle track language"))?;
        let input_fingerprint = self.content_fit_input_fingerprint(track_id, &track, &language)?;
        let document = self.export_lltimeline_document(track_id)?;

        // Count word tokens per normalized lexical key. Tokens that normalize
        // to nothing (bare digits, stray symbols the tokenizer still labels
        // Word) are not lexical learning targets and stay out of both the
        // numerator and the denominator.
        let mut normalized_by_raw: HashMap<String, Option<String>> = HashMap::new();
        let mut token_counts_by_key: HashMap<String, u32> = HashMap::new();
        let mut lexical_token_total: u32 = 0;
        for segment in &document.segments {
            for token in &segment.tokens {
                if token.kind != SubtitleTokenKind::Word {
                    continue;
                }
                let key = match normalized_by_raw.get(&token.text) {
                    Some(cached) => cached.clone(),
                    None => {
                        let normalized = self
                            .lexical_learning()
                            .normalize_lexical_form(language.as_str(), &token.text)?
                            .normalized;
                        let value = (!normalized.is_empty()).then_some(normalized);
                        normalized_by_raw.insert(token.text.clone(), value.clone());
                        value
                    }
                };
                let Some(key) = key else { continue };
                lexical_token_total += 1;
                *token_counts_by_key.entry(key).or_default() += 1;
            }
        }
        if lexical_token_total == 0 {
            return Err(ApplicationError::Validation("track word tokens"));
        }

        let keys: Vec<String> = token_counts_by_key.keys().cloned().collect();
        let entries = self.lexical_entries.lexical_entries_by_keys(
            &language,
            LexicalEntryKind::Word,
            &keys,
        )?;
        let status_by_key: HashMap<&str, Option<LearningStatus>> = entries
            .iter()
            .map(|entry| (entry.normalized_form.as_str(), entry.status))
            .collect();

        let mut unknown_tokens: u32 = 0;
        let mut unassessed_tokens: u32 = 0;
        let mut known_not_recognized_tokens: u32 = 0;
        for (key, count) in &token_counts_by_key {
            match status_by_key.get(key.as_str()).copied().flatten() {
                None => unassessed_tokens += count,
                Some(LearningStatus::UnknownMeaning) => unknown_tokens += count,
                Some(LearningStatus::KnownNotRecognized) => known_not_recognized_tokens += count,
                Some(LearningStatus::KnownRecognized) => {}
            }
        }
        let total = lexical_token_total as f32;
        let unknown_meaning_density = unknown_tokens as f32 / total;
        let unassessed_density = unassessed_tokens as f32 / total;
        let known_not_recognized_density = known_not_recognized_tokens as f32 / total;

        let active_word_timeline = document
            .active_word_timeline_id
            .as_ref()
            .and_then(|id| document.word_timelines.iter().find(|t| &t.id == id));
        let speech_rate =
            active_word_timeline.and_then(|timeline| speech_rate_wpm(&timeline.words));

        let (weak_form_density, compression_density) = if document.rhythm_frames.is_empty() {
            (None, None)
        } else {
            let weak_groups: usize = document
                .rhythm_frames
                .iter()
                .map(|frame| frame.rhythm_frame.weak_groups.len())
                .sum();
            let compression_spans: usize = document
                .rhythm_frames
                .iter()
                .map(|frame| frame.rhythm_frame.compression_spans.len())
                .sum();
            (
                Some(weak_groups as f32 / total),
                Some(compression_spans as f32 / total),
            )
        };

        let active_prosody = document
            .active_prosody_analysis_id
            .as_ref()
            .and_then(|id| document.prosody_analyses.iter().find(|a| &a.id == id));
        let mean_chunk_length = active_prosody.and_then(|analysis| {
            if analysis.chunks.is_empty() {
                return None;
            }
            let words: u32 = analysis
                .chunks
                .iter()
                .map(|chunk| {
                    chunk
                        .end_token_index
                        .saturating_sub(chunk.start_token_index)
                        + 1
                })
                .sum();
            Some(words as f32 / analysis.chunks.len() as f32)
        });

        // -- v3 sense-group features (Issue #94) --
        let active_sg = document
            .active_sense_group_analysis_id
            .as_ref()
            .and_then(|id| document.sense_group_analyses.iter().find(|a| &a.id == id));
        let (mean_sense_group_length, sense_group_density) =
            extract_sense_group_features(active_sg, &document);
        let phrase_features = self.extract_phrase_features(&document, &language, total)?;

        // Syntax facts are persisted with the sense-group analysis that
        // consumed the validated parser output. Older/rule-only analyses
        // degrade to missing evidence.
        let (syntax_depth, mean_dependency_span) = extract_syntax_features(active_sg);

        // -- v3 pause ratio --
        let pause_ratio =
            active_word_timeline.and_then(|timeline| compute_pause_ratio(&timeline.words));

        // -- v3 subtitle timing quality --
        let subtitle_timing_quality =
            active_word_timeline.map(|timeline| compute_subtitle_timing_quality(&timeline.words));

        // Replay and lookup actions are not yet persisted with an authoritative
        // media identity. Keep both absent instead of substituting unrelated
        // learning events; FeatureCoverage makes the degradation explicit.
        let media_id = document.metadata.media.id.as_str().to_owned();
        let replay_density = None;
        let lookup_density = None;

        let assessed_token_ratio = 1.0 - unassessed_density;

        // Build the v3 feature snapshot.
        let snapshot = ContentFitFeatureSnapshot {
            unknown_meaning_density,
            unassessed_density,
            known_not_recognized_density,
            speech_rate_wpm: speech_rate,
            weak_form_density,
            compression_density,
            mean_chunk_length,
            mean_sense_group_length,
            sense_group_density,
            multi_word_expression_density: phrase_features.expression_density,
            unknown_phrase_density: phrase_features.unknown_density,
            unassessed_phrase_density: phrase_features.unassessed_density,
            syntax_depth,
            mean_dependency_span,
            pause_ratio,
            replay_density,
            lookup_density,
            subtitle_timing_quality,
            assessed_token_ratio,
        };

        let coverage = FeatureCoverage::compute(&snapshot);
        let weights = ContentFitWeights::default();

        // v3 weighted banding.
        let meaning = weighted_meaning_fit(&snapshot, &weights);
        let mut sound = weighted_sound_fit(&snapshot, &weights);

        // Usage-feedback calibration (Slice 7): the recorded correction term
        // shifts only the presented band and appends its own signals; the
        // material signals above stay raw. Only this path may report
        // `usage_calibrated` (ADR 0018 decision 1).
        let mut evidence_grade = FitEvidenceGrade::InitialEstimate;
        if let Some(calibration) = self.difficulty.get_fit_calibration("media", &media_id)? {
            let outcome = sound_fit_calibration_outcome(&calibration);
            if outcome.informative {
                sound = apply_sound_fit_calibration(sound, &outcome);
                evidence_grade = FitEvidenceGrade::UsageCalibrated;
            }
        }

        Ok(ContentDifficultyProfile {
            subject_kind: "media".into(),
            subject_id: media_id,
            language,
            meaning,
            sound,
            assessed_token_ratio,
            evidence_grade,
            algorithm_version: CONTENT_FIT_ALGORITHM_VERSION.into(),
            computed_at_ms: now_ms(),
            input_fingerprint,
            feature_snapshot: Some(snapshot),
            feature_coverage: Some(coverage),
        })
    }

    fn extract_phrase_features(
        &self,
        document: &LLTimelineDocument,
        language: &LanguageCode,
        total_word_tokens: f32,
    ) -> Result<PhraseFeatures, ApplicationError> {
        let mut occurrences_by_key = HashMap::<String, u32>::new();
        let mut covered_word_tokens = std::collections::HashSet::<(SubtitleSentenceId, u32)>::new();
        for segment in &document.segments {
            for candidate in self.lexical_learning().phrase_candidates(&segment.id)? {
                *occurrences_by_key
                    .entry(candidate.normalized_form)
                    .or_default() += 1;
                for token in &segment.tokens {
                    if token.kind == SubtitleTokenKind::Word
                        && token.index >= candidate.token_start
                        && token.index <= candidate.token_end
                    {
                        covered_word_tokens.insert((segment.id.clone(), token.index));
                    }
                }
            }
        }
        if occurrences_by_key.is_empty() {
            return Ok(PhraseFeatures {
                expression_density: None,
                unknown_density: None,
                unassessed_density: None,
            });
        }

        let keys = occurrences_by_key.keys().cloned().collect::<Vec<_>>();
        let entries = self.lexical_entries.lexical_entries_by_keys(
            language,
            LexicalEntryKind::Phrase,
            &keys,
        )?;
        let status_by_key = entries
            .iter()
            .map(|entry| (entry.normalized_form.as_str(), entry.status))
            .collect::<HashMap<_, _>>();
        let mut unknown = 0u32;
        let mut unassessed = 0u32;
        let total_occurrences = occurrences_by_key.values().sum::<u32>();
        for (key, count) in &occurrences_by_key {
            match status_by_key.get(key.as_str()).copied().flatten() {
                Some(LearningStatus::UnknownMeaning) => unknown += count,
                None => unassessed += count,
                Some(_) => {}
            }
        }
        Ok(PhraseFeatures {
            expression_density: (total_word_tokens > 0.0)
                .then_some(covered_word_tokens.len() as f32 / total_word_tokens),
            unknown_density: Some(unknown as f32 / total_occurrences as f32),
            unassessed_density: Some(unassessed as f32 / total_occurrences as f32),
        })
    }

    /// Export calibration samples for all media that have sufficient user
    /// feedback. Each sample pairs the v3 feature snapshot with the observed
    /// user difficulty from comprehension reports and practice accuracy.
    pub fn export_calibration_samples(
        &self,
        language: Option<&LanguageCode>,
    ) -> Result<Vec<CalibrationSample>, ApplicationError> {
        let weights = ContentFitWeights::default();
        let mut samples = Vec::new();
        let mut seen_media = std::collections::HashSet::new();
        for media in self.media.list()? {
            if !seen_media.insert(media.id.clone()) {
                continue;
            }
            let Some(track) = self
                .subtitle_tracks
                .list_tracks_for_media(&media.id)?
                .into_iter()
                .find(|track| {
                    track.language.is_some()
                        && language.is_none_or(|expected| track.language.as_ref() == Some(expected))
                })
            else {
                continue;
            };
            let calibration = self
                .difficulty
                .get_fit_calibration("media", track.media_id.as_str())?;
            let Some(cal) = calibration else { continue };

            // Only include media with sufficient feedback.
            let feedback_total = cal.reports_understood_all
                + cal.reports_got_the_gist
                + cal.reports_unclear
                + cal.practice_attempts;
            if feedback_total < CALIBRATION_SAMPLE_MIN_FEEDBACK {
                continue;
            }
            let Some(observed_difficulty) = calibration_observed_difficulty(&cal) else {
                continue;
            };

            // Compute or retrieve the current profile.
            let profile = match self.content_fit_for_track(&track.id) {
                Ok(p) => p,
                Err(_) => continue,
            };
            let Some(snapshot) = profile.feature_snapshot else {
                continue;
            };
            let predicted_meaning = weighted_meaning_fit(&snapshot, &weights);
            let predicted_sound = weighted_sound_fit(&snapshot, &weights);
            let v2_meaning = meaning_fit(MeaningFitInputs {
                unknown_meaning_density: snapshot.unknown_meaning_density,
                unassessed_density: snapshot.unassessed_density,
            });
            let v2_sound = sound_fit(SoundFitInputs {
                known_not_recognized_density: snapshot.known_not_recognized_density,
                speech_rate_wpm: snapshot.speech_rate_wpm,
                weak_form_density: snapshot.weak_form_density,
                compression_density: snapshot.compression_density,
                mean_chunk_length: snapshot.mean_chunk_length,
            });

            samples.push(CalibrationSample {
                subject_kind: "media".into(),
                subject_id: track.media_id.as_str().to_owned(),
                language: profile.language,
                snapshot,
                predicted_meaning_score: predicted_meaning.score.unwrap_or(0.0),
                predicted_sound_score: predicted_sound.score.unwrap_or(0.0),
                predicted_meaning_band: predicted_meaning.fit,
                predicted_sound_band: predicted_sound.fit,
                v2_meaning_band: v2_meaning.fit,
                v2_sound_band: v2_sound.fit,
                observed_difficulty: Some(observed_difficulty),
                reports_understood_all: cal.reports_understood_all,
                reports_got_the_gist: cal.reports_got_the_gist,
                reports_unclear: cal.reports_unclear,
                practice_attempts: cal.practice_attempts,
                practice_correct: cal.practice_correct,
                sampled_at_ms: now_ms(),
            });
        }

        Ok(samples)
    }

    pub fn cold_start_word_candidates(
        &self,
        track_id: &SubtitleTrackId,
        limit: u32,
    ) -> Result<Vec<ColdStartWordCandidate>, ApplicationError> {
        let limit = limit.min(50);
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let language = track
            .language
            .clone()
            .ok_or(ApplicationError::Validation("subtitle track language"))?;

        let mut normalized_by_raw: HashMap<String, Option<String>> = HashMap::new();
        let mut token_counts_by_key: HashMap<String, u32> = HashMap::new();
        let mut display_counts: HashMap<String, HashMap<String, u32>> = HashMap::new();

        for sentence in &track.sentences {
            for token in &sentence.tokens {
                if token.kind != SubtitleTokenKind::Word {
                    continue;
                }
                let key = match normalized_by_raw.get(&token.text) {
                    Some(cached) => cached.clone(),
                    None => {
                        let normalized = self
                            .lexical_learning()
                            .normalize_lexical_form(language.as_str(), &token.text)?
                            .normalized;
                        let value = (!normalized.is_empty()).then_some(normalized);
                        normalized_by_raw.insert(token.text.clone(), value.clone());
                        value
                    }
                };
                let Some(key) = key else { continue };
                *token_counts_by_key.entry(key.clone()).or_default() += 1;
                *display_counts
                    .entry(key)
                    .or_default()
                    .entry(token.text.clone())
                    .or_default() += 1;
            }
        }

        if token_counts_by_key.is_empty() {
            return Ok(Vec::new());
        }

        let keys: Vec<String> = token_counts_by_key.keys().cloned().collect();
        let entries = self.lexical_entries.lexical_entries_by_keys(
            &language,
            LexicalEntryKind::Word,
            &keys,
        )?;
        let assessed_keys: std::collections::HashSet<&str> = entries
            .iter()
            .filter(|entry| entry.status.is_some())
            .map(|entry| entry.normalized_form.as_str())
            .collect();

        let mut candidates: Vec<ColdStartWordCandidate> = token_counts_by_key
            .iter()
            .filter(|(key, _)| !assessed_keys.contains(key.as_str()))
            .map(|(key, count)| {
                let best_display = display_counts
                    .get(key)
                    .and_then(|forms| forms.iter().max_by_key(|(_, c)| *c).map(|(f, _)| f.clone()))
                    .unwrap_or_else(|| key.clone());
                ColdStartWordCandidate {
                    display_form: best_display,
                    normalized_form: key.clone(),
                    occurrence_count: *count,
                }
            })
            .collect();

        candidates.sort_by(|a, b| {
            b.occurrence_count
                .cmp(&a.occurrence_count)
                .then_with(|| a.normalized_form.cmp(&b.normalized_form))
        });
        candidates.truncate(limit as usize);
        Ok(candidates)
    }
}

/// Words per minute over speech time only: per-sentence spans are summed so
/// inter-sentence gaps (silence, music) do not dilute the rate.
fn speech_rate_wpm(words: &[WordTiming]) -> Option<f32> {
    if words.is_empty() {
        return None;
    }
    let mut spans: HashMap<&SubtitleSentenceId, (u64, u64)> = HashMap::new();
    for word in words {
        let span = spans
            .entry(&word.sentence_id)
            .or_insert((word.start_ms, word.end_ms));
        span.0 = span.0.min(word.start_ms);
        span.1 = span.1.max(word.end_ms);
    }
    let speech_ms: u64 = spans
        .values()
        .map(|(start, end)| end.saturating_sub(*start))
        .sum();
    if speech_ms == 0 {
        return None;
    }
    Some(words.len() as f32 * 60_000.0 / speech_ms as f32)
}

// ---------------------------------------------------------------------------
// v3 feature extraction helpers (Issue #94)
// ---------------------------------------------------------------------------

/// Extract sense-group features from the active analysis.
/// Returns (mean_sg_length, sg_density).
fn extract_sense_group_features(
    active_sg: Option<&SenseGroupAnalysis>,
    document: &LLTimelineDocument,
) -> (Option<f32>, Option<f32>) {
    let Some(sg) = active_sg else {
        return (None, None);
    };
    if sg.groups.is_empty() {
        return (None, None);
    }

    let sentence_count = document.segments.len().max(1) as f32;
    let group_count = sg.groups.len() as f32;

    // Mean sense-group length in word tokens.
    let total_tokens_in_groups: u32 = sg
        .groups
        .iter()
        .map(|g| g.end_token_index.saturating_sub(g.start_token_index) + 1)
        .sum();
    let mean_sg_length = total_tokens_in_groups as f32 / group_count;

    // Sense groups per sentence.
    let sg_density = group_count / sentence_count;

    (Some(mean_sg_length), Some(sg_density))
}

/// Extract syntax complexity persisted with the active sense-group analysis.
fn extract_syntax_features(active_sg: Option<&SenseGroupAnalysis>) -> (Option<f32>, Option<f32>) {
    let Some(metrics) = active_sg.map(|analysis| analysis.metrics_json.as_object()) else {
        return (None, None);
    };
    (
        metrics
            .get("syntax_max_depth")
            .and_then(serde_json::Value::as_f64)
            .map(|value| value as f32),
        metrics
            .get("syntax_mean_dependency_span")
            .and_then(serde_json::Value::as_f64)
            .map(|value| value as f32),
    )
}

/// Compute the ratio of inter-word pauses to total speech duration.
fn compute_pause_ratio(words: &[WordTiming]) -> Option<f32> {
    if words.len() < 2 {
        return None;
    }

    // Group words by sentence.
    let mut by_sentence: HashMap<&SubtitleSentenceId, Vec<&WordTiming>> = HashMap::new();
    for word in words {
        by_sentence.entry(&word.sentence_id).or_default().push(word);
    }

    let mut total_speech_ms: u64 = 0;
    let mut total_pause_ms: u64 = 0;

    for sentence_words in by_sentence.values() {
        let mut sorted = sentence_words.clone();
        sorted.sort_by_key(|w| w.start_ms);

        for pair in sorted.windows(2) {
            let gap = pair[1].start_ms.saturating_sub(pair[0].end_ms);
            total_pause_ms += gap;
        }

        if let (Some(first), Some(last)) = (sorted.first(), sorted.last()) {
            total_speech_ms += last.end_ms.saturating_sub(first.start_ms);
        }
    }

    if total_speech_ms == 0 {
        return None;
    }

    Some(total_pause_ms as f32 / total_speech_ms as f32)
}

/// Mean timing reliability by provenance. The values are explicit
/// `heuristic_proxy` inputs: estimated timings remain usable but uncertain,
/// while aligned and user-adjusted timings carry stronger evidence.
fn compute_subtitle_timing_quality(words: &[WordTiming]) -> f32 {
    if words.is_empty() {
        return 0.0;
    }
    let quality = words
        .iter()
        .map(|word| match word.timing_source {
            TimingSource::Estimated => 0.25,
            TimingSource::AsrReported => 0.60,
            TimingSource::AsrAligned => 0.85,
            TimingSource::ForcedAligned | TimingSource::UserAdjusted => 1.0,
        })
        .sum::<f32>();
    quality / words.len() as f32
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::TimingSource;

    fn timing(sentence: &SubtitleSentenceId, index: u32, start_ms: u64, end_ms: u64) -> WordTiming {
        WordTiming {
            sentence_id: sentence.clone(),
            token_index: index,
            text: format!("w{index}"),
            start_ms,
            end_ms,
            confidence: None,
            timing_source: TimingSource::ForcedAligned,
            provider_id: "test".into(),
            provider_version: "v1".into(),
        }
    }

    #[test]
    fn speech_rate_excludes_inter_sentence_gaps() {
        let s1 = SubtitleSentenceId::parse("s1").unwrap();
        let s2 = SubtitleSentenceId::parse("s2").unwrap();
        // Two sentences of 3 words / 1.5s each with a 10s gap between them:
        // 6 words over 3s of speech = 120 wpm, not 6 words over 13s.
        let words = vec![
            timing(&s1, 0, 0, 500),
            timing(&s1, 1, 500, 1000),
            timing(&s1, 2, 1000, 1500),
            timing(&s2, 0, 11_500, 12_000),
            timing(&s2, 1, 12_000, 12_500),
            timing(&s2, 2, 12_500, 13_000),
        ];
        let wpm = speech_rate_wpm(&words).unwrap();
        assert!((wpm - 120.0).abs() < 0.01, "expected 120 wpm, got {wpm}");
    }

    #[test]
    fn speech_rate_handles_empty_and_zero_duration() {
        assert_eq!(speech_rate_wpm(&[]), None);
        let s1 = SubtitleSentenceId::parse("s1").unwrap();
        assert_eq!(speech_rate_wpm(&[timing(&s1, 0, 100, 100)]), None);
    }

    #[test]
    fn subtitle_timing_quality_respects_alignment_provenance() {
        let sentence = SubtitleSentenceId::parse("s1").unwrap();
        let mut estimated = timing(&sentence, 0, 0, 100);
        estimated.timing_source = TimingSource::Estimated;
        let mut aligned = timing(&sentence, 1, 100, 200);
        aligned.timing_source = TimingSource::AsrAligned;
        let forced = timing(&sentence, 2, 200, 300);
        let quality = compute_subtitle_timing_quality(&[estimated, aligned, forced]);
        assert!((quality - 0.70).abs() < 1e-6);
    }
}
