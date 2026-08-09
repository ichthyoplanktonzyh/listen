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
    /// Evidence of explicit Personal Library membership. Non-null means the
    /// media is a library member and carries the deterministic membership
    /// time; null means Temporary Material (registered and readable, but
    /// absent from the media library projection). Availability remains a
    /// separate playback-source fact. The value is set once at first
    /// retention and is never silently rewritten or cleared by repeated
    /// registration or retention.
    #[serde(default)]
    pub retained_at_ms: Option<u64>,
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
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        };

        assert!(item.has_detached_source());
        assert_eq!(item.path, "lltimeline://detached-media");
        // Detached imports are readable without being Personal Library
        // members unless explicitly retained.
        assert_eq!(item.retained_at_ms, None);
    }

    #[test]
    fn media_item_without_retained_at_ms_deserializes_as_temporary() {
        // Backward compatibility: persisted or client-produced MediaItem JSON
        // from before membership became explicit has no `retained_at_ms`
        // field. It must decode as Temporary Material (null membership)
        // rather than failing the parse.
        let json = serde_json::json!({
            "id": "media-old",
            "path": "/tmp/old.mp4",
            "fingerprint": "old-fingerprint",
            "title": "Old",
            "kind": "video",
            "duration": null,
            "availability": "available",
            "created_at_ms": 1,
            "updated_at_ms": 1
        });
        let item: MediaItem = serde_json::from_value(json).expect("old MediaItem JSON parses");
        assert_eq!(item.retained_at_ms, None);
        assert!(!item.has_detached_source());
    }

    #[test]
    fn media_item_serialization_always_states_membership() {
        let item = MediaItem {
            id: MediaId::parse("serialized-media").unwrap(),
            path: "/tmp/serialized.mp4".into(),
            fingerprint: "serialized-fingerprint".into(),
            title: "Serialized".into(),
            kind: MediaKind::Audio,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        let value = serde_json::to_value(&item).expect("MediaItem serializes");
        // Every response states known membership, including null.
        assert!(value.get("retained_at_ms").is_some());
        assert!(value["retained_at_ms"].is_null());
    }
}
