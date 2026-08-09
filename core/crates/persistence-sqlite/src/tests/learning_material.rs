//! Repository-level acceptance tests for durable learning material.
//!
//! These tests exercise the real SQLite `MaterialRepository` — through the
//! `AppServices::new(...).with_material_repository(...).materials()` use cases
//! where a use case adds value, and directly on the repository where the
//! contract is repo-level (idempotent retries, conflict rollback, corruption
//! detection, membership synchronization).

use application::{
    AppendMaterialRevision, CreateLearningMaterial, MaterialAssetInput, MaterialRepository,
    PlaybackProgressRepository,
};

use super::*;
use crate::learning_material::{LEGACY_BLANK_TITLE_FALLBACK, backfill_legacy_media_materials};

/// AppServices with the real SQLite repository behind the material and media
/// seams.
fn services(repo: &Arc<SqliteRepository>) -> AppServices {
    AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_material_repository(repo.clone())
}

/// Registers a Temporary Material row (no membership) through the real media
/// repository.
fn register_media(repo: &Arc<SqliteRepository>, id: &str, kind: MediaKind) -> MediaItem {
    MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse(id).unwrap(),
            path: format!("/tmp/{id}.media"),
            fingerprint: format!("{id}-fp"),
            title: format!("title-{id}"),
            kind,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        },
    )
    .unwrap()
}

fn text_input(text: &str) -> MaterialAssetInput {
    MaterialAssetInput::DocumentText {
        text: text.to_owned(),
        language: None,
    }
}

fn media_input(id: &str) -> MaterialAssetInput {
    MaterialAssetInput::MediaRendition {
        media_id: MediaId::parse(id).unwrap(),
    }
}

fn count(repo: &SqliteRepository, table: &str) -> u32 {
    repo.connection
        .lock()
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .unwrap()
}

/// Graph row counts in a fixed order, used to prove that a rejected
/// candidate leaves no graph rows behind.
fn graph_counts(repo: &SqliteRepository) -> (u32, u32, u32, u32) {
    (
        count(repo, "learning_materials"),
        count(repo, "material_revisions"),
        count(repo, "material_assets"),
        count(repo, "material_media_bindings"),
    )
}

/// A media row's membership columns, used to prove that a rejected candidate
/// never synchronizes media membership.
fn media_membership(repo: &SqliteRepository, id: &str) -> (Option<u64>, u64) {
    let conn = repo.connection.lock();
    conn.query_row(
        "SELECT retained_at_ms, updated_at_ms FROM media_items WHERE id=?1",
        [id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .unwrap()
}

/// `learning_materials` row as a JSON object, in SELECT order. Used to prove
/// that a membership mutation changes exactly `retained_at_ms` and
/// `updated_at_ms`.
fn material_row(repo: &SqliteRepository, id: &str) -> serde_json::Value {
    let conn = repo.connection.lock();
    conn.query_row(
        "SELECT id,current_revision_id,retained_at_ms,created_at_ms,updated_at_ms
         FROM learning_materials WHERE id=?1",
        [id],
        |row| {
            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "current_revision_id": row.get::<_, String>(1)?,
                "retained_at_ms": row.get::<_, Option<u64>>(2)?,
                "created_at_ms": row.get::<_, u64>(3)?,
                "updated_at_ms": row.get::<_, u64>(4)?,
            }))
        },
    )
    .unwrap()
}

/// `media_items` row as a JSON object, in SELECT order. Used to prove that a
/// membership mutation changes exactly `retained_at_ms` and `updated_at_ms`.
fn media_row(repo: &SqliteRepository, id: &str) -> serde_json::Value {
    let conn = repo.connection.lock();
    conn.query_row(
        "SELECT id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms,availability,retained_at_ms
         FROM media_items WHERE id=?1",
        [id],
        |row| {
            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "path": row.get::<_, String>(1)?,
                "fingerprint": row.get::<_, String>(2)?,
                "title": row.get::<_, String>(3)?,
                "kind": row.get::<_, String>(4)?,
                "duration_ms": row.get::<_, Option<u64>>(5)?,
                "created_at_ms": row.get::<_, u64>(6)?,
                "updated_at_ms": row.get::<_, u64>(7)?,
                "availability": row.get::<_, String>(8)?,
                "retained_at_ms": row.get::<_, Option<u64>>(9)?,
            }))
        },
    )
    .unwrap()
}

/// Stored `material_assets.asset_json` values for one revision, in ordinal
/// order.
fn stored_asset_json(repo: &SqliteRepository, revision_id: &str) -> Vec<String> {
    let conn = repo.connection.lock();
    let mut statement = conn
        .prepare(
            "SELECT asset_json FROM material_assets
             WHERE revision_id=?1 ORDER BY ordinal",
        )
        .unwrap();
    statement
        .query_map([revision_id], |row| row.get::<_, String>(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
}

#[test]
fn create_covers_text_media_and_mixed_shapes_and_reads_back_faithfully() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);

    let text = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Notes".into(),
            assets: vec![text_input("plain notes")],
            retain: None,
        })
        .unwrap();
    assert_eq!(text.shape(), MaterialShape::Text);

    register_media(&repo, "media-audio", MediaKind::Audio);
    let audio = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Audio".into(),
            assets: vec![media_input("media-audio")],
            retain: None,
        })
        .unwrap();
    assert_eq!(audio.shape(), MaterialShape::Audio);

    register_media(&repo, "media-video", MediaKind::Video);
    let video = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Video".into(),
            assets: vec![media_input("media-video")],
            retain: None,
        })
        .unwrap();
    assert_eq!(video.shape(), MaterialShape::Video);

    let mixed = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Mixed".into(),
            assets: vec![text_input("with notes"), media_input("media-audio")],
            retain: None,
        })
        .unwrap();
    assert_eq!(mixed.shape(), MaterialShape::Mixed);
    // One raw media -> one canonical material: media-audio already owns its
    // deterministic material, so the mixed revision converges on that same
    // material instead of creating a second one.
    assert_eq!(
        mixed.material.id, audio.material.id,
        "a media input bound to its material converges on that material"
    );

    // The repository rehydrates exactly what it persisted.
    let read = services
        .materials()
        .read(&mixed.material.id)
        .unwrap()
        .unwrap();
    assert_eq!(read.material, mixed.material);
    assert_eq!(read.current_revision, mixed.current_revision);
    let assets = read.current_revision.assets;
    assert_eq!(assets.len(), 2);
    assert_eq!(
        assets
            .iter()
            .filter(|asset| matches!(asset, MaterialAsset::MediaRendition(_)))
            .count(),
        1
    );
    assert_eq!(
        assets
            .iter()
            .filter(|asset| matches!(asset, MaterialAsset::DocumentText(_)))
            .count(),
        1
    );
}

#[test]
fn retained_and_temporary_materials_list_deterministically() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);

    let kept = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Kept".into(),
            assets: vec![text_input("kept content")],
            retain: None,
        })
        .unwrap();
    let explicit = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Explicit".into(),
            assets: vec![text_input("explicit content")],
            retain: Some(true),
        })
        .unwrap();
    let temporary = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Temporary".into(),
            assets: vec![text_input("temporary content")],
            retain: Some(false),
        })
        .unwrap();

    let listed = services.materials().list_retained().unwrap();
    let listed_ids: Vec<&str> = listed.iter().map(|d| d.material.id.as_str()).collect();
    assert_eq!(listed.len(), 2);
    assert!(listed_ids.contains(&kept.material.id.as_str()));
    assert!(listed_ids.contains(&explicit.material.id.as_str()));
    assert!(
        !listed_ids.contains(&temporary.material.id.as_str()),
        "the temporary material's exact id must be absent from the retained list"
    );

    // The repository lists only non-null membership, in deterministic order.
    let direct = MaterialRepository::list_retained_materials(repo.as_ref()).unwrap();
    assert_eq!(direct.len(), 2);
    let ids: Vec<&str> = direct.iter().map(|m| m.id.as_str()).collect();
    let mut sorted = ids.clone();
    sorted.sort();
    assert_eq!(ids, sorted, "list order is deterministic by id");
    for material in direct {
        assert!(
            material.retained_at_ms.is_some(),
            "temporary materials never appear in the retained list"
        );
    }
}

#[test]
fn current_and_historical_revisions_read_back() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);

    let v1 = services
        .materials()
        .create(CreateLearningMaterial {
            title: "V1".into(),
            assets: vec![text_input("first content")],
            retain: None,
        })
        .unwrap();
    let material_id = v1.material.id.clone();
    let v1_id = v1.current_revision.id.clone();

    let v2 = services
        .materials()
        .append_revision(
            &material_id,
            AppendMaterialRevision {
                title: "V2".into(),
                assets: vec![text_input("second content")],
            },
        )
        .unwrap();
    let v2_id = v2.current_revision.id.clone();

    let v3 = services
        .materials()
        .append_revision(
            &material_id,
            AppendMaterialRevision {
                title: "V3".into(),
                assets: vec![text_input("third content")],
            },
        )
        .unwrap();
    let v3_id = v3.current_revision.id.clone();
    assert_eq!(v3.material.current_revision_id, v3_id);

    // The current read is the latest revision.
    let current = services.materials().read(&material_id).unwrap().unwrap();
    assert_eq!(current.material.current_revision_id, v3_id);
    assert_eq!(current.current_revision.title, "V3");

    // Historical revisions stay readable with exact ownership.
    let read_v1 = services
        .materials()
        .read_revision(&material_id, &v1_id)
        .unwrap();
    assert_eq!(read_v1.title, "V1");
    assert_eq!(read_v1.material_id, material_id);
    let read_v2 = services
        .materials()
        .read_revision(&material_id, &v2_id)
        .unwrap();
    assert_eq!(read_v2.title, "V2");
    assert_eq!(read_v2.material_id, material_id);

    // Direct repository read rehydrates the historical revision too.
    let direct = repo
        .get_revision(&v2_id)
        .unwrap()
        .expect("historical revision stored");
    assert_eq!(direct.title, "V2");
    assert_eq!(direct.material_id, material_id);
    assert_eq!(direct.assets.len(), 1);

    // A revision belongs to exactly one material.
    let other = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Other".into(),
            assets: vec![text_input("other content")],
            retain: None,
        })
        .unwrap();
    let err = services
        .materials()
        .read_revision(&other.material.id, &v1_id)
        .expect_err("revision belongs to another material");
    assert!(matches!(
        err,
        ApplicationError::NotFound("material revision")
    ));
    let err = services
        .materials()
        .read_revision(
            &material_id,
            &MaterialRevisionId::from_fingerprint("material-revision", "missing"),
        )
        .expect_err("missing revision");
    assert!(matches!(
        err,
        ApplicationError::NotFound("material revision")
    ));
}

#[test]
fn equal_content_retry_converges_without_duplicates_or_overwrites() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);

    let first = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Same".into(),
            assets: vec![text_input("identical content")],
            retain: None,
        })
        .unwrap();
    let retry = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Same".into(),
            assets: vec![text_input("identical content")],
            retain: None,
        })
        .unwrap();
    assert_eq!(retry.material.id, first.material.id);
    assert_eq!(
        retry.material.current_revision_id, first.material.current_revision_id,
        "equal-content retries converge on the same revision"
    );
    assert_eq!(
        retry.material.updated_at_ms, first.material.updated_at_ms,
        "an idempotent retry must not advance the update time"
    );
    assert_eq!(count(&repo, "learning_materials"), 1);
    assert_eq!(count(&repo, "material_revisions"), 1);

    // Direct repo-level create retry returns the actual stored aggregate.
    let stored_material = repo.get_material(&first.material.id).unwrap().unwrap();
    let stored_revision = repo
        .get_revision(&first.material.current_revision_id)
        .unwrap()
        .unwrap();
    let again =
        MaterialRepository::create_material(repo.as_ref(), &stored_material, &stored_revision)
            .unwrap();
    assert_eq!(again, stored_material);
    assert_eq!(count(&repo, "learning_materials"), 1);

    // A different create under an existing material identity must never
    // silently overwrite the stored aggregate.
    let asset = DocumentTextAsset::new("identical content", None).unwrap();
    let assets = vec![MaterialAsset::DocumentText(asset)];
    let material_id = initial_material_id(&assets).unwrap();
    assert_eq!(material_id, first.material.id);
    let different =
        MaterialRevision::new(material_id.clone(), "Different title", assets, 1).unwrap();
    let material = LearningMaterial::new(&different, None, 1, 1).unwrap();
    let err = MaterialRepository::create_material(repo.as_ref(), &material, &different)
        .expect_err("different create under an existing identity");
    assert!(matches!(err, ApplicationError::Conflict(_)));
    let stored = repo.get_material(&first.material.id).unwrap().unwrap();
    assert_eq!(
        stored.current_revision_id, first.material.current_revision_id,
        "the conflicting create left the stored aggregate untouched"
    );
}

#[test]
fn forged_material_candidates_are_rejected_atomically() {
    // The domain structs have public fields, so a caller can forge a material
    // that serde would accept but no constructor would ever produce. The
    // repository must reject it as Repository with no graph or media writes.
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    register_media(&repo, "media-forged", MediaKind::Audio);

    let rendition = MediaRenditionAsset::new(
        MediaId::parse("media-forged").unwrap(),
        MediaKind::Audio,
        "media-forged-fp".to_owned(),
        MediaAvailability::Available,
    )
    .unwrap();
    let assets = vec![MaterialAsset::MediaRendition(rendition)];
    let material_id = initial_material_id(&assets).unwrap();
    let revision = MaterialRevision::new(material_id.clone(), "Canonical", assets, 1000).unwrap();
    let valid = LearningMaterial::new(&revision, Some(1000), 1000, 1000).unwrap();

    let before = graph_counts(&repo);
    let media_before = media_membership(&repo, "media-forged");

    // Forged current_revision_id pointer: must not be inserted as the row's
    // current revision, and must not converge on any existing row.
    let mut forged_pointer = valid.clone();
    forged_pointer.current_revision_id =
        MaterialRevisionId::from_fingerprint("material-revision", "forged-pointer");
    let err = MaterialRepository::create_material(repo.as_ref(), &forged_pointer, &revision)
        .expect_err("forged current revision pointer");
    assert!(matches!(err, ApplicationError::Repository(_)));

    // Forged material id not derived from the initial assets.
    let mut forged_id = valid.clone();
    forged_id.id = LearningMaterialId::parse("material-forged-id").unwrap();
    let err = MaterialRepository::create_material(repo.as_ref(), &forged_id, &revision)
        .expect_err("forged material id");
    assert!(matches!(err, ApplicationError::Repository(_)));

    // Forged timestamp relation (updated before created).
    let mut forged_time = valid.clone();
    forged_time.updated_at_ms = 999;
    let err = MaterialRepository::create_material(repo.as_ref(), &forged_time, &revision)
        .expect_err("forged timestamp relation");
    assert!(matches!(err, ApplicationError::Repository(_)));

    // None of the forged candidates wrote a graph row or touched media.
    assert_eq!(graph_counts(&repo), before);
    assert_eq!(media_membership(&repo, "media-forged"), media_before);
}

#[test]
fn forged_revision_candidates_are_rejected_atomically() {
    // Forged revision fields (title, asset content, digest) and a
    // non-canonical asset order must be rejected before any row read or write,
    // on both the create and append paths.
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    register_media(&repo, "media-forge-b", MediaKind::Video);

    let created = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Canonical".into(),
            assets: vec![text_input("canonical text")],
            retain: Some(false),
        })
        .unwrap();
    let material_id = created.material.id.clone();
    let material = repo.get_material(&material_id).unwrap().unwrap();
    let revision = repo
        .get_revision(&created.material.current_revision_id)
        .unwrap()
        .unwrap();
    let before = graph_counts(&repo);
    let material_before = material_row(&repo, material_id.as_str());

    // Forged title.
    let mut forged_title = revision.clone();
    forged_title.title = "Tampered title".into();

    // Forged asset content: text mutated while id/digest/byte_size stay stale.
    let mut forged_text = revision.clone();
    let MaterialAsset::DocumentText(asset) = &mut forged_text.assets[0] else {
        panic!("expected a document text asset");
    };
    asset.text = "tampered text".into();

    // Forged digest.
    let mut forged_digest = revision.clone();
    let MaterialAsset::DocumentText(asset) = &mut forged_digest.assets[0] else {
        panic!("expected a document text asset");
    };
    asset.sha256_digest = "0".repeat(64);

    // Internally inconsistent: the same revision id with an extra media asset.
    let mut forged_new_media = revision.clone();
    forged_new_media.assets.push(MaterialAsset::MediaRendition(
        MediaRenditionAsset::new(
            MediaId::parse("media-forge-b").unwrap(),
            MediaKind::Video,
            "media-forge-b-fp".to_owned(),
            MediaAvailability::Available,
        )
        .unwrap(),
    ));

    for (label, forged) in [
        ("forged title", forged_title),
        ("forged asset text", forged_text),
        ("forged asset digest", forged_digest),
    ] {
        let err = MaterialRepository::create_material(repo.as_ref(), &material, &forged)
            .expect_err("create with {label}");
        assert!(matches!(err, ApplicationError::Repository(_)));
        let err = MaterialRepository::append_revision(repo.as_ref(), &material_id, &forged, 5000)
            .expect_err("append with {label}");
        assert!(matches!(err, ApplicationError::Repository(_)));
        assert_eq!(
            graph_counts(&repo),
            before,
            "a rejected {label} candidate must not write graph rows"
        );
        assert_eq!(
            material_row(&repo, material_id.as_str()),
            material_before,
            "a rejected {label} candidate must not advance the material"
        );
    }

    // A forged append carrying an inconsistent media asset list must neither
    // write a binding nor synchronize media membership.
    let err =
        MaterialRepository::append_revision(repo.as_ref(), &material_id, &forged_new_media, 5000)
            .expect_err("append with an inconsistent asset list");
    assert!(matches!(err, ApplicationError::Repository(_)));
    assert_eq!(graph_counts(&repo), before);
    assert_eq!(material_row(&repo, material_id.as_str()), material_before);
    assert_eq!(
        media_membership(&repo, "media-forge-b"),
        (None, 1),
        "a rejected append must not synchronize media membership"
    );

    // Non-canonical asset order (same asset set, swapped) is rejected too.
    let mixed = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Mixed canonical".into(),
            assets: vec![text_input("mixed note"), media_input("media-forge-b")],
            retain: Some(false),
        })
        .unwrap();
    let mixed_revision = repo
        .get_revision(&mixed.material.current_revision_id)
        .unwrap()
        .unwrap();
    let mixed_material = repo.get_material(&mixed.material.id).unwrap().unwrap();
    let mixed_before = graph_counts(&repo);
    let mut swapped = mixed_revision.clone();
    swapped.assets.swap(0, 1);
    assert_ne!(swapped.assets, mixed_revision.assets);
    let err = MaterialRepository::create_material(repo.as_ref(), &mixed_material, &swapped)
        .expect_err("create with a non-canonical asset order");
    assert!(matches!(err, ApplicationError::Repository(_)));
    assert_eq!(graph_counts(&repo), mixed_before);
}

#[test]
fn materials_survive_reopening_a_file_database() {
    let dir = tempfile::tempdir().unwrap();
    let database_path = dir.path().join("listen-material.db");
    let material_id = {
        let repo = Arc::new(SqliteRepository::open(&database_path).unwrap());
        let services = services(&repo);
        register_media(&repo, "media-reopen", MediaKind::Audio);
        let created = services
            .materials()
            .create(CreateLearningMaterial {
                title: "Persisted".into(),
                assets: vec![media_input("media-reopen")],
                retain: None,
            })
            .unwrap();
        created.material.id
    };

    let reopened = Arc::new(SqliteRepository::open(&database_path).unwrap());
    let services = services(&reopened);
    let read = services
        .materials()
        .read(&material_id)
        .unwrap()
        .expect("material persisted across reopen");
    assert_eq!(read.material.id, material_id);
    assert_eq!(read.shape(), MaterialShape::Audio);
    let resolved = services
        .materials()
        .resolve_for_media(&MediaId::parse("media-reopen").unwrap())
        .unwrap()
        .expect("binding survives reopen");
    assert_eq!(resolved.material.id, material_id);
}

#[test]
fn material_for_media_resolves_bound_media_only() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);

    let free = MediaId::parse("media-free").unwrap();
    assert!(repo.material_for_media(&free).unwrap().is_none());

    register_media(&repo, "media-bound", MediaKind::Video);
    let created = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Bound".into(),
            assets: vec![media_input("media-bound")],
            retain: None,
        })
        .unwrap();

    let bound = repo
        .material_for_media(&MediaId::parse("media-bound").unwrap())
        .unwrap()
        .expect("binding resolves");
    assert_eq!(bound.id, created.material.id);
    assert_eq!(
        bound.current_revision_id,
        created.material.current_revision_id
    );

    let resolved = services
        .materials()
        .resolve_for_media(&MediaId::parse("media-bound").unwrap())
        .unwrap()
        .unwrap();
    assert_eq!(resolved.material.id, created.material.id);
    assert_eq!(resolved.current_revision.id, created.current_revision.id);
}

#[test]
fn create_and_append_synchronize_registered_media_membership() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    register_media(&repo, "media-sync-a", MediaKind::Audio);
    register_media(&repo, "media-sync-b", MediaKind::Audio);

    // Temporary material: the bound media stays temporary too.
    let temporary = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Draft".into(),
            assets: vec![media_input("media-sync-a")],
            retain: Some(false),
        })
        .unwrap();
    let material_id = temporary.material.id.clone();
    assert!(temporary.material.retained_at_ms.is_none());
    let row: (Option<u64>, u64) = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT retained_at_ms, updated_at_ms FROM media_items WHERE id='media-sync-a'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
    };
    assert_eq!(
        row,
        (None, temporary.material.updated_at_ms),
        "temporary membership mirrors on the media row with the create timestamp"
    );

    // Retaining the material retains every bound registered media.
    let retained = services.materials().retain(&material_id).unwrap();
    let retained_at = retained.material.retained_at_ms.expect("membership time");
    let row: (Option<u64>, u64) = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT retained_at_ms, updated_at_ms FROM media_items WHERE id='media-sync-a'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
    };
    assert_eq!(row, (Some(retained_at), retained_at));

    // One raw media -> one canonical material: every registered media already
    // owns its deterministic material, so appending media-sync-b (bound to its
    // own material) into material-a is a conflict, never a silent rebind.
    let err = services
        .materials()
        .append_revision(
            &material_id,
            AppendMaterialRevision {
                title: "Draft v2".into(),
                assets: vec![media_input("media-sync-a"), media_input("media-sync-b")],
            },
        )
        .expect_err("cross-material append");
    assert!(matches!(
        err,
        ApplicationError::Conflict("media rendition belongs to another material")
    ));

    // A media registered after its material became retained immediately
    // follows aggregate membership: registration converges on the existing
    // retained material (never a duplicate graph) inside the same transaction,
    // and the new media row mirrors the material's membership authority.
    let late_rendition = MediaRenditionAsset::new(
        MediaId::parse("media-late-register").unwrap(),
        MediaKind::Audio,
        "fp-late-register".to_owned(),
        MediaAvailability::Available,
    )
    .unwrap();
    let late_assets = vec![MaterialAsset::MediaRendition(late_rendition)];
    let late_material_id = initial_material_id(&late_assets).unwrap();
    let late_revision = MaterialRevision::new(
        late_material_id.clone(),
        "Retained late register",
        late_assets,
        2000,
    )
    .unwrap();
    let late_material = LearningMaterial::new(&late_revision, Some(2000), 2000, 2000).unwrap();
    MaterialRepository::create_material(repo.as_ref(), &late_material, &late_revision).unwrap();
    assert_eq!(
        count(&repo, "media_items"),
        2,
        "the graph may bind unregistered media"
    );
    let registered = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-late-register").unwrap(),
            path: "/tmp/late-register.mp4".into(),
            fingerprint: "fp-late-register".into(),
            title: "Late register".into(),
            kind: MediaKind::Audio,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 5000,
            updated_at_ms: 5000,
        },
    )
    .unwrap();
    let row: (Option<u64>, u64) = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT retained_at_ms, updated_at_ms FROM media_items WHERE id='media-late-register'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
    };
    assert_eq!(
        row.0,
        Some(2000),
        "a media registered under a retained material follows aggregate membership"
    );
    assert_eq!(
        row.1, 5000,
        "the fresh registration updated_at_ms is preserved, never rolled back to the material's"
    );
    assert!(
        row.1 >= 5000,
        "the preserved media updated_at_ms is never older than its created_at_ms"
    );
    assert_eq!(registered.id.as_str(), "media-late-register");
    assert_eq!(registered.updated_at_ms, 5000);
    assert_eq!(
        repo.material_for_media(&registered.id).unwrap().unwrap().id,
        late_material_id,
        "registration converges on the existing retained material"
    );
    assert_eq!(
        repo.material_for_media(&registered.id)
            .unwrap()
            .unwrap()
            .updated_at_ms,
        2000,
        "the retained material's own update time is untouched by the registration"
    );
    assert_eq!(
        count(&repo, "learning_materials"),
        3,
        "registering the media never creates a duplicate material"
    );

    // Creating a retained material synchronizes its media immediately.
    register_media(&repo, "media-sync-c", MediaKind::Video);
    let created = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Kept now".into(),
            assets: vec![media_input("media-sync-c")],
            retain: None,
        })
        .unwrap();
    let row: (Option<u64>, u64) = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT retained_at_ms, updated_at_ms FROM media_items WHERE id='media-sync-c'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
    };
    assert_eq!(
        row.0, created.material.retained_at_ms,
        "create synchronizes a bound registered media to the material membership"
    );
    assert_eq!(row.1, created.material.updated_at_ms);

    // Media bindings stay durable when `media_items` is absent: a direct
    // create with an unregistered media persists the graph without touching
    // any media row.
    let unregistered = MediaRenditionAsset::new(
        MediaId::parse("media-unregistered").unwrap(),
        MediaKind::Audio,
        "fp-unregistered".to_owned(),
        MediaAvailability::Available,
    )
    .unwrap();
    let assets = vec![MaterialAsset::MediaRendition(unregistered)];
    let material_id = initial_material_id(&assets).unwrap();
    let revision =
        MaterialRevision::new(material_id.clone(), "Unregistered media", assets, 1000).unwrap();
    let material = LearningMaterial::new(&revision, Some(1000), 1000, 1000).unwrap();
    let media_count_before = count(&repo, "media_items");
    MaterialRepository::create_material(repo.as_ref(), &material, &revision).unwrap();
    assert_eq!(count(&repo, "media_items"), media_count_before);
    let bound = repo
        .material_for_media(&MediaId::parse("media-unregistered").unwrap())
        .unwrap()
        .expect("binding is durable without a media row");
    assert_eq!(bound.id, material_id);
}

#[test]
fn membership_mutation_changes_only_two_columns_and_keeps_graph_and_state() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let item = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("membership-proof").unwrap(),
            path: "/tmp/membership-proof.mp4".into(),
            fingerprint: "membership-proof-fp".into(),
            title: "Membership proof".into(),
            kind: MediaKind::Video,
            duration: Some(TimeMs::new(9_000)),
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 7,
            updated_at_ms: 8,
        },
    )
    .unwrap();
    let created = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Proof".into(),
            assets: vec![media_input("membership-proof")],
            retain: None,
        })
        .unwrap();
    let material_id = created.material.id.clone();
    let revision_id = created.material.current_revision_id.clone();

    // Learner-owned state attached before the membership mutation.
    PlaybackProgressRepository::save(repo.as_ref(), &item.id, TimeMs::new(4_200)).unwrap();
    let track = SubtitleTrack {
        id: SubtitleTrackId::from_fingerprint("track", "membership-proof"),
        media_id: item.id.clone(),
        fingerprint: "membership-proof-track".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("sentence", "membership-proof"),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(5_000),
            original_text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: vec![SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "Hello".into(),
                normalized: Some("hello".into()),
                start_char: 0,
                end_char: 5,
            }],
        }],
    };
    repo.save_track(&track).unwrap();
    LearningEventRepository::append_learning_event(
        repo.as_ref(),
        &LearningEvent {
            id: LearningEventId::from_fingerprint("learning-event", "membership-proof"),
            occurred_at_ms: 42,
            kind: LearningEventKind::FamiliarMaterialMarked,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::Media,
                id: item.id.as_str().to_owned(),
            },
            payload: serde_json::json!({}),
            session_id: None,
        },
    )
    .unwrap();

    let graph_before = (
        count(&repo, "learning_materials"),
        count(&repo, "material_revisions"),
        count(&repo, "material_assets"),
        count(&repo, "material_media_bindings"),
    );
    let material_before = material_row(&repo, material_id.as_str());
    let media_before = media_row(&repo, item.id.as_str());

    // Membership timestamps must not precede the material's creation time.
    let membership_stamp = material_before["updated_at_ms"].as_u64().unwrap() + 1_000;

    let unretained = MaterialRepository::set_library_membership(
        repo.as_ref(),
        &material_id,
        None,
        membership_stamp,
    )
    .unwrap();
    assert!(unretained.retained_at_ms.is_none());
    assert_eq!(unretained.updated_at_ms, membership_stamp);

    // Only the two membership columns change on the material row...
    let mut expected_material = material_before.clone();
    expected_material["retained_at_ms"] = serde_json::Value::Null;
    expected_material["updated_at_ms"] = serde_json::json!(membership_stamp);
    assert_eq!(
        material_row(&repo, material_id.as_str()),
        expected_material,
        "material membership changes only retained_at_ms and updated_at_ms"
    );
    // ...and on every bound media row.
    let mut expected_media = media_before.clone();
    expected_media["retained_at_ms"] = serde_json::Value::Null;
    expected_media["updated_at_ms"] = serde_json::json!(membership_stamp);
    assert_eq!(
        media_row(&repo, item.id.as_str()),
        expected_media,
        "media membership changes only retained_at_ms and updated_at_ms"
    );

    // Graph rows survive: revisions, assets, bindings, and reads are intact.
    assert_eq!(
        (
            count(&repo, "learning_materials"),
            count(&repo, "material_revisions"),
            count(&repo, "material_assets"),
            count(&repo, "material_media_bindings"),
        ),
        graph_before
    );
    let stored = repo.get_material(&material_id).unwrap().unwrap();
    assert_eq!(stored.current_revision_id, revision_id);
    let revision = repo
        .get_revision(&revision_id)
        .unwrap()
        .expect("revision survives membership change");
    assert_eq!(revision.title, "Proof");
    let bound = repo
        .material_for_media(&item.id)
        .unwrap()
        .expect("binding survives membership change");
    assert_eq!(bound.id, material_id);

    // Learner-owned state survives: progress, subtitles, and history.
    assert_eq!(
        services.media_analysis().read_progress(&item.id).unwrap(),
        Some(TimeMs::new(4_200))
    );
    assert_eq!(repo.get_track(&track.id).unwrap(), Some(track.clone()));
    assert_eq!(
        repo.list_event_subject_ids(
            LearningEventKind::FamiliarMaterialMarked,
            LearningEventSubjectKind::Media,
        )
        .unwrap(),
        vec![item.id.as_str().to_owned()]
    );

    // Retain/unretain retries converge: repeating the same membership write
    // produces the same aggregate, and use-case retain on a retained material
    // is a no-op that never rewrites the update time.
    let retained_stamp = membership_stamp + 1_000;
    let retained = MaterialRepository::set_library_membership(
        repo.as_ref(),
        &material_id,
        Some(retained_stamp),
        retained_stamp,
    )
    .unwrap();
    assert_eq!(retained.retained_at_ms, Some(retained_stamp));
    let retained_again = MaterialRepository::set_library_membership(
        repo.as_ref(),
        &material_id,
        Some(retained_stamp),
        retained_stamp,
    )
    .unwrap();
    assert_eq!(retained_again, retained);
    let no_op = services.materials().retain(&material_id).unwrap();
    assert_eq!(no_op.material.updated_at_ms, retained_stamp);
    assert_eq!(no_op.material.retained_at_ms, Some(retained_stamp));
}

#[test]
fn binding_conflict_rolls_back_the_entire_append() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    register_media(&repo, "media-conflict-a", MediaKind::Audio);
    register_media(&repo, "media-conflict-b", MediaKind::Video);
    let a = services
        .materials()
        .create(CreateLearningMaterial {
            title: "A".into(),
            assets: vec![media_input("media-conflict-a")],
            retain: None,
        })
        .unwrap();
    let b = services
        .materials()
        .create(CreateLearningMaterial {
            title: "B".into(),
            assets: vec![media_input("media-conflict-b")],
            retain: None,
        })
        .unwrap();
    let a_id = a.material.id.clone();
    let a_before = material_row(&repo, a_id.as_str());
    let revisions_before = count(&repo, "material_revisions");
    let assets_before = count(&repo, "material_assets");

    // Direct repository append: media already bound to B joins A -> conflict.
    let rendition = MediaRenditionAsset::new(
        MediaId::parse("media-conflict-b").unwrap(),
        MediaKind::Video,
        "media-conflict-b-fp".to_owned(),
        MediaAvailability::Available,
    )
    .unwrap();
    let assets = vec![MaterialAsset::MediaRendition(rendition)];
    let revision = MaterialRevision::new(a_id.clone(), "A conflict", assets, 5000).unwrap();
    let err = MaterialRepository::append_revision(repo.as_ref(), &a_id, &revision, 9999)
        .expect_err("media bound to another material");
    assert!(matches!(
        err,
        ApplicationError::Conflict("media rendition belongs to another material")
    ));

    // The whole append rolled back: the pointer, timestamps, revisions,
    // assets, and bindings are all unchanged.
    assert_eq!(material_row(&repo, a_id.as_str()), a_before);
    assert_eq!(count(&repo, "material_revisions"), revisions_before);
    assert_eq!(count(&repo, "material_assets"), assets_before);
    let binding: String = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT material_id FROM material_media_bindings
             WHERE media_id='media-conflict-b'",
            [],
            |row| row.get(0),
        )
        .unwrap()
    };
    assert_eq!(binding, b.material.id.as_str());

    // The use case rejects the same cross-material append before writing.
    let err = services
        .materials()
        .append_revision(
            &a_id,
            AppendMaterialRevision {
                title: "A conflict via use case".into(),
                assets: vec![media_input("media-conflict-b")],
            },
        )
        .expect_err("use case conflict");
    assert!(matches!(
        err,
        ApplicationError::Conflict("media rendition belongs to another material")
    ));
    assert_eq!(material_row(&repo, a_id.as_str()), a_before);
}

#[test]
fn missing_rows_return_none_or_not_found() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let missing = LearningMaterialId::parse("material-absent").unwrap();

    assert!(repo.get_material(&missing).unwrap().is_none());
    assert!(services.materials().read(&missing).unwrap().is_none());

    let asset = DocumentTextAsset::new("never stored", None).unwrap();
    let assets = vec![MaterialAsset::DocumentText(asset)];
    let revision = MaterialRevision::new(missing.clone(), "Never", assets, 1).unwrap();
    let err = MaterialRepository::append_revision(repo.as_ref(), &missing, &revision, 1)
        .expect_err("append to a missing material");
    assert!(matches!(err, ApplicationError::NotFound("material")));

    let err = MaterialRepository::set_library_membership(repo.as_ref(), &missing, None, 1)
        .expect_err("membership on a missing material");
    assert!(matches!(err, ApplicationError::NotFound("material")));

    assert!(
        repo.material_for_media(&MediaId::parse("media-unbound").unwrap())
            .unwrap()
            .is_none()
    );
}

#[test]
fn corrupt_rows_surface_as_repository_errors() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);

    // Tampered asset JSON: valid JSON with different content than the stored
    // asset_id describes.
    {
        let created = services
            .materials()
            .create(CreateLearningMaterial {
                title: "Asset proof".into(),
                assets: vec![text_input("original content")],
                retain: None,
            })
            .unwrap();
        let revision_id = created.material.current_revision_id.clone();
        let tampered = serde_json::to_string(&MaterialAsset::DocumentText(
            DocumentTextAsset::new("tampered content", None).unwrap(),
        ))
        .unwrap();
        {
            let conn = repo.connection.lock();
            conn.execute(
                "UPDATE material_assets SET asset_json=?1 WHERE revision_id=?2",
                params![tampered, revision_id.as_str()],
            )
            .unwrap();
        }
        let err = repo
            .get_revision(&revision_id)
            .expect_err("tampered asset JSON is corruption");
        assert!(matches!(err, ApplicationError::Repository(_)));
    }

    // asset_kind mismatch: JSON is a media rendition but the kind says text.
    {
        register_media(&repo, "media-corrupt-kind", MediaKind::Audio);
        let created = services
            .materials()
            .create(CreateLearningMaterial {
                title: "Kind proof".into(),
                assets: vec![media_input("media-corrupt-kind")],
                retain: None,
            })
            .unwrap();
        let revision_id = created.material.current_revision_id.clone();
        {
            let conn = repo.connection.lock();
            conn.execute(
                "UPDATE material_assets SET asset_kind='document_text' WHERE revision_id=?1",
                [revision_id.as_str()],
            )
            .unwrap();
        }
        let err = repo
            .get_revision(&revision_id)
            .expect_err("asset_kind mismatch is corruption");
        assert!(matches!(err, ApplicationError::Repository(_)));
    }

    // Non-contiguous asset ordinals.
    {
        register_media(&repo, "media-corrupt-ordinal", MediaKind::Audio);
        let created = services
            .materials()
            .create(CreateLearningMaterial {
                title: "Ordinal proof".into(),
                assets: vec![text_input("notes"), media_input("media-corrupt-ordinal")],
                retain: None,
            })
            .unwrap();
        let revision_id = created.material.current_revision_id.clone();
        {
            let conn = repo.connection.lock();
            conn.execute(
                "UPDATE material_assets SET ordinal=5 WHERE revision_id=?1 AND ordinal=1",
                [revision_id.as_str()],
            )
            .unwrap();
        }
        let err = repo
            .get_revision(&revision_id)
            .expect_err("non-contiguous ordinals are corruption");
        assert!(matches!(err, ApplicationError::Repository(_)));
    }

    // Internally consistent but different content: the recomputed revision
    // identity no longer matches the stored revision id.
    {
        let created = services
            .materials()
            .create(CreateLearningMaterial {
                title: "Identity proof".into(),
                assets: vec![text_input("identity content")],
                retain: None,
            })
            .unwrap();
        let revision_id = created.material.current_revision_id.clone();
        let forged = DocumentTextAsset::new("forged content", None).unwrap();
        let forged_json =
            serde_json::to_string(&MaterialAsset::DocumentText(forged.clone())).unwrap();
        {
            let conn = repo.connection.lock();
            conn.execute(
                "UPDATE material_assets SET asset_id=?1, asset_json=?2 WHERE revision_id=?3",
                params![forged.id.as_str(), forged_json, revision_id.as_str()],
            )
            .unwrap();
        }
        let err = repo
            .get_revision(&revision_id)
            .expect_err("forged revision identity is corruption");
        assert!(matches!(err, ApplicationError::Repository(_)));
    }

    // Blank stored title violates the revision invariant.
    {
        let created = services
            .materials()
            .create(CreateLearningMaterial {
                title: "Title proof".into(),
                assets: vec![text_input("title content")],
                retain: None,
            })
            .unwrap();
        let revision_id = created.material.current_revision_id.clone();
        {
            let conn = repo.connection.lock();
            conn.execute(
                "UPDATE material_revisions SET title='   ' WHERE id=?1",
                [revision_id.as_str()],
            )
            .unwrap();
        }
        let err = repo
            .get_revision(&revision_id)
            .expect_err("blank stored title is corruption");
        assert!(matches!(err, ApplicationError::Repository(_)));
    }

    // A current pointer to a missing revision surfaces as a repository error
    // when the application assembles details.
    {
        let created = services
            .materials()
            .create(CreateLearningMaterial {
                title: "Pointer proof".into(),
                assets: vec![text_input("pointer content")],
                retain: None,
            })
            .unwrap();
        let material_id = created.material.id.clone();
        let revision_id = created.material.current_revision_id.clone();
        {
            let conn = repo.connection.lock();
            conn.execute_batch("PRAGMA foreign_keys=OFF;").unwrap();
            conn.execute(
                "DELETE FROM material_revisions WHERE id=?1",
                [revision_id.as_str()],
            )
            .unwrap();
            conn.execute_batch("PRAGMA foreign_keys=ON;").unwrap();
        }
        assert!(
            repo.get_material(&material_id).unwrap().is_some(),
            "the material row itself still reads"
        );
        assert!(
            repo.get_revision(&revision_id).unwrap().is_none(),
            "the deleted revision reads as missing"
        );
        let err = services
            .materials()
            .read(&material_id)
            .expect_err("dangling current pointer is a repository error");
        assert!(matches!(err, ApplicationError::Repository(_)));
    }
}

#[test]
fn forged_stored_typed_asset_fields_are_corruption() {
    // Forge only the stored `byte_size` of a document asset, keeping text,
    // digest, id, and kind consistent, so the revision identity still matches:
    // only the per-asset constructor validation can catch the corruption.
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    let created = services
        .materials()
        .create(CreateLearningMaterial {
            title: "Stored proof".into(),
            assets: vec![text_input("stored content")],
            retain: None,
        })
        .unwrap();
    let revision_id = created.material.current_revision_id.clone();

    {
        let conn = repo.connection.lock();
        let stored: String = conn
            .query_row(
                "SELECT asset_json FROM material_assets WHERE revision_id=?1",
                [revision_id.as_str()],
                |row| row.get(0),
            )
            .unwrap();
        let mut value: serde_json::Value = serde_json::from_str(&stored).unwrap();
        let byte_size = value["document_text"]["byte_size"].as_u64().unwrap();
        value["document_text"]["byte_size"] = serde_json::json!(byte_size + 1);
        conn.execute(
            "UPDATE material_assets SET asset_json=?1 WHERE revision_id=?2",
            params![value.to_string(), revision_id.as_str()],
        )
        .unwrap();
    }

    let err = repo
        .get_revision(&revision_id)
        .expect_err("forged stored byte_size is corruption");
    assert!(matches!(err, ApplicationError::Repository(_)));
}

#[test]
fn stored_asset_json_never_contains_a_path() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = services(&repo);
    register_media(&repo, "media-no-path", MediaKind::Audio);
    let created = services
        .materials()
        .create(CreateLearningMaterial {
            title: "No path".into(),
            assets: vec![text_input("notes"), media_input("media-no-path")],
            retain: None,
        })
        .unwrap();
    let revision_id = created.material.current_revision_id.clone();

    for asset_json in stored_asset_json(&repo, revision_id.as_str()) {
        assert!(
            !asset_json.contains("\"path\""),
            "stored asset JSON must never carry a path field: {asset_json}"
        );
        assert!(
            !asset_json.contains("/tmp"),
            "stored asset JSON must never carry a media path: {asset_json}"
        );
        let value: serde_json::Value = serde_json::from_str(&asset_json).unwrap();
        if let Some(rendition) = value.get("media_rendition") {
            let object = rendition.as_object().expect("rendition object");
            assert!(
                !object.contains_key("path"),
                "media rendition JSON must never carry a path key"
            );
        }
    }
}

#[test]
fn repository_reads_backfilled_legacy_materials() {
    // Legacy `media_items` rows backfilled by the v59 migration are read back
    // through the repository with typed values and the blank-title fallback.
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    {
        let conn = repo.connection.lock();
        conn.execute_batch(
            r#"
            INSERT INTO media_items
              (id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms,availability,retained_at_ms)
            VALUES
              ('legacy-a','/tmp/legacy-a.mp4','fp-a','Legacy A','"video"',NULL,100,200,'"available"',100),
              ('legacy-b','/tmp/legacy-b.mp4','fp-b','   ','"audio"',NULL,300,400,'"available"',NULL);
            "#,
        )
        .unwrap();
        let tx = conn.unchecked_transaction().unwrap();
        backfill_legacy_media_materials(&tx).unwrap();
        tx.commit().unwrap();
    }

    let retained = repo
        .material_for_media(&MediaId::parse("legacy-a").unwrap())
        .unwrap()
        .expect("legacy media bound to its backfilled material");
    assert_eq!(retained.retained_at_ms, Some(100));
    assert_eq!(retained.created_at_ms, 100);
    assert_eq!(retained.updated_at_ms, 200);
    let revision = repo
        .get_revision(&retained.current_revision_id)
        .unwrap()
        .expect("backfilled revision rehydrates");
    assert_eq!(revision.title, "Legacy A");
    assert!(matches!(
        revision.assets.first().unwrap(),
        MaterialAsset::MediaRendition(_)
    ));

    let temporary = repo
        .material_for_media(&MediaId::parse("legacy-b").unwrap())
        .unwrap()
        .expect("temporary legacy media still binds");
    assert!(temporary.retained_at_ms.is_none());
    let revision = repo
        .get_revision(&temporary.current_revision_id)
        .unwrap()
        .expect("blank-title backfill rehydrates");
    assert_eq!(revision.title, LEGACY_BLANK_TITLE_FALLBACK);

    // Only the retained legacy material appears in the retained list.
    let listed = MaterialRepository::list_retained_materials(repo.as_ref()).unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].id, retained.id);

    // The backfill guarantee holds through the repository read path too.
    for asset_json in stored_asset_json(&repo, revision.id.as_str()) {
        assert!(!asset_json.contains("\"path\""));
    }
}

#[test]
fn media_upsert_immediately_yields_one_deterministic_graph_without_paths() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());

    // Temporary registration: the graph exists from the very first write and
    // resolves deterministically through the public media->material query.
    let temporary = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-graph-temp").unwrap(),
            path: "/tmp/media-graph-temp.mp4".into(),
            fingerprint: "media-graph-temp-fp".into(),
            title: "Temporary media".into(),
            kind: MediaKind::Video,
            duration: Some(TimeMs::new(1_000)),
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 100,
            updated_at_ms: 200,
        },
    )
    .unwrap();
    let temporary_material = repo
        .material_for_media(&temporary.id)
        .unwrap()
        .expect("temporary media resolves through its material");
    assert!(temporary_material.retained_at_ms.is_none());
    assert_eq!(temporary_material.created_at_ms, 100);
    assert_eq!(temporary_material.updated_at_ms, 200);

    // Retained registration resolves too, carrying the membership evidence.
    let retained = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-graph-kept").unwrap(),
            path: "/tmp/media-graph-kept.mp4".into(),
            fingerprint: "media-graph-kept-fp".into(),
            title: "Kept media".into(),
            kind: MediaKind::Audio,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: Some(300),
            created_at_ms: 100,
            updated_at_ms: 400,
        },
    )
    .unwrap();
    let kept_material = repo
        .material_for_media(&retained.id)
        .unwrap()
        .expect("retained media resolves through its material");
    assert_eq!(kept_material.retained_at_ms, Some(300));

    // Exactly one deterministic graph per media: one material, one initial
    // revision, one asset, one binding.
    assert_eq!(count(&repo, "learning_materials"), 2);
    assert_eq!(count(&repo, "material_revisions"), 2);
    assert_eq!(count(&repo, "material_assets"), 2);
    assert_eq!(count(&repo, "material_media_bindings"), 2);

    // The rendition asset is a typed snapshot: media id, kind, fingerprint,
    // and availability only. The path must never be serialized or stored.
    for material in [&temporary_material, &kept_material] {
        let revision = repo
            .get_revision(&material.current_revision_id)
            .unwrap()
            .unwrap();
        assert_eq!(revision.assets.len(), 1);
        let MaterialAsset::MediaRendition(rendition) = &revision.assets[0] else {
            panic!("media material carries exactly one rendition asset");
        };
        assert_eq!(rendition.media_id, material_media_id(&revision));
        for asset_json in stored_asset_json(&repo, material.current_revision_id.as_str()) {
            assert!(
                !asset_json.contains("\"path\""),
                "stored asset JSON must never carry a path: {asset_json}"
            );
            let value: serde_json::Value = serde_json::from_str(&asset_json).unwrap();
            let object = value["media_rendition"]
                .as_object()
                .expect("rendition object");
            for key in ["id", "media_id", "kind", "fingerprint", "availability"] {
                assert!(object.contains_key(key), "missing key: {key}");
            }
        }
    }

    // The material identity matches the domain derivation from the media id.
    let rendition = MediaRenditionAsset::new(
        temporary.id.clone(),
        MediaKind::Video,
        "media-graph-temp-fp".to_owned(),
        MediaAvailability::Available,
    )
    .unwrap();
    assert_eq!(
        temporary_material.id,
        initial_material_id(&[MaterialAsset::MediaRendition(rendition)]).unwrap()
    );
}

/// The media id snapshotted by a media-backed revision's rendition asset.
fn material_media_id(revision: &MaterialRevision) -> MediaId {
    match revision.assets.first().expect("revision carries assets") {
        MaterialAsset::MediaRendition(rendition) => rendition.media_id.clone(),
        MaterialAsset::DocumentText(_) => panic!("expected a media rendition"),
    }
}

#[test]
fn repeated_registration_and_rebind_preserve_graph_identity_and_learner_state() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let item = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-rebind-graph").unwrap(),
            path: "/tmp/rebind-v1.mp4".into(),
            fingerprint: "rebind-graph-fp".into(),
            title: "Original title".into(),
            kind: MediaKind::Video,
            duration: Some(TimeMs::new(1_000)),
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 50,
            updated_at_ms: 60,
        },
    )
    .unwrap();

    // Learner-owned state attached before any re-registration.
    PlaybackProgressRepository::save(repo.as_ref(), &item.id, TimeMs::new(4_200)).unwrap();
    LearningEventRepository::append_learning_event(
        repo.as_ref(),
        &LearningEvent {
            id: LearningEventId::from_fingerprint("learning-event", "rebind-graph"),
            occurred_at_ms: 42,
            kind: LearningEventKind::FamiliarMaterialMarked,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::Media,
                id: item.id.as_str().to_owned(),
            },
            payload: serde_json::json!({}),
            session_id: None,
        },
    )
    .unwrap();
    let track = SubtitleTrack {
        id: SubtitleTrackId::from_fingerprint("track", "rebind-graph"),
        media_id: item.id.clone(),
        fingerprint: "rebind-graph-track".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("sentence", "rebind-graph"),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(5_000),
            original_text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: vec![SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "Hello".into(),
                normalized: Some("hello".into()),
                start_char: 0,
                end_char: 5,
            }],
        }],
    };
    repo.save_track(&track).unwrap();

    let first_material = repo.material_for_media(&item.id).unwrap().unwrap();
    let first_revision = repo
        .get_revision(&first_material.current_revision_id)
        .unwrap()
        .unwrap();
    let first_membership_row = media_row(&repo, item.id.as_str());

    // Managed-path rebind: the same fingerprint at a new path, title, kind,
    // and duration. The legacy register API updates those binding facts only.
    let rebound = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-rebind-graph").unwrap(),
            path: "/managed-assets/rebind-v2.mp3".into(),
            fingerprint: "rebind-graph-fp".into(),
            title: "Rebound title".into(),
            kind: MediaKind::Audio,
            duration: Some(TimeMs::new(2_000)),
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 50,
            updated_at_ms: 70,
        },
    )
    .unwrap();

    // Graph identity, current revision pointer, creation time, and revision
    // content are preserved: no revision is appended for binding facts.
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    assert_eq!(material.id, first_material.id);
    assert_eq!(
        material.current_revision_id, first_material.current_revision_id,
        "a rebind never advances the current revision pointer"
    );
    assert_eq!(material.created_at_ms, 50);
    assert_eq!(
        material.updated_at_ms, 60,
        "a rebind never advances the material update time"
    );
    let revision = repo
        .get_revision(&material.current_revision_id)
        .unwrap()
        .unwrap();
    assert_eq!(revision, first_revision);
    assert_eq!(count(&repo, "learning_materials"), 1);
    assert_eq!(count(&repo, "material_revisions"), 1);
    assert_eq!(count(&repo, "material_assets"), 1);
    assert_eq!(count(&repo, "material_media_bindings"), 1);

    // The media row carries the rebound binding facts while the durable
    // revision keeps its original typed snapshot.
    assert_eq!(rebound.path, "/managed-assets/rebind-v2.mp3");
    assert_eq!(rebound.title, "Rebound title");
    assert_eq!(rebound.kind, MediaKind::Audio);
    let MaterialAsset::MediaRendition(rendition) = &revision.assets[0] else {
        panic!("expected a media rendition asset");
    };
    assert_eq!(
        rendition.kind,
        MediaKind::Video,
        "the durable revision keeps its original snapshot"
    );
    assert_eq!(media_row(&repo, item.id.as_str()), {
        let mut expected = first_membership_row.clone();
        expected["path"] = serde_json::json!("/managed-assets/rebind-v2.mp3");
        expected["title"] = serde_json::json!("Rebound title");
        expected["kind"] = serde_json::json!("\"audio\"");
        expected["duration_ms"] = serde_json::json!(2000);
        expected["updated_at_ms"] = serde_json::json!(70);
        expected
    });

    // Learner-owned state survives: progress, subtitles, history, and the
    // graph rows.
    assert_eq!(
        PlaybackProgressRepository::load(repo.as_ref(), &item.id).unwrap(),
        Some(TimeMs::new(4_200))
    );
    assert_eq!(repo.get_track(&track.id).unwrap(), Some(track));
    assert_eq!(
        repo.list_event_subject_ids(
            LearningEventKind::FamiliarMaterialMarked,
            LearningEventSubjectKind::Media,
        )
        .unwrap(),
        vec![item.id.as_str().to_owned()]
    );
}

#[test]
fn fingerprint_conflict_keeps_the_stored_identity_and_graph() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let stored = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("stored-id").unwrap(),
            path: "/tmp/stored.mp4".into(),
            fingerprint: "shared-fp".into(),
            title: "Stored".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: Some(1),
            created_at_ms: 1,
            updated_at_ms: 1,
        },
    )
    .unwrap();

    // Re-registration presents the same fingerprint with a different input id
    // and explicit temporary membership. The stored id wins the conflict and
    // existing membership wins via COALESCE, so the graph must follow the
    // ACTUAL persisted row — never the input.
    let re_registered = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("input-id").unwrap(),
            path: "/tmp/input.mp4".into(),
            fingerprint: "shared-fp".into(),
            title: "Input".into(),
            kind: MediaKind::Audio,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 2,
        },
    )
    .unwrap();
    assert_eq!(
        re_registered.id.as_str(),
        "stored-id",
        "the stored id wins the fingerprint conflict"
    );
    assert_eq!(
        re_registered.retained_at_ms,
        Some(1),
        "existing membership wins via COALESCE"
    );
    assert_eq!(re_registered.kind, MediaKind::Audio);
    assert_eq!(re_registered.title, "Input");

    // The graph keys on the actual stored media id, not the input id, and the
    // deterministic aggregate is untouched by the rebinding facts.
    let material = repo.material_for_media(&stored.id).unwrap().unwrap();
    assert_eq!(material.retained_at_ms, Some(1));
    assert_eq!(material.created_at_ms, 1);
    assert!(
        repo.material_for_media(&MediaId::parse("input-id").unwrap())
            .unwrap()
            .is_none()
    );
    assert_eq!(count(&repo, "learning_materials"), 1);
    assert_eq!(count(&repo, "material_revisions"), 1);
    assert_eq!(count(&repo, "material_assets"), 1);
    assert_eq!(count(&repo, "material_media_bindings"), 1);
}

#[test]
fn blank_title_media_uses_the_legacy_fallback_in_its_graph() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let item = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-blank-title").unwrap(),
            path: "/tmp/blank-title.mp4".into(),
            fingerprint: "blank-title-fp".into(),
            title: "   ".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        },
    )
    .unwrap();
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    let revision = repo
        .get_revision(&material.current_revision_id)
        .unwrap()
        .unwrap();
    assert_eq!(revision.title, LEGACY_BLANK_TITLE_FALLBACK);
}

#[test]
fn media_bound_to_another_material_conflicts_and_rolls_back_the_media_write() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    // A text material to serve as the corruption target.
    let asset = DocumentTextAsset::new("other material", None).unwrap();
    let assets = vec![MaterialAsset::DocumentText(asset)];
    let other_id = initial_material_id(&assets).unwrap();
    let revision = MaterialRevision::new(other_id.clone(), "Other", assets, 1).unwrap();
    let material = LearningMaterial::new(&revision, None, 1, 1).unwrap();
    MaterialRepository::create_material(repo.as_ref(), &material, &revision).unwrap();

    // Corruption: the media is bound to a material that is not its
    // deterministic one (unreachable through the public APIs, which always
    // bind a media to its own material).
    {
        let conn = repo.connection.lock();
        conn.execute(
            "INSERT INTO material_media_bindings (media_id, material_id)
             VALUES ('media-corrupt-bound', ?1)",
            [other_id.as_str()],
        )
        .unwrap();
    }
    let graph_before = graph_counts(&repo);

    let err = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-corrupt-bound").unwrap(),
            path: "/tmp/corrupt.mp4".into(),
            fingerprint: "corrupt-bound-fp".into(),
            title: "Corrupt bound".into(),
            kind: MediaKind::Audio,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        },
    )
    .expect_err("media bound to another material must not be moved");
    assert!(matches!(
        err,
        ApplicationError::Conflict("media rendition belongs to another material")
    ));

    // All-or-nothing: the media row itself rolled back and no graph row moved.
    assert_eq!(
        count(&repo, "media_items"),
        0,
        "the media write must roll back together with the conflict"
    );
    assert_eq!(graph_counts(&repo), graph_before);
    let binding: String = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT material_id FROM material_media_bindings
             WHERE media_id='media-corrupt-bound'",
            [],
            |row| row.get(0),
        )
        .unwrap()
    };
    assert_eq!(binding, other_id.as_str(), "the binding is never moved");
}

#[test]
fn invalid_media_that_cannot_form_a_graph_rolls_back_atomically() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());

    // A blank fingerprint fails the rendition asset constructor: the upsert
    // must fail with no media row and no graph row.
    let blank = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-blank-fp").unwrap(),
            path: "/tmp/blank.mp4".into(),
            fingerprint: "   ".into(),
            title: "Blank fingerprint".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        },
    );
    assert!(matches!(blank, Err(ApplicationError::Repository(_))));
    assert_eq!(
        count(&repo, "media_items"),
        0,
        "the media row must not survive a graph construction failure"
    );
    assert_eq!(graph_counts(&repo), (0, 0, 0, 0));

    // Inverted timestamps (updated before created) fail the material
    // constructor: nothing is persisted either.
    let inverted = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-inverted-time").unwrap(),
            path: "/tmp/inverted.mp4".into(),
            fingerprint: "inverted-time-fp".into(),
            title: "Inverted".into(),
            kind: MediaKind::Audio,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 10,
            updated_at_ms: 5,
        },
    );
    assert!(matches!(inverted, Err(ApplicationError::Repository(_))));
    assert_eq!(count(&repo, "media_items"), 0);
    assert_eq!(graph_counts(&repo), (0, 0, 0, 0));

    // Retention evidence after the update time fails the material constructor
    // too: the media row written by the upsert rolls back with the graph.
    let retained_after_update = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-retained-after-update").unwrap(),
            path: "/tmp/retained-after.mp4".into(),
            fingerprint: "retained-after-update-fp".into(),
            title: "Retained after".into(),
            kind: MediaKind::Audio,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: Some(300),
            created_at_ms: 1,
            updated_at_ms: 200,
        },
    );
    assert!(matches!(
        retained_after_update,
        Err(ApplicationError::Repository(_))
    ));
    assert_eq!(count(&repo, "media_items"), 0);
    assert_eq!(graph_counts(&repo), (0, 0, 0, 0));
}

#[test]
fn invalid_membership_timestamp_pair_rolls_back_atomically() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let item = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-invalid-membership").unwrap(),
            path: "/tmp/invalid-membership.mp4".into(),
            fingerprint: "invalid-membership-fp".into(),
            title: "Invalid membership".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 7,
            updated_at_ms: 8,
        },
    )
    .unwrap();
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    let media_before = media_row(&repo, item.id.as_str());
    let material_before = material_row(&repo, material.id.as_str());

    // A retained stamp after its own update time cannot be represented by the
    // material invariant (retention evidence never postdates the latest
    // update), so the operation must fail transactionally instead of silently
    // rewriting the caller's timestamps.
    let err = MediaRepository::set_library_membership(repo.as_ref(), &item.id, Some(123_456), 9)
        .expect_err("retained_at_ms after updated_at_ms must fail");
    assert!(matches!(err, ApplicationError::Repository(_)));

    // Both the media and the material rows rolled back byte-for-byte,
    // membership and update columns included.
    assert_eq!(
        media_row(&repo, item.id.as_str()),
        media_before,
        "the media row must be byte-for-byte unchanged after the failed membership"
    );
    assert_eq!(
        material_row(&repo, material.id.as_str()),
        material_before,
        "the material row must be byte-for-byte unchanged after the failed membership"
    );
    assert_eq!(
        count(&repo, "learning_materials"),
        1,
        "the graph is left intact"
    );
}

#[test]
fn retained_rebind_preserves_the_fresh_media_updated_at_ms() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let original = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-retained-rebind").unwrap(),
            path: "/tmp/rebind-old.mp4".into(),
            fingerprint: "retained-rebind-fp".into(),
            title: "Original".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: Some(1),
            created_at_ms: 1,
            updated_at_ms: 1,
        },
    )
    .unwrap();
    let material_before = repo.material_for_media(&original.id).unwrap().unwrap();
    assert_eq!(material_before.retained_at_ms, Some(1));

    // Re-registration with an explicit temporary intent cannot clear the
    // retained membership, and the fresh registration update time must never
    // be rolled back to the older material time.
    let rebound = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-retained-rebind").unwrap(),
            path: "/managed-assets/rebind-new.mp3".into(),
            fingerprint: "retained-rebind-fp".into(),
            title: "Rebound".into(),
            kind: MediaKind::Audio,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 5000,
        },
    )
    .unwrap();
    assert_eq!(
        rebound.retained_at_ms,
        Some(1),
        "existing membership survives a temporary re-registration"
    );
    assert_eq!(
        rebound.updated_at_ms, 5000,
        "the fresh rebind update time is preserved"
    );
    assert_eq!(rebound.path, "/managed-assets/rebind-new.mp3");

    let material = repo.material_for_media(&original.id).unwrap().unwrap();
    assert_eq!(material.retained_at_ms, Some(1));
    assert_eq!(
        material.updated_at_ms, material_before.updated_at_ms,
        "the material update time is not advanced by the rebind"
    );
    assert_eq!(count(&repo, "learning_materials"), 1);
    assert_eq!(count(&repo, "material_revisions"), 1);
}

#[test]
fn direct_idempotent_membership_never_rolls_media_updated_backward() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let item = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-no-rollback").unwrap(),
            path: "/tmp/no-rollback.mp4".into(),
            fingerprint: "no-rollback-fp".into(),
            title: "No rollback".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: Some(1),
            created_at_ms: 1,
            updated_at_ms: 2,
        },
    )
    .unwrap();
    let material_before = repo.material_for_media(&item.id).unwrap().unwrap();
    assert_eq!(material_before.retained_at_ms, Some(1));

    // A direct idempotent membership call on an already-retained item keeps the
    // material's original retained timestamp but must preserve the newer
    // requested update time instead of rolling it back to the material's.
    let result =
        MediaRepository::set_library_membership(repo.as_ref(), &item.id, Some(1), 5000).unwrap();
    assert_eq!(result.retained_at_ms, Some(1));
    assert_eq!(
        result.updated_at_ms, 5000,
        "the newer requested update time is preserved"
    );
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    assert_eq!(material.retained_at_ms, Some(1));
    assert_eq!(
        material.updated_at_ms, material_before.updated_at_ms,
        "the material is untouched by the idempotent membership call"
    );
}

#[test]
fn cross_material_current_revision_pointer_is_corruption_and_rolls_back() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());

    // A second material whose revision will be stolen by the corrupt pointer.
    let asset = DocumentTextAsset::new("another material", None).unwrap();
    let assets = vec![MaterialAsset::DocumentText(asset)];
    let other_id = initial_material_id(&assets).unwrap();
    let other_revision = MaterialRevision::new(other_id.clone(), "Other", assets, 1).unwrap();
    let other_material = LearningMaterial::new(&other_revision, None, 1, 1).unwrap();
    MaterialRepository::create_material(repo.as_ref(), &other_material, &other_revision).unwrap();

    // The media's deterministic material, created through registration.
    let item = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-bad-pointer").unwrap(),
            path: "/tmp/bad-pointer.mp4".into(),
            fingerprint: "bad-pointer-fp".into(),
            title: "Bad pointer".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        },
    )
    .unwrap();
    let media_before = media_row(&repo, item.id.as_str());
    let graph_before = graph_counts(&repo);

    // Corruption: point the media's material at the other material's revision.
    // The current pointer is a deferred FK and carries no ownership constraint,
    // so this shape is only reachable through direct storage tampering.
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    {
        let conn = repo.connection.lock();
        conn.execute(
            "UPDATE learning_materials SET current_revision_id=?1 WHERE id=?2",
            params![other_revision.id.as_str(), material.id.as_str()],
        )
        .unwrap();
    }

    // Re-registration converges on the stored material and detects the
    // cross-material pointer as corruption, rolling back the media write with
    // no half-written media or graph state.
    let err = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("media-bad-pointer").unwrap(),
            path: "/tmp/bad-pointer-new.mp4".into(),
            fingerprint: "bad-pointer-fp".into(),
            title: "Bad pointer new".into(),
            kind: MediaKind::Video,
            duration: None,
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 1,
            updated_at_ms: 5000,
        },
    )
    .expect_err("a cross-material current revision pointer is corruption");
    assert!(matches!(err, ApplicationError::Repository(_)));
    assert_eq!(
        media_row(&repo, item.id.as_str()),
        media_before,
        "the media write rolled back byte-for-byte"
    );
    assert_eq!(
        graph_counts(&repo),
        graph_before,
        "no graph rows were added or moved by the failed upsert"
    );
}
