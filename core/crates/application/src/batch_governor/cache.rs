//! Sentence-level fingerprint cache for LLM partition idempotency.
//!
//! Before dispatching a sentence to the LLM, the batch checks this cache. If a
//! result exists for the same fingerprint (sentence content + provider + prompt
//! version), the cached boundaries are returned without a network call. This
//! makes resumed batches and re-runs cheap.

use std::collections::HashMap;
use std::sync::Mutex;

/// An in-memory sentence-level cache keyed by content fingerprint.
///
/// Thread-safe via internal Mutex. The cache is seeded from durable checkpoints
/// before dispatch and snapshots successful results for durable persistence
/// after dispatch.
#[derive(Default)]
pub struct SentenceCache {
    entries: Mutex<HashMap<String, CachedPartition>>,
}

/// A cached LLM partition result for one sentence.
#[derive(Debug, Clone, PartialEq, Eq, serde::Deserialize, serde::Serialize)]
pub struct CachedPartition {
    /// The boundary-after-token indices returned by the LLM.
    pub boundary_after_token_indices: Vec<u32>,
    /// The model that produced this result.
    pub model_id: Option<String>,
    /// The prompt version used.
    pub prompt_version: Option<String>,
}

impl SentenceCache {
    pub fn new() -> Self {
        Self {
            entries: Mutex::new(HashMap::new()),
        }
    }

    /// Compute an unambiguous fingerprint for a provider-scoped request
    /// snapshot and the local prompt contract version.
    pub fn fingerprint(
        provider_scope: &str,
        prompt_contract: &str,
        request_snapshot: &[u8],
    ) -> String {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        for component in [
            provider_scope.as_bytes(),
            prompt_contract.as_bytes(),
            request_snapshot,
        ] {
            hasher.update(component.len().to_le_bytes());
            hasher.update(component);
        }
        hex::encode(hasher.finalize())
    }

    /// Look up a cached result. Returns `None` on cache miss.
    pub fn get(&self, fingerprint: &str) -> Option<CachedPartition> {
        self.entries.lock().unwrap().get(fingerprint).cloned()
    }

    /// Insert a result into the cache.
    pub fn insert(&self, fingerprint: String, result: CachedPartition) {
        self.entries.lock().unwrap().insert(fingerprint, result);
    }

    pub fn snapshot(&self) -> Vec<(String, CachedPartition)> {
        self.entries
            .lock()
            .unwrap()
            .iter()
            .map(|(fingerprint, partition)| (fingerprint.clone(), partition.clone()))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fingerprint_is_deterministic() {
        let a = SentenceCache::fingerprint("profile-a", "v1", b"hello world");
        let b = SentenceCache::fingerprint("profile-a", "v1", b"hello world");
        assert_eq!(a, b);
    }

    #[test]
    fn fingerprint_differs_for_different_input() {
        let a = SentenceCache::fingerprint("profile-a", "v1", b"hello world");
        let b = SentenceCache::fingerprint("profile-a", "v2", b"hello world");
        assert_ne!(a, b);
    }

    #[test]
    fn cache_miss_then_hit() {
        let cache = SentenceCache::new();
        let fp = SentenceCache::fingerprint("profile-a", "v1", b"test");
        assert!(cache.get(&fp).is_none());
        cache.insert(
            fp.clone(),
            CachedPartition {
                boundary_after_token_indices: vec![2, 4],
                model_id: Some("model".into()),
                prompt_version: Some("v1".into()),
            },
        );
        let hit = cache.get(&fp).unwrap();
        assert_eq!(hit.boundary_after_token_indices, vec![2, 4]);
        assert_eq!(cache.snapshot().len(), 1);
    }
}
