use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{Cursor, Read};
use std::path::{Component, Path};

use sha2::{Digest as _, Sha256};
use thiserror::Error;

use crate::inspect::InspectLimits;

/// Errors produced while reading a package directory or ZIP carrier.
///
/// These are intentionally phrased identically to the v1 `PackageError`
/// archive variants so that both the v1 and v2 interfaces can map them
/// without changing user-visible messages.
#[derive(Debug, Error)]
pub(crate) enum ArchiveError {
    #[error("could not access package: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid ZIP package: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("package limit exceeded: {0}")]
    Limit(&'static str),
    #[error("invalid package entry path: {0}")]
    UnsafePath(String),
    #[error("symbolic links are not allowed in packages: {0}")]
    Symlink(String),
    #[error("duplicate package entry: {0}")]
    DuplicatePath(String),
    #[error("invalid package at {path}: {message}")]
    Invalid { path: String, message: String },
}

/// Reads every regular file of a directory tree or ZIP archive into memory,
/// enforcing the shared safety limits. Directory entries are ignored.
///
/// `manifest_names` lists the carrier files that receive the manifest size
/// limit instead of the ordinary per-file limit.
pub(crate) fn read_package(
    path: &Path,
    limits: InspectLimits,
    manifest_names: &[&str],
) -> Result<BTreeMap<String, Vec<u8>>, ArchiveError> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() {
        return Err(ArchiveError::Symlink(path.display().to_string()));
    }
    if metadata.is_dir() {
        read_directory(path, limits, manifest_names)
    } else {
        read_zip(path, limits, manifest_names)
    }
}

fn read_directory(
    root: &Path,
    limits: InspectLimits,
    manifest_names: &[&str],
) -> Result<BTreeMap<String, Vec<u8>>, ArchiveError> {
    let mut pending = vec![root.to_path_buf()];
    let mut files = BTreeMap::new();
    let mut total = 0_u64;
    while let Some(directory) = pending.pop() {
        for entry in fs::read_dir(&directory)? {
            let entry = entry?;
            let metadata = fs::symlink_metadata(entry.path())?;
            let relative = entry
                .path()
                .strip_prefix(root)
                .map_err(|_| invalid("package", "entry escaped package root"))?
                .to_path_buf();
            let name = safe_path_string(&relative)?;
            if metadata.file_type().is_symlink() {
                return Err(ArchiveError::Symlink(name));
            }
            if metadata.is_dir() {
                pending.push(entry.path());
                continue;
            }
            if !metadata.is_file() {
                return Err(invalid(&name, "entry is not a regular file"));
            }
            enforce_file_limits(
                &name,
                metadata.len(),
                &mut total,
                files.len(),
                limits,
                manifest_names,
            )?;
            let bytes = fs::read(entry.path())?;
            if files.insert(name.clone(), bytes).is_some() {
                return Err(ArchiveError::DuplicatePath(name));
            }
        }
    }
    Ok(files)
}

fn read_zip(
    path: &Path,
    limits: InspectLimits,
    manifest_names: &[&str],
) -> Result<BTreeMap<String, Vec<u8>>, ArchiveError> {
    if fs::metadata(path)?.len() > limits.max_total_bytes {
        return Err(ArchiveError::Limit("ZIP file size"));
    }
    let bytes = fs::read(path)?;
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes))?;
    // Preserve the legacy v1 archive-entry bound before skipping directory
    // entries. A carrier with thousands of empty directories must not bypass
    // `max_file_count` merely because it has few regular files.
    if archive.len() > limits.max_file_count {
        return Err(ArchiveError::Limit("ZIP entry count"));
    }
    let mut files = BTreeMap::new();
    let mut total = 0_u64;
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        let raw_name = entry.name().to_owned();
        let enclosed = entry
            .enclosed_name()
            .ok_or_else(|| ArchiveError::UnsafePath(raw_name.clone()))?;
        let name = safe_path_string(&enclosed)?;
        if entry.is_symlink() {
            return Err(ArchiveError::Symlink(name));
        }
        if entry.is_dir() {
            continue;
        }
        enforce_file_limits(
            &name,
            entry.size(),
            &mut total,
            files.len(),
            limits,
            manifest_names,
        )?;
        let capacity =
            usize::try_from(entry.size()).map_err(|_| ArchiveError::Limit("file size"))?;
        let mut contents = Vec::with_capacity(capacity);
        entry
            .by_ref()
            .take(limits.max_file_bytes.saturating_add(1))
            .read_to_end(&mut contents)?;
        if contents.len() as u64 != entry.size() {
            return Err(invalid(
                &name,
                "ZIP entry size does not match decompressed bytes",
            ));
        }
        if files.insert(name.clone(), contents).is_some() {
            return Err(ArchiveError::DuplicatePath(name));
        }
    }
    Ok(files)
}

fn enforce_file_limits(
    name: &str,
    size: u64,
    total: &mut u64,
    current_count: usize,
    limits: InspectLimits,
    manifest_names: &[&str],
) -> Result<(), ArchiveError> {
    if current_count >= limits.max_file_count {
        return Err(ArchiveError::Limit("file count"));
    }
    let maximum = if manifest_names.contains(&name) {
        limits.max_manifest_bytes
    } else {
        limits.max_file_bytes
    };
    if size > maximum {
        return Err(ArchiveError::Limit("file size"));
    }
    *total = total
        .checked_add(size)
        .ok_or(ArchiveError::Limit("total decompressed size"))?;
    if *total > limits.max_total_bytes {
        return Err(ArchiveError::Limit("total decompressed size"));
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// v2 bounded archive APIs (crate-private; consumed by the v2 inspection).
// They share the v1 safety checks but never read ordinary bodies up front and
// never materialize streamed bodies at all.
// ---------------------------------------------------------------------------

/// Per-file size-limit class applied to a single package entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FileLimit {
    /// Control file: bounded by `max_manifest_bytes` and retained.
    Manifest,
    /// Ordinary file: bounded by `max_file_bytes` and retained.
    Ordinary,
    /// Cataloged or streamed entry: no per-file bound, only the shared total.
    None,
}

/// A single non-directory entry discovered by the catalog pass.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CatalogEntry {
    /// Safe forward-slash path within the package.
    pub name: String,
    /// Exact size in bytes reported by the carrier metadata.
    pub size: u64,
}

/// Result of the safe catalog/control pass: retained control documents plus a
/// name/size catalog of every non-directory entry.
#[derive(Debug, Clone)]
pub(crate) struct PackageCatalog {
    /// Retained control-file bodies keyed by safe entry name.
    pub controls: BTreeMap<String, Vec<u8>>,
    /// Every non-directory entry, sorted by name.
    pub entries: Vec<CatalogEntry>,
    /// Sum of every non-directory entry size.
    pub total_bytes: u64,
}

/// Fact about a body that was read and hashed but not retained.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct StreamedFile {
    /// Safe forward-slash path within the package.
    pub name: String,
    /// Observed byte count, equal to the carrier-declared size.
    pub size: u64,
    /// `sha256:` followed by the lowercase hex digest of the body.
    pub sha256: String,
}

/// Result of the selective content pass: retained control and ordinary bodies
/// plus size/digest facts for streamed entries.
#[derive(Debug, Clone)]
pub(crate) struct SelectivePackage {
    /// Retained control and ordinary bodies keyed by safe entry name.
    pub files: BTreeMap<String, Vec<u8>>,
    /// Facts for streamed entries, sorted by name; bodies are never retained.
    pub streamed: Vec<StreamedFile>,
    /// Sum of every non-directory entry size (retained and streamed).
    pub total_bytes: u64,
}

/// Reads the control files of a directory tree or ZIP carrier and catalogs
/// every non-directory entry, without reading ordinary file bodies.
///
/// `control_names` lists the carrier files that are read and returned,
/// bounded by `max_manifest_bytes`; every other non-directory entry is only
/// cataloged (safe name and exact size) and never opened.
///
/// Used by the v2 inspection's catalog pass.
pub(crate) fn read_package_controls(
    path: &Path,
    limits: InspectLimits,
    control_names: &[&str],
) -> Result<PackageCatalog, ArchiveError> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() {
        return Err(ArchiveError::Symlink(path.display().to_string()));
    }
    if metadata.is_dir() {
        catalog_directory(path, limits, control_names)
    } else {
        catalog_zip(path, limits, control_names)
    }
}

/// Reads the control and ordinary files of a directory tree or ZIP carrier,
/// retaining them in memory, and hashes the entries named in `streamed_paths`
/// without retaining their bodies.
///
/// Every non-directory entry receives the shared safety, duplicate, count,
/// and total checks. Control files are bounded by `max_manifest_bytes`,
/// ordinary files by `max_file_bytes`; entries named exactly in
/// `streamed_paths` may exceed `max_file_bytes` but never `max_total_bytes`.
///
/// Used by the v2 inspection's selective pass.
pub(crate) fn read_package_selective(
    path: &Path,
    limits: InspectLimits,
    control_names: &[&str],
    streamed_paths: &[&str],
) -> Result<SelectivePackage, ArchiveError> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() {
        return Err(ArchiveError::Symlink(path.display().to_string()));
    }
    if metadata.is_dir() {
        selective_directory(path, limits, control_names, streamed_paths)
    } else {
        selective_zip(path, limits, control_names, streamed_paths)
    }
}

fn catalog_directory(
    root: &Path,
    limits: InspectLimits,
    control_names: &[&str],
) -> Result<PackageCatalog, ArchiveError> {
    let mut controls = BTreeMap::new();
    let mut entry_sizes = BTreeMap::new();
    let mut seen = BTreeSet::new();
    let mut total = 0_u64;
    walk_directory(root, |name, file_path, size| {
        let limit_class = catalog_limit_class(name, control_names);
        check_entry_limits(size, seen.len(), &mut total, limits, limit_class)?;
        if !seen.insert(name.to_owned()) {
            return Err(ArchiveError::DuplicatePath(name.to_owned()));
        }
        if limit_class == FileLimit::Manifest {
            controls.insert(
                name.to_owned(),
                read_bounded_file(name, file_path, size, limits.max_manifest_bytes)?,
            );
        }
        entry_sizes.insert(name.to_owned(), size);
        Ok(())
    })?;
    let entries = entry_sizes
        .into_iter()
        .map(|(name, size)| CatalogEntry { name, size })
        .collect();
    Ok(PackageCatalog {
        controls,
        entries,
        total_bytes: total,
    })
}

fn catalog_zip(
    path: &Path,
    limits: InspectLimits,
    control_names: &[&str],
) -> Result<PackageCatalog, ArchiveError> {
    let mut controls = BTreeMap::new();
    let mut entry_sizes = BTreeMap::new();
    let mut seen = BTreeSet::new();
    let mut total = 0_u64;
    walk_zip(path, limits, |name, size, entry| {
        let limit_class = catalog_limit_class(name, control_names);
        check_entry_limits(size, seen.len(), &mut total, limits, limit_class)?;
        if !seen.insert(name.to_owned()) {
            return Err(ArchiveError::DuplicatePath(name.to_owned()));
        }
        if limit_class == FileLimit::Manifest {
            controls.insert(
                name.to_owned(),
                read_bounded_zip_entry(name, size, entry, limits.max_manifest_bytes)?,
            );
        }
        entry_sizes.insert(name.to_owned(), size);
        Ok(())
    })?;
    let entries = entry_sizes
        .into_iter()
        .map(|(name, size)| CatalogEntry { name, size })
        .collect();
    Ok(PackageCatalog {
        controls,
        entries,
        total_bytes: total,
    })
}

fn selective_directory(
    root: &Path,
    limits: InspectLimits,
    control_names: &[&str],
    streamed_paths: &[&str],
) -> Result<SelectivePackage, ArchiveError> {
    let mut files = BTreeMap::new();
    let mut streamed = Vec::new();
    let mut seen = BTreeSet::new();
    let mut total = 0_u64;
    walk_directory(root, |name, file_path, size| {
        let limit_class = selective_limit_class(name, control_names, streamed_paths);
        check_entry_limits(size, seen.len(), &mut total, limits, limit_class)?;
        if !seen.insert(name.to_owned()) {
            return Err(ArchiveError::DuplicatePath(name.to_owned()));
        }
        if limit_class == FileLimit::None {
            streamed.push(stream_directory_file(name, file_path, size, limits)?);
        } else {
            let limit = if control_names.contains(&name) {
                limits.max_manifest_bytes
            } else {
                limits.max_file_bytes
            };
            files.insert(
                name.to_owned(),
                read_bounded_file(name, file_path, size, limit)?,
            );
        }
        Ok(())
    })?;
    streamed.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(SelectivePackage {
        files,
        streamed,
        total_bytes: total,
    })
}

fn selective_zip(
    path: &Path,
    limits: InspectLimits,
    control_names: &[&str],
    streamed_paths: &[&str],
) -> Result<SelectivePackage, ArchiveError> {
    let mut files = BTreeMap::new();
    let mut streamed = Vec::new();
    let mut seen = BTreeSet::new();
    let mut total = 0_u64;
    walk_zip(path, limits, |name, size, entry| {
        let limit_class = selective_limit_class(name, control_names, streamed_paths);
        check_entry_limits(size, seen.len(), &mut total, limits, limit_class)?;
        if !seen.insert(name.to_owned()) {
            return Err(ArchiveError::DuplicatePath(name.to_owned()));
        }
        if limit_class == FileLimit::None {
            streamed.push(stream_zip_entry(name, size, entry, limits)?);
        } else {
            let limit = if control_names.contains(&name) {
                limits.max_manifest_bytes
            } else {
                limits.max_file_bytes
            };
            files.insert(
                name.to_owned(),
                read_bounded_zip_entry(name, size, entry, limit)?,
            );
        }
        Ok(())
    })?;
    streamed.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(SelectivePackage {
        files,
        streamed,
        total_bytes: total,
    })
}

/// Reads one directory file up to `limit` bytes and verifies the observed
/// length still equals the size captured by the metadata pass, so the
/// reported entry size never contradicts the retained bytes.
fn read_bounded_file(
    name: &str,
    file_path: &Path,
    declared: u64,
    limit: u64,
) -> Result<Vec<u8>, ArchiveError> {
    let mut contents = Vec::new();
    fs::File::open(file_path)?
        .take(limit.saturating_add(1))
        .read_to_end(&mut contents)?;
    if contents.len() as u64 != declared {
        return Err(invalid(name, "file size changed while reading"));
    }
    Ok(contents)
}

/// Reads one ZIP entry up to `limit` bytes and verifies the observed length
/// equals the central-directory size, mirroring the v1 mismatch check.
fn read_bounded_zip_entry(
    name: &str,
    declared: u64,
    entry: &mut zip::read::ZipFile<'_, fs::File>,
    limit: u64,
) -> Result<Vec<u8>, ArchiveError> {
    let capacity = usize::try_from(declared).map_err(|_| ArchiveError::Limit("file size"))?;
    let mut contents = Vec::with_capacity(capacity);
    entry
        .by_ref()
        .take(limit.saturating_add(1))
        .read_to_end(&mut contents)?;
    if contents.len() as u64 != declared {
        return Err(invalid(
            name,
            "ZIP entry size does not match decompressed bytes",
        ));
    }
    Ok(contents)
}

/// Streams one directory file in bounded chunks, accumulating SHA-256 and the
/// observed byte count, never retaining the body.
fn stream_directory_file(
    name: &str,
    file_path: &Path,
    declared: u64,
    limits: InspectLimits,
) -> Result<StreamedFile, ArchiveError> {
    let mut hasher = Sha256::new();
    let mut observed = 0_u64;
    let mut buffer = [0_u8; 64 * 1024];
    let mut reader = fs::File::open(file_path)?.take(limits.max_total_bytes.saturating_add(1));
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        observed += read as u64;
        hasher.update(&buffer[..read]);
    }
    if observed > limits.max_total_bytes {
        return Err(ArchiveError::Limit("total decompressed size"));
    }
    if observed != declared {
        return Err(invalid(name, "file size changed while reading"));
    }
    Ok(StreamedFile {
        name: name.to_owned(),
        size: observed,
        sha256: format!("sha256:{}", hex::encode(hasher.finalize())),
    })
}

/// Streams one ZIP entry in bounded chunks, accumulating SHA-256 and the
/// observed byte count, never retaining the body.
fn stream_zip_entry(
    name: &str,
    declared: u64,
    entry: &mut zip::read::ZipFile<'_, fs::File>,
    limits: InspectLimits,
) -> Result<StreamedFile, ArchiveError> {
    let mut hasher = Sha256::new();
    let mut observed = 0_u64;
    let mut buffer = [0_u8; 64 * 1024];
    let mut reader = entry
        .by_ref()
        .take(limits.max_total_bytes.saturating_add(1));
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        observed += read as u64;
        hasher.update(&buffer[..read]);
    }
    if observed > limits.max_total_bytes {
        return Err(ArchiveError::Limit("total decompressed size"));
    }
    if observed != declared {
        return Err(invalid(
            name,
            "ZIP entry size does not match decompressed bytes",
        ));
    }
    Ok(StreamedFile {
        name: name.to_owned(),
        size: observed,
        sha256: format!("sha256:{}", hex::encode(hasher.finalize())),
    })
}

/// Shared per-entry checks for the v2 passes: entry count, per-file size
/// limit class, and the running total decompressed size.
fn check_entry_limits(
    size: u64,
    count: usize,
    total: &mut u64,
    limits: InspectLimits,
    limit_class: FileLimit,
) -> Result<(), ArchiveError> {
    if count >= limits.max_file_count {
        return Err(ArchiveError::Limit("file count"));
    }
    let maximum = match limit_class {
        FileLimit::Manifest => Some(limits.max_manifest_bytes),
        FileLimit::Ordinary => Some(limits.max_file_bytes),
        FileLimit::None => None,
    };
    if let Some(maximum) = maximum
        && size > maximum
    {
        return Err(ArchiveError::Limit("file size"));
    }
    *total = total
        .checked_add(size)
        .ok_or(ArchiveError::Limit("total decompressed size"))?;
    if *total > limits.max_total_bytes {
        return Err(ArchiveError::Limit("total decompressed size"));
    }
    Ok(())
}

/// Size-limit class for the catalog pass: control files are bounded by the
/// manifest limit, everything else is only cataloged and has no per-file
/// bound beyond the shared total.
fn catalog_limit_class(name: &str, control_names: &[&str]) -> FileLimit {
    if control_names.contains(&name) {
        FileLimit::Manifest
    } else {
        FileLimit::None
    }
}

/// Size-limit class for the selective pass: streamed entries have no per-file
/// bound, control files use the manifest bound, everything else the file
/// bound.
fn selective_limit_class(name: &str, control_names: &[&str], streamed_paths: &[&str]) -> FileLimit {
    if streamed_paths.contains(&name) {
        FileLimit::None
    } else if control_names.contains(&name) {
        FileLimit::Manifest
    } else {
        FileLimit::Ordinary
    }
}

/// Walks a directory tree, yielding every non-directory regular file with its
/// safe name, path, and metadata size. Rejects symlinks and non-regular
/// entries with the same errors as the v1 reader.
fn walk_directory<F>(root: &Path, mut on_file: F) -> Result<(), ArchiveError>
where
    F: FnMut(&str, &Path, u64) -> Result<(), ArchiveError>,
{
    let mut pending = vec![root.to_path_buf()];
    while let Some(directory) = pending.pop() {
        for entry in fs::read_dir(&directory)? {
            let entry = entry?;
            let metadata = fs::symlink_metadata(entry.path())?;
            let relative = entry
                .path()
                .strip_prefix(root)
                .map_err(|_| invalid("package", "entry escaped package root"))?
                .to_path_buf();
            let name = safe_path_string(&relative)?;
            if metadata.file_type().is_symlink() {
                return Err(ArchiveError::Symlink(name));
            }
            if metadata.is_dir() {
                pending.push(entry.path());
                continue;
            }
            if !metadata.is_file() {
                return Err(invalid(&name, "entry is not a regular file"));
            }
            on_file(&name, &entry.path(), metadata.len())?;
        }
    }
    Ok(())
}

/// Iterates a ZIP archive's entries without reading the whole carrier,
/// yielding every non-directory entry with its safe name, central-directory
/// size, and a borrow of the entry body. Rejects symlinks, unsafe names, and
/// compressed carriers larger than `max_total_bytes`, as the v1 reader does.
fn walk_zip<F>(path: &Path, limits: InspectLimits, mut on_entry: F) -> Result<(), ArchiveError>
where
    F: for<'a> FnMut(&str, u64, &mut zip::read::ZipFile<'a, fs::File>) -> Result<(), ArchiveError>,
{
    if fs::metadata(path)?.len() > limits.max_total_bytes {
        return Err(ArchiveError::Limit("ZIP file size"));
    }
    let file = fs::File::open(path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    // Bound every central-directory entry before filtering out directory
    // records, matching the v1 reader and keeping v2's two passes bounded.
    if archive.len() > limits.max_file_count {
        return Err(ArchiveError::Limit("ZIP entry count"));
    }
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        let raw_name = entry.name().to_owned();
        let enclosed = entry
            .enclosed_name()
            .ok_or_else(|| ArchiveError::UnsafePath(raw_name.clone()))?;
        let name = safe_path_string(&enclosed)?;
        if entry.is_symlink() {
            return Err(ArchiveError::Symlink(name));
        }
        if entry.is_dir() {
            continue;
        }
        on_entry(&name, entry.size(), &mut entry)?;
    }
    Ok(())
}

/// Converts a relative package path into a safe forward-slash string.
///
/// Rejects absolute paths, empty paths, parent/root components, backslashes,
/// colons, and control characters.
pub(crate) fn safe_path_string(path: &Path) -> Result<String, ArchiveError> {
    if path.as_os_str().is_empty() || path.is_absolute() {
        return Err(ArchiveError::UnsafePath(path.display().to_string()));
    }
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let part = part
                    .to_str()
                    .ok_or_else(|| ArchiveError::UnsafePath(path.display().to_string()))?;
                if part.contains('\\') || part.contains(':') || part.chars().any(char::is_control) {
                    return Err(ArchiveError::UnsafePath(path.display().to_string()));
                }
                parts.push(part);
            }
            _ => return Err(ArchiveError::UnsafePath(path.display().to_string())),
        }
    }
    Ok(parts.join("/"))
}

fn invalid(path: impl Into<String>, message: impl Into<String>) -> ArchiveError {
    ArchiveError::Invalid {
        path: path.into(),
        message: message.into(),
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::io::Write;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use sha2::{Digest as _, Sha256};
    use zip::write::SimpleFileOptions;

    use super::*;
    use crate::inspect::InspectLimits;

    /// Unique scratch directory removed on drop.
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
                "listen-content-package-archive-{}-{}-{}",
                std::process::id(),
                sequence,
                nonce
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

    /// Limits that make ordinary files tiny so streamed entries clearly exceed
    /// `max_file_bytes` while still fitting under `max_total_bytes`.
    fn tiny_limits() -> InspectLimits {
        InspectLimits {
            max_file_count: 64,
            max_file_bytes: 16,
            max_manifest_bytes: 64,
            max_total_bytes: 512,
        }
    }

    fn write_zip(dir: &Path, files: &[(&str, &[u8])]) -> PathBuf {
        let zip_path = dir.join("package.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        let options = SimpleFileOptions::default();
        for (name, bytes) in files {
            archive.start_file(*name, options).unwrap();
            archive.write_all(bytes).unwrap();
        }
        archive.finish().unwrap();
        zip_path
    }

    fn sha256_id(bytes: &[u8]) -> String {
        format!("sha256:{}", hex::encode(Sha256::digest(bytes)))
    }

    /// Minimal raw ZIP writer used to build carriers the crate's own writer
    /// refuses to produce (duplicate entry names). Entries are STORED and the
    /// standard CRC-32 is computed inline.
    fn write_raw_zip(dir: &Path, files: &[(&str, &[u8])]) -> PathBuf {
        fn crc32(bytes: &[u8]) -> u32 {
            let mut crc = 0xFFFF_FFFF_u32;
            for &byte in bytes {
                crc ^= byte as u32;
                for _ in 0..8 {
                    let mask = (crc & 1).wrapping_neg();
                    crc = (crc >> 1) ^ (0xEDB8_8320 & mask);
                }
            }
            !crc
        }

        let mut body = Vec::new();
        let mut local_offsets = Vec::new();
        for (name, bytes) in files {
            local_offsets.push(body.len() as u32);
            let name_bytes = name.as_bytes();
            let crc = crc32(bytes);
            body.extend_from_slice(&0x0403_4b50_u32.to_le_bytes()); // local header
            body.extend_from_slice(&20_u16.to_le_bytes()); // version needed
            body.extend_from_slice(&0_u16.to_le_bytes()); // flags
            body.extend_from_slice(&0_u16.to_le_bytes()); // stored method
            body.extend_from_slice(&0_u16.to_le_bytes()); // mod time
            body.extend_from_slice(&0_u16.to_le_bytes()); // mod date
            body.extend_from_slice(&crc.to_le_bytes());
            body.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
            body.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
            body.extend_from_slice(&(name_bytes.len() as u16).to_le_bytes());
            body.extend_from_slice(&0_u16.to_le_bytes()); // extra length
            body.extend_from_slice(name_bytes);
            body.extend_from_slice(bytes);
        }
        let central_offset = body.len() as u32;
        let mut central = Vec::new();
        for (index, (name, bytes)) in files.iter().enumerate() {
            let name_bytes = name.as_bytes();
            let crc = crc32(bytes);
            central.extend_from_slice(&0x0201_4b50_u32.to_le_bytes()); // central header
            central.extend_from_slice(&20_u16.to_le_bytes()); // version made by
            central.extend_from_slice(&20_u16.to_le_bytes()); // version needed
            central.extend_from_slice(&0_u16.to_le_bytes()); // flags
            central.extend_from_slice(&0_u16.to_le_bytes()); // stored method
            central.extend_from_slice(&0_u16.to_le_bytes()); // mod time
            central.extend_from_slice(&0_u16.to_le_bytes()); // mod date
            central.extend_from_slice(&crc.to_le_bytes());
            central.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
            central.extend_from_slice(&(bytes.len() as u32).to_le_bytes());
            central.extend_from_slice(&(name_bytes.len() as u16).to_le_bytes());
            central.extend_from_slice(&0_u16.to_le_bytes()); // extra length
            central.extend_from_slice(&0_u16.to_le_bytes()); // comment length
            central.extend_from_slice(&0_u16.to_le_bytes()); // disk number
            central.extend_from_slice(&0_u16.to_le_bytes()); // internal attrs
            central.extend_from_slice(&0_u32.to_le_bytes()); // external attrs
            central.extend_from_slice(&local_offsets[index].to_le_bytes());
            central.extend_from_slice(name_bytes);
        }
        let mut eocd = Vec::new();
        eocd.extend_from_slice(&0x0605_4b50_u32.to_le_bytes()); // end of central dir
        eocd.extend_from_slice(&0_u16.to_le_bytes()); // disk number
        eocd.extend_from_slice(&0_u16.to_le_bytes()); // disk with central dir
        eocd.extend_from_slice(&(files.len() as u16).to_le_bytes());
        eocd.extend_from_slice(&(files.len() as u16).to_le_bytes());
        eocd.extend_from_slice(&(central.len() as u32).to_le_bytes());
        eocd.extend_from_slice(&central_offset.to_le_bytes());
        eocd.extend_from_slice(&0_u16.to_le_bytes()); // comment length

        let zip_path = dir.join("package.zip");
        let mut bytes = Vec::with_capacity(body.len() + central.len() + eocd.len());
        bytes.extend_from_slice(&body);
        bytes.extend_from_slice(&central);
        bytes.extend_from_slice(&eocd);
        fs::write(&zip_path, bytes).unwrap();
        zip_path
    }

    #[test]
    fn directory_streamed_entry_exceeds_file_limit_and_is_hashed_not_retained() {
        let dir = TestDirectory::new();
        let payload = vec![b'x'; 64];
        fs::write(dir.path().join("big.bin"), &payload).unwrap();
        fs::write(dir.path().join("small.txt"), b"hello").unwrap();

        let limits = tiny_limits();
        let result =
            read_package_selective(dir.path(), limits, &["manifest.json"], &["big.bin"]).unwrap();

        assert_eq!(result.total_bytes, 64 + 5);
        assert_eq!(result.files["small.txt"], b"hello");
        assert!(!result.files.contains_key("big.bin"));
        assert_eq!(result.streamed.len(), 1);
        assert_eq!(result.streamed[0].name, "big.bin");
        assert_eq!(result.streamed[0].size, 64);
        assert_eq!(result.streamed[0].sha256, sha256_id(&payload));
    }

    #[test]
    fn absent_streamed_path_is_omitted_not_an_error() {
        let dir = TestDirectory::new();
        fs::write(dir.path().join("small.txt"), b"hello").unwrap();

        let limits = tiny_limits();
        let result = read_package_selective(dir.path(), limits, &[], &["missing.bin"]).unwrap();

        assert_eq!(result.files["small.txt"], b"hello");
        assert!(result.streamed.is_empty());
        assert_eq!(result.total_bytes, 5);
    }

    #[test]
    fn zip_streamed_entry_exceeds_file_limit_and_is_hashed_not_retained() {
        let dir = TestDirectory::new();
        let payload = vec![b'z'; 64];
        let zip_path = write_zip(
            dir.path(),
            &[("big.bin", &payload), ("small.txt", b"hello")],
        );

        let limits = tiny_limits();
        let result =
            read_package_selective(&zip_path, limits, &["manifest.json"], &["big.bin"]).unwrap();

        assert_eq!(result.total_bytes, 64 + 5);
        assert_eq!(result.files["small.txt"], b"hello");
        assert!(!result.files.contains_key("big.bin"));
        assert_eq!(result.streamed.len(), 1);
        assert_eq!(result.streamed[0].name, "big.bin");
        assert_eq!(result.streamed[0].size, 64);
        assert_eq!(result.streamed[0].sha256, sha256_id(&payload));
    }

    #[test]
    fn zip_directory_entries_count_toward_the_shared_entry_limit() {
        let dir = TestDirectory::new();
        let zip_path = dir.path().join("directory-heavy.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut archive = zip::ZipWriter::new(file);
        let options = SimpleFileOptions::default();
        archive.add_directory("one/", options).unwrap();
        archive.add_directory("two/", options).unwrap();
        archive.start_file("payload.bin", options).unwrap();
        archive.write_all(b"payload").unwrap();
        archive.finish().unwrap();

        // There is only one regular file but three central-directory entries.
        // The legacy v1 reader counted all three before this archive module
        // was extracted, and both v2 passes need the same bounded behavior.
        let limits = InspectLimits {
            max_file_count: 2,
            ..tiny_limits()
        };
        for result in [
            read_package(&zip_path, limits, &[]).map(|_| ()),
            read_package_controls(&zip_path, limits, &[]).map(|_| ()),
            read_package_selective(&zip_path, limits, &[], &[]).map(|_| ()),
        ] {
            assert!(matches!(
                result,
                Err(ArchiveError::Limit("ZIP entry count"))
            ));
        }
    }

    #[test]
    fn directory_unselected_oversized_entry_fails_file_limit() {
        let dir = TestDirectory::new();
        fs::write(dir.path().join("big.bin"), vec![b'x'; 64]).unwrap();

        let limits = tiny_limits();
        let err = read_package_selective(dir.path(), limits, &[], &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::Limit("file size")));
    }

    #[test]
    fn zip_unselected_oversized_entry_fails_file_limit() {
        let dir = TestDirectory::new();
        let payload = vec![b'x'; 64];
        let zip_path = write_zip(dir.path(), &[("big.bin", &payload)]);

        let limits = tiny_limits();
        let err = read_package_selective(&zip_path, limits, &[], &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::Limit("file size")));
    }

    #[test]
    fn directory_streamed_entry_over_total_fails_total_limit() {
        let dir = TestDirectory::new();
        fs::write(dir.path().join("huge.bin"), vec![b'h'; 600]).unwrap();

        let limits = tiny_limits();
        let err = read_package_selective(dir.path(), limits, &[], &["huge.bin"]).unwrap_err();
        assert!(matches!(
            err,
            ArchiveError::Limit("total decompressed size")
        ));
    }

    #[test]
    fn zip_streamed_entry_over_total_fails_total_limit() {
        let dir = TestDirectory::new();
        let payload = vec![b'h'; 600];
        let zip_path = write_zip(dir.path(), &[("huge.bin", &payload)]);

        let limits = tiny_limits();
        let err = read_package_selective(&zip_path, limits, &[], &["huge.bin"]).unwrap_err();
        assert!(matches!(
            err,
            ArchiveError::Limit("total decompressed size")
        ));
    }

    #[test]
    fn control_pass_enforces_total_limit() {
        let dir = TestDirectory::new();
        for index in 0..40 {
            fs::write(
                dir.path().join(format!("part-{index:02}.bin")),
                vec![b'p'; 16],
            )
            .unwrap();
        }

        // 40 * 16 = 640 > max_total_bytes (512), with the count (40) below
        // max_file_count (64), so only the total limit can fire.
        let limits = tiny_limits();
        let err = read_package_controls(dir.path(), limits, &[]).unwrap_err();
        assert!(matches!(
            err,
            ArchiveError::Limit("total decompressed size")
        ));
    }

    #[test]
    fn directory_controls_retained_with_manifest_limit() {
        let dir = TestDirectory::new();
        let manifest = vec![b'm'; 40]; // > max_file_bytes (16), <= max_manifest_bytes (64)
        fs::write(dir.path().join("manifest.json"), &manifest).unwrap();
        fs::write(dir.path().join("payload.bin"), b"payload").unwrap();

        let limits = tiny_limits();
        let catalog = read_package_controls(dir.path(), limits, &["manifest.json"]).unwrap();
        assert_eq!(catalog.controls["manifest.json"], manifest);
        assert_eq!(catalog.total_bytes, 40 + 7);
        assert_eq!(
            catalog.entries,
            vec![
                CatalogEntry {
                    name: "manifest.json".into(),
                    size: 40,
                },
                CatalogEntry {
                    name: "payload.bin".into(),
                    size: 7,
                },
            ]
        );

        let selective =
            read_package_selective(dir.path(), limits, &["manifest.json"], &[]).unwrap();
        assert_eq!(selective.files["manifest.json"], manifest);
        assert_eq!(selective.files["payload.bin"], b"payload");
        assert!(selective.streamed.is_empty());
        assert_eq!(selective.total_bytes, 47);
    }

    #[test]
    fn zip_controls_retained_with_manifest_limit() {
        let dir = TestDirectory::new();
        let manifest = vec![b'm'; 40];
        let zip_path = write_zip(
            dir.path(),
            &[("manifest.json", &manifest), ("payload.bin", b"payload")],
        );

        let limits = tiny_limits();
        let catalog = read_package_controls(&zip_path, limits, &["manifest.json"]).unwrap();
        assert_eq!(catalog.controls["manifest.json"], manifest);
        assert_eq!(catalog.total_bytes, 47);
        assert_eq!(catalog.entries.len(), 2);

        let selective = read_package_selective(&zip_path, limits, &["manifest.json"], &[]).unwrap();
        assert_eq!(selective.files["manifest.json"], manifest);
        assert_eq!(selective.files["payload.bin"], b"payload");
        assert!(selective.streamed.is_empty());
    }

    #[test]
    fn control_pass_catalogs_oversized_ordinary_entries_without_reading_them() {
        let dir = TestDirectory::new();
        fs::write(dir.path().join("big.bin"), vec![b'b'; 100]).unwrap();

        // Ordinary entries are only cataloged: 100 bytes exceeds max_file_bytes
        // (16) yet the catalog pass succeeds, which would be impossible if the
        // body were read under the per-file limit.
        let limits = tiny_limits();
        let catalog = read_package_controls(dir.path(), limits, &[]).unwrap();
        assert_eq!(
            catalog.entries,
            vec![CatalogEntry {
                name: "big.bin".into(),
                size: 100,
            }]
        );
        assert!(catalog.controls.is_empty());
        assert_eq!(catalog.total_bytes, 100);

        // The same entry is rejected by the selective pass unless streamed.
        let err = read_package_selective(dir.path(), limits, &[], &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::Limit("file size")));
    }

    #[test]
    fn zip_control_pass_catalogs_oversized_ordinary_entries() {
        let dir = TestDirectory::new();
        let payload = vec![b'b'; 100];
        let zip_path = write_zip(dir.path(), &[("big.bin", &payload)]);

        let limits = tiny_limits();
        let catalog = read_package_controls(&zip_path, limits, &[]).unwrap();
        assert_eq!(
            catalog.entries,
            vec![CatalogEntry {
                name: "big.bin".into(),
                size: 100,
            }]
        );
        assert!(catalog.controls.is_empty());
        assert_eq!(catalog.total_bytes, 100);
    }

    #[test]
    fn directory_rejects_unsafe_entry_paths() {
        let dir = TestDirectory::new();
        // A backslash is a legal Unix filename character but never a safe
        // package path.
        fs::write(dir.path().join("bad\\name.txt"), b"x").unwrap();

        let limits = tiny_limits();
        let err = read_package_controls(dir.path(), limits, &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::UnsafePath(_)));
        let err = read_package_selective(dir.path(), limits, &[], &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::UnsafePath(_)));
    }

    #[test]
    fn zip_rejects_unsafe_entry_names() {
        let dir = TestDirectory::new();
        // ".." is never a safe package path, whichever platform normalizes it.
        let zip_path = write_zip(dir.path(), &[("../evil.txt", b"x")]);

        let limits = tiny_limits();
        let err = read_package_controls(&zip_path, limits, &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::UnsafePath(_)));
        let err = read_package_selective(&zip_path, limits, &[], &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::UnsafePath(_)));
    }

    #[test]
    fn zip_rejects_duplicate_entry_names() {
        let dir = TestDirectory::new();
        // The zip crate's own writer refuses duplicate names, and its reader
        // silently collapses identical raw names in the central directory.
        // Distinct raw names that normalize to the same safe path ("a//b" and
        // "a/b") still surface both entries and must be rejected as
        // duplicates, so the carrier is assembled by hand.
        let zip_path = write_raw_zip(dir.path(), &[("a//b", b"first"), ("a/b", b"second")]);

        let limits = tiny_limits();
        let err = read_package_controls(&zip_path, limits, &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::DuplicatePath(_)));
        let err = read_package_selective(&zip_path, limits, &[], &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::DuplicatePath(_)));
    }

    #[cfg(unix)]
    #[test]
    fn directory_rejects_entry_symlinks() {
        use std::os::unix::fs::symlink;

        let dir = TestDirectory::new();
        fs::write(dir.path().join("target.txt"), b"x").unwrap();
        symlink(dir.path().join("target.txt"), dir.path().join("link.txt")).unwrap();

        let limits = tiny_limits();
        let err = read_package_controls(dir.path(), limits, &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::Symlink(_)));
        let err = read_package_selective(dir.path(), limits, &[], &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::Symlink(_)));
    }

    #[cfg(unix)]
    #[test]
    fn rejects_input_symlink() {
        use std::os::unix::fs::symlink;

        let dir = TestDirectory::new();
        fs::create_dir(dir.path().join("real")).unwrap();
        fs::write(dir.path().join("real/inside.txt"), b"x").unwrap();
        symlink(dir.path().join("real"), dir.path().join("alias")).unwrap();

        let limits = tiny_limits();
        let err = read_package_controls(&dir.path().join("alias"), limits, &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::Symlink(_)));
        let err = read_package_selective(&dir.path().join("alias"), limits, &[], &[]).unwrap_err();
        assert!(matches!(err, ArchiveError::Symlink(_)));
    }
}
