use std::io::Read;
use std::sync::Arc;

use domain::{
    LearningEvent, LearningEventId, LearningEventKind, LearningEventSubject,
    LearningEventSubjectKind, PracticeAttempt, PracticeAttemptId, PracticeEvaluation, PracticeKind,
    PracticeResult, RecordingAsset, RecordingAssetId, RecordingAudioFacts, RecordingAudioMetadata,
    ShadowingAnalysisId, ShadowingAnalysisRecord, ShadowingComparison,
};
use sha2::{Digest, Sha256};

use crate::{
    ApplicationError, CompleteShadowingAttempt, CreateRecordingAsset, CreateShadowingComparison,
    DisabledLearningLoopRepository, LearningEventRepository, PracticeRepository,
    RecordingRepository, SubtitleTrackRepository, WordTimelineRepository, clean_required, now_ms,
};

pub struct RecordingUseCases {
    recordings: Arc<dyn RecordingRepository>,
    practice: Arc<dyn PracticeRepository>,
    learning_events: Arc<dyn LearningEventRepository>,
    subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
    word_timelines: Arc<dyn WordTimelineRepository>,
}

impl RecordingUseCases {
    pub(crate) fn new(
        recordings: Arc<dyn RecordingRepository>,
        practice: Arc<dyn PracticeRepository>,
        learning_events: Arc<dyn LearningEventRepository>,
        subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
        word_timelines: Arc<dyn WordTimelineRepository>,
    ) -> Self {
        Self {
            recordings,
            practice,
            learning_events,
            subtitle_tracks,
            word_timelines,
        }
    }

    pub fn create_recording_asset(
        &self,
        input: CreateRecordingAsset,
    ) -> Result<RecordingAsset, ApplicationError> {
        let file_path = clean_required(input.file_path, "recording file path")?;
        let recorder_version = clean_required(input.recorder_version, "recorder version")?;
        let container = clean_required(input.audio.container, "recording container")?;
        let codec = clean_required(input.audio.codec, "recording codec")?;
        let sample_format = clean_required(input.audio.sample_format, "recording sample format")?;
        let content_sha256 = input.audio.content_sha256.trim().to_ascii_lowercase();
        if input.duration_ms == 0
            || input.audio.sample_rate_hz == 0
            || input.audio.channels == 0
            || input.audio.byte_length == 0
            || content_sha256.len() != 64
            || !content_sha256
                .bytes()
                .all(|value| value.is_ascii_hexdigit())
            || input.source_segment.end_ms <= input.source_segment.start_ms
        {
            return Err(ApplicationError::Validation("recording metadata"));
        }
        let now = now_ms();
        let id = RecordingAssetId::from_fingerprint(
            "recording-asset",
            &format!(
                "{}:{}:{}:{now}",
                content_sha256,
                input.target.id.as_deref().unwrap_or(""),
                input.source_segment.start_ms
            ),
        );
        self.recordings.save_recording_asset(&RecordingAsset {
            id,
            file_path,
            created_at_ms: now,
            duration_ms: input.duration_ms,
            practice_attempt_id: None,
            target: input.target,
            source_segment: input.source_segment,
            language: input.language,
            audio: RecordingAudioMetadata {
                container,
                codec,
                sample_rate_hz: input.audio.sample_rate_hz,
                channels: input.audio.channels,
                sample_format,
                byte_length: input.audio.byte_length,
                content_sha256,
            },
            recorder_version,
        })
    }

    pub fn recording_asset(
        &self,
        id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError> {
        self.recordings.get_recording_asset(id)
    }

    pub fn delete_recording_asset(
        &self,
        id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError> {
        self.recordings.delete_recording_asset(id)
    }

    pub fn latest_shadowing_analysis(
        &self,
        recording_id: &RecordingAssetId,
    ) -> Result<Option<ShadowingAnalysisRecord>, ApplicationError> {
        self.recordings.latest_shadowing_analysis(recording_id)
    }

    /// Records that a shadowing activity finished without pretending that an
    /// unscored recording proves speaking capability.
    pub fn complete_shadowing_attempt(
        &self,
        input: CompleteShadowingAttempt,
    ) -> Result<PracticeAttempt, ApplicationError> {
        let item = self
            .practice
            .get_practice_item(&input.item_id)?
            .ok_or(ApplicationError::NotFound("practice item"))?;
        if item.kind != PracticeKind::Shadowing {
            return Err(ApplicationError::Validation("shadowing practice item"));
        }
        let mut recording = self
            .recordings
            .get_recording_asset(&input.recording_id)?
            .ok_or(ApplicationError::NotFound("recording asset"))?;
        if recording.target != item.target {
            return Err(ApplicationError::Validation("shadowing recording target"));
        }
        if let Some(attempt_id) = recording.practice_attempt_id.as_ref()
            && let Some(attempt) = self.practice.get_practice_attempt(attempt_id)?
        {
            return Ok(attempt);
        }

        let now = now_ms();
        let attempt = PracticeAttempt {
            id: PracticeAttemptId::from_fingerprint(
                "practice-attempt",
                &format!("shadowing:{}", recording.id.as_str()),
            ),
            item_id: item.id,
            submitted_at_ms: now,
            input: serde_json::json!({ "recording_id": recording.id.as_str() }),
            result: PracticeResult::Completed,
            score: None,
            evaluation: PracticeEvaluation {
                summary: "Shadowing recording completed without automated scoring.".into(),
                token_results: Vec::new(),
                extra: serde_json::json!({ "evaluation_kind": "not_scored" }),
            },
            generated_observation_ids: Vec::new(),
            generated_review_item_ids: Vec::new(),
        };
        let saved = self.practice.create_practice_attempt(&attempt)?;
        recording.practice_attempt_id = Some(saved.id.clone());
        self.recordings.save_recording_asset(&recording)?;
        self.learning_events.append_learning_event(&LearningEvent {
            id: LearningEventId::from_fingerprint(
                "learning-event",
                &format!("practice-completed:{}:{now}", saved.id.as_str()),
            ),
            occurred_at_ms: now,
            kind: LearningEventKind::PracticeCompleted,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::PracticeAttempt,
                id: saved.id.as_str().to_owned(),
            },
            payload: serde_json::json!({
                "item_id": saved.item_id.as_str(),
                "result": saved.result,
                "score": null,
                "recording_id": recording.id.as_str(),
                "evaluation_kind": "not_scored",
            }),
            session_id: item.session_id,
        })?;
        Ok(saved)
    }

    pub fn compare_shadowing(
        &self,
        input: CreateShadowingComparison,
    ) -> Result<ShadowingComparison, ApplicationError> {
        let reference_wav_path = clean_required(input.reference_wav_path, "reference WAV path")?;
        let recording = self
            .recordings
            .get_recording_asset(&input.recording_id)?
            .ok_or(ApplicationError::NotFound("recording asset"))?;
        let attempt_id = recording
            .practice_attempt_id
            .clone()
            .ok_or(ApplicationError::Validation("completed shadowing attempt"))?;

        let sentence = if let Some(ref sentence_id) = recording.target.sentence_id {
            self.subtitle_tracks.get_sentence(sentence_id)?
        } else {
            None
        };
        let reference_word_timings = if let Some(ref sentence_id) = recording.target.sentence_id {
            self.word_timelines.get_word_timings(sentence_id)?
        } else {
            Vec::new()
        };

        let model_dir = resolve_ctc_model_dir();
        let model_revision = resolve_ctc_model_revision();

        let analysis = speech_analysis::phonetics::compare_pcm16_wav_paths(
            &reference_wav_path,
            &recording.file_path,
        )
        .map_err(|_| ApplicationError::Validation("shadowing comparison audio"))?;

        let analysis_v2 = speech_analysis::phonetics::compare_shadowing_v2(
            &reference_wav_path,
            &recording.file_path,
            sentence.as_ref(),
            &reference_word_timings,
            recording.source_segment.start_ms,
            model_dir.as_deref(),
            Some(&model_revision),
        )
        .map_err(|_| ApplicationError::Validation("shadowing v2 comparison audio"))?;

        let reference_audio_sha256 = sha256_file(&reference_wav_path)
            .map_err(|_| ApplicationError::Validation("reference WAV path"))?;
        let analysis_id = ShadowingAnalysisId::from_fingerprint(
            "shadowing-analysis",
            &format!(
                "{}:{}:{}:{}:{}",
                recording.id.as_str(),
                recording.audio.content_sha256,
                reference_audio_sha256,
                analysis_v2.provider_version,
                model_revision,
            ),
        );
        let saved_analysis = self
            .recordings
            .save_shadowing_analysis(&ShadowingAnalysisRecord {
                id: analysis_id,
                recording_id: recording.id.clone(),
                attempt_id: attempt_id.clone(),
                reference_audio_sha256,
                created_at_ms: now_ms(),
                analysis: analysis_v2,
            })?;

        Ok(ShadowingComparison {
            attempt_id,
            reference_segment: recording.source_segment,
            recording_id: recording.id,
            duration_delta_ms: analysis.duration_delta_ms,
            pause_alignment: analysis.pause_alignment,
            reference_waveform: analysis.reference_waveform,
            recording_waveform: analysis.recording_waveform,
            analysis_v2: Some(saved_analysis.analysis),
        })
    }

    pub fn recording_audio_facts(
        &self,
        recording_id: &RecordingAssetId,
    ) -> Result<RecordingAudioFacts, ApplicationError> {
        let recording = self
            .recordings
            .get_recording_asset(recording_id)?
            .ok_or(ApplicationError::NotFound("recording asset"))?;
        let analysis = speech_analysis::phonetics::analyze_pcm16_wav_path(&recording.file_path)
            .map_err(|_| ApplicationError::Validation("recording audio facts"))?;
        Ok(RecordingAudioFacts {
            recording_id: recording.id,
            duration_ms: analysis.duration_ms,
            pauses: analysis.pauses,
            waveform: analysis.waveform,
        })
    }
}

impl RecordingRepository for DisabledLearningLoopRepository {
    fn save_recording_asset(
        &self,
        _asset: &RecordingAsset,
    ) -> Result<RecordingAsset, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_recording_asset(
        &self,
        _id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError> {
        Err(Self::disabled())
    }

    fn delete_recording_asset(
        &self,
        _id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError> {
        Err(Self::disabled())
    }

    fn save_shadowing_analysis(
        &self,
        _record: &ShadowingAnalysisRecord,
    ) -> Result<ShadowingAnalysisRecord, ApplicationError> {
        Err(Self::disabled())
    }

    fn latest_shadowing_analysis(
        &self,
        _recording_id: &RecordingAssetId,
    ) -> Result<Option<ShadowingAnalysisRecord>, ApplicationError> {
        Err(Self::disabled())
    }
}

fn resolve_ctc_model_dir() -> Option<String> {
    if let Ok(path) = std::env::var("LLPLAYERNEXT_PHONEME_MODEL_DIR")
        && std::path::Path::new(&path).is_dir()
    {
        return Some(path);
    }
    if let Some(home) = std::env::var_os("HOME") {
        let default = std::path::PathBuf::from(home)
            .join("Library/Application Support/LLPlayerNext/models/wav2vec2-phoneme");
        if default.is_dir() {
            return Some(default.to_string_lossy().into_owned());
        }
    }
    None
}

fn resolve_ctc_model_revision() -> String {
    std::env::var("LLPLAYERNEXT_PHONEME_MODEL_REVISION")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| speech_analysis::phonetics::PHONE_PROVIDER_VERSION.into())
}

fn sha256_file(path: impl AsRef<std::path::Path>) -> std::io::Result<String> {
    let mut file = std::fs::File::open(path)?;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        digest.update(&buffer[..read]);
    }
    Ok(hex::encode(digest.finalize()))
}
