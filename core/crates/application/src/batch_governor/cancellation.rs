//! Batch cancellation and checkpoint support.
//!
//! A [`BatchCancellationToken`] is shared between the task orchestrator and the
//! caller. When cancelled, no new requests are started; in-flight requests
//! complete naturally but their results may be discarded by the caller.

use std::sync::Arc;
use std::sync::atomic::{AtomicU8, AtomicU64, Ordering};

use tokio::sync::watch;

/// A lightweight cancellation token for batch LLM operations.
///
/// Clone is cheap (Arc). All workers share the same cancellation state.
#[derive(Clone)]
pub struct BatchCancellationToken {
    state: Arc<AtomicU8>,
    signal: Arc<watch::Sender<bool>>,
    /// Number of sentences successfully completed before cancellation.
    completed_count: Arc<AtomicU64>,
    total_count: Arc<AtomicU64>,
    progress_observer: Option<Arc<dyn Fn(u64, u64) + Send + Sync>>,
}

impl Default for BatchCancellationToken {
    fn default() -> Self {
        Self::new()
    }
}

impl BatchCancellationToken {
    const RUNNING: u8 = 0;
    const CANCELLED: u8 = 1;
    const COMMITTING: u8 = 2;

    pub fn new() -> Self {
        Self {
            state: Arc::new(AtomicU8::new(Self::RUNNING)),
            signal: Arc::new(watch::channel(false).0),
            completed_count: Arc::new(AtomicU64::new(0)),
            total_count: Arc::new(AtomicU64::new(0)),
            progress_observer: None,
        }
    }

    pub(crate) fn with_progress_observer(observer: Arc<dyn Fn(u64, u64) + Send + Sync>) -> Self {
        let mut token = Self::new();
        token.progress_observer = Some(observer);
        token
    }

    /// Signal cancellation. All workers checking `is_cancelled()` will observe
    /// `true` after this call.
    pub fn cancel(&self) -> bool {
        let accepted = self
            .state
            .compare_exchange(
                Self::RUNNING,
                Self::CANCELLED,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .is_ok();
        if accepted {
            self.signal.send_replace(true);
        }
        accepted
    }

    /// Whether cancellation has been requested.
    pub fn is_cancelled(&self) -> bool {
        self.state.load(Ordering::Acquire) == Self::CANCELLED
    }

    /// Atomically closes the cancellation window before committing the final
    /// analysis. Once this succeeds, later cancellation requests are rejected
    /// and the batch completes normally.
    pub fn begin_commit(&self) -> bool {
        self.state
            .compare_exchange(
                Self::RUNNING,
                Self::COMMITTING,
                Ordering::AcqRel,
                Ordering::Acquire,
            )
            .is_ok()
    }

    /// Wait until cancellation is signalled. Useful for select! loops.
    pub async fn cancelled(&self) {
        if self.is_cancelled() {
            return;
        }
        let mut receiver = self.signal.subscribe();
        if *receiver.borrow() {
            return;
        }
        let _ = receiver.changed().await;
    }

    /// Record that one sentence completed successfully.
    pub fn record_completion(&self) {
        let completed = self.completed_count.fetch_add(1, Ordering::Relaxed) + 1;
        if let Some(observer) = &self.progress_observer {
            observer(completed, self.total_count());
        }
    }

    /// Number of sentences completed so far (checkpoint progress).
    pub fn completed_count(&self) -> u64 {
        self.completed_count.load(Ordering::Relaxed)
    }

    pub fn set_total_count(&self, total: u64) {
        self.total_count.store(total, Ordering::Relaxed);
        if let Some(observer) = &self.progress_observer {
            observer(self.completed_count(), total);
        }
    }

    pub fn total_count(&self) -> u64 {
        self.total_count.load(Ordering::Relaxed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_starts_uncancelled() {
        let token = BatchCancellationToken::new();
        assert!(!token.is_cancelled());
        assert_eq!(token.completed_count(), 0);
    }

    #[test]
    fn cancel_is_observable() {
        let token = BatchCancellationToken::new();
        let clone = token.clone();
        assert!(token.cancel());
        assert!(clone.is_cancelled());
    }

    #[test]
    fn completion_count_tracks_progress() {
        let token = BatchCancellationToken::new();
        token.record_completion();
        token.record_completion();
        assert_eq!(token.completed_count(), 2);
    }

    #[tokio::test]
    async fn cancelled_future_resolves_after_cancel() {
        let token = BatchCancellationToken::new();
        let clone = token.clone();
        tokio::spawn(async move {
            clone.cancel();
        });
        token.cancelled().await;
        assert!(token.is_cancelled());
    }

    #[test]
    fn commit_closes_the_cancellation_window() {
        let token = BatchCancellationToken::new();
        assert!(token.begin_commit());
        assert!(!token.cancel());
        assert!(!token.is_cancelled());
    }
}
