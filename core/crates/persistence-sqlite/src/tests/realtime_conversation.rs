use std::sync::Arc;

use application::{AppServices, InMemorySecretStore};
use domain::*;

use super::*;

fn services(repo: &Arc<SqliteRepository>) -> AppServices {
    AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_semantic_task_repository(repo.clone())
    .with_realtime_conversation_repository(repo.clone())
    .with_production_corpus_repository(repo.clone())
}

#[test]
fn only_local_finalized_learner_turn_projects_into_spoken_corpus() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let store = InMemorySecretStore::new();
    let services = services(&repo);
    let profile = services
        .realtime_conversations()
        .register_profile(profile(), "secret", &store)
        .unwrap();
    let session = RealtimeConversationSession {
        id: RealtimeConversationSessionId::parse("session-spoken").unwrap(),
        profile_id: profile.id,
        language: LanguageCode::parse("en").unwrap(),
        context: None,
        status: RealtimeSessionStatus::Active,
        started_at_ms: 10,
        ended_at_ms: None,
        failure_kind: None,
    };
    services
        .realtime_conversations()
        .save_session(session.clone())
        .unwrap();
    repo.connection.lock().execute(
        "INSERT INTO recording_assets (id,language,file_path,duration_ms,created_at_ms,asset_json) VALUES ('recording-spoken','en','/tmp/spoken.wav',1000,10,'{}')",
        [],
    ).unwrap();
    let recording_id = RecordingAssetId::parse("recording-spoken").unwrap();
    let mut turn = RealtimeConversationTurn {
        id: RealtimeConversationTurnId::parse("learner-spoken").unwrap(),
        session_id: session.id.clone(),
        sequence: 1,
        role: RealtimeTurnRole::Learner,
        status: RealtimeTurnStatus::Streaming,
        assistance: ProductionAssistance::ContentAnchored,
        provider_transcript: Some(ProviderTranscript {
            text: "provider guess".into(),
            provider_item_id: None,
            received_at_ms: 20,
        }),
        local_transcript: None,
        recording_asset_id: None,
        started_at_ms: 11,
        ended_at_ms: None,
        failure_kind: None,
    };
    turn.await_local_transcript(recording_id.clone(), 30)
        .unwrap();
    turn.finalize_local(LocalLearnerTranscript {
        text: "Locally verified learner words".into(),
        recording_asset_id: recording_id,
        transcription_job_id: RecordingTranscriptionJobId::parse("local-job").unwrap(),
        completed_at_ms: 40,
    })
    .unwrap();
    services
        .production_corpus()
        .record_realtime_turn_and_index(turn)
        .unwrap();
    let mut assistant = RealtimeConversationTurn {
        id: RealtimeConversationTurnId::parse("assistant-spoken").unwrap(),
        session_id: session.id.clone(),
        sequence: 2,
        role: RealtimeTurnRole::Assistant,
        status: RealtimeTurnStatus::Streaming,
        assistance: ProductionAssistance::Unknown,
        provider_transcript: Some(ProviderTranscript {
            text: "Assistant words must stay out".into(),
            provider_item_id: Some("provider-assistant".into()),
            received_at_ms: 41,
        }),
        local_transcript: None,
        recording_asset_id: None,
        started_at_ms: 41,
        ended_at_ms: None,
        failure_kind: None,
    };
    assistant.finalize_assistant(42).unwrap();
    services
        .production_corpus()
        .record_realtime_turn_and_index(assistant)
        .unwrap();
    assert_eq!(
        services
            .production_corpus()
            .rebuild_production_corpus()
            .unwrap(),
        0
    );
    let summary = services
        .production_corpus()
        .production_gap_review("en", ProductionChannel::Spoken, 10)
        .unwrap();
    assert_eq!(summary.document_count, 1);
    let stored: (String, Option<String>) = repo.connection.lock().query_row(
        "SELECT response_text,attempt_id FROM production_corpus_documents WHERE realtime_turn_id='learner-spoken'",
        [], |row| Ok((row.get(0)?, row.get(1)?)),
    ).unwrap();
    assert_eq!(stored.0, "Locally verified learner words");
    assert_eq!(stored.1, None);
    let observations: u32 = repo
        .connection
        .lock()
        .query_row("SELECT COUNT(*) FROM learning_observations", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(observations, 0);
}

fn profile() -> RealtimeProviderProfile {
    RealtimeProviderProfile {
        id: realtime_provider_profile_id(
            RealtimeAdapterKind::OpenAiRealtime,
            "wss://api.example/realtime",
            "realtime-model",
        ),
        display_name: "Realtime".into(),
        adapter_kind: RealtimeAdapterKind::OpenAiRealtime,
        base_url: "wss://api.example/realtime".into(),
        model_id: "realtime-model".into(),
        voice: "voice".into(),
        auth_ref: SecretRef::new("pending"),
        timeout_ms: 30_000,
        created_at_ms: 1,
    }
}

#[test]
fn credential_never_enters_realtime_profile_storage() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let store = InMemorySecretStore::new();
    let secret = "realtime-secret-must-not-persist";
    let saved = services(&repo)
        .realtime_conversations()
        .register_profile(profile(), secret, &store)
        .unwrap();
    let row: String = repo
        .connection
        .lock()
        .query_row(
            "SELECT auth_ref || profile_json FROM realtime_provider_profiles WHERE id=?1",
            [saved.id.as_str()],
            |row| row.get(0),
        )
        .unwrap();
    assert!(!row.contains(secret));
    assert!(row.contains(saved.auth_ref.as_str()));
}

#[test]
fn terminal_turn_is_immutable_and_content_anchor_is_optional() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let store = InMemorySecretStore::new();
    let api = services(&repo).realtime_conversations();
    let saved_profile = api.register_profile(profile(), "secret", &store).unwrap();
    let session = RealtimeConversationSession {
        id: RealtimeConversationSessionId::parse("session-open-chat").unwrap(),
        profile_id: saved_profile.id,
        language: LanguageCode::parse("en").unwrap(),
        context: None,
        status: RealtimeSessionStatus::Active,
        started_at_ms: 10,
        ended_at_ms: None,
        failure_kind: None,
    };
    api.save_session(session.clone()).unwrap();
    let mut turn = RealtimeConversationTurn {
        id: RealtimeConversationTurnId::parse("assistant-turn").unwrap(),
        session_id: session.id,
        sequence: 1,
        role: RealtimeTurnRole::Assistant,
        status: RealtimeTurnStatus::Streaming,
        assistance: ProductionAssistance::Unknown,
        provider_transcript: None,
        local_transcript: None,
        recording_asset_id: None,
        started_at_ms: 11,
        ended_at_ms: None,
        failure_kind: None,
    };
    turn.finalize_assistant(20).unwrap();
    api.save_turn(turn.clone()).unwrap();
    turn.failure_kind = Some("rewrite".into());
    assert!(api.save_turn(turn).is_err());
}
