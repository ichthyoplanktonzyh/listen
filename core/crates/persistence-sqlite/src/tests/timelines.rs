use super::*;

#[test]
fn archived_transcription_jobs_are_hidden_from_list_and_reuse() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let mut job = transcription_job("job-1", "same-input", TranscriptionJobStatus::Completed, 10);
    repo.create_job(&job).unwrap();

    assert_eq!(repo.list_jobs().unwrap().len(), 1);
    assert_eq!(
        repo.find_completed_job("same-input")
            .unwrap()
            .expect("completed job should be reusable")
            .id,
        job.id
    );

    job.archived_at_ms = Some(20);
    job.updated_at_ms = 20;
    repo.update_job(&job).unwrap();

    assert!(repo.list_jobs().unwrap().is_empty());
    assert!(repo.find_completed_job("same-input").unwrap().is_none());
    assert_eq!(
        repo.get_job(&job.id)
            .unwrap()
            .expect("archive should not delete job")
            .archived_at_ms,
        Some(20)
    );
}

#[test]
fn activating_word_timeline_updates_active_resource_and_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let older = word_timeline(
        "timeline-1",
        &track,
        TimelineStatus::Active,
        "whisper-dtw",
        120,
        300,
    );
    let newer = word_timeline(
        "timeline-2",
        &track,
        TimelineStatus::Candidate,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&older).unwrap();
    repo.save_word_timeline(&newer).unwrap();

    let active = repo.activate_word_timeline(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_word_timeline(&track.id).unwrap().unwrap().id,
        newer.id
    );
    assert_eq!(
        repo.get_word_timeline(&older.id).unwrap().unwrap().status,
        TimelineStatus::Candidate
    );

    let compatibility_timings = repo.get_word_timings(&sentence_id).unwrap();
    assert_eq!(compatibility_timings.len(), 1);
    assert_eq!(compatibility_timings[0].provider_id, "mms-fa");
    assert_eq!(compatibility_timings[0].start_ms, 150);
    assert_eq!(compatibility_timings[0].end_ms, 260);
}

#[test]
fn timeline_active_uniqueness_is_schema_enforced() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();

    let word_active = word_timeline(
        "timeline-active-unique-1",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    let word_duplicate = word_timeline(
        "timeline-active-unique-2",
        &track,
        TimelineStatus::Active,
        "whisper-dtw",
        180,
        290,
    );
    repo.save_word_timeline(&word_active).unwrap();
    assert!(repo.save_word_timeline(&word_duplicate).is_err());

    let chunk_active = chunk_timeline(
        "chunk-active-unique-1",
        &track,
        &word_active,
        TimelineStatus::Active,
    );
    let chunk_duplicate = chunk_timeline(
        "chunk-active-unique-2",
        &track,
        &word_active,
        TimelineStatus::Active,
    );
    repo.save_chunk_timeline(&chunk_active).unwrap();
    assert!(repo.save_chunk_timeline(&chunk_duplicate).is_err());

    let phone_active = phone_timeline(
        "phone-active-unique-1",
        &track,
        &word_active,
        TimelineStatus::Active,
    );
    let phone_duplicate = phone_timeline(
        "phone-active-unique-2",
        &track,
        &word_active,
        TimelineStatus::Active,
    );
    repo.save_phone_timeline(&phone_active).unwrap();
    assert!(repo.save_phone_timeline(&phone_duplicate).is_err());
}

#[test]
fn archiving_active_word_timeline_clears_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let timeline = word_timeline(
        "timeline-archive-active",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&timeline).unwrap();
    repo.activate_word_timeline(&timeline.id).unwrap();

    let archived = repo.archive_word_timeline(&timeline.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
    assert!(repo.get_word_timings(&sentence_id).unwrap().is_empty());
}

#[test]
fn deleting_active_word_timeline_clears_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let timeline = word_timeline(
        "timeline-delete-active",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&timeline).unwrap();
    repo.activate_word_timeline(&timeline.id).unwrap();

    let deleted = repo.delete_word_timeline(&timeline.id).unwrap();
    assert_eq!(deleted.id, timeline.id);
    assert!(repo.get_word_timeline(&timeline.id).unwrap().is_none());
    assert!(repo.active_word_timeline(&track.id).unwrap().is_none());
    assert!(repo.get_word_timings(&sentence_id).unwrap().is_empty());
}

#[test]
fn activating_chunk_timeline_updates_active_resource() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let parent = word_timeline(
        "timeline-parent",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&parent).unwrap();
    let older = chunk_timeline("chunk-timeline-1", &track, &parent, TimelineStatus::Active);
    let newer = chunk_timeline(
        "chunk-timeline-2",
        &track,
        &parent,
        TimelineStatus::Candidate,
    );
    repo.save_chunk_timeline(&older).unwrap();
    repo.save_chunk_timeline(&newer).unwrap();

    let active = repo.activate_chunk_timeline(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_chunk_timeline(&track.id).unwrap().unwrap().id,
        newer.id
    );
    assert_eq!(
        repo.get_chunk_timeline(&older.id).unwrap().unwrap().status,
        TimelineStatus::Candidate
    );
    assert_eq!(repo.list_chunk_timelines(&track.id).unwrap().len(), 2);
}

#[test]
fn archiving_and_deleting_chunk_timeline_updates_repository() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let parent = word_timeline(
        "timeline-parent-delete",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&parent).unwrap();
    let timeline = chunk_timeline(
        "chunk-timeline-delete",
        &track,
        &parent,
        TimelineStatus::Candidate,
    );
    repo.save_chunk_timeline(&timeline).unwrap();

    let archived = repo.archive_chunk_timeline(&timeline.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    let deleted = repo.delete_chunk_timeline(&timeline.id).unwrap();
    assert_eq!(deleted.id, timeline.id);
    assert!(repo.get_chunk_timeline(&timeline.id).unwrap().is_none());
}

#[test]
fn activating_phone_timeline_updates_active_resource() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let parent = word_timeline(
        "timeline-parent-phone",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&parent).unwrap();
    let older = phone_timeline("phone-timeline-1", &track, &parent, TimelineStatus::Active);
    let newer = phone_timeline(
        "phone-timeline-2",
        &track,
        &parent,
        TimelineStatus::Candidate,
    );
    repo.save_phone_timeline(&older).unwrap();
    repo.save_phone_timeline(&newer).unwrap();

    let active = repo.activate_phone_timeline(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_phone_timeline(&track.id).unwrap().unwrap().id,
        newer.id
    );
    assert_eq!(
        repo.get_phone_timeline(&older.id).unwrap().unwrap().status,
        TimelineStatus::Candidate
    );
    assert_eq!(repo.list_phone_timelines(&track.id).unwrap().len(), 2);
}

#[test]
fn archiving_and_deleting_phone_timeline_updates_repository() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let parent = word_timeline(
        "timeline-parent-phone-delete",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&parent).unwrap();
    let timeline = phone_timeline(
        "phone-timeline-delete",
        &track,
        &parent,
        TimelineStatus::Candidate,
    );
    repo.save_phone_timeline(&timeline).unwrap();

    let archived = repo.archive_phone_timeline(&timeline.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    let deleted = repo.delete_phone_timeline(&timeline.id).unwrap();
    assert_eq!(deleted.id, timeline.id);
    assert!(repo.get_phone_timeline(&timeline.id).unwrap().is_none());
}

#[test]
fn lltimeline_resource_metadata_and_artifacts_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let metadata = LLTimelineMetadata {
        created_at_ms: 42,
        generator: LLTimelineGenerator {
            id: "fixture-production-engine".into(),
            version: "v2".into(),
            mode: "production_engine".into(),
        },
        media: LLTimelineMedia {
            id: track.media_id.clone(),
            fingerprint: "media-fingerprint".into(),
            path: None,
            title: "Fixture".into(),
            duration_ms: Some(1200),
        },
        language: track.language.clone(),
        human_reviewed: true,
        extra: serde_json::json!({"track_source": "fixture.lltimeline.json"}),
    };
    let artifacts = vec![LLTimelineArtifact {
        kind: "production_report".into(),
        provider_id: Some("fixture-production-engine".into()),
        provider_version: Some("v2".into()),
        payload: serde_json::json!({"readiness": "ready"}),
    }];

    repo.save_lltimeline_resource(&track.id, &metadata, &artifacts)
        .unwrap();

    let (saved_metadata, saved_artifacts) = repo
        .get_lltimeline_resource(&track.id)
        .unwrap()
        .expect("resource metadata should be saved");
    assert_eq!(saved_metadata.generator.id, "fixture-production-engine");
    assert!(saved_metadata.human_reviewed);
    assert_eq!(saved_artifacts.len(), 1);
    assert_eq!(saved_artifacts[0].kind, "production_report");
}
