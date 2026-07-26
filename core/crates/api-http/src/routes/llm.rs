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

use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, Json, Path, Serialize, State, StatusCode,
};
use application::RubricGenerationRequest;
use domain::{
    CapabilityClaim, CostBudget, DataRetentionPreference, LanguageCode, LlmAdapterKind,
    LlmProviderProfile, LlmProviderProfileId, LlmUse, ProviderCapability, RubricPointImportance,
    SemanticJudgment, SemanticTaskAttemptId, SemanticTaskKind, llm_provider_profile_id,
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
    let provider = build_provider(&state, &id).await?;
    let claim = provider
        .probe_structured_output()
        .await
        .map_err(ApplicationError::from)?;
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
    let provider = build_provider(&state, &id).await?;
    let response_revision = request.response_revision;
    let now = application::now_ms();
    let judgment = state
        .application
        .execute_async("llm.judge_attempt", move |services| async move {
            services
                .semantic()
                .judge_semantic_attempt(&attempt_id, response_revision, provider.as_judge(), now)
                .await
        })
        .await?;
    Ok(Json(judgment))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ProviderFeedbackRequest {
    pub attempt_id: String,
    pub response_revision: u32,
}

/// Free-text qualitative feedback view. Ephemeral by design: nothing is
/// persisted server-side, so a refused or cut-off answer costs nothing.
#[derive(Debug, Serialize)]
pub(crate) struct OutputFeedbackView {
    pub feedback: String,
    pub model_id: Option<String>,
    pub prompt_version: Option<String>,
}

/// Gives teacher-style free-text feedback on one stored output-task attempt
/// (speaking/writing), with the rubric source transcript and task prompt as
/// context. Distinct from `judge_via_llm_provider`, which Reading keeps for
/// per-point rubric judgments.
pub(crate) async fn feedback_via_llm_provider(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<ProviderFeedbackRequest>,
) -> Result<Json<OutputFeedbackView>, ApiError> {
    let attempt_id =
        SemanticTaskAttemptId::parse(request.attempt_id).map_err(ApplicationError::from)?;
    let provider = build_provider(&state, &id).await?;
    let response_revision = request.response_revision;
    let draft = state
        .application
        .execute_async("llm.feedback_attempt", move |services| async move {
            services
                .semantic()
                .feedback_on_semantic_attempt(
                    &attempt_id,
                    response_revision,
                    provider.as_feedback(),
                )
                .await
        })
        .await?;
    Ok(Json(OutputFeedbackView {
        feedback: draft.feedback,
        model_id: draft.model_id,
        prompt_version: draft.prompt_version,
    }))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ProviderRubricRequest {
    pub purpose: SemanticTaskKind,
    pub source_language: LanguageCode,
    pub response_language: LanguageCode,
    pub transcript_snapshot: String,
}

#[derive(Debug, Serialize)]
pub(crate) struct RubricPointDraftView {
    pub importance: RubricPointImportance,
    pub statement: String,
    pub accepted_paraphrase_notes: Option<String>,
}

/// Content-only rubric proposal. Deliberately omits identity/version/source
/// snapshot: those are minted only when the user saves an approved rubric
/// through the manual create path, so the vendor layer never becomes a rubric
/// identity writer (ADR 0021 four-layer separation).
#[derive(Debug, Serialize)]
pub(crate) struct RubricDraftView {
    pub points: Vec<RubricPointDraftView>,
    pub model_id: Option<String>,
    pub prompt_version: Option<String>,
    pub schema_version: Option<String>,
}

/// Generates a rubric draft (information points only) for one source segment.
/// The draft is not persisted; the client shows it for review/edit and saves an
/// approved rubric through the normal create path. On any provider error nothing
/// is returned and a standardized, secret-free error is surfaced.
pub(crate) async fn generate_rubric_via_llm_provider(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<ProviderRubricRequest>,
) -> Result<Json<RubricDraftView>, ApiError> {
    let provider = build_provider(&state, &id).await?;
    let generation = RubricGenerationRequest {
        purpose: request.purpose,
        source_language: request.source_language,
        response_language: request.response_language,
        transcript_snapshot: request.transcript_snapshot,
    };
    let draft = provider
        .as_rubric()
        .generate_rubric(&generation)
        .await
        .map_err(ApplicationError::from)?;
    Ok(Json(RubricDraftView {
        points: draft
            .points
            .into_iter()
            .map(|point| RubricPointDraftView {
                importance: point.importance,
                statement: point.statement,
                accepted_paraphrase_notes: point.accepted_paraphrase_notes,
            })
            .collect(),
        model_id: draft.model_id,
        prompt_version: draft.prompt_version,
        schema_version: draft.schema_version,
    }))
}

/// Loads a profile, resolves its secret, and builds the concrete provider.
async fn build_provider(state: &ApiState, id: &str) -> Result<BuiltSemanticProvider, ApiError> {
    let id = LlmProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    let secret_store = state.infrastructure.secret_store.clone();
    let (profile, secret) = state
        .application
        .execute("llm.build_provider", move |services| {
            let module = services.llm_providers();
            let profile = module
                .llm_provider_profile(&id)?
                .ok_or(ApplicationError::NotFound("llm provider profile"))?;
            let secret = module.resolve_llm_provider_secret(&profile, secret_store.as_ref())?;
            Ok((profile, secret))
        })
        .await?;
    BuiltSemanticProvider::build(&profile, secret)
        .map_err(ApplicationError::from)
        .map_err(ApiError::from)
}
