use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;

use application::{
    ForcedAlignCancellation, ForcedAlignFailure, ForcedAlignFailureKind, ForcedAlignOutcome,
    ForcedAlignProvider, ForcedAlignProviderDescriptor, ForcedAlignRequest, ForcedAlignedWord,
};
use async_trait::async_trait;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;

const PROTOCOL_VERSION: &str = "align-cli-json-v2";
const PROVIDER_ID: &str = "torchaudio-ctc-forced-aligner";
const MODEL_REVISION: &str = "mms-fa-v1";

#[derive(Deserialize)]
struct SidecarResponse {
    timings: Vec<ForcedAlignedWord>,
    provenance: SidecarProvenance,
}

#[derive(Deserialize)]
struct SidecarProvenance {
    torchaudio_version: String,
    model_bundle: String,
    model_asset: String,
}

pub fn resolved_forced_align_provider() -> Option<Arc<dyn ForcedAlignProvider>> {
    let (executable, script) = crate::runtime_support::resolve_forced_align_command()?;
    Some(Arc::new(SidecarForcedAlignProvider::new(
        executable, script,
    )))
}

#[derive(Debug, Clone)]
pub struct SidecarForcedAlignProvider {
    executable: PathBuf,
    script: PathBuf,
    descriptor: ForcedAlignProviderDescriptor,
}

impl SidecarForcedAlignProvider {
    pub fn new(executable: PathBuf, script: PathBuf) -> Self {
        let runtime = executable.to_string_lossy().into_owned();
        let sidecar_sha256 = std::fs::read(&script)
            .map(|bytes| hex::encode(Sha256::digest(bytes)))
            .unwrap_or_else(|_| "unavailable".into());
        Self {
            executable,
            script,
            descriptor: ForcedAlignProviderDescriptor {
                provider_id: PROVIDER_ID.into(),
                model_revision: format!("{MODEL_REVISION};sidecar_sha256={sidecar_sha256}"),
                protocol_version: PROTOCOL_VERSION.into(),
                runtime,
            },
        }
    }

    fn failure(
        &self,
        kind: ForcedAlignFailureKind,
        detail: impl Into<String>,
    ) -> ForcedAlignFailure {
        ForcedAlignFailure {
            kind,
            detail: detail.into(),
            descriptor: self.descriptor.clone(),
        }
    }
}

#[async_trait]
impl ForcedAlignProvider for SidecarForcedAlignProvider {
    fn descriptor(&self) -> ForcedAlignProviderDescriptor {
        self.descriptor.clone()
    }

    async fn align(
        &self,
        request: &ForcedAlignRequest,
        cancellation: &dyn ForcedAlignCancellation,
    ) -> Result<ForcedAlignOutcome, ForcedAlignFailure> {
        if cancellation.is_cancelled() {
            return Err(self.failure(
                ForcedAlignFailureKind::Cancelled,
                "forced alignment cancelled before sidecar spawn",
            ));
        }
        let stdin_json = serde_json::to_vec(request)
            .map_err(|error| self.failure(ForcedAlignFailureKind::RequestIo, error.to_string()))?;
        let mut child = Command::new(&self.executable)
            .arg(&self.script)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|error| self.failure(ForcedAlignFailureKind::Spawn, error.to_string()))?;

        let mut stdin = child.stdin.take().ok_or_else(|| {
            self.failure(
                ForcedAlignFailureKind::RequestIo,
                "sidecar stdin was not available",
            )
        })?;
        stdin
            .write_all(&stdin_json)
            .await
            .map_err(|error| self.failure(ForcedAlignFailureKind::RequestIo, error.to_string()))?;
        stdin
            .shutdown()
            .await
            .map_err(|error| self.failure(ForcedAlignFailureKind::RequestIo, error.to_string()))?;
        drop(stdin);

        let mut stdout = child.stdout.take().ok_or_else(|| {
            self.failure(
                ForcedAlignFailureKind::RequestIo,
                "sidecar stdout was not available",
            )
        })?;
        let mut stderr = child.stderr.take().ok_or_else(|| {
            self.failure(
                ForcedAlignFailureKind::RequestIo,
                "sidecar stderr was not available",
            )
        })?;
        let stdout_task = tokio::spawn(async move {
            let mut bytes = Vec::new();
            stdout.read_to_end(&mut bytes).await.map(|_| bytes)
        });
        let stderr_task = tokio::spawn(async move {
            let mut bytes = Vec::new();
            stderr.read_to_end(&mut bytes).await.map(|_| bytes)
        });
        let status = {
            loop {
                tokio::select! {
                    status = child.wait() => {
                        break status.map_err(|error| {
                            self.failure(ForcedAlignFailureKind::RequestIo, error.to_string())
                        })?;
                    }
                    _ = tokio::time::sleep(std::time::Duration::from_millis(20)) => {
                        if cancellation.is_cancelled() {
                            child.kill().await.map_err(|error| {
                                self.failure(ForcedAlignFailureKind::RequestIo, error.to_string())
                            })?;
                            let _ = child.wait().await;
                            stdout_task.abort();
                            stderr_task.abort();
                            return Err(self.failure(
                                ForcedAlignFailureKind::Cancelled,
                                "forced alignment cancelled while sidecar was running",
                            ));
                        }
                    }
                }
            }
        };
        let stdout = stdout_task
            .await
            .map_err(|error| self.failure(ForcedAlignFailureKind::RequestIo, error.to_string()))?
            .map_err(|error| self.failure(ForcedAlignFailureKind::RequestIo, error.to_string()))?;
        let stderr = stderr_task
            .await
            .map_err(|error| self.failure(ForcedAlignFailureKind::RequestIo, error.to_string()))?
            .map_err(|error| self.failure(ForcedAlignFailureKind::RequestIo, error.to_string()))?;
        if !status.success() {
            let stderr = String::from_utf8_lossy(&stderr);
            let detail = format!(
                "sidecar exited with {}: {}",
                status,
                stderr.trim().chars().take(500).collect::<String>()
            );
            return Err(self.failure(ForcedAlignFailureKind::Exit, detail));
        }
        let aligned = serde_json::from_slice::<SidecarResponse>(&stdout).map_err(|error| {
            self.failure(ForcedAlignFailureKind::InvalidResponse, error.to_string())
        })?;
        let provenance = aligned.provenance;
        if [
            provenance.torchaudio_version.as_str(),
            provenance.model_bundle.as_str(),
            provenance.model_asset.as_str(),
        ]
        .into_iter()
        .map(str::trim)
        .any(str::is_empty)
        {
            return Err(self.failure(
                ForcedAlignFailureKind::InvalidResponse,
                "sidecar provenance fields must be non-empty",
            ));
        }
        let mut descriptor = self.descriptor.clone();
        descriptor.model_revision = format!(
            "{};torchaudio={};bundle={};asset={}",
            descriptor.model_revision,
            provenance.torchaudio_version,
            provenance.model_bundle,
            provenance.model_asset,
        );
        Ok(ForcedAlignOutcome {
            timings: aligned.timings,
            descriptor,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use application::{ForcedAlignSegment, NeverCancelForcedAlignment};
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

    static SCRIPT_SEQUENCE: AtomicU64 = AtomicU64::new(1);

    fn request() -> ForcedAlignRequest {
        ForcedAlignRequest {
            audio_path: "/tmp/audio.wav".into(),
            segments: vec![ForcedAlignSegment {
                index: 0,
                text: "hello".into(),
                words: vec!["hello".into()],
                start_ms: 0,
                end_ms: 1000,
            }],
            language: Some("en".into()),
        }
    }

    fn shell_provider(body: &str) -> SidecarForcedAlignProvider {
        let path = std::env::temp_dir().join(format!(
            "listen-forced-align-test-{}-{}.sh",
            std::process::id(),
            SCRIPT_SEQUENCE.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::write(&path, format!("#!/bin/sh\ncat >/dev/null\n{body}\n")).unwrap();
        SidecarForcedAlignProvider::new(PathBuf::from("/bin/sh"), path)
    }

    #[tokio::test]
    async fn adapter_returns_typed_success() {
        let provider = shell_provider(
            r#"printf '%s' '{"timings":[{"segment_index":0,"word_index":0,"text":"hello","start_ms":10,"end_ms":900,"score":0.9}],"provenance":{"torchaudio_version":"2.9.1","model_bundle":"torchaudio.pipelines.MMS_FA","model_asset":"https://models.invalid/model.pt"}}'"#,
        );
        let outcome = provider
            .align(&request(), &NeverCancelForcedAlignment)
            .await
            .unwrap();
        assert_eq!(outcome.timings.len(), 1);
        assert_eq!(outcome.descriptor.protocol_version, PROTOCOL_VERSION);
        assert!(
            outcome
                .descriptor
                .model_revision
                .contains("sidecar_sha256=")
        );
        assert!(
            outcome
                .descriptor
                .model_revision
                .contains("torchaudio=2.9.1")
        );
        assert!(
            outcome
                .descriptor
                .model_revision
                .contains("bundle=torchaudio.pipelines.MMS_FA")
        );
        assert!(
            outcome
                .descriptor
                .model_revision
                .contains("asset=https://models.invalid/model.pt")
        );
        let _ = std::fs::remove_file(provider.script);
    }

    #[tokio::test]
    async fn adapter_classifies_spawn_failure() {
        let provider = SidecarForcedAlignProvider::new(
            PathBuf::from("/definitely/missing/forced-align"),
            PathBuf::from("/missing/script"),
        );
        let failure = provider
            .align(&request(), &NeverCancelForcedAlignment)
            .await
            .unwrap_err();
        assert_eq!(failure.kind, ForcedAlignFailureKind::Spawn);
    }

    #[tokio::test]
    async fn adapter_classifies_nonzero_exit() {
        let provider = shell_provider("echo model-failed >&2\nexit 7");
        let failure = provider
            .align(&request(), &NeverCancelForcedAlignment)
            .await
            .unwrap_err();
        assert_eq!(failure.kind, ForcedAlignFailureKind::Exit);
        assert!(failure.detail.contains("model-failed"));
        let _ = std::fs::remove_file(provider.script);
    }

    #[tokio::test]
    async fn adapter_classifies_invalid_response() {
        let provider = shell_provider("printf '%s' 'not-json'");
        let failure = provider
            .align(&request(), &NeverCancelForcedAlignment)
            .await
            .unwrap_err();
        assert_eq!(failure.kind, ForcedAlignFailureKind::InvalidResponse);
        let _ = std::fs::remove_file(provider.script);
    }

    #[tokio::test]
    async fn adapter_rejects_success_without_provenance() {
        let provider = shell_provider(r#"printf '%s' '{"timings":[]}'"#);
        let failure = provider
            .align(&request(), &NeverCancelForcedAlignment)
            .await
            .unwrap_err();
        assert_eq!(failure.kind, ForcedAlignFailureKind::InvalidResponse);
        let _ = std::fs::remove_file(provider.script);
    }

    #[derive(Default)]
    struct TestCancellation(AtomicBool);

    impl ForcedAlignCancellation for TestCancellation {
        fn is_cancelled(&self) -> bool {
            self.0.load(Ordering::Acquire)
        }
    }

    #[tokio::test]
    async fn cancelling_a_blocked_sidecar_ends_the_adapter_call() {
        let provider = Arc::new(shell_provider("exec sleep 30"));
        let script = provider.script.clone();
        let cancellation = Arc::new(TestCancellation::default());
        let running_provider = provider.clone();
        let running_cancellation = cancellation.clone();
        let task = tokio::spawn(async move {
            running_provider
                .align(&request(), running_cancellation.as_ref())
                .await
        });
        tokio::time::sleep(std::time::Duration::from_millis(80)).await;
        cancellation.0.store(true, Ordering::Release);

        let failure = tokio::time::timeout(std::time::Duration::from_secs(2), task)
            .await
            .expect("cancelled sidecar should end promptly")
            .unwrap()
            .unwrap_err();
        assert_eq!(failure.kind, ForcedAlignFailureKind::Cancelled);
        let _ = std::fs::remove_file(script);
    }
}
