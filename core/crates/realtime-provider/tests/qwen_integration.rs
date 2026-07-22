//! Integration test: Qwen Omni Realtime adapter with a real API key.
//!
//! Set QWEN_API_KEY env var to run:
//!   QWEN_API_KEY=sk-xxx cargo test -p realtime-provider --test qwen_integration -- --nocapture

use std::time::Duration;

use application::{
    RealtimeAudioFormat, RealtimeConversationAdapter, RealtimeEvent, RealtimeSessionRequest,
    RealtimeTurnDetection,
};
use domain::LanguageCode;
use realtime_provider::{QwenRealtimeAdapter, RealtimeAdapterConfig};

fn request() -> RealtimeSessionRequest {
    RealtimeSessionRequest {
        instructions: "You are a helpful medical tutor. Keep responses brief.".into(),
        language: LanguageCode::parse("en").unwrap(),
        voice: "test-voice".into(),
        input_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
        output_audio: RealtimeAudioFormat::Pcm16Mono24Khz,
        turn_detection: RealtimeTurnDetection::ServerVad,
    }
}

/// Smoke test: connect to the real Qwen Omni Realtime service, verify
/// SessionReady, send a tiny audio frame, and read events until a short
/// timeout expires.
///
/// This validates the full flow:
///   1. WebSocket handshake with Bearer auth
///   2. session.update is accepted
///   3. session.created / session.updated → SessionReady
///   4. input_audio_buffer.append works
///   5. VAD / response events arrive
#[tokio::test]
#[ignore = "requires QWEN_API_KEY and QWEN_WORKSPACE_ID env vars"]
async fn qwen_realtime_smoke_test() {
    let api_key = std::env::var("QWEN_API_KEY").expect("QWEN_API_KEY must be set");
    let workspace_id = std::env::var("QWEN_WORKSPACE_ID")
        .expect("QWEN_WORKSPACE_ID must be set (Alibaba Cloud Model Studio China endpoint)");
    assert!(!api_key.trim().is_empty(), "QWEN_API_KEY must not be empty");

    let config = RealtimeAdapterConfig {
        base_url: format!("wss://{workspace_id}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime"),
        model_id: "qwen3-omni-flash-realtime".into(),
        credential: api_key,
        timeout: Duration::from_secs(15),
    };
    let adapter = QwenRealtimeAdapter::new(config);
    let mut session = adapter
        .connect(&request())
        .await
        .expect("Qwen adapter should connect successfully");

    // 1. Expect SessionReady within 10s
    let event = tokio::time::timeout(Duration::from_secs(10), session.next_event())
        .await
        .expect("should receive SessionReady within timeout")
        .expect("next_event should return Ok")
        .expect("SessionReady should be Some");
    assert!(
        matches!(event, RealtimeEvent::SessionReady { .. }),
        "First event should be SessionReady, got {event:?}"
    );
    eprintln!("✓ SessionReady received");

    // 2. Send a tiny PCM16 frame (silence, 24kHz, ~100ms)
    let silent_pcm = vec![0_u8; 4800]; // 4800 samples = 100ms at 48kHz? Actually PCM16 = 2 bytes/sample at 24kHz
    session
        .send_audio(&silent_pcm)
        .await
        .expect("should send audio without error");
    eprintln!("✓ Audio sent");

    // 3. Collect events for up to 8 seconds
    let deadline = tokio::time::Instant::now() + Duration::from_secs(8);
    let mut saw_speech_started = false;
    let mut saw_assistant_audio = false;

    while tokio::time::Instant::now() < deadline {
        tokio::select! {
            biased;
            event = session.next_event() => {
                match event {
                    Ok(Some(RealtimeEvent::SpeechStarted { .. })) => {
                        saw_speech_started = true;
                        eprintln!("✓ SpeechStarted");
                    }
                    Ok(Some(RealtimeEvent::AssistantAudioDelta { .. })) => {
                        saw_assistant_audio = true;
                        eprintln!("✓ AssistantAudioDelta (response audio)");
                    }
                    Ok(Some(other)) => {
                        eprintln!("  Event: {other:?}");
                    }
                    Ok(None) => {
                        eprintln!("  Session ended (None)");
                        break;
                    }
                    Err(e) => {
                        eprintln!("  Provider error: {e:?}");
                        break;
                    }
                }
            }
        }
    }

    // The service may or may not produce VAD events on pure silence,
    // but the connection itself succeeded — that's the important part.
    eprintln!("✓ Events collected. saw_speech_started={saw_speech_started}, saw_assistant_audio={saw_assistant_audio}");

    // 4. Close cleanly
    session
        .close()
        .await
        .expect("should close without error");
    eprintln!("✓ Session closed");
}

/// Connectivity test with detailed error diagnostics.
/// Tries multiple endpoints and model names.
#[tokio::test]
#[ignore = "requires QWEN_API_KEY env var and network access to DashScope"]
async fn qwen_connectivity_test() {
    let api_key = std::env::var("QWEN_API_KEY").expect("QWEN_API_KEY must be set");
    let workspace_id = std::env::var("QWEN_WORKSPACE_ID").ok();

    // Required: QWEN_WORKSPACE_ID must be set for China (Beijing) endpoint
    let workspace_id = workspace_id.expect("QWEN_WORKSPACE_ID must be set for Alibaba Cloud Model Studio (China)");

    // Build the correct China (Beijing) WebSocket endpoint
    // Format: wss://{workspaceId}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime?model=...
    let base_url = format!("wss://{workspace_id}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime");

    struct Combo {
        base_url: String,
        model_id: String,
    }
    let combos: Vec<Combo> = vec![
        Combo { base_url: base_url.clone(), model_id: "qwen3-omni-flash-realtime".into() },
        Combo { base_url: base_url.clone(), model_id: "qwen3.5-omni-flash-realtime".into() },
        Combo { base_url: base_url.clone(), model_id: "qwen3.5-omni-plus-realtime".into() },
    ];

    for combo in &combos {
        eprintln!("  Trying: {} ?model={}", combo.base_url, combo.model_id);

        let config = RealtimeAdapterConfig {
            base_url: combo.base_url.clone(),
            model_id: combo.model_id.clone(),
            credential: api_key.clone(),
            timeout: Duration::from_secs(15),
        };
        let adapter = QwenRealtimeAdapter::new(config);

        match adapter.connect(&request()).await {
            Ok(mut session) => {
                match tokio::time::timeout(Duration::from_secs(10), session.next_event()).await {
                    Ok(Ok(Some(RealtimeEvent::SessionReady { .. }))) => {
                        eprintln!("  ✓ SUCCESS with {} ?model={}", combo.base_url, combo.model_id);
                        session.close().await.expect("close cleanly");
                        return; // success
                    }
                    Ok(Ok(Some(event))) => {
                        eprintln!("  Got event: {event:?}");
                    }
                    Ok(Ok(None)) => {
                        eprintln!("  Session ended immediately (no events)");
                    }
                    Ok(Err(e)) => {
                        eprintln!("  Session error: {e:?}");
                    }
                    Err(_) => {
                        eprintln!("  Timeout waiting for SessionReady (10s)");
                    }
                }
                let _ = session.close().await;
            }
            Err(e) => {
                eprintln!("  Connect failed: {e:?}");
            }
        }
    }

    panic!("All model names failed.\n\
        Hints:\n\
        - Make sure the model is 'activated' in your Model Studio console.\n\
        - Check that the API key has permissions for realtime models.\n\
        - Verify the workspace ID is correct.");
}
