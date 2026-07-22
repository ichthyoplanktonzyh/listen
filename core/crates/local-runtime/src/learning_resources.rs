use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use application::{ApplicationError, now_ms};
use domain::{LearningResourceDescriptor, LearningResourceId, LearningResourceState};
use thiserror::Error;

use crate::download::{ArtifactDownloader, DownloadProgress, ReqwestArtifactDownloader};
use crate::runtime_support::{hash_file, io_error};

#[derive(Debug, Error)]
pub enum LearningResourceError {
    #[error("learning resource was not found")]
    NotFound,
    #[error("learning resource checksum mismatch")]
    ChecksumMismatch,
    #[error("learning resource download failed: {0}")]
    Download(String),
    #[error(transparent)]
    Storage(#[from] ApplicationError),
}

#[derive(Clone)]
pub struct LearningResourceManager {
    resources: Arc<Mutex<Vec<LearningResourceDescriptor>>>,
    resource_dir: PathBuf,
    downloader: Arc<dyn ArtifactDownloader>,
}

impl LearningResourceManager {
    pub fn new() -> Self {
        Self::with_configuration(
            resource_catalog(),
            default_resources_dir(),
            Arc::new(ReqwestArtifactDownloader),
        )
    }

    pub fn with_configuration(
        mut resources: Vec<LearningResourceDescriptor>,
        resource_dir: PathBuf,
        downloader: Arc<dyn ArtifactDownloader>,
    ) -> Self {
        for descriptor in &mut resources {
            let path = resource_dir.join(format!("{}.data", descriptor.id.as_str()));
            if let Ok(metadata) = std::fs::metadata(&path) {
                if metadata.is_file() && metadata.len() == descriptor.size_bytes {
                    descriptor.local_path = Some(path.to_string_lossy().into_owned());
                    descriptor.installed_bytes = metadata.len();
                    descriptor.state = LearningResourceState::Installed;
                } else {
                    descriptor.state = LearningResourceState::Failed;
                    descriptor.error = Some("installed resource size mismatch".into());
                }
            }
        }
        Self {
            resources: Arc::new(Mutex::new(resources)),
            resource_dir,
            downloader,
        }
    }

    pub fn list(&self) -> Vec<LearningResourceDescriptor> {
        self.resources
            .lock()
            .expect("resource mutex poisoned")
            .clone()
    }

    pub async fn install(
        &self,
        id: &LearningResourceId,
    ) -> Result<LearningResourceDescriptor, LearningResourceError> {
        let mut descriptor = self.find(id).ok_or(LearningResourceError::NotFound)?;
        descriptor.state = LearningResourceState::Installing;
        descriptor.error = None;
        self.replace(descriptor.clone());
        tokio::fs::create_dir_all(&self.resource_dir)
            .await
            .map_err(io_error)?;
        let path = self.resource_dir.join(format!("{}.data", id.as_str()));
        let partial = self
            .resource_dir
            .join(format!("{}.data.download", id.as_str()));
        if let Err(error) = self
            .downloader
            .download(
                &descriptor.source_url,
                &partial,
                Arc::new(ResourceDownloadProgress {
                    resources: self.resources.clone(),
                    id: id.clone(),
                }),
            )
            .await
        {
            let _ = tokio::fs::remove_file(&partial).await;
            self.fail(id, error.to_string());
            return Err(LearningResourceError::Download(error.to_string()));
        }
        let checksum = hash_file(&partial)?;
        if !descriptor.checksum_sha256.is_empty() && descriptor.checksum_sha256 != checksum {
            let _ = tokio::fs::remove_file(&partial).await;
            self.fail(id, "checksum mismatch".into());
            return Err(LearningResourceError::ChecksumMismatch);
        }
        tokio::fs::rename(&partial, &path).await.map_err(io_error)?;
        let size = tokio::fs::metadata(&path).await.map_err(io_error)?.len();
        descriptor.checksum_sha256 = checksum;
        descriptor.size_bytes = size;
        descriptor.installed_bytes = size;
        descriptor.local_path = Some(path.to_string_lossy().into_owned());
        descriptor.state = LearningResourceState::Installed;
        descriptor.error = None;
        descriptor.updated_at_ms = now_ms();
        self.replace(descriptor.clone());
        Ok(descriptor)
    }

    pub async fn remove(
        &self,
        id: &LearningResourceId,
    ) -> Result<LearningResourceDescriptor, LearningResourceError> {
        let mut descriptor = self.find(id).ok_or(LearningResourceError::NotFound)?;
        if let Some(path) = descriptor.local_path.take() {
            let _ = tokio::fs::remove_file(path).await;
        }
        descriptor.state = LearningResourceState::Available;
        descriptor.installed_bytes = 0;
        descriptor.error = None;
        descriptor.updated_at_ms = now_ms();
        self.replace(descriptor.clone());
        Ok(descriptor)
    }

    fn find(&self, id: &LearningResourceId) -> Option<LearningResourceDescriptor> {
        self.resources
            .lock()
            .expect("resource mutex poisoned")
            .iter()
            .find(|value| value.id == *id)
            .cloned()
    }

    fn replace(&self, replacement: LearningResourceDescriptor) {
        let mut values = self.resources.lock().expect("resource mutex poisoned");
        if let Some(value) = values.iter_mut().find(|value| value.id == replacement.id) {
            *value = replacement;
        }
    }

    fn fail(&self, id: &LearningResourceId, detail: String) {
        if let Some(mut descriptor) = self.find(id) {
            descriptor.state = LearningResourceState::Failed;
            descriptor.error = Some(detail);
            descriptor.updated_at_ms = now_ms();
            self.replace(descriptor);
        }
    }
}

impl Default for LearningResourceManager {
    fn default() -> Self {
        Self::new()
    }
}

struct ResourceDownloadProgress {
    resources: Arc<Mutex<Vec<LearningResourceDescriptor>>>,
    id: LearningResourceId,
}

impl DownloadProgress for ResourceDownloadProgress {
    fn is_cancelled(&self) -> Result<bool, ApplicationError> {
        Ok(self
            .resources
            .lock()
            .expect("resource mutex poisoned")
            .iter()
            .find(|value| value.id == self.id)
            .is_some_and(|value| value.state != LearningResourceState::Installing))
    }

    fn downloaded(&self, bytes: u64) -> Result<(), ApplicationError> {
        if let Some(descriptor) = self
            .resources
            .lock()
            .expect("resource mutex poisoned")
            .iter_mut()
            .find(|value| value.id == self.id)
        {
            descriptor.installed_bytes = bytes;
            descriptor.updated_at_ms = now_ms();
        }
        Ok(())
    }
}

fn default_resources_dir() -> PathBuf {
    std::env::var_os("LLPLAYERNEXT_RESOURCES_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
                .join("Library/Application Support/LLPlayerNext/resources/learning")
        })
}

fn resource_catalog() -> Vec<LearningResourceDescriptor> {
    [
        ("ecdict", "ECDICT", "bc015ed2", "https://raw.githubusercontent.com/skywind3000/ECDICT/bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b/ecdict.csv", "MIT", "1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf", 65_933_428),
        ("cmudict", "CMU Pronouncing Dictionary", "74790861", "https://raw.githubusercontent.com/cmusphinx/cmudict/74790861f652b15e4ac49015a90074ad62a27690/cmudict.dict", "BSD-style CMUdict license", "81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22", 3_618_488),
        ("cc-cedict", "CC-CEDICT", "61e2794c", "https://raw.githubusercontent.com/ueda-keisuke/CC-CEDICT-MeCab/61e2794c475313adf241b739fcde8acb4520c1ea/cedict_ts.u8", "CC-BY-SA 4.0", "09ec3a583100088c4f7db2d65643bb9134df5174a4bca7592f50fe2bc5686957", 9_151_648),
    ]
    .into_iter()
    .map(|(id, name, version, url, license, checksum, size)| LearningResourceDescriptor {
        id: LearningResourceId::from_fingerprint("learning-resource", id),
        display_name: name.into(),
        version: version.into(),
        source_url: url.into(),
        license: license.into(),
        checksum_sha256: checksum.into(),
        size_bytes: size,
        local_path: None,
        state: LearningResourceState::Available,
        installed_bytes: 0,
        error: None,
        updated_at_ms: 0,
    })
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::FakeArtifactDownloader;
    use sha2::{Digest, Sha256};

    fn descriptor(checksum: String) -> LearningResourceDescriptor {
        LearningResourceDescriptor {
            id: LearningResourceId::from_fingerprint("learning-resource", "fixture"),
            display_name: "Fixture".into(),
            version: "v1".into(),
            source_url: "memory://fixture".into(),
            license: "MIT".into(),
            checksum_sha256: checksum,
            size_bytes: 7,
            local_path: None,
            state: LearningResourceState::Available,
            installed_bytes: 0,
            error: None,
            updated_at_ms: 0,
        }
    }

    #[tokio::test]
    async fn install_verifies_checksum_and_remove_cleans_file() {
        let bytes = b"fixture".to_vec();
        let resource = descriptor(hex::encode(Sha256::digest(&bytes)));
        let id = resource.id.clone();
        let directory =
            std::env::temp_dir().join(format!("local-runtime-resource-{}", std::process::id()));
        let manager = LearningResourceManager::with_configuration(
            vec![resource],
            directory.clone(),
            Arc::new(FakeArtifactDownloader::new(bytes)),
        );
        let installed = manager.install(&id).await.unwrap();
        let path = installed.local_path.clone().unwrap();
        assert_eq!(installed.state, LearningResourceState::Installed);
        assert!(std::path::Path::new(&path).exists());
        assert_eq!(
            manager.remove(&id).await.unwrap().state,
            LearningResourceState::Available
        );
        assert!(!std::path::Path::new(&path).exists());
        let _ = std::fs::remove_dir_all(directory);
    }

    #[tokio::test]
    async fn checksum_failure_never_publishes_partial_file() {
        let resource = descriptor("wrong".into());
        let id = resource.id.clone();
        let directory = std::env::temp_dir().join(format!(
            "local-runtime-resource-checksum-{}",
            std::process::id()
        ));
        let manager = LearningResourceManager::with_configuration(
            vec![resource],
            directory.clone(),
            Arc::new(FakeArtifactDownloader::new(b"fixture".to_vec())),
        );
        assert!(matches!(
            manager.install(&id).await,
            Err(LearningResourceError::ChecksumMismatch)
        ));
        assert_eq!(manager.list()[0].state, LearningResourceState::Failed);
        assert!(!directory.join(format!("{}.data", id.as_str())).exists());
        assert!(
            !directory
                .join(format!("{}.data.download", id.as_str()))
                .exists()
        );
    }
}
