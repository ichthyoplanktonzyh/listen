//! Provider-neutral LLM profile and dispatch workflows.
//!
//! The secret never touches the profile or the database on the client path:
//! [`LlmProviderUseCases::register_llm_provider`] takes the raw key, writes it to the
//! injected [`SecretStore`] (OS keychain in production), stashes only the
//! returned opaque `auth_ref` on the profile, and persists that. Deleting a
//! provider deletes its secret too, so disabling a provider leaves no
//! credential behind.

use std::sync::Arc;

use domain::{
    CapabilityClaim, LlmAuthRef, LlmProviderProfile, LlmProviderProfileId, LlmUse,
    SemanticJudgment, SemanticTaskAttemptId, SenseGroupAnalysis, SubtitleTrackId, TimelineStatus,
};

use crate::batch_governor::{BackoffPolicy, BatchProgress, LlmBatchCoordinator, LlmBatchExecution};
use crate::{
    AppServices, ApplicationError, LlmProviderProfileRepository, MediaAnalysisUseCases,
    OutputFeedbackDraft, RubricDraft, RubricGenerationRequest, SecretCleanupRepository,
    SecretStore, SemanticLlmRuntime, SemanticLlmRuntimeFactory, SemanticUseCases,
};

fn retry_secret_cleanups(
    repository: &(impl SecretCleanupRepository + ?Sized),
    secret_store: &dyn SecretStore,
) -> Result<usize, ApplicationError> {
    let mut completed = 0;
    let mut first_error = None;
    for auth_ref in repository.pending_secret_cleanups()? {
        match secret_store
            .delete(&auth_ref)
            .map_err(ApplicationError::from)
        {
            Ok(()) => match repository.complete_secret_cleanup(&auth_ref) {
                Ok(()) => completed += 1,
                Err(error) => {
                    first_error.get_or_insert(error);
                }
            },
            Err(error) => {
                first_error.get_or_insert(error);
            }
        };
    }
    if let Some(error) = first_error {
        Err(error)
    } else {
        Ok(completed)
    }
}

fn register_profile_with_secret(
    profiles: &dyn LlmProviderProfileRepository,
    mut profile: LlmProviderProfile,
    secret: &str,
    secret_store: &dyn SecretStore,
) -> Result<LlmProviderProfile, ApplicationError> {
    let new_auth_ref: LlmAuthRef = secret_store.reserve()?;
    // Record the cleanup intent before the external keychain write. A crash
    // from this point until profile activation leaves a discoverable entry.
    profiles.reserve_secret_cleanup(&new_auth_ref)?;
    if let Err(error) = secret_store.store_reserved(&new_auth_ref, secret) {
        profiles.schedule_secret_cleanup(&new_auth_ref)?;
        let _pending_cleanup_result = retry_secret_cleanups(profiles, secret_store);
        return Err(error.into());
    }
    profile.auth_ref = Some(new_auth_ref.clone());

    let saved = match profiles.upsert_provider_profile_and_schedule_cleanup(&profile) {
        Ok(saved) => saved,
        Err(persist_error) => {
            profiles.schedule_secret_cleanup(&new_auth_ref)?;
            let _pending_cleanup_result = retry_secret_cleanups(profiles, secret_store);
            return Err(persist_error);
        }
    };

    // Cleanup failure does not make the committed rotation look unsuccessful:
    // the opaque reference remains in the durable outbox for startup/retry.
    let _pending_cleanup_result = retry_secret_cleanups(profiles, secret_store);
    Ok(saved)
}

fn save_profile_preserving_credential(
    profiles: &dyn LlmProviderProfileRepository,
    profile: LlmProviderProfile,
) -> Result<LlmProviderProfile, ApplicationError> {
    // A settings update without a write-only secret means "keep the current
    // credential", not "drop its opaque reference". Explicit credential
    // removal needs a separate compensated operation.
    profiles.upsert_provider_profile_preserving_credential(&profile)
}

fn delete_profile_then_secret(
    profiles: &dyn LlmProviderProfileRepository,
    id: &LlmProviderProfileId,
    secret_store: &dyn SecretStore,
) -> Result<(), ApplicationError> {
    profiles.delete_provider_profile_and_schedule_cleanup(id)?;
    let _pending_cleanup_result = retry_secret_cleanups(profiles, secret_store);
    Ok(())
}

pub struct LlmProviderUseCases {
    profiles: Arc<dyn LlmProviderProfileRepository>,
    semantic: SemanticUseCases,
    media_analysis: MediaAnalysisUseCases,
}

impl LlmProviderUseCases {
    pub(crate) fn from_services(services: &AppServices) -> Self {
        Self {
            profiles: services.llm_provider_profiles.clone(),
            semantic: SemanticUseCases::new(services.semantic_tasks.clone()),
            media_analysis: MediaAnalysisUseCases::from_services(services),
        }
    }

    /// Persists provider settings without changing an existing credential.
    /// Use [`LlmProviderUseCases::register_llm_provider`] when there is a new
    /// raw key to store.
    pub fn save_llm_provider_profile(
        &self,
        profile: LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        save_profile_preserving_credential(self.profiles.as_ref(), profile)
    }

    /// Registers or rotates a profile credential.
    ///
    /// The new reference is reserved durably before the keychain write. Profile
    /// activation and stale-reference scheduling are one repository
    /// transaction. A later keychain cleanup failure leaves retryable outbox
    /// work and does not make the committed rotation appear unsuccessful.
    pub fn register_llm_provider(
        &self,
        profile: LlmProviderProfile,
        secret: &str,
        secret_store: &dyn SecretStore,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        register_profile_with_secret(self.profiles.as_ref(), profile, secret, secret_store)
    }

    pub fn llm_provider_profile(
        &self,
        id: &LlmProviderProfileId,
    ) -> Result<Option<LlmProviderProfile>, ApplicationError> {
        self.profiles.get_provider_profile(id)
    }

    pub fn list_llm_provider_profiles(&self) -> Result<Vec<LlmProviderProfile>, ApplicationError> {
        self.profiles.list_provider_profiles()
    }

    /// Retries cleanup work already marked ready. In-progress reservations are
    /// deliberately excluded so concurrent rotations cannot delete each
    /// other's credentials.
    pub fn retry_pending_secret_cleanups(
        &self,
        secret_store: &dyn SecretStore,
    ) -> Result<usize, ApplicationError> {
        retry_secret_cleanups(self.profiles.as_ref(), secret_store)
    }

    /// Promotes reservations left by a previous process to cleanup work, then
    /// drains it. Call once before accepting profile mutations.
    pub fn recover_pending_secret_cleanups(
        &self,
        secret_store: &dyn SecretStore,
    ) -> Result<usize, ApplicationError> {
        self.profiles.recover_secret_cleanup_reservations()?;
        retry_secret_cleanups(self.profiles.as_ref(), secret_store)
    }

    /// Atomically deletes a profile and schedules its referenced credential for
    /// retryable cleanup. Deleting an unknown profile is idempotent.
    pub fn delete_llm_provider(
        &self,
        id: &LlmProviderProfileId,
        secret_store: &dyn SecretStore,
    ) -> Result<(), ApplicationError> {
        delete_profile_then_secret(self.profiles.as_ref(), id, secret_store)
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

    /// Loads configuration and the dispatch-time credential, then asks the
    /// injected adapter factory for a protocol-neutral runtime.
    fn runtime(
        &self,
        id: &LlmProviderProfileId,
        secret_store: &dyn SecretStore,
        factory: &dyn SemanticLlmRuntimeFactory,
    ) -> Result<(Box<dyn SemanticLlmRuntime>, LlmProviderProfile), ApplicationError> {
        let profile = self
            .llm_provider_profile(id)?
            .ok_or(ApplicationError::NotFound("llm provider profile"))?;
        let secret = self.resolve_llm_provider_secret(&profile, secret_store)?;
        let runtime = factory.build(&profile, secret)?;
        Ok((runtime, profile))
    }

    fn runtime_for_use(
        &self,
        id: &LlmProviderProfileId,
        use_case: LlmUse,
        use_label: &'static str,
        secret_store: &dyn SecretStore,
        factory: &dyn SemanticLlmRuntimeFactory,
    ) -> Result<(Box<dyn SemanticLlmRuntime>, LlmProviderProfile), ApplicationError> {
        let profile = self
            .llm_provider_profile(id)?
            .ok_or(ApplicationError::NotFound("llm provider profile"))?;
        if !profile.allows(use_case) {
            return Err(ApplicationError::Invalid(format!(
                "LLM provider profile does not allow {use_label}"
            )));
        }
        let secret = self.resolve_llm_provider_secret(&profile, secret_store)?;
        let runtime = factory.build(&profile, secret)?;
        Ok((runtime, profile))
    }

    /// Actually exercises structured output against the configured endpoint.
    pub async fn probe_structured_output(
        &self,
        id: &LlmProviderProfileId,
        secret_store: &dyn SecretStore,
        factory: &dyn SemanticLlmRuntimeFactory,
    ) -> Result<CapabilityClaim, ApplicationError> {
        let (runtime, _) = self.runtime(id, secret_store, factory)?;
        Ok(runtime.probe_structured_output().await?)
    }

    /// Generates a content-only rubric proposal. Identity and persistence stay
    /// outside the provider adapter.
    pub async fn generate_rubric(
        &self,
        id: &LlmProviderProfileId,
        request: &RubricGenerationRequest,
        secret_store: &dyn SecretStore,
        factory: &dyn SemanticLlmRuntimeFactory,
    ) -> Result<RubricDraft, ApplicationError> {
        let (runtime, _) = self.runtime_for_use(
            id,
            LlmUse::RubricGeneration,
            "rubric_generation",
            secret_store,
            factory,
        )?;
        Ok(runtime.rubric().generate_rubric(request).await?)
    }

    /// Judges one stored attempt and records the resulting immutable judgment.
    /// Provider failures occur before persistence and therefore write nothing.
    pub async fn judge_attempt(
        &self,
        id: &LlmProviderProfileId,
        attempt_id: &SemanticTaskAttemptId,
        response_revision: u32,
        created_at_ms: u64,
        secret_store: &dyn SecretStore,
        factory: &dyn SemanticLlmRuntimeFactory,
    ) -> Result<SemanticJudgment, ApplicationError> {
        let (runtime, _) = self.runtime_for_use(
            id,
            LlmUse::SemanticJudgment,
            "semantic_judgment",
            secret_store,
            factory,
        )?;
        self.semantic
            .judge_semantic_attempt(
                attempt_id,
                response_revision,
                runtime.judge(),
                created_at_ms,
            )
            .await
    }

    /// Returns ephemeral teacher-style feedback for a stored output attempt.
    pub async fn feedback_on_attempt(
        &self,
        id: &LlmProviderProfileId,
        attempt_id: &SemanticTaskAttemptId,
        response_revision: u32,
        secret_store: &dyn SecretStore,
        factory: &dyn SemanticLlmRuntimeFactory,
    ) -> Result<OutputFeedbackDraft, ApplicationError> {
        let (runtime, _) = self.runtime_for_use(
            id,
            LlmUse::SemanticJudgment,
            "semantic_judgment",
            secret_store,
            factory,
        )?;
        self.semantic
            .feedback_on_semantic_attempt(attempt_id, response_revision, runtime.feedback())
            .await
    }

    /// Generates and persists one hybrid sense-group analysis while owning the
    /// account governor, cancellation, retry and completion lifecycle.
    #[allow(clippy::too_many_arguments)]
    pub async fn generate_sense_groups(
        &self,
        id: &LlmProviderProfileId,
        batch_id: &str,
        track_id: &SubtitleTrackId,
        status: Option<TimelineStatus>,
        batches: &LlmBatchCoordinator,
        secret_store: &dyn SecretStore,
        factory: &dyn SemanticLlmRuntimeFactory,
    ) -> Result<SenseGroupAnalysis, ApplicationError> {
        let (runtime, profile) = self.runtime_for_use(
            id,
            LlmUse::SenseGroupPartition,
            "sense_group_partition",
            secret_store,
            factory,
        )?;
        let account_scope = profile
            .batch_policy
            .account_scope
            .as_deref()
            .filter(|scope| !scope.trim().is_empty())
            .unwrap_or_else(|| profile.id.as_str())
            .to_string();
        let (governor, cancellation) = batches.begin(
            batch_id,
            &account_scope,
            profile.batch_policy.max_in_flight as usize,
            profile.batch_policy.start_rate_per_second,
        )?;
        let execution = LlmBatchExecution::new(
            profile.id.as_str(),
            governor,
            cancellation,
            BackoffPolicy::new(500, 30_000, profile.max_retries),
        );
        let result = self
            .media_analysis
            .generate_sense_group_analysis_via_llm(
                track_id,
                status,
                runtime.sense_groups(),
                &execution,
            )
            .await;
        batches.finish(batch_id, result.is_ok())?;
        result
    }

    pub fn batch_status(
        &self,
        batch_id: &str,
        batches: &LlmBatchCoordinator,
    ) -> Result<Option<BatchProgress>, ApplicationError> {
        batches.status(batch_id)
    }

    pub fn cancel_batch(
        &self,
        batch_id: &str,
        batches: &LlmBatchCoordinator,
    ) -> Result<Option<BatchProgress>, ApplicationError> {
        batches.cancel(batch_id)
    }
}

#[cfg(test)]
mod credential_compensation_tests {
    use super::*;
    use crate::SecretStoreError;
    use domain::{
        DataRetentionPreference, LlmAdapterKind, LlmBatchPolicy, ProviderCapability,
        llm_provider_profile_id,
    };
    use std::collections::HashSet;
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

    #[derive(Default)]
    struct FaultingProfiles {
        profile: Mutex<Option<LlmProviderProfile>>,
        reserved_cleanups: Mutex<HashSet<String>>,
        pending_cleanups: Mutex<HashSet<String>>,
        fail_upsert: AtomicBool,
        fail_delete: AtomicBool,
    }

    impl crate::SecretCleanupRepository for FaultingProfiles {
        fn reserve_secret_cleanup(
            &self,
            auth_ref: &domain::SecretRef,
        ) -> Result<(), ApplicationError> {
            self.reserved_cleanups
                .lock()
                .unwrap()
                .insert(auth_ref.as_str().to_owned());
            Ok(())
        }

        fn schedule_secret_cleanup(
            &self,
            auth_ref: &domain::SecretRef,
        ) -> Result<(), ApplicationError> {
            self.pending_cleanups
                .lock()
                .unwrap()
                .insert(auth_ref.as_str().to_owned());
            self.reserved_cleanups
                .lock()
                .unwrap()
                .remove(auth_ref.as_str());
            Ok(())
        }

        fn recover_secret_cleanup_reservations(&self) -> Result<usize, ApplicationError> {
            let reserved = std::mem::take(&mut *self.reserved_cleanups.lock().unwrap());
            let count = reserved.len();
            self.pending_cleanups.lock().unwrap().extend(reserved);
            Ok(count)
        }

        fn pending_secret_cleanups(&self) -> Result<Vec<domain::SecretRef>, ApplicationError> {
            Ok(self
                .pending_cleanups
                .lock()
                .unwrap()
                .iter()
                .cloned()
                .map(domain::SecretRef::new)
                .collect())
        }

        fn complete_secret_cleanup(
            &self,
            auth_ref: &domain::SecretRef,
        ) -> Result<(), ApplicationError> {
            self.pending_cleanups
                .lock()
                .unwrap()
                .remove(auth_ref.as_str());
            self.reserved_cleanups
                .lock()
                .unwrap()
                .remove(auth_ref.as_str());
            Ok(())
        }
    }

    impl LlmProviderProfileRepository for FaultingProfiles {
        fn upsert_provider_profile(
            &self,
            profile: &LlmProviderProfile,
        ) -> Result<LlmProviderProfile, ApplicationError> {
            if self.fail_upsert.load(Ordering::SeqCst) {
                return Err(ApplicationError::Repository(
                    "injected profile upsert failure".into(),
                ));
            }
            *self.profile.lock().unwrap() = Some(profile.clone());
            Ok(profile.clone())
        }

        fn get_provider_profile(
            &self,
            id: &LlmProviderProfileId,
        ) -> Result<Option<LlmProviderProfile>, ApplicationError> {
            Ok(self
                .profile
                .lock()
                .unwrap()
                .clone()
                .filter(|profile| &profile.id == id))
        }

        fn list_provider_profiles(&self) -> Result<Vec<LlmProviderProfile>, ApplicationError> {
            Ok(self.profile.lock().unwrap().clone().into_iter().collect())
        }

        fn delete_provider_profile(
            &self,
            _id: &LlmProviderProfileId,
        ) -> Result<(), ApplicationError> {
            if self.fail_delete.load(Ordering::SeqCst) {
                return Err(ApplicationError::Repository(
                    "injected profile delete failure".into(),
                ));
            }
            *self.profile.lock().unwrap() = None;
            Ok(())
        }

        fn upsert_provider_profile_preserving_credential(
            &self,
            profile: &LlmProviderProfile,
        ) -> Result<LlmProviderProfile, ApplicationError> {
            if self.fail_upsert.load(Ordering::SeqCst) {
                return Err(ApplicationError::Repository(
                    "injected profile upsert failure".into(),
                ));
            }
            let mut saved = profile.clone();
            let mut current = self.profile.lock().unwrap();
            if current.is_some() {
                saved.auth_ref = current
                    .as_ref()
                    .and_then(|profile| profile.auth_ref.clone());
            }
            *current = Some(saved.clone());
            Ok(saved)
        }

        fn upsert_provider_profile_and_schedule_cleanup(
            &self,
            profile: &LlmProviderProfile,
        ) -> Result<LlmProviderProfile, ApplicationError> {
            if self.fail_upsert.load(Ordering::SeqCst) {
                return Err(ApplicationError::Repository(
                    "injected profile upsert failure".into(),
                ));
            }
            let stale_auth_ref = {
                let mut current = self.profile.lock().unwrap();
                let stale = current
                    .as_ref()
                    .and_then(|profile| profile.auth_ref.clone());
                *current = Some(profile.clone());
                stale
            };
            if let Some(active_auth_ref) = profile.auth_ref.as_ref() {
                self.complete_secret_cleanup(active_auth_ref)?;
            }
            if let Some(auth_ref) = stale_auth_ref
                .as_ref()
                .filter(|stale| Some(*stale) != profile.auth_ref.as_ref())
            {
                self.schedule_secret_cleanup(auth_ref)?;
            }
            Ok(profile.clone())
        }

        fn delete_provider_profile_and_schedule_cleanup(
            &self,
            _id: &LlmProviderProfileId,
        ) -> Result<(), ApplicationError> {
            if self.fail_delete.load(Ordering::SeqCst) {
                return Err(ApplicationError::Repository(
                    "injected profile delete failure".into(),
                ));
            }
            let stale_auth_ref = self
                .profile
                .lock()
                .unwrap()
                .take()
                .and_then(|profile| profile.auth_ref);
            if let Some(auth_ref) = stale_auth_ref.as_ref() {
                self.schedule_secret_cleanup(auth_ref)?;
            }
            Ok(())
        }
    }

    #[derive(Default)]
    struct TrackingSecretStore {
        next: AtomicU64,
        active: Mutex<HashSet<String>>,
        delete_calls: AtomicU64,
        fail_delete: AtomicBool,
        fail_refs: Mutex<HashSet<String>>,
    }

    impl TrackingSecretStore {
        fn seed(&self, auth_ref: &LlmAuthRef) {
            self.active
                .lock()
                .unwrap()
                .insert(auth_ref.as_str().to_string());
        }

        fn active_count(&self) -> usize {
            self.active.lock().unwrap().len()
        }
    }

    impl SecretStore for TrackingSecretStore {
        fn reserve(&self) -> Result<LlmAuthRef, SecretStoreError> {
            let sequence = self.next.fetch_add(1, Ordering::SeqCst);
            Ok(LlmAuthRef::new(format!("test-secret-ref://{sequence}")))
        }

        fn store_reserved(
            &self,
            auth_ref: &LlmAuthRef,
            _secret: &str,
        ) -> Result<(), SecretStoreError> {
            self.seed(auth_ref);
            Ok(())
        }

        fn resolve(&self, auth_ref: &LlmAuthRef) -> Result<Option<String>, SecretStoreError> {
            Ok(self
                .active
                .lock()
                .unwrap()
                .contains(auth_ref.as_str())
                .then(|| "present".to_string()))
        }

        fn delete(&self, auth_ref: &LlmAuthRef) -> Result<(), SecretStoreError> {
            self.delete_calls.fetch_add(1, Ordering::SeqCst);
            if self.fail_delete.load(Ordering::SeqCst)
                || self.fail_refs.lock().unwrap().contains(auth_ref.as_str())
            {
                return Err(SecretStoreError("injected secret delete failure".into()));
            }
            self.active.lock().unwrap().remove(auth_ref.as_str());
            Ok(())
        }
    }

    fn profile(auth_ref: Option<LlmAuthRef>) -> LlmProviderProfile {
        let adapter_kind = LlmAdapterKind::OpenAiChatCompletions;
        let base_url = "https://provider.invalid/v1";
        let model_id = "test-model";
        LlmProviderProfile {
            id: llm_provider_profile_id(adapter_kind, base_url, model_id),
            display_name: "Test".into(),
            adapter_kind,
            protocol_version: None,
            base_url: base_url.into(),
            model_id: model_id.into(),
            auth_ref,
            timeout_ms: 1_000,
            max_retries: 0,
            batch_policy: LlmBatchPolicy::default(),
            cost_budget: None,
            retention: DataRetentionPreference::Unknown,
            allowed_uses: vec![LlmUse::SemanticJudgment],
            capability: ProviderCapability::unknown(),
            created_at_ms: 1,
        }
    }

    #[test]
    fn failed_profile_upsert_compensates_the_new_secret() {
        let profiles = FaultingProfiles::default();
        profiles.fail_upsert.store(true, Ordering::SeqCst);
        let secrets = TrackingSecretStore::default();

        let result =
            register_profile_with_secret(&profiles, profile(None), "not-observed", &secrets);

        assert!(matches!(result, Err(ApplicationError::Repository(_))));
        assert_eq!(secrets.active_count(), 0);
        assert_eq!(secrets.delete_calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn crash_window_before_profile_activation_remains_discoverable() {
        let profiles = FaultingProfiles::default();
        let secrets = TrackingSecretStore::default();
        let auth_ref = secrets.reserve().unwrap();
        profiles.reserve_secret_cleanup(&auth_ref).unwrap();
        secrets.store_reserved(&auth_ref, "not-observed").unwrap();

        assert!(secrets.resolve(&auth_ref).unwrap().is_some());
        assert_eq!(retry_secret_cleanups(&profiles, &secrets).unwrap(), 0);
        assert_eq!(profiles.recover_secret_cleanup_reservations().unwrap(), 1);
        assert_eq!(retry_secret_cleanups(&profiles, &secrets).unwrap(), 1);
        assert!(secrets.resolve(&auth_ref).unwrap().is_none());
        assert!(profiles.pending_secret_cleanups().unwrap().is_empty());
    }

    #[test]
    fn one_cleanup_failure_does_not_starve_later_entries() {
        let profiles = FaultingProfiles::default();
        let secrets = TrackingSecretStore::default();
        let blocked = LlmAuthRef::new("test-secret-ref://blocked");
        let removable = LlmAuthRef::new("test-secret-ref://removable");
        for auth_ref in [&blocked, &removable] {
            profiles.schedule_secret_cleanup(auth_ref).unwrap();
            secrets.seed(auth_ref);
        }
        secrets
            .fail_refs
            .lock()
            .unwrap()
            .insert(blocked.as_str().to_owned());

        assert!(retry_secret_cleanups(&profiles, &secrets).is_err());
        assert!(secrets.resolve(&blocked).unwrap().is_some());
        assert!(secrets.resolve(&removable).unwrap().is_none());
        assert_eq!(profiles.pending_secret_cleanups().unwrap(), vec![blocked]);
    }

    #[test]
    fn successful_rotation_removes_the_previous_secret() {
        let old_auth_ref = LlmAuthRef::new("test-secret-ref://old");
        let profiles = FaultingProfiles {
            profile: Mutex::new(Some(profile(Some(old_auth_ref.clone())))),
            ..FaultingProfiles::default()
        };
        let secrets = TrackingSecretStore::default();
        secrets.seed(&old_auth_ref);

        let saved =
            register_profile_with_secret(&profiles, profile(None), "not-observed", &secrets)
                .expect("rotation succeeds");

        assert_ne!(saved.auth_ref.as_ref(), Some(&old_auth_ref));
        assert_eq!(secrets.resolve(&old_auth_ref).unwrap(), None);
        assert_eq!(secrets.active_count(), 1);
    }

    #[test]
    fn settings_update_without_a_secret_preserves_the_existing_reference() {
        let auth_ref = LlmAuthRef::new("test-secret-ref://existing");
        let profiles = FaultingProfiles {
            profile: Mutex::new(Some(profile(Some(auth_ref.clone())))),
            ..FaultingProfiles::default()
        };
        let mut update = profile(None);
        update.display_name = "Updated".into();

        let saved = save_profile_preserving_credential(&profiles, update).unwrap();

        assert_eq!(saved.display_name, "Updated");
        assert_eq!(saved.auth_ref.as_ref(), Some(&auth_ref));
    }

    #[test]
    fn failed_profile_delete_keeps_the_referenced_secret() {
        let auth_ref = LlmAuthRef::new("test-secret-ref://existing");
        let profiles = FaultingProfiles {
            profile: Mutex::new(Some(profile(Some(auth_ref.clone())))),
            fail_delete: AtomicBool::new(true),
            ..FaultingProfiles::default()
        };
        let secrets = TrackingSecretStore::default();
        secrets.seed(&auth_ref);

        let result = delete_profile_then_secret(&profiles, &profile(None).id, &secrets);

        assert!(matches!(result, Err(ApplicationError::Repository(_))));
        assert!(
            profiles
                .get_provider_profile(&profile(None).id)
                .unwrap()
                .is_some()
        );
        assert!(secrets.resolve(&auth_ref).unwrap().is_some());
        assert_eq!(secrets.delete_calls.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn failed_old_secret_cleanup_keeps_rotation_successful_and_durable_for_retry() {
        let old_auth_ref = LlmAuthRef::new("test-secret-ref://old");
        let profiles = FaultingProfiles {
            profile: Mutex::new(Some(profile(Some(old_auth_ref.clone())))),
            ..FaultingProfiles::default()
        };
        let secrets = TrackingSecretStore::default();
        secrets.seed(&old_auth_ref);
        secrets.fail_delete.store(true, Ordering::SeqCst);

        let saved =
            register_profile_with_secret(&profiles, profile(None), "not-observed", &secrets);

        assert!(saved.is_ok());
        let persisted = profiles
            .get_provider_profile(&profile(None).id)
            .unwrap()
            .unwrap();
        assert_ne!(persisted.auth_ref.as_ref(), Some(&old_auth_ref));
        assert!(
            secrets
                .resolve(persisted.auth_ref.as_ref().unwrap())
                .unwrap()
                .is_some()
        );
        assert!(secrets.resolve(&old_auth_ref).unwrap().is_some());
        assert_eq!(
            profiles.pending_secret_cleanups().unwrap(),
            vec![old_auth_ref.clone()]
        );

        secrets.fail_delete.store(false, Ordering::SeqCst);
        assert_eq!(retry_secret_cleanups(&profiles, &secrets).unwrap(), 1);
        assert!(profiles.pending_secret_cleanups().unwrap().is_empty());
        assert!(secrets.resolve(&old_auth_ref).unwrap().is_none());
    }

    #[test]
    fn failed_secret_cleanup_after_delete_is_retryable_without_restoring_profile() {
        let auth_ref = LlmAuthRef::new("test-secret-ref://existing");
        let profiles = FaultingProfiles {
            profile: Mutex::new(Some(profile(Some(auth_ref.clone())))),
            ..FaultingProfiles::default()
        };
        let secrets = TrackingSecretStore::default();
        secrets.seed(&auth_ref);
        secrets.fail_delete.store(true, Ordering::SeqCst);

        let result = delete_profile_then_secret(&profiles, &profile(None).id, &secrets);

        assert!(result.is_ok());
        assert!(
            profiles
                .get_provider_profile(&profile(None).id)
                .unwrap()
                .is_none()
        );
        assert!(secrets.resolve(&auth_ref).unwrap().is_some());
        assert_eq!(
            profiles.pending_secret_cleanups().unwrap(),
            vec![auth_ref.clone()]
        );
    }
}
