use application::SpeechSynthesisError;
use local_runtime::{SpeechSynthesisAsset, SpeechSynthesisCapabilityView, SpeechSynthesisRequest};

use crate::{ApiError, ApiState, Json, State, StatusCode};

pub(crate) async fn speech_synthesis_capability(
    State(state): State<ApiState>,
) -> Json<SpeechSynthesisCapabilityView> {
    Json(state.generative.speech_synthesis.capability().await)
}

pub(crate) async fn synthesize_speech(
    State(state): State<ApiState>,
    Json(request): Json<SpeechSynthesisRequest>,
) -> Result<Json<SpeechSynthesisAsset>, ApiError> {
    state
        .generative
        .speech_synthesis
        .synthesize(request)
        .await
        .map(Json)
        .map_err(synthesis_error)
}

pub(crate) async fn clear_speech_synthesis_cache(
    State(state): State<ApiState>,
) -> Result<Json<SpeechSynthesisCapabilityView>, ApiError> {
    state
        .generative
        .speech_synthesis
        .clear_cache()
        .await
        .map(Json)
        .map_err(synthesis_error)
}

fn synthesis_error(error: SpeechSynthesisError) -> ApiError {
    match error {
        SpeechSynthesisError::InvalidRequest(message)
        | SpeechSynthesisError::UnsupportedLanguage(message)
        | SpeechSynthesisError::VoiceUnavailable(message) => ApiError::new(
            StatusCode::BAD_REQUEST,
            "speech_synthesis_invalid_request",
            message,
            false,
        ),
        SpeechSynthesisError::Unavailable(message) => ApiError::new(
            StatusCode::SERVICE_UNAVAILABLE,
            "speech_synthesis_unavailable",
            message,
            true,
        ),
        SpeechSynthesisError::Provider(message) => {
            ApiError::gateway("speech_synthesis_provider_failed", message)
        }
        SpeechSynthesisError::Cache(message) => ApiError::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            "speech_synthesis_cache_failed",
            message,
            true,
        ),
    }
}
