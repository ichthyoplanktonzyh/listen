//! Isolated Python JSONL adapters for provider-neutral syntactic analysis.
//!
//! The heavy runtime/model remains outside the consumer bundle. This crate owns
//! process/protocol adaptation only; application finalization owns artifact
//! identity and domain validation owns activation safety.

use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use application::{
    SyntacticAnalysisDraft, SyntacticAnalysisProvider, SyntacticAnalysisRequest,
    SyntacticCapabilityStatus, SyntacticProviderCapability,
};
use async_trait::async_trait;
use domain::{
    LanguageCode, SubtitleSentence, SyntacticProviderDescriptor, SyntacticProviderError,
    SyntacticSentenceAnalysis,
};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use tokio::sync::Mutex;
use tokio::time::Instant;

const PROTOCOL_VERSION: u32 = 1;
static REQUEST_SEQUENCE: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PythonSyntacticKind {
    Stanza,
    Spacy,
}

impl PythonSyntacticKind {
    pub fn provider_id(self) -> &'static str {
        match self {
            Self::Stanza => "stanza",
            Self::Spacy => "spacy",
        }
    }

    pub fn default_model(self) -> &'static str {
        match self {
            Self::Stanza => "ewt",
            Self::Spacy => "en_core_web_sm",
        }
    }
}

#[derive(Debug, Clone)]
pub struct PythonSyntacticProvider {
    kind: PythonSyntacticKind,
    python: PathBuf,
    script: PathBuf,
    model: String,
    model_dir: Option<PathBuf>,
    timeout: Duration,
    idle_timeout: Duration,
    process: Arc<Mutex<Option<ResidentProcess>>>,
}

#[derive(Debug)]
struct ResidentProcess {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    last_used: Instant,
}

impl PythonSyntacticProvider {
    pub fn new(
        kind: PythonSyntacticKind,
        python: impl Into<PathBuf>,
        script: impl Into<PathBuf>,
    ) -> Self {
        Self {
            kind,
            python: python.into(),
            script: script.into(),
            model: kind.default_model().into(),
            model_dir: None,
            timeout: Duration::from_secs(60),
            idle_timeout: Duration::from_secs(120),
            process: Arc::new(Mutex::new(None)),
        }
    }

    pub fn with_model(mut self, model: impl Into<String>) -> Self {
        self.model = model.into();
        self
    }

    pub fn with_model_dir(mut self, model_dir: impl Into<PathBuf>) -> Self {
        self.model_dir = Some(model_dir.into());
        self
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    pub fn with_idle_timeout(mut self, timeout: Duration) -> Self {
        self.idle_timeout = timeout;
        self
    }

    /// Stops the optional resident runtime. Capability disable/uninstall calls
    /// this before changing files; normal app shutdown is still covered by
    /// `kill_on_drop`.
    pub async fn shutdown(&self) {
        let mut process = self.process.lock().await;
        if let Some(mut resident) = process.take() {
            let _ = resident.child.kill().await;
        }
    }

    #[cfg(test)]
    async fn resident_process_id(&self) -> Option<u32> {
        self.process.lock().await.as_ref()?.child.id()
    }

    #[cfg(test)]
    async fn terminate_resident_for_test(&self) {
        let mut process = self.process.lock().await;
        if let Some(resident) = process.as_mut() {
            let _ = resident.child.kill().await;
        }
    }

    async fn start_process(&self) -> Result<ResidentProcess, SyntacticProviderError> {
        if self.python.components().count() > 1 && !self.python.is_file() {
            return Err(SyntacticProviderError::RuntimeMissing);
        }
        if !self.script.is_file() {
            return Err(SyntacticProviderError::ModelMissing);
        }
        let mut command = Command::new(&self.python);
        command
            .arg(&self.script)
            .arg("--provider")
            .arg(self.kind.provider_id())
            .arg("--model")
            .arg(&self.model)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        if let Some(model_dir) = &self.model_dir {
            command.arg("--model-dir").arg(model_dir);
        }
        let mut child = command
            .spawn()
            .map_err(|error| SyntacticProviderError::Process {
                detail: format!("failed to start syntactic sidecar: {error}"),
            })?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| SyntacticProviderError::Process {
                detail: "syntactic sidecar stdin was not piped".into(),
            })?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| SyntacticProviderError::Process {
                detail: "syntactic sidecar stdout was not piped".into(),
            })?;
        if let Some(mut stderr) = child.stderr.take() {
            tokio::spawn(async move {
                let mut sink = tokio::io::sink();
                let _ = tokio::io::copy(&mut stderr, &mut sink).await;
            });
        }
        Ok(ResidentProcess {
            child,
            stdin,
            stdout: BufReader::new(stdout),
            last_used: Instant::now(),
        })
    }

    async fn exchange(
        &self,
        request: &WireRequest<'_>,
    ) -> Result<WireResponse, SyntacticProviderError> {
        let mut payload =
            serde_json::to_vec(request).map_err(|error| SyntacticProviderError::Protocol {
                detail: format!("failed to encode syntactic request: {error}"),
            })?;
        payload.push(b'\n');
        let mut process = self.process.lock().await;
        if process
            .as_ref()
            .is_some_and(|resident| resident.last_used.elapsed() >= self.idle_timeout)
            && let Some(mut resident) = process.take()
        {
            let _ = resident.child.kill().await;
        }
        let mut last_error = None;
        for attempt in 0..2 {
            if process.is_none() {
                *process = Some(self.start_process().await?);
            }
            let resident = process.as_mut().expect("resident process initialized");
            let exchange = async {
                resident.stdin.write_all(&payload).await?;
                resident.stdin.flush().await?;
                let mut line = String::new();
                let read = resident.stdout.read_line(&mut line).await?;
                if read == 0 {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::UnexpectedEof,
                        "syntactic sidecar closed stdout",
                    ));
                }
                Ok::<String, std::io::Error>(line)
            };
            match tokio::time::timeout(self.timeout, exchange).await {
                Ok(Ok(line)) => {
                    resident.last_used = Instant::now();
                    let response = decode_response(request, &line)?;
                    self.schedule_idle_shutdown();
                    return Ok(response);
                }
                Ok(Err(error)) => {
                    last_error = Some(format!("syntactic sidecar exchange failed: {error}"));
                }
                Err(_) => {
                    if let Some(mut failed) = process.take() {
                        let _ = failed.child.kill().await;
                    }
                    return Err(SyntacticProviderError::Timeout);
                }
            }
            if let Some(mut failed) = process.take() {
                let _ = failed.child.kill().await;
            }
            if attempt == 1 {
                break;
            }
        }
        Err(SyntacticProviderError::Process {
            detail: last_error.unwrap_or_else(|| "syntactic sidecar failed".into()),
        })
    }

    fn schedule_idle_shutdown(&self) {
        let process = Arc::clone(&self.process);
        let idle_timeout = self.idle_timeout;
        tokio::spawn(async move {
            tokio::time::sleep(idle_timeout).await;
            let mut process = process.lock().await;
            if process
                .as_ref()
                .is_some_and(|resident| resident.last_used.elapsed() >= idle_timeout)
                && let Some(mut resident) = process.take()
            {
                let _ = resident.child.kill().await;
            }
        });
    }
}

fn decode_response(
    request: &WireRequest<'_>,
    line: &str,
) -> Result<WireResponse, SyntacticProviderError> {
    let response: WireResponse =
        serde_json::from_str(line.trim()).map_err(|error| SyntacticProviderError::Protocol {
            detail: format!("invalid syntactic sidecar JSON: {error}"),
        })?;
    if response.protocol_version != PROTOCOL_VERSION || response.request_id != request.request_id {
        return Err(SyntacticProviderError::Protocol {
            detail: "syntactic response version/request_id mismatch".into(),
        });
    }
    if !response.ok {
        return Err(map_wire_error(response.error));
    }
    Ok(response)
}

#[async_trait]
impl SyntacticAnalysisProvider for PythonSyntacticProvider {
    fn provider_id(&self) -> &str {
        self.kind.provider_id()
    }

    async fn probe(
        &self,
        language: &LanguageCode,
    ) -> Result<SyntacticProviderCapability, SyntacticProviderError> {
        let request_id = next_request_id("probe");
        let request = WireRequest {
            protocol_version: PROTOCOL_VERSION,
            request_id: &request_id,
            operation: "probe",
            provider: self.kind.provider_id(),
            language: language.as_str(),
            sentences: None,
        };
        match self.exchange(&request).await {
            Ok(response) => {
                let capability =
                    response
                        .capability
                        .ok_or_else(|| SyntacticProviderError::Protocol {
                            detail: "probe response omitted capability".into(),
                        })?;
                if capability.status != "ready" {
                    return Err(SyntacticProviderError::Protocol {
                        detail: format!(
                            "unknown successful capability status: {}",
                            capability.status
                        ),
                    });
                }
                Ok(SyntacticProviderCapability {
                    descriptor: capability.descriptor,
                    language: language.clone(),
                    status: SyntacticCapabilityStatus::Ready,
                })
            }
            Err(error) => match error {
                SyntacticProviderError::RuntimeMissing => Ok(unavailable_capability(
                    language,
                    SyntacticCapabilityStatus::RuntimeMissing,
                )),
                SyntacticProviderError::ModelMissing => Ok(unavailable_capability(
                    language,
                    SyntacticCapabilityStatus::ModelMissing,
                )),
                SyntacticProviderError::ModelCorrupt => Ok(unavailable_capability(
                    language,
                    SyntacticCapabilityStatus::ModelCorrupt,
                )),
                SyntacticProviderError::UnsupportedLanguage { .. } => Ok(unavailable_capability(
                    language,
                    SyntacticCapabilityStatus::UnsupportedLanguage,
                )),
                other => Err(other),
            },
        }
    }

    async fn analyze(
        &self,
        request: &SyntacticAnalysisRequest,
    ) -> Result<SyntacticAnalysisDraft, SyntacticProviderError> {
        let request_id = next_request_id("analyze");
        let sentences: Vec<_> = request.sentences.iter().map(WireSentence::from).collect();
        let wire_request = WireRequest {
            protocol_version: PROTOCOL_VERSION,
            request_id: &request_id,
            operation: "analyze",
            provider: self.kind.provider_id(),
            language: request.language.as_str(),
            sentences: Some(sentences),
        };
        let response = self.exchange(&wire_request).await?;
        let analysis = response
            .analysis
            .ok_or_else(|| SyntacticProviderError::Protocol {
                detail: "analyze response omitted analysis".into(),
            })?;
        Ok(SyntacticAnalysisDraft {
            descriptor: analysis.descriptor,
            sentences: analysis.sentences,
        })
    }
}

fn unavailable_capability(
    language: &LanguageCode,
    status: SyntacticCapabilityStatus,
) -> SyntacticProviderCapability {
    SyntacticProviderCapability {
        descriptor: None,
        language: language.clone(),
        status,
    }
}

fn next_request_id(operation: &str) -> String {
    format!(
        "syntax-{operation}-{}",
        REQUEST_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    )
}

fn map_wire_error(error: Option<WireError>) -> SyntacticProviderError {
    let Some(error) = error else {
        return SyntacticProviderError::Protocol {
            detail: "failed response omitted error taxonomy".into(),
        };
    };
    match error.kind.as_str() {
        "runtime_missing" => SyntacticProviderError::RuntimeMissing,
        "model_missing" => SyntacticProviderError::ModelMissing,
        "model_corrupt" => SyntacticProviderError::ModelCorrupt,
        "unsupported_language" => SyntacticProviderError::UnsupportedLanguage {
            language: error.detail,
        },
        "timeout" => SyntacticProviderError::Timeout,
        "invalid_output" => SyntacticProviderError::InvalidOutput {
            detail: error.detail,
        },
        "process" => SyntacticProviderError::Process {
            detail: error.detail,
        },
        "protocol" => SyntacticProviderError::Protocol {
            detail: error.detail,
        },
        other => SyntacticProviderError::Protocol {
            detail: format!("unknown syntactic error kind: {other}"),
        },
    }
}

#[derive(Serialize)]
struct WireRequest<'a> {
    protocol_version: u32,
    request_id: &'a str,
    operation: &'a str,
    provider: &'a str,
    language: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    sentences: Option<Vec<WireSentence<'a>>>,
}

#[derive(Serialize)]
struct WireSentence<'a> {
    sentence_id: &'a str,
    text: &'a str,
    subtitle_tokens: &'a [domain::SubtitleToken],
}

impl<'a> From<&'a SubtitleSentence> for WireSentence<'a> {
    fn from(sentence: &'a SubtitleSentence) -> Self {
        Self {
            sentence_id: sentence.id.as_str(),
            text: &sentence.display_text,
            subtitle_tokens: &sentence.tokens,
        }
    }
}

#[derive(Deserialize)]
struct WireResponse {
    protocol_version: u32,
    request_id: String,
    ok: bool,
    capability: Option<WireCapability>,
    analysis: Option<WireAnalysis>,
    error: Option<WireError>,
}

#[derive(Deserialize)]
struct WireCapability {
    status: String,
    descriptor: Option<SyntacticProviderDescriptor>,
}

#[derive(Deserialize)]
struct WireAnalysis {
    descriptor: SyntacticProviderDescriptor,
    sentences: Vec<SyntacticSentenceAnalysis>,
}

#[derive(Deserialize)]
struct WireError {
    kind: String,
    detail: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use application::finalize_syntactic_analysis;
    use domain::{SubtitleSentenceId, TimeMs};

    fn fake_script() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fake_sidecar.py")
    }

    fn request() -> SyntacticAnalysisRequest {
        let text = "Cats run.";
        SyntacticAnalysisRequest {
            language: LanguageCode::parse("en").unwrap(),
            sentences: vec![SubtitleSentence {
                id: SubtitleSentenceId::parse("sentence-1").unwrap(),
                index: 0,
                start: TimeMs::new(0),
                end: TimeMs::new(1000),
                original_text: text.into(),
                display_text: text.into(),
                tokens: subtitle_core::tokenize_english(text),
            }],
            profile_fingerprint: "test-profile".into(),
        }
    }

    fn provider(kind: PythonSyntacticKind) -> PythonSyntacticProvider {
        PythonSyntacticProvider::new(kind, "python3", fake_script()).with_model("fixture")
    }

    #[tokio::test]
    async fn both_protocol_adapters_pass_the_same_neutral_contract() {
        for kind in [PythonSyntacticKind::Stanza, PythonSyntacticKind::Spacy] {
            let provider = provider(kind);
            let request = request();
            let capability = provider.probe(&request.language).await.unwrap();
            assert_eq!(capability.status, SyntacticCapabilityStatus::Ready);
            let draft = provider.analyze(&request).await.unwrap();
            let (analysis, report) = finalize_syntactic_analysis(&request, draft).unwrap();
            assert_eq!(analysis.descriptor.provider_id, kind.provider_id());
            assert!(report.is_activatable(), "{:#?}", report.issues);
        }
    }

    #[tokio::test]
    async fn missing_model_probe_is_honest_capability_not_process_failure() {
        let provider =
            PythonSyntacticProvider::new(PythonSyntacticKind::Stanza, "python3", fake_script())
                .with_model("missing");
        let capability = provider
            .probe(&LanguageCode::parse("en").unwrap())
            .await
            .unwrap();
        assert_eq!(capability.status, SyntacticCapabilityStatus::ModelMissing);
        assert!(capability.descriptor.is_none());
    }

    #[tokio::test]
    async fn corrupt_model_probe_is_honest_and_has_no_descriptor() {
        let provider =
            PythonSyntacticProvider::new(PythonSyntacticKind::Stanza, "python3", fake_script())
                .with_model("corrupt");
        let capability = provider
            .probe(&LanguageCode::parse("en").unwrap())
            .await
            .unwrap();
        assert_eq!(capability.status, SyntacticCapabilityStatus::ModelCorrupt);
        assert!(capability.descriptor.is_none());
    }

    #[tokio::test]
    async fn explicit_invalid_output_never_becomes_a_draft() {
        let provider =
            PythonSyntacticProvider::new(PythonSyntacticKind::Spacy, "python3", fake_script())
                .with_model("invalid");
        let error = provider.analyze(&request()).await.unwrap_err();
        assert!(matches!(
            error,
            SyntacticProviderError::InvalidOutput { .. }
        ));
    }

    #[tokio::test]
    async fn malformed_stdout_is_protocol_error() {
        let provider =
            PythonSyntacticProvider::new(PythonSyntacticKind::Spacy, "python3", fake_script())
                .with_model("malformed");
        let error = provider
            .probe(&LanguageCode::parse("en").unwrap())
            .await
            .unwrap_err();
        assert!(matches!(error, SyntacticProviderError::Protocol { .. }));
    }

    #[tokio::test]
    async fn timeout_is_closed_and_does_not_create_an_artifact() {
        let provider =
            PythonSyntacticProvider::new(PythonSyntacticKind::Stanza, "python3", fake_script())
                .with_model("slow")
                .with_timeout(Duration::from_millis(20));
        let error = provider
            .probe(&LanguageCode::parse("en").unwrap())
            .await
            .unwrap_err();
        assert_eq!(error, SyntacticProviderError::Timeout);
    }

    #[tokio::test]
    async fn probe_and_analysis_reuse_one_resident_process() {
        let provider = provider(PythonSyntacticKind::Spacy);
        let request = request();
        provider.probe(&request.language).await.unwrap();
        let first = provider.resident_process_id().await.unwrap();
        provider.analyze(&request).await.unwrap();
        assert_eq!(provider.resident_process_id().await, Some(first));
    }

    #[tokio::test]
    async fn idle_release_and_crash_recovery_restart_once() {
        let provider =
            provider(PythonSyntacticKind::Spacy).with_idle_timeout(Duration::from_millis(5));
        let request = request();
        provider.probe(&request.language).await.unwrap();
        let first = provider.resident_process_id().await.unwrap();
        tokio::time::sleep(Duration::from_millis(30)).await;
        assert_eq!(provider.resident_process_id().await, None);
        provider.analyze(&request).await.unwrap();
        let second = provider.resident_process_id().await.unwrap();
        assert_ne!(first, second);
        provider.terminate_resident_for_test().await;
        provider.analyze(&request).await.unwrap();
        assert_ne!(provider.resident_process_id().await, Some(second));
    }
}
