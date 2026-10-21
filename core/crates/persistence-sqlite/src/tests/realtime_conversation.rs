use super::*;
use application::RealtimeConversationRepository;

fn profile() -> RealtimeProviderProfile {
    let adapter_kind = RealtimeAdapterKind::OpenAiRealtime;
    let base_url = "wss://api.openai.com/v1/realtime";
    let model_id = "gpt-realtime-test";
    RealtimeProviderProfile {
        id: realtime_provider_profile_id(adapter_kind, base_url, model_id),
        display_name: "Test voice".into(),
        adapter_kind,
        base_url: base_url.into(),
        model_id: model_id.into(),
        voice: "alloy".into(),
        auth_ref: None,
        timeout_ms: 30_000,
        created_at_ms: 10,
    }
}

#[test]
fn profile_session_and_turn_round_trip_in_fresh_ai_schema() {
    let repository = SqliteRepository::in_memory().unwrap();
    let profile = repository.upsert_realtime_profile(&profile()).unwrap();
    let session = RealtimeConversationSession {
        id: RealtimeConversationSessionId::parse("session-1").unwrap(),
        profile_id: profile.id.clone(),
        language: LanguageCode::parse("en").unwrap(),
        context: Some(RealtimeSurfaceContext {
            surface_kind: "material_conversation".into(),
            content_anchor: Some(RealtimeContentAnchor {
                media_id: MediaId::parse("media-1").unwrap(),
                start_ms: 1_000,
                end_ms: 2_000,
                source_text: "A listening source line.".into(),
            }),
        }),
        status: RealtimeSessionStatus::Active,
        started_at_ms: 20,
        ended_at_ms: None,
        failure_kind: None,
    };
    repository.save_realtime_session(&session).unwrap();

    let turn = RealtimeConversationTurn {
        id: RealtimeConversationTurnId::parse("assistant-1").unwrap(),
        session_id: session.id.clone(),
        sequence: 1,
        role: RealtimeTurnRole::Assistant,
        status: RealtimeTurnStatus::Streaming,
        assistance: RealtimeConversationAssistance::Unknown,
        provider_transcript: None,
        local_transcript: None,
        recording_asset_id: None,
        started_at_ms: 25,
        ended_at_ms: None,
        failure_kind: None,
    };
    repository.save_realtime_turn(&turn).unwrap();

    assert_eq!(
        repository.get_realtime_profile(&profile.id).unwrap(),
        Some(profile)
    );
    assert_eq!(
        repository.get_realtime_session(&session.id).unwrap(),
        Some(session.clone())
    );
    assert_eq!(
        repository.list_realtime_turns(&session.id).unwrap(),
        vec![turn]
    );
}
