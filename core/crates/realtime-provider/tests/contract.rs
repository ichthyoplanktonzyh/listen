use application::{
    RealtimeAudioFormat, RealtimeConversationAdapter, RealtimeEvent, RealtimeSessionRequest,
    RealtimeTurnDetection,
};
use domain::LanguageCode;
use futures_util::{SinkExt, StreamExt};
use realtime_provider::{
    OpenAiRealtimeAdapter, OpenAiRealtimeCodec, QwenRealtimeAdapter, QwenRealtimeCodec,
    RealtimeAdapterConfig, RealtimeProtocolCodec,
};
use std::time::Duration;
use tokio::net::TcpListener;
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

#[test]
fn both_protocols_encode_the_same_neutral_audio_contract() {
    let pcm = [0_u8, 1, 2, 3];
    for codec in codecs() {
        let session = codec.session_update(&request());
        assert_eq!(session["type"], "session.update");
        let append = codec.audio_append(&pcm);
        assert_eq!(append["type"], "input_audio_buffer.append");
        assert_eq!(append["audio"], "AAECAw==");
    }
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
                    "type":"input_audio_buffer.speech_started", "item_id":"learner-1"
                }))
                .unwrap(),
            Some(RealtimeEvent::SpeechStarted { .. })
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
        let mut session = adapter.connect(&request()).await.unwrap();
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
