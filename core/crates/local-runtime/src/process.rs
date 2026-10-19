use std::collections::VecDeque;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use application::ApplicationError;
use async_trait::async_trait;
use tokio::process::Command;

use crate::runtime_support::io_error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessSpec {
    pub executable: PathBuf,
    pub args: Vec<String>,
}

impl ProcessSpec {
    pub fn new(executable: impl Into<PathBuf>, args: Vec<String>) -> Self {
        Self {
            executable: executable.into(),
            args,
        }
    }
}

pub trait CancellationProbe: Send + Sync {
    fn is_cancelled(&self) -> Result<bool, ApplicationError>;
}

pub trait ProcessOutputObserver: Send + Sync {
    fn stdout_line(&self, line: &str) -> Result<(), ApplicationError>;
}

#[derive(Debug, Default)]
pub struct IgnoreProcessOutput;

impl ProcessOutputObserver for IgnoreProcessOutput {
    fn stdout_line(&self, _line: &str) -> Result<(), ApplicationError> {
        Ok(())
    }
}

#[derive(Debug, Default)]
pub struct NeverCancelled;

impl CancellationProbe for NeverCancelled {
    fn is_cancelled(&self) -> Result<bool, ApplicationError> {
        Ok(false)
    }
}

#[async_trait]
pub trait ProcessRunner: Send + Sync {
    async fn run(
        &self,
        process: ProcessSpec,
        cancellation: Arc<dyn CancellationProbe>,
    ) -> Result<(), ApplicationError>;

    async fn run_streaming(
        &self,
        process: ProcessSpec,
        cancellation: Arc<dyn CancellationProbe>,
        output: Arc<dyn ProcessOutputObserver>,
    ) -> Result<(), ApplicationError>;
}

/// Production child-process adapter. Cancellation is polled because the
/// persisted job is the source of truth and may be changed by another request.
#[derive(Debug, Default)]
pub struct TokioProcessRunner;

#[async_trait]
impl ProcessRunner for TokioProcessRunner {
    async fn run(
        &self,
        process: ProcessSpec,
        cancellation: Arc<dyn CancellationProbe>,
    ) -> Result<(), ApplicationError> {
        self.run_streaming(process, cancellation, Arc::new(IgnoreProcessOutput))
            .await
    }

    async fn run_streaming(
        &self,
        process: ProcessSpec,
        cancellation: Arc<dyn CancellationProbe>,
        output: Arc<dyn ProcessOutputObserver>,
    ) -> Result<(), ApplicationError> {
        use tokio::io::{AsyncBufReadExt, BufReader};

        let mut child = Command::new(&process.executable)
            .args(&process.args)
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(io_error)?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| ApplicationError::ExternalProcess("stdout unavailable".into()))?;
        let mut lines = BufReader::new(stdout).lines();
        loop {
            tokio::select! {
                line = lines.next_line() => {
                    match line.map_err(io_error)? {
                        Some(line) => output.stdout_line(&line)?,
                        None => break,
                    }
                }
                _ = tokio::time::sleep(Duration::from_millis(250)) => {
                    if cancellation.is_cancelled()? {
                        child.kill().await.map_err(io_error)?;
                        return Err(ApplicationError::Repository("job cancelled".into()));
                    }
                }
            }
        }
        let status = child.wait().await.map_err(io_error)?;
        status.success().then_some(()).ok_or_else(|| {
            ApplicationError::Repository(format!(
                "{} exited with {status}",
                process.executable.display()
            ))
        })
    }
}

/// Deterministic adapter for coordinator tests. Each invocation consumes one
/// configured result and records the exact command it received.
#[derive(Clone, Default)]
pub struct FakeProcessRunner {
    calls: Arc<Mutex<Vec<ProcessSpec>>>,
    results: Arc<Mutex<VecDeque<Result<(), String>>>>,
    stdout_lines: Arc<Vec<String>>,
}

impl FakeProcessRunner {
    pub fn succeeding() -> Self {
        Self::default()
    }

    pub fn with_results(results: impl IntoIterator<Item = Result<(), String>>) -> Self {
        Self {
            calls: Arc::default(),
            results: Arc::new(Mutex::new(results.into_iter().collect())),
            stdout_lines: Arc::default(),
        }
    }

    pub fn with_stdout_lines(lines: impl IntoIterator<Item = String>) -> Self {
        Self {
            calls: Arc::default(),
            results: Arc::default(),
            stdout_lines: Arc::new(lines.into_iter().collect()),
        }
    }

    pub fn calls(&self) -> Vec<ProcessSpec> {
        self.calls
            .lock()
            .expect("fake process mutex poisoned")
            .clone()
    }
}

#[async_trait]
impl ProcessRunner for FakeProcessRunner {
    async fn run(
        &self,
        process: ProcessSpec,
        cancellation: Arc<dyn CancellationProbe>,
    ) -> Result<(), ApplicationError> {
        self.run_streaming(process, cancellation, Arc::new(IgnoreProcessOutput))
            .await
    }

    async fn run_streaming(
        &self,
        process: ProcessSpec,
        cancellation: Arc<dyn CancellationProbe>,
        output: Arc<dyn ProcessOutputObserver>,
    ) -> Result<(), ApplicationError> {
        self.calls
            .lock()
            .expect("fake process mutex poisoned")
            .push(process);
        if cancellation.is_cancelled()? {
            return Err(ApplicationError::Repository("job cancelled".into()));
        }
        for line in self.stdout_lines.iter() {
            output.stdout_line(line)?;
        }
        self.results
            .lock()
            .expect("fake process mutex poisoned")
            .pop_front()
            .unwrap_or(Ok(()))
            .map_err(ApplicationError::ExternalProcess)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Cancelled;

    impl CancellationProbe for Cancelled {
        fn is_cancelled(&self) -> Result<bool, ApplicationError> {
            Ok(true)
        }
    }

    #[tokio::test]
    async fn fake_records_commands_and_obeys_cancellation() {
        let runner = FakeProcessRunner::succeeding();
        let error = runner
            .run(
                ProcessSpec::new("tool", vec!["--flag".into()]),
                Arc::new(Cancelled),
            )
            .await
            .unwrap_err();
        assert!(error.to_string().contains("job cancelled"));
        assert_eq!(runner.calls()[0].executable, PathBuf::from("tool"));
    }
}
