//! Phase 3.12 vendor-neutral LLM provider surface.
//!
//! Manages provider profiles (secure config, never the secret) and dispatches
//! provider-backed subtitle analysis. The raw key enters exactly once through
//! `register_llm_provider` (write-only) and is never returned: responses use
//! [`ProviderProfileView`], which exposes `has_credential`, not `auth_ref`.
//!
//! Provider credentials never enter responses; analysis output is validated
//! and saved through the media-analysis use case.

use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, Json, Path, Serialize, State, StatusCode,
};
use domain::{
    CapabilityClaim, CostBudget, DataRetentionPreference, LlmAdapterKind, LlmBatchPolicy,
    LlmProviderProfile, LlmProviderProfileId, LlmUse, ProviderCapability, SenseGroupAnalysis,
    SubtitleTrackId, TimelineStatus, llm_provider_profile_id,
};

/// Client-facing view of a profile. Deliberately omits `auth_ref`: the settings
/// UI needs to know a key *exists*, never the opaque reference itself.
#[derive(Debug, Serialize)]
pub(crate) struct ProviderProfileView {
    pub id: String,
    pub display_name: String,
    pub adapter_kind: LlmAdapterKind,
    pub protocol_version: Option<String>,
    pub base_url: String,
    pub model_id: String,
    pub has_credential: bool,
    pub timeout_ms: u64,
    pub max_retries: u32,
    pub batch_policy: LlmBatchPolicy,
    pub cost_budget: Option<CostBudget>,
    pub retention: DataRetentionPreference,
    pub allowed_uses: Vec<LlmUse>,
    pub capability: ProviderCapability,
    pub created_at_ms: u64,
}

impl From<&LlmProviderProfile> for ProviderProfileView {
    fn from(profile: &LlmProviderProfile) -> Self {
        Self {
            id: profile.id.as_str().to_string(),
            display_name: profile.display_name.clone(),
            adapter_kind: profile.adapter_kind,
            protocol_version: profile.protocol_version.clone(),
            base_url: profile.base_url.clone(),
            model_id: profile.model_id.clone(),
            has_credential: profile.auth_ref.is_some(),
            timeout_ms: profile.timeout_ms,
            max_retries: profile.max_retries,
            batch_policy: profile.batch_policy.clone(),
            cost_budget: profile.cost_budget,
            retention: profile.retention,
            allowed_uses: profile.allowed_uses.clone(),
            capability: profile.capability,
            created_at_ms: profile.created_at_ms,
        }
    }
}

fn default_timeout_ms() -> u64 {
    30_000
}

#[derive(Debug, Deserialize)]
pub(crate) struct RegisterProviderRequest {
    pub display_name: String,
    pub adapter_kind: LlmAdapterKind,
    #[serde(default)]
    pub protocol_version: Option<String>,
    pub base_url: String,
    pub model_id: String,
    /// Write-only. Present exactly when the endpoint needs a credential; it is
    /// stored in the secure store and never echoed back.
    #[serde(default)]
    pub secret: Option<String>,
    #[serde(default = "default_timeout_ms")]
    pub timeout_ms: u64,
    #[serde(default)]
    pub max_retries: u32,
    #[serde(default)]
    pub batch_policy: LlmBatchPolicy,
    #[serde(default)]
    pub cost_budget: Option<CostBudget>,
    pub retention: DataRetentionPreference,
    pub allowed_uses: Vec<LlmUse>,
}

pub(crate) async fn list_llm_providers(
    State(state): State<ApiState>,
) -> Result<Json<Vec<ProviderProfileView>>, ApiError> {
    let profiles = state
        .application
        .execute("llm.list_profiles", move |services| {
            services.llm_providers().list_llm_provider_profiles()
        })
        .await?;
    Ok(Json(
        profiles.iter().map(ProviderProfileView::from).collect(),
    ))
}

pub(crate) async fn register_llm_provider(
    State(state): State<ApiState>,
    Json(request): Json<RegisterProviderRequest>,
) -> Result<Json<ProviderProfileView>, ApiError> {
    if request.batch_policy.max_in_flight == 0 {
        return Err(ApiError::from(ApplicationError::Invalid(
            "batch_policy.max_in_flight must be greater than zero".into(),
        )));
    }
    if request.batch_policy.start_rate_per_second == Some(0) {
        return Err(ApiError::from(ApplicationError::Invalid(
            "batch_policy.start_rate_per_second must be greater than zero".into(),
        )));
    }
    let id = llm_provider_profile_id(request.adapter_kind, &request.base_url, &request.model_id);
    let profile = LlmProviderProfile {
        id,
        display_name: request.display_name,
        adapter_kind: request.adapter_kind,
        protocol_version: request.protocol_version,
        base_url: request.base_url,
        model_id: request.model_id,
        auth_ref: None,
        timeout_ms: request.timeout_ms,
        max_retries: request.max_retries,
        batch_policy: request.batch_policy,
        cost_budget: request.cost_budget,
        retention: request.retention,
        allowed_uses: request.allowed_uses,
        capability: ProviderCapability::unknown(),
        created_at_ms: application::now_ms(),
    };
    let secret_store = state.infrastructure.secret_store.clone();
    let saved = state
        .application
        .execute("llm.register_profile", move |services| {
            match request.secret {
                Some(secret) if !secret.is_empty() => services
                    .llm_providers()
                    .register_llm_provider(profile, &secret, secret_store.as_ref()),
                _ => services.llm_providers().save_llm_provider_profile(profile),
            }
        })
        .await?;
    Ok(Json(ProviderProfileView::from(&saved)))
}

pub(crate) async fn get_llm_provider(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<ProviderProfileView>, ApiError> {
    let id = LlmProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("llm.get_profile", move |services| {
            services.llm_providers().llm_provider_profile(&id)
        })
        .await?
        .as_ref()
        .map(ProviderProfileView::from)
        .map(Json)
        .ok_or_else(|| ApiError::not_found("llm provider profile"))
}

pub(crate) async fn delete_llm_provider(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<StatusCode, ApiError> {
    let id = LlmProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    let secret_store = state.infrastructure.secret_store.clone();
    state
        .application
        .execute("llm.delete_profile", move |services| {
            services
                .llm_providers()
                .delete_llm_provider(&id, secret_store.as_ref())
        })
        .await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Serialize)]
pub(crate) struct ProbeResult {
    pub structured_output: CapabilityClaim,
}

/// Connectivity + capability test. Actually exercises structured output against
/// the endpoint (the Ollama trap: protocol compatibility is not capability
/// equivalence). This is a diagnostic, not learning feedback.
pub(crate) async fn probe_llm_provider(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<ProbeResult>, ApiError> {
    let id = LlmProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    let secret_store = state.infrastructure.secret_store.clone();
    let factory = state.generative.llm_runtime_factory.clone();
    let claim = state
        .application
        .execute_async("llm.probe_provider", move |services| async move {
            services
                .llm_providers()
                .probe_structured_output(&id, secret_store.as_ref(), factory.as_ref())
                .await
        })
        .await?;
    Ok(Json(ProbeResult {
        structured_output: claim,
    }))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ProviderSenseGroupRequest {
    pub batch_id: String,
    pub track_id: String,
    #[serde(default)]
    pub status: Option<TimelineStatus>,
}

/// Generates and persists one hybrid SenseGroup analysis. Each sentence is
/// proposed by the configured LLM, validated against server-owned token
/// indices, and independently falls back to the deterministic partitioner.
pub(crate) async fn generate_sense_groups_via_llm_provider(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<ProviderSenseGroupRequest>,
) -> Result<Json<SenseGroupAnalysis>, ApiError> {
    let track_id = SubtitleTrackId::parse(request.track_id).map_err(ApplicationError::from)?;
    let id = LlmProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    let batch_id = request.batch_id;
    let coordinator = state.generative.llm_batches.clone();
    let secret_store = state.infrastructure.secret_store.clone();
    let factory = state.generative.llm_runtime_factory.clone();
    let status = request.status;
    state
        .application
        .execute_async("llm.generate_sense_groups", move |services| async move {
            services
                .llm_providers()
                .generate_sense_groups(
                    &id,
                    &batch_id,
                    &track_id,
                    status,
                    &coordinator,
                    secret_store.as_ref(),
                    factory.as_ref(),
                )
                .await
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn llm_batch_status(
    State(state): State<ApiState>,
    Path(batch_id): Path<String>,
) -> Result<Json<application::batch_governor::BatchProgress>, ApiError> {
    let coordinator = state.generative.llm_batches.clone();
    state
        .application
        .execute("llm.batch_status", move |services| {
            services
                .llm_providers()
                .batch_status(&batch_id, &coordinator)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("LLM batch"))
}

pub(crate) async fn cancel_llm_batch(
    State(state): State<ApiState>,
    Path(batch_id): Path<String>,
) -> Result<Json<application::batch_governor::BatchProgress>, ApiError> {
    let coordinator = state.generative.llm_batches.clone();
    state
        .application
        .execute("llm.cancel_batch", move |services| {
            services
                .llm_providers()
                .cancel_batch(&batch_id, &coordinator)
        })
        .await?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("LLM batch"))
}
