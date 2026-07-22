use std::collections::HashMap;

use crate::{
    ApplicationError, CONTENT_FIT_ALGORITHM_VERSION, ColdStartWordCandidate,
    ContentDifficultyProfile, FitEvidenceGrade, LanguageCode, LearningStatus, LexicalEntryKind,
    MeaningFitInputs, MediaAnalysisUseCases, SoundFitInputs, SubtitleSentenceId, SubtitleTokenKind,
    SubtitleTrack, SubtitleTrackId, WordTiming, apply_sound_fit_calibration,
    content_fit_fingerprint, meaning_fit, now_ms, sound_fit, sound_fit_calibration_outcome,
};

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
    /// track content, active word/chunk timeline identities, and the
    /// language-wide vocabulary watermark. Must stay the single composition
    /// point shared by the cached and compute paths.
    fn content_fit_input_fingerprint(
        &self,
        track_id: &SubtitleTrackId,
        track: &SubtitleTrack,
        language: &LanguageCode,
    ) -> Result<String, ApplicationError> {
        let word_timeline = self.word_timelines.active_word_timeline(track_id)?;
        let chunk_timeline = self.chunk_timelines.active_chunk_timeline(track_id)?;
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
            "{}|lang:{}|track:{}:{}|wt:{}:{}|ct:{}:{}|vocab:{}:{}|cal:{}",
            CONTENT_FIT_ALGORITHM_VERSION,
            language.as_str(),
            track.id.as_str(),
            track.fingerprint,
            word_timeline.as_ref().map(|t| t.id.as_str()).unwrap_or(""),
            word_timeline.as_ref().map(|t| t.updated_at_ms).unwrap_or(0),
            chunk_timeline.as_ref().map(|t| t.id.as_str()).unwrap_or(""),
            chunk_timeline
                .as_ref()
                .map(|t| t.updated_at_ms)
                .unwrap_or(0),
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

        let active_chunk_timeline = document
            .active_chunk_timeline_id
            .as_ref()
            .and_then(|id| document.chunk_timelines.iter().find(|t| &t.id == id));
        let mean_chunk_length = active_chunk_timeline.and_then(|timeline| {
            if timeline.chunks.is_empty() {
                return None;
            }
            let words: u32 = timeline
                .chunks
                .iter()
                .map(|chunk| chunk.end_word_index.saturating_sub(chunk.start_word_index) + 1)
                .sum();
            Some(words as f32 / timeline.chunks.len() as f32)
        });

        let media_id = document.metadata.media.id.as_str().to_owned();
        let mut sound = sound_fit(SoundFitInputs {
            known_not_recognized_density,
            speech_rate_wpm: speech_rate,
            weak_form_density,
            compression_density,
            mean_chunk_length,
        });
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
            meaning: meaning_fit(MeaningFitInputs {
                unknown_meaning_density,
                unassessed_density,
            }),
            sound,
            assessed_token_ratio: 1.0 - unassessed_density,
            evidence_grade,
            algorithm_version: CONTENT_FIT_ALGORITHM_VERSION.into(),
            computed_at_ms: now_ms(),
            input_fingerprint,
        })
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
}
