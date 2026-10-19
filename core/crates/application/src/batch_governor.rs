//! Account-level LLM request governance: concurrency limiting, backoff,
//! cancellation, sentence-level caching, and batch metrics.
//!
//! The governor is a process-wide shared resource. Multiple media tasks
//! (sense-group analysis, semantic evaluation, etc.) acquire permits from the
//! same governor so the aggregate in-flight request count never exceeds the
//! provider account ceiling.

mod backoff;
mod cache;
mod cancellation;
mod coordinator;
mod governor;
mod metrics;

pub use backoff::BackoffPolicy;
pub use cache::{CachedPartition, SentenceCache};
pub use cancellation::BatchCancellationToken;
pub use coordinator::{BatchExecutionState, BatchProgress, LlmBatchCoordinator};
pub use governor::RequestGovernor;
pub use metrics::BatchMetrics;

/// One batch's complete execution policy and lifecycle handles.
#[derive(Clone)]
pub struct LlmBatchExecution {
    provider_cache_scope: String,
    governor: RequestGovernor,
    cancellation: BatchCancellationToken,
    backoff: BackoffPolicy,
}

impl LlmBatchExecution {
    pub fn new(
        provider_cache_scope: impl Into<String>,
        governor: RequestGovernor,
        cancellation: BatchCancellationToken,
        backoff: BackoffPolicy,
    ) -> Self {
        Self {
            provider_cache_scope: provider_cache_scope.into(),
            governor,
            cancellation,
            backoff,
        }
    }

    pub(crate) fn provider_cache_scope(&self) -> &str {
        &self.provider_cache_scope
    }

    pub(crate) fn governor(&self) -> &RequestGovernor {
        &self.governor
    }

    pub(crate) fn cancellation(&self) -> &BatchCancellationToken {
        &self.cancellation
    }

    pub(crate) fn backoff(&self) -> &BackoffPolicy {
        &self.backoff
    }
}
