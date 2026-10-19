//! Account-level request governor backed by a shared semaphore.
//!
//! Every LLM task (sense-group batch, semantic evaluation, etc.) acquires a
//! permit before dispatching a request. The governor's capacity is the
//! account-wide in-flight ceiling, so multiple concurrent media tasks can never
//! collectively exceed the provider's concurrency limit.

use std::sync::Arc;
use std::time::{Duration, Instant};

use tokio::sync::{Mutex, OwnedSemaphorePermit, Semaphore};

use super::BatchCancellationToken;
use super::metrics::BatchMetrics;

/// Default account-wide in-flight ceiling. DeepSeek V4 Flash allows 2,500
/// account-wide concurrent requests; we stay comfortably below that.
pub const DEFAULT_ACCOUNT_CONCURRENCY: usize = 800;

/// A process-wide governor that bounds aggregate LLM in-flight requests.
///
/// Clone is cheap (Arc internally). All tasks share the same semaphore.
#[derive(Clone)]
pub struct RequestGovernor {
    semaphore: Arc<Semaphore>,
    capacity: usize,
    start_interval: Option<Duration>,
    next_start: Arc<Mutex<Instant>>,
}

impl RequestGovernor {
    /// Create a governor with the given account-wide concurrency ceiling.
    pub fn new(max_in_flight: usize) -> Self {
        Self::with_start_rate(max_in_flight, None)
    }

    pub fn with_start_rate(max_in_flight: usize, starts_per_second: Option<u32>) -> Self {
        let capacity = max_in_flight.max(1);
        let start_interval = starts_per_second
            .filter(|rate| *rate > 0)
            .map(|rate| Duration::from_secs_f64(1.0 / f64::from(rate)));
        Self {
            semaphore: Arc::new(Semaphore::new(capacity)),
            capacity,
            start_interval,
            next_start: Arc::new(Mutex::new(Instant::now())),
        }
    }

    /// Create a governor with the default concurrency ceiling.
    pub fn with_defaults() -> Self {
        Self::new(DEFAULT_ACCOUNT_CONCURRENCY)
    }

    /// Acquire a permit, waiting if the account ceiling is reached.
    ///
    /// Returns a guard that releases the permit on drop. Records queue wait
    /// time in the shared metrics.
    pub async fn acquire(
        &self,
        cancellation: &BatchCancellationToken,
        metrics: &BatchMetrics,
    ) -> Option<GovernorPermit> {
        let queued_at = Instant::now();
        let permit = tokio::select! {
            _ = cancellation.cancelled() => return None,
            permit = self.semaphore.clone().acquire_owned() => {
                permit.expect("governor semaphore is never closed")
            }
        };
        if let Some(interval) = self.start_interval {
            let mut next_start = tokio::select! {
                _ = cancellation.cancelled() => return None,
                guard = self.next_start.lock() => guard,
            };
            let scheduled = (*next_start).max(Instant::now());
            tokio::select! {
                _ = cancellation.cancelled() => return None,
                _ = tokio::time::sleep_until(tokio::time::Instant::from_std(scheduled)) => {}
            }
            *next_start = Instant::now() + interval;
        }
        if cancellation.is_cancelled() {
            return None;
        }
        let queue_wait_ms = queued_at.elapsed().as_millis() as u64;
        metrics.record_queue_wait(queue_wait_ms);
        Some(GovernorPermit { _permit: permit })
    }

    /// Current number of available permits (not yet acquired).
    pub fn available_permits(&self) -> usize {
        self.semaphore.available_permits()
    }

    /// The configured maximum in-flight capacity.
    pub fn capacity(&self) -> usize {
        self.capacity
    }
}

/// RAII guard: releases the semaphore permit on drop.
pub struct GovernorPermit {
    _permit: OwnedSemaphorePermit,
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;

    #[tokio::test]
    async fn governor_bounds_concurrent_permits() {
        let governor = RequestGovernor::new(2);
        let cancellation = BatchCancellationToken::new();
        let metrics = BatchMetrics::new();
        let p1 = governor.acquire(&cancellation, &metrics).await.unwrap();
        let p2 = governor.acquire(&cancellation, &metrics).await.unwrap();
        // Third permit should not be immediately available.
        assert_eq!(governor.available_permits(), 0);
        drop(p1);
        assert_eq!(governor.available_permits(), 1);
        drop(p2);
    }

    #[tokio::test]
    async fn cancellation_interrupts_a_queued_acquire() {
        let governor = RequestGovernor::new(1);
        let occupied_token = BatchCancellationToken::new();
        let occupied_metrics = BatchMetrics::new();
        let _permit = governor
            .acquire(&occupied_token, &occupied_metrics)
            .await
            .unwrap();

        let queued_token = BatchCancellationToken::new();
        let queued_token_for_task = queued_token.clone();
        let queued_governor = governor.clone();
        let queued = tokio::spawn(async move {
            queued_governor
                .acquire(&queued_token_for_task, &BatchMetrics::new())
                .await
                .is_none()
        });
        tokio::task::yield_now().await;
        queued_token.cancel();
        assert!(queued.await.unwrap());
    }

    #[tokio::test]
    async fn one_thousand_request_batch_can_fill_the_account_capacity() {
        let governor = RequestGovernor::new(800);
        let barrier = Arc::new(tokio::sync::Barrier::new(800));
        let active = Arc::new(AtomicUsize::new(0));
        let max_active = Arc::new(AtomicUsize::new(0));
        let admission_order = Arc::new(AtomicUsize::new(0));
        let mut tasks = Vec::new();
        for _ in 0..1000 {
            let governor = governor.clone();
            let barrier = barrier.clone();
            let active = active.clone();
            let max_active = max_active.clone();
            let admission_order = admission_order.clone();
            tasks.push(tokio::spawn(async move {
                let token = BatchCancellationToken::new();
                let metrics = BatchMetrics::new();
                let permit = governor.acquire(&token, &metrics).await.unwrap();
                let current = active.fetch_add(1, Ordering::SeqCst) + 1;
                max_active.fetch_max(current, Ordering::SeqCst);
                if admission_order.fetch_add(1, Ordering::SeqCst) < 800 {
                    barrier.wait().await;
                }
                active.fetch_sub(1, Ordering::SeqCst);
                drop(permit);
            }));
        }
        for task in tasks {
            task.await.unwrap();
        }
        assert_eq!(max_active.load(Ordering::SeqCst), 800);
    }
}
