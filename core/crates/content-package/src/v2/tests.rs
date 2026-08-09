//! Content Package v2 tests: bounded, persistence-free inspection and the
//! pure installation plan, exercised against the committed example carriers
//! and compact synthetic fixtures.
//!
//! Fixtures are built from real payload bytes so every digest is honest; the
//! shared `canonical` serializer produces identity documents that match the
//! inspector's canonical profile.

use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use zip::write::SimpleFileOptions;

use crate::archive::{CatalogEntry, SelectivePackage, StreamedFile};
use crate::inspect::InspectLimits;
use crate::v2::canonical::serialize_canonical;
use crate::v2::inspect::verify_carrier_consistency;
use crate::v2::payload::KnownPayload;
use crate::v2::{
    DELIVERY_SCHEMA_V2, DOCUMENT_TEXT_SCHEMA_V1, DeliveryProfile, PHONE_TIMELINE_SCHEMA_V1,
    PROSODY_ANALYSIS_SCHEMA_V1, RELEASE_SCHEMA_V2, RENDITION_AUDIO_SCHEMA_V1, ResourceDisposition,
    ResourceRole, SENSE_GROUP_ANALYSIS_SCHEMA_V1, SUBTITLE_TEXT_TRACK_SCHEMA_V1,
    TIMED_TEXT_TRACK_SCHEMA_V2, TRANSLATION_SCHEMA_V1, V2Error, V2Inspection,
    WORD_ACOUSTICS_SCHEMA_V1, WORD_TIMELINE_SCHEMA_V1, inspect_v2_path,
    inspect_v2_path_with_limits, installation_plan,
};

const MATERIAL_REVISION: &str = "revision-fixture-v1";
const UNKNOWN_KIND: &str = "future_analysis";
const UNKNOWN_SCHEMA: &str = "listen.payload.future-analysis.v1";

struct TestDirectory(PathBuf);

static NEXT_TEST_DIRECTORY: AtomicU64 = AtomicU64::new(0);

impl TestDirectory {
    fn new() -> Self {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let sequence = NEXT_TEST_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        let process = std::process::id();
        let path = std::env::temp_dir().join(format!(
            "listen-content-package-v2-{process}-{sequence}-{nonce}"
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

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

fn sha256_id(bytes: &[u8]) -> String {
    format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
}

fn canonical_bytes(value: &Value) -> Vec<u8> {
    serialize_canonical(value).unwrap()
}

fn blob_path(digest: &str) -> String {
    format!("blobs/sha256/{}", digest.strip_prefix("sha256:").unwrap())
}

/// A document_text payload built from real bytes with the given per-segment
/// end character positions; returns (payload value, raw bytes, digest).
fn document_payload(text: &str, segment_ends: &[u32]) -> (Value, Vec<u8>, String) {
    let mut segments = Vec::new();
    let mut start = 0_u32;
    for (index, end) in segment_ends.iter().enumerate() {
        segments.push(json!({
            "id": format!("s{}", index + 1),
            "index": index,
            "language": "en",
            "start_char": start,
            "end_char": end,
            "extensions": {},
        }));
        start = *end;
    }
    let payload = json!({
        "language": "en",
        "text": text,
        "segments": segments,
        "extensions": {},
    });
    let bytes = serde_json::to_vec_pretty(&payload).unwrap();
    let digest = sha256_id(&bytes);
    (payload, bytes, digest)
}

fn base_descriptor(
    kind: &str,
    schema: &str,
    language: &str,
    dependencies: &[&str],
    digest: &str,
    size: u64,
) -> Value {
    json!({
        "schema": schema,
        "kind": kind,
        "role": "base",
        "content_language": language,
        "support_languages": [],
        "subject": {"material_revision_id": MATERIAL_REVISION, "rendition_ids": [], "anchor_resource_ids": []},
        "dependencies": dependencies.iter().map(|dep| json!({"resource_id": dep})).collect::<Vec<_>>(),
        "provenance": {"created_at_ms": 1, "tool": {"id": "listen-gen", "version": "0.4.0"}, "input_resource_ids": [], "extensions": {}},
        "quality": {"review_status": "human_reviewed", "warnings": [], "extensions": {}},
        "payload_blob": {"digest": digest, "size_bytes": size},
        "extensions": {},
    })
}

fn assistance_descriptor(
    kind: &str,
    schema: &str,
    support: &[&str],
    dependencies: &[&str],
    digest: &str,
    size: u64,
) -> Value {
    json!({
        "schema": schema,
        "kind": kind,
        "role": "assistance",
        "support_languages": support,
        "subject": {"material_revision_id": MATERIAL_REVISION, "rendition_ids": [], "anchor_resource_ids": []},
        "dependencies": dependencies.iter().map(|dep| json!({"resource_id": dep})).collect::<Vec<_>>(),
        "provenance": {"created_at_ms": 1, "tool": {"id": "listen-gen", "version": "0.4.0"}, "input_resource_ids": [], "extensions": {}},
        "quality": {"review_status": "machine_checked", "warnings": [], "extensions": {}},
        "payload_blob": {"digest": digest, "size_bytes": size},
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

fn release_value(
    support: &[&str],
    entrypoints: Value,
    resources: Vec<Value>,
    renditions: Vec<Value>,
) -> Value {
    json!({
        "schema": RELEASE_SCHEMA_V2,
        "created_at_ms": 1u64,
        "edition": {
            "edition_id": "edition-fixture-v1",
            "title": "Fixture Edition",
            "target_language": "en",
            "support_languages": support,
        },
        "material": {
            "material_id": "material-fixture-v1",
            "material_revision_id": MATERIAL_REVISION,
            "title": "Fixture Material",
        },
        "entrypoints": entrypoints,
        "resources": resources,
        "renditions": renditions,
        "extensions": {},
    })
}

fn entrypoint(resource_id: &str) -> Value {
    json!([{"entrypoint_id": "primary", "resource_id": resource_id}])
}

fn rendition_entrypoint(rendition_id: &str) -> Value {
    json!([{"entrypoint_id": "primary", "rendition_id": rendition_id}])
}

fn carrier(
    release: &Value,
    delivery: Option<&Value>,
    blobs: &[(String, Vec<u8>)],
) -> BTreeMap<String, Vec<u8>> {
    let mut files = BTreeMap::new();
    files.insert("release.json".to_owned(), canonical_bytes(release));
    if let Some(delivery) = delivery {
        files.insert("delivery.json".to_owned(), canonical_bytes(delivery));
    }
    for (path, bytes) in blobs {
        files.insert(path.clone(), bytes.clone());
    }
    files
}

fn delivery_blob(digest: &str, size: u64, hints: &[&str]) -> Value {
    json!({
        "digest": digest,
        "size_bytes": size,
        "hints": hints.iter().map(|hint| json!({"url": hint})).collect::<Vec<_>>(),
    })
}

fn delivery_value(release: &Value, profile: &str, blobs: Vec<Value>) -> Value {
    json!({
        "schema": DELIVERY_SCHEMA_V2,
        "release_id": sha256_id(&canonical_bytes(release)),
        "profile": profile,
        "blobs": blobs,
        "extensions": {},
    })
}

fn write_tree(root: &Path, files: &BTreeMap<String, Vec<u8>>) {
    for (name, bytes) in files {
        let path = root.join(name);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, bytes).unwrap();
    }
}

fn write_zip(root: &Path, files: &BTreeMap<String, Vec<u8>>) -> PathBuf {
    let path = root.join("fixture.listenpkg");
    let mut writer = zip::ZipWriter::new(fs::File::create(&path).unwrap());
    for (name, bytes) in files {
        writer
            .start_file(name, SimpleFileOptions::default())
            .unwrap();
        writer.write_all(bytes).unwrap();
    }
    writer.finish().unwrap();
    path
}

fn inspect_carrier(
    files: &BTreeMap<String, Vec<u8>>,
    as_zip: bool,
) -> Result<V2Inspection, V2Error> {
    inspect_carrier_with_limits(files, as_zip, InspectLimits::default())
}

fn inspect_carrier_with_limits(
    files: &BTreeMap<String, Vec<u8>>,
    as_zip: bool,
    limits: InspectLimits,
) -> Result<V2Inspection, V2Error> {
    let directory = TestDirectory::new();
    if as_zip {
        inspect_v2_path_with_limits(write_zip(directory.path(), files), limits)
    } else {
        write_tree(directory.path(), files);
        inspect_v2_path_with_limits(directory.path(), limits)
    }
}

fn inspect_ok(files: &BTreeMap<String, Vec<u8>>) -> V2Inspection {
    inspect_carrier(files, false).unwrap()
}

fn inspect_err(files: &BTreeMap<String, Vec<u8>>) -> V2Error {
    inspect_carrier(files, false).unwrap_err()
}

fn example_files(name: &str) -> BTreeMap<String, Vec<u8>> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../contracts/content-package/v2/examples")
        .join(name);
    let mut files = BTreeMap::new();
    let mut pending = vec![root.clone()];
    while let Some(directory) = pending.pop() {
        for entry in fs::read_dir(&directory).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                pending.push(path);
            } else {
                let relative = path
                    .strip_prefix(&root)
                    .unwrap()
                    .to_str()
                    .unwrap()
                    .to_owned();
                files.insert(relative, fs::read(&path).unwrap());
            }
        }
    }
    files
}

fn inspect_example(name: &str, as_zip: bool) -> V2Inspection {
    let directory = TestDirectory::new();
    let files = example_files(name);
    if as_zip {
        inspect_v2_path(write_zip(directory.path(), &files)).unwrap()
    } else {
        write_tree(directory.path(), &files);
        inspect_v2_path(directory.path()).unwrap()
    }
}

/// Mutates a resource descriptor in place and restores the identity invariant
/// (resource_id is the canonical JSON digest of the descriptor), keeping any
/// entrypoint that referenced the old id in sync.
fn update_resource_descriptor(release: &mut Value, index: usize, update: impl FnOnce(&mut Value)) {
    let (previous_id, new_id) = {
        let resources = release
            .get_mut("resources")
            .unwrap()
            .as_array_mut()
            .unwrap();
        let entry = &mut resources[index];
        let previous_id = entry["resource_id"].as_str().unwrap().to_owned();
        let descriptor = entry.get_mut("descriptor").unwrap();
        update(descriptor);
        let new_id = sha256_id(&canonical_bytes(descriptor));
        entry["resource_id"] = json!(new_id.clone());
        (previous_id, new_id)
    };
    if let Some(entrypoints) = release.get_mut("entrypoints") {
        for entrypoint in entrypoints.as_array_mut().unwrap() {
            if entrypoint.get("resource_id").and_then(Value::as_str) == Some(previous_id.as_str()) {
                entrypoint["resource_id"] = json!(new_id);
            }
        }
    }
}

/// One embedded base document_text resource.
fn embedded_doc_fixture() -> (Value, Vec<(String, Vec<u8>)>) {
    let text = "Hello world.";
    let (_, bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let descriptor = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &digest,
        bytes.len() as u64,
    );
    let resource = resource_entry(&descriptor, true);
    let id = resource["resource_id"].as_str().unwrap().to_owned();
    let release = release_value(&[], entrypoint(&id), vec![resource], vec![]);
    let blobs = vec![(blob_path(&digest), bytes)];
    (release, blobs)
}

/// One embedded base document_text plus one embedded translation assistance.
fn bilingual_fixture() -> (Value, Vec<(String, Vec<u8>)>) {
    let text = "Pandas eat bamboo. They live in China.";
    let first_end = text.find('.').unwrap() as u32 + 1;
    let total = text.chars().count() as u32;
    let (_, base_bytes, base_digest) = document_payload(text, &[first_end, total]);
    let base_descriptor = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &base_digest,
        base_bytes.len() as u64,
    );
    let base_id = sha256_id(&canonical_bytes(&base_descriptor));
    let segments = json!([
        {"id": "tr-1", "index": 0, "text": "大熊猫吃竹子。", "source_segment_id": "s1", "extensions": {}},
        {"id": "tr-2", "index": 1, "text": "它们住在中国。", "source_segment_id": "s2", "extensions": {}},
    ]);
    let translation = json!({
        "support_language": "zh-Hans",
        "base_resource_id": base_id,
        "segments": segments,
        "extensions": {},
    });
    let translation_bytes = serde_json::to_vec_pretty(&translation).unwrap();
    let translation_digest = sha256_id(&translation_bytes);
    let translation_descriptor = assistance_descriptor(
        "translation",
        TRANSLATION_SCHEMA_V1,
        &["zh-Hans"],
        &[&base_id],
        &translation_digest,
        translation_bytes.len() as u64,
    );
    let release = release_value(
        &["zh-Hans"],
        entrypoint(&base_id),
        vec![
            resource_entry(&base_descriptor, true),
            resource_entry(&translation_descriptor, false),
        ],
        vec![],
    );
    let blobs = vec![
        (blob_path(&base_digest), base_bytes),
        (blob_path(&translation_digest), translation_bytes),
    ];
    (release, blobs)
}

/// A rendition-only release whose audio media blob is embedded with the given
/// declared size; the carrier holds the real `media` bytes.
fn rendition_fixture_with_size(
    media: &[u8],
    declared_size: u64,
) -> (Value, Vec<(String, Vec<u8>)>) {
    let media_digest = sha256_id(media);
    let descriptor = json!({
        "schema": RENDITION_AUDIO_SCHEMA_V1,
        "kind": "audio",
        "media_type": "audio/mpeg",
        "material_revision_id": MATERIAL_REVISION,
        "media_blob": {"digest": media_digest, "size_bytes": declared_size},
        "extensions": {},
    });
    let rendition_id = sha256_id(&canonical_bytes(&descriptor));
    let rendition = json!({"rendition_id": rendition_id, "descriptor": descriptor});
    let release = release_value(
        &[],
        rendition_entrypoint(&rendition_id),
        vec![],
        vec![rendition],
    );
    (release, vec![(blob_path(&media_digest), media.to_vec())])
}

/// Limits that make ordinary payloads tiny so embedded rendition media clearly
/// exceeds `max_file_bytes` while the carrier total stays bounded.
fn streaming_limits() -> InspectLimits {
    InspectLimits {
        max_file_count: 64,
        max_file_bytes: 1024,
        max_manifest_bytes: 64 * 1024,
        max_total_bytes: 1024 * 1024,
    }
}

// ---------------------------------------------------------------------------
// Payload identifiers
// ---------------------------------------------------------------------------

#[test]
fn payload_identifiers_are_v2_listen_payload_while_v1_stays_listen_resource() {
    assert_eq!(DOCUMENT_TEXT_SCHEMA_V1, "listen.payload.document-text.v1");
    assert_eq!(
        TIMED_TEXT_TRACK_SCHEMA_V2,
        "listen.payload.timed-text-track.v2"
    );
    assert_eq!(TRANSLATION_SCHEMA_V1, "listen.payload.translation.v1");
    assert_eq!(
        SUBTITLE_TEXT_TRACK_SCHEMA_V1,
        "listen.payload.subtitle-text-track.v1"
    );
    assert_eq!(WORD_TIMELINE_SCHEMA_V1, "listen.payload.word-timeline.v1");
    assert_eq!(PHONE_TIMELINE_SCHEMA_V1, "listen.payload.phone-timeline.v1");
    assert_eq!(
        SENSE_GROUP_ANALYSIS_SCHEMA_V1,
        "listen.payload.sense-group-analysis.v1"
    );
    assert_eq!(WORD_ACOUSTICS_SCHEMA_V1, "listen.payload.word-acoustics.v1");
    assert_eq!(
        PROSODY_ANALYSIS_SCHEMA_V1,
        "listen.payload.prosody-analysis.v1"
    );
    // The v1 full-envelope identifiers are never reinterpreted.
    assert_eq!(
        crate::model::SUBTITLE_TEXT_TRACK_SCHEMA_V1,
        "listen.resource.subtitle-text-track.v1"
    );
    assert_eq!(
        crate::model::WORD_TIMELINE_SCHEMA_V1,
        "listen.resource.word-timeline.v1"
    );
    assert_eq!(
        crate::model::PHONE_TIMELINE_SCHEMA_V1,
        "listen.resource.phone-timeline.v1"
    );
    assert_eq!(
        crate::model::SENSE_GROUP_ANALYSIS_SCHEMA_V1,
        "listen.resource.sense-group-analysis.v1"
    );
    assert_eq!(
        crate::model::WORD_ACOUSTICS_SCHEMA_V1,
        "listen.resource.word-acoustics.v1"
    );
    assert_eq!(
        crate::model::PROSODY_ANALYSIS_SCHEMA_V1,
        "listen.resource.prosody-analysis.v1"
    );
}

// ---------------------------------------------------------------------------
// Committed examples
// ---------------------------------------------------------------------------

#[test]
fn text_full_example_is_embedded_in_directory_and_zip() {
    for as_zip in [false, true] {
        let inspection = inspect_example("text-full", as_zip);
        assert_eq!(inspection.delivery_profile, DeliveryProfile::Embedded);
        assert_eq!(
            inspection.release_id,
            "sha256:fc30d8eb76ff9b549294becb8e0f95e0daeafd6f114673fd4ec57925389e6122"
        );
        let plan = installation_plan(&inspection);
        assert_eq!(plan.release_id, inspection.release_id);
        assert_eq!(plan.delivery_profile, DeliveryProfile::Embedded);
        assert!(plan.missing_blobs.is_empty());
        assert_eq!(plan.resources.len(), 1);
        assert_eq!(plan.resources[0].kind, "document_text");
        assert_eq!(plan.resources[0].schema, DOCUMENT_TEXT_SCHEMA_V1);
        assert_eq!(
            plan.resources[0].disposition,
            ResourceDisposition::Candidate
        );
        assert!(plan.resources[0].required);
        assert_eq!(plan.resources[0].role, ResourceRole::Base);
        // total_bytes covers release + delivery + every present blob.
        let expected_total: u64 = example_files("text-full")
            .values()
            .map(|bytes| bytes.len() as u64)
            .sum();
        assert_eq!(inspection.total_bytes, expected_total);
    }
}

#[test]
fn detached_media_example_is_hybrid_with_exact_missing_plan_records() {
    for as_zip in [false, true] {
        let inspection = inspect_example("detached-media", as_zip);
        assert_eq!(inspection.delivery_profile, DeliveryProfile::Hybrid);
        assert_eq!(
            inspection.release_id,
            "sha256:e188fd643b969b2c1405428018af962faec18c25252ceddaa468c2d3c049b0b5"
        );
        let plan = installation_plan(&inspection);
        assert_eq!(plan.delivery_profile, DeliveryProfile::Hybrid);
        assert_eq!(plan.resources.len(), 1);
        assert_eq!(plan.resources[0].kind, "timed_text_track");
        assert_eq!(
            plan.resources[0].disposition,
            ResourceDisposition::Candidate
        );
        assert_eq!(plan.renditions.len(), 1);
        assert_eq!(plan.renditions[0].kind, "audio");
        assert_eq!(plan.renditions[0].media_type, "audio/mpeg");
        assert!(!plan.renditions[0].available);
        assert_eq!(
            plan.renditions[0].media_digest,
            "sha256:db868bc797d3b618d49c1855c1d893186288a4c0586e3dedfe1a3ce230fbd390"
        );
        assert_eq!(plan.renditions[0].media_size_bytes, 3291402);
        assert_eq!(plan.missing_blobs.len(), 1);
        assert_eq!(
            plan.missing_blobs[0].digest,
            "sha256:db868bc797d3b618d49c1855c1d893186288a4c0586e3dedfe1a3ce230fbd390"
        );
        assert_eq!(plan.missing_blobs[0].size_bytes, 3291402);
        assert_eq!(
            plan.missing_blobs[0].hints,
            vec!["https://cdn.example.com/audio/museum-tour.mp3"]
        );
    }
}

#[test]
fn hybrid_multilingual_example_reports_missing_word_timeline_in_release_order() {
    for as_zip in [false, true] {
        let inspection = inspect_example("hybrid-multilingual", as_zip);
        assert_eq!(inspection.delivery_profile, DeliveryProfile::Hybrid);
        assert_eq!(
            inspection.release_id,
            "sha256:8a8e6d71c667273ff537a95aea838a25b00621af0f7dab360a98a341ea8a835c"
        );
        let plan = installation_plan(&inspection);
        assert_eq!(plan.resources.len(), 3);
        let dispositions: Vec<ResourceDisposition> = plan
            .resources
            .iter()
            .map(|resource| resource.disposition)
            .collect();
        assert_eq!(
            dispositions,
            vec![
                ResourceDisposition::Candidate,
                ResourceDisposition::Candidate,
                ResourceDisposition::Missing,
            ]
        );
        assert_eq!(plan.resources[0].kind, "document_text");
        assert_eq!(plan.resources[1].kind, "translation");
        assert_eq!(plan.resources[1].role, ResourceRole::Assistance);
        assert_eq!(plan.resources[2].kind, "word_timeline");
        assert_eq!(plan.missing_blobs.len(), 1);
        assert_eq!(
            plan.missing_blobs[0].digest,
            "sha256:c8ff7cde6f7617c7cb9bf18aec92845fce519ab74018887c7fc9ab8ab5033145"
        );
        assert_eq!(plan.missing_blobs[0].size_bytes, 8124);
        assert_eq!(
            plan.missing_blobs[0].hints,
            vec!["https://cdn.example.com/blobs/word-timeline.json"]
        );
    }
}

// ---------------------------------------------------------------------------
// Release identity and delivery
// ---------------------------------------------------------------------------

#[test]
fn delivery_carrier_changes_never_change_the_release_id() {
    let directory = TestDirectory::new();
    write_tree(directory.path(), &example_files("text-full"));
    let first = inspect_v2_path(directory.path()).unwrap();

    // Rewrite delivery.json with an extra acquisition hint on the embedded
    // blob; release identity and the plan release id must be unchanged.
    let release: Value =
        serde_json::from_slice(&fs::read(directory.path().join("release.json")).unwrap()).unwrap();
    let delivery = delivery_value(
        &release,
        "embedded",
        vec![delivery_blob(
            "sha256:49128790cdb73915d8eef1a4c0cc9bb953c2d875e2e366bac8fd2276920f7c6f",
            438,
            &["https://cdn.example.com/blobs/document-text.json"],
        )],
    );
    fs::write(
        directory.path().join("delivery.json"),
        canonical_bytes(&delivery),
    )
    .unwrap();
    let second = inspect_v2_path(directory.path()).unwrap();

    assert_eq!(first.release_id, second.release_id);
    assert_eq!(
        second.release_id,
        "sha256:fc30d8eb76ff9b549294becb8e0f95e0daeafd6f114673fd4ec57925389e6122"
    );
    let plan = installation_plan(&second);
    assert!(plan.missing_blobs.is_empty());
    assert_eq!(
        second.blobs["sha256:49128790cdb73915d8eef1a4c0cc9bb953c2d875e2e366bac8fd2276920f7c6f"]
            .hints,
        vec!["https://cdn.example.com/blobs/document-text.json"]
    );
}

#[test]
fn rejects_delivery_with_wrong_identity_or_profile_or_hints() {
    let (release, blobs) = embedded_doc_fixture();
    let digest = blobs[0].0.strip_prefix("blobs/sha256/").unwrap().to_owned();
    let digest = format!("sha256:{digest}");
    let size = blobs[0].1.len() as u64;

    let mut wrong_id = delivery_value(
        &release,
        "embedded",
        vec![delivery_blob(&digest, size, &[])],
    );
    wrong_id["release_id"] = json!(format!("sha256:{}", "ef".repeat(32)));
    let error = inspect_err(&carrier(&release, Some(&wrong_id), &blobs));
    assert!(error.to_string().contains("release_id does not match"));

    let wrong_profile = delivery_value(
        &release,
        "referenced",
        vec![delivery_blob(&digest, size, &[])],
    );
    let error = inspect_err(&carrier(&release, Some(&wrong_profile), &blobs));
    assert!(
        error
            .to_string()
            .contains("delivery profile does not match")
    );

    let wrong_size = delivery_value(
        &release,
        "embedded",
        vec![delivery_blob(&digest, size + 1, &[])],
    );
    let error = inspect_err(&carrier(&release, Some(&wrong_size), &blobs));
    assert!(error.to_string().contains("delivery blob size differs"));

    let unreferenced = delivery_value(
        &release,
        "embedded",
        vec![delivery_blob(
            &format!("sha256:{}", "ab".repeat(32)),
            1,
            &[],
        )],
    );
    let error = inspect_err(&carrier(&release, Some(&unreferenced), &blobs));
    assert!(
        error
            .to_string()
            .contains("delivery blob digest is not referenced")
    );

    for (hint, expected) in [
        ("http://cdn.example.com/x", "must use https"),
        (
            "https://user:pass@cdn.example.com/x",
            "must not contain credentials",
        ),
        ("not a url", "not a valid URL"),
        (
            "https://cdn.example.com/x#frag",
            "must not contain a fragment",
        ),
    ] {
        let delivery = delivery_value(
            &release,
            "embedded",
            vec![delivery_blob(&digest, size, &[hint])],
        );
        let error = inspect_err(&carrier(&release, Some(&delivery), &blobs));
        assert!(error.to_string().contains(expected), "{hint}");
    }
}

#[test]
fn rejects_noncanonical_release_and_delivery_documents() {
    let directory = TestDirectory::new();
    for (bytes, label) in [
        (b"\xEF\xBB\xBF{\"a\":1}".as_slice(), "BOM"),
        (b"{\n  \"a\": 1\n}\n", "whitespace"),
        (b"{\"b\":1,\"a\":2}", "unsorted keys"),
        (b"{\"created_at_ms\":1.5}", "non-integer number"),
    ] {
        fs::write(directory.path().join("release.json"), bytes).unwrap();
        let error = inspect_v2_path(directory.path()).unwrap_err();
        assert!(
            error.to_string().contains("release.json is not canonical"),
            "{label}: {error}"
        );
        fs::remove_file(directory.path().join("release.json")).unwrap();
    }

    let (release, blobs) = embedded_doc_fixture();
    let delivery = delivery_value(
        &release,
        "embedded",
        vec![delivery_blob(
            &format!("sha256:{}", hex::encode(Sha256::digest(&blobs[0].1))),
            blobs[0].1.len() as u64,
            &[],
        )],
    );
    let mut files = carrier(&release, None, &blobs);
    files.insert(
        "delivery.json".to_owned(),
        serde_json::to_vec_pretty(&delivery).unwrap(),
    );
    let error = inspect_err(&files);
    assert!(error.to_string().contains("delivery.json is not canonical"));
}

// ---------------------------------------------------------------------------
// Archive safety
// ---------------------------------------------------------------------------

#[test]
fn rejects_zip_path_traversal_and_symlink_entries() {
    // The zip 5.1 writer itself refuses duplicate entry names, so the
    // inspector's defensive DuplicatePath variant is not reachable through
    // this public packer API; traversal and symlink carriers are.
    let directory = TestDirectory::new();
    let path = directory.path().join("traversal.listenpkg");
    let mut writer = zip::ZipWriter::new(fs::File::create(&path).unwrap());
    writer
        .start_file("../release.json", SimpleFileOptions::default())
        .unwrap();
    writer.write_all(b"{}").unwrap();
    writer.finish().unwrap();
    assert!(matches!(
        inspect_v2_path(&path).unwrap_err(),
        V2Error::UnsafePath(_)
    ));

    let path = directory.path().join("symlink.listenpkg");
    let mut writer = zip::ZipWriter::new(fs::File::create(&path).unwrap());
    writer
        .add_symlink(
            "release.json",
            "elsewhere.json",
            SimpleFileOptions::default(),
        )
        .unwrap();
    writer.finish().unwrap();
    assert!(matches!(
        inspect_v2_path(&path).unwrap_err(),
        V2Error::Symlink(_)
    ));
}

#[cfg(unix)]
#[test]
fn rejects_directory_symlink() {
    use std::os::unix::fs::symlink;

    let directory = TestDirectory::new();
    fs::write(directory.path().join("elsewhere.json"), b"{}").unwrap();
    symlink(
        directory.path().join("elsewhere.json"),
        directory.path().join("release.json"),
    )
    .unwrap();
    assert!(matches!(
        inspect_v2_path(directory.path()).unwrap_err(),
        V2Error::Symlink(_)
    ));
}

// ---------------------------------------------------------------------------
// Blob verification
// ---------------------------------------------------------------------------

#[test]
fn rejects_digest_size_zero_and_conflicting_size_declarations() {
    // Content no longer matches the declared digest (same length).
    let (release, blobs) = embedded_doc_fixture();
    let mut files = carrier(&release, None, &blobs);
    let path = blobs[0].0.clone();
    let mut tampered = files[&path].clone();
    *tampered.last_mut().unwrap() ^= 0x01;
    files.insert(path.clone(), tampered);
    let error = inspect_err(&files);
    assert!(
        error
            .to_string()
            .contains("digest does not match its content")
    );

    // Actual file size differs from the declared size.
    let (release, blobs) = embedded_doc_fixture();
    let mut files = carrier(&release, None, &blobs);
    let mut grown = files[&blobs[0].0].clone();
    grown.push(b' ');
    files.insert(blobs[0].0.clone(), grown);
    let error = inspect_err(&files);
    assert!(error.to_string().contains("size does not match"));

    // size_bytes = 0 is rejected.
    let (mut release, blobs) = embedded_doc_fixture();
    update_resource_descriptor(&mut release, 0, |descriptor| {
        descriptor["payload_blob"]["size_bytes"] = json!(0);
    });
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(error.to_string().contains("size_bytes must be >= 1"));

    // The same digest declared with conflicting sizes is rejected.
    let text = "Shared payload bytes.";
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let first = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &digest,
        payload_bytes.len() as u64,
    );
    let first_id = sha256_id(&canonical_bytes(&first));
    let second = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "fr",
        &[],
        &digest,
        payload_bytes.len() as u64 + 1,
    );
    let release = release_value(
        &[],
        entrypoint(&first_id),
        vec![resource_entry(&first, true), resource_entry(&second, false)],
        vec![],
    );
    let error = inspect_err(&carrier(
        &release,
        None,
        &[(blob_path(&digest), payload_bytes)],
    ));
    assert!(error.to_string().contains("conflicting sizes"));
}

#[test]
fn rejects_undeclared_and_unreferenced_carrier_files() {
    let (release, blobs) = embedded_doc_fixture();
    let mut files = carrier(&release, None, &blobs);
    files.insert("notes.txt".to_owned(), b"undeclared".to_vec());
    let error = inspect_err(&files);
    assert!(error.to_string().contains("not declared by the release"));

    let (release, blobs) = embedded_doc_fixture();
    let mut files = carrier(&release, None, &blobs);
    files.insert(
        blob_path(&format!("sha256:{}", "cd".repeat(32))),
        b"x".to_vec(),
    );
    let error = inspect_err(&files);
    assert!(
        error
            .to_string()
            .contains("blob file is not referenced by the release")
    );
}

// ---------------------------------------------------------------------------
// Dependency closure, cycles, and Base/Assistance rules
// ---------------------------------------------------------------------------

#[test]
fn rejects_dependencies_outside_the_release_and_duplicate_dependency_ids() {
    let text = "Hello world.";
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let unknown_id = format!("sha256:{}", "ab".repeat(32));
    let descriptor = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[&unknown_id],
        &digest,
        payload_bytes.len() as u64,
    );
    let id = sha256_id(&canonical_bytes(&descriptor));
    let release = release_value(
        &[],
        entrypoint(&id),
        vec![resource_entry(&descriptor, true)],
        vec![],
    );
    let error = inspect_err(&carrier(
        &release,
        None,
        &[(blob_path(&digest), payload_bytes)],
    ));
    assert!(
        error
            .to_string()
            .contains("dependency is not in the release")
    );

    // A second declared resource lets a duplicate dependency id be expressed.
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let target = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &digest,
        payload_bytes.len() as u64,
    );
    let target_id = sha256_id(&canonical_bytes(&target));
    let owner = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[&target_id, &target_id],
        &digest,
        payload_bytes.len() as u64,
    );
    let owner_id = sha256_id(&canonical_bytes(&owner));
    let release = release_value(
        &[],
        entrypoint(&owner_id),
        vec![resource_entry(&owner, true), resource_entry(&target, false)],
        vec![],
    );
    let error = inspect_err(&carrier(
        &release,
        None,
        &[(blob_path(&digest), payload_bytes)],
    ));
    assert!(error.to_string().contains("dependency ids must be unique"));
}

#[test]
fn rejects_dependency_cycles_and_base_reaching_assistance() {
    // A real cycle cannot be serialized (each edge is a digest inside an
    // identity-bearing descriptor), so the bounded traversal is exercised as
    // the same crate-internal seam the v1 tests use.
    use crate::v2::inspect::dependency_graph_has_cycle;

    let a = format!("sha256:{}", "aa".repeat(32));
    let b = format!("sha256:{}", "bb".repeat(32));
    assert!(dependency_graph_has_cycle(&HashMap::from([
        (a.clone(), vec![b.clone()]),
        (b.clone(), vec![a.clone()]),
    ])));
    assert!(dependency_graph_has_cycle(&HashMap::from([(
        a.clone(),
        vec![a.clone()]
    )])));
    assert!(!dependency_graph_has_cycle(&HashMap::from([
        (a.clone(), vec![b.clone()]),
        (b.clone(), vec![]),
    ])));

    // A Base Resource must not depend on an Assistance Resource, directly or
    // through a chain of Bases.
    let text = "Hello world.";
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let assistance = assistance_descriptor(
        "translation",
        TRANSLATION_SCHEMA_V1,
        &["zh-Hans"],
        &[],
        &digest,
        payload_bytes.len() as u64,
    );
    let assistance_id = sha256_id(&canonical_bytes(&assistance));
    let middle = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[&assistance_id],
        &digest,
        payload_bytes.len() as u64,
    );
    let middle_id = sha256_id(&canonical_bytes(&middle));
    let root = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[&middle_id],
        &digest,
        payload_bytes.len() as u64,
    );
    let root_id = sha256_id(&canonical_bytes(&root));
    let release = release_value(
        &["zh-Hans"],
        entrypoint(&root_id),
        vec![
            resource_entry(&root, true),
            resource_entry(&middle, false),
            resource_entry(&assistance, false),
        ],
        vec![],
    );
    let error = inspect_err(&carrier(
        &release,
        None,
        &[(blob_path(&digest), payload_bytes)],
    ));
    assert!(
        error
            .to_string()
            .contains("base resource cannot depend on an assistance resource"),
        "{error}"
    );
}

// ---------------------------------------------------------------------------
// Typed compatibility: required unknown, optional opaque
// ---------------------------------------------------------------------------

#[test]
fn optional_unknown_stays_opaque_and_required_unknown_is_incompatible() {
    let text = "Opaque payload.";
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let unknown = base_descriptor(
        UNKNOWN_KIND,
        UNKNOWN_SCHEMA,
        "en",
        &[],
        &digest,
        payload_bytes.len() as u64,
    );
    let optional_id = sha256_id(&canonical_bytes(&unknown));
    let release = release_value(
        &[],
        entrypoint(&optional_id),
        vec![resource_entry(&unknown, false)],
        vec![],
    );
    let inspection = inspect_ok(&carrier(
        &release,
        None,
        &[(blob_path(&digest), payload_bytes.clone())],
    ));
    assert_eq!(inspection.opaque_resources.len(), 1);
    assert!(
        inspection
            .warnings
            .iter()
            .any(|warning| warning.contains("opaque"))
    );
    let plan = installation_plan(&inspection);
    assert_eq!(plan.resources[0].disposition, ResourceDisposition::Opaque);
    assert!(!plan.resources[0].required);

    // Required unknown resources are a typed incompatibility.
    let release = release_value(
        &[],
        entrypoint(&optional_id),
        vec![resource_entry(&unknown, true)],
        vec![],
    );
    let error = inspect_err(&carrier(
        &release,
        None,
        &[(blob_path(&digest), payload_bytes)],
    ));
    assert!(matches!(
        error,
        V2Error::Incompatible { resource_id, kind, schema }
            if kind == UNKNOWN_KIND
                && schema == UNKNOWN_SCHEMA
                && resource_id == optional_id
    ));
}

#[test]
fn required_resource_reaching_unknown_optional_is_incompatible() {
    let text = "Required base.";
    let (_, base_bytes, base_digest) = document_payload(text, &[text.chars().count() as u32]);
    let (_, unknown_bytes, unknown_digest) = document_payload(text, &[text.chars().count() as u32]);
    let unknown = base_descriptor(
        UNKNOWN_KIND,
        UNKNOWN_SCHEMA,
        "en",
        &[],
        &unknown_digest,
        unknown_bytes.len() as u64,
    );
    let unknown_id = sha256_id(&canonical_bytes(&unknown));
    let root = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[&unknown_id],
        &base_digest,
        base_bytes.len() as u64,
    );
    let root_id = sha256_id(&canonical_bytes(&root));
    let release = release_value(
        &[],
        entrypoint(&root_id),
        vec![resource_entry(&root, true), resource_entry(&unknown, false)],
        vec![],
    );
    let error = inspect_err(&carrier(
        &release,
        None,
        &[
            (blob_path(&base_digest), base_bytes),
            (blob_path(&unknown_digest), unknown_bytes),
        ],
    ));
    assert!(matches!(
        error,
        V2Error::Incompatible { resource_id, kind, .. }
            if kind == UNKNOWN_KIND && resource_id == unknown_id
    ));
}

// ---------------------------------------------------------------------------
// Languages and roles
// ---------------------------------------------------------------------------

#[test]
fn enforces_explicit_language_tags_without_defaults_or_underscores() {
    let (mut release, blobs) = bilingual_fixture();
    release["edition"]["target_language"] = json!("");
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(error.to_string().contains("language tag must not be empty"));

    let (mut release, blobs) = bilingual_fixture();
    release["edition"]["target_language"] = json!("zh_Hans");
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(
        error
            .to_string()
            .contains("language tag must use hyphens only")
    );

    let (mut release, blobs) = bilingual_fixture();
    release["edition"]["support_languages"] = json!(["zh-Hans", "zh-Hans"]);
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(
        error
            .to_string()
            .contains("edition support_languages must be unique")
    );
}

#[test]
fn rejects_release_without_edition_support_languages() {
    // release.schema.json requires edition support_languages; the Rust model
    // must reject its absence exactly like the schema.
    let (mut release, blobs) = embedded_doc_fixture();
    release["edition"]
        .as_object_mut()
        .unwrap()
        .remove("support_languages");
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(
        error
            .to_string()
            .contains("missing field `support_languages`"),
        "{error}"
    );
}

#[test]
fn enforces_base_and_assistance_language_rules() {
    // Base requires content_language.
    let (mut release, blobs) = bilingual_fixture();
    update_resource_descriptor(&mut release, 0, |descriptor| {
        descriptor
            .as_object_mut()
            .unwrap()
            .remove("content_language");
    });
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(
        error
            .to_string()
            .contains("base resource requires content_language")
    );

    // Base must not declare support_languages.
    let (mut release, blobs) = bilingual_fixture();
    update_resource_descriptor(&mut release, 0, |descriptor| {
        descriptor["support_languages"] = json!(["zh-Hans"]);
    });
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(
        error
            .to_string()
            .contains("base resource must not declare support_languages")
    );

    // Assistance must omit content_language entirely, including null.
    for value in [json!(null), json!("en")] {
        let (mut release, blobs) = bilingual_fixture();
        update_resource_descriptor(&mut release, 1, |descriptor| {
            descriptor["content_language"] = value.clone();
        });
        let error = inspect_err(&carrier(&release, None, &blobs));
        assert!(
            error
                .to_string()
                .contains("assistance resource must omit content_language entirely"),
            "{value}"
        );
    }

    // Assistance requires at least one support_language.
    let (mut release, blobs) = bilingual_fixture();
    update_resource_descriptor(&mut release, 1, |descriptor| {
        descriptor["support_languages"] = json!([]);
    });
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(error.to_string().contains("at least one support_language"));

    // Assistance support_languages must belong to the edition.
    let (mut release, blobs) = bilingual_fixture();
    update_resource_descriptor(&mut release, 1, |descriptor| {
        descriptor["support_languages"] = json!(["fr"]);
    });
    let error = inspect_err(&carrier(&release, None, &blobs));
    assert!(
        error
            .to_string()
            .contains("must belong to the edition support_languages")
    );
}

// ---------------------------------------------------------------------------
// Strict provenance and quality presence
// ---------------------------------------------------------------------------

#[test]
fn rejects_descriptors_omitting_required_provenance_and_quality_fields() {
    // resource.schema.json requires provenance input_resource_ids/extensions
    // and quality warnings/extensions; the Rust model must reject each
    // omission exactly like the schema.
    for (path, missing) in [
        (
            vec!["provenance", "input_resource_ids"],
            "input_resource_ids",
        ),
        (vec!["provenance", "extensions"], "provenance extensions"),
        (vec!["quality", "warnings"], "quality warnings"),
        (vec!["quality", "extensions"], "quality extensions"),
    ] {
        let (mut release, blobs) = embedded_doc_fixture();
        update_resource_descriptor(&mut release, 0, |descriptor| {
            let mut current = descriptor;
            for segment in &path[..path.len() - 1] {
                current = current.get_mut(segment).unwrap();
            }
            current
                .as_object_mut()
                .unwrap()
                .remove(path.last().copied().unwrap());
        });
        let error = inspect_err(&carrier(&release, None, &blobs));
        assert!(
            error.to_string().contains("missing field"),
            "{missing}: {error}"
        );
    }
}

// ---------------------------------------------------------------------------
// Renditions and empty resources
// ---------------------------------------------------------------------------

#[test]
fn rendition_only_release_with_empty_resources_is_valid() {
    let audio = b"\x00\x01\x02\x03";
    let audio_digest = sha256_id(audio);
    let descriptor = json!({
        "schema": RENDITION_AUDIO_SCHEMA_V1,
        "kind": "audio",
        "media_type": "audio/mpeg",
        "material_revision_id": MATERIAL_REVISION,
        "media_blob": {"digest": audio_digest, "size_bytes": audio.len() as u64},
        "extensions": {},
    });
    let rendition_id = sha256_id(&canonical_bytes(&descriptor));
    let rendition = json!({"rendition_id": rendition_id, "descriptor": descriptor});
    let release = release_value(
        &[],
        rendition_entrypoint(&rendition_id),
        vec![],
        vec![rendition],
    );
    let files = carrier(
        &release,
        None,
        &[(blob_path(&audio_digest), audio.to_vec())],
    );
    for as_zip in [false, true] {
        let inspection = inspect_carrier(&files, as_zip).unwrap();
        assert!(inspection.resources.is_empty());
        assert_eq!(inspection.renditions.len(), 1);
        let plan = installation_plan(&inspection);
        assert!(plan.resources.is_empty());
        assert_eq!(plan.renditions.len(), 1);
        assert!(plan.renditions[0].available);
        assert_eq!(plan.renditions[0].media_type, "audio/mpeg");
        assert_eq!(plan.renditions[0].kind, "audio");
    }
}

#[test]
fn rejects_missing_base_or_rendition_entrypoint() {
    let text = "Hello world.";
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let assistance = assistance_descriptor(
        "translation",
        TRANSLATION_SCHEMA_V1,
        &["zh-Hans"],
        &[],
        &digest,
        payload_bytes.len() as u64,
    );
    let assistance_id = sha256_id(&canonical_bytes(&assistance));
    let release = release_value(
        &["zh-Hans"],
        entrypoint(&assistance_id),
        vec![resource_entry(&assistance, false)],
        vec![],
    );
    let error = inspect_err(&carrier(
        &release,
        None,
        &[(blob_path(&digest), payload_bytes)],
    ));
    assert!(
        error
            .to_string()
            .contains("no entrypoint references a declared Base Resource or Media Rendition"),
        "{error}"
    );
}

// ---------------------------------------------------------------------------
// Installation plan and limits
// ---------------------------------------------------------------------------

#[test]
fn plan_preserves_release_order_for_candidate_opaque_and_missing() {
    let text = "Ordered payload.";
    let (_, first_bytes, first_digest) = document_payload(text, &[text.chars().count() as u32]);
    let missing_text = "Missing payload.";
    let (_, third_bytes, third_digest) =
        document_payload(missing_text, &[missing_text.chars().count() as u32]);
    let first = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &first_digest,
        first_bytes.len() as u64,
    );
    let first_id = sha256_id(&canonical_bytes(&first));
    let opaque = base_descriptor(
        UNKNOWN_KIND,
        UNKNOWN_SCHEMA,
        "en",
        &[],
        &first_digest,
        first_bytes.len() as u64,
    );
    let opaque_id = sha256_id(&canonical_bytes(&opaque));
    let missing = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &third_digest,
        third_bytes.len() as u64,
    );
    let missing_id = sha256_id(&canonical_bytes(&missing));
    let release = release_value(
        &[],
        entrypoint(&first_id),
        vec![
            resource_entry(&first, true),
            resource_entry(&opaque, false),
            resource_entry(&missing, false),
        ],
        vec![],
    );
    // The third payload is deliberately not embedded.
    let inspection = inspect_ok(&carrier(
        &release,
        None,
        &[(blob_path(&first_digest), first_bytes)],
    ));
    let plan = installation_plan(&inspection);
    let ids: Vec<&str> = plan
        .resources
        .iter()
        .map(|resource| resource.resource_id.as_str())
        .collect();
    assert_eq!(
        ids,
        vec![first_id.as_str(), opaque_id.as_str(), missing_id.as_str()]
    );
    let dispositions: Vec<ResourceDisposition> = plan
        .resources
        .iter()
        .map(|resource| resource.disposition)
        .collect();
    assert_eq!(
        dispositions,
        vec![
            ResourceDisposition::Candidate,
            ResourceDisposition::Opaque,
            ResourceDisposition::Missing,
        ]
    );
    assert_eq!(plan.missing_blobs.len(), 1);
    assert_eq!(plan.missing_blobs[0].digest, third_digest);
}

#[test]
fn enforces_bounded_inspection_limits() {
    // File count.
    let (release, blobs) = embedded_doc_fixture();
    let files = carrier(&release, None, &blobs);
    let directory = TestDirectory::new();
    write_tree(directory.path(), &files);
    let limits = InspectLimits {
        max_file_count: 1,
        ..InspectLimits::default()
    };
    assert!(matches!(
        inspect_v2_path_with_limits(directory.path(), limits).unwrap_err(),
        V2Error::Limit(_)
    ));

    // Total decompressed bytes.
    let limits = InspectLimits {
        max_total_bytes: 10,
        ..InspectLimits::default()
    };
    assert!(matches!(
        inspect_v2_path_with_limits(directory.path(), limits).unwrap_err(),
        V2Error::Limit(_)
    ));

    // Delivery hint inventory.
    let (release, blobs) = embedded_doc_fixture();
    let digest = format!("sha256:{}", hex::encode(Sha256::digest(&blobs[0].1)));
    let size = blobs[0].1.len() as u64;
    let delivery = delivery_value(
        &release,
        "embedded",
        vec![delivery_blob(
            &digest,
            size,
            &[
                "https://a.example/x",
                "https://b.example/x",
                "https://c.example/x",
                "https://d.example/x",
            ],
        )],
    );
    let files = carrier(&release, Some(&delivery), &blobs);
    let directory = TestDirectory::new();
    write_tree(directory.path(), &files);
    let limits = InspectLimits {
        max_file_count: 3,
        ..InspectLimits::default()
    };
    assert!(matches!(
        inspect_v2_path_with_limits(directory.path(), limits).unwrap_err(),
        V2Error::Limit(_)
    ));

    // Dependency graph edge budget: two resources with two dependencies each
    // exceed a two-edge budget before descriptor validation runs.
    let text = "Hello world.";
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let left_id = format!("sha256:{}", "aa".repeat(32));
    let right_id = format!("sha256:{}", "bb".repeat(32));
    let first = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[&left_id, &right_id],
        &digest,
        payload_bytes.len() as u64,
    );
    let first_id = sha256_id(&canonical_bytes(&first));
    let second = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[&left_id, &right_id],
        &digest,
        payload_bytes.len() as u64,
    );
    let release = release_value(
        &[],
        entrypoint(&first_id),
        vec![resource_entry(&first, true), resource_entry(&second, false)],
        vec![],
    );
    // Payloads are deliberately absent so the carrier has a single file.
    let files = carrier(&release, None, &[]);
    let directory = TestDirectory::new();
    write_tree(directory.path(), &files);
    let limits = InspectLimits {
        max_file_count: 2,
        ..InspectLimits::default()
    };
    assert!(matches!(
        inspect_v2_path_with_limits(directory.path(), limits).unwrap_err(),
        V2Error::Limit(_)
    ));
}

#[test]
fn enforces_combined_resource_and_rendition_inventory_limit() {
    // One resource plus one rendition passes each per-category bound but
    // exceeds a single-entry combined budget. Blobs are deliberately absent
    // so the carrier holds only release.json and read_package stays within
    // the file-count limit; the combined inventory check is what rejects.
    let text = "Hello world.";
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    let descriptor = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &digest,
        payload_bytes.len() as u64,
    );
    let resource_id = sha256_id(&canonical_bytes(&descriptor));
    let audio = b"\x00\x01\x02\x03";
    let audio_digest = sha256_id(audio);
    let rendition_descriptor = json!({
        "schema": RENDITION_AUDIO_SCHEMA_V1,
        "kind": "audio",
        "media_type": "audio/mpeg",
        "material_revision_id": MATERIAL_REVISION,
        "media_blob": {"digest": audio_digest, "size_bytes": audio.len() as u64},
        "extensions": {},
    });
    let rendition_id = sha256_id(&canonical_bytes(&rendition_descriptor));
    let release = release_value(
        &[],
        entrypoint(&resource_id),
        vec![resource_entry(&descriptor, true)],
        vec![json!({"rendition_id": rendition_id, "descriptor": rendition_descriptor})],
    );
    let files = carrier(&release, None, &[]);
    let directory = TestDirectory::new();
    write_tree(directory.path(), &files);
    let limits = InspectLimits {
        max_file_count: 1,
        ..InspectLimits::default()
    };
    let error = inspect_v2_path_with_limits(directory.path(), limits).unwrap_err();
    assert!(
        matches!(error, V2Error::Limit(_)),
        "expected a limit error, got {error}"
    );
}

// ---------------------------------------------------------------------------
// Payload extensions alignment
// ---------------------------------------------------------------------------

#[test]
fn payload_segment_extensions_are_accepted_and_preserved() {
    let text = "Hello world.";
    let (_, payload_bytes, digest) = document_payload(text, &[text.chars().count() as u32]);
    // The schema promises segment-level extensions; the Rust model must keep
    // them even when inspection reserializes the decoded payload.
    let descriptor = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &digest,
        payload_bytes.len() as u64,
    );
    let id = sha256_id(&canonical_bytes(&descriptor));
    let release = release_value(
        &[],
        entrypoint(&id),
        vec![resource_entry(&descriptor, true)],
        vec![],
    );
    let inspection = inspect_ok(&carrier(
        &release,
        None,
        &[(blob_path(&digest), payload_bytes)],
    ));
    match &inspection.resources[0].payload {
        KnownPayload::DocumentText(document) => {
            assert!(document.segments[0].extensions.is_empty());
        }
        other => panic!("expected document_text payload, got {other:?}"),
    }
}

#[test]
fn v2_native_payload_omitted_extensions_are_empty_objects() {
    // The v2-native payloads omit extensions entirely; the Rust models must
    // default to an empty object map and serialize it back as `{}`.
    let text = "Hello world.";
    let payload = json!({
        "language": "en",
        "text": text,
        "segments": [
            {"id": "s1", "index": 0, "language": "en", "start_char": 0, "end_char": text.chars().count() as u32},
        ],
    });
    let bytes = serde_json::to_vec_pretty(&payload).unwrap();
    let digest = sha256_id(&bytes);
    let descriptor = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &digest,
        bytes.len() as u64,
    );
    let id = sha256_id(&canonical_bytes(&descriptor));
    let release = release_value(
        &[],
        entrypoint(&id),
        vec![resource_entry(&descriptor, true)],
        vec![],
    );
    let inspection = inspect_ok(&carrier(&release, None, &[(blob_path(&digest), bytes)]));
    match &inspection.resources[0].payload {
        KnownPayload::DocumentText(document) => {
            assert!(document.extensions.is_empty());
            assert!(document.segments[0].extensions.is_empty());
            let serialized = serde_json::to_value(document).unwrap();
            assert_eq!(serialized["extensions"], json!({}));
            assert_eq!(serialized["segments"][0]["extensions"], json!({}));
        }
        other => panic!("expected document_text payload, got {other:?}"),
    }
}

#[test]
fn v2_native_payload_explicit_null_extensions_are_rejected() {
    use crate::v2::payload::{
        DocumentText, DocumentTextSegment, TimedTextSegment, TimedTextTrack, Translation,
        TranslationSegment,
    };

    // Top-level null extensions are rejected for every v2-native payload.
    assert!(
        serde_json::from_value::<DocumentText>(json!({
            "language": "en",
            "text": "Hello world.",
            "segments": [],
            "extensions": null,
        }))
        .is_err()
    );
    assert!(
        serde_json::from_value::<TimedTextTrack>(json!({
            "language": "en",
            "segments": [],
            "extensions": null,
        }))
        .is_err()
    );
    assert!(
        serde_json::from_value::<Translation>(json!({
            "support_language": "zh-Hans",
            "base_resource_id": "sha256:abc",
            "segments": [],
            "extensions": null,
        }))
        .is_err()
    );

    // Segment-level null extensions are rejected for every v2-native shape.
    assert!(
        serde_json::from_value::<DocumentTextSegment>(json!({
            "id": "s1", "index": 0, "language": "en", "start_char": 0, "end_char": 12,
            "extensions": null,
        }))
        .is_err()
    );
    assert!(
        serde_json::from_value::<TimedTextSegment>(json!({
            "id": "t1", "index": 0, "language": "en", "start_ms": 0, "end_ms": 1000,
            "text": "Hi.", "extensions": null,
        }))
        .is_err()
    );
    assert!(
        serde_json::from_value::<TranslationSegment>(json!({
            "id": "tr-1", "index": 0, "text": "你好。", "source_segment_id": "s1",
            "extensions": null,
        }))
        .is_err()
    );
}

#[test]
fn payload_schema_extensions_objects_align_with_the_rust_models() {
    let payload_dir =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../contracts/content-package/v2/payload");
    // The three v2-native payloads carry segment-level extensions in both the
    // Rust structs and the JSON schemas.
    for (file, def) in [
        ("document-text.v1.schema.json", "segment"),
        ("timed-text-track.v2.schema.json", "segment"),
        ("translation.v1.schema.json", "segment"),
    ] {
        let document: Value =
            serde_json::from_slice(&fs::read(payload_dir.join(file)).unwrap()).unwrap();
        assert_eq!(
            document["$defs"][def]["properties"]["extensions"],
            json!({"type": "object"}),
            "{file}"
        );
    }
    // The six v1-reused payload shapes are strict: no extensions anywhere,
    // matching the v1 models they reuse verbatim.
    for file in [
        "subtitle-text-track.v1.schema.json",
        "word-timeline.v1.schema.json",
        "phone-timeline.v1.schema.json",
        "sense-group-analysis.v1.schema.json",
        "word-acoustics.v1.schema.json",
        "prosody-analysis.v1.schema.json",
    ] {
        let document: Value =
            serde_json::from_slice(&fs::read(payload_dir.join(file)).unwrap()).unwrap();
        assert!(
            document["properties"].get("extensions").is_none(),
            "{file} must not declare extensions for the strict v1 payload shape"
        );
    }
}

// ---------------------------------------------------------------------------
// Selective streaming archive reads
// ---------------------------------------------------------------------------

#[test]
fn oversized_embedded_media_streams_and_plan_marks_available() {
    // Embedded rendition media larger than max_file_bytes is streamed to its
    // size and digest facts instead of failing the file-size limit, for both
    // directory and ZIP carriers with a sufficient max_total_bytes.
    let media = vec![0xAB; 64 * 1024];
    let (release, blobs) = rendition_fixture_with_size(&media, media.len() as u64);
    let files = carrier(&release, None, &blobs);
    let limits = streaming_limits();
    for as_zip in [false, true] {
        let inspection = inspect_carrier_with_limits(&files, as_zip, limits).unwrap();
        assert!(inspection.blobs.values().all(|blob| blob.present));
        assert_eq!(inspection.delivery_profile, DeliveryProfile::Embedded);
        assert!(inspection.missing_blobs.is_empty());
        assert_eq!(inspection.renditions.len(), 1);
        assert!(inspection.renditions[0].media_present);
        let plan = installation_plan(&inspection);
        assert_eq!(plan.delivery_profile, DeliveryProfile::Embedded);
        assert!(plan.missing_blobs.is_empty());
        assert!(plan.renditions[0].available);
        assert_eq!(plan.renditions[0].media_size_bytes, media.len() as u64);
        // total_bytes counts every carrier entry once, including the media.
        let expected_total: u64 = files.values().map(|bytes| bytes.len() as u64).sum();
        assert_eq!(inspection.total_bytes, expected_total);
    }
}

#[test]
fn corrupt_streamed_media_fails_digest_validation() {
    // The streamed body is hashed without retention; a corrupt body no longer
    // matches the declared digest and must fail exactly like a retained blob.
    let media = vec![0xAB; 64 * 1024];
    let (release, blobs) = rendition_fixture_with_size(&media, media.len() as u64);
    let mut files = carrier(&release, None, &blobs);
    let path = blobs[0].0.clone();
    let mut tampered = files[&path].clone();
    *tampered.last_mut().unwrap() ^= 0x01;
    files.insert(path, tampered);
    let limits = streaming_limits();
    for as_zip in [false, true] {
        let error = inspect_carrier_with_limits(&files, as_zip, limits).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("digest does not match its content"),
            "as_zip={as_zip}: {error}"
        );
    }
}

#[test]
fn streamed_media_wrong_declared_size_fails_size_validation() {
    // The descriptor declares one byte more than the embedded media; the
    // streamed observed size must be validated against the descriptor.
    let media = vec![0xAB; 64 * 1024];
    let (release, blobs) = rendition_fixture_with_size(&media, media.len() as u64 + 1);
    let files = carrier(&release, None, &blobs);
    let limits = streaming_limits();
    for as_zip in [false, true] {
        let error = inspect_carrier_with_limits(&files, as_zip, limits).unwrap_err();
        assert!(
            error.to_string().contains("size does not match"),
            "as_zip={as_zip}: {error}"
        );
    }
}

#[test]
fn known_payload_larger_than_max_file_bytes_still_fails_file_limit() {
    // Known typed payloads are retained and bounded by max_file_bytes; only
    // rendition media and opaque payloads are streamed.
    let text = "x".repeat(4096);
    let (_, payload_bytes, digest) = document_payload(&text, &[text.chars().count() as u32]);
    assert!(payload_bytes.len() as u64 > 1024);
    let descriptor = base_descriptor(
        "document_text",
        DOCUMENT_TEXT_SCHEMA_V1,
        "en",
        &[],
        &digest,
        payload_bytes.len() as u64,
    );
    let id = sha256_id(&canonical_bytes(&descriptor));
    let release = release_value(
        &[],
        entrypoint(&id),
        vec![resource_entry(&descriptor, true)],
        vec![],
    );
    let files = carrier(&release, None, &[(blob_path(&digest), payload_bytes)]);
    let limits = streaming_limits();
    let error = inspect_carrier_with_limits(&files, false, limits).unwrap_err();
    assert!(
        matches!(error, V2Error::Limit("file size")),
        "expected a file-size limit error, got {error}"
    );
}

#[test]
fn streamed_media_over_total_limit_still_fails_total_limit() {
    // Streaming removes the per-file bound but never the shared total bound:
    // media larger than max_total_bytes must fail the total-size limit.
    let media = vec![0xAB; 128 * 1024];
    let (release, blobs) = rendition_fixture_with_size(&media, media.len() as u64);
    let files = carrier(&release, None, &blobs);
    let limits = InspectLimits {
        max_file_count: 64,
        max_file_bytes: 1024,
        max_manifest_bytes: 64 * 1024,
        max_total_bytes: 64 * 1024,
    };
    let error = inspect_carrier_with_limits(&files, false, limits).unwrap_err();
    assert!(
        matches!(error, V2Error::Limit("total decompressed size")),
        "expected a total-size limit error, got {error}"
    );
}

// ---------------------------------------------------------------------------
// Carrier consistency between inspection passes
// ---------------------------------------------------------------------------

const BLOB_ONE: &str =
    "blobs/sha256/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const BLOB_TWO: &str =
    "blobs/sha256/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

/// Synthetic catalog-pass facts: one entry (name, size) pair per carrier file.
fn catalog_entries(entries: &[(&str, u64)]) -> Vec<CatalogEntry> {
    entries
        .iter()
        .map(|(name, size)| CatalogEntry {
            name: (*name).to_owned(),
            size: *size,
        })
        .collect()
}

/// Synthetic selective-pass facts: retained file bodies plus streamed
/// (name, size) facts; `total_bytes` mirrors what the pass reported.
fn selective_package(
    files: &[(&str, &[u8])],
    streamed: &[(&str, u64)],
    total_bytes: u64,
) -> SelectivePackage {
    SelectivePackage {
        files: files
            .iter()
            .map(|(name, bytes)| ((*name).to_owned(), bytes.to_vec()))
            .collect(),
        streamed: streamed
            .iter()
            .map(|(name, size)| StreamedFile {
                name: (*name).to_owned(),
                size: *size,
                sha256: String::new(),
            })
            .collect(),
        total_bytes,
    }
}

fn assert_carrier_changed(error: V2Error, expected_path: &str) {
    assert!(
        error
            .to_string()
            .contains("carrier changed between inspection passes"),
        "expected a stable carrier-change error, got {error}"
    );
    assert!(
        matches!(&error, V2Error::Invalid { path, .. } if path == expected_path),
        "expected the mismatch to be reported at {expected_path}, got {error}"
    );
}

#[test]
fn carrier_consistency_accepts_identical_passes() {
    // release.json, delivery.json, one retained blob, and one streamed blob
    // all match between the catalog and selective facts.
    let entries = catalog_entries(&[
        ("release.json", 3),
        ("delivery.json", 3),
        (BLOB_ONE, 4),
        (BLOB_TWO, 5),
    ]);
    let selective = selective_package(
        &[
            ("release.json", b"rel"),
            ("delivery.json", b"del"),
            (BLOB_ONE, b"aaaa"),
        ],
        &[(BLOB_TWO, 5)],
        15,
    );
    verify_carrier_consistency(&entries, 15, b"rel", Some(b"del"), &selective).unwrap();

    // delivery.json absent in both passes is also consistent.
    let entries = catalog_entries(&[("release.json", 3), (BLOB_ONE, 4)]);
    let selective = selective_package(&[("release.json", b"rel"), (BLOB_ONE, b"aaaa")], &[], 7);
    verify_carrier_consistency(&entries, 7, b"rel", None, &selective).unwrap();
}

#[test]
fn carrier_consistency_rejects_added_entry() {
    // BLOB_TWO exists only in the selective facts: an addition between passes.
    let entries = catalog_entries(&[("release.json", 3), (BLOB_ONE, 4)]);
    let selective = selective_package(
        &[
            ("release.json", b"rel"),
            (BLOB_ONE, b"aaaa"),
            (BLOB_TWO, b"bbbb"),
        ],
        &[],
        11,
    );
    let error = verify_carrier_consistency(&entries, 7, b"rel", None, &selective).unwrap_err();
    assert_carrier_changed(error, BLOB_TWO);
}

#[test]
fn carrier_consistency_rejects_removed_entry() {
    // BLOB_TWO was cataloged in the first pass but is missing from the
    // selective facts: a removal between passes.
    let entries = catalog_entries(&[("release.json", 3), (BLOB_ONE, 4), (BLOB_TWO, 5)]);
    let selective = selective_package(&[("release.json", b"rel"), (BLOB_ONE, b"aaaa")], &[], 7);
    let error = verify_carrier_consistency(&entries, 12, b"rel", None, &selective).unwrap_err();
    assert_carrier_changed(error, BLOB_TWO);
}

#[test]
fn carrier_consistency_rejects_size_mismatch() {
    // BLOB_ONE grew from 4 to 5 bytes between the passes while still present.
    let entries = catalog_entries(&[("release.json", 3), (BLOB_ONE, 4)]);
    let selective = selective_package(&[("release.json", b"rel"), (BLOB_ONE, b"aaaaa")], &[], 8);
    let error = verify_carrier_consistency(&entries, 7, b"rel", None, &selective).unwrap_err();
    assert_carrier_changed(error, BLOB_ONE);
}

#[test]
fn carrier_consistency_rejects_same_size_control_mutation() {
    // release.json keeps its 3-byte size but its bytes differ between the
    // passes: the entry comparison cannot see it, the byte comparison must.
    let entries = catalog_entries(&[("release.json", 3), (BLOB_ONE, 4)]);
    let selective = selective_package(&[("release.json", b"rex"), (BLOB_ONE, b"aaaa")], &[], 7);
    let error = verify_carrier_consistency(&entries, 7, b"rel", None, &selective).unwrap_err();
    assert_carrier_changed(error, "release.json");
}

#[test]
fn carrier_consistency_rejects_delivery_presence_change() {
    // delivery.json was present in the catalog pass but is absent from the
    // selective pass: a presence change must fail.
    let entries = catalog_entries(&[("release.json", 3), ("delivery.json", 3), (BLOB_ONE, 4)]);
    let selective = selective_package(&[("release.json", b"rel"), (BLOB_ONE, b"aaaa")], &[], 7);
    let error =
        verify_carrier_consistency(&entries, 10, b"rel", Some(b"del"), &selective).unwrap_err();
    assert_carrier_changed(error, "delivery.json");

    // The reverse: delivery.json appears only in the selective pass.
    let entries = catalog_entries(&[("release.json", 3), (BLOB_ONE, 4)]);
    let selective = selective_package(
        &[
            ("release.json", b"rel"),
            ("delivery.json", b"del"),
            (BLOB_ONE, b"aaaa"),
        ],
        &[],
        10,
    );
    let error = verify_carrier_consistency(&entries, 7, b"rel", None, &selective).unwrap_err();
    assert_carrier_changed(error, "delivery.json");
}

#[test]
fn carrier_consistency_rejects_delivery_byte_mutation() {
    // delivery.json keeps its size but its bytes differ between the passes.
    let entries = catalog_entries(&[("release.json", 3), ("delivery.json", 3), (BLOB_ONE, 4)]);
    let selective = selective_package(
        &[
            ("release.json", b"rel"),
            ("delivery.json", b"dex"),
            (BLOB_ONE, b"aaaa"),
        ],
        &[],
        10,
    );
    let error =
        verify_carrier_consistency(&entries, 10, b"rel", Some(b"del"), &selective).unwrap_err();
    assert_carrier_changed(error, "delivery.json");
}

#[test]
fn carrier_consistency_rejects_total_mismatch() {
    // Every entry matches, but the selective pass reports a total that cannot
    // be produced by the observed bodies: the totals must agree explicitly.
    let entries = catalog_entries(&[("release.json", 3)]);
    let selective = selective_package(&[("release.json", b"rel")], &[], 99);
    let error = verify_carrier_consistency(&entries, 3, b"rel", None, &selective).unwrap_err();
    assert_carrier_changed(error, "package");
}
