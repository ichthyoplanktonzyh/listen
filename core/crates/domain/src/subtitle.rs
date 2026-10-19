use serde::{Deserialize, Serialize};

use crate::{LanguageCode, MediaId, SubtitleSentenceId, SubtitleTrackId, TimeMs};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SubtitleTrackStatus {
    Available,
    Archived,
}

fn default_subtitle_track_status() -> SubtitleTrackStatus {
    SubtitleTrackStatus::Available
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleTrack {
    pub id: SubtitleTrackId,
    pub media_id: MediaId,
    pub fingerprint: String,
    pub language: Option<LanguageCode>,
    pub source: String,
    #[serde(default = "default_subtitle_track_status")]
    pub status: SubtitleTrackStatus,
    pub sentences: Vec<SubtitleSentence>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleSentence {
    pub id: SubtitleSentenceId,
    pub index: u32,
    pub start: TimeMs,
    pub end: TimeMs,
    pub original_text: String,
    pub display_text: String,
    pub tokens: Vec<SubtitleToken>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SubtitleTokenKind {
    Word,
    Whitespace,
    Punctuation,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubtitleToken {
    pub index: u32,
    pub kind: SubtitleTokenKind,
    pub text: String,
    pub normalized: Option<String>,
    pub start_char: u32,
    pub end_char: u32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SubtitleSearchResult {
    pub id: String,
    pub file_id: u64,
    pub language: String,
    pub release: String,
    pub source: String,
    pub rating: f64,
    pub download_count: u64,
}
