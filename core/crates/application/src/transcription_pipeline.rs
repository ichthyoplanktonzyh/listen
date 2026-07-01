use std::path::Path;
use std::process::Stdio;

use crate::*;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

const TEXT_LINE_DTW_ALGORITHM_ID: &str = "whisper-dtw";
const TEXT_LINE_DTW_ALGORITHM_VERSION: &str = "dtw-v2";
const TEXT_LINE_DTW_CONFIG_HASH: &str = "whisper-json-full-dtw-v2";
const SOUND_LINE_DTW_ALGORITHM_ID: &str = "sound-line-whisper-dtw";
const SOUND_LINE_DTW_ALGORITHM_VERSION: &str = "phase-2.22";
const SOUND_LINE_DTW_CONFIG_HASH: &str = "sound-line-whisper-json-full-dtw-v1";

impl AppServices {
    pub async fn store_transcription_text_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
        whisper_json_bytes: &[u8],
    ) -> Result<Option<WordTimelinePipelineResult>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let timings = match speech_analysis::asr_timing::extract_word_timings_from_json(
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

        Ok(Some(WordTimelinePipelineResult {
            extracted_word_count: timings.len(),
            forced_aligned_word_count: 0,
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
        forced_align_sidecar: Option<ForcedAlignSidecar>,
        language: Option<&str>,
    ) -> Result<Option<WordTimelinePipelineResult>, ApplicationError> {
        let track = self
            .subtitle_tracks
            .get_track(track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let extracted_timings = match speech_analysis::asr_timing::extract_word_timings_from_json(
            whisper_json_bytes,
            &track.sentences,
        ) {
            Ok(timings) if !timings.is_empty() => timings,
            _ => return Ok(None),
        };
        let active_text_timeline = self.timelines.active_word_timeline(&track.id)?;
        let dtw_timeline_id = active_text_timeline
            .as_ref()
            .map(|timeline| timeline.id.clone());
        let mut timings = active_text_timeline
            .as_ref()
            .filter(|timeline| !timeline.words.is_empty())
            .map(|timeline| timeline.words.clone())
            .unwrap_or(extracted_timings);
        let extracted_word_count = timings.len();

        let mut parent_timeline_id = dtw_timeline_id.clone();

        let forced_aligned_word_count = if let Some(sidecar) = forced_align_sidecar {
            self.try_apply_forced_alignment(
                audio_wav_path,
                &track.sentences,
                &mut timings,
                &sidecar,
                language,
            )
            .await
        } else {
            0
        };

        let mut forced_aligned_timeline_id = None;
        let mut final_timeline_id = None;
        if forced_aligned_word_count > 0 {
            if let Ok(timeline_id) = save_word_timeline_snapshot_with_metrics(
                self,
                &track.id,
                &timings,
                speech_analysis::forced_align::PROVIDER_ID,
                speech_analysis::forced_align::PROVIDER_VERSION,
                "mms-fa-v1-whisper-segment-window",
                TimelineStatus::Candidate,
                parent_timeline_id.as_ref(),
                Some(TimelineMetrics::from_value(serde_json::json!({
                    "line": "sound",
                    "source": "forced_alignment",
                }))),
            ) {
                parent_timeline_id = Some(timeline_id.clone());
                forced_aligned_timeline_id = Some(timeline_id.clone());
                final_timeline_id = Some(timeline_id);
            }
        }

        let wav_bytes = tokio::fs::read(audio_wav_path).await.ok();
        if let Some(wav_bytes) = wav_bytes.as_deref()
            && let Ok(refined) = speech_analysis::pause_refinement::refine_word_timings_from_pcm_wav(
                wav_bytes,
                &timings,
                &speech_analysis::pause_refinement::PauseRefinementConfig::default(),
            )
            && !refined.pauses.is_empty()
        {
            let refined_timings = refined.timings;
            if let Ok(timeline_id) = save_word_timeline_snapshot_with_metrics(
                self,
                &track.id,
                &refined_timings,
                speech_analysis::pause_refinement::PROVIDER_ID,
                speech_analysis::pause_refinement::PROVIDER_VERSION,
                "pause-refinement-default-v1",
                TimelineStatus::Candidate,
                parent_timeline_id.as_ref(),
                Some(TimelineMetrics::from_value(serde_json::json!({
                    "line": "sound",
                    "source": "pause_refinement",
                    "pause_count": refined.pauses.len(),
                }))),
            ) {
                timings = refined_timings;
                final_timeline_id = Some(timeline_id);
            }
        }

        if final_timeline_id.is_none() {
            final_timeline_id = save_word_timeline_snapshot_with_metrics(
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
                }))),
            )
            .ok();
        }

        let mut acoustic_cue_count = 0;
        let mut energy_prominence_cue_count = 0;
        let mut pitch_prominence_cue_count = 0;
        if let (Some(timeline_id), Some(wav_bytes)) =
            (final_timeline_id.as_ref(), wav_bytes.as_deref())
            && let Ok(acoustic_analysis) =
                speech_analysis::word_acoustics::analyze_word_acoustics_from_pcm_wav(
                    wav_bytes, &timings,
                )
            && let Ok(cue_count) =
                self.store_rhythm_word_acoustic_analysis(&track.id, timeline_id, &acoustic_analysis)
        {
            acoustic_cue_count = cue_count;
            energy_prominence_cue_count = acoustic_analysis.positive_energy_cue_count();
            pitch_prominence_cue_count = acoustic_analysis.positive_pitch_cue_count();
        }

        Ok(Some(WordTimelinePipelineResult {
            extracted_word_count,
            forced_aligned_word_count,
            dtw_timeline_id,
            forced_aligned_timeline_id,
            final_timeline_id,
            stored_legacy_word_timings: false,
            acoustic_cue_count,
            energy_prominence_cue_count,
            pitch_prominence_cue_count,
        }))
    }

    async fn try_apply_forced_alignment(
        &self,
        wav: &Path,
        sentences: &[SubtitleSentence],
        timings: &mut [WordTiming],
        sidecar: &ForcedAlignSidecar,
        language: Option<&str>,
    ) -> usize {
        let request = ForcedAlignRequest {
            audio_path: wav.to_string_lossy().into_owned(),
            segments: forced_align_segments(sentences),
            language: language.map(|s| s.to_owned()),
        };
        if request.segments.is_empty() {
            return 0;
        }
        let Ok(stdin_json) = serde_json::to_vec(&request) else {
            return 0;
        };

        let mut child = match Command::new(&sidecar.python)
            .arg(&sidecar.script)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
        {
            Ok(child) => child,
            Err(_) => return 0,
        };

        let Some(mut stdin) = child.stdin.take() else {
            return 0;
        };
        if stdin.write_all(&stdin_json).await.is_err() || stdin.shutdown().await.is_err() {
            return 0;
        }
        drop(stdin);

        let Ok(output) = child.wait_with_output().await else {
            return 0;
        };
        if !output.status.success() {
            return 0;
        }
        let Ok(aligned) =
            serde_json::from_slice::<speech_analysis::forced_align::AlignOutput>(&output.stdout)
        else {
            return 0;
        };
        speech_analysis::forced_align::merge_alignments(timings, &aligned.timings, sentences)
    }
}
