//! Focused learning-material wire tests (contract `3.2.0`).
//!
//! These complement the full-stack HTTP acceptance tests by pinning the
//! explicit response/input DTO shapes defined in `routes/material.rs` and the
//! material schema facts in the canonical OpenAPI document: assets are flat
//! `asset_type`-discriminated objects, never the externally-tagged domain
//! serialization, and no material, revision, or asset wire shape carries a
//! path.

use crate::routes::material::{MaterialAssetInputRequest, MaterialDetailsResponse};
use domain::{
    DocumentTextAsset, LanguageCode, LearningMaterial, MaterialAsset, MaterialRevision,
    MediaAvailability, MediaId, MediaKind, MediaRenditionAsset, initial_material_id,
};

fn media_asset() -> MaterialAsset {
    MaterialAsset::MediaRendition(
        MediaRenditionAsset::new(
            MediaId::parse("media-1").expect("media id"),
            MediaKind::Video,
            "fp-media-1",
            MediaAvailability::Available,
        )
        .expect("valid rendition asset"),
    )
}

fn text_asset() -> MaterialAsset {
    MaterialAsset::DocumentText(
        DocumentTextAsset::new(
            "  exact 字节\n",
            Some(LanguageCode::parse("en").expect("language")),
        )
        .expect("valid text asset"),
    )
}

fn details_with(assets: Vec<MaterialAsset>) -> MaterialDetailsResponse {
    let material_id = initial_material_id(&assets).expect("deterministic material id");
    let revision =
        MaterialRevision::new(material_id, "Wire Title", assets, 7).expect("valid revision");
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
fn material_wire_dtos_are_flat_discriminated_and_path_free() {
    // A mixed revision (text + media rendition) exercises both asset shapes.
    let response = details_with(vec![text_asset(), media_asset()]);
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
        vec!["assets", "created_at_ms", "id", "material_id", "title"]
    );
    assert_eq!(revision["title"], "Wire Title");
    assert_eq!(revision["created_at_ms"], 7);

    // Assets are flat `asset_type`-discriminated objects (never the
    // externally-tagged `{"document_text": {...}}` domain form).
    let assets = revision["assets"].as_array().expect("assets array");
    assert_eq!(assets.len(), 2);

    let text = assets
        .iter()
        .find(|asset| asset["asset_type"] == "document_text")
        .expect("document_text asset");
    assert_eq!(
        {
            let mut keys: Vec<_> = text.as_object().unwrap().keys().collect();
            keys.sort_unstable();
            keys
        },
        vec![
            "asset_type",
            "byte_size",
            "id",
            "language",
            "sha256_digest",
            "text"
        ]
    );
    assert_eq!(text["text"], "  exact 字节\n");
    assert_eq!(text["byte_size"], "  exact 字节\n".len() as u64);
    assert_eq!(text["language"], "en");
    assert!(
        text["sha256_digest"]
            .as_str()
            .is_some_and(|digest| digest.len() == 64)
    );

    let rendition = assets
        .iter()
        .find(|asset| asset["asset_type"] == "media_rendition")
        .expect("media_rendition asset");
    assert_eq!(
        {
            let mut keys: Vec<_> = rendition.as_object().unwrap().keys().collect();
            keys.sort_unstable();
            keys
        },
        vec![
            "asset_type",
            "availability",
            "fingerprint",
            "id",
            "media_id",
            "media_kind"
        ]
    );
    assert_eq!(rendition["media_id"], "media-1");
    assert_eq!(rendition["media_kind"], "video");
    assert_eq!(rendition["availability"], "available");
    assert_eq!(rendition["fingerprint"], "fp-media-1");

    // No material, revision, or asset value anywhere carries a path.
    assert_no_path_key(&wire);
}

#[test]
fn material_input_dtos_deserialize_by_asset_type_discriminator() {
    let text: MaterialAssetInputRequest = serde_json::from_value(serde_json::json!({
        "asset_type": "document_text",
        "text": "typed input",
        "language": null,
    }))
    .expect("document_text input");
    assert!(matches!(
        text,
        MaterialAssetInputRequest::DocumentText { ref text, ref language }
            if text == "typed input" && language.is_none()
    ));

    let rendition: MaterialAssetInputRequest = serde_json::from_value(serde_json::json!({
        "asset_type": "media_rendition",
        "media_id": "media-1",
    }))
    .expect("media_rendition input");
    assert!(matches!(
        rendition,
        MaterialAssetInputRequest::MediaRendition { ref media_id } if media_id == "media-1"
    ));
}

#[test]
fn openapi_material_schemas_match_wire_semantics() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    // All material schemas were appended contiguously at the end of the
    // components section, so the tail from LearningMaterial covers them.
    let tail = openapi
        .split("    LearningMaterial:\n")
        .nth(1)
        .expect("LearningMaterial schema exists");

    // Membership evidence is required but nullable on the material.
    let learning_material = tail
        .split("    MaterialAsset:\n")
        .next()
        .expect("LearningMaterial block precedes MaterialAsset");
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

    // The asset unions are real oneOf discriminator unions over their two
    // concrete variants — never a plain object that only declares asset_type.
    let material_asset = schema_block(openapi, "MaterialAsset");
    assert!(
        material_asset.contains("oneOf:"),
        "MaterialAsset must be a oneOf union: {material_asset}"
    );
    assert!(
        material_asset.contains("- $ref: \"#/components/schemas/DocumentTextAsset\"")
            && material_asset.contains("- $ref: \"#/components/schemas/MediaRenditionAsset\""),
        "MaterialAsset must reference both concrete asset variants: {material_asset}"
    );
    assert!(
        material_asset.contains("propertyName: asset_type")
            && material_asset.contains("document_text: \"#/components/schemas/DocumentTextAsset\"")
            && material_asset
                .contains("media_rendition: \"#/components/schemas/MediaRenditionAsset\""),
        "MaterialAsset discriminator must map both asset types: {material_asset}"
    );
    assert!(
        !material_asset.contains("properties:"),
        "MaterialAsset must not degrade to a properties-only object: {material_asset}"
    );

    let material_asset_input = schema_block(openapi, "MaterialAssetInput");
    assert!(
        material_asset_input.contains("oneOf:")
            && material_asset_input
                .contains("- $ref: \"#/components/schemas/DocumentTextAssetInput\"")
            && material_asset_input
                .contains("- $ref: \"#/components/schemas/MediaRenditionAssetInput\""),
        "MaterialAssetInput must oneOf both concrete input variants: {material_asset_input}"
    );
    assert!(
        material_asset_input.contains("propertyName: asset_type"),
        "MaterialAssetInput discriminator must key on asset_type"
    );

    // Revision and create/append request arrays reference the unions.
    assert!(
        tail.contains("items: { $ref: \"#/components/schemas/MaterialAsset\" }"),
        "MaterialRevision assets must reference the MaterialAsset union"
    );
    assert!(
        tail.contains("items: { $ref: \"#/components/schemas/MaterialAssetInput\" }"),
        "CreateLearningMaterial and AppendMaterialRevision assets must reference MaterialAssetInput"
    );

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
