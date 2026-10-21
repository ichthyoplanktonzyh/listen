use std::sync::Arc;

use domain::{RecordingAsset, RecordingAssetId};

use crate::{ApplicationError, CreateRecordingAsset, RecordingRepository, clean_required, now_ms};

pub struct RecordingUseCases {
    recordings: Arc<dyn RecordingRepository>,
}

impl RecordingUseCases {
    pub(crate) fn new(recordings: Arc<dyn RecordingRepository>) -> Self {
        Self { recordings }
    }

    pub fn create_recording_asset(
        &self,
        input: CreateRecordingAsset,
    ) -> Result<RecordingAsset, ApplicationError> {
        let file_path = clean_required(input.file_path, "recording file path")?;
        let recorder_version = clean_required(input.recorder_version, "recording version")?;
        let container = clean_required(input.audio.container, "recording container")?;
        let codec = clean_required(input.audio.codec, "recording codec")?;
        let sample_format = clean_required(input.audio.sample_format, "recording format")?;
        let content_sha256 = input.audio.content_sha256.trim().to_ascii_lowercase();
        let has_source_media = input.source_segment.media_id.is_some();
        if input.duration_ms == 0
            || input.audio.sample_rate_hz == 0
            || input.audio.channels == 0
            || input.audio.byte_length == 0
            || content_sha256.len() != 64
            || !content_sha256
                .bytes()
                .all(|value| value.is_ascii_hexdigit())
            || (has_source_media && input.source_segment.end_ms <= input.source_segment.start_ms)
            || (!has_source_media && input.source_segment.start_ms != input.source_segment.end_ms)
        {
            return Err(ApplicationError::Validation("recording metadata"));
        }

        let created_at_ms = now_ms();
        let id = RecordingAssetId::from_fingerprint(
            "recording-asset",
            &format!("{content_sha256}:{}", created_at_ms),
        );
        self.recordings.save_recording_asset(&RecordingAsset {
            id,
            file_path,
            created_at_ms,
            duration_ms: input.duration_ms,
            target: input.target,
            source_segment: input.source_segment,
            language: input.language,
            audio: domain::RecordingAudioMetadata {
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
}
