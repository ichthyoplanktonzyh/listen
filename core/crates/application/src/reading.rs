use std::sync::Arc;

use domain::{MediaId, ReadingPosition, SubtitleSentenceId, SubtitleTrackId};

use crate::{ApplicationError, ReadingPositionRepository, now_ms};

/// Reading-posture use cases (Phase 3.13). The position is a per-track
/// cursor with upsert semantics; reading history stays in the append-only
/// semantic-task family and never routes through here.
#[derive(Clone)]
pub struct ReadingUseCases {
    positions: Arc<dyn ReadingPositionRepository>,
}

impl ReadingUseCases {
    pub(crate) fn new(positions: Arc<dyn ReadingPositionRepository>) -> Self {
        Self { positions }
    }

    pub fn reading_position(
        &self,
        track_id: &str,
    ) -> Result<Option<ReadingPosition>, ApplicationError> {
        let track_id = SubtitleTrackId::parse(track_id)?;
        self.positions.get_reading_position(&track_id)
    }

    pub fn save_reading_position(
        &self,
        track_id: &str,
        media_id: Option<&str>,
        anchor_cue_id: &str,
        paragraph_index: u32,
    ) -> Result<ReadingPosition, ApplicationError> {
        let anchor_cue_id = anchor_cue_id.trim();
        if anchor_cue_id.is_empty() {
            return Err(ApplicationError::Invalid(
                "reading position anchor cue id must not be empty".into(),
            ));
        }
        let position = ReadingPosition {
            track_id: SubtitleTrackId::parse(track_id)?,
            media_id: media_id
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(MediaId::parse)
                .transpose()?,
            anchor_cue_id: SubtitleSentenceId::parse(anchor_cue_id)?,
            paragraph_index,
            updated_at_ms: now_ms(),
        };
        self.positions.save_reading_position(&position)
    }
}
