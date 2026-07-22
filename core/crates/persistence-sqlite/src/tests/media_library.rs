use application::ApplicationError;

use super::*;

fn library_services(repo: &Arc<SqliteRepository>) -> AppServices {
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
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_difficulty_repository(repo.clone())
}

fn media(id: &str, updated_at_ms: u64) -> MediaItem {
    MediaItem {
        id: MediaId::parse(id).unwrap(),
        path: format!("/tmp/{id}.mp4"),
        fingerprint: format!("{id}-fp"),
        title: id.to_owned(),
        kind: MediaKind::Video,
        duration: Some(TimeMs::new(1_000)),
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms,
    }
}

#[test]
fn triage_intent_roundtrip_upserts_and_clears() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let item = MediaRepository::upsert(repo.as_ref(), &media("triage-media", 10)).unwrap();

    assert_eq!(repo.get_triage_intent(&item.id).unwrap(), None);
    repo.set_triage_intent(&item.id, Some(MediaTriageIntent::Defer), 100)
        .unwrap();
    assert_eq!(
        repo.get_triage_intent(&item.id).unwrap(),
        Some(MediaTriageIntent::Defer)
    );
    repo.set_triage_intent(&item.id, Some(MediaTriageIntent::PinIntensive), 200)
        .unwrap();
    assert_eq!(
        repo.get_triage_intent(&item.id).unwrap(),
        Some(MediaTriageIntent::PinIntensive)
    );
    assert_eq!(
        repo.list_triage_intents().unwrap(),
        vec![(item.id.clone(), MediaTriageIntent::PinIntensive)]
    );
    repo.set_triage_intent(&item.id, None, 300).unwrap();
    assert_eq!(repo.get_triage_intent(&item.id).unwrap(), None);
    assert!(repo.list_triage_intents().unwrap().is_empty());
}

#[test]
fn media_library_lists_facts_without_requiring_fit() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    // Newer media first: list orders by updated_at_ms DESC.
    MediaRepository::upsert(repo.as_ref(), &media("lib-old", 10)).unwrap();
    let newer = MediaRepository::upsert(repo.as_ref(), &media("lib-new", 20)).unwrap();
    repo.set_triage_intent(&newer.id, Some(MediaTriageIntent::PinExtensive), 30)
        .unwrap();

    let library = services.media_analysis().list_media_library().unwrap();
    assert_eq!(library.len(), 2);
    assert_eq!(library[0].media.id, newer.id);
    assert_eq!(
        library[0].triage_intent,
        Some(MediaTriageIntent::PinExtensive)
    );
    // No subtitle track exists: fit degrades to None, the row still serves.
    assert_eq!(library[0].primary_track_id, None);
    assert!(library[0].fit.is_none());
    assert!(!library[0].familiar_material);
    assert_eq!(library[1].triage_intent, None);
}

#[test]
fn familiar_material_mark_reaches_the_library_entry() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = MediaRepository::upsert(repo.as_ref(), &media("familiar-media", 10)).unwrap();

    LearningEventRepository::append_learning_event(
        repo.as_ref(),
        &LearningEvent {
            id: LearningEventId::from_fingerprint("learning-event", "familiar-test"),
            occurred_at_ms: 42,
            kind: LearningEventKind::FamiliarMaterialMarked,
            subject: LearningEventSubject {
                kind: LearningEventSubjectKind::Media,
                id: item.id.as_str().to_owned(),
            },
            payload: serde_json::json!({}),
            session_id: None,
        },
    )
    .unwrap();

    let library = services.media_analysis().list_media_library().unwrap();
    assert_eq!(library.len(), 1);
    assert!(library[0].familiar_material);
    assert_eq!(
        repo.list_event_subject_ids(
            LearningEventKind::FamiliarMaterialMarked,
            LearningEventSubjectKind::Media,
        )
        .unwrap(),
        vec![item.id.as_str().to_owned()]
    );
}

#[test]
fn set_media_triage_intent_validates_media_and_returns_entry() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let missing = MediaId::parse("missing-media").unwrap();
    assert!(matches!(
        services
            .media_analysis()
            .set_media_triage_intent(&missing, Some(MediaTriageIntent::Defer)),
        Err(ApplicationError::NotFound("media"))
    ));

    let item = MediaRepository::upsert(repo.as_ref(), &media("intent-media", 10)).unwrap();
    let entry = services
        .media_analysis()
        .set_media_triage_intent(&item.id, Some(MediaTriageIntent::Defer))
        .unwrap();
    assert_eq!(entry.media.id, item.id);
    assert_eq!(entry.triage_intent, Some(MediaTriageIntent::Defer));
    let cleared = services
        .media_analysis()
        .set_media_triage_intent(&item.id, None)
        .unwrap();
    assert_eq!(cleared.triage_intent, None);
}
