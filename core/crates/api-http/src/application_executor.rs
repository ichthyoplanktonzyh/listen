use std::time::{Duration, Instant};
use std::{future::Future, sync::Arc};

use application::{AppServices, ApplicationError};

const SLOW_OPERATION_THRESHOLD: Duration = Duration::from_millis(100);

/// Dispatches synchronous application work without occupying an async runtime
/// worker.
///
/// Application and repository interfaces deliberately remain synchronous so
/// transactions and runtime-independent tests stay local. This module owns the
/// one async-to-blocking seam used by HTTP routes.
#[derive(Clone)]
pub(crate) struct ApplicationExecutor {
    services: AppServices,
    runtime: Arc<tokio::runtime::Handle>,
}

impl ApplicationExecutor {
    pub(crate) fn new(services: AppServices) -> Self {
        Self {
            services,
            runtime: Arc::new(tokio::runtime::Handle::current()),
        }
    }

    pub(crate) async fn execute<T, F>(
        &self,
        operation: &'static str,
        work: F,
    ) -> Result<T, ApplicationError>
    where
        T: Send + 'static,
        F: FnOnce(AppServices) -> Result<T, ApplicationError> + Send + 'static,
    {
        let services = self.services.clone();
        let started = Instant::now();
        let result = tokio::task::spawn_blocking(move || work(services))
            .await
            .map_err(|error| {
                ApplicationError::Repository(format!(
                    "blocking application operation {operation} failed to join: {error}"
                ))
            })?;
        self.warn_if_slow(operation, started);
        result
    }

    /// Drives an application future on a blocking worker.
    ///
    /// Some provider workflows perform synchronous repository reads before and
    /// after awaiting network/model work. Driving the future here keeps those
    /// synchronous sections off Tokio's async workers without splitting one
    /// application invariant across HTTP handlers.
    pub(crate) async fn execute_async<T, F, Fut>(
        &self,
        operation: &'static str,
        work: F,
    ) -> Result<T, ApplicationError>
    where
        T: Send + 'static,
        F: FnOnce(AppServices) -> Fut + Send + 'static,
        Fut: Future<Output = Result<T, ApplicationError>> + Send + 'static,
    {
        let services = self.services.clone();
        let runtime = self.runtime.clone();
        let started = Instant::now();
        let result = tokio::task::spawn_blocking(move || runtime.block_on(work(services)))
            .await
            .map_err(|error| {
                ApplicationError::Repository(format!(
                    "blocking async application operation {operation} failed to join: {error}"
                ))
            })?;
        self.warn_if_slow(operation, started);
        result
    }

    fn warn_if_slow(&self, operation: &'static str, started: Instant) {
        let elapsed = started.elapsed();
        if elapsed >= SLOW_OPERATION_THRESHOLD {
            tracing::warn!(
                event = "api.application.slow",
                operation,
                duration_ms = elapsed.as_millis() as u64,
                "blocking application operation exceeded the slow threshold"
            );
        }
    }
}
