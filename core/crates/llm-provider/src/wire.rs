//! Shared wire-level error mapping.
//!
//! Guardrail: nothing here echoes request headers, auth material, or raw
//! response bodies into an error. HTTP status codes map to the standardized
//! [`LlmProviderError`] taxonomy; unexpected statuses carry only the numeric
//! code, never provider text that might contain reflected secrets.

use domain::LlmProviderError;

/// Map a transport-level `reqwest` failure onto the neutral taxonomy.
pub(crate) fn map_reqwest_error(error: &reqwest::Error) -> LlmProviderError {
    if error.is_timeout() {
        LlmProviderError::Timeout
    } else if error.is_connect() || error.is_request() {
        LlmProviderError::Offline
    } else {
        // Only the reqwest error category is surfaced, never the URL/body.
        LlmProviderError::Protocol {
            detail: "transport failure".into(),
        }
    }
}

/// Map a non-success HTTP status onto the neutral taxonomy. `retry_after_ms`
/// is taken from the `Retry-After` header when present.
pub(crate) fn map_status_error(
    status: reqwest::StatusCode,
    retry_after_ms: Option<u64>,
) -> LlmProviderError {
    match status.as_u16() {
        401 | 403 => LlmProviderError::Auth,
        429 => LlmProviderError::RateLimit { retry_after_ms },
        // 529 is Anthropic "overloaded"; treat as a transient offline signal.
        503 | 529 => LlmProviderError::Offline,
        code => LlmProviderError::Protocol {
            detail: format!("unexpected status {code}"),
        },
    }
}

/// A protocol error whose detail is a fixed, secret-free string.
pub(crate) fn sanitized_protocol(detail: &str) -> LlmProviderError {
    LlmProviderError::Protocol {
        detail: detail.to_string(),
    }
}

/// Parse a `Retry-After` header value (seconds) into milliseconds.
pub(crate) fn retry_after_ms(headers: &reqwest::header::HeaderMap) -> Option<u64> {
    headers
        .get(reqwest::header::RETRY_AFTER)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.trim().parse::<u64>().ok())
        .map(|secs| secs.saturating_mul(1000))
}
