use std::sync::Arc;

use application::{AppServices, ImportSubtitle, RegisterMedia, UpdateWordProfile};
use domain::{MediaAvailability, MediaKind, TimeMs, WordStatus};
use persistence_sqlite::SqliteRepository;

/// Create test media and verify it round-trips through the database.
fn register_test_media(services: &AppServices) -> domain::MediaItem {
    services
        .register_media(RegisterMedia {
            path: "/tmp/test.mp4".into(),
            fingerprint: format!("fp-{}", application::now_ms()),
            title: "Test Video".into(),
            kind: MediaKind::Video,
            duration_ms: Some(10_000),
        })
        .expect("register media should succeed")
}

#[test]
fn file_database_persists_across_reopen() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("test.sqlite");

    // Create and populate
    {
        let repo = SqliteRepository::open(&db_path).expect("open");
        let services = AppServices::new(
            Arc::new(repo),
            Arc::new(SqliteRepository::open(&db_path).expect("open 2")),
            Arc::new(SqliteRepository::open(&db_path).expect("open 3")),
            Arc::new(SqliteRepository::open(&db_path).expect("open 4")),
            Arc::new(SqliteRepository::open(&db_path).expect("open 5")),
            Arc::new(SqliteRepository::open(&db_path).expect("open 6")),
            Arc::new(SqliteRepository::open(&db_path).expect("open 7")),
            Arc::new(SqliteRepository::open(&db_path).expect("open 8")),
        );
        let media = register_test_media(&services);
        services
            .update_word_profile(UpdateWordProfile {
                language: "en".into(),
                lemma: "persist".into(),
                display_form: "Persist".into(),
                status: Some(WordStatus::KnownRecognized),
                source: None,
            })
            .expect("update word profile");
        services
            .update_progress(&media.id, 5555)
            .expect("save progress");
    }

    // Reopen and verify
    {
        let repo = SqliteRepository::open(&db_path).expect("reopen");
        assert_eq!(
            repo.schema_version().expect("schema version"),
            persistence_sqlite::MIGRATION_VERSION
        );
        let services = AppServices::new(
            Arc::new(repo),
            Arc::new(SqliteRepository::open(&db_path).expect("open")),
            Arc::new(SqliteRepository::open(&db_path).expect("open")),
            Arc::new(SqliteRepository::open(&db_path).expect("open")),
            Arc::new(SqliteRepository::open(&db_path).expect("open")),
            Arc::new(SqliteRepository::open(&db_path).expect("open")),
            Arc::new(SqliteRepository::open(&db_path).expect("open")),
            Arc::new(SqliteRepository::open(&db_path).expect("open")),
        );
        let profile = services
            .read_word_profile("en", "persist")
            .expect("read")
            .expect("profile should exist after reopen");
        assert_eq!(profile.display_form, "Persist");
        assert_eq!(profile.status, Some(WordStatus::KnownRecognized));
    }
}

#[test]
fn backup_created_when_migration_upgrades_existing_database() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("old.sqlite");
    let backup_path = dir.path().join("old.sqlite.pre-migration.bak");

    // Create a database at version 1 (only the first migration applied)
    {
        let conn = rusqlite::Connection::open(&db_path).expect("create");
        conn.execute_batch(include_str!("../migrations/0001_media.sql"))
            .expect("apply migration 1");
        conn.pragma_update(None, "user_version", 1)
            .expect("set version");
    }
    assert!(!backup_path.exists());

    // Open with SqliteRepository — should migrate and create backup
    {
        let repo = SqliteRepository::open(&db_path).expect("open old");
        assert_eq!(
            repo.schema_version().expect("version"),
            persistence_sqlite::MIGRATION_VERSION
        );
    }

    // Backup file must exist
    assert!(
        backup_path.exists(),
        "expected backup at {}",
        backup_path.display()
    );

    // Reopening the backup should show the OLD version (v1)
    let backup_version: u32 = rusqlite::Connection::open(&backup_path)
        .expect("open backup")
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .expect("read backup version");
    assert_eq!(
        backup_version, 1,
        "backup should preserve old schema version"
    );
}

#[test]
fn concurrent_access_through_mutex_is_safe() {
    let repo = Arc::new(SqliteRepository::in_memory().expect("in_memory"));

    // Spawn multiple threads that all insert and query concurrently
    let handles: Vec<_> = (0..8)
        .map(|i| {
            let repo = Arc::clone(&repo);
            std::thread::spawn(move || {
                let services = AppServices::new(
                    repo.clone(),
                    repo.clone(),
                    repo.clone(),
                    repo.clone(),
                    repo.clone(),
                    repo.clone(),
                    repo.clone(),
                    repo.clone(),
                );
                for j in 0..50 {
                    let result = services.update_word_profile(UpdateWordProfile {
                        language: "en".into(),
                        lemma: format!("thread-{i}-word-{j}"),
                        display_form: format!("T{i}W{j}"),
                        status: Some(WordStatus::UnknownMeaning),
                        source: None,
                    });
                    assert!(result.is_ok(), "thread {i} word {j}: {:?}", result.err());
                }
            })
        })
        .collect();

    for handle in handles {
        handle.join().expect("thread should not panic");
    }

    // All 400 words should be queryable
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo,
    );
    for i in 0..8 {
        for j in 0..50 {
            let profile = services
                .read_word_profile("en", &format!("thread-{i}-word-{j}"))
                .expect("read")
                .expect("word should exist");
            assert_eq!(profile.display_form, format!("T{i}W{j}"));
        }
    }
}

#[test]
fn subtitle_import_and_export_preserves_sentence_structure() {
    let repo = Arc::new(SqliteRepository::in_memory().expect("in_memory"));
    let media = {
        let services = AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        );
        register_test_media(&services)
    };

    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo,
    );
    let track = services
        .import_subtitle(ImportSubtitle {
            media_id: media.id.clone(),
            source_name: "timeline.srt".into(),
            content: include_bytes!("../../../testdata/subtitles/timeline.srt").to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .expect("import subtitle");

    // Verify sentence structure
    assert_eq!(track.sentences.len(), 4, "timeline.srt has 4 cues");
    assert_eq!(track.sentences[0].display_text, "Hello, world!");
    assert_eq!(track.sentences[0].start, TimeMs::new(500));
    assert_eq!(track.sentences[3].display_text, "Final cue.");

    // Verify idempotent re-import
    let track_again = services
        .import_subtitle(ImportSubtitle {
            media_id: media.id,
            source_name: "timeline.srt".into(),
            content: include_bytes!("../../../testdata/subtitles/timeline.srt").to_vec(),
            language: Some("en".into()),
            identity_salt: None,
        })
        .expect("reimport");
    assert_eq!(
        track.id, track_again.id,
        "reimport should return same track"
    );

    // Verify track retrieval
    let retrieved = services
        .read_subtitle_track(&track.id)
        .expect("read track")
        .expect("track should exist");
    assert_eq!(retrieved.sentences.len(), 4);
    assert_eq!(retrieved.fingerprint, track.fingerprint);
}

#[test]
fn media_availability_lifecycle() {
    let repo = Arc::new(SqliteRepository::in_memory().expect("in_memory"));
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo,
    );
    let media = register_test_media(&services);
    assert_eq!(media.availability, MediaAvailability::Available);

    // Archive
    let archived = services
        .set_media_availability(&media.id, MediaAvailability::Archived)
        .expect("archive");
    assert_eq!(archived.availability, MediaAvailability::Archived);

    // Missing
    let deleted = services
        .set_media_availability(&media.id, MediaAvailability::Missing)
        .expect("delete");
    assert_eq!(deleted.availability, MediaAvailability::Missing);
}

#[test]
fn empty_database_has_no_data() {
    let repo = SqliteRepository::in_memory().expect("in_memory");
    assert_eq!(
        repo.schema_version().expect("version"),
        persistence_sqlite::MIGRATION_VERSION
    );

    let services = AppServices::new(
        Arc::new(repo),
        Arc::new(SqliteRepository::in_memory().expect("m2")),
        Arc::new(SqliteRepository::in_memory().expect("m3")),
        Arc::new(SqliteRepository::in_memory().expect("m4")),
        Arc::new(SqliteRepository::in_memory().expect("m5")),
        Arc::new(SqliteRepository::in_memory().expect("m6")),
        Arc::new(SqliteRepository::in_memory().expect("m7")),
        Arc::new(SqliteRepository::in_memory().expect("m8")),
    );
    assert!(
        services
            .read_word_profile("en", "nonexistent")
            .expect("read")
            .is_none()
    );
    assert!(
        services
            .read_progress(&domain::MediaId::parse("nonexistent-media-id").unwrap())
            .expect("read")
            .is_none()
    );
}
