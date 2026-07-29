use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;

use application::{
    ForcedAlignFailure, ForcedAlignFailureKind, ForcedAlignOutcome, ForcedAlignProvider,
    ForcedAlignProviderDescriptor, ForcedAlignRequest, ForcedAlignedWord,
};
use async_trait::async_trait;
use serde::Deserialize;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

const PROTOCOL_VERSION: &str = "align-cli-json-v1";
const PROVIDER_ID: &str = "torchaudio-ctc-forced-aligner";
const MODEL_REVISION: &str = "mms-fa-v1";

#[derive(Deserialize)]
struct SidecarResponse {
    timings: Vec<ForcedAlignedWord>,
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
        Self {
            executable,
            script,
            descriptor: ForcedAlignProviderDescriptor {
                provider_id: PROVIDER_ID.into(),
                model_revision: MODEL_REVISION.into(),
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
    ) -> Result<ForcedAlignOutcome, ForcedAlignFailure> {
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

        let output = child
            .wait_with_output()
            .await
            .map_err(|error| self.failure(ForcedAlignFailureKind::RequestIo, error.to_string()))?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let detail = format!(
                "sidecar exited with {}: {}",
                output.status,
                stderr.trim().chars().take(500).collect::<String>()
            );
            return Err(self.failure(ForcedAlignFailureKind::Exit, detail));
        }
        let aligned =
            serde_json::from_slice::<SidecarResponse>(&output.stdout).map_err(|error| {
                self.failure(ForcedAlignFailureKind::InvalidResponse, error.to_string())
            })?;
        Ok(ForcedAlignOutcome {
            timings: aligned.timings,
            descriptor: self.descriptor.clone(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use application::ForcedAlignSegment;
    use std::sync::atomic::{AtomicU64, Ordering};

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
            r#"printf '%s' '{"timings":[{"segment_index":0,"word_index":0,"text":"hello","start_ms":10,"end_ms":900,"score":0.9}]}'"#,
        );
        let outcome = provider.align(&request()).await.unwrap();
        assert_eq!(outcome.timings.len(), 1);
        assert_eq!(outcome.descriptor.protocol_version, PROTOCOL_VERSION);
        let _ = std::fs::remove_file(provider.script);
    }

    #[tokio::test]
    async fn adapter_classifies_spawn_failure() {
        let provider = SidecarForcedAlignProvider::new(
            PathBuf::from("/definitely/missing/forced-align"),
            PathBuf::from("/missing/script"),
        );
        let failure = provider.align(&request()).await.unwrap_err();
        assert_eq!(failure.kind, ForcedAlignFailureKind::Spawn);
    }

    #[tokio::test]
    async fn adapter_classifies_nonzero_exit() {
        let provider = shell_provider("echo model-failed >&2\nexit 7");
        let failure = provider.align(&request()).await.unwrap_err();
        assert_eq!(failure.kind, ForcedAlignFailureKind::Exit);
        assert!(failure.detail.contains("model-failed"));
        let _ = std::fs::remove_file(provider.script);
    }

    #[tokio::test]
    async fn adapter_classifies_invalid_response() {
        let provider = shell_provider("printf '%s' 'not-json'");
        let failure = provider.align(&request()).await.unwrap_err();
        assert_eq!(failure.kind, ForcedAlignFailureKind::InvalidResponse);
        let _ = std::fs::remove_file(provider.script);
    }
}
