use application::{PreparedRealtimeConnection, RealtimeConnectionOptions, RealtimeEvent};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use domain::{
    LanguageCode, RealtimeAdapterKind, RealtimeConversationSession, RealtimeConversationTurn,
    RealtimeProviderProfile, RealtimeProviderProfileId, realtime_provider_profile_id,
};
use futures_util::{SinkExt, StreamExt};

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
            has_credential: profile.auth_ref.is_some(),
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
    #[serde(default)]
    secret: Option<String>,
    #[serde(default = "default_timeout")]
    timeout_ms: u64,
}

fn default_timeout() -> u64 {
    30_000
}

pub(crate) async fn list_profiles(
    State(state): State<ApiState>,
) -> Result<Json<Vec<RealtimeProfileView>>, ApiError> {
    let profiles = state
        .application
        .execute("realtime.list_profiles", move |services| {
            services.realtime_conversations().list_profiles()
        })
        .await?;
    Ok(Json(
        profiles.iter().map(RealtimeProfileView::from).collect(),
    ))
}

pub(crate) async fn register_profile(
    State(state): State<ApiState>,
    Json(request): Json<RegisterRealtimeProfileRequest>,
) -> Result<Json<RealtimeProfileView>, ApiError> {
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
        auth_ref: None,
        timeout_ms: request.timeout_ms,
        created_at_ms: application::now_ms(),
    };
    let secret = request.secret.filter(|value| !value.trim().is_empty());
    let secret_store = state.infrastructure.secret_store.clone();
    let saved = state
        .application
        .execute("realtime.register_profile", move |services| {
            services.realtime_conversations().register_profile(
                profile,
                secret.as_deref(),
                secret_store.as_ref(),
            )
        })
        .await?;
    Ok(Json(RealtimeProfileView::from(&saved)))
}

pub(crate) async fn delete_profile(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<axum::http::StatusCode, ApiError> {
    let id = RealtimeProviderProfileId::parse(id).map_err(ApplicationError::from)?;
    let secret_store = state.infrastructure.secret_store.clone();
    state
        .application
        .execute("realtime.delete_profile", move |services| {
            services
                .realtime_conversations()
                .delete_profile(&id, secret_store.as_ref())
        })
        .await?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}

pub(crate) async fn save_session(
    State(state): State<ApiState>,
    Json(session): Json<RealtimeConversationSession>,
) -> Result<Json<RealtimeConversationSession>, ApiError> {
    state
        .application
        .execute("realtime.save_session", move |services| {
            services.realtime_conversations().save_session(session)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn list_sessions(
    State(state): State<ApiState>,
) -> Result<Json<Vec<RealtimeConversationSession>>, ApiError> {
    state
        .application
        .execute("realtime.list_sessions", move |services| {
            services.realtime_conversations().sessions()
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn list_turns(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<RealtimeConversationTurn>>, ApiError> {
    let id = domain::RealtimeConversationSessionId::parse(id).map_err(ApplicationError::from)?;
    state
        .application
        .execute("realtime.list_turns", move |services| {
            services.realtime_conversations().turns(&id)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn save_turn(
    State(state): State<ApiState>,
    Json(turn): Json<RealtimeConversationTurn>,
) -> Result<Json<RealtimeConversationTurn>, ApiError> {
    state
        .application
        .execute("realtime.save_turn", move |services| {
            services
                .production_corpus()
                .record_realtime_turn_and_index(turn)
        })
        .await
        .map(Json)
        .map_err(ApiError::from)
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
    let language = LanguageCode::parse(query.language).map_err(ApplicationError::from)?;
    let secret_store = state.infrastructure.secret_store.clone();
    let factory = state.generative.realtime_adapter_factory.clone();
    let options = RealtimeConnectionOptions {
        language,
        instructions: query.instructions,
        manual_turns: query.manual_turns,
    };
    let prepared = state
        .application
        .execute("realtime.connect_profile", move |services| {
            services.realtime_conversations().prepare_connection(
                &id,
                options,
                secret_store.as_ref(),
                factory.as_ref(),
            )
        })
        .await?;
    Ok(ws.on_upgrade(move |socket| run_socket(socket, prepared)))
}

async fn run_socket(socket: WebSocket, prepared: PreparedRealtimeConnection) {
    let (mut client_tx, mut client_rx) = socket.split();
    let mut provider = match prepared.connect().await {
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
                Some(Ok(Message::Binary(bytes))) => {
                    if provider.send_audio(&bytes).await.is_err() { break; }
                },
                Some(Ok(Message::Text(command))) if command == "commit" => { if provider.commit_turn().await.is_err() { break; } },
                Some(Ok(Message::Text(command))) if command == "cancel" => { let _ = provider.cancel_response().await; },
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                _ => {}
            },
            event = provider.next_event() => match event {
                Ok(Some(RealtimeEvent::AssistantAudioDelta { pcm16_mono_24khz, .. })) => {
                    if client_tx.send(Message::Binary(pcm16_mono_24khz.into())).await.is_err() { break; }
                },
                Ok(Some(event)) => {
                    if client_tx.send(Message::Text(serde_json::to_string(&event).unwrap_or_else(|_| "{\"type\":\"protocol_error\"}".into()).into())).await.is_err() { break; }
                },
                Ok(None) => break,
                Err(error) => { let _ = client_tx.send(Message::Text(serde_json::json!({"type":"provider_error","error":error}).to_string().into())).await; break; }
            }
        }
    }
    let _ = provider.close().await;
}
