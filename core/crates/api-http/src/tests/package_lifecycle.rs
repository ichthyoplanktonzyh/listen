//! Focused package lifecycle wire tests (contract `3.3.0`).
//!
//! These exercise the real axum router over a real in-memory SQLite
//! repository: the full `api-http -> application -> persistence-sqlite`
//! stack with the package lifecycle repository composed in. Carriers are
//! deterministic local Content Package v3 directories bound to the
//! material_id/current_revision_id actually created over HTTP; release and
//! resource identities come from the canonical computation
//! (`serialize_canonical` + the inspector), never from hard-coded fake ids.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::body::to_bytes;
use axum::http::header::{AUTHORIZATION, CONTENT_TYPE};
use axum::http::{Request, StatusCode};
use content_package::v2::serialize_canonical;
use content_package::v3::{RELEASE_SCHEMA_V3, STRUCTURED_READING_SCHEMA_V1};
use rusqlite::params;
use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use tower::ServiceExt;

use super::*;
use crate::routes::package_lifecycle::{
    AdoptLearningEditionRequest, InstallMaterialPackageRequest, LearningEditionDetails,
    LearningEditionRendition, LearningEditionResource,
};

const TOKEN: &str = "secret";

fn sha256_id(bytes: &[u8]) -> String {
    format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
}

fn canonical_bytes(value: &Value) -> Vec<u8> {
    serialize_canonical(value).unwrap()
}

fn blob_path(digest: &str) -> String {
    format!("blobs/sha256/{}", digest.strip_prefix("sha256:").unwrap())
}

// ---------------------------------------------------------------------
// Carrier fixture builders (canonical v2, directory carriers)
// ---------------------------------------------------------------------

struct TestDirectory(PathBuf);

static NEXT_TEST_DIRECTORY: AtomicU64 = AtomicU64::new(0);

impl TestDirectory {
    fn new() -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let sequence = NEXT_TEST_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "listen-api-package-lifecycle-{}-{sequence}-{nonce}",
            std::process::id()
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TestDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn base_descriptor(
    schema: &str,
    language: &str,
    digest: &str,
    size: u64,
    revision_id: &str,
    review_status: &str,
) -> Value {
    json!({
        "schema": schema,
        "kind": "structured_reading",
        "role": "base",
        "content_language": language,
        "support_languages": [],
        "subject": {"material_revision_id": revision_id, "rendition_ids": [], "anchor_resource_ids": []},
        "dependencies": [],
        "provenance": {"created_at_ms": 1, "tool": {"id": "listen-gen", "version": "0.4.0"}, "provider": null, "model": null, "config_sha256": null, "input_rendition_ids": [], "input_resource_ids": [], "extensions": {}},
        "quality": {"review_status": review_status, "warnings": [], "extensions": {}},
        "payload_blob": {"digest": digest, "size_bytes": size, "embedded": true},
        "extensions": {},
    })
}

fn resource_entry(descriptor: &Value, required: bool) -> Value {
    json!({
        "resource_id": sha256_id(&canonical_bytes(descriptor)),
        "required": required,
        "descriptor": descriptor.clone(),
    })
}

/// Sentence anchor ranges over the exact text so every offset is a true byte
/// boundary of the payload's `text`.
fn sentence_ranges(text: &str) -> Vec<(u64, u64)> {
    let mut ranges = Vec::new();
    let mut start = 0_u64;
    let bytes = text.as_bytes();
    let mut index = 0_usize;
    while index < bytes.len() {
        if matches!(bytes[index], b'.' | b'!' | b'?') {
            let mut end = index + 1;
            while bytes.get(end) == Some(&b' ') {
                end += 1;
            }
            if start < end as u64 {
                ranges.push((start, end as u64));
            }
            start = end as u64;
            index = end;
        } else {
            index += 1;
        }
    }
    if start < text.len() as u64 {
        ranges.push((start, text.len() as u64));
    }
    ranges
}

/// A structured reading payload over the exact `text` with one root block.
fn structured_payload(text: &str) -> Value {
    let ranges = sentence_ranges(text);
    let anchors: Vec<Value> = ranges
        .iter()
        .enumerate()
        .map(|(index, (start, end))| {
            json!({
                "anchor_id": format!("anchor-{}", index + 1),
                "kind": "sentence",
                "start_offset": start,
                "end_offset": end,
            })
        })
        .collect();
    json!({
        "language": "en",
        "text": text,
        "anchors": anchors,
        "blocks": [{
            "block_id": "block-root",
            "kind": "root",
            "order": 0,
            "span_anchor_ids": (0..ranges.len()).map(|index| format!("anchor-{}", index + 1)).collect::<Vec<_>>(),
            "parent_block_id": null,
        }],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    })
}

/// A text-only release bound to the given material and revision. The base
/// structured reading resource embeds the exact `text` payload; the source
/// Document Rendition carries the raw text bytes.
fn text_release_carrier(
    material_id: &str,
    revision_id: &str,
    edition_id: &str,
    text: &str,
    review_status: &str,
) -> (TestDirectory, Value, Value) {
    let structured = structured_payload(text);
    let bytes = canonical_bytes(&structured);
    let digest = sha256_id(&bytes);
    let descriptor = base_descriptor(
        STRUCTURED_READING_SCHEMA_V1,
        "en",
        &digest,
        bytes.len() as u64,
        revision_id,
        review_status,
    );
    let resource = resource_entry(&descriptor, true);
    let text_digest = sha256_id(text.as_bytes());
    let text_blob = json!({
        "digest": text_digest,
        "size_bytes": text.len() as u64,
        "embedded": true,
    });
    let document = json!({
        "rendition_id": sha256_id(&canonical_bytes(&json!({
            "media_type": "text/plain",
            "language": "en",
            "text_blob": text_blob,
        }))),
        "origin": "source",
        "media_type": "text/plain",
        "language": "en",
        "text_blob": text_blob,
        "source_asset_id": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "producer": null,
        "compatibility": null,
        "extensions": {},
    });
    let release = json!({
        "schema": RELEASE_SCHEMA_V3,
        "created_at_ms": 1u64,
        "edition": {
            "edition_id": edition_id,
            "title": "Wire Fixture Edition",
            "target_language": "en",
            "support_languages": ["zh-Hans"],
        },
        "material": {
            "material_id": material_id,
            "material_revision_id": revision_id,
            "title": "Wire Fixture Material",
        },
        "document_renditions": [document],
        "media_renditions": [],
        "resources": [resource],
        "extensions": {},
    });
    let mut files = BTreeMap::new();
    files.insert("release.json".into(), canonical_bytes(&release));
    files.insert(blob_path(&digest), bytes);
    files.insert(
        blob_path(&sha256_id(text.as_bytes())),
        text.as_bytes().to_vec(),
    );
    let directory = TestDirectory::new();
    for (name, bytes) in &files {
        let path = directory.path().join(name);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, bytes).unwrap();
    }
    let resource_id_value = resource["resource_id"].clone();
    (directory, release, resource_id_value)
}

// ---------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------

async fn create_text_material(app: &Router, text: &str) -> Value {
    let digest = hex::encode(Sha256::digest(text.as_bytes()));
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/materials")
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "title": "Wire Fixture",
                        "source_assets": [{
                            "media_type": "text/plain",
                            "byte_length": text.len(),
                            "sha256_digest": digest,
                            "binding": { "type": "managed" },
                        }],
                        "document_renditions": [{
                            "media_type": "text/plain",
                            "language": "en",
                            "digest": digest,
                            "byte_size": text.len(),
                            "source_asset_index": 0,
                        }],
                        "media_renditions": [],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap()
}

async fn install_package(
    app: &Router,
    material_id: &str,
    package_path: &Path,
) -> (StatusCode, Value) {
    let response = app
        .clone()
        .oneshot(
            Request::post(format!("/v1/materials/{material_id}/package-installations"))
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({"package_path": package_path.to_string_lossy()}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let value: Value = if body.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&body).unwrap()
    };
    (status, value)
}

async fn list_editions(app: &Router, material_id: &str) -> (StatusCode, Value) {
    let response = app
        .clone()
        .oneshot(
            Request::get(format!("/v1/materials/{material_id}/editions"))
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let value: Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    (status, value)
}

async fn adopt_edition(app: &Router, material_id: &str, release_id: &str) -> (StatusCode, Value) {
    let response = app
        .clone()
        .oneshot(
            Request::put(format!("/v1/materials/{material_id}/edition-adoption"))
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(json!({"release_id": release_id}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let value: Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    (status, value)
}

fn test_app() -> Router {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_material_repository(repo.clone())
    .with_package_lifecycle_repository(repo.clone());
    router(ApiState::new(services, repo, TOKEN))
}

/// Asserts no serialized package lifecycle value carries a forbidden key.
fn assert_no_private_facts(value: &Value) {
    match value {
        Value::Object(map) => {
            for forbidden in [
                "path",
                "file_path",
                "local_path",
                "manifest",
                "payload",
                "payload_blob",
                "blob_path",
                "digest",
                "byte_size",
                "schema",
                "dependencies",
                "provenance",
                "tool_id",
                "model_id",
            ] {
                assert!(
                    !map.contains_key(forbidden),
                    "package lifecycle wire shape must not expose {forbidden}: {value}"
                );
            }
            for nested in map.values() {
                assert_no_private_facts(nested);
            }
        }
        Value::Array(items) => {
            for item in items {
                assert_no_private_facts(item);
            }
        }
        _ => {}
    }
}

// ---------------------------------------------------------------------
// 1. Install a matching v2 package for an existing text Material
// ---------------------------------------------------------------------

#[tokio::test]
async fn installing_a_matching_v2_package_returns_exact_candidate_dto() {
    let app = test_app();
    let material = create_text_material(&app, "Hello world.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (directory, _, resource_id) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-wire-a",
        "Hello world.",
        "human_reviewed",
    );

    let (status, installed) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{installed}");
    assert_eq!(installed["material_id"], material_id);
    assert_eq!(installed["material_revision_id"], revision_id);
    assert_eq!(installed["edition_id"], "edition-wire-a");
    assert!(
        installed["release_id"]
            .as_str()
            .unwrap()
            .starts_with("sha256:")
    );
    assert_eq!(installed["title"], "Wire Fixture Edition");
    assert_eq!(installed["target_language"], "en");
    assert_eq!(installed["support_languages"], json!(["zh-hans"]));
    assert!(installed["installed_at_ms"].as_u64().unwrap() > 0);
    assert!(installed["adopted_at_ms"].is_null());
    assert_eq!(installed["adopted"], false);
    assert_eq!(installed["resources"].as_array().unwrap().len(), 1);
    let resource = &installed["resources"][0];
    assert_eq!(resource["resource_id"], resource_id);
    assert_eq!(resource["kind"], "structured_reading");
    assert_eq!(resource["role"], "base");
    assert_eq!(resource["required"], true);
    assert_eq!(resource["availability"], "available");
    assert_eq!(resource["review_status"], "human_reviewed");
    assert_eq!(resource["content_language"], "en");
    assert_eq!(resource["support_languages"], json!([]));
    assert_eq!(installed["renditions"].as_array().unwrap().len(), 1);
    assert_eq!(installed["renditions"][0]["kind"], "document");
    assert_eq!(installed["renditions"][0]["available"], true);
    assert_no_private_facts(&installed);
}

// ---------------------------------------------------------------------
// 2. Delete the source carrier; HTTP still works from durable facts
// ---------------------------------------------------------------------

#[tokio::test]
async fn deleting_the_source_carrier_keeps_listing_and_adoption_working() {
    let app = test_app();
    let material = create_text_material(&app, "Durable text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (directory, _, _) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-durable",
        "Durable text.",
        "machine_checked",
    );
    let path = directory.path().to_path_buf();
    let (status, installed) = install_package(&app, &material_id, &path).await;
    assert_eq!(status, StatusCode::OK, "{installed}");
    let release_id = installed["release_id"].as_str().unwrap().to_owned();
    let carrier_exists = path.join("release.json").exists();
    assert!(carrier_exists);
    drop(directory);
    assert!(!carrier_exists || !path.join("release.json").exists());

    let (status, editions) = list_editions(&app, &material_id).await;
    assert_eq!(status, StatusCode::OK, "{editions}");
    assert_eq!(editions[0]["release_id"], release_id);

    let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::OK, "{adopted}");
    assert_eq!(adopted["release_id"], release_id);
    assert_eq!(adopted["adopted"], true);
    assert!(adopted["adopted_at_ms"].as_u64().unwrap() > 0);
}

// ---------------------------------------------------------------------
// 3. Equal install retry is idempotent and stays candidate-only
// ---------------------------------------------------------------------

#[tokio::test]
async fn equal_install_retry_preserves_installation_and_never_adopts() {
    let app = test_app();
    let material = create_text_material(&app, "Retry text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (directory, _, _) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-retry",
        "Retry text.",
        "unreviewed",
    );

    let (status, first) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{first}");
    let release_id = first["release_id"].as_str().unwrap().to_owned();
    let installed_at_ms = first["installed_at_ms"].as_u64().unwrap();

    let (status, second) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{second}");
    assert_eq!(second["release_id"], release_id);
    assert_eq!(
        second["installed_at_ms"].as_u64(),
        Some(installed_at_ms),
        "an equal retry must preserve the original installation time"
    );
    assert_eq!(second["adopted"], false, "installation never adopts");
    assert!(second["adopted_at_ms"].is_null());

    let (_, editions) = list_editions(&app, &material_id).await;
    assert_eq!(
        editions
            .as_array()
            .unwrap()
            .iter()
            .filter(|edition| edition["release_id"] == release_id)
            .count(),
        1,
        "an equal retry must not create a second installation"
    );
    assert_eq!(editions[0]["adopted"], false);
}

// ---------------------------------------------------------------------
// 4. Two Editions for one Material: listing and adoption switch semantics
// ---------------------------------------------------------------------

#[tokio::test]
async fn two_editions_list_independently_and_adoption_switches() {
    let app = test_app();
    let material = create_text_material(&app, "Shared text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (directory_a, _, _) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-a",
        "Shared text.",
        "unreviewed",
    );
    let (directory_b, _, _) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-b",
        "Shared text.",
        "unreviewed",
    );

    let (status, a) = install_package(&app, &material_id, directory_a.path()).await;
    assert_eq!(status, StatusCode::OK, "{a}");
    let release_a = a["release_id"].as_str().unwrap().to_owned();
    let (status, b) = install_package(&app, &material_id, directory_b.path()).await;
    assert_eq!(status, StatusCode::OK, "{b}");
    let release_b = b["release_id"].as_str().unwrap().to_owned();
    assert_ne!(release_a, release_b);

    let (status, editions) = list_editions(&app, &material_id).await;
    assert_eq!(status, StatusCode::OK, "{editions}");
    let releases: Vec<&str> = editions
        .as_array()
        .unwrap()
        .iter()
        .map(|edition| edition["release_id"].as_str().unwrap())
        .collect();
    let mut expected = vec![release_a.as_str(), release_b.as_str()];
    expected.sort_unstable();
    assert_eq!(
        releases, expected,
        "listings follow the deterministic release id order"
    );
    assert!(
        editions
            .as_array()
            .unwrap()
            .iter()
            .all(|edition| edition["adopted"] == false)
    );

    let (status, adopted_a) = adopt_edition(&app, &material_id, &release_a).await;
    assert_eq!(status, StatusCode::OK, "{adopted_a}");
    assert_eq!(adopted_a["adopted"], true);
    assert!(adopted_a["adopted_at_ms"].as_u64().unwrap() > 0);
    let (_, editions) = list_editions(&app, &material_id).await;
    let by_release = |release: &str| {
        editions
            .as_array()
            .unwrap()
            .iter()
            .find(|edition| edition["release_id"] == release)
            .expect("release listed")
    };
    assert_eq!(
        by_release(&release_a)["adopted"],
        true,
        "only edition A is adopted"
    );
    assert_eq!(by_release(&release_b)["adopted"], false);

    // Adopting B replaces the adoption: only B is adopted afterwards.
    let (status, adopted_b) = adopt_edition(&app, &material_id, &release_b).await;
    assert_eq!(status, StatusCode::OK, "{adopted_b}");
    assert_eq!(adopted_b["adopted"], true);
    assert!(adopted_b["adopted_at_ms"].as_u64().unwrap() > 0);
    let (_, editions) = list_editions(&app, &material_id).await;
    let by_release = |release: &str| {
        editions
            .as_array()
            .unwrap()
            .iter()
            .find(|edition| edition["release_id"] == release)
            .expect("release listed")
    };
    assert_eq!(by_release(&release_a)["adopted"], false);
    assert_eq!(
        by_release(&release_b)["adopted"],
        true,
        "only edition B is adopted"
    );
}

// ---------------------------------------------------------------------
// 5. Repeated adoption of the same release is idempotent
// ---------------------------------------------------------------------

#[tokio::test]
async fn repeated_adoption_preserves_the_original_adopted_at_ms() {
    let app = test_app();
    let material = create_text_material(&app, "Idempotent text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (directory, _, _) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-idem",
        "Idempotent text.",
        "unreviewed",
    );
    let (status, installed) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{installed}");
    let release_id = installed["release_id"].as_str().unwrap().to_owned();

    let (status, first) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::OK, "{first}");
    let adopted_at_ms = first["adopted_at_ms"].as_u64().unwrap();

    tokio::time::sleep(std::time::Duration::from_millis(2)).await;
    let (status, second) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::OK, "{second}");
    assert_eq!(second, first, "a repeat adoption response is identical");
    assert_eq!(
        second["adopted_at_ms"].as_u64(),
        Some(adopted_at_ms),
        "the original adoption timestamp must be preserved"
    );
}

// ---------------------------------------------------------------------
// 6. Restart/reopen: file SQLite survives a fresh router and repository
// ---------------------------------------------------------------------

#[tokio::test]
async fn file_database_keeps_editions_and_adoption_evidence_after_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("package-lifecycle.db");
    let carrier_path;
    let material_id;
    let release_id;
    let revision_id;
    let adopted_at_ms;
    {
        let repo = Arc::new(SqliteRepository::open(&db_path).unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        )
        .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
        .with_material_repository(repo.clone())
        .with_package_lifecycle_repository(repo.clone());
        let app = router(ApiState::new(services, repo, TOKEN));
        let material = create_text_material(&app, "Reopen text.").await;
        material_id = material["material"]["id"].as_str().unwrap().to_owned();
        revision_id = material["current_revision"]["id"]
            .as_str()
            .unwrap()
            .to_owned();
        let (directory, _, _) = text_release_carrier(
            &material_id,
            &revision_id,
            "edition-reopen",
            "Reopen text.",
            "unreviewed",
        );
        carrier_path = directory.path().to_path_buf();
        let (status, installed) = install_package(&app, &material_id, &carrier_path).await;
        assert_eq!(status, StatusCode::OK, "{installed}");
        release_id = installed["release_id"].as_str().unwrap().to_owned();
        let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
        assert_eq!(status, StatusCode::OK, "{adopted}");
        adopted_at_ms = adopted["adopted_at_ms"].as_u64().unwrap();
    }

    // A fresh repository and router over the same file: everything remains.
    let repo = Arc::new(SqliteRepository::open(&db_path).unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_material_repository(repo.clone())
    .with_package_lifecycle_repository(repo.clone());
    let app = router(ApiState::new(services, repo, TOKEN));
    let (status, editions) = list_editions(&app, &material_id).await;
    assert_eq!(status, StatusCode::OK, "{editions}");
    assert_eq!(editions.as_array().unwrap().len(), 1);
    assert_eq!(editions[0]["release_id"], release_id);
    assert_eq!(editions[0]["adopted"], true);
    assert_eq!(
        editions[0]["adopted_at_ms"].as_u64(),
        Some(adopted_at_ms),
        "adoption evidence must survive a restart"
    );
    assert_no_private_facts(&editions);
}

// ---------------------------------------------------------------------
// 6b. Tampered stored adoption row fails closed over real file SQLite
// ---------------------------------------------------------------------

#[tokio::test]
async fn tampered_stored_adoption_fails_closed_with_typed_500() {
    let logs = CapturedLogs::default();
    let subscriber = tracing_subscriber::fmt()
        .json()
        .without_time()
        .with_writer(logs.clone())
        .finish();
    let _guard = tracing::subscriber::set_default(subscriber);

    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("package-lifecycle.db");
    let material_id;
    let release_id;
    let adopted_at_ms;
    {
        let repo = Arc::new(SqliteRepository::open(&db_path).unwrap());
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        )
        .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
        .with_material_repository(repo.clone())
        .with_package_lifecycle_repository(repo.clone());
        let app = router(ApiState::new(services, repo, TOKEN));
        let material = create_text_material(&app, "Tamper text.").await;
        material_id = material["material"]["id"].as_str().unwrap().to_owned();
        let revision_id = material["current_revision"]["id"]
            .as_str()
            .unwrap()
            .to_owned();
        let (directory, _, _) = text_release_carrier(
            &material_id,
            &revision_id,
            "edition-tamper",
            "Tamper text.",
            "unreviewed",
        );
        let (status, installed) = install_package(&app, &material_id, directory.path()).await;
        assert_eq!(status, StatusCode::OK, "{installed}");
        release_id = installed["release_id"].as_str().unwrap().to_owned();
        let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
        assert_eq!(status, StatusCode::OK, "{adopted}");
        adopted_at_ms = adopted["adopted_at_ms"].as_u64().unwrap();
    }

    // Test-only rusqlite connection: replace the stored selection JSON with
    // another json_valid plan, keeping the release_id untouched.
    let connection = rusqlite::Connection::open(&db_path).unwrap();
    let tampered_json = json!(["resource-forged"]).to_string();
    let changed = connection
        .execute(
            "UPDATE package_adoptions SET selected_resource_ids_json=?1 WHERE material_id=?2",
            params![tampered_json, material_id],
        )
        .unwrap();
    assert_eq!(changed, 1, "one adoption row must be tampered");
    drop(connection);

    // A fresh repository and router over the same file.
    let repo = Arc::new(SqliteRepository::open(&db_path).unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_material_repository(repo.clone())
    .with_package_lifecycle_repository(repo.clone());
    let app = router(ApiState::new(services, repo, TOKEN));

    // Re-adopting the same release fails closed: the recomputed plan is valid
    // but the stored row no longer equals it, so the commit must fail
    // atomically as a typed 500 and never repair the row.
    let (status, body) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR, "{body}");
    assert_eq!(body["code"], "package_lifecycle_failed");
    assert_eq!(body["retryable"], true);
    let text = body.to_string();
    assert!(
        !text.contains(&release_id),
        "body must not leak release identities: {text}"
    );
    assert!(
        !text.contains("resource-forged"),
        "body must not leak the selection JSON: {text}"
    );
    assert!(
        !text.contains("selected_resource_ids"),
        "body must not leak the internal selection plan: {text}"
    );

    let diagnostics = String::from_utf8(logs.0.lock().unwrap().clone()).unwrap();
    assert!(
        !diagnostics.contains(&release_id),
        "logs must not leak release identities"
    );
    assert!(
        !diagnostics.contains("resource-forged"),
        "logs must not leak selection content"
    );
    assert!(
        !diagnostics.contains("selected_resource_ids"),
        "logs must not leak the internal selection plan"
    );

    // The tampered row and its original timestamp are untouched.
    let connection = rusqlite::Connection::open(&db_path).unwrap();
    let (stored_json, stored_at_ms): (String, u64) = connection
        .query_row(
            "SELECT selected_resource_ids_json, adopted_at_ms
             FROM package_adoptions WHERE material_id=?1",
            [material_id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(
        stored_json, tampered_json,
        "the tampered row is never overwritten"
    );
    assert_eq!(
        stored_at_ms, adopted_at_ms,
        "the original adopted_at_ms is preserved"
    );
}

// ---------------------------------------------------------------------
// 7. Unknown material and unknown release installation are typed 404
// ---------------------------------------------------------------------

#[tokio::test]
async fn unknown_material_and_unknown_release_are_typed_not_found() {
    let app = test_app();
    let unknown = "0".repeat(64);

    let (status, body) = install_package(&app, &unknown, Path::new("/nonexistent/pkg")).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");

    let (status, body) = list_editions(&app, &unknown).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");

    let (status, body) = adopt_edition(&app, &unknown, "sha256:release-missing").await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");

    // An existing material with a release that was never installed.
    let material = create_text_material(&app, "NotFound text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let (status, body) = adopt_edition(&app, &material_id, "sha256:release-missing").await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");
    assert_eq!(
        body["message"],
        "package release installation was not found"
    );
}

// ---------------------------------------------------------------------
// 8. Invalid/incompatible installations and stale adoption are typed and
//    redacted
// ---------------------------------------------------------------------

#[tokio::test]
async fn installation_failures_are_422_redacted_in_body_and_logs() {
    let logs = CapturedLogs::default();
    let subscriber = tracing_subscriber::fmt()
        .json()
        .without_time()
        .with_writer(logs.clone())
        .finish();
    let _guard = tracing::subscriber::set_default(subscriber);

    let app = test_app();
    let material = create_text_material(&app, "Install failure text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();

    // A carrier path that does not exist.
    let (status, body) = install_package(
        &app,
        &material_id,
        Path::new("/nonexistent/listen-fixture/package.listenpkg"),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "package_installation_invalid");
    assert_eq!(
        body["message"],
        "package release is invalid or incompatible"
    );
    assert_eq!(body["retryable"], false);
    let text = body.to_string();
    assert!(
        !text.contains("nonexistent"),
        "body must not leak the path: {text}"
    );
    assert!(!text.contains("listenpkg"));

    // A blank package path is rejected before any application call.
    let response = app
        .clone()
        .oneshot(
            Request::post(format!("/v1/materials/{material_id}/package-installations"))
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(json!({"package_path": "   "}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let body: Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(body["code"], "package_installation_invalid");

    // A package bound to a different material revision (stale) is invalid.
    let (other_directory, _, _) = text_release_carrier(
        &material_id,
        "rev-stale-other",
        "edition-stale",
        "Install failure text.",
        "unreviewed",
    );
    let (status, body) = install_package(&app, &material_id, other_directory.path()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "package_installation_invalid");
    let text = body.to_string();
    assert!(
        !text.contains("rev-stale-other"),
        "body must not leak revision ids: {text}"
    );

    // A package bound to a different material entirely is invalid.
    let other_material = create_text_material(&app, "Other material.").await;
    let other_material_id = other_material["material"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (wrong_directory, _, _) = text_release_carrier(
        &other_material_id,
        &revision_id,
        "edition-cross-material",
        "Install failure text.",
        "unreviewed",
    );
    let (status, body) = install_package(&app, &material_id, wrong_directory.path()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert_eq!(body["code"], "package_installation_invalid");

    // Logs carry no private path or payload.
    let diagnostics = String::from_utf8(logs.0.lock().unwrap().clone()).unwrap();
    assert!(
        !diagnostics.contains("nonexistent"),
        "logs must not leak the package path"
    );
    assert!(
        !diagnostics.contains("listenpkg") && !diagnostics.contains("blobs/sha256"),
        "logs must not leak carrier details"
    );
    assert!(
        !diagnostics.contains("Install failure text"),
        "logs must not leak payload text"
    );
}

#[tokio::test]
async fn stale_revision_adoption_is_409_and_never_exposes_plan_details() {
    let logs = CapturedLogs::default();
    let subscriber = tracing_subscriber::fmt()
        .json()
        .without_time()
        .with_writer(logs.clone())
        .finish();
    let _guard = tracing::subscriber::set_default(subscriber);

    let app = test_app();
    let material = create_text_material(&app, "Stale adoption text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (directory, _, _) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-stale-adopt",
        "Stale adoption text.",
        "unreviewed",
    );
    let (status, installed) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{installed}");
    let release_id = installed["release_id"].as_str().unwrap().to_owned();

    // Append a new revision so the installed release is now stale.
    let digest = hex::encode(Sha256::digest("New revision text.".as_bytes()));
    let response = app
        .clone()
        .oneshot(
            Request::post(format!("/v1/materials/{material_id}/revisions"))
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "title": "Stale adoption v2",
                        "source_assets": [{
                            "media_type": "text/plain",
                            "byte_length": "New revision text.".len(),
                            "sha256_digest": digest,
                            "binding": { "type": "managed" },
                        }],
                        "document_renditions": [{
                            "media_type": "text/plain",
                            "language": null,
                            "digest": digest,
                            "byte_size": "New revision text.".len(),
                            "source_asset_index": 0,
                        }],
                        "media_renditions": [],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let (status, body) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert_eq!(body["code"], "edition_adoption_conflict");
    assert_eq!(body["message"], "learning edition cannot be adopted");
    assert_eq!(body["retryable"], false);
    let text = body.to_string();
    assert!(
        !text.contains(release_id.as_str()) && !text.contains("resource"),
        "body must not expose the release or resource ids: {text}"
    );

    let diagnostics = String::from_utf8(logs.0.lock().unwrap().clone()).unwrap();
    assert!(
        !diagnostics.contains(release_id.as_str()),
        "logs must not leak release identities"
    );
    assert!(
        !diagnostics.contains("selected_resource_ids"),
        "logs must not leak the internal selection plan"
    );
}

// ---------------------------------------------------------------------
// 9. OpenAPI/router method+path parity for the three package routes
// ---------------------------------------------------------------------

#[test]
fn package_lifecycle_routes_match_openapi_and_client() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let router_source = concat!(
        include_str!("../lib.rs"),
        include_str!("../routes/router.rs")
    );
    let implemented = super::openapi::implemented_v1_operations(router_source);
    let documented = super::openapi::openapi_v1_operations(openapi);

    for (method, path) in [
        ("post", "/v1/materials/{material_id}/package-installations"),
        ("get", "/v1/materials/{material_id}/editions"),
        ("put", "/v1/materials/{material_id}/edition-adoption"),
    ] {
        assert!(
            implemented.contains(&(method.to_owned(), path.to_owned())),
            "router must implement {method} {path}"
        );
        assert!(
            documented.contains(&(method.to_owned(), path.to_owned())),
            "OpenAPI must document {method} {path}"
        );
    }

    // The typed error contract must be recorded in the canonical OpenAPI:
    // exact codes exist, and each operation declares its error responses.
    for code in [
        "not_found",
        "package_installation_invalid",
        "edition_adoption_conflict",
        "package_lifecycle_failed",
    ] {
        assert!(
            openapi.contains(&format!("code: {code}")),
            "OpenAPI must record the typed package lifecycle error code {code}"
        );
    }
    let install = super::openapi::operation_response_block(openapi, "installMaterialPackage");
    let editions = super::openapi::operation_response_block(openapi, "listLearningEditions");
    let adoption = super::openapi::operation_response_block(openapi, "adoptLearningEdition");
    for status in ["\"404\"", "\"422\"", "\"500\""] {
        assert!(
            install.contains(status),
            "installMaterialPackage must declare {status} responses"
        );
    }
    for status in ["\"404\"", "\"500\""] {
        assert!(
            editions.contains(status),
            "listLearningEditions must declare {status} responses"
        );
    }
    for status in ["\"404\"", "\"409\"", "\"500\""] {
        assert!(
            adoption.contains(status),
            "adoptLearningEdition must declare {status} responses"
        );
    }

    let client = include_str!("../../../../contracts/generated/local-api-v1.ts");
    assert!(
        client.contains("installMaterialPackage(")
            && client.contains("listLearningEditions(")
            && client.contains("adoptLearningEdition("),
        "generated client must expose the three package lifecycle operations"
    );
}

// ---------------------------------------------------------------------
// 10. DTO conversion pins exact field and enum strings
// ---------------------------------------------------------------------

#[test]
fn wire_dtos_convert_exact_fields_and_enum_strings() {
    let view = application::PackageEditionView {
        material_id: domain::LearningMaterialId::parse("m-a").unwrap(),
        material_revision_id: domain::MaterialRevisionId::parse("r-a").unwrap(),
        edition_id: domain::LearningEditionId::parse("e-a").unwrap(),
        release_id: domain::PackageReleaseId::parse("sha256:r").unwrap(),
        title: "T".into(),
        target_language: domain::LanguageCode::parse("en").unwrap(),
        support_languages: vec![domain::LanguageCode::parse("zh-Hans").unwrap()],
        installed_at_ms: 11,
        adopted_at_ms: None,
        adopted: false,
        resources: vec![application::PackageResourceView {
            resource_id: "res-1".into(),
            kind: "word_timeline".into(),
            role: domain::PackageResourceRole::Assistance,
            required: false,
            availability: domain::PackageResourceAvailability::Opaque,
            review_status: domain::PackageReviewStatus::Unreviewed,
            content_language: None,
            support_languages: vec![domain::LanguageCode::parse("zh-Hans").unwrap()],
        }],
        renditions: vec![application::PackageRenditionView {
            rendition_id: "rend-1".into(),
            kind: "audio".into(),
            available: false,
        }],
    };
    let details = LearningEditionDetails::from(view);
    assert_eq!(details.adopted_at_ms, None);
    let resource = LearningEditionResource::from(application::PackageResourceView {
        resource_id: "res-1".into(),
        kind: "word_timeline".into(),
        role: domain::PackageResourceRole::Assistance,
        required: false,
        availability: domain::PackageResourceAvailability::Opaque,
        review_status: domain::PackageReviewStatus::Unreviewed,
        content_language: None,
        support_languages: Vec::new(),
    });
    assert_eq!(resource.role, "assistance");
    assert_eq!(resource.availability, "opaque");
    assert_eq!(resource.review_status, "unreviewed");
    assert_eq!(resource.content_language, None);
    let base = LearningEditionResource::from(application::PackageResourceView {
        resource_id: "res-2".into(),
        kind: "document_text".into(),
        role: domain::PackageResourceRole::Base,
        required: true,
        availability: domain::PackageResourceAvailability::Available,
        review_status: domain::PackageReviewStatus::MachineChecked,
        content_language: Some(domain::LanguageCode::parse("en").unwrap()),
        support_languages: Vec::new(),
    });
    assert_eq!(base.role, "base");
    assert_eq!(base.availability, "available");
    assert_eq!(base.review_status, "machine_checked");
    assert_eq!(base.content_language.as_deref(), Some("en"));
    let human = LearningEditionResource::from(application::PackageResourceView {
        resource_id: "res-3".into(),
        kind: "document_text".into(),
        role: domain::PackageResourceRole::Base,
        required: true,
        availability: domain::PackageResourceAvailability::Missing,
        review_status: domain::PackageReviewStatus::HumanReviewed,
        content_language: None,
        support_languages: Vec::new(),
    });
    assert_eq!(human.availability, "missing");
    assert_eq!(human.review_status, "human_reviewed");
    let rendition = LearningEditionRendition::from(application::PackageRenditionView {
        rendition_id: "rend-2".into(),
        kind: "video".into(),
        available: true,
    });
    assert!(rendition.available);

    // Request DTOs deserialize from the documented wire shape.
    let request: InstallMaterialPackageRequest =
        serde_json::from_value(json!({"package_path": "/tmp/pkg"})).unwrap();
    assert_eq!(request.package_path, "/tmp/pkg");
    let adoption: AdoptLearningEditionRequest =
        serde_json::from_value(json!({"release_id": "sha256:r"})).unwrap();
    assert_eq!(adoption.release_id, "sha256:r");
}

// ---------------------------------------------------------------------
// Adopted composition surface (contract 4.0.0): the single Core-owned
// composition authority. The App never re-parses a `.listenpkg`; these
// typed reads are the only composition interface.
// ---------------------------------------------------------------------

/// A file-backed app so composition content can be proven to survive a real
/// close and reopen, mirroring the production wiring in `main.rs`.
fn file_app(database_path: &Path) -> Router {
    let repo = Arc::new(SqliteRepository::open(database_path).unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_material_repository(repo.clone())
    .with_package_lifecycle_repository(repo.clone());
    router(ApiState::new(services, repo, TOKEN))
}

async fn read_composition(app: &Router, material_id: &str) -> (StatusCode, Value) {
    let response = app
        .clone()
        .oneshot(
            Request::get(format!("/v1/materials/{material_id}/composition"))
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    (status, serde_json::from_slice(&body).unwrap())
}

async fn read_payload(app: &Router, material_id: &str, resource_id: &str) -> (StatusCode, Vec<u8>) {
    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/materials/{material_id}/composition/resources/{resource_id}/payload"
            ))
            .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let body = to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap()
        .to_vec();
    (status, body)
}

async fn read_blob(app: &Router, material_id: &str, rendition_id: &str) -> (StatusCode, Vec<u8>) {
    let response = app
        .clone()
        .oneshot(
            Request::get(format!(
                "/v1/materials/{material_id}/composition/renditions/{rendition_id}/blob"
            ))
            .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
            .body(Body::empty())
            .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let body = to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap()
        .to_vec();
    (status, body)
}

#[tokio::test]
async fn adopted_composition_resolves_and_unadopted_material_is_typed_404() {
    let app = test_app();
    let material = create_text_material(&app, "Composition text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();

    // No adoption yet: typed not-found.
    let (status, body) = read_composition(&app, &material_id).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");

    let (directory, release, resource_id) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-composition",
        "Composition text.",
        "machine_checked",
    );
    let resource_id = resource_id.as_str().unwrap().to_owned();
    let rendition_id = release["document_renditions"][0]["rendition_id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (status, installed) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{installed}");
    let release_id = installed["release_id"].as_str().unwrap().to_owned();
    let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::OK, "{adopted}");

    let (status, composition) = read_composition(&app, &material_id).await;
    assert_eq!(status, StatusCode::OK, "{composition}");
    assert_eq!(composition["release_id"], release_id);
    assert_eq!(composition["material_id"], material_id);
    assert_eq!(composition["material_revision_id"], revision_id);
    assert_eq!(composition["target_language"], "en");

    // Exactly the selected resource and rendition are listed, with exact
    // digest/size facts and a binding that never leaks a path.
    let resources = composition["resources"].as_array().unwrap();
    assert_eq!(resources.len(), 1);
    assert_eq!(resources[0]["resource_id"], resource_id);
    assert!(resources[0]["payload_digest"].as_str().unwrap().len() > 10);
    let renditions = composition["renditions"].as_array().unwrap();
    assert_eq!(renditions.len(), 1);
    assert_eq!(renditions[0]["rendition_id"], rendition_id);
    assert_eq!(renditions[0]["origin"], "source");
    assert_eq!(renditions[0]["binding"]["type"], "managed_source_asset");
    assert!(renditions[0]["binding"].get("source_asset_id").is_some());
    let serialized = composition.to_string();
    assert!(
        !serialized.contains("package_path") && !serialized.contains("local_path"),
        "composition must never expose a local path: {serialized}"
    );
}

#[tokio::test]
async fn composition_payload_and_blob_survive_carrier_deletion_and_database_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("composition.db");
    let material_id;
    let release_id;
    let revision_id;
    let resource_id: String;
    let rendition_id: String;
    {
        let app = file_app(&db_path);
        let material = create_text_material(&app, "Durable composition.").await;
        material_id = material["material"]["id"].as_str().unwrap().to_owned();
        revision_id = material["current_revision"]["id"]
            .as_str()
            .unwrap()
            .to_owned();
        let (directory, release, resource_id_value) = text_release_carrier(
            &material_id,
            &revision_id,
            "edition-durable-composition",
            "Durable composition.",
            "machine_checked",
        );
        resource_id = resource_id_value.as_str().unwrap().to_owned();
        rendition_id = release["document_renditions"][0]["rendition_id"]
            .as_str()
            .unwrap()
            .to_owned();
        let (status, installed) = install_package(&app, &material_id, directory.path()).await;
        assert_eq!(status, StatusCode::OK, "{installed}");
        release_id = installed["release_id"].as_str().unwrap().to_owned();
        let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
        assert_eq!(status, StatusCode::OK, "{adopted}");
        // Delete the source carrier while the app is still open.
        drop(directory);
        // The typed content is still readable through Core-owned storage.
        let (status, payload) = read_payload(&app, &material_id, resource_id.as_str()).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(
            payload,
            canonical_bytes(&structured_payload("Durable composition."))
        );
        let (status, blob) = read_blob(&app, &material_id, rendition_id.as_str()).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(blob, b"Durable composition.".to_vec());
    }

    // A real close and reopen: the App never re-parses the carrier; the
    // adopted content is read straight from the durable Core store.
    let reopened = file_app(&db_path);
    let (status, composition) = read_composition(&reopened, &material_id).await;
    assert_eq!(status, StatusCode::OK, "{composition}");
    assert_eq!(composition["release_id"], release_id);
    assert_eq!(composition["material_revision_id"], revision_id);
    let (status, payload) = read_payload(&reopened, &material_id, resource_id.as_str()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        payload,
        canonical_bytes(&structured_payload("Durable composition."))
    );
    let (status, blob) = read_blob(&reopened, &material_id, rendition_id.as_str()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(blob, b"Durable composition.".to_vec());
}

#[tokio::test]
async fn tampered_stored_composition_content_fails_closed_as_integrity_failure() {
    let dir = tempfile::tempdir().unwrap();
    let db_path = dir.path().join("composition-tamper.db");
    let material_id;
    let release_id;
    let revision_id;
    let resource_id: String;
    {
        let app = file_app(&db_path);
        let material = create_text_material(&app, "Tamper text.").await;
        material_id = material["material"]["id"].as_str().unwrap().to_owned();
        revision_id = material["current_revision"]["id"]
            .as_str()
            .unwrap()
            .to_owned();
        let (directory, _, resource_id_value) = text_release_carrier(
            &material_id,
            &revision_id,
            "edition-tamper",
            "Tamper text.",
            "machine_checked",
        );
        resource_id = resource_id_value.as_str().unwrap().to_owned();
        let (status, installed) = install_package(&app, &material_id, directory.path()).await;
        assert_eq!(status, StatusCode::OK, "{installed}");
        release_id = installed["release_id"].as_str().unwrap().to_owned();
        let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
        assert_eq!(status, StatusCode::OK, "{adopted}");
    }

    // Tamper the stored payload bytes: digest and size no longer verify.
    {
        let conn = rusqlite::Connection::open(&db_path).unwrap();
        conn.execute(
            "UPDATE package_resource_payloads SET body=?1 WHERE resource_id=?2",
            params![b"tampered payload bytes".to_vec(), resource_id.as_str()],
        )
        .unwrap();
    }

    let reopened = file_app(&db_path);
    let (status, body) = read_payload(&reopened, &material_id, resource_id.as_str()).await;
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    let body: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(body["code"], "composition_integrity_failure");
    assert_eq!(
        body["message"],
        "adopted composition content is missing or fails integrity verification"
    );
    assert_eq!(body["retryable"], false);
}

#[tokio::test]
async fn stale_revision_adopted_composition_is_integrity_failure() {
    let app = test_app();
    let material = create_text_material(&app, "Stale composition.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (directory, _, _) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-stale-composition",
        "Stale composition.",
        "machine_checked",
    );
    let (status, installed) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{installed}");
    let release_id = installed["release_id"].as_str().unwrap().to_owned();
    let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::OK, "{adopted}");

    // Append a new revision: the adopted composition is now stale. The
    // composition authority fails closed instead of silently serving the old
    // selection.
    let digest = hex::encode(Sha256::digest(b"new revision text"));
    let (status, appended) = {
        let response = app
            .clone()
            .oneshot(
                Request::post(format!("/v1/materials/{material_id}/revisions"))
                    .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                    .header(CONTENT_TYPE, "application/json")
                    .body(Body::from(
                        json!({
                            "title": "Stale composition v2",
                            "source_assets": [{
                                "media_type": "text/plain",
                                "byte_length": b"new revision text".len(),
                                "sha256_digest": digest,
                                "binding": { "type": "managed" },
                            }],
                            "document_renditions": [{
                                "media_type": "text/plain",
                                "language": null,
                                "digest": digest,
                                "byte_size": b"new revision text".len(),
                                "source_asset_index": 0,
                            }],
                            "media_renditions": [],
                        })
                        .to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();
        let status = response.status();
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        (status, serde_json::from_slice::<Value>(&body).unwrap())
    };
    assert_eq!(status, StatusCode::OK, "{appended}");

    let (status, body) = read_composition(&app, &material_id).await;
    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(body["code"], "composition_integrity_failure");
}

#[tokio::test]
async fn unselected_composition_reads_are_typed_not_found() {
    let app = test_app();
    let material = create_text_material(&app, "Selection text.").await;
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (directory, _, _) = text_release_carrier(
        &material_id,
        &revision_id,
        "edition-selection",
        "Selection text.",
        "machine_checked",
    );
    let (status, installed) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{installed}");
    let release_id = installed["release_id"].as_str().unwrap().to_owned();
    let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::OK, "{adopted}");

    let (status, body) = read_payload(&app, &material_id, "resource-never-selected").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let body: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(body["code"], "not_found");

    let (status, body) = read_blob(&app, &material_id, "rendition-never-selected").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let body: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(body["code"], "not_found");
}

#[tokio::test]
async fn referenced_source_asset_unavailability_is_source_unavailable() {
    // A Source Document Rendition whose bound Source Asset is referenced in
    // place and unreachable: the blob read is an explicit source_unavailable,
    // and the Material with its adoption stay untouched.
    let app = test_app();
    let text = "Reference text.";
    let digest = hex::encode(Sha256::digest(text.as_bytes()));
    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/materials")
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "title": "Wire Fixture",
                        "source_assets": [{
                            "media_type": "text/plain",
                            "byte_length": text.len(),
                            "sha256_digest": digest,
                            "binding": { "type": "referenced", "reference": "/opaque/reference" },
                        }],
                        "document_renditions": [{
                            "media_type": "text/plain",
                            "language": "en",
                            "digest": digest,
                            "byte_size": text.len(),
                            "source_asset_index": 0,
                        }],
                        "media_renditions": [],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let material: Value =
        serde_json::from_slice(&to_bytes(response.into_body(), usize::MAX).await.unwrap()).unwrap();
    let material_id = material["material"]["id"].as_str().unwrap().to_owned();
    let revision_id = material["current_revision"]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    let source_asset_id = material["current_revision"]["source_assets"][0]["id"]
        .as_str()
        .unwrap()
        .to_owned();

    // The carrier binds a Source rendition with no embedded blob: the carrier
    // declares the rendition's bytes as referenced, not embedded.
    let structured = structured_payload(text);
    let payload_bytes = canonical_bytes(&structured);
    let payload_digest = sha256_id(&payload_bytes);
    let descriptor = base_descriptor(
        STRUCTURED_READING_SCHEMA_V1,
        "en",
        &payload_digest,
        payload_bytes.len() as u64,
        &revision_id,
        "machine_checked",
    );
    let resource = resource_entry(&descriptor, true);
    let text_digest = sha256_id(text.as_bytes());
    let text_blob = json!({
        "digest": text_digest,
        "size_bytes": text.len() as u64,
        "embedded": false,
    });
    let rendition_id = sha256_id(&canonical_bytes(&json!({
        "media_type": "text/plain",
        "language": "en",
        "text_blob": text_blob,
    })));
    let document = json!({
        "rendition_id": rendition_id,
        "origin": "source",
        "media_type": "text/plain",
        "language": "en",
        "text_blob": text_blob,
        "source_asset_id": text_digest,
        "producer": null,
        "compatibility": null,
        "extensions": {},
    });
    let release = json!({
        "schema": RELEASE_SCHEMA_V3,
        "created_at_ms": 1u64,
        "edition": {
            "edition_id": "edition-reference",
            "title": "Reference Edition",
            "target_language": "en",
            "support_languages": ["zh-Hans"],
        },
        "material": {
            "material_id": material_id,
            "material_revision_id": revision_id,
            "title": "Reference Material",
        },
        "document_renditions": [document],
        "media_renditions": [],
        "resources": [resource],
        "extensions": {},
    });
    let mut files = BTreeMap::new();
    files.insert("release.json".into(), canonical_bytes(&release));
    files.insert(blob_path(&payload_digest), payload_bytes);
    let directory = TestDirectory::new();
    for (name, bytes) in &files {
        let path = directory.path().join(name);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, bytes).unwrap();
    }

    let (status, installed) = install_package(&app, &material_id, directory.path()).await;
    assert_eq!(status, StatusCode::OK, "{installed}");
    let release_id = installed["release_id"].as_str().unwrap().to_owned();
    let (status, adopted) = adopt_edition(&app, &material_id, &release_id).await;
    assert_eq!(status, StatusCode::OK, "{adopted}");

    // The referenced Source Asset is reported unavailable through the
    // availability operation.
    let (status, updated) = {
        let response = app
            .clone()
            .oneshot(
                Request::put(format!(
                    "/v1/materials/{material_id}/source-assets/{source_asset_id}/availability"
                ))
                .header(AUTHORIZATION, format!("Bearer {TOKEN}"))
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({
                        "availability": {
                            "state": "unavailable",
                            "reason": "file_missing",
                        }
                    })
                    .to_string(),
                ))
                .unwrap(),
            )
            .await
            .unwrap();
        let status = response.status();
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        (status, serde_json::from_slice::<Value>(&body).unwrap())
    };
    assert_eq!(status, StatusCode::OK, "{updated}");

    // The blob is not stored (embedded: false) and the referenced Source
    // Asset is unreachable: an explicit source_unavailable that never deletes
    // the Material or the adoption.
    let (status, body) = read_blob(&app, &material_id, &rendition_id).await;
    assert_eq!(status, StatusCode::BAD_GATEWAY);
    let body: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(body["code"], "source_unavailable");
    assert_eq!(body["retryable"], true);

    let (status, composition) = read_composition(&app, &material_id).await;
    assert_eq!(status, StatusCode::OK, "{composition}");
    assert_eq!(composition["release_id"], release_id);
}
