use std::time::Duration;

use application::{
    RealtimeAudioFormat, RealtimeConversationAdapter, RealtimeEvent, RealtimeSessionRequest,
    RealtimeTurnDetection,
};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use domain::{
    LanguageCode, RealtimeAdapterKind, RealtimeConversationSession, RealtimeConversationTurn,
    RealtimeProviderProfile, RealtimeProviderProfileId, SecretRef, realtime_provider_profile_id,
};
use futures_util::{SinkExt, StreamExt};
use realtime_provider::{OpenAiRealtimeAdapter, QwenRealtimeAdapter, RealtimeAdapterConfig};

use crate::{ApiError, ApiState, ApplicationError, Deserialize, Json, Path, Serialize, State};

#[derive(Debug, Serialize)]
pub(crate) struct RealtimeProfileView {
    id: String,
    display_name: String,
    adapter_kind: RealtimeAdapterKind,
    base_url: String,
    model_id: String,
    voice: String,
    has_credential: bool,
    timeout_ms: u64,
}

impl From<&RealtimeProviderProfile> for RealtimeProfileView {
    fn from(profile: &RealtimeProviderProfile) -> Self {
        Self {
            id: profile.id.as_str().into(),
            display_name: profile.display_name.clone(),
            adapter_kind: profile.adapter_kind,
            base_url: profile.base_url.clone(),
            model_id: profile.model_id.clone(),
            voice: profile.voice.clone(),
            has_credential: true,
            timeout_ms: profile.timeout_ms,
        }
    }
}

#[derive(Debug, Deserialize)]
pub(crate) struct RegisterRealtimeProfileRequest {
    display_name: String,
    adapter_kind: RealtimeAdapterKind,
    base_url: String,
    model_id: String,
    voice: String,
    secret: String,
    #[serde(default = "default_timeout")]
    timeout_ms: u64,
}

fn default_timeout() -> u64 {
    30_000
}

pub(crate) async fn list_profiles(
    State(state): State<ApiState>,
) -> Result<Json<Vec<RealtimeProfileView>>, ApiError> {
    Ok(Json(
        state
            .services
            .realtime_conversations()
            .list_profiles()?
            .iter()
            .map(RealtimeProfileView::from)
            .collect(),
    ))
}

pub(crate) async fn register_profile(
    State(state): State<ApiState>,
    Json(request): Json<RegisterRealtimeProfileRequest>,
) -> Result<Json<RealtimeProfileView>, ApiError> {
    if request.secret.trim().is_empty() {
        return Err(ApiError::new(
            axum::http::StatusCode::BAD_REQUEST,
            "invalid_realtime_profile",
            "realtime provider credential is required",
            false,
        ));
    }
    let profile = RealtimeProviderProfile {
        id: realtime_provider_profile_id(
            request.adapter_kind,
            &request.base_url,
            &request.model_id,
        ),
        display_name: request.display_name,
        adapter_kind: request.adapter_kind,
        base_url: request.base_url,
        model_id: request.model_id,
        voice: request.voice,
        auth_ref: SecretRef::new("pending://write-only"),
        timeout_ms: request.timeout_ms,
        created_at_ms: application::now_ms(),
    };
    let saved = state.services.realtime_conversations().register_profile(
        profile,
        &request.secret,
        state.secret_store.as_ref(),
    )?;
    Ok(Json(RealtimeProfileView::from(&saved)))
}

pub(crate) async fn delete_profile(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<axum::http::StatusCode, ApiError> {
    let id = RealtimeProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .realtime_conversations()
        .delete_profile(&id, state.secret_store.as_ref())?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}

pub(crate) async fn save_session(
    State(state): State<ApiState>,
    Json(session): Json<RealtimeConversationSession>,
) -> Result<Json<RealtimeConversationSession>, ApiError> {
    Ok(Json(
        state
            .services
            .realtime_conversations()
            .save_session(session)?,
    ))
}

pub(crate) async fn save_turn(
    State(state): State<ApiState>,
    Json(turn): Json<RealtimeConversationTurn>,
) -> Result<Json<RealtimeConversationTurn>, ApiError> {
    Ok(Json(
        state
            .services
            .production_corpus()
            .record_realtime_turn_and_index(turn)?,
    ))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ConnectQuery {
    profile_id: String,
    #[serde(default = "default_language")]
    language: String,
    #[serde(default)]
    instructions: String,
    #[serde(default)]
    manual_turns: bool,
}

fn default_language() -> String {
    "en".into()
}

pub(crate) async fn connect(
    ws: WebSocketUpgrade,
    State(state): State<ApiState>,
    axum::extract::Query(query): axum::extract::Query<ConnectQuery>,
) -> Result<axum::response::Response, ApiError> {
    let id = RealtimeProviderProfileId::parse(query.profile_id).map_err(ApplicationError::from)?;
    let profile = state
        .services
        .realtime_conversations()
        .profile(&id)?
        .ok_or_else(|| ApiError::not_found("realtime provider profile"))?;
    let credential = state
        .services
        .realtime_conversations()
        .resolve_secret(&profile, state.secret_store.as_ref())?
        .ok_or_else(|| {
            ApiError::new(
                axum::http::StatusCode::BAD_REQUEST,
                "realtime_credential_missing",
                "realtime provider credential is missing",
                false,
            )
        })?;
    let language = LanguageCode::parse(query.language).map_err(ApplicationError::from)?;
    Ok(ws.on_upgrade(move |socket| {
        run_socket(
            socket,
            profile,
            credential,
            language,
            query.instructions,
            query.manual_turns,
        )
    }))
}

async fn run_socket(
    socket: WebSocket,
    profile: RealtimeProviderProfile,
    credential: String,
    language: LanguageCode,
    instructions: String,
    manual_turns: bool,
) {
    let config = RealtimeAdapterConfig {
        base_url: profile.base_url,
        model_id: profile.model_id,
        credential,
        timeout: Duration::from_millis(profile.timeout_ms.clamp(1_000, 120_000)),
    };
    let adapter: Box<dyn RealtimeConversationAdapter> = match profile.adapter_kind {
        RealtimeAdapterKind::OpenAiRealtime => Box::new(OpenAiRealtimeAdapter::new(config)),
        RealtimeAdapterKind::QwenOmniRealtime => Box::new(QwenRealtimeAdapter::new(config)),
    };
    let request = RealtimeSessionRequest {
        instructions,
        language,
        voice: profile.voice,
        input_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
        output_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
        turn_detection: if manual_turns {
            RealtimeTurnDetection::Manual
        } else {
            RealtimeTurnDetection::ServerVad
        },
    };
    let (mut client_tx, mut client_rx) = socket.split();
    let mut provider = match adapter.connect(&request).await {
        Ok(provider) => provider,
        Err(error) => {
            let _ = client_tx
                .send(Message::Text(
                    serde_json::json!({"type":"connection_failed","error":error})
                        .to_string()
                        .into(),
                ))
                .await;
            return;
        }
    };
    loop {
        tokio::select! {
            incoming = client_rx.next() => match incoming {
                Some(Ok(Message::Binary(bytes))) => if provider.send_audio(&bytes).await.is_err() { break; },
                Some(Ok(Message::Text(command))) if command == "commit" => { if provider.commit_turn().await.is_err() { break; } },
                Some(Ok(Message::Text(command))) if command == "cancel" => { let _ = provider.cancel_response().await; },
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                _ => {}
            },
            event = provider.next_event() => match event {
                Ok(Some(RealtimeEvent::AssistantAudioDelta { pcm16_mono_24khz, .. })) => if client_tx.send(Message::Binary(pcm16_mono_24khz.into())).await.is_err() { break; },
                Ok(Some(event)) => if client_tx.send(Message::Text(serde_json::to_string(&event).unwrap_or_else(|_| "{\"type\":\"protocol_error\"}".into()).into())).await.is_err() { break; },
                Ok(None) => break,
                Err(error) => { let _ = client_tx.send(Message::Text(serde_json::json!({"type":"provider_error","error":error}).to_string().into())).await; break; }
            }
        }
    }
    let _ = provider.close().await;
}
