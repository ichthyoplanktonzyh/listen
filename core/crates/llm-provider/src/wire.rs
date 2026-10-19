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

/// Parse either standard `Retry-After` form: delta-seconds or HTTP-date.
pub(crate) fn retry_after_ms(headers: &reqwest::header::HeaderMap) -> Option<u64> {
    let value = headers
        .get(reqwest::header::RETRY_AFTER)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)?;
    if let Ok(seconds) = value.parse::<u64>() {
        return Some(seconds.saturating_mul(1000));
    }
    let retry_at = httpdate::parse_http_date(value).ok()?;
    let delay = retry_at
        .duration_since(std::time::SystemTime::now())
        .unwrap_or_default();
    Some(delay.as_millis().min(u128::from(u64::MAX)) as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retry_after_accepts_delta_seconds_and_http_date() {
        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(reqwest::header::RETRY_AFTER, "2".parse().unwrap());
        assert_eq!(retry_after_ms(&headers), Some(2_000));

        let future = std::time::SystemTime::now() + std::time::Duration::from_secs(60);
        headers.insert(
            reqwest::header::RETRY_AFTER,
            httpdate::fmt_http_date(future).parse().unwrap(),
        );
        let parsed = retry_after_ms(&headers).unwrap();
        assert!((58_000..=60_000).contains(&parsed), "{parsed}");
    }
}
