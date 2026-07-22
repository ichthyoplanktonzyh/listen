use std::time::Duration;

use application::{
    RealtimeAudioFormat, RealtimeConversationAdapter, RealtimeConversationSession, RealtimeEvent,
    RealtimeProviderCapabilities, RealtimeProviderDescriptor, RealtimeSessionRequest,
    RealtimeTransportKind,
};
use async_trait::async_trait;
use domain::RealtimeProviderError;
use futures_util::{
    SinkExt, StreamExt,
    stream::{SplitSink, SplitStream},
};
use http::{HeaderValue, Request};
use tokio::net::TcpStream;
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{Message, client::IntoClientRequest},
};
use url::Url;

use crate::{OpenAiRealtimeCodec, QwenRealtimeCodec, RealtimeProtocolCodec};

#[derive(Debug, Clone)]
pub struct RealtimeAdapterConfig {
    pub base_url: String,
    pub model_id: String,
    pub credential: String,
    pub timeout: Duration,
}

type Wire = WebSocketStream<MaybeTlsStream<TcpStream>>;

struct WireSession<C> {
    codec: C,
    sink: SplitSink<Wire, Message>,
    stream: SplitStream<Wire>,
}

impl<C: RealtimeProtocolCodec> WireSession<C> {
    async fn send_json(&mut self, value: serde_json::Value) -> Result<(), RealtimeProviderError> {
        self.sink
            .send(Message::Text(value.to_string().into()))
            .await
            .map_err(|_| RealtimeProviderError::Disconnected)
    }
}

#[async_trait]
impl<C: RealtimeProtocolCodec> RealtimeConversationSession for WireSession<C> {
    async fn send_audio(&mut self, pcm: &[u8]) -> Result<(), RealtimeProviderError> {
        self.send_json(self.codec.audio_append(pcm)).await
    }
    async fn commit_turn(&mut self) -> Result<(), RealtimeProviderError> {
        self.send_json(self.codec.commit_turn()).await
    }
    async fn cancel_response(&mut self) -> Result<(), RealtimeProviderError> {
        self.send_json(self.codec.cancel_response()).await
    }
    async fn next_event(&mut self) -> Result<Option<RealtimeEvent>, RealtimeProviderError> {
        loop {
            match self.stream.next().await {
                Some(Ok(Message::Text(text))) => {
                    let value = serde_json::from_str(&text).map_err(|_| {
                        RealtimeProviderError::Protocol {
                            detail: "provider sent invalid JSON".into(),
                        }
                    })?;
                    if let Some(event) = self.codec.decode(&value)? {
                        return Ok(Some(event));
                    }
                }
                Some(Ok(Message::Close(Some(frame)))) => {
                    return Err(RealtimeProviderError::Protocol {
                        detail: format!(
                            "provider closed WebSocket: code={} reason={}",
                            u16::from(frame.code),
                            frame.reason
                        ),
                    });
                }
                Some(Ok(Message::Close(None))) | None => {
                    return Err(RealtimeProviderError::Disconnected);
                }
                Some(Ok(Message::Ping(payload))) => {
                    self.sink
                        .send(Message::Pong(payload))
                        .await
                        .map_err(|_| RealtimeProviderError::Disconnected)?;
                }
                Some(Ok(_)) => {}
                Some(Err(_)) => return Err(RealtimeProviderError::Disconnected),
            }
        }
    }
    async fn close(&mut self) -> Result<(), RealtimeProviderError> {
        self.sink
            .close()
            .await
            .map_err(|_| RealtimeProviderError::Disconnected)
    }
}

async fn connect<C: RealtimeProtocolCodec>(
    codec: C,
    config: &RealtimeAdapterConfig,
    request: &RealtimeSessionRequest,
) -> Result<Box<dyn RealtimeConversationSession>, RealtimeProviderError> {
    if config.credential.trim().is_empty() {
        return Err(RealtimeProviderError::Auth);
    }
    if config.model_id.trim().is_empty() {
        return Err(RealtimeProviderError::UnsupportedCapability {
            capability: "realtime model".into(),
        });
    }
    let mut url = Url::parse(&config.base_url).map_err(|_| RealtimeProviderError::Protocol {
        detail: "invalid provider WebSocket URL".into(),
    })?;
    if !matches!(url.scheme(), "ws" | "wss") {
        return Err(RealtimeProviderError::Protocol {
            detail: "provider URL must use ws or wss".into(),
        });
    }
    url.query_pairs_mut().append_pair("model", &config.model_id);
    let mut handshake: Request<()> =
        url.as_str()
            .into_client_request()
            .map_err(|_| RealtimeProviderError::Protocol {
                detail: "invalid provider WebSocket URL".into(),
            })?;
    let auth = HeaderValue::from_str(&format!("Bearer {}", config.credential))
        .map_err(|_| RealtimeProviderError::Auth)?;
    handshake.headers_mut().insert("authorization", auth);
    let (wire, _) = tokio::time::timeout(config.timeout, connect_async(handshake))
        .await
        .map_err(|_| RealtimeProviderError::Timeout)?
        .map_err(|error| match error {
            tokio_tungstenite::tungstenite::Error::Http(response)
                if response.status() == http::StatusCode::UNAUTHORIZED
                    || response.status() == http::StatusCode::FORBIDDEN =>
            {
                RealtimeProviderError::Auth
            }
            tokio_tungstenite::tungstenite::Error::Http(response)
                if response.status() == http::StatusCode::TOO_MANY_REQUESTS =>
            {
                RealtimeProviderError::RateLimit {
                    retry_after_ms: None,
                }
            }
            _ => RealtimeProviderError::Offline,
        })?;
    let (sink, stream) = wire.split();
    let session_update = codec.session_update(request);
    let mut session = WireSession {
        codec,
        sink,
        stream,
    };
    session.send_json(session_update).await?;
    Ok(Box::new(session))
}

macro_rules! adapter {
    ($name:ident, $codec:ty, $kind:literal, $input_audio:expr) => {
        pub struct $name {
            config: RealtimeAdapterConfig,
        }
        impl $name {
            pub fn new(config: RealtimeAdapterConfig) -> Self {
                Self { config }
            }
        }
        #[async_trait]
        impl RealtimeConversationAdapter for $name {
            fn descriptor(&self) -> RealtimeProviderDescriptor {
                let codec = <$codec>::default();
                RealtimeProviderDescriptor {
                    adapter_kind: $kind.into(),
                    model_id: self.config.model_id.clone(),
                    protocol_version: codec.protocol_version().into(),
                    capabilities: RealtimeProviderCapabilities {
                        transport: RealtimeTransportKind::WebSocket,
                        input_audio: $input_audio,
                        output_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
                        supports_server_vad: true,
                        supports_manual_turns: true,
                        supports_provider_input_transcript: true,
                        supports_assistant_transcript: true,
                        supports_response_cancel: true,
                        supports_output_audio_clear: false,
                        supports_conversation_truncate: false,
                        supports_function_calls: false,
                        supports_image_input: false,
                        supports_session_resume: false,
                    },
                }
            }
            async fn connect(
                &self,
                request: &RealtimeSessionRequest,
            ) -> Result<Box<dyn RealtimeConversationSession>, RealtimeProviderError> {
                connect(<$codec>::default(), &self.config, request).await
            }
        }
    };
}

adapter!(
    OpenAiRealtimeAdapter,
    OpenAiRealtimeCodec,
    "openai_realtime",
    RealtimeAudioFormat::Pcm16Mono24Khz
);
adapter!(
    QwenRealtimeAdapter,
    QwenRealtimeCodec,
    "qwen_omni_realtime",
    RealtimeAudioFormat::Pcm16Mono16Khz
);
