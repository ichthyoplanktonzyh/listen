//! Phase 3.12 secret storage seam.
//!
//! The rest of the system holds only opaque [`domain::LlmAuthRef`]s. The raw
//! credential is written once and resolved at call time through a
//! [`SecretStore`] backed by the OS keychain (production) — it never enters an
//! `LlmProviderProfile`, SQLite row, log line, or portable bundle
//! (shared context §3.4).
//!
//! This module defines the seam plus an in-memory implementation for tests and
//! headless runs. The OS-keychain implementation lives outside the leaf
//! application crate (it is platform-specific and prompts the user), and is
//! injected by the composition root.

use std::collections::HashMap;
use std::sync::Mutex;
use std::sync::atomic::{AtomicU64, Ordering};

use domain::LlmAuthRef;
use thiserror::Error;

#[derive(Debug, Error)]
#[error("secret store failure: {0}")]
pub struct SecretStoreError(pub String);

/// Stores and resolves provider credentials. Implementations must never return
/// the secret through any path other than [`SecretStore::resolve`], and must
/// never log it.
pub trait SecretStore: Send + Sync {
    /// Persist a secret and return the opaque reference to store on a profile.
    fn store(&self, secret: &str) -> Result<LlmAuthRef, SecretStoreError>;
    /// Resolve a reference to its secret, or `None` if the reference is unknown
    /// (e.g. the key was deleted out of band — the caller degrades honestly).
    fn resolve(&self, auth_ref: &LlmAuthRef) -> Result<Option<String>, SecretStoreError>;
    /// Remove a secret. Disabling a provider must leave no credential behind.
    fn delete(&self, auth_ref: &LlmAuthRef) -> Result<(), SecretStoreError>;
}

/// A process-local secret store for tests and headless runs. Not durable and
/// not secure across processes; production uses the OS keychain implementation.
#[derive(Default)]
pub struct InMemorySecretStore {
    next: AtomicU64,
    secrets: Mutex<HashMap<String, String>>,
}

impl InMemorySecretStore {
    pub fn new() -> Self {
        Self::default()
    }
}

impl SecretStore for InMemorySecretStore {
    fn store(&self, secret: &str) -> Result<LlmAuthRef, SecretStoreError> {
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        let reference = format!("mem://{id}");
        self.secrets
            .lock()
            .map_err(|_| SecretStoreError("poisoned".into()))?
            .insert(reference.clone(), secret.to_string());
        Ok(LlmAuthRef::new(reference))
    }

    fn resolve(&self, auth_ref: &LlmAuthRef) -> Result<Option<String>, SecretStoreError> {
        Ok(self
            .secrets
            .lock()
            .map_err(|_| SecretStoreError("poisoned".into()))?
            .get(auth_ref.as_str())
            .cloned())
    }

    fn delete(&self, auth_ref: &LlmAuthRef) -> Result<(), SecretStoreError> {
        self.secrets
            .lock()
            .map_err(|_| SecretStoreError("poisoned".into()))?
            .remove(auth_ref.as_str());
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn store_resolve_delete_round_trip() {
        let store = InMemorySecretStore::new();
        let reference = store.store("sk-secret").unwrap();
        // The reference is opaque and does not contain the secret.
        assert!(!reference.as_str().contains("sk-secret"));
        assert_eq!(store.resolve(&reference).unwrap().as_deref(), Some("sk-secret"));
        store.delete(&reference).unwrap();
        assert_eq!(store.resolve(&reference).unwrap(), None);
    }
}
