use std::path::{Path, PathBuf};
use std::sync::Arc;

use application::{
    SyntacticAnalysisDraft, SyntacticAnalysisProvider, SyntacticAnalysisRequest,
    SyntacticCapabilityStatus, SyntacticProviderCapability,
};
use async_trait::async_trait;
use domain::{LanguageCode, SyntacticProviderError};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use syntactic_provider::PythonSyntacticProvider;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;
use tokio::sync::{Mutex, RwLock};
use tokio::task::JoinHandle;

const RUNTIME_VERSION: &str = "3.8.13";
const MODEL_VERSION: &str = "3.8.0";
const MODEL_CHECKSUM: &str = "adda6df4860f555a57e6e31635f233359ab471dafa177d58d96a8d4198450a7c";
const EXPECTED_BYTES: u64 = 162_250_752;
const PROVIDER_VERSION: &str = "jsonl-v2";
const REQUIREMENTS: &str =
    include_str!("../../../scripts/syntactic-analysis/requirements-spacy-product.txt");
const SIDECAR: &str = include_str!("../../../scripts/syntactic-analysis/syntax-sidecar.py");
const ACTIVE_PROVIDER_ID: &str = "spacy";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyntaxCapabilityStatus {
    NotInstalled,
    Downloading,
    Ready,
    Partial,
    Failed,
    Stale,
    Disabled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct SyntaxCapabilityView {
    pub status: SyntaxCapabilityStatus,
    pub progress: f32,
    pub enabled: bool,
    pub runtime_version: String,
    pub provider_version: String,
    pub model_version: String,
    pub model_checksum_sha256: String,
    pub expected_install_bytes: u64,
    pub delivery_checksum_sha256: String,
    pub installed_bytes: u64,
    pub error: Option<String>,
    pub updated_at_ms: u64,
}

impl Default for SyntaxCapabilityView {
    fn default() -> Self {
        Self {
            status: SyntaxCapabilityStatus::NotInstalled,
            progress: 0.0,
            enabled: false,
            runtime_version: RUNTIME_VERSION.into(),
            provider_version: PROVIDER_VERSION.into(),
            model_version: MODEL_VERSION.into(),
            model_checksum_sha256: MODEL_CHECKSUM.into(),
            expected_install_bytes: EXPECTED_BYTES,
            delivery_checksum_sha256: delivery_checksum(),
            installed_bytes: 0,
            error: None,
            updated_at_ms: now_ms(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SyntaxCandidateFailureStage {
    Prepare,
    Install,
    Validate,
    Activate,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyntaxCandidateFailure {
    pub candidate_id: String,
    pub stage: SyntaxCandidateFailureStage,
    pub detail: String,
    pub failed_at_ms: u64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
struct SyntaxUpgradeState {
    active_directory: Option<PathBuf>,
    active_enabled: bool,
    last_candidate_failure: Option<SyntaxCandidateFailure>,
    cleanup_debt: Option<PathBuf>,
    journal_sync_debt: Option<String>,
}

#[derive(Debug)]
struct CandidateInstallFailure {
    candidate_id: String,
    directory: PathBuf,
    stage: SyntaxCandidateFailureStage,
    detail: String,
}

pub struct SyntaxCapabilityManager {
    root: PathBuf,
    install_dir: PathBuf,
    state_path: PathBuf,
    upgrade_state_path: PathBuf,
    state: Mutex<SyntaxCapabilityView>,
    upgrade_state: Mutex<SyntaxUpgradeState>,
    task: Mutex<Option<JoinHandle<()>>>,
    activation: Mutex<()>,
    active_provider: RwLock<Option<Arc<PythonSyntacticProvider>>>,
}

impl SyntaxCapabilityManager {
    pub fn unmanaged() -> Arc<Self> {
        let root =
            std::env::temp_dir().join(format!("llplayer-syntax-unmanaged-{}", std::process::id()));
        Self::new(root, None)
    }

    pub fn new(
        root: impl Into<PathBuf>,
        provider: Option<Arc<PythonSyntacticProvider>>,
    ) -> Arc<Self> {
        let root = root.into();
        let install_dir = root.join(format!(
            "spacy-{RUNTIME_VERSION}-en_core_web_sm-{MODEL_VERSION}"
        ));
        let state_path = root.join("capability-state.json");
        let upgrade_state_path = root.join("syntax-upgrade-state.json");
        let mut state = read_state(&state_path).unwrap_or_default();
        let upgrade_state = read_upgrade_state(&upgrade_state_path).unwrap_or_default();
        if let Some(active_directory) = upgrade_state
            .active_directory
            .as_ref()
            .filter(|directory| directory.is_dir())
        {
            state.status = if upgrade_state.active_enabled {
                SyntaxCapabilityStatus::Ready
            } else {
                SyntaxCapabilityStatus::Disabled
            };
            state.progress = 1.0;
            state.enabled = upgrade_state.active_enabled;
            state.error = None;
            state.installed_bytes = directory_size(active_directory);
        }
        let provider = upgrade_state
            .active_directory
            .as_ref()
            .filter(|directory| directory.is_dir())
            .map(|directory| Arc::new(provider_for_directory(directory)))
            .or(provider);
        cleanup_inactive_releases(&root, upgrade_state.active_directory.as_deref());
        Arc::new(Self {
            root,
            install_dir,
            state_path,
            upgrade_state_path,
            state: Mutex::new(state),
            upgrade_state: Mutex::new(upgrade_state),
            task: Mutex::new(None),
            activation: Mutex::new(()),
            active_provider: RwLock::new(provider),
        })
    }

    pub fn install_dir(&self) -> &Path {
        &self.install_dir
    }

    pub fn cache_dir(&self) -> PathBuf {
        self.root.join("track-cache")
    }

    pub async fn active_directory(&self) -> PathBuf {
        self.upgrade_state
            .lock()
            .await
            .active_directory
            .clone()
            .unwrap_or_else(|| self.install_dir.clone())
    }

    pub async fn candidate_failure_provenance(&self) -> Option<SyntaxCandidateFailure> {
        self.upgrade_state
            .lock()
            .await
            .last_candidate_failure
            .clone()
    }

    pub async fn read_track_cache<T>(&self, track_id: &str) -> Option<T>
    where
        T: serde::de::DeserializeOwned,
    {
        let path = self.cache_dir().join(format!("{track_id}.json"));
        serde_json::from_slice(&tokio::fs::read(path).await.ok()?).ok()
    }

    pub async fn write_track_cache<T>(&self, track_id: &str, entry: &T)
    where
        T: Serialize,
    {
        let directory = self.cache_dir();
        let Ok(json) = serde_json::to_vec(entry) else {
            return;
        };
        if tokio::fs::create_dir_all(&directory).await.is_err() {
            return;
        }
        let path = directory.join(format!("{track_id}.json"));
        let temporary = directory.join(format!("{track_id}.json.tmp"));
        if tokio::fs::write(&temporary, json).await.is_ok() {
            let _ = tokio::fs::rename(temporary, path).await;
        }
    }

    pub async fn view(&self) -> SyntaxCapabilityView {
        let mut state = self.state.lock().await.clone();
        let active_directory = self.active_directory().await;
        if matches!(
            state.status,
            SyntaxCapabilityStatus::Ready | SyntaxCapabilityStatus::Disabled
        ) {
            state.installed_bytes = directory_size(&active_directory);
            if !active_directory.join("venv/bin/python").is_file()
                || !active_directory.join("syntax-sidecar.py").is_file()
            {
                state.status = SyntaxCapabilityStatus::Partial;
                state.enabled = false;
                state.error = Some("installed syntax runtime is incomplete".into());
            }
        }
        state
    }

    pub async fn start_install(self: &Arc<Self>) -> SyntaxCapabilityView {
        let mut task = self.task.lock().await;
        if task.as_ref().is_some_and(|task| !task.is_finished()) {
            return self.view().await;
        }
        let baseline = self.state.lock().await.clone();
        let has_last_good = matches!(
            baseline.status,
            SyntaxCapabilityStatus::Ready | SyntaxCapabilityStatus::Disabled
        ) && self.active_directory().await.is_dir();
        if !has_last_good {
            self.set_state(SyntaxCapabilityStatus::Downloading, 0.01, false, None)
                .await;
        }
        let manager = Arc::clone(self);
        *task = Some(tokio::spawn(async move {
            if let Err(error) = manager.install().await {
                manager
                    .record_candidate_failure(error, has_last_good.then_some(baseline))
                    .await;
            }
        }));
        drop(task);
        self.view().await
    }

    pub async fn cancel(&self) -> SyntaxCapabilityView {
        if let Some(task) = self.task.lock().await.take() {
            task.abort();
            // Wait until the install future has actually dropped its
            // kill-on-drop child before removing staging. Without this join,
            // venv creation can race and recreate the directory after cancel.
            let _ = task.await;
        }
        let _ = tokio::fs::remove_dir_all(self.root.join(".installing")).await;
        cleanup_inactive_releases(&self.root, Some(&self.active_directory().await));
        let active = self.active_directory().await;
        let state = self.state.lock().await.clone();
        let status = if active.is_dir() {
            if state.enabled {
                SyntaxCapabilityStatus::Ready
            } else {
                SyntaxCapabilityStatus::Disabled
            }
        } else {
            SyntaxCapabilityStatus::NotInstalled
        };
        let enabled = status == SyntaxCapabilityStatus::Ready;
        self.set_state(
            status,
            if active.is_dir() { 1.0 } else { 0.0 },
            enabled,
            None,
        )
        .await;
        self.view().await
    }

    pub async fn validate(&self) -> SyntaxCapabilityView {
        let active_directory = self.active_directory().await;
        if !active_directory.is_dir() {
            self.set_state(SyntaxCapabilityStatus::NotInstalled, 0.0, false, None)
                .await;
            return self.view().await;
        }
        let Some(provider) = self.active_provider.read().await.clone() else {
            self.set_state(
                SyntaxCapabilityStatus::Partial,
                0.0,
                false,
                Some("syntax provider is not composed".into()),
            )
            .await;
            return self.view().await;
        };
        let sidecar_matches = tokio::fs::read(active_directory.join("syntax-sidecar.py"))
            .await
            .is_ok_and(|value| value == SIDECAR.as_bytes());
        let requirements_match = tokio::fs::read(active_directory.join("requirements.txt"))
            .await
            .is_ok_and(|value| value == REQUIREMENTS.as_bytes());
        if !sidecar_matches || !requirements_match {
            self.set_state(
                SyntaxCapabilityStatus::Stale,
                0.0,
                false,
                Some("installed syntax delivery files do not match this app version".into()),
            )
            .await;
            return self.view().await;
        }
        match provider
            .probe(&LanguageCode::parse("en").expect("static language"))
            .await
        {
            Ok(capability) if capability.status == SyntacticCapabilityStatus::Ready => {
                let descriptor_ok = capability.descriptor.as_ref().is_some_and(|descriptor| {
                    descriptor.runtime_version == RUNTIME_VERSION
                        && descriptor.provider_version == PROVIDER_VERSION
                        && descriptor.model_version == MODEL_VERSION
                        && descriptor.model_checksum_sha256 == MODEL_CHECKSUM
                });
                if descriptor_ok {
                    let enabled = self.state.lock().await.enabled;
                    self.set_state(
                        if enabled {
                            SyntaxCapabilityStatus::Ready
                        } else {
                            SyntaxCapabilityStatus::Disabled
                        },
                        1.0,
                        enabled,
                        None,
                    )
                    .await;
                } else {
                    self.set_state(
                        SyntaxCapabilityStatus::Stale,
                        0.0,
                        false,
                        Some(
                            "installed syntax identity does not match the qualified manifest"
                                .into(),
                        ),
                    )
                    .await;
                }
            }
            Ok(capability) => {
                self.set_state(
                    SyntaxCapabilityStatus::Partial,
                    0.0,
                    false,
                    Some(format!("syntax probe reported {:?}", capability.status)),
                )
                .await;
            }
            Err(error) => {
                self.set_state(
                    SyntaxCapabilityStatus::Failed,
                    0.0,
                    false,
                    Some(error.to_string()),
                )
                .await;
            }
        }
        self.view().await
    }

    pub async fn set_enabled(&self, enabled: bool) -> SyntaxCapabilityView {
        if !enabled {
            if let Some(provider) = self.active_provider.read().await.clone() {
                provider.shutdown().await;
            }
            self.persist_active_enabled(false).await;
            self.set_state(SyntaxCapabilityStatus::Disabled, 1.0, false, None)
                .await;
        } else {
            {
                let mut state = self.state.lock().await;
                state.enabled = true;
            }
            let view = self.validate().await;
            if view.status == SyntaxCapabilityStatus::Ready && view.enabled {
                self.persist_active_enabled(true).await;
            }
            return view;
        }
        self.view().await
    }

    pub async fn uninstall(&self) -> SyntaxCapabilityView {
        let _ = self.cancel().await;
        let _activation = self.activation.lock().await;
        let active_directory = self.active_directory().await;
        let tombstone = self.root.join(format!(".uninstalling-{}", now_ns()));
        let mut provider_slot = self.active_provider.write().await;
        let moved_active = if active_directory.is_dir() {
            if tokio::fs::rename(&active_directory, &tombstone)
                .await
                .is_err()
            {
                drop(provider_slot);
                return self.view().await;
            }
            true
        } else {
            false
        };
        let reset_upgrade_state = SyntaxUpgradeState::default();
        if persist_upgrade_state(&self.upgrade_state_path, &reset_upgrade_state)
            .await
            .is_err()
        {
            if moved_active {
                let _ = tokio::fs::rename(&tombstone, &active_directory).await;
            }
            drop(provider_slot);
            return self.view().await;
        }
        let previous_provider = provider_slot.take();
        drop(provider_slot);
        *self.upgrade_state.lock().await = reset_upgrade_state;
        if let Some(provider) = previous_provider {
            provider.shutdown().await;
        }
        let _ = tokio::fs::remove_dir_all(&tombstone).await;
        let _ = tokio::fs::remove_dir_all(&self.install_dir).await;
        let _ = tokio::fs::remove_dir_all(self.root.join("releases")).await;
        let _ = tokio::fs::remove_dir_all(self.cache_dir()).await;
        self.set_state(SyntaxCapabilityStatus::NotInstalled, 0.0, false, None)
            .await;
        self.view().await
    }

    pub async fn is_ready(&self) -> bool {
        let view = self.view().await;
        view.enabled && view.status == SyntaxCapabilityStatus::Ready
    }

    pub async fn mark_partial(&self, detail: impl Into<String>) {
        self.set_state(
            SyntaxCapabilityStatus::Partial,
            0.0,
            false,
            Some(detail.into()),
        )
        .await;
    }

    #[doc(hidden)]
    pub async fn assume_ready_for_tests(&self) {
        self.set_state(SyntaxCapabilityStatus::Ready, 1.0, true, None)
            .await;
    }

    async fn install(&self) -> Result<(), CandidateInstallFailure> {
        tokio::fs::create_dir_all(&self.root)
            .await
            .map_err(|error| CandidateInstallFailure {
                candidate_id: "unallocated".into(),
                directory: self.root.join("releases"),
                stage: SyntaxCandidateFailureStage::Prepare,
                detail: format!("create syntax root: {error}"),
            })?;
        let candidate_id = format!("release-{}-{}", &delivery_checksum()[..12], now_ns());
        let candidate_directory = self.root.join("releases").join(&candidate_id);
        tokio::fs::create_dir_all(&candidate_directory)
            .await
            .map_err(|error| CandidateInstallFailure {
                candidate_id: candidate_id.clone(),
                directory: candidate_directory.clone(),
                stage: SyntaxCandidateFailureStage::Prepare,
                detail: format!("create syntax candidate: {error}"),
            })?;
        tokio::fs::write(candidate_directory.join("requirements.txt"), REQUIREMENTS)
            .await
            .map_err(|error| {
                candidate_failure(
                    &candidate_id,
                    &candidate_directory,
                    SyntaxCandidateFailureStage::Prepare,
                    format!("write syntax requirements: {error}"),
                )
            })?;
        tokio::fs::write(candidate_directory.join("syntax-sidecar.py"), SIDECAR)
            .await
            .map_err(|error| {
                candidate_failure(
                    &candidate_id,
                    &candidate_directory,
                    SyntaxCandidateFailureStage::Prepare,
                    format!("write syntax sidecar: {error}"),
                )
            })?;
        self.report_candidate_progress(0.08).await;
        let base_python = discover_python().await.map_err(|detail| {
            candidate_failure(
                &candidate_id,
                &candidate_directory,
                SyntaxCandidateFailureStage::Install,
                detail,
            )
        })?;
        run(&base_python, &["-m", "venv", "venv"], &candidate_directory)
            .await
            .map_err(|detail| {
                candidate_failure(
                    &candidate_id,
                    &candidate_directory,
                    SyntaxCandidateFailureStage::Install,
                    detail,
                )
            })?;
        self.report_candidate_progress(0.15).await;
        let python = candidate_directory.join("venv/bin/python");
        run_path(
            &python,
            &[
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "-r",
                "requirements.txt",
            ],
            &candidate_directory,
        )
        .await
        .map_err(|detail| {
            candidate_failure(
                &candidate_id,
                &candidate_directory,
                SyntaxCandidateFailureStage::Install,
                detail,
            )
        })?;
        self.report_candidate_progress(0.9).await;
        validate_delivery_files(&candidate_directory)
            .await
            .map_err(|detail| {
                candidate_failure(
                    &candidate_id,
                    &candidate_directory,
                    SyntaxCandidateFailureStage::Validate,
                    detail,
                )
            })?;
        let candidate = Arc::new(provider_for_directory(&candidate_directory));
        self.activate_candidate(candidate_id, candidate_directory, candidate)
            .await
    }

    async fn activate_candidate(
        &self,
        candidate_id: String,
        candidate_directory: PathBuf,
        candidate: Arc<PythonSyntacticProvider>,
    ) -> Result<(), CandidateInstallFailure> {
        let _activation = self.activation.lock().await;
        let capability = candidate
            .probe(&LanguageCode::parse("en").expect("static language"))
            .await
            .map_err(|error| {
                candidate_failure(
                    &candidate_id,
                    &candidate_directory,
                    SyntaxCandidateFailureStage::Validate,
                    format!("installed syntax probe failed: {error}"),
                )
            })?;
        let descriptor = capability.descriptor.as_ref().ok_or_else(|| {
            candidate_failure(
                &candidate_id,
                &candidate_directory,
                SyntaxCandidateFailureStage::Validate,
                "installed syntax probe omitted descriptor",
            )
        })?;
        if capability.status != SyntacticCapabilityStatus::Ready
            || descriptor.runtime_version != RUNTIME_VERSION
            || descriptor.provider_version != PROVIDER_VERSION
            || descriptor.model_version != MODEL_VERSION
            || descriptor.model_checksum_sha256 != MODEL_CHECKSUM
        {
            candidate.shutdown().await;
            return Err(candidate_failure(
                &candidate_id,
                &candidate_directory,
                SyntaxCandidateFailureStage::Validate,
                "installed syntax identity failed qualified manifest validation",
            ));
        }

        let previous_directory = self.active_directory().await;
        let current_state = self.state.lock().await.clone();
        let target_enabled = current_state.enabled
            || current_state.status == SyntaxCapabilityStatus::Downloading
            || !previous_directory.is_dir();
        let next_upgrade_state = SyntaxUpgradeState {
            active_directory: Some(candidate_directory.clone()),
            active_enabled: target_enabled,
            last_candidate_failure: None,
            cleanup_debt: None,
            journal_sync_debt: None,
        };
        let mut provider_slot = self.active_provider.write().await;
        let journal_sync_debt =
            persist_upgrade_state(&self.upgrade_state_path, &next_upgrade_state)
                .await
                .map_err(|detail| {
                    candidate_failure(
                        &candidate_id,
                        &candidate_directory,
                        SyntaxCandidateFailureStage::Activate,
                        detail,
                    )
                })?;
        let previous_provider = provider_slot.replace(candidate);
        drop(provider_slot);
        let mut next_upgrade_state = next_upgrade_state;
        next_upgrade_state.journal_sync_debt = journal_sync_debt;
        *self.upgrade_state.lock().await = next_upgrade_state;
        self.set_state(
            if target_enabled {
                SyntaxCapabilityStatus::Ready
            } else {
                SyntaxCapabilityStatus::Disabled
            },
            1.0,
            target_enabled,
            None,
        )
        .await;

        if let Some(previous_provider) = previous_provider {
            previous_provider.shutdown().await;
        }
        if previous_directory != candidate_directory
            && is_managed_release(&self.root, &previous_directory)
            && tokio::fs::remove_dir_all(&previous_directory)
                .await
                .is_err()
        {
            let mut upgrade = self.upgrade_state.lock().await;
            upgrade.cleanup_debt = Some(previous_directory);
            let _ = persist_upgrade_state(&self.upgrade_state_path, &upgrade).await;
        }
        Ok(())
    }

    async fn report_candidate_progress(&self, progress: f32) {
        let mut state = self.state.lock().await;
        if state.status == SyntaxCapabilityStatus::Downloading {
            state.progress = progress;
        }
    }

    async fn persist_active_enabled(&self, enabled: bool) {
        let mut upgrade = self.upgrade_state.lock().await;
        if upgrade.active_directory.is_some() {
            upgrade.active_enabled = enabled;
            let _ = persist_upgrade_state(&self.upgrade_state_path, &upgrade).await;
        }
    }

    async fn record_candidate_failure(
        &self,
        failure: CandidateInstallFailure,
        baseline: Option<SyntaxCapabilityView>,
    ) {
        let cleanup_debt = match tokio::fs::remove_dir_all(&failure.directory).await {
            Ok(()) => None,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
            Err(_) => Some(failure.directory.clone()),
        };
        let provenance = SyntaxCandidateFailure {
            candidate_id: failure.candidate_id,
            stage: failure.stage,
            detail: failure.detail,
            failed_at_ms: now_ms(),
        };
        {
            let mut upgrade = self.upgrade_state.lock().await;
            upgrade.last_candidate_failure = Some(provenance.clone());
            if cleanup_debt.is_some() {
                upgrade.cleanup_debt = cleanup_debt;
            }
            let _ = persist_upgrade_state(&self.upgrade_state_path, &upgrade).await;
        }
        if let Some(baseline) = baseline {
            self.set_state(
                baseline.status,
                baseline.progress,
                baseline.enabled,
                baseline.error,
            )
            .await;
        } else {
            self.set_state(
                SyntaxCapabilityStatus::Failed,
                0.0,
                false,
                Some(provenance.detail),
            )
            .await;
        }
    }

    async fn set_state(
        &self,
        status: SyntaxCapabilityStatus,
        progress: f32,
        enabled: bool,
        error: Option<String>,
    ) {
        let active_directory = self.active_directory().await;
        let snapshot = {
            let mut state = self.state.lock().await;
            state.status = status;
            state.progress = progress.clamp(0.0, 1.0);
            state.enabled = enabled;
            state.error = error;
            state.updated_at_ms = now_ms();
            state.installed_bytes = directory_size(&active_directory);
            state.clone()
        };
        let _ = tokio::fs::create_dir_all(&self.root).await;
        if let Ok(json) = serde_json::to_vec_pretty(&snapshot) {
            let temporary = self.state_path.with_extension("json.tmp");
            if tokio::fs::write(&temporary, json).await.is_ok() {
                let _ = tokio::fs::rename(temporary, &self.state_path).await;
            }
        }
    }
}

#[async_trait]
impl SyntacticAnalysisProvider for SyntaxCapabilityManager {
    fn provider_id(&self) -> &str {
        ACTIVE_PROVIDER_ID
    }

    async fn probe(
        &self,
        language: &LanguageCode,
    ) -> Result<SyntacticProviderCapability, SyntacticProviderError> {
        let provider = self
            .active_provider
            .read()
            .await
            .clone()
            .ok_or(SyntacticProviderError::RuntimeMissing)?;
        provider.probe(language).await
    }

    async fn analyze(
        &self,
        request: &SyntacticAnalysisRequest,
    ) -> Result<SyntacticAnalysisDraft, SyntacticProviderError> {
        let provider = self
            .active_provider
            .read()
            .await
            .clone()
            .ok_or(SyntacticProviderError::RuntimeMissing)?;
        provider.analyze(request).await
    }
}

fn provider_for_directory(directory: &Path) -> PythonSyntacticProvider {
    PythonSyntacticProvider::new(
        syntactic_provider::PythonSyntacticKind::Spacy,
        directory.join("venv/bin/python"),
        directory.join("syntax-sidecar.py"),
    )
}

fn candidate_failure(
    candidate_id: &str,
    directory: &Path,
    stage: SyntaxCandidateFailureStage,
    detail: impl Into<String>,
) -> CandidateInstallFailure {
    CandidateInstallFailure {
        candidate_id: candidate_id.into(),
        directory: directory.into(),
        stage,
        detail: detail.into(),
    }
}

async fn validate_delivery_files(directory: &Path) -> Result<(), String> {
    let sidecar_matches = tokio::fs::read(directory.join("syntax-sidecar.py"))
        .await
        .is_ok_and(|value| value == SIDECAR.as_bytes());
    let requirements_match = tokio::fs::read(directory.join("requirements.txt"))
        .await
        .is_ok_and(|value| value == REQUIREMENTS.as_bytes());
    if sidecar_matches && requirements_match {
        Ok(())
    } else {
        Err("syntax candidate delivery checksum validation failed".into())
    }
}

async fn persist_upgrade_state(
    path: &Path,
    state: &SyntaxUpgradeState,
) -> Result<Option<String>, String> {
    persist_upgrade_state_inner(path, state, false).await
}

async fn persist_upgrade_state_inner(
    path: &Path,
    state: &SyntaxUpgradeState,
    simulate_parent_sync_failure: bool,
) -> Result<Option<String>, String> {
    let parent = path
        .parent()
        .ok_or_else(|| "syntax upgrade state has no parent directory".to_string())?;
    tokio::fs::create_dir_all(parent)
        .await
        .map_err(|error| format!("create syntax upgrade state directory: {error}"))?;
    let json = serde_json::to_vec_pretty(state)
        .map_err(|error| format!("encode syntax upgrade state: {error}"))?;
    let temporary = path.with_extension("json.tmp");
    let mut file = tokio::fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&temporary)
        .await
        .map_err(|error| format!("open syntax upgrade state: {error}"))?;
    file.write_all(&json)
        .await
        .map_err(|error| format!("write syntax upgrade state: {error}"))?;
    file.sync_all()
        .await
        .map_err(|error| format!("sync syntax upgrade state: {error}"))?;
    drop(file);
    tokio::fs::rename(&temporary, path)
        .await
        .map_err(|error| format!("publish syntax upgrade state: {error}"))?;
    if simulate_parent_sync_failure {
        return Ok(Some(
            "simulated syntax upgrade state directory sync failure".into(),
        ));
    }
    let parent = parent.to_path_buf();
    let sync_result = tokio::task::spawn_blocking(move || {
        std::fs::File::open(&parent)
            .and_then(|directory| directory.sync_all())
            .map_err(|error| format!("sync syntax upgrade state directory: {error}"))
    })
    .await;
    Ok(match sync_result {
        Ok(Ok(())) => None,
        Ok(Err(error)) => Some(error),
        Err(error) => Some(format!("join syntax upgrade directory sync: {error}")),
    })
}

fn read_upgrade_state(path: &Path) -> Option<SyntaxUpgradeState> {
    serde_json::from_slice(&std::fs::read(path).ok()?).ok()
}

fn is_managed_release(root: &Path, directory: &Path) -> bool {
    directory.parent() == Some(root.join("releases").as_path())
}

fn cleanup_inactive_releases(root: &Path, active_directory: Option<&Path>) {
    let releases = root.join("releases");
    let Ok(entries) = std::fs::read_dir(releases) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if Some(path.as_path()) != active_directory {
            let _ = std::fs::remove_dir_all(path);
        }
    }
}

async fn discover_python() -> Result<PathBuf, String> {
    for candidate in [
        PathBuf::from("/opt/homebrew/bin/python3.11"),
        PathBuf::from("/usr/local/bin/python3.11"),
        PathBuf::from("python3.11"),
        PathBuf::from("python3"),
    ] {
        let mut command = Command::new(&candidate);
        command.arg("--version");
        if command
            .output()
            .await
            .is_ok_and(|output| output.status.success())
        {
            return Ok(candidate);
        }
    }
    Err("Python 3.11 is required to install the optional syntax capability".into())
}

async fn run(program: &Path, args: &[&str], cwd: &Path) -> Result<(), String> {
    run_path(program, args, cwd).await
}

async fn run_path(program: &Path, args: &[&str], cwd: &Path) -> Result<(), String> {
    let mut command = Command::new(program);
    command.args(args).current_dir(cwd).kill_on_drop(true);
    // Creating a venv can launch ensurepip grandchildren. Killing only the
    // direct child lets those grandchildren recreate staging after Cancel.
    // Give every installer command its own process group and kill the whole
    // group if this future is dropped.
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.as_std_mut().process_group(0);
    }
    let child = command
        .spawn()
        .map_err(|error| format!("run {}: {error}", program.display()))?;
    #[cfg(unix)]
    let mut process_group = ProcessGroupGuard::new(child.id());
    let output = child
        .wait_with_output()
        .await
        .map_err(|error| format!("run {}: {error}", program.display()))?;
    #[cfg(unix)]
    process_group.disarm();
    if output.status.success() {
        Ok(())
    } else {
        let detail = String::from_utf8_lossy(&output.stderr)
            .chars()
            .take(800)
            .collect::<String>();
        Err(format!("{} failed: {detail}", program.display()))
    }
}

#[cfg(unix)]
struct ProcessGroupGuard {
    pid: u32,
    armed: bool,
}

#[cfg(unix)]
impl ProcessGroupGuard {
    fn new(pid: Option<u32>) -> Self {
        Self {
            pid: pid.unwrap_or_default(),
            armed: pid.is_some(),
        }
    }

    fn disarm(&mut self) {
        self.armed = false;
    }
}

#[cfg(unix)]
impl Drop for ProcessGroupGuard {
    fn drop(&mut self) {
        if self.armed {
            let _ = std::process::Command::new("/bin/kill")
                .args(["-KILL", &format!("-{}", self.pid)])
                .status();
        }
    }
}

fn read_state(path: &Path) -> Option<SyntaxCapabilityView> {
    serde_json::from_slice(&std::fs::read(path).ok()?).ok()
}

fn directory_size(path: &Path) -> u64 {
    let Ok(entries) = std::fs::read_dir(path) else {
        return 0;
    };
    entries
        .flatten()
        .map(|entry| {
            entry
                .metadata()
                .map(|metadata| {
                    if metadata.is_dir() {
                        directory_size(&entry.path())
                    } else {
                        metadata.len()
                    }
                })
                .unwrap_or(0)
        })
        .sum()
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn now_ns() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
}

fn delivery_checksum() -> String {
    let mut digest = Sha256::new();
    digest.update(b"syntax-delivery-v1\0");
    digest.update(PROVIDER_VERSION.as_bytes());
    digest.update(RUNTIME_VERSION.as_bytes());
    digest.update(MODEL_VERSION.as_bytes());
    digest.update(MODEL_CHECKSUM.as_bytes());
    digest.update(REQUIREMENTS.as_bytes());
    digest.update(SIDECAR.as_bytes());
    hex::encode(digest.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;

    fn root(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("llplayer-syntax-{name}-{}", now_ms()))
    }

    #[cfg(unix)]
    async fn qualified_provider(
        directory: &Path,
        provider_version: &str,
    ) -> Arc<PythonSyntacticProvider> {
        tokio::fs::create_dir_all(directory.join("venv/bin"))
            .await
            .unwrap();
        let python = directory.join("venv/bin/python");
        tokio::fs::write(&python, b"#!/bin/sh\nexec python3 \"$@\"\n")
            .await
            .unwrap();
        let mut permissions = tokio::fs::metadata(&python).await.unwrap().permissions();
        permissions.set_mode(0o755);
        tokio::fs::set_permissions(&python, permissions)
            .await
            .unwrap();
        let sidecar = format!(
            r#"import argparse, json, sys, time
parser = argparse.ArgumentParser()
parser.add_argument("--provider", required=True)
parser.add_argument("--model", required=True)
args = parser.parse_args()
for line in sys.stdin:
    request = json.loads(line)
    if "{provider_version}" == "slow-old":
        time.sleep(0.3)
    descriptor = {{
        "provider_id": "spacy",
        "provider_version": "{provider_version}",
        "runtime_id": "python",
        "runtime_version": "{RUNTIME_VERSION}",
        "model_id": "en_core_web_sm",
        "model_version": "{MODEL_VERSION}",
        "model_checksum_sha256": "{MODEL_CHECKSUM}"
    }}
    print(json.dumps({{
        "protocol_version": 1,
        "request_id": request["request_id"],
        "ok": True,
        "capability": {{"status": "ready", "descriptor": descriptor}}
    }}), flush=True)
"#
        );
        tokio::fs::write(directory.join("syntax-sidecar.py"), sidecar)
            .await
            .unwrap();
        tokio::fs::write(directory.join("requirements.txt"), REQUIREMENTS)
            .await
            .unwrap();
        Arc::new(provider_for_directory(directory))
    }

    #[tokio::test]
    async fn persisted_state_and_missing_files_report_partial() {
        let root = root("state");
        let manager = SyntaxCapabilityManager::new(&root, None);
        tokio::fs::create_dir_all(manager.install_dir())
            .await
            .unwrap();
        manager.assume_ready_for_tests().await;
        let reloaded = SyntaxCapabilityManager::new(&root, None);
        let view = reloaded.view().await;
        assert_eq!(view.status, SyntaxCapabilityStatus::Partial);
        assert!(!view.enabled);
        assert!(view.error.is_some());
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn cancel_and_uninstall_are_idempotent() {
        let root = root("remove");
        let manager = SyntaxCapabilityManager::new(&root, None);
        let cancelled = manager.cancel().await;
        assert_eq!(cancelled.status, SyntaxCapabilityStatus::NotInstalled);
        let removed = manager.uninstall().await;
        assert_eq!(removed.status, SyntaxCapabilityStatus::NotInstalled);
        assert!(!removed.enabled);
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn cancel_waits_for_task_drop_and_removes_staging() {
        let root = root("cancel-staging");
        let manager = SyntaxCapabilityManager::new(&root, None);
        let staging = root.join(".installing");
        tokio::fs::create_dir_all(&staging).await.unwrap();
        tokio::fs::write(staging.join("partial"), b"partial")
            .await
            .unwrap();
        *manager.task.lock().await = Some(tokio::spawn(async {
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
        }));
        manager.cancel().await;
        assert!(!staging.exists());
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn candidate_delivery_validation_rejects_modified_inputs() {
        let root = root("delivery-validation");
        tokio::fs::create_dir_all(&root).await.unwrap();
        tokio::fs::write(root.join("requirements.txt"), REQUIREMENTS)
            .await
            .unwrap();
        tokio::fs::write(root.join("syntax-sidecar.py"), SIDECAR)
            .await
            .unwrap();
        validate_delivery_files(&root).await.unwrap();

        tokio::fs::write(root.join("syntax-sidecar.py"), b"modified")
            .await
            .unwrap();
        assert!(validate_delivery_files(&root).await.is_err());
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn failed_activation_retains_last_good_and_records_provenance() {
        let root = root("failed-activation");
        let legacy = root.join(format!(
            "spacy-{RUNTIME_VERSION}-en_core_web_sm-{MODEL_VERSION}"
        ));
        let old = qualified_provider(&legacy, PROVIDER_VERSION).await;
        let manager = SyntaxCapabilityManager::new(&root, Some(old));
        manager.assume_ready_for_tests().await;
        let baseline = manager.view().await;

        let candidate_directory = root.join("releases/candidate");
        let candidate = qualified_provider(&candidate_directory, PROVIDER_VERSION).await;
        tokio::fs::create_dir_all(root.join("syntax-upgrade-state.json.tmp"))
            .await
            .unwrap();
        let failure = manager
            .activate_candidate("candidate".into(), candidate_directory.clone(), candidate)
            .await
            .unwrap_err();
        assert_eq!(failure.stage, SyntaxCandidateFailureStage::Activate);
        manager
            .record_candidate_failure(failure, Some(baseline))
            .await;

        assert_eq!(manager.active_directory().await, legacy);
        let view = manager.view().await;
        assert_eq!(view.status, SyntaxCapabilityStatus::Ready);
        assert!(view.enabled);
        assert_eq!(
            manager.candidate_failure_provenance().await.unwrap().stage,
            SyntaxCandidateFailureStage::Activate
        );
        assert!(!candidate_directory.exists());
        assert_eq!(
            manager
                .probe(&LanguageCode::parse("en").unwrap())
                .await
                .unwrap()
                .status,
            SyntacticCapabilityStatus::Ready
        );
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn restart_recovers_the_atomically_activated_provider() {
        let root = root("restart");
        let manager = SyntaxCapabilityManager::new(&root, None);
        let candidate_directory = root.join("releases/restart-candidate");
        let candidate = qualified_provider(&candidate_directory, PROVIDER_VERSION).await;
        manager
            .activate_candidate(
                "restart-candidate".into(),
                candidate_directory.clone(),
                candidate,
            )
            .await
            .unwrap();
        drop(manager);

        let reloaded = SyntaxCapabilityManager::new(&root, None);
        assert_eq!(reloaded.active_directory().await, candidate_directory);
        assert_eq!(
            reloaded
                .probe(&LanguageCode::parse("en").unwrap())
                .await
                .unwrap()
                .status,
            SyntacticCapabilityStatus::Ready
        );
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn validation_failure_cleans_candidate_without_replacing_last_good() {
        let root = root("validation-cleanup");
        let legacy = root.join(format!(
            "spacy-{RUNTIME_VERSION}-en_core_web_sm-{MODEL_VERSION}"
        ));
        let old = qualified_provider(&legacy, PROVIDER_VERSION).await;
        let manager = SyntaxCapabilityManager::new(&root, Some(old));
        manager.assume_ready_for_tests().await;
        let baseline = manager.view().await;
        let candidate_directory = root.join("releases/invalid-candidate");
        let candidate = qualified_provider(&candidate_directory, "unqualified").await;

        let failure = manager
            .activate_candidate(
                "invalid-candidate".into(),
                candidate_directory.clone(),
                candidate,
            )
            .await
            .unwrap_err();
        assert_eq!(failure.stage, SyntaxCandidateFailureStage::Validate);
        manager
            .record_candidate_failure(failure, Some(baseline))
            .await;

        assert_eq!(manager.active_directory().await, legacy);
        assert!(!candidate_directory.exists());
        assert_eq!(manager.view().await.status, SyntaxCapabilityStatus::Ready);
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn concurrent_activations_are_serialized_and_leave_one_release() {
        let root = root("concurrent");
        let manager = SyntaxCapabilityManager::new(&root, None);
        let first_directory = root.join("releases/first");
        let second_directory = root.join("releases/second");
        let first = qualified_provider(&first_directory, PROVIDER_VERSION).await;
        let second = qualified_provider(&second_directory, PROVIDER_VERSION).await;

        let (first_result, second_result) = tokio::join!(
            manager.activate_candidate("first".into(), first_directory, first),
            manager.activate_candidate("second".into(), second_directory.clone(), second)
        );
        first_result.unwrap();
        second_result.unwrap();

        assert_eq!(manager.active_directory().await, second_directory);
        assert_eq!(
            std::fs::read_dir(root.join("releases"))
                .unwrap()
                .flatten()
                .count(),
            1
        );
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn activation_waits_for_in_flight_last_good_request() {
        let root = root("in-flight");
        let legacy = root.join(format!(
            "spacy-{RUNTIME_VERSION}-en_core_web_sm-{MODEL_VERSION}"
        ));
        let old = qualified_provider(&legacy, "slow-old").await;
        let manager = SyntaxCapabilityManager::new(&root, Some(old));
        manager.assume_ready_for_tests().await;
        let in_flight_manager = Arc::clone(&manager);
        let in_flight = tokio::spawn(async move {
            in_flight_manager
                .probe(&LanguageCode::parse("en").unwrap())
                .await
        });
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;

        let candidate_directory = root.join("releases/new");
        let candidate = qualified_provider(&candidate_directory, PROVIDER_VERSION).await;
        manager
            .activate_candidate("new".into(), candidate_directory, candidate)
            .await
            .unwrap();

        assert_eq!(
            in_flight.await.unwrap().unwrap().status,
            SyntacticCapabilityStatus::Ready
        );
        assert_eq!(
            manager
                .probe(&LanguageCode::parse("en").unwrap())
                .await
                .unwrap()
                .descriptor
                .unwrap()
                .provider_version,
            PROVIDER_VERSION
        );
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn cleanup_failure_records_debt_without_rolling_back_activation() {
        let root = root("cleanup-debt");
        let manager = SyntaxCapabilityManager::new(&root, None);
        let first_directory = root.join("releases/first");
        let first = qualified_provider(&first_directory, PROVIDER_VERSION).await;
        manager
            .activate_candidate("first".into(), first_directory.clone(), first)
            .await
            .unwrap();
        tokio::fs::remove_dir_all(&first_directory).await.unwrap();
        tokio::fs::write(&first_directory, b"not-a-directory")
            .await
            .unwrap();

        let second_directory = root.join("releases/second");
        let second = qualified_provider(&second_directory, PROVIDER_VERSION).await;
        manager
            .activate_candidate("second".into(), second_directory.clone(), second)
            .await
            .unwrap();

        assert_eq!(manager.active_directory().await, second_directory);
        assert_eq!(
            manager.upgrade_state.lock().await.cleanup_debt,
            Some(first_directory)
        );
        assert_eq!(manager.view().await.status, SyntaxCapabilityStatus::Ready);
        let _ = tokio::fs::remove_dir_all(root).await;
    }

    #[tokio::test]
    async fn concurrent_install_request_keeps_last_good_ready() {
        let root = root("concurrent-install");
        let manager = SyntaxCapabilityManager::new(&root, None);
        tokio::fs::create_dir_all(manager.install_dir().join("venv/bin"))
            .await
            .unwrap();
        tokio::fs::write(manager.install_dir().join("venv/bin/python"), b"fixture")
            .await
            .unwrap();
        tokio::fs::write(manager.install_dir().join("syntax-sidecar.py"), b"fixture")
            .await
            .unwrap();
        manager.assume_ready_for_tests().await;
        *manager.task.lock().await = Some(tokio::spawn(async {
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
        }));

        let view = manager.start_install().await;

        assert_eq!(view.status, SyntaxCapabilityStatus::Ready);
        assert!(view.enabled);
        manager.cancel().await;
        let _ = tokio::fs::remove_dir_all(root).await;
    }
}
