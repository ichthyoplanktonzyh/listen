//! Focused media-only learning-material wire tests (contract `5.1.0`).
//!
//! These tests pin the explicit response/input DTO shapes used by the active
//! audio/video material path. Components remain typed and path-free.

use crate::routes::material::{
    MaterialDetailsResponse, MediaRenditionInputRequest, SourceAssetInputRequest,
};
use domain::{
    LearningMaterial, MaterialRevision, MediaId, MediaKind, MediaRendition, Rendition,
    RenditionOrigin, initial_material_id,
};

fn media_rendition() -> Rendition {
    Rendition::Media(
        MediaRendition::new(
            RenditionOrigin::Source,
            MediaKind::Video,
            "video/mp4",
            "fp-media-1",
            domain::MediaAvailability::Available,
            Some(MediaId::parse("media-1").expect("media id")),
            None,
            None,
            None,
            None,
        )
        .expect("valid media rendition"),
    )
}

fn details() -> MaterialDetailsResponse {
    let renditions = vec![media_rendition()];
    let material_id = initial_material_id(&[], &renditions).expect("deterministic material id");
    let revision = MaterialRevision::new(material_id, "Wire Title", Vec::new(), renditions, 7)
        .expect("valid revision");
    let material = LearningMaterial::new(&revision, Some(7), 7, 7).expect("valid material");
    MaterialDetailsResponse::from(application::MaterialDetails {
        material,
        current_revision: revision,
    })
}

fn assert_no_path_key(value: &serde_json::Value) {
    match value {
        serde_json::Value::Object(map) => {
            assert!(
                !map.contains_key("path"),
                "wire shape must not expose a path key: {value}"
            );
            for nested in map.values() {
                assert_no_path_key(nested);
            }
        }
        serde_json::Value::Array(items) => {
            for nested in items {
                assert_no_path_key(nested);
            }
        }
        _ => {}
    }
}

#[test]
fn material_wire_dtos_are_media_typed_and_path_free() {
    let wire = serde_json::to_value(details()).expect("serialize details response");
    assert_eq!(wire["shape"], "video");

    let material = &wire["material"];
    let mut material_keys: Vec<_> = material.as_object().unwrap().keys().collect();
    material_keys.sort_unstable();
    assert_eq!(
        material_keys,
        vec![
            "created_at_ms",
            "current_revision_id",
            "id",
            "retained_at_ms",
            "updated_at_ms"
        ]
    );
    assert_eq!(material["retained_at_ms"], 7);

    let revision = &wire["current_revision"];
    let mut revision_keys: Vec<_> = revision.as_object().unwrap().keys().collect();
    revision_keys.sort_unstable();
    assert_eq!(
        revision_keys,
        vec![
            "created_at_ms",
            "id",
            "material_id",
            "media_renditions",
            "source_assets",
            "title"
        ]
    );
    assert_eq!(revision["title"], "Wire Title");
    assert!(revision["source_assets"].as_array().unwrap().is_empty());
    let renditions = revision["media_renditions"].as_array().unwrap();
    assert_eq!(renditions.len(), 1);
    assert_eq!(renditions[0]["origin"], "source");
    assert_eq!(renditions[0]["media_id"], "media-1");
    assert_eq!(renditions[0]["kind"], "video");
    assert_eq!(renditions[0]["availability"], "available");
    assert_eq!(renditions[0]["fingerprint"], "fp-media-1");
    assert_no_path_key(&wire);
}

#[test]
fn material_input_dtos_deserialize_media_components() {
    let source: serde_json::Value = serde_json::from_value(serde_json::json!({
        "media_type": "audio/mpeg",
        "byte_length": 1024,
        "sha256_digest": "ab12",
        "binding": { "type": "managed" },
    }))
    .expect("source asset input");
    let _: SourceAssetInputRequest =
        serde_json::from_value(source.clone()).expect("typed source asset input");
    assert_eq!(source["media_type"], "audio/mpeg");

    let rendition: serde_json::Value =
        serde_json::from_value(serde_json::json!({ "media_id": "media-1" }))
            .expect("media rendition input");
    let _: MediaRenditionInputRequest =
        serde_json::from_value(rendition.clone()).expect("typed media rendition input");
    assert_eq!(rendition["media_id"], "media-1");
}
