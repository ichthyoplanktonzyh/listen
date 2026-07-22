use application::{
    RealtimeAudioFormat, RealtimeConversationAdapter, RealtimeEvent, RealtimeSessionRequest,
    RealtimeTransportKind, RealtimeTurnDetection,
};
use domain::LanguageCode;
use futures_util::{SinkExt, StreamExt};
use realtime_provider::{
    OpenAiRealtimeAdapter, OpenAiRealtimeCodec, QwenRealtimeAdapter, QwenRealtimeCodec,
    RealtimeAdapterConfig, RealtimeProtocolCodec,
};
use std::time::Duration;
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::protocol::{CloseFrame, frame::coding::CloseCode};
use tokio_tungstenite::{accept_async, tungstenite::Message};

fn request() -> RealtimeSessionRequest {
    RealtimeSessionRequest {
        instructions: "Discuss the source, do not recite it.".into(),
        language: LanguageCode::parse("en").unwrap(),
        voice: "test-voice".into(),
        input_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
        output_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
        turn_detection: RealtimeTurnDetection::ServerVad,
    }
}

fn qwen_request() -> RealtimeSessionRequest {
    RealtimeSessionRequest {
        input_audio: RealtimeAudioFormat::Pcm16Mono16Khz,
        ..request()
    }
}

#[test]
fn descriptors_report_implemented_capabilities_instead_of_vendor_promises() {
    for adapter in adapters() {
        let descriptor = adapter.descriptor();
        let capabilities = descriptor.capabilities;
        assert_eq!(capabilities.transport, RealtimeTransportKind::WebSocket);
        assert_eq!(
            capabilities.input_audio,
            match descriptor.adapter_kind.as_str() {
                "qwen_omni_realtime" => RealtimeAudioFormat::Pcm16Mono16Khz,
                _ => RealtimeAudioFormat::Pcm16Mono24Khz,
            }
        );
        assert_eq!(
            capabilities.output_audio,
            RealtimeAudioFormat::Pcm16Mono24Khz
        );
        assert!(capabilities.supports_server_vad);
        assert!(capabilities.supports_manual_turns);
        assert!(capabilities.supports_provider_input_transcript);
        assert!(capabilities.supports_assistant_transcript);
        assert!(capabilities.supports_response_cancel);
        assert!(!capabilities.supports_output_audio_clear);
        assert!(!capabilities.supports_conversation_truncate);
        assert!(!capabilities.supports_function_calls);
        assert!(!capabilities.supports_image_input);
        assert!(!capabilities.supports_session_resume);
    }
}

#[test]
fn both_protocols_encode_the_same_neutral_audio_contract() {
    let pcm = [0_u8, 1, 2, 3];
    for (codec, request) in [
        (
            Box::new(OpenAiRealtimeCodec::default()) as Box<dyn RealtimeProtocolCodec>,
            request(),
        ),
        (
            Box::new(QwenRealtimeCodec) as Box<dyn RealtimeProtocolCodec>,
            qwen_request(),
        ),
    ] {
        let session = codec.session_update(&request);
        assert_eq!(session["type"], "session.update");
        let append = codec.audio_append(&pcm);
        assert_eq!(append["type"], "input_audio_buffer.append");
        assert_eq!(append["audio"], "AAECAw==");
    }
}

#[test]
fn qwen_baseline_uses_the_current_full_duplex_audio_session_shape() {
    let session = QwenRealtimeCodec.session_update(&qwen_request());
    assert_eq!(session["session"]["input_audio_format"], "pcm");
    assert_eq!(session["session"]["output_audio_format"], "pcm");
    assert_eq!(session["session"]["voice"], "test-voice");
    assert_eq!(
        session["session"]["turn_detection"],
        serde_json::json!({
            "type": "semantic_vad",
            "threshold": 0.2,
            "silence_duration_ms": 800,
        })
    );
    assert!(
        session["session"]
            .get("input_audio_transcription")
            .is_none()
    );
}

#[test]
fn openai_baseline_uses_the_current_ga_audio_session_shape() {
    let session = OpenAiRealtimeCodec::default().session_update(&request());
    assert_eq!(session["session"]["type"], "realtime");
    assert_eq!(
        session["session"]["output_modalities"],
        serde_json::json!(["audio"])
    );
    assert_eq!(
        session["session"]["audio"]["input"]["format"],
        serde_json::json!({"type": "audio/pcm", "rate": 24000})
    );
    assert_eq!(
        session["session"]["audio"]["output"]["format"],
        serde_json::json!({"type": "audio/pcm", "rate": 24000})
    );
    assert_eq!(
        session["session"]["audio"]["input"]["transcription"],
        serde_json::json!({
            "model": "gpt-4o-mini-transcribe",
            "language": "en",
        })
    );
}

#[test]
fn heterogeneous_transcript_events_map_to_the_same_preview_fact() {
    let openai_codec = OpenAiRealtimeCodec::default();
    let openai = openai_codec
        .decode(&serde_json::json!({
            "type": "conversation.item.input_audio_transcription.delta",
            "item_id": "o1", "delta": "hel"
        }))
        .unwrap()
        .unwrap();
    assert!(
        matches!(openai, RealtimeEvent::ProviderTranscriptPreview { text, .. } if text == "hel")
    );
    let openai = openai_codec
        .decode(&serde_json::json!({
            "type": "conversation.item.input_audio_transcription.delta",
            "item_id": "o1", "delta": "lo"
        }))
        .unwrap()
        .unwrap();
    let qwen = QwenRealtimeCodec
        .decode(&serde_json::json!({
            "type": "conversation.item.input_audio_transcription.delta",
            "item_id": "q1", "text": "hel", "stash": "lo"
        }))
        .unwrap()
        .unwrap();
    assert!(
        matches!(openai, RealtimeEvent::ProviderTranscriptPreview { text, .. } if text == "hello")
    );
    assert!(
        matches!(qwen, RealtimeEvent::ProviderTranscriptPreview { text, .. } if text == "hello")
    );
}

#[test]
fn provider_transcripts_are_never_local_authority_events() {
    for codec in codecs() {
        let event = codec
            .decode(&serde_json::json!({
                "type": "conversation.item.input_audio_transcription.completed",
                "item_id": "i", "transcript": "provider words"
            }))
            .unwrap()
            .unwrap();
        assert!(matches!(
            event,
            RealtimeEvent::ProviderTranscriptFinal { .. }
        ));
    }
}

#[test]
fn assistant_audio_is_neutral() {
    for codec in codecs() {
        let event = codec
            .decode(&serde_json::json!({
                "type": "response.audio.delta", "item_id": "a", "delta": "AAECAw=="
            }))
            .unwrap()
            .unwrap();
        assert!(
            matches!(event, RealtimeEvent::AssistantAudioDelta { pcm16_mono_24khz, .. } if pcm16_mono_24khz == [0,1,2,3])
        );
    }
}

#[test]
fn vad_commit_response_done_and_client_controls_share_one_contract() {
    for codec in codecs() {
        assert_eq!(codec.commit_turn()["type"], "input_audio_buffer.commit");
        assert_eq!(codec.cancel_response()["type"], "response.cancel");
        assert!(matches!(
            codec
                .decode(&serde_json::json!({
                    "type":"input_audio_buffer.speech_started", "item_id":"learner-1",
                    "audio_start_ms": 3647
                }))
                .unwrap(),
            Some(RealtimeEvent::SpeechStarted {
                audio_start_ms: Some(3647),
                ..
            })
        ));
        assert!(matches!(
            codec
                .decode(&serde_json::json!({
                    "type":"input_audio_buffer.speech_stopped", "item_id":"learner-1"
                }))
                .unwrap(),
            Some(RealtimeEvent::SpeechStopped { .. })
        ));
        assert!(matches!(
            codec
                .decode(&serde_json::json!({
                    "type":"input_audio_buffer.committed", "item_id":"learner-1"
                }))
                .unwrap(),
            Some(RealtimeEvent::TurnCommitted { .. })
        ));
        assert!(matches!(
            codec
                .decode(&serde_json::json!({
                    "type":"response.done", "response":{"id":"response-1"}
                }))
                .unwrap(),
            Some(RealtimeEvent::ResponseDone { .. })
        ));
    }
}

#[test]
fn both_protocols_map_auth_rate_limit_and_protocol_errors_honestly() {
    for codec in codecs() {
        let auth = codec
            .decode(&serde_json::json!({
                "type": "error", "error": {"code": "invalid_api_key"}
            }))
            .unwrap_err();
        assert_eq!(auth, domain::RealtimeProviderError::Auth);

        let limited = codec
            .decode(&serde_json::json!({
                "type": "error", "error": {"code": "rate_limit_exceeded"}
            }))
            .unwrap_err();
        assert_eq!(
            limited,
            domain::RealtimeProviderError::RateLimit {
                retry_after_ms: None
            }
        );

        let protocol = codec
            .decode(&serde_json::json!({
                "type": "error", "error": {"code": "bad_request", "message": "unsupported format"}
            }))
            .unwrap_err();
        assert!(matches!(
            protocol,
            domain::RealtimeProviderError::Protocol { .. }
        ));
    }
}

#[tokio::test]
async fn both_adapters_cross_a_real_websocket_transport_without_leaking_protocol_shapes() {
    for kind in ["openai", "qwen"] {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let mut socket = accept_async(stream).await.unwrap();
            let session_update = text_json(socket.next().await.unwrap().unwrap());
            assert_eq!(session_update["type"], "session.update");
            socket
                .send(Message::Text(
                    serde_json::json!({"type":"session.updated","session":{"id":"s-1"}})
                        .to_string()
                        .into(),
                ))
                .await
                .unwrap();
            let append = text_json(socket.next().await.unwrap().unwrap());
            assert_eq!(append["type"], "input_audio_buffer.append");
            assert_eq!(append["audio"], "AAECAw==");
        });

        let config = RealtimeAdapterConfig {
            base_url: format!("ws://{address}/realtime"),
            model_id: "contract-model".into(),
            credential: "contract-secret".into(),
            timeout: Duration::from_secs(2),
        };
        let adapter: Box<dyn RealtimeConversationAdapter> = match kind {
            "openai" => Box::new(OpenAiRealtimeAdapter::new(config)),
            _ => Box::new(QwenRealtimeAdapter::new(config)),
        };
        let request = if kind == "qwen" {
            qwen_request()
        } else {
            request()
        };
        let mut session = adapter.connect(&request).await.unwrap();
        assert!(matches!(
            session.next_event().await.unwrap(),
            Some(RealtimeEvent::SessionReady { .. })
        ));
        session.send_audio(&[0, 1, 2, 3]).await.unwrap();
        server.await.unwrap();
    }
}

#[tokio::test]
async fn invalid_configuration_degrades_before_opening_a_socket() {
    let base = RealtimeAdapterConfig {
        base_url: "https://not-a-websocket.example/realtime".into(),
        model_id: "model".into(),
        credential: "secret".into(),
        timeout: Duration::from_millis(10),
    };
    let adapter = OpenAiRealtimeAdapter::new(base.clone());
    assert!(matches!(
        adapter.connect(&request()).await,
        Err(domain::RealtimeProviderError::Protocol { .. })
    ));

    let adapter = QwenRealtimeAdapter::new(RealtimeAdapterConfig {
        credential: String::new(),
        base_url: "ws://127.0.0.1:9/realtime".into(),
        ..base
    });
    assert!(matches!(
        adapter.connect(&request()).await,
        Err(domain::RealtimeProviderError::Auth)
    ));
}

#[tokio::test]
async fn provider_close_reason_is_preserved_instead_of_becoming_bare_disconnect() {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move {
        let (stream, _) = listener.accept().await.unwrap();
        let mut socket = accept_async(stream).await.unwrap();
        let _session_update = socket.next().await.unwrap().unwrap();
        socket
            .send(Message::Close(Some(CloseFrame {
                code: CloseCode::Policy,
                reason: "semantic_vad rejected".into(),
            })))
            .await
            .unwrap();
    });
    let adapter = QwenRealtimeAdapter::new(RealtimeAdapterConfig {
        base_url: format!("ws://{address}/realtime"),
        model_id: "contract-model".into(),
        credential: "contract-secret".into(),
        timeout: Duration::from_secs(2),
    });
    let mut session = adapter.connect(&qwen_request()).await.unwrap();

    let error = session.next_event().await.unwrap_err();

    assert!(matches!(
        error,
        domain::RealtimeProviderError::Protocol { detail }
            if detail.contains("1008") && detail.contains("semantic_vad rejected")
    ));
    server.await.unwrap();
}

fn text_json(message: Message) -> serde_json::Value {
    match message {
        Message::Text(text) => serde_json::from_str(&text).unwrap(),
        other => panic!("expected text frame, got {other:?}"),
    }
}

fn codecs() -> Vec<Box<dyn RealtimeProtocolCodec>> {
    vec![
        Box::new(OpenAiRealtimeCodec::default()),
        Box::new(QwenRealtimeCodec),
    ]
}

fn adapters() -> Vec<Box<dyn RealtimeConversationAdapter>> {
    let config = RealtimeAdapterConfig {
        base_url: "wss://example.invalid/realtime".into(),
        model_id: "contract-model".into(),
        credential: "contract-secret".into(),
        timeout: Duration::from_secs(2),
    };
    vec![
        Box::new(OpenAiRealtimeAdapter::new(config.clone())),
        Box::new(QwenRealtimeAdapter::new(config)),
    ]
}
