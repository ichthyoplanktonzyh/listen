use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{Value, json};
use sha2::{Digest as _, Sha256};
use zip::write::SimpleFileOptions;

use crate::inspect::validate_dependency_graph;
use crate::{PackageError, inspect_path};

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
            "listen-content-package-{process}-{sequence}-{nonce}"
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

fn example_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../contracts/content-package/v1/examples/minimal")
}

fn copy_example() -> TestDirectory {
    let output = TestDirectory::new();
    fs::create_dir(output.path().join("resources")).unwrap();
    fs::copy(
        example_path().join("manifest.json"),
        output.path().join("manifest.json"),
    )
    .unwrap();
    for entry in fs::read_dir(example_path().join("resources")).unwrap() {
        let entry = entry.unwrap();
        fs::copy(
            entry.path(),
            output.path().join("resources").join(entry.file_name()),
        )
        .unwrap();
    }
    output
}

fn package_files(root: &Path) -> BTreeMap<String, Vec<u8>> {
    let mut files = BTreeMap::new();
    files.insert(
        "manifest.json".to_owned(),
        fs::read(root.join("manifest.json")).unwrap(),
    );
    for entry in fs::read_dir(root.join("resources")).unwrap() {
        let entry = entry.unwrap();
        files.insert(
            format!("resources/{}", entry.file_name().to_string_lossy()),
            fs::read(entry.path()).unwrap(),
        );
    }
    files
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

fn sha256_id(bytes: &[u8]) -> String {
    format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
}

fn retain_subtitle_and_words(root: &Path) {
    let mut manifest: Value =
        serde_json::from_slice(&fs::read(root.join("manifest.json")).unwrap()).unwrap();
    manifest["resources"]
        .as_array_mut()
        .unwrap()
        .retain(|entry| {
            matches!(
                entry["kind"].as_str(),
                Some("subtitle_text_track" | "word_timeline")
            )
        });
    for entry in fs::read_dir(root.join("resources")).unwrap() {
        let entry = entry.unwrap();
        let name = entry.file_name();
        if name != "subtitle-text-track.json" && name != "word-timeline.json" {
            fs::remove_file(entry.path()).unwrap();
        }
    }
    fs::write(
        root.join("manifest.json"),
        serde_json::to_vec_pretty(&manifest).unwrap(),
    )
    .unwrap();
}

fn replace_resource(root: &Path, kind: &str, resource: &Value) {
    let mut manifest: Value =
        serde_json::from_slice(&fs::read(root.join("manifest.json")).unwrap()).unwrap();
    let descriptor = manifest["resources"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|entry| entry["kind"] == kind)
        .unwrap();
    let path = descriptor["path"].as_str().unwrap().to_owned();
    let bytes = serde_json::to_vec_pretty(resource).unwrap();
    descriptor["resource_id"] = json!(sha256_id(&bytes));
    descriptor["size_bytes"] = json!(bytes.len());
    fs::write(root.join(path), bytes).unwrap();
    fs::write(
        root.join("manifest.json"),
        serde_json::to_vec_pretty(&manifest).unwrap(),
    )
    .unwrap();
}

#[test]
fn canonical_example_exercises_all_six_typed_resources() {
    let inspected = inspect_path(example_path()).unwrap();
    assert_eq!(inspected.package.resources.len(), 6);
    assert!(inspected.package.opaque_resources.is_empty());
    assert!(inspected.package.manifest_sha256.starts_with("sha256:"));
}

#[test]
fn canonical_example_is_valid_as_listenpkg_zip() {
    let directory = TestDirectory::new();
    let path = write_zip(directory.path(), &package_files(&example_path()));
    assert_eq!(inspect_path(path).unwrap().package.resources.len(), 6);
}

#[test]
fn rejects_manifest_size_and_hash_mismatch() {
    let directory = copy_example();
    fs::OpenOptions::new()
        .append(true)
        .open(directory.path().join("resources/word-timeline.json"))
        .unwrap()
        .write_all(b" ")
        .unwrap();
    let error = inspect_path(directory.path()).unwrap_err();
    assert!(error.to_string().contains("size does not match"));
}

#[test]
fn rejects_invalid_word_anchor() {
    let directory = copy_example();
    retain_subtitle_and_words(directory.path());
    let path = directory.path().join("resources/word-timeline.json");
    let mut words: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    words["payload"]["words"][0]["token_index"] = json!(1);
    replace_resource(directory.path(), "word_timeline", &words);
    let error = inspect_path(directory.path()).unwrap_err();
    assert!(error.to_string().contains("word token"));
}

#[test]
fn rejects_out_of_range_confidence_and_empty_time_range() {
    for (field, value, expected) in [
        ("confidence", json!(1.1), "0..=1"),
        ("end_ms", json!(1040), "half-open"),
    ] {
        let directory = copy_example();
        retain_subtitle_and_words(directory.path());
        let path = directory.path().join("resources/word-timeline.json");
        let mut words: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
        words["payload"]["words"][0][field] = value;
        replace_resource(directory.path(), "word_timeline", &words);
        assert!(
            inspect_path(directory.path())
                .unwrap_err()
                .to_string()
                .contains(expected)
        );
    }
}

#[test]
fn preserves_optional_unknown_and_rejects_it_when_required() {
    for (required, should_pass) in [(false, true), (true, false)] {
        let directory = copy_example();
        let resource = json!({
            "schema": "listen.resource.future-analysis.v1",
            "kind": "future_analysis",
            "subject": {"media_fingerprint": format!("sha256:{}", "a".repeat(64))},
            "dependencies": [],
            "provenance": {
                "created_at_ms": 1,
                "tool": {"id": "future", "version": "1"}
            },
            "quality": {"review_status": "unreviewed"},
            "payload": {"future": true}
        });
        let bytes = serde_json::to_vec_pretty(&resource).unwrap();
        let path = "resources/future-analysis.json";
        fs::write(directory.path().join(path), &bytes).unwrap();
        let mut manifest: Value =
            serde_json::from_slice(&fs::read(directory.path().join("manifest.json")).unwrap())
                .unwrap();
        manifest["resources"].as_array_mut().unwrap().push(json!({
            "resource_id": sha256_id(&bytes), "path": path,
            "size_bytes": bytes.len(), "kind": "future_analysis",
            "schema": "listen.resource.future-analysis.v1", "required": required
        }));
        fs::write(
            directory.path().join("manifest.json"),
            serde_json::to_vec_pretty(&manifest).unwrap(),
        )
        .unwrap();
        let result = inspect_path(directory.path());
        if should_pass {
            assert_eq!(result.unwrap().package.opaque_resources.len(), 1);
        } else {
            assert!(
                result
                    .unwrap_err()
                    .to_string()
                    .contains("required resource")
            );
        }
    }
}

#[test]
fn rejects_dependency_kind_mismatch() {
    let directory = copy_example();
    retain_subtitle_and_words(directory.path());
    let path = directory.path().join("resources/word-timeline.json");
    let mut words: Value = serde_json::from_slice(&fs::read(&path).unwrap()).unwrap();
    words["dependencies"][0]["kind"] = json!("phone_timeline");
    replace_resource(directory.path(), "word_timeline", &words);
    let error = inspect_path(directory.path()).unwrap_err();
    assert!(error.to_string().contains("dependency kind"));
}

#[test]
fn rejects_zip_path_traversal_and_symlink() {
    for symlink in [false, true] {
        let directory = TestDirectory::new();
        let path = directory.path().join("unsafe.listenpkg");
        let mut writer = zip::ZipWriter::new(fs::File::create(&path).unwrap());
        if symlink {
            writer
                .add_symlink(
                    "manifest.json",
                    "elsewhere.json",
                    SimpleFileOptions::default(),
                )
                .unwrap();
        } else {
            writer
                .start_file("../manifest.json", SimpleFileOptions::default())
                .unwrap();
            writer.write_all(b"{}").unwrap();
        }
        writer.finish().unwrap();
        let error = inspect_path(path).unwrap_err();
        assert!(matches!(
            error,
            PackageError::UnsafePath(_) | PackageError::Symlink(_)
        ));
    }
}

#[cfg(unix)]
#[test]
fn rejects_directory_symlink() {
    use std::os::unix::fs::symlink;

    let directory = TestDirectory::new();
    fs::write(directory.path().join("outside.json"), b"{}").unwrap();
    symlink(
        directory.path().join("outside.json"),
        directory.path().join("manifest.json"),
    )
    .unwrap();
    assert!(matches!(
        inspect_path(directory.path()).unwrap_err(),
        PackageError::Symlink(_)
    ));
}

#[test]
fn rejects_closed_dependency_cycle() {
    let a = format!("sha256:{}", "aa".repeat(32));
    let b = format!("sha256:{}", "bb".repeat(32));
    let graph = HashMap::from([(a.clone(), vec![b.clone()]), (b, vec![a])]);
    assert!(
        validate_dependency_graph(&graph)
            .unwrap_err()
            .to_string()
            .contains("cycle")
    );
}
