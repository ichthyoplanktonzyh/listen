//! OS-keychain `SecretStore` for the composition root.
//!
//! On macOS this stores each provider credential as a generic keychain item
//! under a fixed service, keyed by a random account id. The `auth_ref` handed
//! back to the rest of the system is just that account id — never the secret.
//! On other targets it degrades to an error store so a misconfigured build
//! fails loudly instead of silently persisting keys somewhere insecure.

use application::{SecretStore, SecretStoreError};
use domain::LlmAuthRef;

const KEYCHAIN_SERVICE: &str = "com.llplayernext.llm-provider";
const AUTH_REF_PREFIX: &str = "keychain:";

/// Formats an opaque `auth_ref` from a keychain account id.
fn auth_ref_for(account: &str) -> LlmAuthRef {
    LlmAuthRef::new(format!("{AUTH_REF_PREFIX}{account}"))
}

/// Extracts the keychain account id from an `auth_ref`, if it is one of ours.
fn account_of(auth_ref: &LlmAuthRef) -> Option<&str> {
    auth_ref.as_str().strip_prefix(AUTH_REF_PREFIX)
}

/// Generates a random, secret-free account id for a new credential.
fn new_account_id() -> String {
    use rand::RngCore;
    let mut bytes = [0u8; 16];
    rand::rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

#[cfg(target_os = "macos")]
pub struct KeychainSecretStore;

#[cfg(target_os = "macos")]
impl KeychainSecretStore {
    pub fn new() -> Self {
        Self
    }
}

#[cfg(target_os = "macos")]
impl Default for KeychainSecretStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(target_os = "macos")]
impl SecretStore for KeychainSecretStore {
    fn reserve(&self) -> Result<LlmAuthRef, SecretStoreError> {
        Ok(auth_ref_for(&new_account_id()))
    }

    fn store_reserved(&self, auth_ref: &LlmAuthRef, secret: &str) -> Result<(), SecretStoreError> {
        let account = account_of(auth_ref)
            .ok_or_else(|| SecretStoreError("invalid keychain auth reference".into()))?;
        security_framework::passwords::set_generic_password(
            KEYCHAIN_SERVICE,
            account,
            secret.as_bytes(),
        )
        .map_err(|error| SecretStoreError(error.to_string()))
    }

    fn resolve(&self, auth_ref: &LlmAuthRef) -> Result<Option<String>, SecretStoreError> {
        let Some(account) = account_of(auth_ref) else {
            return Ok(None);
        };
        match security_framework::passwords::get_generic_password(KEYCHAIN_SERVICE, account) {
            Ok(bytes) => {
                let secret = String::from_utf8(bytes)
                    .map_err(|_| SecretStoreError("stored secret was not utf-8".into()))?;
                Ok(Some(secret))
            }
            Err(error) if error.code() == security_framework_sys::base::errSecItemNotFound => {
                Ok(None)
            }
            Err(error) => Err(SecretStoreError(error.to_string())),
        }
    }

    fn delete(&self, auth_ref: &LlmAuthRef) -> Result<(), SecretStoreError> {
        if let Some(account) = account_of(auth_ref) {
            match security_framework::passwords::delete_generic_password(KEYCHAIN_SERVICE, account)
            {
                Ok(()) => {}
                Err(error) if error.code() == security_framework_sys::base::errSecItemNotFound => {}
                Err(error) => return Err(SecretStoreError(error.to_string())),
            }
        }
        Ok(())
    }
}

/// Non-macOS builds get an explicit unsupported store so keys are never written
/// to an insecure fallback by accident.
#[cfg(not(target_os = "macos"))]
pub struct KeychainSecretStore;

#[cfg(not(target_os = "macos"))]
impl KeychainSecretStore {
    pub fn new() -> Self {
        Self
    }
}

#[cfg(not(target_os = "macos"))]
impl Default for KeychainSecretStore {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(not(target_os = "macos"))]
impl SecretStore for KeychainSecretStore {
    fn reserve(&self) -> Result<LlmAuthRef, SecretStoreError> {
        Err(SecretStoreError(
            "no OS keychain available on this platform".into(),
        ))
    }

    fn store_reserved(
        &self,
        _auth_ref: &LlmAuthRef,
        _secret: &str,
    ) -> Result<(), SecretStoreError> {
        Err(SecretStoreError(
            "no OS keychain available on this platform".into(),
        ))
    }

    fn resolve(&self, _auth_ref: &LlmAuthRef) -> Result<Option<String>, SecretStoreError> {
        Ok(None)
    }

    fn delete(&self, _auth_ref: &LlmAuthRef) -> Result<(), SecretStoreError> {
        Ok(())
    }
}
