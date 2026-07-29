use std::path::Path;

use crate::{
    ApplicationError, ForcedAlignCancellation, ForcedAlignFailure, ForcedAlignProvider,
    ForcedAlignRequest, ForcedAlignmentReport, ForcedAlignmentStatus, MediaAnalysisUseCases,
    NeverCancelForcedAlignment, SubtitleSentence, SubtitleTrackId, TimelineMetrics, TimelineStatus,
    WordTimelinePipelineResult, WordTiming, forced_align_segments,
    save_word_timeline_snapshot_with_metrics,
};

const TEXT_LINE_DTW_ALGORITHM_ID: &str = "whisper-dtw";
const TEXT_LINE_DTW_ALGORITHM_VERSION: &str = "dtw-v2";
const TEXT_LINE_DTW_CONFIG_HASH: &str = "whisper-json-full-dtw-v2";
const SOUND_LINE_DTW_ALGORITHM_ID: &str = "sound-line-whisper-dtw";
const SOUND_LINE_DTW_ALGORITHM_VERSION: &str = "phase-2.22";
const SOUND_LINE_DTW_CONFIG_HASH: &str = "sound-line-whisper-json-full-dtw-v1";

impl MediaAnalysisUseCases {
    pub async fn store_transcription_text_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
        whisper_json_bytes: &[u8],
    ) -> Result<Option<WordTimelinePipelineResult>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let timings = match speech_analysis::timing::extract_word_timings_from_json(
            whisper_json_bytes,
            &track.sentences,
        ) {
            Ok(timings) if !timings.is_empty() => timings,
            _ => return Ok(None),
        };

        let active_timeline_id = save_word_timeline_snapshot_with_metrics(
            self,
            &track.id,
            &timings,
            TEXT_LINE_DTW_ALGORITHM_ID,
            TEXT_LINE_DTW_ALGORITHM_VERSION,
            TEXT_LINE_DTW_CONFIG_HASH,
            TimelineStatus::Active,
            None,
            Some(TimelineMetrics::from_value(serde_json::json!({
                "line": "text",
                "source": "whisper.cpp_dtw",
            }))),
        )
        .ok();
        let stored_legacy_word_timings = if active_timeline_id.is_some() {
            false
        } else {
            self.store_word_timings(&track.id, &timings).is_ok()
        };
        // New word timelines feed rhythm frames; refresh the corpus family
        // projection (Phase 3.9) so specialty aggregation sees this track.
        let _ = self.reindex_track_corpus(&track.id);

        Ok(Some(WordTimelinePipelineResult {
            extracted_word_count: timings.len(),
            forced_aligned_word_count: 0,
            forced_alignment: ForcedAlignmentReport::not_configured(),
            dtw_timeline_id: active_timeline_id.clone(),
            forced_aligned_timeline_id: None,
            final_timeline_id: active_timeline_id,
            stored_legacy_word_timings,
            acoustic_cue_count: 0,
            energy_prominence_cue_count: 0,
            pitch_prominence_cue_count: 0,
        }))
    }

    pub async fn build_transcription_sound_line_resources(
        &self,
        track_id: &SubtitleTrackId,
        whisper_json_bytes: &[u8],
        audio_wav_path: &Path,
        forced_aligner: Option<&dyn ForcedAlignProvider>,
        language: Option<&str>,
    ) -> Result<Option<WordTimelinePipelineResult>, ApplicationError> {
        self.build_transcription_sound_line_resources_cancellable(
            track_id,
            whisper_json_bytes,
            audio_wav_path,
            forced_aligner,
            None,
            language,
        )
        .await
    }

    pub async fn build_transcription_sound_line_resources_cancellable(
        &self,
        track_id: &SubtitleTrackId,
        whisper_json_bytes: &[u8],
        audio_wav_path: &Path,
        forced_aligner: Option<&dyn ForcedAlignProvider>,
        cancellation: Option<&dyn ForcedAlignCancellation>,
        language: Option<&str>,
    ) -> Result<Option<WordTimelinePipelineResult>, ApplicationError> {
        if cancellation_requested(cancellation) {
            return Ok(None);
        }
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let active_text_timeline = self.word_timelines.active_word_timeline(&track.id)?;
        let dtw_timeline_id = active_text_timeline
            .as_ref()
            .map(|timeline| timeline.id.clone());
        // Reuse the already-persisted text-line words when available and only
        // fall back to re-parsing the whisper JSON when there is no usable
        // active timeline, avoiding a redundant extract on the normal path.
        let mut timings = match active_text_timeline
            .as_ref()
            .filter(|timeline| !timeline.words.is_empty())
            .map(|timeline| timeline.words.clone())
        {
            Some(words) => words,
            None => match speech_analysis::timing::extract_word_timings_from_json(
                whisper_json_bytes,
                &track.sentences,
            ) {
                Ok(timings) if !timings.is_empty() => timings,
                _ => return Ok(None),
            },
        };
        let extracted_word_count = timings.len();

        let mut parent_timeline_id = dtw_timeline_id.clone();

        let forced_alignment = if let Some(provider) = forced_aligner {
            apply_forced_alignment(
                audio_wav_path,
                &track.sentences,
                &mut timings,
                provider,
                cancellation,
                language,
            )
            .await
        } else {
            ForcedAlignmentReport::not_configured()
        };
        if cancellation_requested(cancellation) {
            return Ok(None);
        }
        let forced_aligned_word_count = forced_alignment.aligned_word_count;

        let mut forced_aligned_timeline_id = None;
        let mut final_timeline_id = None;
        if forced_aligned_word_count > 0
            && let Some(descriptor) = forced_alignment.descriptor.as_ref()
            && let Some(Ok(timeline_id)) = commit_if_active(cancellation, || {
                save_word_timeline_snapshot_with_metrics(
                    self,
                    &track.id,
                    &timings,
                    &descriptor.provider_id,
                    &descriptor.model_revision,
                    &descriptor.protocol_version,
                    TimelineStatus::Candidate,
                    parent_timeline_id.as_ref(),
                    Some(TimelineMetrics::from_value(serde_json::json!({
                        "line": "sound",
                        "source": "forced_alignment",
                        "forced_alignment": forced_alignment,
                    }))),
                )
            })
        {
            parent_timeline_id = Some(timeline_id.clone());
            forced_aligned_timeline_id = Some(timeline_id.clone());
            final_timeline_id = Some(timeline_id);
        }

        let wav_bytes = tokio::fs::read(audio_wav_path).await.ok();
        if let Some(wav_bytes) = wav_bytes.as_deref()
            && let Ok(refined) = speech_analysis::timing::refine_word_timings_from_pcm_wav(
                wav_bytes,
                &timings,
                &speech_analysis::timing::PauseRefinementConfig::default(),
            )
            && !refined.pauses.is_empty()
        {
            let refined_timings = refined.timings;
            if let Some(Ok(timeline_id)) = commit_if_active(cancellation, || {
                save_word_timeline_snapshot_with_metrics(
                    self,
                    &track.id,
                    &refined_timings,
                    speech_analysis::timing::PAUSE_REFINEMENT_PROVIDER_ID,
                    speech_analysis::timing::PAUSE_REFINEMENT_PROVIDER_VERSION,
                    "pause-refinement-default-v1",
                    TimelineStatus::Candidate,
                    parent_timeline_id.as_ref(),
                    Some(TimelineMetrics::from_value(serde_json::json!({
                        "line": "sound",
                        "source": "pause_refinement",
                        "pause_count": refined.pauses.len(),
                        "forced_alignment": forced_alignment,
                    }))),
                )
            }) {
                timings = refined_timings;
                final_timeline_id = Some(timeline_id);
            }
        }

        if final_timeline_id.is_none() {
            final_timeline_id = commit_if_active(cancellation, || {
                save_word_timeline_snapshot_with_metrics(
                    self,
                    &track.id,
                    &timings,
                    SOUND_LINE_DTW_ALGORITHM_ID,
                    SOUND_LINE_DTW_ALGORITHM_VERSION,
                    SOUND_LINE_DTW_CONFIG_HASH,
                    TimelineStatus::Candidate,
                    parent_timeline_id.as_ref(),
                    Some(TimelineMetrics::from_value(serde_json::json!({
                        "line": "sound",
                        "source": "whisper.cpp_dtw",
                        "forced_alignment": forced_alignment,
                    }))),
                )
            })
            .and_then(Result::ok);
        }

        let mut acoustic_cue_count = 0;
        let mut energy_prominence_cue_count = 0;
        let mut pitch_prominence_cue_count = 0;
        if let (Some(timeline_id), Some(wav_bytes)) =
            (final_timeline_id.as_ref(), wav_bytes.as_deref())
            && let Ok(acoustic_analysis) =
                speech_analysis::timing::analyze_word_acoustics_from_pcm_wav(wav_bytes, &timings)
            && let Some(Ok(cue_count)) = commit_if_active(cancellation, || {
                self.store_rhythm_word_acoustic_analysis(&track.id, timeline_id, &acoustic_analysis)
            })
        {
            acoustic_cue_count = cue_count;
            energy_prominence_cue_count = acoustic_analysis.positive_energy_cue_count();
            pitch_prominence_cue_count = acoustic_analysis.positive_pitch_cue_count();
        }
        let _ = commit_if_active(cancellation, || self.reindex_track_corpus(&track.id));

        if cancellation_requested(cancellation) {
            return Ok(None);
        }

        Ok(Some(WordTimelinePipelineResult {
            extracted_word_count,
            forced_aligned_word_count,
            forced_alignment,
            dtw_timeline_id,
            forced_aligned_timeline_id,
            final_timeline_id,
            stored_legacy_word_timings: false,
            acoustic_cue_count,
            energy_prominence_cue_count,
            pitch_prominence_cue_count,
        }))
    }
}

async fn apply_forced_alignment(
    wav: &Path,
    sentences: &[SubtitleSentence],
    timings: &mut [WordTiming],
    provider: &dyn ForcedAlignProvider,
    cancellation: Option<&dyn ForcedAlignCancellation>,
    language: Option<&str>,
) -> ForcedAlignmentReport {
    let descriptor = provider.descriptor();
    let request = ForcedAlignRequest {
        audio_path: wav.to_string_lossy().into_owned(),
        segments: forced_align_segments(sentences),
        language: language.map(str::to_owned),
    };
    if request.segments.is_empty() {
        return ForcedAlignmentReport {
            status: ForcedAlignmentStatus::Skipped,
            aligned_word_count: 0,
            descriptor: Some(descriptor),
            failure: None,
        };
    }
    let never_cancel = NeverCancelForcedAlignment;
    let cancellation = cancellation.unwrap_or(&never_cancel);
    match provider.align(&request, cancellation).await {
        Ok(outcome) => {
            let aligned_word_count =
                speech_analysis::timing::merge_alignments(timings, &outcome.timings, sentences);
            ForcedAlignmentReport {
                status: ForcedAlignmentStatus::Applied,
                aligned_word_count,
                descriptor: Some(outcome.descriptor),
                failure: None,
            }
        }
        Err(failure) => degraded_alignment(failure),
    }
}

fn cancellation_requested(cancellation: Option<&dyn ForcedAlignCancellation>) -> bool {
    cancellation.is_some_and(ForcedAlignCancellation::is_cancelled)
}

fn commit_if_active<T>(
    cancellation: Option<&dyn ForcedAlignCancellation>,
    commit: impl FnOnce() -> T,
) -> Option<T> {
    let Some(cancellation) = cancellation else {
        return Some(commit());
    };
    let mut commit = Some(commit);
    let mut result = None;
    let mut guarded_commit = || {
        result = Some(commit.take().expect("commit callback runs once")());
    };
    if cancellation.commit_if_active(&mut guarded_commit) {
        result
    } else {
        None
    }
}

fn degraded_alignment(failure: ForcedAlignFailure) -> ForcedAlignmentReport {
    ForcedAlignmentReport {
        status: ForcedAlignmentStatus::Degraded,
        aligned_word_count: 0,
        descriptor: Some(failure.descriptor.clone()),
        failure: Some(failure),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use domain::{SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs, TimingSource};

    struct FailingForcedAlignProvider;

    fn descriptor() -> crate::ForcedAlignProviderDescriptor {
        crate::ForcedAlignProviderDescriptor {
            provider_id: "fake-forced-align".into(),
            model_revision: "fake-v1".into(),
            protocol_version: "fake-json-v1".into(),
            runtime: "test".into(),
        }
    }

    #[async_trait]
    impl ForcedAlignProvider for FailingForcedAlignProvider {
        fn descriptor(&self) -> crate::ForcedAlignProviderDescriptor {
            descriptor()
        }

        async fn align(
            &self,
            _request: &ForcedAlignRequest,
            _cancellation: &dyn ForcedAlignCancellation,
        ) -> Result<crate::ForcedAlignOutcome, ForcedAlignFailure> {
            Err(ForcedAlignFailure {
                kind: crate::ForcedAlignFailureKind::Exit,
                detail: "model unavailable".into(),
                descriptor: descriptor(),
            })
        }
    }

    #[tokio::test]
    async fn forced_align_failure_degrades_without_mutating_asr_timing() {
        let sentence_id = SubtitleSentenceId::parse("sentence-1").unwrap();
        let sentence = SubtitleSentence {
            id: sentence_id.clone(),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(1_000),
            original_text: "hello".into(),
            display_text: "hello".into(),
            tokens: vec![SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "hello".into(),
                normalized: Some("hello".into()),
                start_char: 0,
                end_char: 5,
            }],
        };
        let original = WordTiming {
            sentence_id,
            token_index: 0,
            text: "hello".into(),
            start_ms: 100,
            end_ms: 800,
            confidence: Some(0.7),
            timing_source: TimingSource::AsrReported,
            provider_id: "whisper.cpp".into(),
            provider_version: "dtw-v2".into(),
        };
        let mut timings = vec![original.clone()];

        let report = apply_forced_alignment(
            Path::new("/tmp/audio.wav"),
            &[sentence],
            &mut timings,
            &FailingForcedAlignProvider,
            None,
            Some("en"),
        )
        .await;

        assert_eq!(report.status, ForcedAlignmentStatus::Degraded);
        assert_eq!(report.aligned_word_count, 0);
        assert_eq!(
            report.failure.unwrap().kind,
            crate::ForcedAlignFailureKind::Exit
        );
        assert_eq!(timings, vec![original]);
    }

    struct AlreadyCancelled;

    impl ForcedAlignCancellation for AlreadyCancelled {
        fn is_cancelled(&self) -> bool {
            true
        }
    }

    #[test]
    fn cancellation_winner_prevents_the_persistence_commit() {
        let writes = std::sync::atomic::AtomicUsize::new(0);
        let result = commit_if_active(Some(&AlreadyCancelled), || {
            writes.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        });
        assert!(result.is_none());
        assert_eq!(writes.load(std::sync::atomic::Ordering::Relaxed), 0);
    }
}
