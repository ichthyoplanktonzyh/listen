//! Real-provider baseline gate for GPT-Realtime-2.1.
//!
//! Run explicitly with:
//! `OPENAI_API_KEY=... cargo test -p realtime-provider --test openai_integration -- --ignored --nocapture`

use std::time::Duration;

use application::{
    RealtimeAudioFormat, RealtimeConversationAdapter, RealtimeEvent, RealtimeSessionRequest,
    RealtimeTurnDetection,
};
use domain::LanguageCode;
use realtime_provider::{OpenAiRealtimeAdapter, RealtimeAdapterConfig};

fn request() -> RealtimeSessionRequest {
    RealtimeSessionRequest {
        instructions: "You are a concise English conversation partner.".into(),
        language: LanguageCode::parse("en").unwrap(),
        voice: "marin".into(),
        input_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
        output_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
        turn_detection: RealtimeTurnDetection::ServerVad,
    }
}

#[tokio::test]
#[ignore = "requires OPENAI_API_KEY, model access, and network access"]
async fn gpt_realtime_2_1_accepts_the_baseline_session_contract() {
    let credential = std::env::var("OPENAI_API_KEY").expect("OPENAI_API_KEY must be set");
    let adapter = OpenAiRealtimeAdapter::new(RealtimeAdapterConfig {
        base_url: "wss://api.openai.com/v1/realtime".into(),
        model_id: "gpt-realtime-2.1".into(),
        credential,
        timeout: Duration::from_secs(15),
    });
    let descriptor = adapter.descriptor();
    assert_eq!(descriptor.model_id, "gpt-realtime-2.1");

    let mut session = adapter
        .connect(&request())
        .await
        .expect("GPT-Realtime-2.1 WebSocket handshake should succeed");

    // OpenAI emits session.created for the handshake and session.updated only
    // after validating our GA session.update payload. Both normalize to the
    // provider-neutral SessionReady event, so require two acknowledgements.
    for acknowledgement in ["session.created", "session.updated"] {
        let event = tokio::time::timeout(Duration::from_secs(10), session.next_event())
            .await
            .unwrap_or_else(|_| panic!("timed out waiting for {acknowledgement}"))
            .unwrap_or_else(|error| panic!("provider rejected baseline contract: {error}"))
            .unwrap_or_else(|| panic!("provider closed before {acknowledgement}"));
        assert!(
            matches!(event, RealtimeEvent::SessionReady { .. }),
            "expected {acknowledgement}, got {event:?}"
        );
    }

    session.close().await.expect("session should close cleanly");
}
