use super::*;
use application::{
    DocumentRenditionInput, MaterialRepository, MaterialUseCases, MediaRenditionInput,
    SourceAssetInput,
};
use domain::{LanguageCode, MediaAvailability, MediaItem, MediaKind, SourceAssetBinding, TimeMs};
use sha2::{Digest, Sha256};
use std::sync::Arc;

#[test]
fn audio_material_revision_and_media_binding_round_trip() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let media = MediaItem {
        id: MediaId::parse("material-audio").unwrap(),
        path: "/tmp/material-audio.mp3".into(),
        fingerprint: "sha256:audio-fingerprint".into(),
        title: "Audio lesson".into(),
        kind: MediaKind::Audio,
        duration: Some(TimeMs::new(12_000)),
        availability: MediaAvailability::Available,
        retained_at_ms: Some(1),
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    MediaRepository::upsert(repo.as_ref(), &media).unwrap();

    let use_cases = MaterialUseCases::new(repo.clone(), repo.clone());
    let source_bytes = b"audio source bytes";
    let details = use_cases
        .create(application::CreateLearningMaterial {
            title: "Audio lesson".into(),
            source_assets: vec![SourceAssetInput {
                media_type: "audio/mpeg".into(),
                byte_length: source_bytes.len() as u64,
                sha256_digest: hex::encode(Sha256::digest(source_bytes)),
                binding: SourceAssetBinding::Managed,
            }],
            document_renditions: Vec::new(),
            media_renditions: vec![MediaRenditionInput {
                media_id: media.id.clone(),
            }],
            retain: Some(true),
        })
        .unwrap();

    assert_eq!(details.shape(), domain::MaterialShape::Audio);
    assert_eq!(details.current_revision.source_assets.len(), 1);
    assert_eq!(details.current_revision.renditions.len(), 1);

    let reopened = use_cases.read(&details.material.id).unwrap().unwrap();
    assert_eq!(reopened.material, details.material);
    assert_eq!(reopened.current_revision, details.current_revision);
    assert_eq!(
        MaterialRepository::material_for_media(repo.as_ref(), &media.id)
            .unwrap()
            .unwrap()
            .id,
        details.material.id
    );
}

#[test]
fn document_material_rendition_round_trips_in_the_fresh_schema() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = MaterialUseCases::new(repo.clone(), repo.clone());
    let source_bytes = b"A short document source.";
    let source_digest = hex::encode(Sha256::digest(source_bytes));
    let details = use_cases
        .create(application::CreateLearningMaterial {
            title: "Document material".into(),
            source_assets: vec![SourceAssetInput {
                media_type: "text/plain".into(),
                byte_length: source_bytes.len() as u64,
                sha256_digest: source_digest.clone(),
                binding: SourceAssetBinding::Managed,
            }],
            document_renditions: vec![DocumentRenditionInput {
                media_type: "text/plain".into(),
                language: Some(LanguageCode::parse("en").unwrap()),
                digest: source_digest,
                byte_size: source_bytes.len() as u64,
                source_asset_index: 0,
            }],
            media_renditions: Vec::new(),
            retain: Some(true),
        })
        .unwrap();

    assert_eq!(details.shape(), domain::MaterialShape::Text);
    assert!(matches!(
        details.current_revision.renditions.as_slice(),
        [domain::Rendition::Document(_)]
    ));
    let reopened = use_cases.read(&details.material.id).unwrap().unwrap();
    assert_eq!(reopened, details);
    assert_eq!(
        repo.connection
            .lock()
            .query_row(
                "SELECT COUNT(*) FROM material_document_renditions",
                [],
                |row| row.get::<_, u32>(0),
            )
            .unwrap(),
        1
    );
}
