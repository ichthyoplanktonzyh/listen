use super::*;
use application::{BackgroundJobStore, BackgroundJobTransition};
use domain::{BackgroundJob, BackgroundJobId, BackgroundJobKind, BackgroundJobStatus};

fn job(id: &str, kind: BackgroundJobKind, status: BackgroundJobStatus) -> BackgroundJob {
    BackgroundJob {
        id: BackgroundJobId::parse(id).unwrap(),
        kind,
        status,
        payload_json: r#"{"track_id":"track-1"}"#.into(),
        completed_units: 0,
        total_units: 4,
        error: None,
        retry_of_job_id: None,
        created_at_ms: 10,
        updated_at_ms: 10,
    }
}

#[test]
fn background_job_cas_preserves_cancellation_against_stale_completion() {
    let repo = SqliteRepository::in_memory().unwrap();
    let running = repo
        .create(&job(
            "speech-1",
            BackgroundJobKind::SpeechBatch,
            BackgroundJobStatus::Running,
        ))
        .unwrap();
    let mut cancelled = running.clone();
    cancelled.status = BackgroundJobStatus::Cancelled;
    cancelled.updated_at_ms = 11;
    assert!(matches!(
        repo.transition(BackgroundJobStatus::Running, &cancelled)
            .unwrap(),
        BackgroundJobTransition::Applied(_)
    ));

    let mut stale_completion = running;
    stale_completion.status = BackgroundJobStatus::Completed;
    stale_completion.completed_units = 4;
    stale_completion.updated_at_ms = 12;
    assert_eq!(
        repo.transition(BackgroundJobStatus::Running, &stale_completion)
            .unwrap(),
        BackgroundJobTransition::Rejected(cancelled)
    );
}

#[test]
fn background_job_progress_is_monotonic_under_concurrent_callbacks() {
    let repo = SqliteRepository::in_memory().unwrap();
    let mut newest = job(
        "llm-progress",
        BackgroundJobKind::LlmBatch,
        BackgroundJobStatus::Running,
    );
    newest.completed_units = 2;
    repo.create(&newest).unwrap();

    let mut stale = newest.clone();
    stale.completed_units = 1;
    stale.updated_at_ms += 1;
    assert_eq!(
        repo.transition(BackgroundJobStatus::Running, &stale)
            .unwrap(),
        BackgroundJobTransition::Rejected(newest)
    );
}

#[test]
fn startup_recovery_resumes_queued_and_marks_running_interrupted() {
    let repo = SqliteRepository::in_memory().unwrap();
    let queued = repo
        .create(&job(
            "sound-queued",
            BackgroundJobKind::SoundLine,
            BackgroundJobStatus::Queued,
        ))
        .unwrap();
    let running = repo
        .create(&job(
            "sound-running",
            BackgroundJobKind::SoundLine,
            BackgroundJobStatus::Running,
        ))
        .unwrap();

    assert_eq!(
        repo.recover_startup(BackgroundJobKind::SoundLine, 20)
            .unwrap(),
        vec![queued]
    );
    let interrupted = BackgroundJobStore::get(&repo, &running.id)
        .unwrap()
        .unwrap();
    assert_eq!(interrupted.status, BackgroundJobStatus::Interrupted);
    assert_eq!(interrupted.updated_at_ms, 20);
    assert!(interrupted.error.unwrap().contains("stopped"));
}

#[test]
fn background_jobs_survive_repository_reopen() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("jobs.sqlite");
    let created = {
        let repo = SqliteRepository::open(&path).unwrap();
        repo.create(&job(
            "llm-1",
            BackgroundJobKind::LlmBatch,
            BackgroundJobStatus::Running,
        ))
        .unwrap()
    };
    let repo = SqliteRepository::open(&path).unwrap();
    assert_eq!(
        BackgroundJobStore::get(&repo, &created.id).unwrap(),
        Some(created)
    );
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
}

#[test]
fn v50_database_migrates_to_the_durable_background_job_store() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("v50.sqlite");
    let connection = rusqlite::Connection::open(&path).unwrap();
    connection.pragma_update(None, "user_version", 50).unwrap();
    drop(connection);

    let repo = SqliteRepository::open(&path).unwrap();
    assert_eq!(repo.schema_version().unwrap(), MIGRATION_VERSION);
    let created = repo
        .create(&job(
            "migrated-job",
            BackgroundJobKind::SpeechBatch,
            BackgroundJobStatus::Queued,
        ))
        .unwrap();
    assert_eq!(
        BackgroundJobStore::get(&repo, &created.id).unwrap(),
        Some(created)
    );
}
