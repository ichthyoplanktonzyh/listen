use application::{
    ApplicationError, MaterialRepository, PlaybackProgressRepository, RegisterMedia,
};

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
        // Pre-migration rows are retained with their creation time, exactly
        // like the v58 backfill, so the library projection covers them.
        retained_at_ms: Some(1),
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

fn register(services: &AppServices, fingerprint: &str, retain: Option<bool>) -> MediaItem {
    services
        .media_analysis()
        .register_media(RegisterMedia {
            path: format!("/tmp/{fingerprint}.mp4"),
            fingerprint: fingerprint.to_owned(),
            title: fingerprint.to_owned(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
            retain,
        })
        .unwrap()
}

fn library_ids(services: &AppServices) -> Vec<MediaId> {
    services
        .media_analysis()
        .list_media_library()
        .unwrap()
        .into_iter()
        .map(|entry| entry.media.id)
        .collect()
}

#[test]
fn explicit_temporary_registration_is_readable_but_absent_from_library() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "temporary-media", Some(false));

    // Readable by media ID, with no membership evidence...
    let fetched = repo.get(&item.id).unwrap().expect("media exists");
    assert_eq!(fetched.id, item.id);
    assert_eq!(fetched.retained_at_ms, None);
    // ...but absent from the Personal Library projection.
    assert!(!library_ids(&services).contains(&item.id));
    assert!(
        services
            .media_analysis()
            .list_media_library()
            .unwrap()
            .is_empty()
    );
}

#[test]
fn registration_retain_defaults_to_retained_for_old_clients() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "legacy-media", None);
    assert!(item.retained_at_ms.is_some());
    assert!(library_ids(&services).contains(&item.id));
}

#[test]
fn explicit_true_registration_retains_immediately() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "kept-media", Some(true));
    assert!(item.retained_at_ms.is_some());
    assert!(library_ids(&services).contains(&item.id));
}

#[test]
fn repeated_registration_never_clears_existing_membership() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "re-register-media", Some(false));
    let retained = services.media_analysis().retain_media(&item.id).unwrap();
    let membership = retained.retained_at_ms.expect("membership time");

    // A later registration with explicit `retain: false` over the same
    // fingerprint must not silently unretain the item.
    let re_registered = register(&services, "re-register-media", Some(false));
    assert_eq!(re_registered.retained_at_ms, Some(membership));
    assert!(library_ids(&services).contains(&item.id));
}

#[test]
fn reregistering_at_a_managed_path_preserves_identity_learning_state_and_membership() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let original = register(&services, "managed-rebind-media", Some(false));
    PlaybackProgressRepository::save(repo.as_ref(), &original.id, TimeMs::new(4_200)).unwrap();

    // Managed Asset Store rebinding presents the same fingerprint at a new
    // path and a learner-facing title. It must update those mutable binding
    // facts while retaining the fingerprint-derived media ID and every record
    // owned by that ID.
    let rebound = services
        .media_analysis()
        .register_media(RegisterMedia {
            path: "/managed-assets/sha256-managed-rebind-media.mp3".into(),
            fingerprint: "managed-rebind-media".into(),
            title: "Original learner title".into(),
            kind: MediaKind::Audio,
            duration_ms: Some(10_000),
            retain: Some(true),
        })
        .unwrap();

    assert_eq!(rebound.id, original.id);
    assert_eq!(
        rebound.path,
        "/managed-assets/sha256-managed-rebind-media.mp3"
    );
    assert_eq!(rebound.title, "Original learner title");
    assert!(rebound.retained_at_ms.is_some());
    assert!(
        rebound.updated_at_ms >= original.updated_at_ms,
        "the fresh rebind update time is preserved, never rolled back"
    );
    assert_eq!(
        services
            .media_analysis()
            .read_progress(&original.id)
            .unwrap(),
        Some(TimeMs::new(4_200)),
        "re-registering a managed binding must not lose learning state"
    );
}

#[test]
fn retain_media_is_idempotent_and_preserves_original_timestamp() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "retain-twice-media", Some(false));
    let first = services.media_analysis().retain_media(&item.id).unwrap();
    let membership = first.retained_at_ms.expect("membership time");
    assert!(library_ids(&services).contains(&item.id));

    let second = services.media_analysis().retain_media(&item.id).unwrap();
    assert_eq!(
        second.retained_at_ms,
        Some(membership),
        "repeated retention preserves the original membership time"
    );
    // The library contains the item exactly once.
    assert_eq!(
        library_ids(&services)
            .iter()
            .filter(|id| **id == item.id)
            .count(),
        1
    );
}

#[test]
fn unretain_removes_membership_only_and_is_idempotent() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "unretain-media", Some(false));
    let retained = services.media_analysis().retain_media(&item.id).unwrap();
    let updated_at_after_retain = retained.updated_at_ms;

    let unretained = services.media_analysis().unretain_media(&item.id).unwrap();
    assert_eq!(unretained.retained_at_ms, None);
    assert!(unretained.updated_at_ms >= updated_at_after_retain);
    assert!(!library_ids(&services).contains(&item.id));
    // The media itself stays registered and readable.
    assert_eq!(repo.get(&item.id).unwrap().unwrap().id, item.id);

    // Unretaining again is a no-op.
    let again = services.media_analysis().unretain_media(&item.id).unwrap();
    assert_eq!(again.retained_at_ms, None);
    assert!(!library_ids(&services).contains(&item.id));
}

#[test]
fn put_after_delete_obtains_a_new_membership_timestamp() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "cycle-media", Some(false));
    let first = services.media_analysis().retain_media(&item.id).unwrap();
    let first_membership = first.retained_at_ms.expect("membership time");

    services.media_analysis().unretain_media(&item.id).unwrap();
    assert!(!library_ids(&services).contains(&item.id));

    // Guarantee the clock advances so the re-stamp is observably fresh.
    std::thread::sleep(std::time::Duration::from_millis(2));
    let second = services.media_analysis().retain_media(&item.id).unwrap();
    let second_membership = second.retained_at_ms.expect("membership time");
    assert!(
        second_membership > first_membership,
        "PUT after DELETE must obtain a fresh membership timestamp"
    );
    assert!(library_ids(&services).contains(&item.id));
}

#[test]
fn legacy_retain_keeps_media_and_material_membership_in_agreement() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "both-lists-media", Some(false));

    // Temporary registration: absent from both projections.
    assert!(!library_ids(&services).contains(&item.id));
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    assert!(material.retained_at_ms.is_none());

    // Legacy Media API retain: the material and the library agree on the
    // exact membership timestamp.
    let retained = services.media_analysis().retain_media(&item.id).unwrap();
    let membership = retained.retained_at_ms.expect("membership time");
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    assert_eq!(material.retained_at_ms, Some(membership));
    assert!(library_ids(&services).contains(&item.id));
    let retained_list = repo.list_retained_materials().unwrap();
    assert_eq!(retained_list.len(), 1);
    assert_eq!(retained_list[0].id, material.id);

    // Repeated retain is a no-op that keeps the original timestamp on both
    // the media and the material.
    let again = services.media_analysis().retain_media(&item.id).unwrap();
    assert_eq!(again.retained_at_ms, Some(membership));
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    assert_eq!(material.retained_at_ms, Some(membership));
}

#[test]
fn legacy_unretain_clears_material_and_media_membership_together() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "unretain-both-media", Some(true));
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    assert!(material.retained_at_ms.is_some());

    PlaybackProgressRepository::save(repo.as_ref(), &item.id, TimeMs::new(1_200)).unwrap();
    let graph_before = (
        count_rows(&repo, "learning_materials"),
        count_rows(&repo, "material_revisions"),
        count_rows(&repo, "material_assets"),
        count_rows(&repo, "material_media_bindings"),
    );

    let unretained = services.media_analysis().unretain_media(&item.id).unwrap();
    assert!(unretained.retained_at_ms.is_none());
    assert!(!library_ids(&services).contains(&item.id));

    // The material clears together with the media inside the same transaction,
    // so the retained material list agrees with the media library projection.
    let material = repo.material_for_media(&item.id).unwrap().unwrap();
    assert!(material.retained_at_ms.is_none());
    assert_eq!(
        repo.list_retained_materials().unwrap().len(),
        0,
        "the retained material list agrees with the media library"
    );
    // The graph and learner-owned state remain.
    assert_eq!(
        (
            count_rows(&repo, "learning_materials"),
            count_rows(&repo, "material_revisions"),
            count_rows(&repo, "material_assets"),
            count_rows(&repo, "material_media_bindings"),
        ),
        graph_before
    );
    assert_eq!(
        services.media_analysis().read_progress(&item.id).unwrap(),
        Some(TimeMs::new(1_200)),
        "unretaining preserves playback progress"
    );
    assert_eq!(
        repo.get(&item.id).unwrap().unwrap().id,
        item.id,
        "the media stays registered and readable"
    );
}

fn count_rows(repo: &SqliteRepository, table: &str) -> u32 {
    repo.connection
        .lock()
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .unwrap()
}

#[test]
fn direct_membership_on_unknown_media_is_not_found() {
    // The repository boundary itself must reject unknown media with
    // NotFound, independent of the application layer's pre-checks.
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let missing = MediaId::parse("repo-missing-media").unwrap();
    assert!(matches!(
        MediaRepository::set_library_membership(repo.as_ref(), &missing, Some(1), 1),
        Err(ApplicationError::NotFound("media"))
    ));
    assert!(matches!(
        MediaRepository::set_library_membership(repo.as_ref(), &missing, None, 1),
        Err(ApplicationError::NotFound("media"))
    ));
    // Nothing was created for the unknown media.
    assert_eq!(
        count_rows(&repo, "media_items"),
        0,
        "unknown membership must not create a media row"
    );
    assert_eq!(
        count_rows(&repo, "learning_materials"),
        0,
        "unknown membership must not create a material"
    );
}

#[test]
fn membership_operations_on_unknown_media_are_not_found() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let missing = MediaId::parse("missing-membership-media").unwrap();
    assert!(matches!(
        services.media_analysis().retain_media(&missing),
        Err(ApplicationError::NotFound("media"))
    ));
    assert!(matches!(
        services.media_analysis().unretain_media(&missing),
        Err(ApplicationError::NotFound("media"))
    ));
}

#[test]
fn unretain_preserves_progress_subtitles_and_learner_owned_state() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = library_services(&repo);
    let item = register(&services, "state-preserving-media", Some(true));

    // Learner-owned state attached before unretaining: playback progress, a
    // subtitle track (subtitle/resource representative), and a learner fact.
    PlaybackProgressRepository::save(repo.as_ref(), &item.id, TimeMs::new(4_200)).unwrap();
    let track = SubtitleTrack {
        id: SubtitleTrackId::from_fingerprint("track", "state-preserving"),
        media_id: item.id.clone(),
        fingerprint: "state-preserving-track".into(),
        language: Some(LanguageCode::parse("en").unwrap()),
        source: "test".into(),
        status: SubtitleTrackStatus::Available,
        sentences: vec![SubtitleSentence {
            id: SubtitleSentenceId::from_fingerprint("sentence", "state-preserving"),
            index: 0,
            start: TimeMs::new(0),
            end: TimeMs::new(5_000),
            original_text: "Hello".into(),
            display_text: "Hello".into(),
            tokens: vec![SubtitleToken {
                index: 0,
                kind: SubtitleTokenKind::Word,
                text: "Hello".into(),
                normalized: Some("hello".into()),
                start_char: 0,
                end_char: 5,
            }],
        }],
    };
    repo.save_track(&track).unwrap();
    LearningEventRepository::append_learning_event(
        repo.as_ref(),
        &LearningEvent {
            id: LearningEventId::from_fingerprint("learning-event", "state-preserving"),
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

    services.media_analysis().unretain_media(&item.id).unwrap();

    // Progress survives unretaining.
    assert_eq!(
        services.media_analysis().read_progress(&item.id).unwrap(),
        Some(TimeMs::new(4_200))
    );
    // The subtitle track representative survives and stays available.
    assert_eq!(repo.get_track(&track.id).unwrap(), Some(track.clone()));
    // The learner-owned fact survives.
    assert_eq!(
        repo.list_event_subject_ids(
            LearningEventKind::FamiliarMaterialMarked,
            LearningEventSubjectKind::Media,
        )
        .unwrap(),
        vec![item.id.as_str().to_owned()]
    );
    // Media identity itself is untouched.
    let fetched = repo.get(&item.id).unwrap().unwrap();
    assert_eq!(fetched.id, item.id);
    assert_eq!(fetched.path, item.path);
    assert_eq!(fetched.availability, item.availability);
    assert_eq!(fetched.retained_at_ms, None);
}

#[test]
fn membership_mutation_changes_only_retained_and_updated_columns() {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let item = MediaRepository::upsert(
        repo.as_ref(),
        &MediaItem {
            id: MediaId::parse("column-proof-media").unwrap(),
            path: "/tmp/column-proof.mp4".into(),
            fingerprint: "column-proof-fp".into(),
            title: "Column proof".into(),
            kind: MediaKind::Audio,
            duration: Some(TimeMs::new(9_000)),
            availability: MediaAvailability::Available,
            retained_at_ms: None,
            created_at_ms: 7,
            updated_at_ms: 8,
        },
    )
    .unwrap();
    let before = media_row(&repo, &item.id);
    // A valid membership stamp pair: retention evidence never postdates the
    // latest update, so the caller's exact values are preserved verbatim.
    let updated =
        MediaRepository::set_library_membership(repo.as_ref(), &item.id, Some(123_456), 123_456)
            .unwrap();
    let after = media_row(&repo, &item.id);

    // Only `retained_at_ms` and `updated_at_ms` change; every other column is
    // byte-identical before and after the membership mutation, and the caller's
    // exact membership and update values are preserved.
    let mut expected_after = before.clone();
    expected_after["updated_at_ms"] = serde_json::json!(123_456);
    expected_after["retained_at_ms"] = serde_json::json!(123_456);
    assert_eq!(after, expected_after);
    assert_eq!(updated.retained_at_ms, Some(123_456));
    assert_eq!(updated.updated_at_ms, 123_456);

    // Clearing membership changes the same two columns only.
    let cleared =
        MediaRepository::set_library_membership(repo.as_ref(), &item.id, None, 10).unwrap();
    assert_eq!(cleared.retained_at_ms, None);
    assert_eq!(cleared.updated_at_ms, 10);
    let row: (Option<u64>, u64) = {
        let conn = repo.connection.lock();
        conn.query_row(
            "SELECT retained_at_ms, updated_at_ms FROM media_items WHERE id=?1",
            [item.id.as_str()],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap()
    };
    assert_eq!(row, (None, 10));
}

/// `media_items` row as a JSON object, in SELECT order. Used to prove that a
/// membership mutation changes exactly `retained_at_ms` and `updated_at_ms`.
fn media_row(repo: &SqliteRepository, id: &MediaId) -> serde_json::Value {
    let conn = repo.connection.lock();
    conn.query_row(
        "SELECT id,path,fingerprint,title,kind,duration_ms,created_at_ms,updated_at_ms,availability,retained_at_ms
         FROM media_items WHERE id=?1",
        [id.as_str()],
        |row| {
            Ok(serde_json::json!({
                "id": row.get::<_, String>(0)?,
                "path": row.get::<_, String>(1)?,
                "fingerprint": row.get::<_, String>(2)?,
                "title": row.get::<_, String>(3)?,
                "kind": row.get::<_, String>(4)?,
                "duration_ms": row.get::<_, Option<u64>>(5)?,
                "created_at_ms": row.get::<_, u64>(6)?,
                "updated_at_ms": row.get::<_, u64>(7)?,
                "availability": row.get::<_, String>(8)?,
                "retained_at_ms": row.get::<_, Option<u64>>(9)?,
            }))
        },
    )
    .unwrap()
}
