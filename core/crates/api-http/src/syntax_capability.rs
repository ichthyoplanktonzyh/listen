use std::path::{Path, PathBuf};
use std::sync::Arc;

use application::{SyntacticAnalysisProvider, SyntacticCapabilityStatus};
use domain::LanguageCode;
use serde::{Deserialize, Serialize};
use syntactic_provider::PythonSyntacticProvider;
use tokio::process::Command;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

const RUNTIME_VERSION: &str = "3.8.13";
const MODEL_VERSION: &str = "3.8.0";
const MODEL_CHECKSUM: &str = "adda6df4860f555a57e6e31635f233359ab471dafa177d58d96a8d4198450a7c";
const EXPECTED_BYTES: u64 = 162_250_752;
const REQUIREMENTS: &str =
    include_str!("../../../scripts/syntactic-analysis/requirements-spacy-product.txt");
const SIDECAR: &str = include_str!("../../../scripts/syntactic-analysis/syntax-sidecar.py");

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
pub struct SyntaxCapabilityView {
    pub status: SyntaxCapabilityStatus,
    pub progress: f32,
    pub enabled: bool,
    pub runtime_version: String,
    pub model_version: String,
    pub model_checksum_sha256: String,
    pub expected_install_bytes: u64,
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
            model_version: MODEL_VERSION.into(),
            model_checksum_sha256: MODEL_CHECKSUM.into(),
            expected_install_bytes: EXPECTED_BYTES,
            installed_bytes: 0,
            error: None,
            updated_at_ms: now_ms(),
        }
    }
}

pub struct SyntaxCapabilityManager {
    root: PathBuf,
    install_dir: PathBuf,
    state_path: PathBuf,
    state: Mutex<SyntaxCapabilityView>,
    task: Mutex<Option<JoinHandle<()>>>,
    provider: Option<Arc<PythonSyntacticProvider>>,
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
        let state = read_state(&state_path).unwrap_or_default();
        Arc::new(Self {
            root,
            install_dir,
            state_path,
            state: Mutex::new(state),
            task: Mutex::new(None),
            provider,
        })
    }

    pub fn install_dir(&self) -> &Path {
        &self.install_dir
    }

    pub fn cache_dir(&self) -> PathBuf {
        self.root.join("track-cache")
    }

    pub async fn view(&self) -> SyntaxCapabilityView {
        let mut state = self.state.lock().await.clone();
        if matches!(
            state.status,
            SyntaxCapabilityStatus::Ready | SyntaxCapabilityStatus::Disabled
        ) {
            state.installed_bytes = directory_size(&self.install_dir);
            if !self.install_dir.join("venv/bin/python").is_file()
                || !self.install_dir.join("syntax-sidecar.py").is_file()
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
        if let Some(provider) = &self.provider {
            provider.shutdown().await;
        }
        self.set_state(SyntaxCapabilityStatus::Downloading, 0.01, false, None)
            .await;
        let manager = Arc::clone(self);
        *task = Some(tokio::spawn(async move {
            if let Err(error) = manager.install().await {
                let _ = tokio::fs::remove_dir_all(manager.root.join(".installing")).await;
                manager
                    .set_state(SyntaxCapabilityStatus::Failed, 0.0, false, Some(error))
                    .await;
            }
        }));
        drop(task);
        self.view().await
    }

    pub async fn cancel(&self) -> SyntaxCapabilityView {
        if let Some(task) = self.task.lock().await.take() {
            task.abort();
        }
        let staging = self.root.join(".installing");
        let _ = tokio::fs::remove_dir_all(staging).await;
        let status = if self.install_dir.is_dir() {
            SyntaxCapabilityStatus::Disabled
        } else {
            SyntaxCapabilityStatus::NotInstalled
        };
        self.set_state(status, 0.0, false, None).await;
        self.view().await
    }

    pub async fn validate(&self) -> SyntaxCapabilityView {
        if !self.install_dir.is_dir() {
            self.set_state(SyntaxCapabilityStatus::NotInstalled, 0.0, false, None)
                .await;
            return self.view().await;
        }
        let Some(provider) = &self.provider else {
            self.set_state(
                SyntaxCapabilityStatus::Partial,
                0.0,
                false,
                Some("syntax provider is not composed".into()),
            )
            .await;
            return self.view().await;
        };
        provider.shutdown().await;
        match provider
            .probe(&LanguageCode::parse("en").expect("static language"))
            .await
        {
            Ok(capability) if capability.status == SyntacticCapabilityStatus::Ready => {
                let descriptor_ok = capability.descriptor.as_ref().is_some_and(|descriptor| {
                    descriptor.runtime_version == RUNTIME_VERSION
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
            if let Some(provider) = &self.provider {
                provider.shutdown().await;
            }
            self.set_state(SyntaxCapabilityStatus::Disabled, 1.0, false, None)
                .await;
        } else {
            {
                let mut state = self.state.lock().await;
                state.enabled = true;
            }
            return self.validate().await;
        }
        self.view().await
    }

    pub async fn uninstall(&self) -> SyntaxCapabilityView {
        let _ = self.cancel().await;
        if let Some(provider) = &self.provider {
            provider.shutdown().await;
        }
        let _ = tokio::fs::remove_dir_all(&self.install_dir).await;
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

    #[cfg(test)]
    pub(crate) async fn assume_ready_for_tests(&self) {
        self.set_state(SyntaxCapabilityStatus::Ready, 1.0, true, None)
            .await;
    }

    async fn install(&self) -> Result<(), String> {
        tokio::fs::create_dir_all(&self.root)
            .await
            .map_err(|error| format!("create syntax root: {error}"))?;
        let staging = self.root.join(".installing");
        let _ = tokio::fs::remove_dir_all(&staging).await;
        tokio::fs::create_dir_all(&staging)
            .await
            .map_err(|error| format!("create syntax staging: {error}"))?;
        tokio::fs::write(staging.join("requirements.txt"), REQUIREMENTS)
            .await
            .map_err(|error| format!("write syntax requirements: {error}"))?;
        tokio::fs::write(staging.join("syntax-sidecar.py"), SIDECAR)
            .await
            .map_err(|error| format!("write syntax sidecar: {error}"))?;
        self.set_state(SyntaxCapabilityStatus::Downloading, 0.08, false, None)
            .await;
        let base_python = discover_python().await?;
        run(&base_python, &["-m", "venv", "venv"], &staging).await?;
        self.set_state(SyntaxCapabilityStatus::Downloading, 0.15, false, None)
            .await;
        let python = staging.join("venv/bin/python");
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
            &staging,
        )
        .await?;
        self.set_state(SyntaxCapabilityStatus::Downloading, 0.9, false, None)
            .await;
        let candidate = PythonSyntacticProvider::new(
            syntactic_provider::PythonSyntacticKind::Spacy,
            &python,
            staging.join("syntax-sidecar.py"),
        );
        let capability = candidate
            .probe(&LanguageCode::parse("en").expect("static language"))
            .await
            .map_err(|error| format!("installed syntax probe failed: {error}"))?;
        candidate.shutdown().await;
        let descriptor = capability
            .descriptor
            .ok_or_else(|| "installed syntax probe omitted descriptor".to_string())?;
        if capability.status != SyntacticCapabilityStatus::Ready
            || descriptor.runtime_version != RUNTIME_VERSION
            || descriptor.model_version != MODEL_VERSION
            || descriptor.model_checksum_sha256 != MODEL_CHECKSUM
        {
            return Err("installed syntax identity failed qualified manifest validation".into());
        }
        if self.install_dir.exists() {
            tokio::fs::remove_dir_all(&self.install_dir)
                .await
                .map_err(|error| format!("remove previous syntax install: {error}"))?;
        }
        tokio::fs::rename(&staging, &self.install_dir)
            .await
            .map_err(|error| format!("publish syntax install: {error}"))?;
        self.set_state(SyntaxCapabilityStatus::Ready, 1.0, true, None)
            .await;
        Ok(())
    }

    async fn set_state(
        &self,
        status: SyntaxCapabilityStatus,
        progress: f32,
        enabled: bool,
        error: Option<String>,
    ) {
        let snapshot = {
            let mut state = self.state.lock().await;
            state.status = status;
            state.progress = progress.clamp(0.0, 1.0);
            state.enabled = enabled;
            state.error = error;
            state.updated_at_ms = now_ms();
            state.installed_bytes = directory_size(&self.install_dir);
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
    let output = Command::new(program)
        .args(args)
        .current_dir(cwd)
        .kill_on_drop(true)
        .output()
        .await
        .map_err(|error| format!("run {}: {error}", program.display()))?;
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

#[cfg(test)]
mod tests {
    use super::*;

    fn root(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("llplayer-syntax-{name}-{}", now_ms()))
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
}
