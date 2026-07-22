use application::ApplicationError;
use axum::Json;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use domain::{LearningResourceDescriptor, LearningResourceId};

use crate::{ApiError, ApiState};

fn resource_error(error: local_runtime::LearningResourceError) -> ApiError {
    match error {
        local_runtime::LearningResourceError::NotFound => ApiError::not_found("learning resource"),
        local_runtime::LearningResourceError::ChecksumMismatch => ApiError::new(
            StatusCode::UNPROCESSABLE_ENTITY,
            "checksum_mismatch",
            "learning resource checksum mismatch",
            false,
        ),
        local_runtime::LearningResourceError::Download(detail) => {
            ApiError::gateway("resource_download_failed", detail)
        }
        local_runtime::LearningResourceError::Storage(error) => ApiError::from(error),
    }
}

pub(crate) async fn list(State(state): State<ApiState>) -> Json<Vec<LearningResourceDescriptor>> {
    Json(state.learning_resources.list())
}

pub(crate) async fn install(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LearningResourceDescriptor>, ApiError> {
    state
        .learning_resources
        .install(&LearningResourceId::parse(id).map_err(ApplicationError::from)?)
        .await
        .map(Json)
        .map_err(resource_error)
}

pub(crate) async fn remove(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<LearningResourceDescriptor>, ApiError> {
    state
        .learning_resources
        .remove(&LearningResourceId::parse(id).map_err(ApplicationError::from)?)
        .await
        .map(Json)
        .map_err(resource_error)
}
