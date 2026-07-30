use serde::{Deserialize, Serialize};

use crate::{MediaId, TimeMs};

pub const DETACHED_MEDIA_PATH_PREFIX: &str = "lltimeline://";

pub fn detached_media_path(id: &MediaId) -> String {
    format!("{DETACHED_MEDIA_PATH_PREFIX}{}", id.as_str())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaKind {
    Video,
    Audio,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaAvailability {
    Available,
    Missing,
    Archived,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MediaItem {
    pub id: MediaId,
    pub path: String,
    pub fingerprint: String,
    pub title: String,
    pub kind: MediaKind,
    pub duration: Option<TimeMs>,
    pub availability: MediaAvailability,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

impl MediaItem {
    pub fn has_detached_source(&self) -> bool {
        self.path.starts_with(DETACHED_MEDIA_PATH_PREFIX)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detached_media_paths_are_explicitly_non_file_sources() {
        let id = MediaId::parse("detached-media").unwrap();
        let item = MediaItem {
            id: id.clone(),
            path: detached_media_path(&id),
            fingerprint: "fingerprint".into(),
            title: "Detached".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Missing,
            created_at_ms: 1,
            updated_at_ms: 1,
        };

        assert!(item.has_detached_source());
        assert_eq!(item.path, "lltimeline://detached-media");
    }
}
