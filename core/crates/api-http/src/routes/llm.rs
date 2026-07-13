//! Phase 3.12 vendor-neutral LLM provider surface.
//!
//! Manages provider profiles (secure config, never the secret) and dispatches
//! provider-backed rubric/judgment. The raw key enters exactly once through
//! `register_llm_provider` (write-only) and is never returned: responses use
//! [`ProviderProfileView`], which exposes `has_credential`, not `auth_ref`.
//!
//! Judgments produced here are unqualified `heuristic_proxy` (ADR 0022 §7): no
//! observation or projection is written, and nothing is surfaced as learning
//! feedback until Phase 3.12.1 grants display qualification.

use crate::*;
use domain::{
    CapabilityClaim, CostBudget, DataRetentionPreference, LlmAdapterKind, LlmProviderProfile,
    LlmProviderProfileId, LlmUse, ProviderCapability, SemanticJudgment, SemanticTaskAttemptId,
    llm_provider_profile_id,
};
use llm_provider::BuiltSemanticProvider;

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
    pub cost_budget: Option<CostBudget>,
    pub retention: DataRetentionPreference,
    pub allowed_uses: Vec<LlmUse>,
}

pub(crate) async fn list_llm_providers(
    State(state): State<ApiState>,
) -> Result<Json<Vec<ProviderProfileView>>, ApiError> {
    let profiles = state.services.list_llm_provider_profiles()?;
    Ok(Json(profiles.iter().map(ProviderProfileView::from).collect()))
}

pub(crate) async fn register_llm_provider(
    State(state): State<ApiState>,
    Json(request): Json<RegisterProviderRequest>,
) -> Result<Json<ProviderProfileView>, ApiError> {
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
        cost_budget: request.cost_budget,
        retention: request.retention,
        allowed_uses: request.allowed_uses,
        capability: ProviderCapability::unknown(),
        created_at_ms: application::now_ms(),
    };
    let saved = match request.secret {
        Some(secret) if !secret.is_empty() => {
            state
                .services
                .register_llm_provider(profile, &secret, state.secret_store.as_ref())?
        }
        _ => state.services.save_llm_provider_profile(profile)?,
    };
    Ok(Json(ProviderProfileView::from(&saved)))
}

pub(crate) async fn get_llm_provider(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<ProviderProfileView>, ApiError> {
    let id = LlmProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .llm_provider_profile(&id)?
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
    state
        .services
        .delete_llm_provider(&id, state.secret_store.as_ref())?;
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
    let provider = build_provider(&state, &id)?;
    let claim = provider.probe_structured_output().await.map_err(ApplicationError::from)?;
    Ok(Json(ProbeResult {
        structured_output: claim,
    }))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ProviderJudgeRequest {
    pub attempt_id: String,
    pub response_revision: u32,
}

/// Judges one stored attempt through a provider and records the result. On any
/// provider error (offline/auth/refusal/truncated/schema-invalid) nothing is
/// written and a standardized, secret-free error is returned.
pub(crate) async fn judge_via_llm_provider(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<ProviderJudgeRequest>,
) -> Result<Json<SemanticJudgment>, ApiError> {
    let attempt_id =
        SemanticTaskAttemptId::parse(request.attempt_id).map_err(ApplicationError::from)?;
    let provider = build_provider(&state, &id)?;
    let judgment = state
        .services
        .judge_semantic_attempt(
            &attempt_id,
            request.response_revision,
            provider.as_judge(),
            application::now_ms(),
        )
        .await?;
    Ok(Json(judgment))
}

/// Loads a profile, resolves its secret, and builds the concrete provider.
fn build_provider(state: &ApiState, id: &str) -> Result<BuiltSemanticProvider, ApiError> {
    let id = LlmProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    let profile = state
        .services
        .llm_provider_profile(&id)?
        .ok_or_else(|| ApiError::not_found("llm provider profile"))?;
    let secret = state
        .services
        .resolve_llm_provider_secret(&profile, state.secret_store.as_ref())?;
    BuiltSemanticProvider::build(&profile, secret)
        .map_err(ApplicationError::from)
        .map_err(ApiError::from)
}
