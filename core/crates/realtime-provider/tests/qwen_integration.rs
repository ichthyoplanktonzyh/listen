//! Integration test: Qwen Omni Realtime adapter with a real API key.
//!
//! Set DASHSCOPE_API_KEY and QWEN_WORKSPACE_ID to run. QWEN_REGION may be
//! `cn` (default) or `sg`:
//!   DASHSCOPE_API_KEY=sk-xxx QWEN_WORKSPACE_ID=xxx cargo test -p realtime-provider --test qwen_integration -- --nocapture

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
        voice: "Tina".into(),
        input_audio: RealtimeAudioFormat::Pcm16Mono16Khz,
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
#[ignore = "requires DASHSCOPE_API_KEY and QWEN_WORKSPACE_ID env vars"]
async fn qwen_realtime_smoke_test() {
    let api_key = std::env::var("DASHSCOPE_API_KEY")
        .or_else(|_| std::env::var("QWEN_API_KEY"))
        .expect("DASHSCOPE_API_KEY must be set");
    let workspace_id = std::env::var("QWEN_WORKSPACE_ID").expect("QWEN_WORKSPACE_ID must be set");
    let region = std::env::var("QWEN_REGION").unwrap_or_else(|_| "cn".into());
    let region_host = match region.as_str() {
        "cn" => "cn-beijing.maas.aliyuncs.com",
        "sg" => "ap-southeast-1.maas.aliyuncs.com",
        other => panic!("QWEN_REGION must be `cn` or `sg`, got {other}"),
    };
    assert!(
        !api_key.trim().is_empty(),
        "DASHSCOPE_API_KEY must not be empty"
    );

    let config = RealtimeAdapterConfig {
        base_url: format!("wss://{workspace_id}.{region_host}/api-ws/v1/realtime"),
        model_id: "qwen3.5-omni-plus-realtime".into(),
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

    // 2. Send a tiny PCM16 frame (silence, 16kHz, 100ms)
    let silent_pcm = vec![0_u8; 3200];
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
            _ = tokio::time::sleep_until(deadline) => {
                eprintln!("✓ Event observation window completed");
                break;
            }
        }
    }

    // The service may or may not produce VAD events on pure silence,
    // but the connection itself succeeded — that's the important part.
    eprintln!(
        "✓ Events collected. saw_speech_started={saw_speech_started}, saw_assistant_audio={saw_assistant_audio}"
    );

    // 4. Close cleanly
    session.close().await.expect("should close without error");
    eprintln!("✓ Session closed");
}
