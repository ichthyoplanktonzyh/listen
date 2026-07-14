use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use domain::SubtitleSearchResult;
use local_runtime::{
    SubtitleDownloadRequest, SubtitleOperation, SubtitleProviderError, SubtitleSearchRequest,
};

use crate::{ApiError, ApiState};

fn provider_error(error: SubtitleProviderError) -> ApiError {
    match error {
        SubtitleProviderError::ProviderNotFound => ApiError::not_found("subtitle search provider"),
        SubtitleProviderError::CredentialsRequired => ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_credentials_required",
            "subtitle provider credentials are required",
            false,
        ),
        SubtitleProviderError::QueryRequired => ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_search_query_required",
            "a title, filename, or media hash is required",
            false,
        ),
        SubtitleProviderError::Authentication => ApiError::new(
            StatusCode::UNAUTHORIZED,
            "subtitle_authentication_failed",
            "subtitle provider rejected the configured credentials",
            false,
        ),
        SubtitleProviderError::RateLimited => ApiError::new(
            StatusCode::TOO_MANY_REQUESTS,
            "subtitle_rate_limited",
            "subtitle provider rate limit reached",
            true,
        ),
        SubtitleProviderError::Unavailable(operation) => ApiError::gateway(
            "subtitle_service_unavailable",
            format!("subtitle provider {} is unavailable", operation.wire_name()),
        ),
        SubtitleProviderError::Rejected(operation) => ApiError::new(
            StatusCode::BAD_REQUEST,
            "subtitle_request_rejected",
            format!(
                "subtitle provider rejected the {} request",
                operation.wire_name()
            ),
            false,
        ),
        SubtitleProviderError::Network { operation, detail } => ApiError::gateway(
            match operation {
                SubtitleOperation::Search => "subtitle_search_failed",
                SubtitleOperation::Download => "subtitle_download_failed",
            },
            detail,
        ),
        SubtitleProviderError::MissingDownloadLink => {
            ApiError::gateway("subtitle_download_failed", "missing download link")
        }
    }
}

pub(crate) async fn search(
    State(state): State<ApiState>,
    Json(request): Json<SubtitleSearchRequest>,
) -> Result<Json<Vec<SubtitleSearchResult>>, ApiError> {
    state
        .subtitle_search
        .search(&request)
        .await
        .map(Json)
        .map_err(provider_error)
}

pub(crate) async fn download(
    State(state): State<ApiState>,
    Json(request): Json<SubtitleDownloadRequest>,
) -> Result<Response, ApiError> {
    state
        .subtitle_search
        .download(&request)
        .await
        .map_err(provider_error)
        .map(|bytes| {
            (
                [(axum::http::header::CONTENT_TYPE, "application/x-subrip")],
                bytes,
            )
                .into_response()
        })
}
