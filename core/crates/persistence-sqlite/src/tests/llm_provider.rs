use std::sync::Arc;

use application::{InMemorySecretStore, SecretStore};

use super::*;

fn provider_services(repo: &Arc<SqliteRepository>) -> AppServices {
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
    .with_llm_provider_profile_repository(repo.clone())
}

fn sample_profile(auth_ref: Option<LlmAuthRef>) -> LlmProviderProfile {
    LlmProviderProfile {
        id: llm_provider_profile_id(
            LlmAdapterKind::OpenAiChatCompletions,
            "https://api.example.com/v1",
            "model-x",
        ),
        display_name: "Example".into(),
        adapter_kind: LlmAdapterKind::OpenAiChatCompletions,
        protocol_version: None,
        base_url: "https://api.example.com/v1".into(),
        model_id: "model-x".into(),
        auth_ref,
        timeout_ms: 30_000,
        max_retries: 1,
        batch_policy: LlmBatchPolicy::default(),
        cost_budget: None,
        retention: DataRetentionPreference::Unknown,
        allowed_uses: vec![LlmUse::SemanticJudgment],
        capability: ProviderCapability::unknown(),
        created_at_ms: 1_800_000_000_000,
    }
}

fn dump_profiles_table(repo: &SqliteRepository) -> String {
    let conn = repo.connection.lock();
    let mut statement = conn
        .prepare("SELECT id,display_name,adapter_kind,base_url,model_id,auth_ref,profile_json FROM llm_provider_profiles")
        .unwrap();
    let rows = statement
        .query_map([], |row| {
            Ok(format!(
                "{}|{}|{}|{}|{}|{:?}|{}",
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, Option<String>>(5)?,
                row.get::<_, String>(6)?,
            ))
        })
        .unwrap()
        .collect::<rusqlite::Result<Vec<_>>>()
        .unwrap();
    rows.join("\n")
}

#[test]
fn registering_a_provider_never_writes_the_secret_to_the_database() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = provider_services(&repo);
    let store = InMemorySecretStore::new();

    let secret = "sk-super-secret-key-DO-NOT-PERSIST";
    let saved = services
        .llm_providers()
        .register_llm_provider(sample_profile(None), secret, &store)
        .unwrap();

    // The profile now references the secret opaquely, not the secret itself.
    let auth_ref = saved.auth_ref.expect("auth_ref assigned");
    assert!(!auth_ref.as_str().contains(secret));

    // The entire persisted row — every column and the JSON blob — is free of
    // the raw credential. This is the "keys never in plain storage" guardrail.
    let dump = dump_profiles_table(&repo);
    assert!(!dump.contains(secret), "secret leaked into DB: {dump}");
    assert!(dump.contains(auth_ref.as_str()));

    // The secret is resolvable only through the secure store.
    assert_eq!(store.resolve(&auth_ref).unwrap().as_deref(), Some(secret));
}

#[test]
fn provider_profile_round_trips_and_lists() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = provider_services(&repo);

    let profile = sample_profile(Some(LlmAuthRef::new("kc://llm/example")));
    let saved = services
        .llm_providers()
        .save_llm_provider_profile(profile.clone())
        .unwrap();
    assert_eq!(saved, profile);

    let fetched = services
        .llm_providers()
        .llm_provider_profile(&profile.id)
        .unwrap()
        .unwrap();
    assert_eq!(fetched, profile);

    let listed = services
        .llm_providers()
        .list_llm_provider_profiles()
        .unwrap();
    assert_eq!(listed, vec![profile.clone()]);

    // Upsert (edit) replaces in place rather than duplicating.
    let mut edited = profile.clone();
    edited.display_name = "Renamed".into();
    services
        .llm_providers()
        .save_llm_provider_profile(edited.clone())
        .unwrap();
    let listed = services
        .llm_providers()
        .list_llm_provider_profiles()
        .unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].display_name, "Renamed");
}

#[test]
fn llm_sentence_checkpoint_survives_repository_reopen() {
    let directory = tempfile::tempdir().unwrap();
    let database = directory.path().join("checkpoint.sqlite");
    let partition = application::batch_governor::CachedPartition {
        boundary_after_token_indices: vec![2, 4],
        model_id: Some("model-x".into()),
        prompt_version: Some("sense-group-partition-v1".into()),
    };
    {
        let repo = SqliteRepository::open(&database).unwrap();
        repo.save_llm_sentence_checkpoint("fingerprint", &partition, 42)
            .unwrap();
    }
    let reopened = SqliteRepository::open(&database).unwrap();
    assert_eq!(
        reopened.get_llm_sentence_checkpoint("fingerprint").unwrap(),
        Some(partition)
    );
}

#[test]
fn deleting_a_provider_also_removes_its_secret() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = provider_services(&repo);
    let store = InMemorySecretStore::new();

    let saved = services
        .llm_providers()
        .register_llm_provider(sample_profile(None), "sk-key", &store)
        .unwrap();
    let auth_ref = saved.auth_ref.clone().unwrap();
    assert!(store.resolve(&auth_ref).unwrap().is_some());

    services
        .llm_providers()
        .delete_llm_provider(&saved.id, &store)
        .unwrap();

    // Both the profile and its credential are gone.
    assert!(
        services
            .llm_providers()
            .llm_provider_profile(&saved.id)
            .unwrap()
            .is_none()
    );
    assert!(store.resolve(&auth_ref).unwrap().is_none());
}

#[test]
fn resolving_a_deleted_secret_degrades_to_none_not_error() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = provider_services(&repo);
    let store = InMemorySecretStore::new();

    let saved = services
        .llm_providers()
        .register_llm_provider(sample_profile(None), "sk-key", &store)
        .unwrap();
    // Simulate the key being removed from the keychain out of band.
    store.delete(saved.auth_ref.as_ref().unwrap()).unwrap();

    // The dispatcher resolves to None and degrades honestly instead of failing.
    assert_eq!(
        services
            .llm_providers()
            .resolve_llm_provider_secret(&saved, &store)
            .unwrap(),
        None
    );
}
