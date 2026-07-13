//! Phase 3.12 provider profile management use cases.
//!
//! The secret never touches the profile or the database on the client path:
//! [`AppServices::register_llm_provider`] takes the raw key, writes it to the
//! injected [`SecretStore`] (OS keychain in production), stashes only the
//! returned opaque `auth_ref` on the profile, and persists that. Deleting a
//! provider deletes its secret too, so disabling a provider leaves no
//! credential behind.

use domain::{LlmAuthRef, LlmProviderProfile, LlmProviderProfileId};

use crate::{AppServices, ApplicationError, SecretStore};

impl AppServices {
    /// Persists a provider profile as-is (no secret handling). Use
    /// [`AppServices::register_llm_provider`] when there is a raw key to store.
    pub fn save_llm_provider_profile(
        &self,
        profile: LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        self.llm_provider_profiles.upsert_provider_profile(&profile)
    }

    /// Registers a profile with a credential. The raw `secret` is written to the
    /// secure store exactly once here; only the resulting [`LlmAuthRef`] is
    /// stored on the profile and persisted. The secret is never returned,
    /// logged, or written to SQLite.
    pub fn register_llm_provider(
        &self,
        mut profile: LlmProviderProfile,
        secret: &str,
        secret_store: &dyn SecretStore,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        let auth_ref: LlmAuthRef = secret_store.store(secret)?;
        profile.auth_ref = Some(auth_ref);
        self.llm_provider_profiles.upsert_provider_profile(&profile)
    }

    pub fn llm_provider_profile(
        &self,
        id: &LlmProviderProfileId,
    ) -> Result<Option<LlmProviderProfile>, ApplicationError> {
        self.llm_provider_profiles.get_provider_profile(id)
    }

    pub fn list_llm_provider_profiles(&self) -> Result<Vec<LlmProviderProfile>, ApplicationError> {
        self.llm_provider_profiles.list_provider_profiles()
    }

    /// Deletes a profile and, if it referenced a secret, removes that secret
    /// from the secure store. Idempotent: deleting an unknown profile is a
    /// no-op success.
    pub fn delete_llm_provider(
        &self,
        id: &LlmProviderProfileId,
        secret_store: &dyn SecretStore,
    ) -> Result<(), ApplicationError> {
        if let Some(profile) = self.llm_provider_profiles.get_provider_profile(id)?
            && let Some(auth_ref) = &profile.auth_ref
        {
            secret_store.delete(auth_ref)?;
        }
        self.llm_provider_profiles.delete_provider_profile(id)
    }

    /// Resolves the credential for a profile at dispatch time. Returns `None`
    /// for keyless (local) endpoints, or when the referenced secret is gone —
    /// the caller degrades honestly rather than failing hard.
    pub fn resolve_llm_provider_secret(
        &self,
        profile: &LlmProviderProfile,
        secret_store: &dyn SecretStore,
    ) -> Result<Option<String>, ApplicationError> {
        match &profile.auth_ref {
            Some(auth_ref) => Ok(secret_store.resolve(auth_ref)?),
            None => Ok(None),
        }
    }
}
