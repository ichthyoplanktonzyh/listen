//! Reading-posture domain facts (Phase 3.13).
//!
//! The reading position is a cursor, not evidence: one overwritable row per
//! subtitle track. Reading history (attempts, judgments, observations) lives
//! in the append-only semantic-task and observation families — never here.

use serde::{Deserialize, Serialize};

use crate::{MediaId, SubtitleSentenceId, SubtitleTrackId};

/// Where the reader left off in one track's derived paragraph view. The
/// anchor is the paragraph's first cue id, so it survives re-derivation of
/// the paragraph grouping; `paragraph_index` is a display hint only.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadingPosition {
    pub track_id: SubtitleTrackId,
    pub media_id: Option<MediaId>,
    pub anchor_cue_id: SubtitleSentenceId,
    pub paragraph_index: u32,
    pub updated_at_ms: u64,
}
