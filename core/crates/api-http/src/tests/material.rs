//! Focused learning-material wire tests (contract `4.0.0`).
//!
//! These complement the full-stack HTTP acceptance tests by pinning the
//! explicit response/input DTO shapes defined in `routes/material.rs` and the
//! material schema facts in the canonical OpenAPI document: source assets and
//! document/media renditions are separated typed collections, never the
//! externally-tagged domain serialization, and no material, revision, or
//! rendition wire shape carries a path.

use crate::routes::material::{
    DocumentRenditionInputRequest, MaterialDetailsResponse, MediaRenditionInputRequest,
    SourceAssetInputRequest,
};
use domain::{
    DocumentRendition, LanguageCode, LearningMaterial, MaterialRevision, MediaId, MediaKind,
    MediaRendition, Rendition, RenditionOrigin, initial_material_id,
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

fn document_rendition() -> Rendition {
    Rendition::Document(
        DocumentRendition::new(
            RenditionOrigin::Source,
            "text/plain",
            Some(LanguageCode::parse("en").expect("language")),
            "  exact 字节\n",
            None,
            None,
            None,
        )
        .expect("valid document rendition"),
    )
}

fn details_with(renditions: Vec<Rendition>) -> MaterialDetailsResponse {
    let material_id = initial_material_id(&[], &renditions).expect("deterministic material id");
    let revision = MaterialRevision::new(material_id, "Wire Title", Vec::new(), renditions, 7)
        .expect("valid revision");
    let material = LearningMaterial::new(&revision, Some(7), 7, 7).expect("valid material");
    MaterialDetailsResponse::from(application::MaterialDetails {
        material,
        current_revision: revision,
    })
}

/// Asserts no value in the serialized tree carries a `path` key.
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
            for item in items {
                assert_no_path_key(item);
            }
        }
        _ => {}
    }
}

#[test]
fn material_wire_dtos_are_typed_collections_and_path_free() {
    // A mixed revision (document + media rendition) exercises both rendition
    // shapes.
    let response = details_with(vec![document_rendition(), media_rendition()]);
    let wire = serde_json::to_value(response).expect("serialize details response");

    // MaterialDetails: material, current_revision, shape.
    assert_eq!(wire["shape"], "mixed");
    let material = &wire["material"];
    assert_eq!(
        {
            let mut keys: Vec<_> = material.as_object().unwrap().keys().collect();
            keys.sort_unstable();
            keys
        },
        vec![
            "created_at_ms",
            "current_revision_id",
            "id",
            "retained_at_ms",
            "updated_at_ms"
        ]
    );
    assert_eq!(material["retained_at_ms"], 7);

    // The revision embeds a MaterialRevisionResponse, not the domain record.
    let revision = &wire["current_revision"];
    assert_eq!(
        {
            let mut keys: Vec<_> = revision.as_object().unwrap().keys().collect();
            keys.sort_unstable();
            keys
        },
        vec![
            "created_at_ms",
            "document_renditions",
            "id",
            "material_id",
            "media_renditions",
            "source_assets",
            "title"
        ]
    );
    assert_eq!(revision["title"], "Wire Title");
    assert_eq!(revision["created_at_ms"], 7);
    assert_eq!(
        revision["source_assets"]
            .as_array()
            .expect("source assets array")
            .len(),
        0
    );

    // Document renditions are flat typed objects.
    let documents = revision["document_renditions"]
        .as_array()
        .expect("document renditions array");
    assert_eq!(documents.len(), 1);
    let text = &documents[0];
    assert_eq!(
        {
            let mut keys: Vec<_> = text.as_object().unwrap().keys().collect();
            keys.sort_unstable();
            keys
        },
        vec![
            "id",
            "language",
            "media_type",
            "origin",
            "source_asset_id",
            "text",
            "text_byte_size",
            "text_sha256"
        ]
    );
    assert_eq!(text["origin"], "source");
    assert_eq!(text["text"], "  exact 字节\n");
    assert_eq!(text["text_byte_size"], "  exact 字节\n".len() as u64);
    assert_eq!(text["language"], "en");
    assert!(
        text["text_sha256"]
            .as_str()
            .is_some_and(|digest| digest.len() == 64)
    );

    // Media renditions are flat typed objects too.
    let renditions = revision["media_renditions"]
        .as_array()
        .expect("media renditions array");
    assert_eq!(renditions.len(), 1);
    let rendition = &renditions[0];
    assert_eq!(
        {
            let mut keys: Vec<_> = rendition.as_object().unwrap().keys().collect();
            keys.sort_unstable();
            keys
        },
        vec![
            "availability",
            "fingerprint",
            "id",
            "kind",
            "media_byte_size",
            "media_id",
            "media_sha256",
            "media_type",
            "origin"
        ]
    );
    assert_eq!(rendition["origin"], "source");
    assert_eq!(rendition["media_id"], "media-1");
    assert_eq!(rendition["kind"], "video");
    assert_eq!(rendition["availability"], "available");
    assert_eq!(rendition["fingerprint"], "fp-media-1");

    // No material, revision, or rendition value anywhere carries a path.
    assert_no_path_key(&wire);
}

#[test]
fn material_input_dtos_deserialize_typed_components() {
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

    let text: serde_json::Value = serde_json::from_value(serde_json::json!({
        "media_type": "text/plain",
        "language": null,
        "text": "typed input",
        "source_asset_index": null,
    }))
    .expect("document rendition input");
    let _: DocumentRenditionInputRequest =
        serde_json::from_value(text.clone()).expect("typed document rendition input");
    assert_eq!(text["text"], "typed input");

    let rendition: serde_json::Value = serde_json::from_value(serde_json::json!({
        "media_id": "media-1",
    }))
    .expect("media rendition input");
    let _: MediaRenditionInputRequest =
        serde_json::from_value(rendition.clone()).expect("typed media rendition input");
    assert_eq!(rendition["media_id"], "media-1");
}

#[test]
fn openapi_material_schemas_match_wire_semantics() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    // The canonical material schemas were appended contiguously, so the tail
    // from LearningMaterial covers them.
    let tail = openapi
        .split("    LearningMaterial:\n")
        .nth(1)
        .expect("LearningMaterial schema exists");

    // Membership evidence is required but nullable on the material.
    let learning_material = tail
        .split("    MaterialRevision:\n")
        .next()
        .expect("LearningMaterial block precedes MaterialRevision");
    assert!(
        learning_material.contains(
            "required: [id, current_revision_id, retained_at_ms, created_at_ms, updated_at_ms]"
        ),
        "LearningMaterial must require retained_at_ms: {learning_material}"
    );
    assert!(
        learning_material.contains("type: [integer, \"null\"]"),
        "LearningMaterial retained_at_ms must be nullable"
    );

    // MaterialDetails requires the shape dimension.
    assert!(
        tail.contains("required: [material, current_revision, shape]"),
        "MaterialDetails must carry material, current_revision, and shape"
    );

    // The composition shape enum matches the domain values.
    assert!(
        tail.contains("enum: [text, audio, video, mixed]"),
        "shape enum must list text, audio, video, mixed"
    );

    // The revision carries three separated typed component collections.
    for fragment in [
        "source_assets:",
        "document_renditions:",
        "media_renditions:",
    ] {
        assert!(
            tail.contains(fragment),
            "MaterialRevision must carry a {fragment} collection"
        );
    }
    assert!(
        tail.contains("items: { $ref: \"#/components/schemas/SourceAsset\" }"),
        "source_assets must reference the SourceAsset schema"
    );
    assert!(
        tail.contains("items: { $ref: \"#/components/schemas/DocumentRendition\" }"),
        "document_renditions must reference the DocumentRendition schema"
    );
    assert!(
        tail.contains("items: { $ref: \"#/components/schemas/MediaRendition\" }"),
        "media_renditions must reference the MediaRendition schema"
    );

    // The concrete component schemas never degrade to free-form objects.
    for (name, required_fragment) in [
        (
            "SourceAsset",
            "id, media_type, byte_length, sha256_digest, binding, availability, created_at_ms",
        ),
        (
            "DocumentRendition",
            "id, origin, media_type, language, text, text_sha256, text_byte_size, source_asset_id",
        ),
        (
            "MediaRendition",
            "id, origin, kind, media_type, fingerprint, availability, media_id, media_sha256, media_byte_size",
        ),
    ] {
        let block = schema_block(openapi, name);
        assert!(
            block.contains(&format!("required: [{required_fragment}]")),
            "{name} must require its typed columns: {block}"
        );
    }

    // Source Asset input and rendition input request schemas exist for the
    // create/append bodies.
    for name in [
        "SourceAssetInput",
        "DocumentRenditionInput",
        "MediaRenditionInput",
    ] {
        let block = schema_block(openapi, name);
        assert!(
            block.contains("required:"),
            "{name} must exist with required fields: {block}"
        );
    }

    // Material schemas must not define a path property anywhere.
    assert!(
        !tail.contains("        path:"),
        "no material schema may define a path property"
    );
    assert!(
        !tail.contains("path: { type: string }"),
        "material schemas must not type a path as a string"
    );
}

/// Extracts one schema block: from `    <name>:` up to the next line that is
/// indented exactly four spaces (the next schema heading). Content lines are
/// indented six or more spaces, so the first exactly-4-space line ends the
/// block.
fn schema_block<'a>(openapi: &'a str, name: &str) -> &'a str {
    let marker = format!("    {name}:\n");
    let start = openapi
        .find(&marker)
        .unwrap_or_else(|| panic!("schema {name} missing"));
    let mut end = start + marker.len();
    while end < openapi.len() {
        let line_end = openapi[end..]
            .find('\n')
            .map(|offset| end + offset)
            .unwrap_or(openapi.len());
        let line = &openapi[end..line_end];
        if line.starts_with("    ") && !line.starts_with("      ") {
            break;
        }
        end = (line_end + 1).min(openapi.len());
    }
    &openapi[start + marker.len()..end]
}
