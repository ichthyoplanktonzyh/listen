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
    OutputFeedbackDraft, RubricDraft, RubricGenerationRequest, SecretStore, SemanticLlmRuntime,
    SemanticLlmRuntimeFactory, SemanticUseCases,
};

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

    /// Persists a provider profile as-is (no secret handling). Use
    /// [`LlmProviderUseCases::register_llm_provider`] when there is a raw key to store.
    pub fn save_llm_provider_profile(
        &self,
        profile: LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        self.profiles.upsert_provider_profile(&profile)
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
        self.profiles.upsert_provider_profile(&profile)
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

    /// Deletes a profile and, if it referenced a secret, removes that secret
    /// from the secure store. Idempotent: deleting an unknown profile is a
    /// no-op success.
    pub fn delete_llm_provider(
        &self,
        id: &LlmProviderProfileId,
        secret_store: &dyn SecretStore,
    ) -> Result<(), ApplicationError> {
        if let Some(profile) = self.profiles.get_provider_profile(id)?
            && let Some(auth_ref) = &profile.auth_ref
        {
            secret_store.delete(auth_ref)?;
        }
        self.profiles.delete_provider_profile(id)
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
        batches.finish(batch_id, result.is_ok());
        result
    }

    pub fn batch_status(
        &self,
        batch_id: &str,
        batches: &LlmBatchCoordinator,
    ) -> Option<BatchProgress> {
        batches.status(batch_id)
    }

    pub fn cancel_batch(
        &self,
        batch_id: &str,
        batches: &LlmBatchCoordinator,
    ) -> Option<BatchProgress> {
        batches.cancel(batch_id)
    }
}
