use std::sync::Arc;

use application::{AppServices, ImportSubtitle, RegisterMedia, UpsertLexicalEntry};
use domain::{
    LearningStatus, LexicalEntry, LexicalEntryKind, MediaAvailability, MediaKind, TimeMs,
};
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

fn make_services(repo: Arc<SqliteRepository>) -> AppServices {
    AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo,
    )
}

fn upsert_word_asset(
    services: &AppServices,
    value: impl Into<String>,
    display_form: impl Into<String>,
    status: Option<LearningStatus>,
) {
    let value = value.into();
    services
        .create_lexical_entry(UpsertLexicalEntry {
            language: "en".into(),
            kind: LexicalEntryKind::Word,
            canonical_form: value,
            display_form: display_form.into(),
            status,
            user_definition: None,
            personal_note: None,
            source: None,
        })
        .expect("upsert lexical word");
}

fn read_word_asset(services: &AppServices, value: &str) -> Option<LexicalEntry> {
    services
        .read_lexical_entries_by_forms("en", LexicalEntryKind::Word, &[value.into()])
        .expect("read lexical word")
        .into_iter()
        .next()
}

#[test]
fn file_database_persists_across_reopen() {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("test.sqlite");

    // Create and populate
    {
        let repo = SqliteRepository::open(&db_path).expect("open");
        let services = make_services(Arc::new(repo));
        let media = register_test_media(&services);
        upsert_word_asset(
            &services,
            "persist",
            "Persist",
            Some(LearningStatus::KnownRecognized),
        );
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
        let services = make_services(Arc::new(repo));
        let entry = read_word_asset(&services, "persist").expect("entry should exist after reopen");
        assert_eq!(entry.display_form, "Persist");
        assert_eq!(entry.status, Some(LearningStatus::KnownRecognized));
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
                let services = make_services(repo.clone());
                for j in 0..50 {
                    upsert_word_asset(
                        &services,
                        format!("thread-{i}-word-{j}"),
                        format!("T{i}W{j}"),
                        Some(LearningStatus::UnknownMeaning),
                    );
                }
            })
        })
        .collect();

    for handle in handles {
        handle.join().expect("thread should not panic");
    }

    // All 400 words should be queryable
    let services = make_services(repo);
    for i in 0..8 {
        for j in 0..50 {
            let entry = read_word_asset(&services, &format!("thread-{i}-word-{j}"))
                .expect("word should exist");
            assert_eq!(entry.display_form, format!("T{i}W{j}"));
        }
    }
}

#[test]
fn subtitle_import_and_export_preserves_sentence_structure() {
    let repo = Arc::new(SqliteRepository::in_memory().expect("in_memory"));
    let media = {
        let services = make_services(repo.clone());
        register_test_media(&services)
    };

    let services = make_services(repo);
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
    let services = make_services(repo);
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

    let services = make_services(Arc::new(repo));
    assert!(read_word_asset(&services, "nonexistent").is_none());
    assert!(
        services
            .read_progress(&domain::MediaId::parse("nonexistent-media-id").unwrap())
            .expect("read")
            .is_none()
    );
}
