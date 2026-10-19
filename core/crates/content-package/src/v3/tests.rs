//! Content Package v3 tests: bounded, persistence-free inspection and the
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

use crate::inspect::InspectLimits;
use crate::v2::canonical::serialize_canonical;
use crate::v2::{ResourceDisposition, ResourceRole, TRANSLATION_SCHEMA_V1};
use crate::v3::{
    ANCHOR_TIME_ALIGNMENT_SCHEMA_V1, KnownPayloadV3, RELEASE_SCHEMA_V3,
    STRUCTURED_READING_SCHEMA_V1, V3Error, V3Inspection, inspect_v3_path,
    inspect_v3_path_with_limits, installation_plan_v3,
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
            "listen-content-package-v3-{process}-{sequence}-{nonce}"
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

/// Sentence anchor ranges split `text` on sentence enders so every fixture
/// offset stays a true UTF-8 byte boundary of the exact text.
fn sentence_ranges(text: &str) -> Vec<(u64, u64)> {
    let mut ranges = Vec::new();
    let mut start = 0_usize;
    for (index, character) in text.char_indices() {
        if matches!(character, '.' | '!' | '?')
            && text[index..].starts_with(character.to_string().as_str())
            && text[index + character.len_utf8()..]
                .chars()
                .next()
                .is_none_or(|next| next.is_whitespace() || matches!(next, '.' | '!' | '?'))
        {
            let mut end = index + character.len_utf8();
            while text.as_bytes().get(end) == Some(&b' ') {
                end += 1;
            }
            if start < end {
                ranges.push((start as u64, end as u64));
            }
            start = end;
        }
    }
    if start < text.len() {
        ranges.push((start as u64, text.len() as u64));
    }
    ranges
}

/// A structured reading payload with sentence anchors over the exact `text`,
/// one `root` block, an optional block hierarchy, and an optional document
/// mapping to the given document rendition id. Returns (payload value, raw
/// bytes, digest).
fn structured_payload(text: &str, rendition_id: Option<&str>) -> (Value, Vec<u8>, String) {
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
    let mut blocks = vec![json!({
        "block_id": "block-root",
        "kind": "root",
        "order": 0,
        "span_anchor_ids": (0..ranges.len())
            .map(|index| format!("anchor-{}", index + 1))
            .collect::<Vec<_>>(),
        "parent_block_id": null,
    })];
    if ranges.len() > 1 {
        blocks.push(json!({
            "block_id": "block-section",
            "kind": "section",
            "order": 0,
            "span_anchor_ids": [format!("anchor-{}", ranges.len())],
            "parent_block_id": "block-root",
        }));
    }
    let document_mappings = match rendition_id {
        Some(id) => json!([{
            "anchor_id": "anchor-1",
            "rendition_id": id,
            "locator": {"kind": "character_range", "value": format!("0:{}", ranges[0].1)},
        }]),
        None => json!([]),
    };
    let payload = json!({
        "language": "en",
        "text": text,
        "anchors": anchors,
        "blocks": blocks,
        "spans": [],
        "document_mappings": document_mappings,
        "extensions": {},
    });
    let bytes = serde_json::to_vec_pretty(&payload).unwrap();
    let digest = sha256_id(&bytes);
    (payload, bytes, digest)
}

/// A timed text track payload (a shared v2 family still in the v3 active
/// inventory) used to prove that non-structured-reading bases are rejected.
fn timed_text_payload(text: &str) -> (Value, Vec<u8>, String) {
    let payload = json!({
        "language": "en",
        "segments": [
            {"id": "tt-1", "index": 0, "language": "en", "start_ms": 0, "end_ms": 1000, "text": text},
        ],
        "extensions": {},
    });
    let bytes = serde_json::to_vec_pretty(&payload).unwrap();
    let digest = sha256_id(&bytes);
    (payload, bytes, digest)
}

fn producer_value() -> Value {
    json!({
        "created_at_ms": 1,
        "tool": {"id": "listen-gen", "version": "0.4.0"},
        "provider": null,
        "model": null,
        "config_sha256": null,
    })
}

fn compatibility_value(rendition_id: Option<&str>) -> Value {
    let inputs = match rendition_id {
        Some(id) => json!([{"rendition_id": id, "resource_id": null}]),
        None => json!([]),
    };
    json!({
        "verified_inputs": inputs,
        "checks": ["exact_text_match"],
    })
}

/// Builds a Document Rendition entry with the identity derived from the
/// canonical `{media_type, language, text_blob}` descriptor.
fn document_rendition_value(
    origin: &str,
    media_type: &str,
    language: Option<&str>,
    text_blob: &Value,
    source_asset_id: Option<&str>,
    producer: Option<&Value>,
    compatibility: Option<&Value>,
) -> Value {
    let identity = json!({
        "media_type": media_type,
        "language": language,
        "text_blob": text_blob,
    });
    let rendition_id = sha256_id(&canonical_bytes(&identity));
    json!({
        "rendition_id": rendition_id,
        "origin": origin,
        "media_type": media_type,
        "language": language,
        "text_blob": text_blob.clone(),
        "source_asset_id": source_asset_id,
        "producer": producer,
        "compatibility": compatibility,
        "extensions": {},
    })
}

/// Builds a Media Rendition entry with the identity derived from the
/// canonical `{kind, media_type, media_blob, media_id, fingerprint}`
/// descriptor.
fn media_rendition_value(
    origin: &str,
    kind: &str,
    media_type: &str,
    media_blob: &Value,
    media_id: Option<&str>,
    fingerprint: &str,
    extras: MediaExtras,
) -> Value {
    let identity = json!({
        "kind": kind,
        "media_type": media_type,
        "media_blob": media_blob,
        "media_id": media_id,
        "fingerprint": fingerprint,
    });
    let rendition_id = sha256_id(&canonical_bytes(&identity));
    json!({
        "rendition_id": rendition_id,
        "origin": origin,
        "kind": kind,
        "media_type": media_type,
        "media_blob": media_blob.clone(),
        "media_id": media_id,
        "fingerprint": fingerprint,
        "producer": extras.producer,
        "compatibility": extras.compatibility,
        "extensions": {},
    })
}

#[derive(Clone)]
struct MediaExtras<'a> {
    producer: Option<&'a Value>,
    compatibility: Option<&'a Value>,
}

fn media_extras<'a>(
    producer: Option<&'a Value>,
    compatibility: Option<&'a Value>,
) -> MediaExtras<'a> {
    MediaExtras {
        producer,
        compatibility,
    }
}

fn blob_declaration(digest: &str, size: u64, embedded: bool) -> Value {
    json!({"digest": digest, "size_bytes": size, "embedded": embedded})
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
        "payload_blob": blob_declaration(digest, size, true),
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
    document_renditions: Vec<Value>,
    media_renditions: Vec<Value>,
    resources: Vec<Value>,
) -> Value {
    json!({
        "schema": RELEASE_SCHEMA_V3,
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
        "document_renditions": document_renditions,
        "media_renditions": media_renditions,
        "resources": resources,
        "extensions": {},
    })
}

fn carrier(release: &Value, blobs: &[(String, Vec<u8>)]) -> BTreeMap<String, Vec<u8>> {
    let mut files = BTreeMap::new();
    files.insert("release.json".to_owned(), canonical_bytes(release));
    for (path, bytes) in blobs {
        files.insert(path.clone(), bytes.clone());
    }
    files
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
) -> Result<V3Inspection, V3Error> {
    let directory = TestDirectory::new();
    if as_zip {
        inspect_v3_path(write_zip(directory.path(), files))
    } else {
        write_tree(directory.path(), files);
        inspect_v3_path(directory.path())
    }
}

fn inspect_ok(files: &BTreeMap<String, Vec<u8>>) -> V3Inspection {
    inspect_carrier(files, false).unwrap()
}

fn inspect_err(files: &BTreeMap<String, Vec<u8>>) -> V3Error {
    inspect_carrier(files, false).unwrap_err()
}

/// Mutates a resource descriptor in place and restores the identity invariant
/// (resource_id is the canonical JSON digest of the descriptor).
fn update_resource_descriptor(release: &mut Value, index: usize, update: impl FnOnce(&mut Value)) {
    let resources = release
        .get_mut("resources")
        .unwrap()
        .as_array_mut()
        .unwrap();
    let entry = &mut resources[index];
    let descriptor = entry.get_mut("descriptor").unwrap();
    update(descriptor);
    entry["resource_id"] = json!(sha256_id(&canonical_bytes(descriptor)));
}

fn example_files(name: &str) -> BTreeMap<String, Vec<u8>> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../contracts/content-package/v3/examples")
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

fn inspect_example(name: &str, as_zip: bool) -> V3Inspection {
    let directory = TestDirectory::new();
    let files = example_files(name);
    if as_zip {
        inspect_v3_path(write_zip(directory.path(), &files)).unwrap()
    } else {
        write_tree(directory.path(), &files);
        inspect_v3_path(directory.path()).unwrap()
    }
}

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const TEXT: &str = "Pandas eat bamboo. They live in China.";

/// One source Document Rendition carrying the exact raw text bytes and one
/// embedded structured reading resource over the same text. This is the
/// document-source golden shape: raw bytes live on the rendition's
/// `text_blob`, exact logical reading content lives in the Structured
/// Reading payload.
fn document_source_fixture() -> (Value, Vec<(String, Vec<u8>)>) {
    let text_bytes = TEXT.as_bytes().to_vec();
    let text_digest = sha256_id(&text_bytes);
    let text_blob = blob_declaration(&text_digest, text_bytes.len() as u64, true);
    let document = document_rendition_value(
        "source",
        "text/plain",
        Some("en"),
        &text_blob,
        Some("sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
        None,
        None,
    );
    let document_id = document["rendition_id"].as_str().unwrap().to_owned();
    let (_, structured_bytes, structured_digest) = structured_payload(TEXT, Some(&document_id));
    let descriptor = base_descriptor(
        "structured_reading",
        STRUCTURED_READING_SCHEMA_V1,
        "en",
        &[],
        &structured_digest,
        structured_bytes.len() as u64,
    );
    let resource = resource_entry(&descriptor, true);
    let release = release_value(&[], vec![document], vec![], vec![resource]);
    let blobs = vec![
        (blob_path(&text_digest), text_bytes),
        (blob_path(&structured_digest), structured_bytes),
    ];
    (release, blobs)
}

/// One embedded source Document Rendition whose text blob carries a plain
/// text payload distinct from any resource payload.
fn document_only_fixture() -> (Value, Vec<(String, Vec<u8>)>) {
    let text_bytes = TEXT.as_bytes().to_vec();
    let text_digest = sha256_id(&text_bytes);
    let text_blob = blob_declaration(&text_digest, text_bytes.len() as u64, true);
    let document = document_rendition_value(
        "source",
        "text/plain",
        Some("en"),
        &text_blob,
        Some("sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
        None,
        None,
    );
    let release = release_value(&[], vec![document], vec![], vec![]);
    let blobs = vec![(blob_path(&text_digest), text_bytes)];
    (release, blobs)
}

/// One embedded and one referenced Media Rendition, plus a derived
/// Structured Reading base resource and its anchor-to-time alignment. This
/// proves the media path converges on Structured Reading (ASR-derived) in
/// the same format-neutral model as documents.
fn media_only_fixture() -> (Value, Vec<(String, Vec<u8>)>) {
    let embedded_bytes = b"listen fixture derived audio".to_vec();
    let embedded_digest = sha256_id(&embedded_bytes);
    let embedded_blob = blob_declaration(&embedded_digest, embedded_bytes.len() as u64, true);
    let derived = media_rendition_value(
        "derived",
        "audio",
        "audio/mpeg",
        &embedded_blob,
        None,
        "fp-derived-1",
        media_extras(Some(&producer_value()), Some(&compatibility_value(None))),
    );
    let source = {
        let referenced_digest = format!("sha256:{}", "c".repeat(64));
        let referenced_blob = blob_declaration(&referenced_digest, 100, false);
        media_rendition_value(
            "source",
            "audio",
            "audio/mpeg",
            &referenced_blob,
            Some("media-1"),
            "fp-source-1",
            media_extras(None, None),
        )
    };
    let source_id = source["rendition_id"].as_str().unwrap().to_owned();
    let (_, structured, structured_digest) = structured_payload(TEXT, None);
    let structured_descriptor = base_descriptor(
        "structured_reading",
        STRUCTURED_READING_SCHEMA_V1,
        "en",
        &[],
        &structured_digest,
        structured.len() as u64,
    );
    let structured_resource = resource_entry(&structured_descriptor, false);
    let structured_id = structured_resource["resource_id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (_, alignment, alignment_digest) = alignment_payload(&structured_id, &source_id);
    let alignment_descriptor = base_descriptor(
        "anchor_time_alignment",
        ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
        "en",
        &[],
        &alignment_digest,
        alignment.len() as u64,
    );
    let alignment_resource = resource_entry(&alignment_descriptor, false);
    let release = release_value(
        &[],
        vec![],
        vec![derived, source],
        vec![structured_resource, alignment_resource],
    );
    let blobs = vec![
        (blob_path(&embedded_digest), embedded_bytes),
        (blob_path(&structured_digest), structured),
        (blob_path(&alignment_digest), alignment),
    ];
    (release, blobs)
}

fn alignment_payload(anchor_resource_id: &str, rendition_id: &str) -> (Value, Vec<u8>, String) {
    let payload = json!({
        "anchor_resource_id": anchor_resource_id,
        "rendition_id": rendition_id,
        "alignments": [
            {"anchor_id": "anchor-1", "media_time_ms": 0},
            {"anchor_id": "anchor-2", "media_time_ms": 1200},
        ],
        "extensions": {},
    });
    let bytes = serde_json::to_vec_pretty(&payload).unwrap();
    let digest = sha256_id(&bytes);
    (payload, bytes, digest)
}

/// The composed fixture: a source Document Rendition, source and derived
/// Media Renditions, a structured reading base resource, an anchor-to-time
/// alignment base resource, and a translation assistance resource anchored
/// to the Structured Reading sentence anchors. Embedded and referenced blobs
/// mix. The identity strings are parameterized so committed examples can
/// carry example-flavoured identities without touching the shared builders.
fn composed_fixture() -> (Value, Vec<(String, Vec<u8>)>) {
    composed_fixture_with(
        "edition-fixture-v1",
        "Fixture Edition",
        "material-fixture-v1",
        MATERIAL_REVISION,
        "Fixture Material",
    )
}

fn composed_fixture_with(
    edition_id: &str,
    edition_title: &str,
    material_id: &str,
    material_revision_id: &str,
    material_title: &str,
) -> (Value, Vec<(String, Vec<u8>)>) {
    let subject = json!({
        "material_revision_id": material_revision_id,
        "rendition_ids": [],
        "anchor_resource_ids": [],
    });
    let base_descriptor = |kind: &str,
                           schema: &str,
                           language: &str,
                           dependencies: &[&str],
                           digest: &str,
                           size: u64| {
        json!({
            "schema": schema,
            "kind": kind,
            "role": "base",
            "content_language": language,
            "support_languages": [],
            "subject": subject.clone(),
            "dependencies": dependencies.iter().map(|dep| json!({"resource_id": dep})).collect::<Vec<_>>(),
            "provenance": {"created_at_ms": 1, "tool": {"id": "listen-gen", "version": "0.4.0"}, "input_resource_ids": [], "extensions": {}},
            "quality": {"review_status": "human_reviewed", "warnings": [], "extensions": {}},
            "payload_blob": blob_declaration(digest, size, true),
            "extensions": {},
        })
    };
    let assistance_descriptor = |kind: &str,
                                 schema: &str,
                                 support: &[&str],
                                 dependencies: &[&str],
                                 digest: &str,
                                 size: u64| {
        json!({
            "schema": schema,
            "kind": kind,
            "role": "assistance",
            "support_languages": support,
            "subject": subject.clone(),
            "dependencies": dependencies.iter().map(|dep| json!({"resource_id": dep})).collect::<Vec<_>>(),
            "provenance": {"created_at_ms": 1, "tool": {"id": "listen-gen", "version": "0.4.0"}, "input_resource_ids": [], "extensions": {}},
            "quality": {"review_status": "machine_checked", "warnings": [], "extensions": {}},
            "payload_blob": blob_declaration(digest, size, true),
            "extensions": {},
        })
    };
    let mut blobs = Vec::new();

    let text_bytes = TEXT.as_bytes().to_vec();
    let doc_digest = sha256_id(&text_bytes);
    let doc_blob = blob_declaration(&doc_digest, text_bytes.len() as u64, true);
    blobs.push((blob_path(&doc_digest), text_bytes));
    let document = document_rendition_value(
        "source",
        "text/plain",
        Some("en"),
        &doc_blob,
        Some("sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"),
        None,
        None,
    );
    let document_id = document["rendition_id"].as_str().unwrap().to_owned();

    let derived_text = b"Pandas eat bamboo. They live in China. (derived)".to_vec();
    let derived_digest = sha256_id(&derived_text);
    let derived_blob = blob_declaration(&derived_digest, derived_text.len() as u64, false);
    let derived_document = document_rendition_value(
        "derived",
        "text/plain",
        Some("en"),
        &derived_blob,
        None,
        Some(&producer_value()),
        Some(&compatibility_value(Some(&document_id))),
    );

    let embedded_media = b"listen fixture composed media".to_vec();
    let embedded_media_digest = sha256_id(&embedded_media);
    let embedded_media_blob =
        blob_declaration(&embedded_media_digest, embedded_media.len() as u64, true);
    blobs.push((blob_path(&embedded_media_digest), embedded_media));
    let source_media = media_rendition_value(
        "source",
        "audio",
        "audio/mpeg",
        &embedded_media_blob,
        Some("media-1"),
        "fp-source-composed",
        media_extras(None, None),
    );
    let source_media_id = source_media["rendition_id"].as_str().unwrap().to_owned();

    let referenced_media_digest = format!("sha256:{}", "e".repeat(64));
    let referenced_media_blob = blob_declaration(&referenced_media_digest, 200, false);
    let derived_media = media_rendition_value(
        "derived",
        "audio",
        "audio/mpeg",
        &referenced_media_blob,
        None,
        "fp-derived-composed",
        media_extras(
            Some(&producer_value()),
            Some(&compatibility_value(Some(&document_id))),
        ),
    );

    let (_, structured, structured_digest) = structured_payload(TEXT, Some(&document_id));
    let structured_descriptor = base_descriptor(
        "structured_reading",
        STRUCTURED_READING_SCHEMA_V1,
        "en",
        &[],
        &structured_digest,
        structured.len() as u64,
    );
    let structured_resource = resource_entry(&structured_descriptor, true);
    let structured_id = structured_resource["resource_id"]
        .as_str()
        .unwrap()
        .to_owned();
    blobs.push((blob_path(&structured_digest), structured));

    let (_, alignment, alignment_digest) = alignment_payload(&structured_id, &source_media_id);
    let alignment_descriptor = base_descriptor(
        "anchor_time_alignment",
        ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
        "en",
        &[],
        &alignment_digest,
        alignment.len() as u64,
    );
    let alignment_resource = resource_entry(&alignment_descriptor, true);
    blobs.push((blob_path(&alignment_digest), alignment));

    // The translation is an Assistance Resource anchored to the exact
    // Structured Reading sentence anchors; there is no document_text base.
    let translation = json!({
        "support_language": "zh-Hans",
        "base_resource_id": structured_id,
        "segments": [
            {"id": "tr-1", "index": 0, "text": "大熊猫吃竹子。", "source_segment_id": "anchor-1", "extensions": {}},
            {"id": "tr-2", "index": 1, "text": "它们住在中国。", "source_segment_id": "anchor-2", "extensions": {}},
        ],
        "extensions": {},
    });
    let translation_bytes = serde_json::to_vec_pretty(&translation).unwrap();
    let translation_digest = sha256_id(&translation_bytes);
    let translation_descriptor = assistance_descriptor(
        "translation",
        TRANSLATION_SCHEMA_V1,
        &["zh-Hans"],
        &[&structured_id],
        &translation_digest,
        translation_bytes.len() as u64,
    );
    let translation_resource = resource_entry(&translation_descriptor, false);
    blobs.push((blob_path(&translation_digest), translation_bytes));

    let release = json!({
        "schema": RELEASE_SCHEMA_V3,
        "created_at_ms": 1u64,
        "edition": {
            "edition_id": edition_id,
            "title": edition_title,
            "target_language": "en",
            "support_languages": ["zh-Hans"],
        },
        "material": {
            "material_id": material_id,
            "material_revision_id": material_revision_id,
            "title": material_title,
        },
        "document_renditions": [document, derived_document],
        "media_renditions": [source_media, derived_media],
        "resources": [
            structured_resource,
            alignment_resource,
            translation_resource,
        ],
        "extensions": {},
    });
    (release, blobs)
}

// ---------------------------------------------------------------------------
// Example carriers
// ---------------------------------------------------------------------------

#[test]
fn committed_document_source_example_inspects() {
    let inspection = inspect_example("document-source", false);
    assert_eq!(inspection.release.schema, RELEASE_SCHEMA_V3);
    assert_eq!(inspection.document_renditions.len(), 1);
    assert_eq!(inspection.media_renditions.len(), 0);
    let structured = inspection
        .resources
        .iter()
        .find(|record| record.entry.descriptor.kind == "structured_reading")
        .expect("structured reading record");
    assert!(structured.entry.required);
    assert_eq!(structured.entry.descriptor.role, ResourceRole::Base);
    let KnownPayloadV3::StructuredReading(payload) = &structured.payload else {
        panic!("expected structured reading payload");
    };
    assert_eq!(payload.anchors.len(), 2);
    assert!(!payload.text.is_empty());
    assert_eq!(payload.document_mappings.len(), 1);
    assert_eq!(inspection.missing_blobs.len(), 0);
    assert!(!inspection.payload_blobs.is_empty());
    // The same carrier in deterministic ZIP form inspects identically.
    let zipped = inspect_example("document-source", true);
    assert_eq!(zipped.release_id, inspection.release_id);
    assert_eq!(zipped.total_bytes, inspection.total_bytes);
}

#[test]
fn committed_media_only_example_inspects() {
    let inspection = inspect_example("media-only", false);
    assert_eq!(inspection.document_renditions.len(), 0);
    assert_eq!(inspection.media_renditions.len(), 2);
    assert_eq!(inspection.resources.len(), 2);
    assert!(
        inspection
            .resources
            .iter()
            .any(|record| record.entry.descriptor.kind == "structured_reading")
    );
    assert!(
        inspection
            .resources
            .iter()
            .any(|record| record.entry.descriptor.kind == "anchor_time_alignment")
    );
    let derived = inspection
        .media_renditions
        .iter()
        .find(|record| record.entry.origin == crate::v3::RenditionOrigin::Derived)
        .expect("derived media rendition");
    assert!(derived.media_present);
    assert!(derived.entry.producer.is_some());
    assert!(derived.entry.compatibility.is_some());
    let source = inspection
        .media_renditions
        .iter()
        .find(|record| record.entry.origin == crate::v3::RenditionOrigin::Source)
        .expect("source media rendition");
    assert!(!source.media_present);
    assert_eq!(inspection.missing_blobs.len(), 1);
    assert!(
        inspection
            .warnings
            .iter()
            .any(|warning| warning.contains("absent from the carrier"))
    );
    let zipped = inspect_example("media-only", true);
    assert_eq!(zipped.release_id, inspection.release_id);
}

#[test]
fn committed_composed_example_inspects() {
    let inspection = inspect_example("composed", false);
    assert_eq!(inspection.document_renditions.len(), 2);
    assert_eq!(inspection.media_renditions.len(), 2);
    assert_eq!(inspection.resources.len(), 3);
    assert_eq!(inspection.missing_blobs.len(), 2);
    let derived_document = inspection
        .document_renditions
        .iter()
        .find(|record| record.entry.origin == crate::v3::RenditionOrigin::Derived)
        .expect("derived document rendition");
    assert!(derived_document.entry.producer.is_some());
    assert!(!derived_document.text_present);
    let structured = inspection
        .resources
        .iter()
        .find(|record| record.entry.descriptor.kind == "structured_reading")
        .expect("structured reading record");
    let KnownPayloadV3::StructuredReading(payload) = &structured.payload else {
        panic!("expected structured reading payload");
    };
    assert_eq!(payload.anchors.len(), 2);
    assert_eq!(payload.document_mappings.len(), 1);
    assert_eq!(
        payload.document_mappings[0].rendition_id,
        inspection.document_renditions[0].entry.rendition_id
    );
    let alignment = inspection
        .resources
        .iter()
        .find(|record| record.entry.descriptor.kind == "anchor_time_alignment")
        .expect("alignment record");
    let KnownPayloadV3::AnchorTimeAlignment(payload) = &alignment.payload else {
        panic!("expected anchor time alignment payload");
    };
    assert_eq!(payload.alignments.len(), 2);
    let zipped = inspect_example("composed", true);
    assert_eq!(zipped.release_id, inspection.release_id);
}

// ---------------------------------------------------------------------------
// Valid synthetic carriers
// ---------------------------------------------------------------------------

#[test]
fn document_only_package_with_source_rendition_inspects() {
    let (release, blobs) = document_only_fixture();
    let inspection = inspect_ok(&carrier(&release, &blobs));
    assert_eq!(inspection.document_renditions.len(), 1);
    assert!(inspection.document_renditions[0].text_present);
    assert_eq!(inspection.blobs.len(), 1);
    assert!(
        inspection
            .blobs
            .values()
            .all(|record| record.embedded && record.present)
    );
    assert_eq!(inspection.missing_blobs.len(), 0);
}

#[test]
fn media_only_package_with_mixed_embedded_and_referenced_blobs_inspects() {
    let (release, blobs) = media_only_fixture();
    let inspection = inspect_ok(&carrier(&release, &blobs));
    assert_eq!(inspection.media_renditions.len(), 2);
    let derived = inspection
        .media_renditions
        .iter()
        .find(|record| record.entry.origin == crate::v3::RenditionOrigin::Derived)
        .unwrap();
    assert!(derived.media_present);
    let source = inspection
        .media_renditions
        .iter()
        .find(|record| record.entry.origin == crate::v3::RenditionOrigin::Source)
        .unwrap();
    assert!(!source.media_present);
    assert_eq!(inspection.missing_blobs.len(), 1);
}

#[test]
fn composed_package_inspects_and_plans() {
    let (release, blobs) = composed_fixture();
    let inspection = inspect_ok(&carrier(&release, &blobs));
    assert_eq!(inspection.document_renditions.len(), 2);
    assert_eq!(inspection.media_renditions.len(), 2);
    assert_eq!(inspection.resources.len(), 3);
    assert_eq!(inspection.missing_blobs.len(), 2);

    let plan = installation_plan_v3(&inspection);
    assert_eq!(plan.schema, "listen.content-package.plan.v3");
    assert_eq!(plan.document_renditions.len(), 2);
    assert_eq!(plan.media_renditions.len(), 2);
    assert_eq!(plan.resources.len(), 3);
    assert_eq!(
        plan.resources
            .iter()
            .filter(|r| r.disposition == ResourceDisposition::Candidate)
            .count(),
        3
    );
    let derived_document = plan
        .document_renditions
        .iter()
        .find(|rendition| rendition.origin == crate::v3::RenditionOrigin::Derived)
        .unwrap();
    assert!(!derived_document.available);
    assert_eq!(
        derived_document.producer.as_ref().unwrap().tool_id,
        "listen-gen"
    );
    let derived_media = plan
        .media_renditions
        .iter()
        .find(|rendition| rendition.origin == crate::v3::RenditionOrigin::Derived)
        .unwrap();
    assert!(!derived_media.available);
    let source_media = plan
        .media_renditions
        .iter()
        .find(|rendition| rendition.origin == crate::v3::RenditionOrigin::Source)
        .unwrap();
    assert!(source_media.available);
    assert_eq!(plan.missing_blobs.len(), 2);
}

#[test]
fn zip_carrier_inspects_identically_to_directory() {
    let (release, blobs) = composed_fixture();
    let files = carrier(&release, &blobs);
    let directory = inspect_ok(&files);
    let zipped = inspect_carrier(&files, true).unwrap();
    assert_eq!(zipped.release_id, directory.release_id);
    assert_eq!(zipped.total_bytes, directory.total_bytes);
    assert_eq!(zipped.warnings, directory.warnings);
    assert_eq!(zipped.payload_blobs, directory.payload_blobs);
}

// ---------------------------------------------------------------------------
// Rejected invariants
// ---------------------------------------------------------------------------

#[test]
fn non_v3_schema_is_rejected() {
    let (mut release, blobs) = composed_fixture();
    release["schema"] = json!("listen.content-package.release.v2");
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(error.to_string().contains("unsupported release schema"));
}

#[test]
fn embedded_blob_missing_is_an_invalid_carrier() {
    let (release, blobs) = composed_fixture();
    // Re-declare the structured reading payload blob as referenced instead of
    // embedded without removing it from the carrier: the inspector must reject
    // the declaration change... it cannot, so instead drop the payload file
    // while the declaration stays embedded.
    let mut files = carrier(&release, &blobs);
    let embedded_path = files
        .keys()
        .find(|name| name.starts_with("blobs/"))
        .cloned()
        .unwrap();
    files.remove(&embedded_path);
    let error = inspect_err(&files);
    assert!(
        error
            .to_string()
            .contains("embedded blob is absent from the carrier")
    );
}

#[test]
fn conflicting_blob_sizes_are_rejected() {
    let (mut release, blobs) = document_source_fixture();
    let resources = release
        .get_mut("resources")
        .unwrap()
        .as_array_mut()
        .unwrap();
    let descriptor = resources[0].get_mut("descriptor").unwrap();
    descriptor["payload_blob"]["size_bytes"] = json!(9999);
    update_resource_descriptor(&mut release, 0, |_| {});
    let error = inspect_err(&carrier(&release, &blobs));
    // The payload blob path no longer matches the size fact, so the retained
    // verification must fail on the blob itself.
    assert!(matches!(error, V3Error::Invalid { .. }));
}

#[test]
fn conflicting_carrier_contracts_are_rejected() {
    let (mut release, blobs) = document_only_fixture();
    // Declare the same text digest twice: once embedded, once referenced.
    let text_digest = release["document_renditions"][0]["text_blob"]["digest"]
        .as_str()
        .unwrap()
        .to_owned();
    let duplicate = document_rendition_value(
        "source",
        "text/plain",
        None,
        &blob_declaration(&text_digest, TEXT.len() as u64, false),
        Some("sha256:1111111111111111111111111111111111111111111111111111111111111111"),
        None,
        None,
    );
    release["document_renditions"]
        .as_array_mut()
        .unwrap()
        .push(duplicate);
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(error.to_string().contains("conflicting carrier contracts"));
}

#[test]
fn derived_document_rendition_requires_producer_and_compatibility() {
    let (release, blobs) = document_only_fixture();
    let text_digest = release["document_renditions"][0]["text_blob"]["digest"]
        .as_str()
        .unwrap()
        .to_owned();
    let text_size = release["document_renditions"][0]["text_blob"]["size_bytes"]
        .as_u64()
        .unwrap();
    // A derived rendition without producer facts is refused.
    let no_producer = document_rendition_value(
        "derived",
        "text/plain",
        Some("en"),
        &blob_declaration(&text_digest, text_size, false),
        None,
        None,
        None,
    );
    let release = release_value(&[], vec![no_producer], vec![], vec![]);
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(
        error
            .to_string()
            .contains("derived document rendition requires producer facts")
    );
}

#[test]
fn source_document_rendition_requires_source_asset_binding() {
    let (mut release, blobs) = document_only_fixture();
    release["document_renditions"][0]["source_asset_id"] = Value::Null;
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(
        error
            .to_string()
            .contains("source document rendition must bind a source_asset_id")
    );
}

#[test]
fn source_media_rendition_requires_media_id() {
    let referenced_digest = format!("sha256:{}", "c".repeat(64));
    let referenced_blob = blob_declaration(&referenced_digest, 100, false);
    let broken = media_rendition_value(
        "source",
        "audio",
        "audio/mpeg",
        &referenced_blob,
        None,
        "fp-source-1",
        media_extras(None, None),
    );
    let release = release_value(&[], vec![], vec![broken], vec![]);
    let error = inspect_err(&carrier(&release, &[]));
    assert!(
        error
            .to_string()
            .contains("source media rendition must bind a media_id")
    );
}

#[test]
fn derived_media_rendition_requires_producer() {
    let embedded_bytes = b"listen fixture derived audio".to_vec();
    let embedded_digest = sha256_id(&embedded_bytes);
    let embedded_blob = blob_declaration(&embedded_digest, embedded_bytes.len() as u64, true);
    let broken = media_rendition_value(
        "derived",
        "audio",
        "audio/mpeg",
        &embedded_blob,
        None,
        "fp-derived-1",
        media_extras(None, Some(&compatibility_value(None))),
    );
    let release = release_value(&[], vec![], vec![broken], vec![]);
    let error = inspect_err(&carrier(
        &release,
        &[(blob_path(&embedded_digest), embedded_bytes)],
    ));
    assert!(
        error
            .to_string()
            .contains("derived media rendition requires producer facts")
    );
}

#[test]
fn compatibility_input_must_reference_a_declared_rendition() {
    let (mut release, blobs) = media_only_fixture();
    let derived_index = release["media_renditions"]
        .as_array()
        .unwrap()
        .iter()
        .position(|entry| entry["origin"] == "derived")
        .unwrap();
    release["media_renditions"][derived_index]["compatibility"]["verified_inputs"] = json!([
        {"rendition_id": format!("sha256:{}", "f".repeat(64)), "resource_id": null}
    ]);
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(
        error
            .to_string()
            .contains("compatibility verified input rendition is not declared")
    );
}

#[test]
fn media_type_must_match_the_rendition_kind_family() {
    let referenced_digest = format!("sha256:{}", "c".repeat(64));
    let referenced_blob = blob_declaration(&referenced_digest, 100, false);
    let broken = media_rendition_value(
        "source",
        "audio",
        "text/plain",
        &referenced_blob,
        Some("media-1"),
        "fp-source-1",
        media_extras(None, None),
    );
    let release = release_value(&[], vec![], vec![broken], vec![]);
    let error = inspect_err(&carrier(&release, &[]));
    assert!(
        error
            .to_string()
            .contains("rendition media_type does not match its kind")
    );
}

/// Wraps a raw structured reading payload JSON as a resource and carrier so
/// negative tests stay compact.
fn structured_reading_carrier(payload: Value) -> BTreeMap<String, Vec<u8>> {
    let bytes = serde_json::to_vec_pretty(&payload).unwrap();
    let digest = sha256_id(&bytes);
    let descriptor = base_descriptor(
        "structured_reading",
        STRUCTURED_READING_SCHEMA_V1,
        "en",
        &[],
        &digest,
        bytes.len() as u64,
    );
    let resource = resource_entry(&descriptor, false);
    let release = release_value(&[], vec![], vec![], vec![resource]);
    carrier(&release, &[(blob_path(&digest), bytes)])
}

#[test]
fn structured_reading_requires_at_least_one_anchor() {
    let empty = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [],
        "blocks": [],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(empty));
    assert!(
        error
            .to_string()
            .contains("structured_reading must declare at least one anchor")
    );
}

#[test]
fn structured_reading_requires_non_empty_text() {
    let empty_text = json!({
        "language": "en",
        "text": "",
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": 0},
        ],
        "blocks": [
            {"block_id": "block-root", "kind": "root", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
        ],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(empty_text));
    assert!(
        error
            .to_string()
            .contains("structured_reading text must not be empty")
    );
}

#[test]
fn structured_reading_rejects_out_of_bounds_anchor_ranges() {
    let payload = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": (TEXT.len() + 10) as u64},
        ],
        "blocks": [
            {"block_id": "block-root", "kind": "root", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
        ],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(payload));
    assert!(error.to_string().contains("exceeds the text bytes"));
}

#[test]
fn structured_reading_rejects_non_char_boundary_offsets() {
    // "您" is three UTF-8 bytes; offset 1 splits a character.
    let text = "您吃竹子。";
    let payload = json!({
        "language": "zh-Hans",
        "text": text,
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 1, "end_offset": 6},
        ],
        "blocks": [
            {"block_id": "block-root", "kind": "root", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
        ],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(payload));
    assert!(error.to_string().contains("splits a character"));
}

#[test]
fn structured_reading_rejects_non_monotonic_anchor_order() {
    let payload = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [
            {"anchor_id": "anchor-2", "kind": "sentence", "start_offset": 20, "end_offset": TEXT.len() as u64},
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": 19},
        ],
        "blocks": [
            {"block_id": "block-root", "kind": "root", "order": 0, "span_anchor_ids": ["anchor-1", "anchor-2"], "parent_block_id": null},
        ],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(payload));
    assert!(
        error
            .to_string()
            .contains("anchor ranges must be in monotonic byte order")
    );
}

#[test]
fn structured_reading_block_cycle_is_rejected() {
    let cyclic = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": 19},
        ],
        "blocks": [
            {"block_id": "block-root", "kind": "root", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
            {"block_id": "block-1", "kind": "section", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": "block-2"},
            {"block_id": "block-2", "kind": "section", "order": 1, "span_anchor_ids": ["anchor-1"], "parent_block_id": "block-1"},
        ],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(cyclic));
    assert!(
        error
            .to_string()
            .contains("block hierarchy contains a cycle")
    );
}

#[test]
fn structured_reading_requires_exactly_one_root_block() {
    let no_root = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": 19},
        ],
        "blocks": [
            {"block_id": "block-1", "kind": "section", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
        ],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(no_root));
    assert!(
        error
            .to_string()
            .contains("must declare exactly one root block (found 0)")
    );
}

#[test]
fn structured_reading_rejects_non_contiguous_sibling_order() {
    let bad_order = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": 19},
        ],
        "blocks": [
            {"block_id": "block-root", "kind": "root", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
            {"block_id": "block-a", "kind": "section", "order": 2, "span_anchor_ids": ["anchor-1"], "parent_block_id": "block-root"},
        ],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(bad_order));
    assert!(
        error
            .to_string()
            .contains("sibling orders are not contiguous 0-based values")
    );
}

#[test]
fn structured_reading_unknown_block_kind_is_rejected() {
    let unknown_kind = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": 19},
        ],
        "blocks": [
            {"block_id": "block-1", "kind": "folio", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
        ],
        "spans": [],
        "document_mappings": [],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(unknown_kind));
    assert!(error.to_string().contains("unknown variant `folio`"));
}

#[test]
fn structured_reading_mapping_requires_a_declared_document_rendition() {
    let mapping = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": 19},
        ],
        "blocks": [
            {"block_id": "block-root", "kind": "root", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
        ],
        "spans": [],
        "document_mappings": [
            {"anchor_id": "anchor-1", "rendition_id": format!("sha256:{}", "a".repeat(64)), "locator": {"kind": "character_range", "value": "0:19"}},
        ],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(mapping));
    assert!(
        error
            .to_string()
            .contains("document mapping references undeclared rendition")
    );
}

#[test]
fn structured_reading_rejects_empty_locator_value() {
    let mapping = json!({
        "language": "en",
        "text": TEXT,
        "anchors": [
            {"anchor_id": "anchor-1", "kind": "sentence", "start_offset": 0, "end_offset": 19},
        ],
        "blocks": [
            {"block_id": "block-root", "kind": "root", "order": 0, "span_anchor_ids": ["anchor-1"], "parent_block_id": null},
        ],
        "spans": [],
        "document_mappings": [
            {"anchor_id": "anchor-1", "rendition_id": format!("sha256:{}", "a".repeat(64)), "locator": {"kind": "fragment", "value": ""}},
        ],
        "extensions": {},
    });
    let error = inspect_err(&structured_reading_carrier(mapping));
    assert!(
        error
            .to_string()
            .contains("document mapping locator value must not be empty")
    );
}

#[test]
fn anchor_time_alignment_requires_a_structured_reading_anchor_resource() {
    // A declared base resource that is not a structured reading may not be
    // the alignment's anchor resource.
    let (_, bytes, digest) = timed_text_payload("Pandas eat bamboo.");
    let timed_text_descriptor = base_descriptor(
        "timed_text_track",
        crate::v2::TIMED_TEXT_TRACK_SCHEMA_V2,
        "en",
        &[],
        &digest,
        bytes.len() as u64,
    );
    let timed_text_resource = resource_entry(&timed_text_descriptor, false);
    let timed_text_id = timed_text_resource["resource_id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (_, alignment, alignment_digest) =
        alignment_payload(&timed_text_id, &format!("sha256:{}", "c".repeat(64)));
    let alignment_descriptor = base_descriptor(
        "anchor_time_alignment",
        ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
        "en",
        &[],
        &alignment_digest,
        alignment.len() as u64,
    );
    let alignment_resource = resource_entry(&alignment_descriptor, false);
    let release = release_value(
        &[],
        vec![],
        vec![],
        vec![timed_text_resource, alignment_resource],
    );
    let error = inspect_err(&carrier(
        &release,
        &[
            (blob_path(&digest), bytes),
            (blob_path(&alignment_digest), alignment),
        ],
    ));
    assert!(
        error
            .to_string()
            .contains("anchor_resource_id must reference a structured_reading resource")
    );
}

#[test]
fn anchor_time_alignment_must_reference_a_media_rendition() {
    // A declared structured reading resource plus an alignment that names a
    // document rendition id instead of a media rendition id.
    let (document_release, document_blobs) = document_only_fixture();
    let document_id = document_release["document_renditions"][0]["rendition_id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (_, structured, structured_digest) = structured_payload(TEXT, Some(&document_id));
    let structured_descriptor = base_descriptor(
        "structured_reading",
        STRUCTURED_READING_SCHEMA_V1,
        "en",
        &[],
        &structured_digest,
        structured.len() as u64,
    );
    let structured_resource = resource_entry(&structured_descriptor, false);
    let structured_id = structured_resource["resource_id"]
        .as_str()
        .unwrap()
        .to_owned();
    let (_, alignment, alignment_digest) = alignment_payload(&structured_id, &document_id);
    let alignment_descriptor = base_descriptor(
        "anchor_time_alignment",
        ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
        "en",
        &[],
        &alignment_digest,
        alignment.len() as u64,
    );
    let alignment_resource = resource_entry(&alignment_descriptor, false);
    let release = release_value(
        &[],
        vec![document_release["document_renditions"][0].clone()],
        vec![],
        vec![structured_resource, alignment_resource],
    );
    let mut blobs = document_blobs;
    blobs.push((blob_path(&structured_digest), structured));
    blobs.push((blob_path(&alignment_digest), alignment));
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(
        error
            .to_string()
            .contains("references undeclared media rendition")
    );
}

#[test]
fn non_monotonic_alignment_is_rejected() {
    let embedded_bytes = b"listen fixture derived audio".to_vec();
    let embedded_digest = sha256_id(&embedded_bytes);
    let embedded_blob = blob_declaration(&embedded_digest, embedded_bytes.len() as u64, true);
    let media = media_rendition_value(
        "derived",
        "audio",
        "audio/mpeg",
        &embedded_blob,
        None,
        "fp-derived-1",
        media_extras(Some(&producer_value()), Some(&compatibility_value(None))),
    );
    let media_id = media["rendition_id"].as_str().unwrap().to_owned();
    let (_, structured, structured_digest) = structured_payload(TEXT, None);
    let structured_descriptor = base_descriptor(
        "structured_reading",
        STRUCTURED_READING_SCHEMA_V1,
        "en",
        &[],
        &structured_digest,
        structured.len() as u64,
    );
    let structured_resource = resource_entry(&structured_descriptor, false);
    let structured_id = structured_resource["resource_id"]
        .as_str()
        .unwrap()
        .to_owned();
    let payload = json!({
        "anchor_resource_id": structured_id,
        "rendition_id": media_id,
        "alignments": [
            {"anchor_id": "anchor-1", "media_time_ms": 1000},
            {"anchor_id": "anchor-2", "media_time_ms": 500},
        ],
        "extensions": {},
    });
    let bytes = serde_json::to_vec_pretty(&payload).unwrap();
    let alignment_digest = sha256_id(&bytes);
    let alignment_descriptor = base_descriptor(
        "anchor_time_alignment",
        ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
        "en",
        &[],
        &alignment_digest,
        bytes.len() as u64,
    );
    let alignment_resource = resource_entry(&alignment_descriptor, false);
    let release = release_value(
        &[],
        vec![],
        vec![media],
        vec![structured_resource, alignment_resource],
    );
    let error = inspect_err(&carrier(
        &release,
        &[
            (blob_path(&embedded_digest), embedded_bytes),
            (blob_path(&structured_digest), structured),
            (blob_path(&alignment_digest), bytes),
        ],
    ));
    assert!(
        error
            .to_string()
            .contains("alignment media times must be non-decreasing")
    );
}

#[test]
fn unknown_required_resource_is_incompatible() {
    let (mut release, blobs) = document_source_fixture();
    let descriptor = base_descriptor(
        UNKNOWN_KIND,
        UNKNOWN_SCHEMA,
        "en",
        &[],
        &format!("sha256:{}", "0".repeat(64)),
        1,
    );
    let resource = resource_entry(&descriptor, true);
    release["resources"].as_array_mut().unwrap().push(resource);
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(matches!(error, V3Error::Incompatible { .. }));
}

#[test]
fn dependency_cycle_is_rejected_through_the_graph_seam() {
    // A real cycle cannot be serialized: every dependency edge is a digest
    // inside an identity-bearing descriptor. The same bounded seam that the
    // inspector uses is exercised with synthetic graphs.
    let mut cyclic = HashMap::new();
    cyclic.insert("a".to_owned(), vec!["b".to_owned()]);
    cyclic.insert("b".to_owned(), vec!["a".to_owned()]);
    assert!(crate::v2::inspect::dependency_graph_has_cycle(&cyclic));
    let mut acyclic = HashMap::new();
    acyclic.insert("a".to_owned(), vec!["b".to_owned()]);
    acyclic.insert("b".to_owned(), vec!["c".to_owned()]);
    acyclic.insert("c".to_owned(), vec![]);
    acyclic.insert("d".to_owned(), vec![]);
    assert!(!crate::v2::inspect::dependency_graph_has_cycle(&acyclic));
}

#[test]
fn subject_must_reference_declared_renditions() {
    let (mut release, blobs) = document_source_fixture();
    let resources = release
        .get_mut("resources")
        .unwrap()
        .as_array_mut()
        .unwrap();
    let descriptor = resources[0].get_mut("descriptor").unwrap();
    descriptor["subject"]["rendition_ids"] = json!([format!("sha256:{}", "9".repeat(64))]);
    let new_id = sha256_id(&canonical_bytes(descriptor));
    resources[0]["resource_id"] = json!(new_id);
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(
        error
            .to_string()
            .contains("subject binds an undeclared rendition_id")
    );
}

#[test]
fn base_resource_cannot_reach_assistance_resource() {
    let (release, blobs) = composed_fixture();
    // Make the base structured reading resource depend on the translation
    // assistance resource: the direct edge is rejected.
    let translation_id = release["resources"]
        .as_array()
        .unwrap()
        .iter()
        .find(|entry| entry["descriptor"]["kind"] == "translation")
        .unwrap()["resource_id"]
        .clone();
    let mut release = release.clone();
    let resources = release
        .get_mut("resources")
        .unwrap()
        .as_array_mut()
        .unwrap();
    let structured_index = resources
        .iter()
        .position(|entry| entry["descriptor"]["kind"] == "structured_reading")
        .unwrap();
    let descriptor = resources[structured_index].get_mut("descriptor").unwrap();
    descriptor["dependencies"] = json!([{"resource_id": translation_id}]);
    resources[structured_index]["resource_id"] = json!(sha256_id(&canonical_bytes(descriptor)));
    let error = inspect_err(&carrier(&release, &blobs));
    assert!(
        error
            .to_string()
            .contains("base resource cannot depend on an assistance resource")
    );
}

#[test]
fn undeclared_carrier_file_is_rejected() {
    let (release, blobs) = document_source_fixture();
    let mut files = carrier(&release, &blobs);
    files.insert("secret.txt".to_owned(), b"not declared".to_vec());
    let error = inspect_err(&files);
    assert!(
        error
            .to_string()
            .contains("file is not declared by the release")
    );
}

#[test]
fn inventory_limits_are_enforced() {
    let (release, blobs) = media_only_fixture();
    let files = carrier(&release, &blobs);
    let limited = InspectLimits {
        max_file_count: 1,
        ..InspectLimits::default()
    };
    let directory = TestDirectory::new();
    write_tree(directory.path(), &files);
    let error = inspect_v3_path_with_limits(directory.path(), limited).unwrap_err();
    assert!(matches!(error, V3Error::Limit(_)));
}

#[test]
fn missing_release_is_rejected() {
    let directory = TestDirectory::new();
    fs::write(directory.path().join("other.txt"), b"x").unwrap();
    let error = inspect_v3_path(directory.path()).unwrap_err();
    assert!(matches!(error, V3Error::MissingRelease));
}

// ---------------------------------------------------------------------------
// Plan projection
// ---------------------------------------------------------------------------

#[test]
fn plan_projects_origins_and_producers() {
    let (release, blobs) = composed_fixture();
    let inspection = inspect_ok(&carrier(&release, &blobs));
    let plan = installation_plan_v3(&inspection);
    assert_eq!(plan.edition_id, "edition-fixture-v1");
    assert_eq!(plan.material_id, "material-fixture-v1");
    assert_eq!(plan.material_revision_id, MATERIAL_REVISION);
    assert_eq!(plan.warnings.len(), 1);
    let derived_document = plan
        .document_renditions
        .iter()
        .find(|rendition| rendition.origin == crate::v3::RenditionOrigin::Derived)
        .unwrap();
    assert_eq!(
        derived_document.producer.as_ref().unwrap().tool_id,
        "listen-gen"
    );
    let source_document = plan
        .document_renditions
        .iter()
        .find(|rendition| rendition.origin == crate::v3::RenditionOrigin::Source)
        .unwrap();
    assert!(source_document.producer.is_none());
    assert!(source_document.available);
}
