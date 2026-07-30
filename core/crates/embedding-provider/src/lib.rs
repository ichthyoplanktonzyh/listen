//! Concrete semantic-embedding adapters.
//!
//! This crate is the provider seam: application code never sees FastEmbed,
//! ONNX, Hugging Face cache layout, credentials, or vendor JSON. A descriptor
//! fingerprints the complete vector-space contract; wire compatibility never
//! implies vector compatibility.

use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};

use application::{ApplicationError, EmbeddingProvider};
use async_trait::async_trait;
use domain::{
    EmbeddingModelDescriptor, EmbeddingPurpose, SEMANTIC_INDEX_SCHEMA_VERSION,
    SemanticEmbeddingStatus,
};
use fastembed::{EmbeddingModel, TextEmbedding, TextInitOptions};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

const MODEL_REPOSITORY: &str = "models--Qdrant--all-MiniLM-L6-v2-onnx";
const DESCRIPTOR_FILE: &str = "llplayernext-descriptor.json";
const ACTIVE_MANIFEST_FILE: &str = "active.json";
const CANDIDATE_FAILURE_FILE: &str = "candidate-failure.json";
const CANDIDATES_DIR: &str = "candidates";
const VERSIONS_DIR: &str = "versions";
const LIFECYCLE_SCHEMA_VERSION: u32 = 1;
static NEXT_CANDIDATE_ID: AtomicU64 = AtomicU64::new(1);

pub struct FastEmbedProvider {
    descriptor: EmbeddingModelDescriptor,
    model: Arc<Mutex<TextEmbedding>>,
}

impl FastEmbedProvider {
    fn install(cache_dir: &Path) -> Result<Self, ApplicationError> {
        std::fs::create_dir_all(cache_dir).map_err(external)?;
        let model = TextEmbedding::try_new(
            TextInitOptions::new(EmbeddingModel::AllMiniLML6V2)
                .with_cache_dir(cache_dir.to_path_buf())
                .with_show_download_progress(false)
                .with_intra_threads(4),
        )
        .map_err(external)?;
        let descriptor = installed_descriptor(cache_dir)?;
        let bytes = serde_json::to_vec_pretty(&descriptor)
            .map_err(|error| ApplicationError::ExternalProcess(error.to_string()))?;
        std::fs::write(cache_dir.join(DESCRIPTOR_FILE), bytes).map_err(external)?;
        Ok(Self {
            descriptor,
            model: Arc::new(Mutex::new(model)),
        })
    }

    fn load(cache_dir: &Path) -> Result<Option<Self>, ApplicationError> {
        let descriptor_path = cache_dir.join(DESCRIPTOR_FILE);
        if !descriptor_path.is_file() {
            return Ok(None);
        }
        let descriptor: EmbeddingModelDescriptor =
            serde_json::from_slice(&std::fs::read(descriptor_path).map_err(external)?).map_err(
                |error| ApplicationError::Invalid(format!("invalid embedding descriptor: {error}")),
            )?;
        let current = installed_descriptor(cache_dir)?;
        if current != descriptor {
            return Err(ApplicationError::Conflict(
                "installed embedding artifacts no longer match their descriptor",
            ));
        }
        let model = TextEmbedding::try_new(
            TextInitOptions::new(EmbeddingModel::AllMiniLML6V2)
                .with_cache_dir(cache_dir.to_path_buf())
                .with_show_download_progress(false)
                .with_intra_threads(4),
        )
        .map_err(external)?;
        Ok(Some(Self {
            descriptor,
            model: Arc::new(Mutex::new(model)),
        }))
    }
}

#[async_trait]
impl EmbeddingProvider for FastEmbedProvider {
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
        Some(self.descriptor.clone())
    }

    async fn embed(
        &self,
        _purpose: EmbeddingPurpose,
        texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError> {
        if texts.iter().any(|text| text.trim().is_empty()) {
            return Err(ApplicationError::Validation("embedding text"));
        }
        let model = self.model.clone();
        let texts = texts.to_vec();
        tokio::task::spawn_blocking(move || {
            model
                .lock()
                .expect("embedding model mutex poisoned")
                .embed(texts, Some(32))
                .map_err(external)
        })
        .await
        .map_err(|error| ApplicationError::ExternalProcess(error.to_string()))?
    }
}

trait LocalEmbeddingRuntime: Send + Sync {
    fn install(&self, cache_dir: &Path) -> Result<Arc<dyn EmbeddingProvider>, ApplicationError>;
    fn load(
        &self,
        cache_dir: &Path,
    ) -> Result<Option<Arc<dyn EmbeddingProvider>>, ApplicationError>;
}

struct FastEmbedRuntime;

impl LocalEmbeddingRuntime for FastEmbedRuntime {
    fn install(&self, cache_dir: &Path) -> Result<Arc<dyn EmbeddingProvider>, ApplicationError> {
        FastEmbedProvider::install(cache_dir)
            .map(|provider| Arc::new(provider) as Arc<dyn EmbeddingProvider>)
    }

    fn load(
        &self,
        cache_dir: &Path,
    ) -> Result<Option<Arc<dyn EmbeddingProvider>>, ApplicationError> {
        FastEmbedProvider::load(cache_dir)
            .map(|provider| provider.map(|value| Arc::new(value) as Arc<dyn EmbeddingProvider>))
    }
}

trait ActiveManifestPublisher: Send + Sync {
    fn publish(
        &self,
        root: &Path,
        manifest: &ActiveEmbeddingManifest,
    ) -> Result<(), ApplicationError>;
}

trait InstallationRemover: Send + Sync {
    fn remove(&self, root: &Path) -> Result<(), ApplicationError>;
}

struct FilesystemInstallationRemover;

impl InstallationRemover for FilesystemInstallationRemover {
    fn remove(&self, root: &Path) -> Result<(), ApplicationError> {
        std::fs::remove_dir_all(root).map_err(external)
    }
}

struct FilesystemActiveManifestPublisher;

impl ActiveManifestPublisher for FilesystemActiveManifestPublisher {
    fn publish(
        &self,
        root: &Path,
        manifest: &ActiveEmbeddingManifest,
    ) -> Result<(), ApplicationError> {
        atomic_write_json(&root.join(ACTIVE_MANIFEST_FILE), manifest)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct ActiveEmbeddingManifest {
    schema_version: u32,
    directory: String,
    descriptor: EmbeddingModelDescriptor,
    artifacts: Vec<ArtifactIntegrity>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct ArtifactIntegrity {
    path: String,
    size_bytes: u64,
    sha256: String,
}

/// Internal operator provenance for the most recent failed local-model
/// candidate. It is deliberately not part of the learner-facing capability
/// contract.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EmbeddingCandidateFailure {
    pub candidate_id: String,
    pub attempted_at_ms: u64,
    pub phase: String,
    pub detail: String,
}

/// Opt-in local model lifecycle. Construction and capability reads never
/// download. An install is built and validated under an isolated candidate
/// directory, then an active manifest is atomically replaced. Ordinary
/// candidate failures retain the last-good provider, status, and index
/// fingerprint. `disable` preserves model bytes; `uninstall` removes model
/// bytes without touching learning data.
pub struct ManagedFastEmbedProvider {
    root: PathBuf,
    provider: RwLock<Option<Arc<dyn EmbeddingProvider>>>,
    status: RwLock<SemanticEmbeddingStatus>,
    candidate_failure: RwLock<Option<EmbeddingCandidateFailure>>,
    upgrade_in_progress: AtomicBool,
    runtime: Arc<dyn LocalEmbeddingRuntime>,
    publisher: Arc<dyn ActiveManifestPublisher>,
    remover: Arc<dyn InstallationRemover>,
}

impl ManagedFastEmbedProvider {
    pub fn new(root: PathBuf) -> Self {
        Self::with_components(
            root,
            Arc::new(FastEmbedRuntime),
            Arc::new(FilesystemActiveManifestPublisher),
            Arc::new(FilesystemInstallationRemover),
        )
    }

    fn with_components(
        root: PathBuf,
        runtime: Arc<dyn LocalEmbeddingRuntime>,
        publisher: Arc<dyn ActiveManifestPublisher>,
        remover: Arc<dyn InstallationRemover>,
    ) -> Self {
        cleanup_incomplete_installations(&root);
        let candidate_failure = read_json(&root.join(CANDIDATE_FAILURE_FILE)).ok().flatten();
        let loaded = load_active_provider(&root, runtime.as_ref());
        match loaded {
            Ok(provider) => Self {
                root,
                status: RwLock::new(if provider.is_some() {
                    SemanticEmbeddingStatus::Ready
                } else {
                    SemanticEmbeddingStatus::NotInstalled
                }),
                provider: RwLock::new(provider),
                candidate_failure: RwLock::new(candidate_failure),
                upgrade_in_progress: AtomicBool::new(false),
                runtime,
                publisher,
                remover,
            },
            Err(_) => Self {
                root,
                provider: RwLock::new(None),
                status: RwLock::new(SemanticEmbeddingStatus::Failed),
                candidate_failure: RwLock::new(candidate_failure),
                upgrade_in_progress: AtomicBool::new(false),
                runtime,
                publisher,
                remover,
            },
        }
    }

    pub async fn install(&self) -> Result<(), ApplicationError> {
        let _guard = UpgradeGuard::begin(&self.upgrade_in_progress)?;
        let candidate_id = next_candidate_id();
        let candidate_dir = self.root.join(CANDIDATES_DIR).join(&candidate_id);
        if let Err(error) = std::fs::create_dir_all(&candidate_dir).map_err(external) {
            self.record_candidate_failure(&candidate_id, "staging", &error);
            self.fail_only_without_last_good();
            return Err(error);
        }

        let runtime = self.runtime.clone();
        let build_dir = candidate_dir.clone();
        let result = tokio::task::spawn_blocking(move || runtime.install(&build_dir))
            .await
            .map_err(|error| ApplicationError::ExternalProcess(error.to_string()))
            .and_then(|result| result);
        let candidate = match result {
            Ok(provider) => provider,
            Err(error) => {
                remove_path_if_present(&candidate_dir);
                self.record_candidate_failure(&candidate_id, "build", &error);
                self.fail_only_without_last_good();
                return Err(error);
            }
        };

        let descriptor = match validate_candidate(candidate.as_ref()) {
            Ok(descriptor) => descriptor,
            Err(error) => {
                drop(candidate);
                remove_path_if_present(&candidate_dir);
                self.record_candidate_failure(&candidate_id, "validation", &error);
                self.fail_only_without_last_good();
                return Err(error);
            }
        };
        let artifacts = match artifact_integrity(&candidate_dir) {
            Ok(artifacts) if !artifacts.is_empty() => artifacts,
            Ok(_) => {
                let error =
                    ApplicationError::Invalid("embedding candidate has no artifacts".into());
                drop(candidate);
                remove_path_if_present(&candidate_dir);
                self.record_candidate_failure(&candidate_id, "validation", &error);
                self.fail_only_without_last_good();
                return Err(error);
            }
            Err(error) => {
                drop(candidate);
                remove_path_if_present(&candidate_dir);
                self.record_candidate_failure(&candidate_id, "validation", &error);
                self.fail_only_without_last_good();
                return Err(error);
            }
        };
        let version_relative = PathBuf::from(VERSIONS_DIR)
            .join(format!("{}-{candidate_id}", descriptor.model_fingerprint));
        let version_dir = self.root.join(&version_relative);
        if let Err(error) = std::fs::create_dir_all(self.root.join(VERSIONS_DIR)).map_err(external)
        {
            drop(candidate);
            remove_path_if_present(&candidate_dir);
            self.record_candidate_failure(&candidate_id, "activation", &error);
            self.fail_only_without_last_good();
            return Err(error);
        }
        if let Err(error) = std::fs::rename(&candidate_dir, &version_dir).map_err(external) {
            drop(candidate);
            remove_path_if_present(&candidate_dir);
            self.record_candidate_failure(&candidate_id, "activation", &error);
            self.fail_only_without_last_good();
            return Err(error);
        }
        if let Err(error) = sync_directory(&self.root.join(VERSIONS_DIR)) {
            drop(candidate);
            remove_path_if_present(&version_dir);
            self.record_candidate_failure(&candidate_id, "activation", &error);
            self.fail_only_without_last_good();
            return Err(error);
        }
        drop(candidate);
        let activated = match validate_final_version(
            self.runtime.as_ref(),
            &version_dir,
            &descriptor,
            &artifacts,
        ) {
            Ok(provider) => provider,
            Err(error) => {
                remove_path_if_present(&version_dir);
                self.record_candidate_failure(&candidate_id, "validation", &error);
                self.fail_only_without_last_good();
                return Err(error);
            }
        };
        let manifest = ActiveEmbeddingManifest {
            schema_version: LIFECYCLE_SCHEMA_VERSION,
            directory: version_relative.to_string_lossy().into_owned(),
            descriptor,
            artifacts,
        };
        if let Err(error) = self.publisher.publish(&self.root, &manifest) {
            drop(activated);
            self.record_candidate_failure(&candidate_id, "activation", &error);
            self.fail_only_without_last_good();
            return Err(error);
        }

        *self
            .provider
            .write()
            .expect("embedding provider lock poisoned") = Some(activated);
        *self.status.write().expect("embedding status lock poisoned") =
            SemanticEmbeddingStatus::Ready;
        self.clear_candidate_failure();
        Ok(())
    }

    pub fn disable(&self) {
        *self.status.write().expect("embedding status lock poisoned") =
            SemanticEmbeddingStatus::Disabled;
    }

    pub fn enable(&self) -> Result<(), ApplicationError> {
        if self
            .provider
            .read()
            .expect("embedding provider lock poisoned")
            .is_none()
        {
            let provider =
                match load_active_provider(&self.root, self.runtime.as_ref()).and_then(|provider| {
                    provider.ok_or(ApplicationError::Conflict(
                        "semantic embedding model is not installed",
                    ))
                }) {
                    Ok(provider) => provider,
                    Err(error) => {
                        *self.status.write().expect("embedding status lock poisoned") =
                            SemanticEmbeddingStatus::Failed;
                        return Err(error);
                    }
                };
            *self
                .provider
                .write()
                .expect("embedding provider lock poisoned") = Some(provider);
        }
        *self.status.write().expect("embedding status lock poisoned") =
            SemanticEmbeddingStatus::Ready;
        Ok(())
    }

    pub fn uninstall(&self) -> Result<(), ApplicationError> {
        let _guard = UpgradeGuard::begin(&self.upgrade_in_progress)?;
        if self.root.exists() {
            self.remover.remove(&self.root)?;
        }
        *self
            .provider
            .write()
            .expect("embedding provider lock poisoned") = None;
        *self.status.write().expect("embedding status lock poisoned") =
            SemanticEmbeddingStatus::NotInstalled;
        *self
            .candidate_failure
            .write()
            .expect("embedding candidate failure lock poisoned") = None;
        Ok(())
    }

    pub fn candidate_failure(&self) -> Option<EmbeddingCandidateFailure> {
        self.candidate_failure
            .read()
            .expect("embedding candidate failure lock poisoned")
            .clone()
    }

    fn fail_only_without_last_good(&self) {
        if self
            .provider
            .read()
            .expect("embedding provider lock poisoned")
            .is_none()
        {
            *self.status.write().expect("embedding status lock poisoned") =
                SemanticEmbeddingStatus::Failed;
        }
    }

    fn record_candidate_failure(&self, candidate_id: &str, phase: &str, error: &ApplicationError) {
        let failure = EmbeddingCandidateFailure {
            candidate_id: candidate_id.to_owned(),
            attempted_at_ms: application::now_ms(),
            phase: phase.to_owned(),
            detail: error.to_string(),
        };
        let _ = atomic_write_json(&self.root.join(CANDIDATE_FAILURE_FILE), &failure);
        *self
            .candidate_failure
            .write()
            .expect("embedding candidate failure lock poisoned") = Some(failure);
    }

    fn clear_candidate_failure(&self) {
        let path = self.root.join(CANDIDATE_FAILURE_FILE);
        if let Err(error) = std::fs::remove_file(path)
            && error.kind() != std::io::ErrorKind::NotFound
        {
            // Failure provenance is diagnostic only. A successfully activated
            // provider must not be made unavailable because stale diagnostics
            // could not be deleted.
        }
        *self
            .candidate_failure
            .write()
            .expect("embedding candidate failure lock poisoned") = None;
    }
}

struct UpgradeGuard<'a> {
    in_progress: &'a AtomicBool,
}

impl<'a> UpgradeGuard<'a> {
    fn begin(in_progress: &'a AtomicBool) -> Result<Self, ApplicationError> {
        in_progress
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| {
                ApplicationError::Conflict("semantic embedding upgrade is already in progress")
            })?;
        Ok(Self { in_progress })
    }
}

impl Drop for UpgradeGuard<'_> {
    fn drop(&mut self) {
        self.in_progress.store(false, Ordering::Release);
    }
}

fn load_active_provider(
    root: &Path,
    runtime: &dyn LocalEmbeddingRuntime,
) -> Result<Option<Arc<dyn EmbeddingProvider>>, ApplicationError> {
    let manifest_path = root.join(ACTIVE_MANIFEST_FILE);
    if let Some(manifest) = read_json::<ActiveEmbeddingManifest>(&manifest_path)? {
        if manifest.schema_version != LIFECYCLE_SCHEMA_VERSION {
            return Err(ApplicationError::Invalid(
                "unsupported embedding lifecycle manifest version".into(),
            ));
        }
        let directory = safe_relative_directory(&manifest.directory)?;
        let active_dir = root.join(directory);
        validate_artifact_integrity(&active_dir, &manifest.artifacts)?;
        let provider = runtime
            .load(&active_dir)?
            .ok_or(ApplicationError::Conflict(
                "active semantic embedding model is missing",
            ))?;
        let descriptor = validate_candidate(provider.as_ref())?;
        if descriptor != manifest.descriptor {
            return Err(ApplicationError::Conflict(
                "active semantic embedding model no longer matches its manifest",
            ));
        }
        return Ok(Some(provider));
    }

    // Compatibility for installations created before the candidate/active
    // lifecycle existed. The legacy root remains last-good until a successful
    // upgrade publishes an active manifest.
    runtime.load(root)
}

fn validate_final_version(
    runtime: &dyn LocalEmbeddingRuntime,
    version_dir: &Path,
    expected_descriptor: &EmbeddingModelDescriptor,
    expected_artifacts: &[ArtifactIntegrity],
) -> Result<Arc<dyn EmbeddingProvider>, ApplicationError> {
    validate_artifact_integrity(version_dir, expected_artifacts)?;
    let provider = runtime
        .load(version_dir)?
        .ok_or(ApplicationError::Conflict(
            "embedding candidate disappeared before activation",
        ))?;
    let descriptor = validate_candidate(provider.as_ref())?;
    if &descriptor != expected_descriptor {
        return Err(ApplicationError::Conflict(
            "embedding candidate changed during activation",
        ));
    }
    Ok(provider)
}

fn validate_candidate(
    provider: &dyn EmbeddingProvider,
) -> Result<EmbeddingModelDescriptor, ApplicationError> {
    let descriptor = provider.descriptor().ok_or_else(|| {
        ApplicationError::Invalid("embedding candidate has no model descriptor".into())
    })?;
    if !descriptor.local
        || descriptor.dimension == 0
        || descriptor.model_fingerprint.len() != 64
        || !descriptor
            .model_fingerprint
            .chars()
            .all(|value| value.is_ascii_hexdigit())
        || descriptor.artifact_sha256.len() != 64
        || !descriptor
            .artifact_sha256
            .chars()
            .all(|value| value.is_ascii_hexdigit())
    {
        return Err(ApplicationError::Invalid(
            "embedding candidate descriptor failed validation".into(),
        ));
    }
    Ok(descriptor)
}

fn artifact_integrity(root: &Path) -> Result<Vec<ArtifactIntegrity>, ApplicationError> {
    fn visit(
        root: &Path,
        directory: &Path,
        artifacts: &mut Vec<ArtifactIntegrity>,
    ) -> Result<(), ApplicationError> {
        let mut entries = std::fs::read_dir(directory)
            .map_err(external)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(external)?;
        entries.sort_by_key(|entry| entry.file_name());
        for entry in entries {
            let path = entry.path();
            let metadata = std::fs::metadata(&path).map_err(external)?;
            if metadata.is_dir() {
                visit(root, &path, artifacts)?;
            } else if metadata.is_file() {
                let relative = path.strip_prefix(root).map_err(external)?;
                let relative = relative.to_string_lossy().into_owned();
                safe_relative_directory(&relative)?;
                artifacts.push(ArtifactIntegrity {
                    path: relative,
                    size_bytes: metadata.len(),
                    sha256: hash_file(&path)?,
                });
            }
        }
        Ok(())
    }

    let mut artifacts = Vec::new();
    visit(root, root, &mut artifacts)?;
    artifacts.sort_by(|left, right| left.path.cmp(&right.path));
    Ok(artifacts)
}

fn validate_artifact_integrity(
    root: &Path,
    expected: &[ArtifactIntegrity],
) -> Result<(), ApplicationError> {
    if expected.is_empty() {
        return Err(ApplicationError::Invalid(
            "embedding active manifest has no artifact integrity records".into(),
        ));
    }
    let actual = artifact_integrity(root)?;
    if actual != expected {
        return Err(ApplicationError::Conflict(
            "embedding artifacts failed size or checksum validation",
        ));
    }
    Ok(())
}

fn hash_file(path: &Path) -> Result<String, ApplicationError> {
    let mut file = File::open(path).map_err(external)?;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer).map_err(external)?;
        if read == 0 {
            break;
        }
        digest.update(&buffer[..read]);
    }
    Ok(hex::encode(digest.finalize()))
}

fn safe_relative_directory(value: &str) -> Result<PathBuf, ApplicationError> {
    let path = Path::new(value);
    if path.as_os_str().is_empty()
        || path.is_absolute()
        || path
            .components()
            .any(|component| !matches!(component, std::path::Component::Normal(_)))
    {
        return Err(ApplicationError::Invalid(
            "embedding active directory is invalid".into(),
        ));
    }
    Ok(path.to_path_buf())
}

fn next_candidate_id() -> String {
    format!(
        "{}-{}-{}",
        application::now_ms(),
        std::process::id(),
        NEXT_CANDIDATE_ID.fetch_add(1, Ordering::Relaxed)
    )
}

fn cleanup_incomplete_installations(root: &Path) {
    let candidates = root.join(CANDIDATES_DIR);
    if let Err(error) = std::fs::remove_dir_all(candidates)
        && error.kind() != std::io::ErrorKind::NotFound
    {
        // Candidate directories are never active. Cleanup is best-effort so a
        // filesystem permission issue cannot hide an otherwise valid last-good
        // provider during restart.
    }

    let active_relative = match std::fs::read(root.join(ACTIVE_MANIFEST_FILE)) {
        Ok(bytes) => match serde_json::from_slice::<ActiveEmbeddingManifest>(&bytes)
            .ok()
            .and_then(|manifest| safe_relative_directory(&manifest.directory).ok())
        {
            Some(directory) => Some(directory),
            None => return,
        },
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(_) => return,
    };
    let versions = root.join(VERSIONS_DIR);
    let Ok(entries) = std::fs::read_dir(&versions) else {
        return;
    };
    for entry in entries.flatten() {
        let relative = PathBuf::from(VERSIONS_DIR).join(entry.file_name());
        if Some(&relative) != active_relative.as_ref() {
            remove_path_if_present(&entry.path());
        }
    }
}

fn remove_path_if_present(path: &Path) {
    if let Err(error) = std::fs::remove_dir_all(path)
        && error.kind() != std::io::ErrorKind::NotFound
    {
        // The path is not active. A later restart retries candidate/orphan
        // cleanup without changing the selected active manifest.
    }
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> Result<Option<T>, ApplicationError> {
    match std::fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(|error| ApplicationError::Invalid(error.to_string())),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(external(error)),
    }
}

fn atomic_write_json<T: Serialize>(path: &Path, value: &T) -> Result<(), ApplicationError> {
    let parent = path.parent().ok_or_else(|| {
        ApplicationError::Invalid("embedding lifecycle path has no parent".into())
    })?;
    std::fs::create_dir_all(parent).map_err(external)?;
    let temp_path = parent.join(format!(
        ".{}.tmp-{}",
        path.file_name().unwrap_or_default().to_string_lossy(),
        next_candidate_id()
    ));
    let bytes = serde_json::to_vec_pretty(value)
        .map_err(|error| ApplicationError::ExternalProcess(error.to_string()))?;
    let result = (|| {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temp_path)
            .map_err(external)?;
        file.write_all(&bytes).map_err(external)?;
        file.sync_all().map_err(external)?;
        std::fs::rename(&temp_path, path).map_err(external)?;
        sync_directory(parent)
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&temp_path);
    }
    result
}

fn sync_directory(path: &Path) -> Result<(), ApplicationError> {
    File::open(path)
        .and_then(|directory| directory.sync_all())
        .map_err(external)
}

#[async_trait]
impl EmbeddingProvider for ManagedFastEmbedProvider {
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
        if self.status() != SemanticEmbeddingStatus::Ready {
            return None;
        }
        self.provider
            .read()
            .expect("embedding provider lock poisoned")
            .as_ref()
            .and_then(|provider| provider.descriptor())
    }

    fn status(&self) -> SemanticEmbeddingStatus {
        *self.status.read().expect("embedding status lock poisoned")
    }

    async fn embed(
        &self,
        purpose: EmbeddingPurpose,
        texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError> {
        if self.status() != SemanticEmbeddingStatus::Ready {
            return Err(ApplicationError::Conflict(
                "semantic embedding is not ready",
            ));
        }
        let provider = self
            .provider
            .read()
            .expect("embedding provider lock poisoned")
            .clone()
            .ok_or(ApplicationError::Conflict(
                "semantic embedding model is not installed",
            ))?;
        provider.embed(purpose, texts).await
    }
}

#[derive(Clone)]
pub struct OpenAiCompatibleEmbeddingProvider {
    client: reqwest::Client,
    endpoint: String,
    api_key: Option<String>,
    descriptor: EmbeddingModelDescriptor,
}

impl OpenAiCompatibleEmbeddingProvider {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        base_url: &str,
        api_key: Option<String>,
        model_id: &str,
        model_version: &str,
        runtime_version: &str,
        dimension: u32,
        normalization: &str,
    ) -> Result<Self, ApplicationError> {
        if dimension == 0 || model_id.trim().is_empty() || model_version.trim().is_empty() {
            return Err(ApplicationError::Invalid(
                "remote embedding descriptor is incomplete".into(),
            ));
        }
        let endpoint = format!("{}/embeddings", base_url.trim_end_matches('/'));
        let descriptor = make_descriptor(
            "openai-compatible-http",
            model_id,
            model_version,
            runtime_version,
            "remote-artifact-unavailable",
            dimension,
            normalization,
            "wire-compatible; symmetric input; no implicit purpose prefix",
            false,
        );
        Ok(Self {
            client: reqwest::Client::new(),
            endpoint,
            api_key,
            descriptor,
        })
    }
}

#[derive(Serialize)]
struct CompatibleRequest<'a> {
    model: &'a str,
    input: &'a [String],
    encoding_format: &'static str,
    dimensions: u32,
}

#[derive(Deserialize)]
struct CompatibleResponse {
    data: Vec<CompatibleEmbedding>,
}

#[derive(Deserialize)]
struct CompatibleEmbedding {
    index: usize,
    embedding: Vec<f32>,
}

#[async_trait]
impl EmbeddingProvider for OpenAiCompatibleEmbeddingProvider {
    fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
        Some(self.descriptor.clone())
    }

    async fn embed(
        &self,
        _purpose: EmbeddingPurpose,
        texts: &[String],
    ) -> Result<Vec<Vec<f32>>, ApplicationError> {
        if texts.is_empty() || texts.iter().any(|text| text.trim().is_empty()) {
            return Err(ApplicationError::Validation("embedding text"));
        }
        let mut request = self.client.post(&self.endpoint).json(&CompatibleRequest {
            model: &self.descriptor.model_id,
            input: texts,
            encoding_format: "float",
            dimensions: self.descriptor.dimension,
        });
        if let Some(api_key) = &self.api_key {
            request = request.bearer_auth(api_key);
        }
        let response = request.send().await.map_err(external)?;
        if !response.status().is_success() {
            return Err(ApplicationError::ExternalProcess(format!(
                "embedding provider returned HTTP {}",
                response.status()
            )));
        }
        let mut body: CompatibleResponse = response.json().await.map_err(external)?;
        body.data.sort_by_key(|item| item.index);
        Ok(body.data.into_iter().map(|item| item.embedding).collect())
    }
}

fn installed_descriptor(cache_dir: &Path) -> Result<EmbeddingModelDescriptor, ApplicationError> {
    let repository = cache_dir.join(MODEL_REPOSITORY);
    let revision = std::fs::read_to_string(repository.join("refs/main")).map_err(external)?;
    let revision = revision.trim();
    let model_link = repository
        .join("snapshots")
        .join(revision)
        .join("model.onnx");
    let artifact_sha256 = model_link
        .read_link()
        .ok()
        .and_then(|path| {
            path.file_name()
                .map(|name| name.to_string_lossy().into_owned())
        })
        .filter(|name| name.len() == 64 && name.chars().all(|ch| ch.is_ascii_hexdigit()))
        .ok_or_else(|| {
            ApplicationError::Invalid(
                "embedding model artifact has no verifiable SHA-256 cache identity".into(),
            )
        })?;
    Ok(make_descriptor(
        "fastembed-local",
        "sentence-transformers/all-MiniLM-L6-v2",
        revision,
        "fastembed-5.17.3/onnxruntime",
        &artifact_sha256,
        384,
        "mean-pooling; cosine-at-read; output-unit-norm-not-assumed",
        "symmetric input; no purpose prefix",
        true,
    ))
}

#[allow(clippy::too_many_arguments)]
fn make_descriptor(
    provider_id: &str,
    model_id: &str,
    model_version: &str,
    runtime_version: &str,
    artifact_sha256: &str,
    dimension: u32,
    normalization: &str,
    purpose_contract: &str,
    local: bool,
) -> EmbeddingModelDescriptor {
    let contract = format!(
        "{provider_id}\0{model_id}\0{model_version}\0{runtime_version}\0{artifact_sha256}\0{dimension}\0{normalization}\0{purpose_contract}\0{SEMANTIC_INDEX_SCHEMA_VERSION}"
    );
    EmbeddingModelDescriptor {
        provider_id: provider_id.into(),
        model_id: model_id.into(),
        model_version: model_version.into(),
        runtime_version: runtime_version.into(),
        artifact_sha256: artifact_sha256.into(),
        dimension,
        normalization: normalization.into(),
        purpose_contract: purpose_contract.into(),
        index_schema_version: SEMANTIC_INDEX_SCHEMA_VERSION,
        model_fingerprint: hex::encode(Sha256::digest(contract.as_bytes())),
        local,
    }
}

fn external(error: impl std::fmt::Display) -> ApplicationError {
    ApplicationError::ExternalProcess(error.to_string())
}

#[cfg(test)]
mod tests {
    use std::path::Path;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::{Arc, Barrier};

    use super::{
        ActiveEmbeddingManifest, ActiveManifestPublisher, EmbeddingCandidateFailure,
        FilesystemActiveManifestPublisher, FilesystemInstallationRemover, InstallationRemover,
        LocalEmbeddingRuntime, ManagedFastEmbedProvider, OpenAiCompatibleEmbeddingProvider,
        VERSIONS_DIR, make_descriptor,
    };
    use application::{ApplicationError, EmbeddingProvider};
    use async_trait::async_trait;
    use axum::{Json, Router, routing::post};
    use domain::{EmbeddingModelDescriptor, EmbeddingPurpose, SemanticEmbeddingStatus};
    use serde_json::{Value, json};

    #[derive(Clone)]
    struct FakeProvider {
        descriptor: EmbeddingModelDescriptor,
    }

    #[async_trait]
    impl EmbeddingProvider for FakeProvider {
        fn descriptor(&self) -> Option<EmbeddingModelDescriptor> {
            Some(self.descriptor.clone())
        }

        async fn embed(
            &self,
            _purpose: EmbeddingPurpose,
            texts: &[String],
        ) -> Result<Vec<Vec<f32>>, ApplicationError> {
            Ok(texts
                .iter()
                .map(|_| vec![self.descriptor.model_version.parse().unwrap_or(0.0)])
                .collect())
        }
    }

    struct FakeRuntime {
        next_version: AtomicUsize,
        fail_install: AtomicBool,
        invalid_checksum: AtomicBool,
        install_barrier: Option<Arc<Barrier>>,
    }

    impl FakeRuntime {
        fn new() -> Self {
            Self {
                next_version: AtomicUsize::new(1),
                fail_install: AtomicBool::new(false),
                invalid_checksum: AtomicBool::new(false),
                install_barrier: None,
            }
        }

        fn blocking(barrier: Arc<Barrier>) -> Self {
            Self {
                install_barrier: Some(barrier),
                ..Self::new()
            }
        }
    }

    impl LocalEmbeddingRuntime for FakeRuntime {
        fn install(
            &self,
            cache_dir: &Path,
        ) -> Result<Arc<dyn EmbeddingProvider>, ApplicationError> {
            std::fs::create_dir_all(cache_dir).map_err(super::external)?;
            std::fs::write(cache_dir.join("partial-download"), b"bytes")
                .map_err(super::external)?;
            if let Some(barrier) = &self.install_barrier {
                barrier.wait();
                barrier.wait();
            }
            if self.fail_install.load(Ordering::SeqCst) {
                return Err(ApplicationError::ExternalProcess(
                    "fixture download interrupted".into(),
                ));
            }
            let version = self.next_version.fetch_add(1, Ordering::SeqCst);
            let artifact_sha256 = if self.invalid_checksum.load(Ordering::SeqCst) {
                "not-a-checksum".to_owned()
            } else {
                format!("{version:064x}")
            };
            let descriptor = make_descriptor(
                "fake-local",
                "fixture",
                &version.to_string(),
                "fixture-runtime",
                &artifact_sha256,
                1,
                "fixture",
                "fixture",
                true,
            );
            std::fs::write(
                cache_dir.join("fake.json"),
                serde_json::to_vec(&descriptor).unwrap(),
            )
            .map_err(super::external)?;
            Ok(Arc::new(FakeProvider { descriptor }))
        }

        fn load(
            &self,
            cache_dir: &Path,
        ) -> Result<Option<Arc<dyn EmbeddingProvider>>, ApplicationError> {
            let path = cache_dir.join("fake.json");
            let bytes = match std::fs::read(path) {
                Ok(value) => value,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
                Err(error) => return Err(super::external(error)),
            };
            let descriptor = serde_json::from_slice(&bytes)
                .map_err(|error| ApplicationError::Invalid(error.to_string()))?;
            Ok(Some(Arc::new(FakeProvider { descriptor })))
        }
    }

    struct FailingPublisher;

    impl ActiveManifestPublisher for FailingPublisher {
        fn publish(
            &self,
            _root: &Path,
            _manifest: &ActiveEmbeddingManifest,
        ) -> Result<(), ApplicationError> {
            Err(ApplicationError::ExternalProcess(
                "fixture activation failed".into(),
            ))
        }
    }

    struct PublishThenFail;

    impl ActiveManifestPublisher for PublishThenFail {
        fn publish(
            &self,
            root: &Path,
            manifest: &ActiveEmbeddingManifest,
        ) -> Result<(), ApplicationError> {
            FilesystemActiveManifestPublisher.publish(root, manifest)?;
            Err(ApplicationError::ExternalProcess(
                "fixture directory sync failed after publication".into(),
            ))
        }
    }

    struct FailingRemover;

    impl InstallationRemover for FailingRemover {
        fn remove(&self, _root: &Path) -> Result<(), ApplicationError> {
            Err(ApplicationError::ExternalProcess(
                "fixture uninstall removal failed".into(),
            ))
        }
    }

    fn manager_with(
        root: &Path,
        runtime: Arc<dyn LocalEmbeddingRuntime>,
        publisher: Arc<dyn ActiveManifestPublisher>,
    ) -> ManagedFastEmbedProvider {
        manager_with_remover(
            root,
            runtime,
            publisher,
            Arc::new(FilesystemInstallationRemover),
        )
    }

    fn manager_with_remover(
        root: &Path,
        runtime: Arc<dyn LocalEmbeddingRuntime>,
        publisher: Arc<dyn ActiveManifestPublisher>,
        remover: Arc<dyn InstallationRemover>,
    ) -> ManagedFastEmbedProvider {
        ManagedFastEmbedProvider::with_components(root.to_path_buf(), runtime, publisher, remover)
    }

    fn assert_failure(
        failure: Option<EmbeddingCandidateFailure>,
        phase: &str,
    ) -> EmbeddingCandidateFailure {
        let failure = failure.expect("candidate failure");
        assert_eq!(failure.phase, phase);
        assert!(!failure.candidate_id.is_empty());
        assert!(failure.attempted_at_ms > 0);
        assert!(!failure.detail.is_empty());
        failure
    }

    #[tokio::test]
    async fn compatible_adapter_orders_vectors_and_keeps_space_explicit() {
        async fn embeddings(Json(body): Json<Value>) -> Json<Value> {
            assert_eq!(body["model"], "test-model");
            Json(json!({"data":[
                {"index":1,"embedding":[0.0,1.0]},
                {"index":0,"embedding":[1.0,0.0]}
            ]}))
        }
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(
                listener,
                Router::new().route("/v1/embeddings", post(embeddings)),
            )
            .await
            .unwrap();
        });
        let provider = OpenAiCompatibleEmbeddingProvider::new(
            &format!("http://{address}/v1"),
            None,
            "test-model",
            "revision-a",
            "fixture-1",
            2,
            "l2-normalized",
        )
        .unwrap();
        let vectors = provider
            .embed(EmbeddingPurpose::Document, &["a".into(), "b".into()])
            .await
            .unwrap();
        assert_eq!(vectors, vec![vec![1.0, 0.0], vec![0.0, 1.0]]);
        assert!(!provider.descriptor().unwrap().local);
    }

    #[test]
    fn enable_without_an_installed_model_reports_failed_capability() {
        let cache_dir =
            std::env::temp_dir().join(format!("llplayer-embedding-missing-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&cache_dir);
        let provider = ManagedFastEmbedProvider::new(cache_dir);

        assert!(provider.enable().is_err());
        assert_eq!(provider.status(), SemanticEmbeddingStatus::Failed);
    }

    #[tokio::test]
    async fn successful_candidate_activation_survives_restart_and_cleans_partial_candidates() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Arc::new(FakeRuntime::new());
        let manager = manager_with(
            directory.path(),
            runtime.clone(),
            Arc::new(FilesystemActiveManifestPublisher),
        );

        manager.install().await.unwrap();
        let active = manager.descriptor().unwrap();
        assert_eq!(active.model_version, "1");
        let manifest: ActiveEmbeddingManifest =
            serde_json::from_slice(&std::fs::read(directory.path().join("active.json")).unwrap())
                .unwrap();
        assert!(manifest.directory.starts_with("versions/"));
        assert!(!manifest.directory.contains("candidates"));
        assert!(!manifest.artifacts.is_empty());

        let partial = directory.path().join("candidates/interrupted");
        std::fs::create_dir_all(&partial).unwrap();
        std::fs::write(partial.join("download.partial"), b"partial").unwrap();
        let orphan = directory.path().join("versions/orphaned-before-publish");
        std::fs::create_dir_all(&orphan).unwrap();
        std::fs::write(orphan.join("model.partial"), b"partial").unwrap();

        let restarted = manager_with(
            directory.path(),
            runtime,
            Arc::new(FilesystemActiveManifestPublisher),
        );
        assert_eq!(restarted.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(restarted.descriptor(), Some(active));
        assert!(!directory.path().join("candidates").exists());
        assert!(!orphan.exists());
    }

    #[tokio::test]
    async fn interrupted_download_retains_last_good_provider_status_and_failure_provenance() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Arc::new(FakeRuntime::new());
        let manager = manager_with(
            directory.path(),
            runtime.clone(),
            Arc::new(FilesystemActiveManifestPublisher),
        );
        manager.install().await.unwrap();
        let last_good = manager.descriptor().unwrap();
        runtime.fail_install.store(true, Ordering::SeqCst);

        assert!(manager.install().await.is_err());
        assert_eq!(manager.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(manager.descriptor(), Some(last_good));
        assert_eq!(
            manager
                .embed(EmbeddingPurpose::Query, &["still ready".into()])
                .await
                .unwrap(),
            vec![vec![1.0]]
        );
        assert_failure(manager.candidate_failure(), "build");
        assert!(
            directory
                .path()
                .join("candidates")
                .read_dir()
                .map(|mut entries| entries.next().is_none())
                .unwrap_or(true)
        );

        let restarted = manager_with(
            directory.path(),
            runtime,
            Arc::new(FilesystemActiveManifestPublisher),
        );
        assert_eq!(restarted.status(), SemanticEmbeddingStatus::Ready);
        assert_failure(restarted.candidate_failure(), "build");
    }

    #[tokio::test]
    async fn checksum_validation_failure_retains_last_good_active_identity() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Arc::new(FakeRuntime::new());
        let manager = manager_with(
            directory.path(),
            runtime.clone(),
            Arc::new(FilesystemActiveManifestPublisher),
        );
        manager.install().await.unwrap();
        let last_good = manager.descriptor().unwrap();
        runtime.invalid_checksum.store(true, Ordering::SeqCst);

        assert!(manager.install().await.is_err());
        assert_eq!(manager.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(manager.descriptor(), Some(last_good));
        assert_failure(manager.candidate_failure(), "validation");
        assert_eq!(
            directory
                .path()
                .join(VERSIONS_DIR)
                .read_dir()
                .unwrap()
                .count(),
            1
        );
    }

    #[tokio::test]
    async fn restart_rejects_an_active_version_whose_recorded_artifact_was_modified() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Arc::new(FakeRuntime::new());
        let manager = manager_with(
            directory.path(),
            runtime.clone(),
            Arc::new(FilesystemActiveManifestPublisher),
        );
        manager.install().await.unwrap();
        let manifest: ActiveEmbeddingManifest =
            serde_json::from_slice(&std::fs::read(directory.path().join("active.json")).unwrap())
                .unwrap();
        std::fs::write(
            directory.path().join(&manifest.directory).join("fake.json"),
            b"tampered",
        )
        .unwrap();

        let restarted = manager_with(
            directory.path(),
            runtime,
            Arc::new(FilesystemActiveManifestPublisher),
        );
        assert_eq!(restarted.status(), SemanticEmbeddingStatus::Failed);
        assert!(restarted.descriptor().is_none());
    }

    #[tokio::test]
    async fn activation_failure_retains_last_good_manifest_and_provider() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Arc::new(FakeRuntime::new());
        let initial = manager_with(
            directory.path(),
            runtime.clone(),
            Arc::new(FilesystemActiveManifestPublisher),
        );
        initial.install().await.unwrap();
        let last_good = initial.descriptor().unwrap();
        drop(initial);

        let manager = manager_with(
            directory.path(),
            runtime.clone(),
            Arc::new(FailingPublisher),
        );
        assert!(manager.install().await.is_err());
        assert_eq!(manager.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(manager.descriptor(), Some(last_good.clone()));
        assert_failure(manager.candidate_failure(), "activation");

        let restarted = manager_with(
            directory.path(),
            runtime,
            Arc::new(FilesystemActiveManifestPublisher),
        );
        assert_eq!(restarted.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(restarted.descriptor(), Some(last_good));
    }

    #[tokio::test]
    async fn post_publication_error_keeps_both_current_process_and_restart_consistent() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Arc::new(FakeRuntime::new());
        let initial = manager_with(
            directory.path(),
            runtime.clone(),
            Arc::new(FilesystemActiveManifestPublisher),
        );
        initial.install().await.unwrap();
        let old_active = initial.descriptor().unwrap();
        drop(initial);

        let manager = manager_with(directory.path(), runtime.clone(), Arc::new(PublishThenFail));
        assert!(manager.install().await.is_err());
        assert_eq!(manager.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(manager.descriptor(), Some(old_active));
        assert_failure(manager.candidate_failure(), "activation");
        drop(manager);

        let restarted = manager_with(
            directory.path(),
            runtime,
            Arc::new(FilesystemActiveManifestPublisher),
        );
        assert_eq!(restarted.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(
            restarted.descriptor().unwrap().model_version,
            "2",
            "restart follows the successfully published manifest"
        );
    }

    #[tokio::test]
    async fn uninstall_removal_failure_preserves_last_good_provider_and_status() {
        let directory = tempfile::tempdir().unwrap();
        let runtime = Arc::new(FakeRuntime::new());
        let initial = manager_with(
            directory.path(),
            runtime.clone(),
            Arc::new(FilesystemActiveManifestPublisher),
        );
        initial.install().await.unwrap();
        let last_good = initial.descriptor().unwrap();
        drop(initial);

        let manager = manager_with_remover(
            directory.path(),
            runtime,
            Arc::new(FilesystemActiveManifestPublisher),
            Arc::new(FailingRemover),
        );
        assert!(manager.uninstall().is_err());
        assert_eq!(manager.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(manager.descriptor(), Some(last_good));
        assert_eq!(
            manager
                .embed(EmbeddingPurpose::Query, &["still installed".into()])
                .await
                .unwrap(),
            vec![vec![1.0]]
        );
        assert!(directory.path().join("active.json").exists());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn concurrent_upgrade_is_rejected_without_touching_candidate_or_active_state() {
        let directory = tempfile::tempdir().unwrap();
        let barrier = Arc::new(Barrier::new(2));
        let runtime = Arc::new(FakeRuntime::blocking(barrier.clone()));
        let manager = Arc::new(manager_with(
            directory.path(),
            runtime,
            Arc::new(FilesystemActiveManifestPublisher),
        ));
        let first_manager = manager.clone();
        let first = tokio::spawn(async move { first_manager.install().await });
        barrier.wait();

        let concurrent = manager.install().await;
        assert!(matches!(
            concurrent,
            Err(ApplicationError::Conflict(
                "semantic embedding upgrade is already in progress"
            ))
        ));
        barrier.wait();
        first.await.unwrap().unwrap();
        assert_eq!(manager.status(), SemanticEmbeddingStatus::Ready);
        assert_eq!(
            directory
                .path()
                .join(VERSIONS_DIR)
                .read_dir()
                .unwrap()
                .count(),
            1
        );
    }
}
