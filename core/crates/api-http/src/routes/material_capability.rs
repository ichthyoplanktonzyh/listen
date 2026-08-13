//! Material Capability HTTP surface (contract `4.0.0`).
//!
//! Wire adaptation only: the five-state capability projection, durable
//! production attempts, and explicit attempt finalization. Attempts are the
//! unit of `generating` / `failed_attempt` evidence; a failed attempt never
//! invalidates an otherwise usable Material.

use application::AttemptOutcome;
use axum::Json;
use axum::extract::{Path, State};
use domain::{CapabilityAttempt, CapabilityAttemptId, LearningMaterialId, MaterialCapability};
use serde::{Deserialize, Serialize};

use crate::{ApiError, ApiState, ApplicationError};

#[derive(Debug, Serialize)]
pub(crate) struct CapabilityProjectionResponse {
    capability: &'static str,
    status: &'static str,
    latest_attempt: Option<CapabilityAttemptResponse>,
}

#[derive(Debug, Serialize)]
pub(crate) struct CapabilityAttemptResponse {
    attempt_id: String,
    material_id: String,
    capability: &'static str,
    status: &'static str,
    started_at_ms: u64,
    finished_at_ms: Option<u64>,
    failure_reason: Option<String>,
    producer_tool_id: Option<String>,
    producer_tool_version: Option<String>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct StartCapabilityAttemptRequest {
    capability: String,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub(crate) enum FinalizeCapabilityAttemptRequest {
    Succeeded {
        tool_id: String,
        tool_version: String,
    },
    Failed {
        reason: String,
    },
    Cancelled,
}

impl From<domain::MaterialCapabilityProjection> for CapabilityProjectionResponse {
    fn from(value: domain::MaterialCapabilityProjection) -> Self {
        Self {
            capability: capability_string(value.capability),
            status: status_string(value.status),
            latest_attempt: value.latest_attempt.map(CapabilityAttemptResponse::from),
        }
    }
}

impl From<CapabilityAttempt> for CapabilityAttemptResponse {
    fn from(value: CapabilityAttempt) -> Self {
        Self {
            attempt_id: value.attempt_id.as_str().to_owned(),
            material_id: value.material_id.as_str().to_owned(),
            capability: capability_string(value.capability),
            status: attempt_status_string(value.status),
            started_at_ms: value.started_at_ms,
            finished_at_ms: value.finished_at_ms,
            failure_reason: value.failure_reason,
            producer_tool_id: value.producer_tool_id,
            producer_tool_version: value.producer_tool_version,
        }
    }
}

fn capability_string(capability: MaterialCapability) -> &'static str {
    match capability {
        MaterialCapability::Read => "read",
        MaterialCapability::Listen => "listen",
        MaterialCapability::Watch => "watch",
        MaterialCapability::SynchronizedReadListen => "synchronized_read_listen",
    }
}

fn status_string(status: domain::CapabilityStatus) -> &'static str {
    use domain::CapabilityStatus::{Available, Derivable, FailedAttempt, Generating, Unavailable};
    match status {
        Available => "available",
        Derivable => "derivable",
        Generating => "generating",
        Unavailable => "unavailable",
        FailedAttempt => "failed_attempt",
    }
}

fn attempt_status_string(status: domain::CapabilityAttemptStatus) -> &'static str {
    use domain::CapabilityAttemptStatus::{Cancelled, Failed, Running, Succeeded, Superseded};
    match status {
        Running => "running",
        Succeeded => "succeeded",
        Failed => "failed",
        Cancelled => "cancelled",
        Superseded => "superseded",
    }
}

fn parse_capability(value: String) -> Result<MaterialCapability, ApiError> {
    Ok(match value.as_str() {
        "read" => MaterialCapability::Read,
        "listen" => MaterialCapability::Listen,
        "watch" => MaterialCapability::Watch,
        "synchronized_read_listen" => MaterialCapability::SynchronizedReadListen,
        _ => {
            return Err(ApiError::new(
                axum::http::StatusCode::BAD_REQUEST,
                "invalid_input",
                "capability must be read, listen, watch, or synchronized_read_listen",
                false,
            ));
        }
    })
}

/// GET /v1/materials/{material_id}/capabilities — the five-state projection
/// for every capability.
pub(crate) async fn list_material_capabilities(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
) -> Result<Json<Vec<CapabilityProjectionResponse>>, ApiError> {
    let id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("material.capabilities", move |services| {
            services.material_capability().project(&id)
        })
        .await
        .map(|projections| {
            projections
                .into_iter()
                .map(CapabilityProjectionResponse::from)
                .collect()
        })
        .map(Json)
        .map_err(ApiError::from)
}

/// POST /v1/materials/{material_id}/capability-attempts — start a production
/// attempt. Retry creates a new attempt and never rewrites the old attempt's
/// facts.
pub(crate) async fn start_material_capability_attempt(
    State(state): State<ApiState>,
    Path(material_id): Path<String>,
    Json(request): Json<StartCapabilityAttemptRequest>,
) -> Result<Json<CapabilityAttemptResponse>, ApiError> {
    let id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    let capability = parse_capability(request.capability)?;
    state
        .application
        .execute("material.capability_attempt.start", move |services| {
            services
                .material_capability()
                .start_attempt(&id, capability, crate::now_ms())
        })
        .await
        .map(CapabilityAttemptResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}

/// PUT /v1/materials/{material_id}/capability-attempts/{attempt_id} —
/// finalize a running attempt as succeeded or failed.
pub(crate) async fn finalize_material_capability_attempt(
    State(state): State<ApiState>,
    Path((material_id, attempt_id)): Path<(String, String)>,
    Json(request): Json<FinalizeCapabilityAttemptRequest>,
) -> Result<Json<CapabilityAttemptResponse>, ApiError> {
    let material_id = LearningMaterialId::parse(material_id).map_err(ApplicationError::from)?;
    let attempt_id = CapabilityAttemptId::parse(attempt_id).map_err(ApplicationError::from)?;
    let outcome = match request {
        FinalizeCapabilityAttemptRequest::Succeeded {
            tool_id,
            tool_version,
        } => AttemptOutcome::Succeeded {
            tool_id,
            tool_version,
        },
        FinalizeCapabilityAttemptRequest::Failed { reason } => AttemptOutcome::Failed { reason },
        FinalizeCapabilityAttemptRequest::Cancelled => AttemptOutcome::Cancelled,
    };
    state
        .application
        .execute("material.capability_attempt.finalize", move |services| {
            services.material_capability().finalize_attempt(
                &material_id,
                &attempt_id,
                outcome,
                crate::now_ms(),
            )
        })
        .await
        .map(CapabilityAttemptResponse::from)
        .map(Json)
        .map_err(ApiError::from)
}
