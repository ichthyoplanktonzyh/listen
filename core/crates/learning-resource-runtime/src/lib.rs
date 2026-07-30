use std::io;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use domain::LearningResourceId;

pub const RESOURCES_DIR_ENV: &str = "LLPLAYERNEXT_RESOURCES_DIR";
pub const CMUDICT_PATH_ENV: &str = "LLPLAYERNEXT_CMUDICT";

/// Returns the single authoritative directory for installable learning
/// resources. An explicit runtime directory takes precedence over the
/// platform-default application-support location.
pub fn learning_resources_dir() -> PathBuf {
    resources_dir_from(
        std::env::var_os(RESOURCES_DIR_ENV).map(PathBuf::from),
        std::env::var_os("HOME").map(PathBuf::from),
    )
}

/// Resolves a catalog key to the same opaque filename used by the installer.
pub fn learning_resource_path(key: &str) -> PathBuf {
    learning_resources_dir().join(learning_resource_file_name(key))
}

/// Preserves the historical CMUdict-only override while making the shared
/// resource directory authoritative when that override is absent.
pub fn cmudict_resource_path() -> PathBuf {
    cmudict_resource_path_from(
        std::env::var_os(CMUDICT_PATH_ENV).map(PathBuf::from),
        std::env::var_os(RESOURCES_DIR_ENV).map(PathBuf::from),
        std::env::var_os("HOME").map(PathBuf::from),
    )
}

pub fn learning_resource_file_name(key: &str) -> String {
    let id = LearningResourceId::from_fingerprint("learning-resource", key);
    learning_resource_file_name_for_id(&id)
}

pub fn learning_resource_file_name_for_id(id: &LearningResourceId) -> String {
    format!("{}.data", id.as_str())
}

fn resources_dir_from(explicit: Option<PathBuf>, home: Option<PathBuf>) -> PathBuf {
    explicit.unwrap_or_else(|| {
        home.unwrap_or_default()
            .join("Library/Application Support/LLPlayerNext/resources/learning")
    })
}

fn cmudict_resource_path_from(
    cmudict_override: Option<PathBuf>,
    resources_override: Option<PathBuf>,
    home: Option<PathBuf>,
) -> PathBuf {
    cmudict_override.unwrap_or_else(|| {
        resources_dir_from(resources_override, home).join(learning_resource_file_name("cmudict"))
    })
}

/// Metadata used to determine whether a parsed resource index remains valid.
///
/// Length and modification time work across supported platforms. Unix file
/// identity additionally detects atomic replacement even when a publisher
/// preserves both of those values.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResourceSignature {
    len: u64,
    modified: Option<SystemTime>,
    #[cfg(unix)]
    device: u64,
    #[cfg(unix)]
    inode: u64,
}

impl ResourceSignature {
    pub fn read(path: &Path) -> io::Result<Option<Self>> {
        let metadata = match std::fs::metadata(path) {
            Ok(value) => value,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error),
        };
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            Ok(Some(Self {
                len: metadata.len(),
                modified: metadata.modified().ok(),
                device: metadata.dev(),
                inode: metadata.ino(),
            }))
        }
        #[cfg(not(unix))]
        {
            Ok(Some(Self {
                len: metadata.len(),
                modified: metadata.modified().ok(),
            }))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn explicit_resource_directory_is_authoritative() {
        let explicit = PathBuf::from("/runtime/resources");
        assert_eq!(
            resources_dir_from(Some(explicit.clone()), Some(PathBuf::from("/ignored"))),
            explicit
        );
    }

    #[test]
    fn default_resource_directory_is_derived_from_home() {
        assert_eq!(
            resources_dir_from(None, Some(PathBuf::from("/user"))),
            PathBuf::from("/user/Library/Application Support/LLPlayerNext/resources/learning")
        );
    }

    #[test]
    fn catalog_key_has_stable_opaque_filename() {
        let first = learning_resource_file_name("cmudict");
        let second = learning_resource_file_name("cmudict");
        assert_eq!(first, second);
        assert!(first.ends_with(".data"));
    }

    #[test]
    fn legacy_cmudict_override_precedes_shared_resource_directory() {
        let legacy = PathBuf::from("/legacy/cmudict.dict");
        assert_eq!(
            cmudict_resource_path_from(
                Some(legacy.clone()),
                Some(PathBuf::from("/runtime/resources")),
                Some(PathBuf::from("/user")),
            ),
            legacy
        );
    }

    #[test]
    fn cmudict_uses_shared_resource_directory_without_legacy_override() {
        assert_eq!(
            cmudict_resource_path_from(
                None,
                Some(PathBuf::from("/runtime/resources")),
                Some(PathBuf::from("/ignored")),
            ),
            PathBuf::from("/runtime/resources").join(learning_resource_file_name("cmudict"))
        );
    }
}
