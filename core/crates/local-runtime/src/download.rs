use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use application::ApplicationError;
use async_trait::async_trait;
use tokio::io::AsyncWriteExt;

use crate::runtime_support::io_error;

pub trait DownloadProgress: Send + Sync {
    fn is_cancelled(&self) -> Result<bool, ApplicationError>;
    fn downloaded(&self, bytes: u64) -> Result<(), ApplicationError>;
}

#[async_trait]
pub trait ArtifactDownloader: Send + Sync {
    async fn download(
        &self,
        source: &str,
        destination: &Path,
        progress: Arc<dyn DownloadProgress>,
    ) -> Result<(), ApplicationError>;
}

/// Production adapter for remote artifacts. The coordinator owns validation,
/// checksums, publication, and cleanup; this adapter owns only byte transfer.
#[derive(Debug, Default)]
pub struct ReqwestArtifactDownloader;

#[async_trait]
impl ArtifactDownloader for ReqwestArtifactDownloader {
    async fn download(
        &self,
        source: &str,
        destination: &Path,
        progress: Arc<dyn DownloadProgress>,
    ) -> Result<(), ApplicationError> {
        let mut response = reqwest::get(source)
            .await
            .map_err(|error| ApplicationError::Repository(error.to_string()))?
            .error_for_status()
            .map_err(|error| ApplicationError::Repository(error.to_string()))?;
        let mut file = tokio::fs::File::create(destination)
            .await
            .map_err(io_error)?;
        let mut downloaded = 0_u64;
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|error| ApplicationError::Repository(error.to_string()))?
        {
            if progress.is_cancelled()? {
                return Err(ApplicationError::Repository(
                    "model installation cancelled".into(),
                ));
            }
            file.write_all(&chunk).await.map_err(io_error)?;
            downloaded += chunk.len() as u64;
            progress.downloaded(downloaded)?;
        }
        file.flush().await.map_err(io_error)
    }
}

/// Deterministic adapter for install, cancellation, checksum, and cleanup tests.
#[derive(Clone)]
pub struct FakeArtifactDownloader {
    bytes: Arc<Vec<u8>>,
    failure: Arc<Mutex<Option<String>>>,
    calls: Arc<Mutex<Vec<(String, PathBuf)>>>,
}

impl FakeArtifactDownloader {
    pub fn new(bytes: Vec<u8>) -> Self {
        Self {
            bytes: Arc::new(bytes),
            failure: Arc::default(),
            calls: Arc::default(),
        }
    }

    pub fn failing(message: impl Into<String>) -> Self {
        Self {
            bytes: Arc::default(),
            failure: Arc::new(Mutex::new(Some(message.into()))),
            calls: Arc::default(),
        }
    }

    pub fn calls(&self) -> Vec<(String, PathBuf)> {
        self.calls
            .lock()
            .expect("fake downloader mutex poisoned")
            .clone()
    }
}

#[async_trait]
impl ArtifactDownloader for FakeArtifactDownloader {
    async fn download(
        &self,
        source: &str,
        destination: &Path,
        progress: Arc<dyn DownloadProgress>,
    ) -> Result<(), ApplicationError> {
        self.calls
            .lock()
            .expect("fake downloader mutex poisoned")
            .push((source.to_owned(), destination.to_path_buf()));
        if let Some(message) = self
            .failure
            .lock()
            .expect("fake downloader mutex poisoned")
            .take()
        {
            return Err(ApplicationError::Repository(message));
        }
        if progress.is_cancelled()? {
            return Err(ApplicationError::Repository(
                "model installation cancelled".into(),
            ));
        }
        tokio::fs::write(destination, self.bytes.as_slice())
            .await
            .map_err(io_error)?;
        progress.downloaded(self.bytes.len() as u64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    struct Progress(AtomicU64);

    impl DownloadProgress for Progress {
        fn is_cancelled(&self) -> Result<bool, ApplicationError> {
            Ok(false)
        }

        fn downloaded(&self, bytes: u64) -> Result<(), ApplicationError> {
            self.0.store(bytes, Ordering::SeqCst);
            Ok(())
        }
    }

    #[tokio::test]
    async fn fake_writes_bytes_reports_progress_and_records_call() {
        let destination =
            std::env::temp_dir().join(format!("local-runtime-download-{}", std::process::id()));
        let progress = Arc::new(Progress(AtomicU64::new(0)));
        let downloader = FakeArtifactDownloader::new(b"model".to_vec());
        downloader
            .download("memory://model", &destination, progress.clone())
            .await
            .unwrap();
        assert_eq!(tokio::fs::read(&destination).await.unwrap(), b"model");
        assert_eq!(progress.0.load(Ordering::SeqCst), 5);
        assert_eq!(downloader.calls()[0].0, "memory://model");
        let _ = tokio::fs::remove_file(destination).await;
    }
}
