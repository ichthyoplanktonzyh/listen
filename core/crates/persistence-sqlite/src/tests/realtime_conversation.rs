use std::sync::{Arc, Barrier};
use std::thread;

use application::{
    AppServices, InMemorySecretStore, RealtimeConversationRepository, SecretCleanupRepository,
};
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
fn realtime_profile_delete_enqueues_credential_cleanup_atomically() {
    let repo = SqliteRepository::in_memory().unwrap();
    let stored = profile();
    let auth_ref = stored.auth_ref.clone();
    repo.upsert_realtime_profile(&stored).unwrap();

    repo.delete_realtime_profile_and_schedule_cleanup(&stored.id)
        .unwrap();

    assert!(repo.get_realtime_profile(&stored.id).unwrap().is_none());
    assert_eq!(repo.pending_secret_cleanups().unwrap(), vec![auth_ref]);
}

#[test]
fn concurrent_realtime_rotations_schedule_the_losing_reference() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let old = profile();
    let old_ref = old.auth_ref.clone();
    repo.upsert_realtime_profile(&old).unwrap();
    let first_ref = SecretRef::new("keychain:realtime-a");
    let second_ref = SecretRef::new("keychain:realtime-b");
    repo.reserve_secret_cleanup(&first_ref).unwrap();
    repo.reserve_secret_cleanup(&second_ref).unwrap();
    let barrier = Arc::new(Barrier::new(3));
    let mut workers = Vec::new();
    for auth_ref in [first_ref.clone(), second_ref.clone()] {
        let repo = repo.clone();
        let barrier = barrier.clone();
        let mut replacement = old.clone();
        replacement.auth_ref = auth_ref;
        workers.push(thread::spawn(move || {
            barrier.wait();
            repo.upsert_realtime_profile_and_schedule_cleanup(&replacement)
                .unwrap();
        }));
    }
    barrier.wait();
    for worker in workers {
        worker.join().unwrap();
    }

    let active = repo
        .get_realtime_profile(&old.id)
        .unwrap()
        .unwrap()
        .auth_ref;
    let pending = repo.pending_secret_cleanups().unwrap();
    assert!(pending.contains(&old_ref));
    assert!(pending.contains(if active == first_ref {
        &second_ref
    } else {
        &first_ref
    }));
    assert!(!pending.contains(&active));
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
