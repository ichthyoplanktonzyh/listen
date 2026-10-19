//! Bounded exponential backoff with full jitter and Retry-After support.
//!
//! The policy computes a delay for each retry attempt:
//!   delay = min(cap, base * 2^attempt) with full jitter [0, delay).
//! If the provider returns a `Retry-After` value, that value is used as a
//! floor — we never retry sooner than the server asks.

use std::time::Duration;

/// Configuration for bounded exponential backoff.
#[derive(Debug, Clone)]
pub struct BackoffPolicy {
    /// Initial backoff base (before exponential growth).
    pub base_ms: u64,
    /// Maximum backoff cap.
    pub cap_ms: u64,
    /// Maximum number of retry attempts (0 = no retries).
    pub max_retries: u32,
}

impl Default for BackoffPolicy {
    fn default() -> Self {
        Self {
            base_ms: 500,
            cap_ms: 30_000,
            max_retries: 5,
        }
    }
}

impl BackoffPolicy {
    /// Create a policy with explicit parameters.
    pub fn new(base_ms: u64, cap_ms: u64, max_retries: u32) -> Self {
        Self {
            base_ms: base_ms.max(1),
            cap_ms: cap_ms.max(base_ms.max(1)),
            max_retries,
        }
    }

    /// Whether another retry is allowed for the given attempt (0-based).
    pub fn should_retry(&self, attempt: u32) -> bool {
        attempt < self.max_retries
    }

    /// Compute the backoff delay for a given attempt, optionally respecting a
    /// server-provided `retry_after_ms`.
    ///
    /// Uses full jitter: uniform random in `[0, exponential_delay)`, then
    /// clamped to at least `retry_after_ms` if present.
    pub fn delay_for_attempt(&self, attempt: u32, retry_after_ms: Option<u64>) -> Duration {
        let exponential = self.exponential_ms(attempt);
        // Full jitter: uniform [0, exponential).
        let jittered = jitter(exponential);
        // Respect Retry-After as a floor.
        // The exponential component is capped, but a server-supplied floor is
        // authoritative even when it exceeds our local cap.
        let final_ms = retry_after_ms.map_or(jittered, |floor| jittered.max(floor));
        Duration::from_millis(final_ms)
    }

    /// The raw exponential delay (before jitter) for an attempt.
    fn exponential_ms(&self, attempt: u32) -> u64 {
        let shift = attempt.min(20); // prevent overflow
        let raw = self.base_ms.saturating_mul(1u64 << shift);
        raw.min(self.cap_ms)
    }
}

/// Full jitter: uniform random in [0, max_ms).
/// Uses a simple xorshift-based approach to avoid pulling in `rand` for
/// a single call site; the distribution quality is sufficient for backoff.
fn jitter(max_ms: u64) -> u64 {
    if max_ms <= 1 {
        return 0;
    }
    // Use std::hash of current time nanos + thread id as a lightweight
    // entropy source. This avoids adding `rand` as a dependency for one call.
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    std::time::SystemTime::now().hash(&mut hasher);
    std::thread::current().id().hash(&mut hasher);
    // Mix in a counter for successive calls in the same nanosecond.
    static COUNTER: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    COUNTER
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        .hash(&mut hasher);
    hasher.finish() % max_ms
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn should_retry_respects_max() {
        let policy = BackoffPolicy::new(100, 5000, 3);
        assert!(policy.should_retry(0));
        assert!(policy.should_retry(2));
        assert!(!policy.should_retry(3));
        assert!(!policy.should_retry(10));
    }

    #[test]
    fn delay_is_bounded_by_cap() {
        let policy = BackoffPolicy::new(100, 2000, 10);
        for attempt in 0..10 {
            let delay = policy.delay_for_attempt(attempt, None);
            assert!(delay.as_millis() <= 2000, "attempt {attempt} exceeded cap");
        }
    }

    #[test]
    fn retry_after_is_respected_as_floor() {
        let policy = BackoffPolicy::new(100, 30_000, 5);
        // With a 10s Retry-After, delay must be >= 10s.
        let delay = policy.delay_for_attempt(0, Some(10_000));
        assert!(delay.as_millis() >= 10_000);
    }

    #[test]
    fn retry_after_may_exceed_local_exponential_cap() {
        let policy = BackoffPolicy::new(100, 30_000, 5);
        let delay = policy.delay_for_attempt(0, Some(60_000));
        assert!(delay.as_millis() >= 60_000);
    }

    #[test]
    fn exponential_growth_without_overflow() {
        let policy = BackoffPolicy::new(500, 60_000, 30);
        // Even at high attempts, should not panic or overflow.
        let delay = policy.delay_for_attempt(25, None);
        assert!(delay.as_millis() <= 60_000);
    }
}
