//! Lifecycle boundary for an optional local realtime cascade sidecar.
//!
//! This module deliberately exposes only configuration, a ready WebSocket
//! endpoint, and shutdown. Child-process and readiness-probe details stay
//! inside `local-runtime` rather than leaking into HTTP routes.

use std::collections::VecDeque;
use std::ffi::OsString;
use std::path::PathBuf;
use std::process::{ExitStatus, Stdio};
use std::time::Duration;

use reqwest::Url;
use thiserror::Error;
use tokio::io::AsyncReadExt;
use tokio::process::{Child, Command};
use tokio::task::JoinHandle;
use tokio::time::Instant;

const STDERR_TAIL_BYTES: usize = 8 * 1024;
const READINESS_POLL_INTERVAL: Duration = Duration::from_millis(50);
const MAX_PROBE_TIMEOUT: Duration = Duration::from_secs(1);

#[derive(Debug, serde::Deserialize)]
struct PoolReadiness {
    size: u64,
    in_use: u64,
}

#[derive(Debug, Clone)]
pub struct LocalRealtimeCascadeConfig {
    pub executable: PathBuf,
    pub args: Vec<OsString>,
    pub endpoint: String,
    pub readiness_url: String,
    pub startup_timeout: Duration,
    pub shutdown_timeout: Duration,
}

#[derive(Debug, Error)]
pub enum LocalRealtimeCascadeError {
    #[error("invalid local realtime cascade {field}: {detail}")]
    InvalidConfig { field: &'static str, detail: String },
    #[error("failed to spawn local realtime cascade: {detail}")]
    Spawn { detail: String },
    #[error("local realtime cascade exited before it was ready ({status}): {stderr_tail}")]
    ExitedBeforeReady { status: String, stderr_tail: String },
    #[error("local realtime cascade was not ready within {timeout_ms}ms: {last_probe_detail}")]
    ReadinessTimeout {
        timeout_ms: u64,
        last_probe_detail: String,
    },
    #[error("failed to shut down local realtime cascade: {detail}")]
    Shutdown { detail: String },
}

pub struct LocalRealtimeCascadeRuntime {
    endpoint: String,
    shutdown_timeout: Duration,
    child: Option<Child>,
    stderr_task: Option<JoinHandle<Vec<u8>>>,
    #[cfg(unix)]
    process_group_id: Option<i32>,
}

impl LocalRealtimeCascadeRuntime {
    pub async fn start(
        config: LocalRealtimeCascadeConfig,
    ) -> Result<Self, LocalRealtimeCascadeError> {
        validate_config(&config)?;

        let endpoint = Url::parse(&config.endpoint).expect("validated endpoint URL");
        let ws_host = endpoint.host_str().expect("validated endpoint host");
        let ws_port = endpoint
            .port_or_known_default()
            .expect("validated endpoint port");
        let client = reqwest::Client::builder()
            .timeout(MAX_PROBE_TIMEOUT.min(config.startup_timeout))
            .build()
            .map_err(|error| LocalRealtimeCascadeError::InvalidConfig {
                field: "readiness_url",
                detail: error.to_string(),
            })?;
        let mut command = Command::new(&config.executable);
        command
            .args(&config.args)
            // These arguments are appended deliberately so a caller cannot
            // accidentally expose upstream's default 0.0.0.0 listener or
            // switch away from its WebSocket realtime mode.
            .arg("--mode")
            .arg("realtime")
            .arg("--ws_host")
            .arg(ws_host)
            .arg("--ws_port")
            .arg(ws_port.to_string())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            command.as_std_mut().process_group(0);
        }
        let mut child = command
            .spawn()
            .map_err(|error| LocalRealtimeCascadeError::Spawn {
                detail: error.to_string(),
            })?;
        #[cfg(unix)]
        let process_group_id = child.id().map(|id| id as i32);
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| LocalRealtimeCascadeError::Spawn {
                detail: "sidecar stderr was not piped".into(),
            })?;
        let stderr_task = tokio::spawn(read_bounded_tail(stderr));
        let mut runtime = Self {
            endpoint: config.endpoint,
            shutdown_timeout: config.shutdown_timeout,
            child: Some(child),
            stderr_task: Some(stderr_task),
            #[cfg(unix)]
            process_group_id,
        };

        let readiness_url = config.readiness_url;
        let deadline = Instant::now() + config.startup_timeout;
        let mut last_probe_detail = "readiness endpoint was not probed".to_owned();

        loop {
            if let Some(status) = runtime.try_wait()? {
                #[cfg(unix)]
                kill_process_group(runtime.process_group_id);
                runtime.process_group_id_take();
                let stderr_tail = runtime.take_stderr_tail().await;
                return Err(LocalRealtimeCascadeError::ExitedBeforeReady {
                    status: status.to_string(),
                    stderr_tail,
                });
            }
            if Instant::now() >= deadline {
                runtime.kill_and_reap().await;
                let _ = runtime.take_stderr_tail().await;
                return Err(LocalRealtimeCascadeError::ReadinessTimeout {
                    timeout_ms: duration_ms(config.startup_timeout),
                    last_probe_detail,
                });
            }

            match client.get(&readiness_url).send().await {
                Ok(response) if !response.status().is_success() => {
                    last_probe_detail =
                        format!("readiness endpoint returned {}", response.status());
                }
                Ok(response) => match response.json::<PoolReadiness>().await {
                    Ok(pool) if pool.size > 0 && pool.in_use < pool.size => return Ok(runtime),
                    Ok(pool) if pool.size == 0 => {
                        last_probe_detail = "pipeline pool was empty".into();
                    }
                    Ok(pool) => {
                        last_probe_detail =
                            format!("pipeline pool was busy ({}/{})", pool.in_use, pool.size);
                    }
                    Err(_) => {
                        last_probe_detail =
                            "readiness endpoint returned an invalid pool document".into();
                    }
                },
                Err(error) => {
                    last_probe_detail = error_without_url(&error);
                }
            }

            let remaining = deadline.saturating_duration_since(Instant::now());
            tokio::time::sleep(READINESS_POLL_INTERVAL.min(remaining)).await;
        }
    }

    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    /// Stops the managed sidecar and reaps it. Calling shutdown more than once
    /// is safe.
    pub async fn shutdown(&mut self) -> Result<(), LocalRealtimeCascadeError> {
        let Some(mut child) = self.child.take() else {
            return Ok(());
        };
        let running = match child.try_wait() {
            Ok(status) => status.is_none(),
            Err(error) => {
                kill_child(&mut child);
                let _ = child.wait().await;
                #[cfg(unix)]
                kill_process_group(self.process_group_id);
                self.process_group_id_take();
                return Err(LocalRealtimeCascadeError::Shutdown {
                    detail: error.to_string(),
                });
            }
        };
        if running {
            terminate_child(&mut child);
            match tokio::time::timeout(self.shutdown_timeout, child.wait()).await {
                Ok(Ok(_)) => {}
                Ok(Err(error)) => {
                    kill_child(&mut child);
                    #[cfg(unix)]
                    kill_process_group(self.process_group_id);
                    self.process_group_id_take();
                    return Err(LocalRealtimeCascadeError::Shutdown {
                        detail: error.to_string(),
                    });
                }
                Err(_) => {
                    kill_child(&mut child);
                    child
                        .wait()
                        .await
                        .map_err(|error| LocalRealtimeCascadeError::Shutdown {
                            detail: error.to_string(),
                        })?;
                }
            }
        }
        #[cfg(unix)]
        kill_process_group(self.process_group_id);
        self.process_group_id_take();
        let _ = self.take_stderr_tail().await;
        Ok(())
    }

    fn try_wait(&mut self) -> Result<Option<ExitStatus>, LocalRealtimeCascadeError> {
        self.child
            .as_mut()
            .expect("runtime child exists until shutdown")
            .try_wait()
            .map_err(|error| LocalRealtimeCascadeError::Spawn {
                detail: format!("failed to observe sidecar status: {error}"),
            })
    }

    async fn kill_and_reap(&mut self) {
        if let Some(mut child) = self.child.take() {
            kill_child(&mut child);
            let _ = child.wait().await;
        }
        self.process_group_id_take();
    }

    async fn take_stderr_tail(&mut self) -> String {
        let Some(task) = self.stderr_task.take() else {
            return String::new();
        };
        match task.await {
            Ok(bytes) => String::from_utf8_lossy(&bytes).trim().to_owned(),
            Err(_) => String::new(),
        }
    }

    #[cfg(unix)]
    fn process_group_id_take(&mut self) {
        self.process_group_id = None;
    }

    #[cfg(not(unix))]
    fn process_group_id_take(&mut self) {}
}

impl Drop for LocalRealtimeCascadeRuntime {
    fn drop(&mut self) {
        if let Some(child) = self.child.as_mut() {
            kill_child(child);
        }
        if let Some(task) = self.stderr_task.take() {
            task.abort();
        }
    }
}

fn validate_config(config: &LocalRealtimeCascadeConfig) -> Result<(), LocalRealtimeCascadeError> {
    if !config.executable.is_file() {
        return Err(LocalRealtimeCascadeError::InvalidConfig {
            field: "executable",
            detail: "must name an existing file".into(),
        });
    }
    validate_loopback_url("endpoint", &config.endpoint, &["ws", "wss"])?;
    validate_loopback_url("readiness_url", &config.readiness_url, &["http", "https"])?;
    if config
        .args
        .iter()
        .any(|arg| arg == "--local_mac_optimal_settings")
    {
        return Err(LocalRealtimeCascadeError::InvalidConfig {
            field: "args",
            detail: "--local_mac_optimal_settings forces upstream out of realtime mode".into(),
        });
    }
    if config.startup_timeout.is_zero() {
        return Err(LocalRealtimeCascadeError::InvalidConfig {
            field: "startup_timeout",
            detail: "must be greater than zero".into(),
        });
    }
    if config.shutdown_timeout.is_zero() {
        return Err(LocalRealtimeCascadeError::InvalidConfig {
            field: "shutdown_timeout",
            detail: "must be greater than zero".into(),
        });
    }
    Ok(())
}

fn validate_loopback_url(
    field: &'static str,
    value: &str,
    allowed_schemes: &[&str],
) -> Result<(), LocalRealtimeCascadeError> {
    let url = Url::parse(value).map_err(|error| LocalRealtimeCascadeError::InvalidConfig {
        field,
        detail: error.to_string(),
    })?;
    if !allowed_schemes.contains(&url.scheme()) {
        return Err(LocalRealtimeCascadeError::InvalidConfig {
            field,
            detail: format!("scheme must be one of {}", allowed_schemes.join(", ")),
        });
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(LocalRealtimeCascadeError::InvalidConfig {
            field,
            detail: "embedded credentials are not allowed".into(),
        });
    }
    let loopback = match url.host_str() {
        Some("localhost") => true,
        Some(host) => host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|address| address.is_loopback()),
        None => false,
    };
    if !loopback {
        return Err(LocalRealtimeCascadeError::InvalidConfig {
            field,
            detail: "host must be loopback".into(),
        });
    }
    if url.port_or_known_default().is_none() {
        return Err(LocalRealtimeCascadeError::InvalidConfig {
            field,
            detail: "port is required or must be implied by the scheme".into(),
        });
    }
    Ok(())
}

async fn read_bounded_tail(mut stderr: tokio::process::ChildStderr) -> Vec<u8> {
    let mut tail = VecDeque::with_capacity(STDERR_TAIL_BYTES);
    let mut buffer = [0_u8; 1024];
    loop {
        let Ok(read) = stderr.read(&mut buffer).await else {
            break;
        };
        if read == 0 {
            break;
        }
        for byte in &buffer[..read] {
            if tail.len() == STDERR_TAIL_BYTES {
                tail.pop_front();
            }
            tail.push_back(*byte);
        }
    }
    tail.into_iter().collect()
}

fn duration_ms(duration: Duration) -> u64 {
    duration.as_millis().min(u64::MAX as u128) as u64
}

fn error_without_url(error: &reqwest::Error) -> String {
    if error.is_timeout() {
        "readiness request timed out".into()
    } else if error.is_connect() {
        "readiness endpoint refused the connection".into()
    } else {
        "readiness request failed".into()
    }
}

#[cfg(unix)]
fn terminate_child(child: &mut Child) {
    if let Some(pid) = child.id() {
        // SAFETY: the pid names a live child placed in its own process group.
        unsafe {
            libc::kill(-(pid as i32), libc::SIGTERM);
        }
    }
}

#[cfg(not(unix))]
fn terminate_child(child: &mut Child) {
    let _ = child.start_kill();
}

#[cfg(unix)]
fn kill_child(child: &mut Child) {
    if let Some(pid) = child.id() {
        // SAFETY: the pid names a live child placed in its own process group.
        unsafe {
            libc::kill(-(pid as i32), libc::SIGKILL);
        }
    }
    let _ = child.start_kill();
}

#[cfg(unix)]
fn kill_process_group(process_group_id: Option<i32>) {
    if let Some(process_group_id) = process_group_id {
        // SAFETY: the id was captured from a child placed in its own process
        // group. ESRCH is harmless when every member has already exited.
        unsafe {
            libc::kill(-process_group_id, libc::SIGKILL);
        }
    }
}

#[cfg(not(unix))]
fn kill_child(child: &mut Child) {
    let _ = child.start_kill();
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    fn config(readiness_url: String) -> LocalRealtimeCascadeConfig {
        LocalRealtimeCascadeConfig {
            executable: PathBuf::from("/bin/sh"),
            args: vec![OsString::from("-c"), OsString::from("sleep 30")],
            endpoint: "ws://127.0.0.1:12345/v1/realtime".into(),
            readiness_url,
            startup_timeout: Duration::from_secs(2),
            shutdown_timeout: Duration::from_millis(500),
        }
    }

    async fn pool_server(status: &'static str, body: &'static str) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        tokio::spawn(async move {
            loop {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut request = [0_u8; 1024];
                let _ = socket.read(&mut request).await;
                socket
                    .write_all(
                        format!(
                            "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                            body.len()
                        )
                        .as_bytes(),
                    )
                    .await
                    .unwrap();
            }
        });
        format!("http://{address}/v1/pool")
    }

    #[test]
    fn config_rejects_missing_executable_and_non_loopback_urls() {
        let mut value = config("http://127.0.0.1:1/health".into());
        value.executable = PathBuf::from("/definitely/missing/realtime-sidecar");
        assert!(matches!(
            validate_config(&value),
            Err(LocalRealtimeCascadeError::InvalidConfig {
                field: "executable",
                ..
            })
        ));

        value.executable = PathBuf::from("/bin/sh");
        value.endpoint = "wss://example.com/v1/realtime".into();
        assert!(matches!(
            validate_config(&value),
            Err(LocalRealtimeCascadeError::InvalidConfig {
                field: "endpoint",
                ..
            })
        ));

        value.endpoint = "ws://127.0.0.1:12345/v1/realtime".into();
        value.args.push("--local_mac_optimal_settings".into());
        assert!(matches!(
            validate_config(&value),
            Err(LocalRealtimeCascadeError::InvalidConfig { field: "args", .. })
        ));
    }

    #[tokio::test]
    async fn start_waits_for_readiness_and_shutdown_is_idempotent() {
        let readiness_url = pool_server("200 OK", r#"{"size":1,"in_use":0}"#).await;
        let mut runtime = LocalRealtimeCascadeRuntime::start(config(readiness_url))
            .await
            .unwrap();
        assert_eq!(runtime.endpoint(), "ws://127.0.0.1:12345/v1/realtime");
        runtime.shutdown().await.unwrap();
        runtime.shutdown().await.unwrap();
    }

    #[tokio::test]
    async fn early_exit_includes_only_a_bounded_stderr_tail() {
        let mut value = config("http://127.0.0.1:1/health".into());
        value.args = vec![
            OsString::from("-c"),
            OsString::from(
                "i=0; while [ $i -lt 9000 ]; do printf x >&2; i=$((i+1)); done; printf marker >&2; exit 7",
            ),
        ];
        let error = LocalRealtimeCascadeRuntime::start(value)
            .await
            .err()
            .expect("sidecar should exit");
        match error {
            LocalRealtimeCascadeError::ExitedBeforeReady {
                status,
                stderr_tail,
            } => {
                assert!(status.contains('7'));
                assert!(stderr_tail.len() <= STDERR_TAIL_BYTES);
                assert!(stderr_tail.ends_with("marker"));
            }
            other => panic!("unexpected error: {other}"),
        }
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn early_exit_reaps_a_background_process_holding_stderr() {
        let mut value = config("http://127.0.0.1:1/v1/pool".into());
        value.args = vec![
            OsString::from("-c"),
            OsString::from("(sleep 30) & printf marker >&2; exit 7"),
        ];

        let error = tokio::time::timeout(
            Duration::from_secs(2),
            LocalRealtimeCascadeRuntime::start(value),
        )
        .await
        .expect("background stderr holder must be terminated")
        .err()
        .expect("sidecar should exit");

        assert!(matches!(
            error,
            LocalRealtimeCascadeError::ExitedBeforeReady { stderr_tail, .. }
                if stderr_tail.ends_with("marker")
        ));
    }

    #[tokio::test]
    async fn readiness_timeout_kills_and_reaps_the_child() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        drop(listener);
        let mut value = config(format!("http://{address}/health"));
        value.startup_timeout = Duration::from_millis(150);
        let error = LocalRealtimeCascadeRuntime::start(value)
            .await
            .err()
            .expect("sidecar should time out");
        assert!(matches!(
            error,
            LocalRealtimeCascadeError::ReadinessTimeout { .. }
        ));
    }

    #[tokio::test]
    async fn non_success_readiness_is_not_ready() {
        let readiness_url =
            pool_server("503 Service Unavailable", r#"{"size":1,"in_use":0}"#).await;
        let mut value = config(readiness_url);
        value.startup_timeout = Duration::from_millis(150);
        let error = LocalRealtimeCascadeRuntime::start(value)
            .await
            .err()
            .expect("503 should not be ready");
        match error {
            LocalRealtimeCascadeError::ReadinessTimeout {
                last_probe_detail, ..
            } => assert!(last_probe_detail.contains("503")),
            other => panic!("unexpected error: {other}"),
        }
    }

    #[tokio::test]
    async fn a_full_pipeline_pool_is_not_ready() {
        let readiness_url = pool_server("200 OK", r#"{"size":1,"in_use":1}"#).await;
        let mut value = config(readiness_url);
        value.startup_timeout = Duration::from_millis(100);

        let error = LocalRealtimeCascadeRuntime::start(value)
            .await
            .err()
            .expect("a busy pool is not ready");

        match error {
            LocalRealtimeCascadeError::ReadinessTimeout {
                last_probe_detail, ..
            } => assert!(last_probe_detail.contains("busy (1/1)")),
            other => panic!("unexpected error: {other}"),
        }
    }
}
