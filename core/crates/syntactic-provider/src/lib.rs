//! Isolated Python JSONL adapters for provider-neutral syntactic analysis.
//!
//! The heavy runtime/model remains outside the consumer bundle. This crate owns
//! process/protocol adaptation only; application finalization owns artifact
//! identity and domain validation owns activation safety.

use std::path::PathBuf;
use std::process::Stdio;
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
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

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

    async fn exchange(
        &self,
        request: &WireRequest<'_>,
    ) -> Result<WireResponse, SyntacticProviderError> {
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
        let mut stdin = child
            .stdin
            .take()
            .ok_or_else(|| SyntacticProviderError::Process {
                detail: "syntactic sidecar stdin was not piped".into(),
            })?;
        let mut payload =
            serde_json::to_vec(request).map_err(|error| SyntacticProviderError::Protocol {
                detail: format!("failed to encode syntactic request: {error}"),
            })?;
        payload.push(b'\n');
        stdin
            .write_all(&payload)
            .await
            .map_err(|error| SyntacticProviderError::Process {
                detail: format!("failed to write syntactic request: {error}"),
            })?;
        drop(stdin);
        let output = tokio::time::timeout(self.timeout, child.wait_with_output())
            .await
            .map_err(|_| SyntacticProviderError::Timeout)?
            .map_err(|error| SyntacticProviderError::Process {
                detail: format!("failed to wait for syntactic sidecar: {error}"),
            })?;
        let stderr = sanitized_stderr(&output.stderr);
        if !output.status.success() {
            return Err(SyntacticProviderError::Process {
                detail: format!("syntactic sidecar exited {}: {stderr}", output.status),
            });
        }
        let stdout =
            std::str::from_utf8(&output.stdout).map_err(|_| SyntacticProviderError::Protocol {
                detail: "syntactic sidecar stdout is not UTF-8".into(),
            })?;
        let lines: Vec<_> = stdout
            .lines()
            .filter(|line| !line.trim().is_empty())
            .collect();
        if lines.len() != 1 {
            return Err(SyntacticProviderError::Protocol {
                detail: format!("syntactic sidecar returned {} protocol lines", lines.len()),
            });
        }
        let response: WireResponse =
            serde_json::from_str(lines[0]).map_err(|error| SyntacticProviderError::Protocol {
                detail: format!("invalid syntactic sidecar JSON: {error}"),
            })?;
        if response.protocol_version != PROTOCOL_VERSION
            || response.request_id != request.request_id
        {
            return Err(SyntacticProviderError::Protocol {
                detail: "syntactic response version/request_id mismatch".into(),
            });
        }
        if !response.ok {
            return Err(map_wire_error(response.error));
        }
        Ok(response)
    }
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

fn sanitized_stderr(value: &[u8]) -> String {
    let text = String::from_utf8_lossy(value);
    text.chars()
        .take(500)
        .collect::<String>()
        .replace(['\n', '\r'], " ")
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
}
