//! Batch execution metrics: latency, 429 count, retries, queue wait, cache hits.
//!
//! Metrics are collected atomically and can be serialized into the analysis
//! `metrics_json` for observability.

use std::sync::atomic::{AtomicU64, Ordering};

/// Thread-safe counters for one batch execution's operational metrics.
pub struct BatchMetrics {
    /// Total permits acquired (requests dispatched).
    acquired: AtomicU64,
    /// Cumulative queue wait time in milliseconds.
    queue_wait_total_ms: AtomicU64,
    /// Number of 429 rate-limit responses observed.
    rate_limit_count: AtomicU64,
    /// Number of retry attempts (across all sentences).
    retry_count: AtomicU64,
    /// Number of cache hits (sentences served from fingerprint cache).
    cache_hit_count: AtomicU64,
    /// Number of cache misses (sentences dispatched to LLM).
    cache_miss_count: AtomicU64,
    /// Cumulative request latency in milliseconds (successful + failed).
    latency_total_ms: AtomicU64,
    /// Number of requests that completed (success or final failure).
    request_count: AtomicU64,
    /// Number of sentences that fell back to rule-based partition.
    fallback_count: AtomicU64,
    /// Number of sentences cancelled before dispatch.
    cancelled_count: AtomicU64,
}

impl Default for BatchMetrics {
    fn default() -> Self {
        Self::new()
    }
}

impl BatchMetrics {
    pub fn new() -> Self {
        Self {
            acquired: AtomicU64::new(0),
            queue_wait_total_ms: AtomicU64::new(0),
            rate_limit_count: AtomicU64::new(0),
            retry_count: AtomicU64::new(0),
            cache_hit_count: AtomicU64::new(0),
            cache_miss_count: AtomicU64::new(0),
            latency_total_ms: AtomicU64::new(0),
            request_count: AtomicU64::new(0),
            fallback_count: AtomicU64::new(0),
            cancelled_count: AtomicU64::new(0),
        }
    }

    // --- Recording methods (called from hot paths) ---

    pub fn record_queue_wait(&self, ms: u64) {
        self.acquired.fetch_add(1, Ordering::Relaxed);
        self.queue_wait_total_ms.fetch_add(ms, Ordering::Relaxed);
    }

    pub fn record_rate_limit(&self) {
        self.rate_limit_count.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_retry(&self) {
        self.retry_count.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_cache_hit(&self) {
        self.cache_hit_count.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_cache_miss(&self) {
        self.cache_miss_count.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_latency(&self, ms: u64) {
        self.latency_total_ms.fetch_add(ms, Ordering::Relaxed);
        self.request_count.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_fallback(&self) {
        self.fallback_count.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_cancelled(&self) {
        self.cancelled_count.fetch_add(1, Ordering::Relaxed);
    }

    // --- Read accessors ---

    pub fn total_acquired(&self) -> u64 {
        self.acquired.load(Ordering::Relaxed)
    }

    pub fn total_queue_wait_ms(&self) -> u64 {
        self.queue_wait_total_ms.load(Ordering::Relaxed)
    }

    pub fn total_rate_limits(&self) -> u64 {
        self.rate_limit_count.load(Ordering::Relaxed)
    }

    pub fn total_retries(&self) -> u64 {
        self.retry_count.load(Ordering::Relaxed)
    }

    pub fn total_cache_hits(&self) -> u64 {
        self.cache_hit_count.load(Ordering::Relaxed)
    }

    pub fn total_cache_misses(&self) -> u64 {
        self.cache_miss_count.load(Ordering::Relaxed)
    }

    pub fn total_latency_ms(&self) -> u64 {
        self.latency_total_ms.load(Ordering::Relaxed)
    }

    pub fn total_requests(&self) -> u64 {
        self.request_count.load(Ordering::Relaxed)
    }

    pub fn total_fallbacks(&self) -> u64 {
        self.fallback_count.load(Ordering::Relaxed)
    }

    pub fn total_cancelled(&self) -> u64 {
        self.cancelled_count.load(Ordering::Relaxed)
    }

    /// Mean latency per request in ms (0 if no requests).
    pub fn mean_latency_ms(&self) -> u64 {
        let count = self.total_requests();
        if count == 0 {
            0
        } else {
            self.total_latency_ms() / count
        }
    }

    /// Serialize metrics into a JSON object for embedding in analysis records.
    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "requests_acquired": self.total_acquired(),
            "queue_wait_total_ms": self.total_queue_wait_ms(),
            "rate_limit_count": self.total_rate_limits(),
            "retry_count": self.total_retries(),
            "cache": {
                "hits": self.total_cache_hits(),
                "misses": self.total_cache_misses(),
            },
            "latency": {
                "total_ms": self.total_latency_ms(),
                "mean_ms": self.mean_latency_ms(),
                "request_count": self.total_requests(),
            },
            "fallback_count": self.total_fallbacks(),
            "cancelled_count": self.total_cancelled(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn metrics_accumulate() {
        let m = BatchMetrics::new();
        m.record_queue_wait(10);
        m.record_queue_wait(20);
        m.record_rate_limit();
        m.record_retry();
        m.record_latency(100);
        m.record_latency(200);
        m.record_cache_hit();
        m.record_fallback();

        assert_eq!(m.total_acquired(), 2);
        assert_eq!(m.total_queue_wait_ms(), 30);
        assert_eq!(m.total_rate_limits(), 1);
        assert_eq!(m.total_retries(), 1);
        assert_eq!(m.total_requests(), 2);
        assert_eq!(m.mean_latency_ms(), 150);
        assert_eq!(m.total_cache_hits(), 1);
        assert_eq!(m.total_fallbacks(), 1);
    }

    #[test]
    fn to_json_produces_valid_object() {
        let m = BatchMetrics::new();
        m.record_latency(50);
        let json = m.to_json();
        assert_eq!(json["latency"]["request_count"], 1);
        assert_eq!(json["latency"]["mean_ms"], 50);
    }
}
