use std::path::Path;
use std::process::Stdio;

use crate::*;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

impl AppServices {
    pub async fn refine_transcription_word_timelines(
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
        let mut timings = match speech_analysis::asr_timing::extract_word_timings_from_json(
            whisper_json_bytes,
            &track.sentences,
        ) {
            Ok(timings) if !timings.is_empty() => timings,
            _ => return Ok(None),
        };

        let dtw_timeline_id = save_word_timeline_snapshot(
            self,
            &track.id,
            &timings,
            "whisper-dtw",
            "dtw-v2",
            "whisper-json-full-dtw-v2",
            TimelineStatus::Candidate,
            None,
        );
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
        if forced_aligned_word_count > 0
            && let Some(timeline_id) = save_word_timeline_snapshot(
                self,
                &track.id,
                &timings,
                speech_analysis::forced_align::PROVIDER_ID,
                speech_analysis::forced_align::PROVIDER_VERSION,
                "mms-fa-v1-whisper-segment-window",
                TimelineStatus::Candidate,
                parent_timeline_id.as_ref(),
            )
        {
            parent_timeline_id = Some(timeline_id.clone());
            forced_aligned_timeline_id = Some(timeline_id);
        }

        let mut final_timeline_id = parent_timeline_id.clone();
        if let Ok(wav_bytes) = tokio::fs::read(audio_wav_path).await
            && let Ok(refined) = speech_analysis::pause_refinement::refine_word_timings_from_pcm_wav(
                &wav_bytes,
                &timings,
                &speech_analysis::pause_refinement::PauseRefinementConfig::default(),
            )
            && !refined.pauses.is_empty()
        {
            timings = refined.timings;
            final_timeline_id = save_word_timeline_snapshot(
                self,
                &track.id,
                &timings,
                speech_analysis::pause_refinement::PROVIDER_ID,
                speech_analysis::pause_refinement::PROVIDER_VERSION,
                "pause-refinement-default-v1",
                TimelineStatus::Active,
                parent_timeline_id.as_ref(),
            );
        }

        let stored_legacy_word_timings = if let Some(timeline_id) = final_timeline_id.as_ref() {
            let _ = self.activate_word_timeline(timeline_id);
            false
        } else {
            let _ = self.store_word_timings(&track.id, &timings);
            true
        };

        Ok(Some(WordTimelinePipelineResult {
            extracted_word_count: timings.len(),
            forced_aligned_word_count,
            dtw_timeline_id,
            forced_aligned_timeline_id,
            final_timeline_id,
            stored_legacy_word_timings,
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
