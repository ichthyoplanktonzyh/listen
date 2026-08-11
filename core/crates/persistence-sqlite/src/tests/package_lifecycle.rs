//! Repository-level acceptance tests for the durable package lifecycle.
//!
//! These tests exercise the real SQLite `PackageLifecycleRepository` through
//! the `application` trait seam, with direct SQL only where the contract is
//! constraint-level or fault-injection level: payload row inspection, byte
//! tampering, and trigger-injected failures. The closing seam test drives
//! `list_editions` and `adopt_for_material` through `AppServices` and proves
//! the state survives a database close and reopen.

use std::sync::Arc;

use application::{
    AppServices, ApplicationError, MaterialRepository, PackageLifecycleRepository,
    PreparedPackageInstallation, PreparedResourcePayload,
};
use domain::{
    AdoptionCommitPlan, DocumentTextAsset, ExclusiveSelection, LanguageCode, LearningEdition,
    LearningMaterial, LearningMaterialId, MaterialAsset, MaterialRevision, MaterialRevisionId,
    PackageInstallation, PackageReleaseId, PackageRenditionFact, PackageResourceAvailability,
    PackageResourceFact, PackageResourceProvenance, PackageResourceRole, PackageReviewStatus,
    adoption_commit_plan, initial_material_id,
};

use super::*;
use crate::package_lifecycle::query_payloads;
use sha2::{Digest as _, Sha256};

fn sha256_id(bytes: &[u8]) -> String {
    format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
}

fn language(code: &str) -> LanguageCode {
    LanguageCode::parse(code).unwrap()
}

fn edition(edition_id: &str) -> LearningEdition {
    LearningEdition {
        edition_id: domain::LearningEditionId::parse(edition_id).unwrap(),
        title: format!("Edition {edition_id}"),
        target_language: language("en"),
        support_languages: vec![language("zh-Hans")],
    }
}

fn provenance() -> PackageResourceProvenance {
    PackageResourceProvenance {
        created_at_ms: 1,
        tool_id: "listen-gen".into(),
        tool_version: "0.4.0".into(),
        provider_id: None,
        provider_version: None,
        model_id: None,
        model_version: None,
        config_sha256: None,
    }
}

fn resource_fact(
    resource_id: &str,
    kind: &str,
    availability: PackageResourceAvailability,
    digest: &str,
    size_bytes: u64,
) -> PackageResourceFact {
    PackageResourceFact {
        resource_id: resource_id.to_owned(),
        kind: kind.to_owned(),
        schema: format!("listen.payload.{kind}.v1"),
        role: PackageResourceRole::Base,
        required: availability == PackageResourceAvailability::Available,
        availability,
        content_language: Some(language("en")),
        support_languages: Vec::new(),
        dependencies: Vec::new(),
        payload_digest: digest.to_owned(),
        payload_size_bytes: size_bytes,
        provenance: provenance(),
        review_status: PackageReviewStatus::MachineChecked,
        quality_warnings: Vec::new(),
    }
}

fn rendition_fact(rendition_id: &str, kind: &str, available: bool) -> PackageRenditionFact {
    PackageRenditionFact {
        rendition_id: rendition_id.to_owned(),
        kind: kind.to_owned(),
        media_type: format!("audio/{kind}"),
        available,
        media_digest: format!("sha256:{}", "a".repeat(64)),
        media_size_bytes: 100,
    }
}

fn payload(resource_id: &str, kind: &str, bytes: Vec<u8>) -> PreparedResourcePayload {
    let digest = sha256_id(&bytes);
    PreparedResourcePayload {
        resource_id: resource_id.to_owned(),
        kind: kind.to_owned(),
        schema: format!("listen.payload.{kind}.v1"),
        digest,
        size_bytes: bytes.len() as u64,
        bytes,
    }
}

fn prepared(
    material: &LearningMaterial,
    revision: &MaterialRevision,
    release_id: &str,
    edition_id: &str,
    resources: Vec<PackageResourceFact>,
    payloads: Vec<PreparedResourcePayload>,
) -> PreparedPackageInstallation {
    PreparedPackageInstallation {
        installation: PackageInstallation {
            release_id: PackageReleaseId::parse(release_id).unwrap(),
            release_created_at_ms: 1,
            material_id: material.id.clone(),
            material_revision_id: revision.id.clone(),
            edition: edition(edition_id),
            resources,
            renditions: Vec::new(),
            installed_at_ms: 0,
        },
        payloads,
    }
}

fn text_prepared(
    material: &LearningMaterial,
    revision: &MaterialRevision,
    release_id: &str,
    edition_id: &str,
) -> PreparedPackageInstallation {
    let bytes = b"fixture document payload bytes".to_vec();
    let digest = sha256_id(&bytes);
    let fact = resource_fact(
        "resource-document",
        "document_text",
        PackageResourceAvailability::Available,
        &digest,
        bytes.len() as u64,
    );
    prepared(
        material,
        revision,
        release_id,
        edition_id,
        vec![fact],
        vec![payload("resource-document", "document_text", bytes)],
    )
}

fn seed_material(repo: &Arc<SqliteRepository>, text: &str) -> (LearningMaterial, MaterialRevision) {
    let asset =
        MaterialAsset::DocumentText(DocumentTextAsset::new(text, Some(language("en"))).unwrap());
    let material_id = initial_material_id(std::slice::from_ref(&asset)).unwrap();
    let revision = MaterialRevision::new(material_id.clone(), "Material", vec![asset], 1).unwrap();
    let material = LearningMaterial::new(&revision, None, 1, 1).unwrap();
    MaterialRepository::create_material(repo.as_ref(), &material, &revision).unwrap();
    (material, revision)
}

fn count(repo: &SqliteRepository, table: &str) -> u32 {
    repo.connection
        .lock()
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .unwrap()
}

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
    .with_package_lifecycle_repository(repo.clone())
}

// ---------------------------------------------------------------------
// Installation
// ---------------------------------------------------------------------

#[test]
fn save_installation_round_trips_facts_and_exact_payload_bytes() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let input = text_prepared(&material, &revision, "sha256:release-a", "edition-a");
    assert_eq!(
        input.installation.installed_at_ms, 0,
        "the caller hands a zero timestamp"
    );

    let persisted = PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();

    assert_ne!(
        persisted.installed_at_ms, 0,
        "the adapter stamps the installation time on first persist"
    );
    let read = PackageLifecycleRepository::get_installation(
        repo.as_ref(),
        &material.id,
        &persisted.release_id,
    )
    .unwrap()
    .expect("installation reads back");
    assert_eq!(read.installed_at_ms, persisted.installed_at_ms);
    // The stored row carries the adapter-stamped time, not the caller's zero.
    let stored_row: u64 = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT installed_at_ms FROM package_installations
             WHERE material_id=?1 AND release_id=?2",
            params![material.id.as_str(), persisted.release_id.as_str()],
            |row| row.get(0),
        )
        .unwrap()
    };
    assert_eq!(stored_row, persisted.installed_at_ms);
    // The exact carrier bytes are stored as a BLOB, never in the JSON facts.
    let conn = repo.connection.lock();
    let stored =
        query_payloads(&conn, material.id.as_str(), persisted.release_id.as_str()).unwrap();
    assert_eq!(stored.len(), 1);
    assert_eq!(stored[0].resource_id, "resource-document");
    assert_eq!(stored[0].kind, "document_text");
    assert_eq!(
        stored[0].schema, input.payloads[0].schema,
        "the payload fact's schema is stored verbatim"
    );
    assert_eq!(
        stored[0].digest,
        sha256_id(b"fixture document payload bytes")
    );
    assert_eq!(stored[0].size_bytes, 30);
    assert_eq!(stored[0].bytes, b"fixture document payload bytes");
}

#[test]
fn known_and_present_opaque_payloads_persist_exactly() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let doc_bytes = b"document body".to_vec();
    let opaque_bytes = b"opaque future analysis body".to_vec();
    let doc_digest = sha256_id(&doc_bytes);
    let opaque_digest = sha256_id(&opaque_bytes);
    let input = prepared(
        &material,
        &revision,
        "sha256:release-mixed",
        "edition-mixed",
        vec![
            resource_fact(
                "resource-document",
                "document_text",
                PackageResourceAvailability::Available,
                &doc_digest,
                doc_bytes.len() as u64,
            ),
            resource_fact(
                "resource-opaque",
                "future_analysis",
                PackageResourceAvailability::Opaque,
                &opaque_digest,
                opaque_bytes.len() as u64,
            ),
        ],
        vec![
            payload("resource-document", "document_text", doc_bytes.clone()),
            payload("resource-opaque", "future_analysis", opaque_bytes.clone()),
        ],
    );

    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();

    let conn = repo.connection.lock();
    let stored = query_payloads(
        &conn,
        material.id.as_str(),
        input.installation.release_id.as_str(),
    )
    .unwrap();
    assert_eq!(stored.len(), 2);
    assert_eq!(stored[0].bytes, doc_bytes);
    assert_eq!(stored[1].bytes, opaque_bytes);
}

#[test]
fn missing_resource_has_no_payload_row_and_reads_back_unavailable() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let bytes = b"document body".to_vec();
    let digest = sha256_id(&bytes);
    let missing_digest = sha256_id(b"never carried");
    let input = prepared(
        &material,
        &revision,
        "sha256:release-with-missing",
        "edition-missing",
        vec![
            resource_fact(
                "resource-document",
                "document_text",
                PackageResourceAvailability::Available,
                &digest,
                bytes.len() as u64,
            ),
            resource_fact(
                "resource-optional",
                "word_timeline",
                PackageResourceAvailability::Missing,
                &missing_digest,
                0,
            ),
        ],
        vec![payload("resource-document", "document_text", bytes)],
    );

    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();

    assert_eq!(
        count(&repo, "package_resource_payloads"),
        1,
        "a missing resource must not have a payload row"
    );
    let read = PackageLifecycleRepository::get_installation(
        repo.as_ref(),
        &material.id,
        &input.installation.release_id,
    )
    .unwrap()
    .unwrap();
    let missing = read
        .resources
        .iter()
        .find(|fact| fact.resource_id == "resource-optional")
        .unwrap();
    assert_eq!(missing.availability, PackageResourceAvailability::Missing);
}

#[test]
fn installations_survive_reopening_a_file_database() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("package-lifecycle.db");
    let (material_id, release_id, installed_at_ms) = {
        let repo = Arc::new(SqliteRepository::open(&path).unwrap());
        let (material, revision) = seed_material(&repo, "Hello world.");
        let input = text_prepared(
            &material,
            &revision,
            "sha256:release-reopen",
            "edition-reopen",
        );
        let persisted =
            PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
        (material.id, persisted.release_id, persisted.installed_at_ms)
    };

    let reopened = Arc::new(SqliteRepository::open(&path).unwrap());
    let read =
        PackageLifecycleRepository::get_installation(reopened.as_ref(), &material_id, &release_id)
            .unwrap()
            .expect("installation survives reopen");
    assert_eq!(
        read.installed_at_ms, installed_at_ms,
        "the adapter-stamped time survives the reopen"
    );
    let listed =
        PackageLifecycleRepository::list_installations(reopened.as_ref(), &material_id).unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].release_id, release_id);
    // Payload rows survive with exact bytes.
    let conn = reopened.connection.lock();
    let stored = query_payloads(&conn, material_id.as_str(), release_id.as_str()).unwrap();
    assert_eq!(stored.len(), 1);
    assert_eq!(stored[0].bytes, b"fixture document payload bytes");
}

#[test]
fn equal_reinstall_keeps_one_installation_and_the_original_installed_at_ms() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let first = text_prepared(
        &material,
        &revision,
        "sha256:release-equal",
        "edition-equal",
    );
    let persisted = PackageLifecycleRepository::save_installation(repo.as_ref(), &first).unwrap();
    let stamped = persisted.installed_at_ms;
    assert_ne!(stamped, 0, "the adapter stamps the installation time");

    // The caller produces a fresh timestamp on retry; it must not become part
    // of the equality or rewrite the stored value.
    let mut retry = text_prepared(
        &material,
        &revision,
        "sha256:release-equal",
        "edition-equal",
    );
    retry.installation.installed_at_ms = 999;
    let returned = PackageLifecycleRepository::save_installation(repo.as_ref(), &retry).unwrap();
    assert_eq!(
        returned.installed_at_ms, stamped,
        "an equal retry preserves the adapter-stamped installation timestamp"
    );
    assert_eq!(count(&repo, "package_installations"), 1);
    assert_eq!(count(&repo, "package_resource_payloads"), 1);
}

#[test]
fn adapter_stamps_installed_at_ms_at_first_persist() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("stamp.db");
    let (material_id, stamped) = {
        let repo = Arc::new(SqliteRepository::open(&path).unwrap());
        let (material, revision) = seed_material(&repo, "Hello world.");
        // a. The caller hands `installed_at_ms = 0`; the candidate timestamp
        // must never be persisted.
        let input = text_prepared(
            &material,
            &revision,
            "sha256:release-stamp",
            "edition-stamp",
        );
        assert_eq!(input.installation.installed_at_ms, 0);
        let before = application::now_ms();
        let persisted =
            PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
        // b. The returned and stored value is a plausible current time, not 0.
        let stamped = persisted.installed_at_ms;
        assert_ne!(stamped, 0, "the adapter stamps a nonzero time");
        let after = application::now_ms();
        assert!(
            stamped >= before.saturating_sub(60_000) && stamped <= after + 60_000,
            "the stamped time {stamped} is not a plausible current time (before {before}, after {after})"
        );
        let stored_row: u64 = {
            let conn = repo.connection.lock();
            conn.query_row(
                "SELECT installed_at_ms FROM package_installations
                 WHERE material_id=?1 AND release_id=?2",
                params![material.id.as_str(), persisted.release_id.as_str()],
                |row| row.get(0),
            )
            .unwrap()
        };
        assert_eq!(stored_row, stamped);

        // c. An equal retry with another candidate time returns the first
        // adapter-stamped time.
        let mut retry = input.clone();
        retry.installation.installed_at_ms = 123_456;
        let returned =
            PackageLifecycleRepository::save_installation(repo.as_ref(), &retry).unwrap();
        assert_eq!(
            returned.installed_at_ms, stamped,
            "an equal retry ignores the caller's fresh timestamp"
        );
        (material.id.clone(), stamped)
    };

    // d. The adapter-stamped time survives a close and reopen.
    let reopened = Arc::new(SqliteRepository::open(&path).unwrap());
    let read = PackageLifecycleRepository::get_installation(
        reopened.as_ref(),
        &material_id,
        &PackageReleaseId::parse("sha256:release-stamp").unwrap(),
    )
    .unwrap()
    .expect("installation survives reopen");
    assert_eq!(
        read.installed_at_ms, stamped,
        "the adapter-stamped time survives the reopen"
    );
}

#[test]
fn unequal_facts_under_the_same_identity_fail_closed() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let first = text_prepared(&material, &revision, "sha256:release-conflict", "edition-a");
    PackageLifecycleRepository::save_installation(repo.as_ref(), &first).unwrap();

    // Different edition identity under the same (material_id, release_id).
    let mut conflicting =
        text_prepared(&material, &revision, "sha256:release-conflict", "edition-b");
    conflicting.installation.edition = edition("edition-b");
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &conflicting)
        .expect_err("unequal facts must fail closed");
    assert!(matches!(error, ApplicationError::Repository(_)));
    assert_eq!(count(&repo, "package_installations"), 1);
    assert_eq!(count(&repo, "package_resource_payloads"), 1);
    let stored = PackageLifecycleRepository::get_installation(
        repo.as_ref(),
        &material.id,
        &first.installation.release_id,
    )
    .unwrap()
    .unwrap();
    assert_eq!(
        stored.edition,
        edition("edition-a"),
        "the original facts are untouched"
    );
}

#[test]
fn unequal_payload_bytes_or_metadata_fail_closed() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let first = text_prepared(
        &material,
        &revision,
        "sha256:release-payload-conflict",
        "edition-a",
    );
    PackageLifecycleRepository::save_installation(repo.as_ref(), &first).unwrap();

    // Same facts, different payload bytes.
    let mut byte_conflict = text_prepared(
        &material,
        &revision,
        "sha256:release-payload-conflict",
        "edition-a",
    );
    byte_conflict.payloads[0].bytes = b"completely different payload bytes".to_vec();
    byte_conflict.payloads[0].digest = sha256_id(&byte_conflict.payloads[0].bytes);
    byte_conflict.payloads[0].size_bytes = byte_conflict.payloads[0].bytes.len() as u64;
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &byte_conflict)
        .expect_err("unequal payload bytes must fail closed");
    assert!(matches!(error, ApplicationError::Repository(_)));

    // Same facts and bytes, different payload metadata (digest).
    let mut metadata_conflict = text_prepared(
        &material,
        &revision,
        "sha256:release-payload-conflict",
        "edition-a",
    );
    metadata_conflict.payloads[0].digest = sha256_id(b"a different digest for the same bytes");
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &metadata_conflict)
        .expect_err("unequal payload metadata must fail closed");
    assert!(matches!(error, ApplicationError::Repository(_)));

    assert_eq!(count(&repo, "package_installations"), 1);
    assert_eq!(count(&repo, "package_resource_payloads"), 1);
    let conn = repo.connection.lock();
    let stored = query_payloads(
        &conn,
        material.id.as_str(),
        first.installation.release_id.as_str(),
    )
    .unwrap();
    assert_eq!(stored[0].bytes, b"fixture document payload bytes");
}

#[test]
fn invalid_prepared_payload_associations_are_rejected_with_zero_writes() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let base = text_prepared(
        &material,
        &revision,
        "sha256:release-rejects",
        "edition-rejects",
    );

    let mut digest_wrong = base.clone();
    digest_wrong.payloads[0].digest = sha256_id(b"digest of something else");

    let mut size_wrong = base.clone();
    size_wrong.payloads[0].size_bytes = 7;

    let mut kind_wrong = base.clone();
    kind_wrong.payloads[0].kind = "subtitle_text_track".into();

    let mut schema_wrong = base.clone();
    schema_wrong.payloads[0].schema = "listen.payload.subtitle-text-track.v1".into();

    // A body attached to a resource that does not exist in the facts.
    let mut extra_wrong = base.clone();
    extra_wrong.payloads.push(payload(
        "resource-ghost",
        "document_text",
        b"ghost".to_vec(),
    ));

    // An Available resource without a body.
    let mut missing_body = base.clone();
    missing_body.payloads.clear();

    // A Missing resource that carries a body.
    let mut missing_with_body = base.clone();
    missing_with_body.installation.resources[0].availability = PackageResourceAvailability::Missing;
    missing_with_body.installation.resources[0].required = false;

    // A duplicate body for the same resource.
    let mut duplicate = base.clone();
    duplicate.payloads.push(duplicate.payloads[0].clone());

    for (label, candidate) in [
        ("digest mismatch", digest_wrong),
        ("size mismatch", size_wrong),
        ("kind mismatch", kind_wrong),
        ("schema mismatch", schema_wrong),
        ("extra unassociated body", extra_wrong),
        ("available resource without body", missing_body),
        ("missing resource with body", missing_with_body),
        ("duplicate body", duplicate),
    ] {
        let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &candidate)
            .expect_err("{label} must be rejected");
        assert!(matches!(error, ApplicationError::Repository(_)));
        assert_eq!(
            count(&repo, "package_installations"),
            0,
            "{label} must leave no installation"
        );
        assert_eq!(
            count(&repo, "package_resource_payloads"),
            0,
            "{label} must leave no payload rows"
        );
    }
}

#[test]
fn a_payload_insert_failure_rolls_back_facts_and_all_payloads() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let doc_bytes = b"document body".to_vec();
    let timeline_bytes = b"timeline body".to_vec();
    let doc_digest = sha256_id(&doc_bytes);
    let timeline_digest = sha256_id(&timeline_bytes);
    let input = prepared(
        &material,
        &revision,
        "sha256:release-trigger",
        "edition-trigger",
        vec![
            resource_fact(
                "resource-document",
                "document_text",
                PackageResourceAvailability::Available,
                &doc_digest,
                doc_bytes.len() as u64,
            ),
            resource_fact(
                "resource-timeline",
                "word_timeline",
                PackageResourceAvailability::Available,
                &timeline_digest,
                timeline_bytes.len() as u64,
            ),
        ],
        vec![
            payload("resource-document", "document_text", doc_bytes),
            payload("resource-timeline", "word_timeline", timeline_bytes),
        ],
    );
    {
        let conn = repo.connection.lock();
        conn.execute_batch(
            "CREATE TRIGGER fail_second_payload
             BEFORE INSERT ON package_resource_payloads
             WHEN NEW.resource_id = 'resource-timeline'
             BEGIN
               SELECT RAISE(ABORT, 'injected payload failure');
             END;",
        )
        .unwrap();
    }

    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &input)
        .expect_err("the injected payload failure must abort the installation");
    assert!(matches!(error, ApplicationError::Repository(_)));
    assert_eq!(
        count(&repo, "package_installations"),
        0,
        "no installation-only row may survive"
    );
    assert_eq!(
        count(&repo, "package_resource_payloads"),
        0,
        "no partial payload rows may survive"
    );
}

#[test]
fn duplicate_resource_or_rendition_facts_are_rejected_with_zero_writes() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");

    // Two resource facts with the same resource id, sharing one valid
    // payload: the duplicate identity must be rejected explicitly, never
    // covered by a map overwrite.
    let mut duplicate_resource = text_prepared(
        &material,
        &revision,
        "sha256:release-dup-resource",
        "edition-dup-resource",
    );
    duplicate_resource
        .installation
        .resources
        .push(duplicate_resource.installation.resources[0].clone());
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &duplicate_resource)
        .expect_err("duplicate resource ids must be rejected");
    assert!(matches!(error, ApplicationError::Repository(_)));
    let error_text = format!("{error:?}");
    assert!(
        !error_text.contains("resource-document"),
        "the error must not leak the duplicate fact identity"
    );
    assert!(
        !error_text.contains("fixture document payload bytes"),
        "the error must not leak payload bytes"
    );
    assert_eq!(count(&repo, "package_installations"), 0);
    assert_eq!(count(&repo, "package_resource_payloads"), 0);

    // Two rendition facts with the same rendition id: rejected the same way.
    let mut duplicate_rendition = text_prepared(
        &material,
        &revision,
        "sha256:release-dup-rendition",
        "edition-dup-rendition",
    );
    duplicate_rendition.installation.renditions = vec![
        rendition_fact("rendition-1", "audio", true),
        rendition_fact("rendition-1", "video", false),
    ];
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &duplicate_rendition)
        .expect_err("duplicate rendition ids must be rejected");
    assert!(matches!(error, ApplicationError::Repository(_)));
    let error_text = format!("{error:?}");
    assert!(
        !error_text.contains("rendition-1"),
        "the error must not leak the duplicate rendition identity"
    );
    assert_eq!(count(&repo, "package_installations"), 0);
    assert_eq!(count(&repo, "package_resource_payloads"), 0);
}

#[test]
fn stale_or_foreign_revision_is_rejected_inside_the_adapter_transaction() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, v1) = seed_material(&repo, "Hello world.");
    let first = text_prepared(&material, &v1, "sha256:release-v1", "edition-v1");
    PackageLifecycleRepository::save_installation(repo.as_ref(), &first).unwrap();

    // A newer revision becomes current; installing for the stale v1 must be
    // rejected by the adapter transaction with zero writes.
    let text_asset = MaterialAsset::DocumentText(
        DocumentTextAsset::new("second text", Some(language("en"))).unwrap(),
    );
    let v2 =
        MaterialRevision::new(material.id.clone(), "Material v2", vec![text_asset], 2).unwrap();
    MaterialRepository::append_revision(repo.as_ref(), &material.id, &v2, 2).unwrap();

    let stale = text_prepared(&material, &v1, "sha256:release-stale", "edition-stale");
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &stale)
        .expect_err("a stale revision must be rejected");
    assert!(matches!(error, ApplicationError::Invalid(_)));
    assert_eq!(count(&repo, "package_installations"), 1);

    // A revision that belongs to another material is rejected too: the
    // installation claims this material but points at the other material's
    // revision.
    let (other, other_revision) = seed_material(&repo, "other material text");
    let foreign = text_prepared(
        &material,
        &other_revision,
        "sha256:release-foreign",
        "edition-foreign",
    );
    assert_ne!(foreign.installation.material_id, other.id);
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &foreign)
        .expect_err("a foreign revision must be rejected");
    assert!(matches!(error, ApplicationError::Repository(_)));
    assert_eq!(count(&repo, "package_installations"), 1);

    // A missing revision and a missing material are not found, not written.
    let mut missing_revision = text_prepared(
        &material,
        &v1,
        "sha256:release-missing-rev",
        "edition-missing",
    );
    missing_revision.installation.material_revision_id =
        MaterialRevisionId::parse("missing-revision").unwrap();
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &missing_revision)
        .expect_err("a missing revision must be rejected");
    assert!(matches!(
        error,
        ApplicationError::NotFound("material revision")
    ));
    let mut missing_material = text_prepared(
        &material,
        &v1,
        "sha256:release-missing-mat",
        "edition-missing",
    );
    missing_material.installation.material_id =
        LearningMaterialId::parse("missing-material").unwrap();
    let error = PackageLifecycleRepository::save_installation(repo.as_ref(), &missing_material)
        .expect_err("a missing material must be rejected");
    assert!(matches!(error, ApplicationError::NotFound("material")));
    assert_eq!(count(&repo, "package_installations"), 1);
}

#[test]
fn list_installations_is_deterministic_and_includes_historical_revisions() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, v1) = seed_material(&repo, "Hello world.");
    let release_a = text_prepared(&material, &v1, "sha256:release-aaa", "edition-a");
    PackageLifecycleRepository::save_installation(repo.as_ref(), &release_a).unwrap();

    // v2 becomes current; the v1 installation stays listed for its revision.
    let text_asset = MaterialAsset::DocumentText(
        DocumentTextAsset::new("second text", Some(language("en"))).unwrap(),
    );
    let v2 =
        MaterialRevision::new(material.id.clone(), "Material v2", vec![text_asset], 2).unwrap();
    MaterialRepository::append_revision(repo.as_ref(), &material.id, &v2, 2).unwrap();
    let release_b = text_prepared(&material, &v2, "sha256:release-zzz", "edition-b");
    PackageLifecycleRepository::save_installation(repo.as_ref(), &release_b).unwrap();

    let listed =
        PackageLifecycleRepository::list_installations(repo.as_ref(), &material.id).unwrap();
    let release_ids: Vec<&str> = listed.iter().map(|i| i.release_id.as_str()).collect();
    assert_eq!(
        release_ids,
        vec!["sha256:release-aaa", "sha256:release-zzz"]
    );
    assert_eq!(listed[0].material_revision_id, v1.id);
    assert_eq!(listed[1].material_revision_id, v2.id);
}

// ---------------------------------------------------------------------
// Adoption
// ---------------------------------------------------------------------

fn text_adoption(
    repo: &Arc<SqliteRepository>,
    material: &LearningMaterial,
    release_id: &str,
) -> AdoptionCommitPlan {
    let installation = PackageLifecycleRepository::get_installation(
        repo.as_ref(),
        &material.id,
        &PackageReleaseId::parse(release_id).unwrap(),
    )
    .unwrap()
    .expect("installation exists");
    adoption_commit_plan(&installation, 500).unwrap()
}

#[test]
fn valid_text_only_adoption_persists_and_survives_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("adoption-reopen.db");
    let (material_id, revision_id, adopted_at_ms) = {
        let repo = Arc::new(SqliteRepository::open(&path).unwrap());
        let (material, revision) = seed_material(&repo, "Hello world.");
        let input = text_prepared(
            &material,
            &revision,
            "sha256:release-adopt",
            "edition-adopt",
        );
        PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
        let plan = text_adoption(&repo, &material, "sha256:release-adopt");
        let committed = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan).unwrap();
        assert_eq!(committed, plan);
        (material.id.clone(), revision.id.clone(), plan.adopted_at_ms)
    };

    let reopened = Arc::new(SqliteRepository::open(&path).unwrap());
    let restored = PackageLifecycleRepository::get_adoption(reopened.as_ref(), &material_id)
        .unwrap()
        .expect("adoption survives reopen");
    assert_eq!(restored.adopted_at_ms, adopted_at_ms);
    assert_eq!(restored.release_id.as_str(), "sha256:release-adopt");
    assert_eq!(restored.material_revision_id, revision_id);
    assert_eq!(
        restored.selected_resource_ids,
        vec!["resource-document".to_owned()]
    );
    assert_eq!(
        restored.exclusive_selections,
        vec![ExclusiveSelection {
            family: "exclusive:document_text".into(),
            resource_id: "resource-document".into(),
        }]
    );
}

#[test]
fn media_resource_selection_plan_round_trips_completely() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let doc_bytes = b"document body".to_vec();
    let timeline_bytes = b"timeline body".to_vec();
    let doc_digest = sha256_id(&doc_bytes);
    let timeline_digest = sha256_id(&timeline_bytes);
    let mut input = prepared(
        &material,
        &revision,
        "sha256:release-full",
        "edition-full",
        vec![
            resource_fact(
                "resource-document",
                "document_text",
                PackageResourceAvailability::Available,
                &doc_digest,
                doc_bytes.len() as u64,
            ),
            resource_fact(
                "resource-timeline",
                "word_timeline",
                PackageResourceAvailability::Available,
                &timeline_digest,
                timeline_bytes.len() as u64,
            ),
            resource_fact(
                "resource-optional",
                "subtitle_text_track",
                PackageResourceAvailability::Missing,
                &sha256_id(b"never"),
                0,
            ),
        ],
        vec![
            payload("resource-document", "document_text", doc_bytes),
            payload("resource-timeline", "word_timeline", timeline_bytes),
        ],
    );
    input.installation.renditions = vec![
        rendition_fact("rendition-1", "audio", true),
        rendition_fact("rendition-2", "video", false),
    ];
    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();

    let plan = text_adoption(&repo, &material, "sha256:release-full");
    assert_eq!(
        plan.selected_resource_ids,
        vec![
            "resource-document".to_owned(),
            "resource-timeline".to_owned()
        ]
    );
    assert_eq!(plan.exclusive_selections.len(), 2);
    assert_eq!(plan.selected_rendition_ids, vec!["rendition-1".to_owned()]);

    let committed = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan).unwrap();
    assert_eq!(committed, plan);
    let restored = PackageLifecycleRepository::get_adoption(repo.as_ref(), &material.id)
        .unwrap()
        .unwrap();
    assert_eq!(restored, plan);
}

#[test]
fn forged_or_incomplete_selection_plans_are_rejected_without_an_adoption() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let input = text_prepared(
        &material,
        &revision,
        "sha256:release-forge",
        "edition-forge",
    );
    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
    let plan = text_adoption(&repo, &material, "sha256:release-forge");

    let mut extra_resource = plan.clone();
    extra_resource
        .selected_resource_ids
        .push("resource-extra".into());
    let mut missing_dependency = plan.clone();
    missing_dependency.selected_resource_ids.pop();
    let mut wrong_family = plan.clone();
    wrong_family.exclusive_selections[0].family = "exclusive:word_timeline".into();
    let mut wrong_rendition = plan.clone();
    wrong_rendition
        .selected_rendition_ids
        .push("rendition-forged".into());
    let mut wrong_edition = plan.clone();
    wrong_edition.edition = edition("edition-forged");
    let mut wrong_revision = plan.clone();
    wrong_revision.material_revision_id = MaterialRevisionId::parse("wrong-revision").unwrap();

    for (label, forged) in [
        ("extra resource", extra_resource),
        ("missing resource", missing_dependency),
        ("wrong exclusive family", wrong_family),
        ("extra rendition", wrong_rendition),
        ("wrong edition", wrong_edition),
        ("wrong revision", wrong_revision),
    ] {
        let error = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &forged)
            .expect_err("{label} must be rejected");
        assert!(
            matches!(
                error,
                ApplicationError::Repository(_)
                    | ApplicationError::Invalid(_)
                    | ApplicationError::NotFound("material revision")
            ),
            "{label} failed with {error:?}"
        );
        assert!(
            PackageLifecycleRepository::get_adoption(repo.as_ref(), &material.id)
                .unwrap()
                .is_none(),
            "{label} must not create an adoption"
        );
    }
}

#[test]
fn missing_selected_resource_backing_fails_without_an_adoption() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let input = text_prepared(
        &material,
        &revision,
        "sha256:release-backing",
        "edition-backing",
    );
    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
    {
        let conn = repo.connection.lock();
        conn.execute(
            "DELETE FROM package_resource_payloads
             WHERE material_id=?1 AND release_id=?2 AND resource_id=?3",
            params![
                material.id.as_str(),
                "sha256:release-backing",
                "resource-document",
            ],
        )
        .unwrap();
    }
    let plan = text_adoption(&repo, &material, "sha256:release-backing");
    let error = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan)
        .expect_err("missing backing must fail closed");
    assert!(matches!(error, ApplicationError::Repository(_)));
    assert!(
        PackageLifecycleRepository::get_adoption(repo.as_ref(), &material.id)
            .unwrap()
            .is_none()
    );
}

#[test]
fn tampered_payload_blob_fails_adoption_closed() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let input = text_prepared(
        &material,
        &revision,
        "sha256:release-tamper",
        "edition-tamper",
    );
    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
    {
        let conn = repo.connection.lock();
        conn.execute(
            "UPDATE package_resource_payloads SET body=?3
             WHERE material_id=?1 AND release_id=?2",
            params![
                material.id.as_str(),
                "sha256:release-tamper",
                b"tampered bytes that do not match the digest".to_vec(),
            ],
        )
        .unwrap();
    }
    let plan = text_adoption(&repo, &material, "sha256:release-tamper");
    let error = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan)
        .expect_err("tampered bytes must fail the backing verification");
    assert!(matches!(error, ApplicationError::Repository(_)));
    assert!(
        PackageLifecycleRepository::get_adoption(repo.as_ref(), &material.id)
            .unwrap()
            .is_none()
    );

    // A payload row whose digest column was forged is corrupt backing too.
    {
        let conn = repo.connection.lock();
        conn.execute(
            "UPDATE package_resource_payloads SET body=?3, digest=?4
             WHERE material_id=?1 AND release_id=?2",
            params![
                material.id.as_str(),
                "sha256:release-tamper",
                b"original body".to_vec(),
                sha256_id(b"forged digest"),
            ],
        )
        .unwrap();
    }
    let error = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan)
        .expect_err("forged payload metadata must fail the backing verification");
    assert!(matches!(error, ApplicationError::Repository(_)));
}

#[test]
fn readopt_of_the_same_release_preserves_the_original_adoption() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let input = text_prepared(
        &material,
        &revision,
        "sha256:release-readopt",
        "edition-readopt",
    );
    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
    let first = text_adoption(&repo, &material, "sha256:release-readopt");
    PackageLifecycleRepository::commit_adoption(repo.as_ref(), &first).unwrap();
    let selection_rows_before: u32 = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT COUNT(*) FROM package_adoptions WHERE material_id=?1",
            [material.id.as_str()],
            |row| row.get(0),
        )
        .unwrap()
    };

    // A re-adopt with a fresh timestamp must return the existing adoption and
    // keep the original adopted_at_ms.
    let mut retry = first.clone();
    retry.adopted_at_ms = 999_999;
    let returned = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &retry).unwrap();
    assert_eq!(
        returned, first,
        "the existing adoption is returned unchanged"
    );
    assert_eq!(returned.adopted_at_ms, first.adopted_at_ms);
    let rows_after: u32 = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT COUNT(*) FROM package_adoptions WHERE material_id=?1",
            [material.id.as_str()],
            |row| row.get(0),
        )
        .unwrap()
    };
    assert_eq!(
        rows_after, selection_rows_before,
        "no selection rows are rewritten"
    );
}

#[test]
fn readopt_fails_closed_when_the_stored_adoption_row_was_tampered() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let input = text_prepared(
        &material,
        &revision,
        "sha256:release-tampered-adoption",
        "edition-tampered-adoption",
    );
    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
    let plan = text_adoption(&repo, &material, "sha256:release-tampered-adoption");
    PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan).unwrap();

    // Directly tamper the stored selection JSON into another still-valid
    // plan, keeping the release id unchanged.
    {
        let conn = repo.connection.lock();
        conn.execute(
            "UPDATE package_adoptions
             SET selected_resource_ids_json=?2
             WHERE material_id=?1",
            params![material.id.as_str(), r#"["resource-other"]"#],
        )
        .unwrap();
    }
    let (raw, adopted_at_ms): (String, u64) = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT selected_resource_ids_json, adopted_at_ms
             FROM package_adoptions WHERE material_id=?1",
            [material.id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
    };
    assert_eq!(raw, r#"["resource-other"]"#);

    // A readopt with the correct deterministic plan must fail closed: the
    // tampered row is corruption, never silently repaired or rewritten.
    let error = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan)
        .expect_err("a tampered stored adoption row must fail the readopt");
    assert!(matches!(error, ApplicationError::Repository(_)));
    let error_text = format!("{error:?}");
    assert!(
        !error_text.contains("resource-other") && !error_text.contains("resource-document"),
        "the error must not leak the adoption plan JSON"
    );

    // The row was not rewritten: the tampered JSON and the original
    // adopted_at_ms stay in place.
    let (raw_after, adopted_after): (String, u64) = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT selected_resource_ids_json, adopted_at_ms
             FROM package_adoptions WHERE material_id=?1",
            [material.id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
    };
    assert_eq!(raw_after, r#"["resource-other"]"#);
    assert_eq!(adopted_after, adopted_at_ms);
    assert_eq!(count(&repo, "package_adoptions"), 1);
    let restored = PackageLifecycleRepository::get_adoption(repo.as_ref(), &material.id)
        .unwrap()
        .expect("the tampered row still reads as an adoption");
    assert_eq!(
        restored.selected_resource_ids,
        vec!["resource-other".to_owned()]
    );
    assert_eq!(restored.adopted_at_ms, adopted_at_ms);
}

#[test]
fn switching_to_another_installed_release_replaces_the_adoption_atomically() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let release_a = text_prepared(&material, &revision, "sha256:release-switch-a", "edition-a");
    let release_b = text_prepared(&material, &revision, "sha256:release-switch-b", "edition-b");
    PackageLifecycleRepository::save_installation(repo.as_ref(), &release_a).unwrap();
    PackageLifecycleRepository::save_installation(repo.as_ref(), &release_b).unwrap();
    let plan_a = text_adoption(&repo, &material, "sha256:release-switch-a");
    PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan_a).unwrap();

    let plan_b = text_adoption(&repo, &material, "sha256:release-switch-b");
    let committed = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan_b).unwrap();
    assert_eq!(committed, plan_b);

    let current = PackageLifecycleRepository::get_adoption(repo.as_ref(), &material.id)
        .unwrap()
        .unwrap();
    assert_eq!(current.release_id.as_str(), "sha256:release-switch-b");
    assert_eq!(current.selected_resource_ids, plan_b.selected_resource_ids);
    assert_eq!(
        count(&repo, "package_adoptions"),
        1,
        "a switch replaces the single adoption row"
    );
}

#[test]
fn an_adoption_write_failure_preserves_the_previous_adoption_and_selections() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let release_a = text_prepared(
        &material,
        &revision,
        "sha256:release-trigger-a",
        "edition-a",
    );
    let release_b = text_prepared(
        &material,
        &revision,
        "sha256:release-trigger-b",
        "edition-b",
    );
    PackageLifecycleRepository::save_installation(repo.as_ref(), &release_a).unwrap();
    PackageLifecycleRepository::save_installation(repo.as_ref(), &release_b).unwrap();
    let plan_a = text_adoption(&repo, &material, "sha256:release-trigger-a");
    PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan_a).unwrap();
    {
        let conn = repo.connection.lock();
        conn.execute_batch(
            "CREATE TRIGGER fail_adoption_switch
             BEFORE UPDATE ON package_adoptions
             BEGIN
               SELECT RAISE(ABORT, 'injected adoption failure');
             END;",
        )
        .unwrap();
    }

    let plan_b = text_adoption(&repo, &material, "sha256:release-trigger-b");
    let error = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan_b)
        .expect_err("the injected adoption failure must abort the switch");
    assert!(matches!(error, ApplicationError::Repository(_)));

    let current = PackageLifecycleRepository::get_adoption(repo.as_ref(), &material.id)
        .unwrap()
        .expect("adoption A survives");
    assert_eq!(
        current, plan_a,
        "the previous adoption and selections are intact"
    );
    assert_eq!(count(&repo, "package_adoptions"), 1);
}

#[test]
fn a_stale_current_revision_switch_fails_and_preserves_the_previous_adoption() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, v1) = seed_material(&repo, "Hello world.");
    let release_a = text_prepared(&material, &v1, "sha256:release-stale-a", "edition-a");
    PackageLifecycleRepository::save_installation(repo.as_ref(), &release_a).unwrap();
    let plan_a = text_adoption(&repo, &material, "sha256:release-stale-a");
    PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan_a).unwrap();

    let text_asset = MaterialAsset::DocumentText(
        DocumentTextAsset::new("second text", Some(language("en"))).unwrap(),
    );
    let v2 =
        MaterialRevision::new(material.id.clone(), "Material v2", vec![text_asset], 2).unwrap();
    MaterialRepository::append_revision(repo.as_ref(), &material.id, &v2, 2).unwrap();

    // A commit plan for the now-stale v1 must be rejected inside the adapter
    // transaction, preserving adoption A.
    let mut stale = plan_a.clone();
    stale.adopted_at_ms = 9_000;
    let error = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &stale)
        .expect_err("a stale revision commit must be rejected");
    assert!(matches!(error, ApplicationError::Invalid(_)));
    let current = PackageLifecycleRepository::get_adoption(repo.as_ref(), &material.id)
        .unwrap()
        .unwrap();
    assert_eq!(
        current, plan_a,
        "the previous adoption survives the stale switch"
    );
}

#[test]
fn adoption_never_touches_learner_owned_tables() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let input = text_prepared(
        &material,
        &revision,
        "sha256:release-learner",
        "edition-learner",
    );
    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
    {
        let conn = repo.connection.lock();
        conn.execute(
            "INSERT INTO learning_events
               (id,occurred_at_ms,kind,subject_kind,subject_id,event_json)
             VALUES ('learner-event',1,'\"listening_completed\"','\"media\"','media-1','{}')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO review_items
               (id,source_kind,status,created_at_ms,updated_at_ms,item_json)
             VALUES ('learner-review','\"sentence\"','\"active\"',1,1,'{}')",
            [],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO practice_items (id,kind,target_kind,created_at_ms,item_json)
             VALUES ('learner-item','\"cloze\"','\"sentence\"',1,'{}')",
            [],
        )
        .unwrap();
    }
    let before: Vec<(String, u32)> = ["learning_events", "review_items", "practice_items"]
        .iter()
        .map(|table| (table.to_string(), count(&repo, table)))
        .collect();

    let plan = text_adoption(&repo, &material, "sha256:release-learner");
    PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan).unwrap();

    let after: Vec<(String, u32)> = ["learning_events", "review_items", "practice_items"]
        .iter()
        .map(|table| (table.to_string(), count(&repo, table)))
        .collect();
    assert_eq!(before, after, "adoption must not change learner-owned rows");
    // The seeded learner rows keep their exact content.
    let (kind, subject_id): (String, String) = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT kind, subject_id FROM learning_events WHERE id='learner-event'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
    };
    assert_eq!(kind, "\"listening_completed\"");
    assert_eq!(subject_id, "media-1");
}

#[test]
fn error_messages_never_leak_payload_bytes_snapshots_paths_or_sql_parameters() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let (material, revision) = seed_material(&repo, "Hello world.");
    let marker = b"MARKER-SECRET-PAYLOAD-BYTES-987654321".to_vec();
    let mut input = text_prepared(
        &material,
        &revision,
        "sha256:release-marker",
        "edition-marker",
    );
    input.payloads[0].bytes = marker.clone();
    input.payloads[0].digest = sha256_id(&marker);
    input.payloads[0].size_bytes = marker.len() as u64;
    input.installation.resources[0].payload_digest = sha256_id(&marker);
    input.installation.resources[0].payload_size_bytes = marker.len() as u64;

    // A conflicting installation error.
    PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
    let mut conflicting = input.clone();
    conflicting.installation.edition = edition("edition-other");
    let conflict = PackageLifecycleRepository::save_installation(repo.as_ref(), &conflicting)
        .expect_err("conflict");
    let conflict_text = format!("{conflict:?} {conflict}");
    assert!(
        !conflict_text.contains("MARKER"),
        "payload bytes leaked into the error"
    );

    // An internally inconsistent prepared input error.
    let mut inconsistent = input.clone();
    inconsistent.payloads[0].digest = sha256_id(b"different");
    let inconsistent_error =
        PackageLifecycleRepository::save_installation(repo.as_ref(), &inconsistent)
            .expect_err("inconsistent");
    let inconsistent_text = format!("{inconsistent_error:?} {inconsistent_error}");
    assert!(!inconsistent_text.contains("MARKER"));
    assert!(!inconsistent_text.contains("resource-document"));
    assert!(!inconsistent_text.contains("listen.payload"));

    // A corrupt-backing adoption error after tampering the stored body with
    // different bytes (the digest column still describes the marker bytes).
    {
        let conn = repo.connection.lock();
        conn.execute(
            "UPDATE package_resource_payloads SET body=?3
             WHERE material_id=?1 AND release_id=?2",
            params![
                material.id.as_str(),
                "sha256:release-marker",
                b"TAMPERED-OTHER-BYTES".to_vec()
            ],
        )
        .unwrap();
    }
    let plan = text_adoption(&repo, &material, "sha256:release-marker");
    let backing_error = PackageLifecycleRepository::commit_adoption(repo.as_ref(), &plan)
        .expect_err("tampered backing");
    let backing_text = format!("{backing_error:?} {backing_error}");
    assert!(!backing_text.contains("MARKER"));
    assert!(
        !backing_text.contains("package_resource_payloads"),
        "SQL identifiers must not leak"
    );
}

// ---------------------------------------------------------------------
// Application seam across reopen
// ---------------------------------------------------------------------

#[test]
fn package_lifecycle_seam_survives_a_database_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("seam.db");
    let (material_id, installed_at_ms, adopted_at_ms) = {
        let repo = Arc::new(SqliteRepository::open(&path).unwrap());
        let (material, revision) = seed_material(&repo, "Hello world.");
        let input = text_prepared(&material, &revision, "sha256:release-seam", "edition-seam");
        let persisted =
            PackageLifecycleRepository::save_installation(repo.as_ref(), &input).unwrap();
        let services = services(&repo);

        let editions = services
            .package_lifecycle()
            .list_editions(&material.id)
            .unwrap();
        assert_eq!(editions.len(), 1);
        assert!(!editions[0].adopted);
        assert_eq!(editions[0].installed_at_ms, persisted.installed_at_ms);
        assert_ne!(
            editions[0].installed_at_ms, 0,
            "the adapter-stamped time surfaces in the edition view"
        );

        let view = services
            .package_lifecycle()
            .adopt_for_material(&material.id, &persisted.release_id)
            .unwrap();
        assert!(view.adopted);
        let adopted_at_ms = view.adopted_at_ms.expect("adoption time");
        assert!(adopted_at_ms > 0);

        let editions = services
            .package_lifecycle()
            .list_editions(&material.id)
            .unwrap();
        assert_eq!(editions.len(), 1);
        assert!(editions[0].adopted);
        assert_eq!(editions[0].adopted_at_ms, Some(adopted_at_ms));
        (material.id, view.installed_at_ms, adopted_at_ms)
    };

    // Close and reopen the database; list/get/adopt work from the database
    // alone with the adoption evidence, timestamps, and selections intact.
    let reopened = Arc::new(SqliteRepository::open(&path).unwrap());
    let services = services(&reopened);
    let editions = services
        .package_lifecycle()
        .list_editions(&material_id)
        .unwrap();
    assert_eq!(editions.len(), 1);
    assert_eq!(editions[0].installed_at_ms, installed_at_ms);
    assert!(editions[0].adopted);
    assert_eq!(editions[0].adopted_at_ms, Some(adopted_at_ms));
    assert_eq!(editions[0].resources.len(), 1);
    assert_eq!(
        editions[0].resources[0].availability,
        PackageResourceAvailability::Available
    );

    let plan = PackageLifecycleRepository::get_adoption(reopened.as_ref(), &material_id)
        .unwrap()
        .expect("adoption restored");
    assert_eq!(plan.release_id.as_str(), "sha256:release-seam");
    assert_eq!(
        plan.selected_resource_ids,
        vec!["resource-document".to_owned()]
    );
    assert_eq!(
        plan.exclusive_selections,
        vec![ExclusiveSelection {
            family: "exclusive:document_text".into(),
            resource_id: "resource-document".into(),
        }]
    );
    assert_eq!(plan.selected_rendition_ids, Vec::<String>::new());
    assert_eq!(plan.adopted_at_ms, adopted_at_ms);

    // Re-adopting after reopen stays idempotent with the same timestamp.
    let view = services
        .package_lifecycle()
        .adopt_for_material(&material_id, &plan.release_id)
        .unwrap();
    assert!(view.adopted);
    assert_eq!(view.adopted_at_ms, Some(adopted_at_ms));
    assert_eq!(view.installed_at_ms, installed_at_ms);
}
