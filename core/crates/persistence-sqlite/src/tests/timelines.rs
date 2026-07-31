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
    assert!(matches!(
        repo.transition_job(TranscriptionJobStatus::Completed, &job)
            .unwrap(),
        TranscriptionJobTransition::Applied(_)
    ));

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
fn cancellation_wins_over_a_stale_worker_phase_transition() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let mut worker = transcription_job(
        "job-cancel-phase",
        "phase-race",
        TranscriptionJobStatus::Queued,
        10,
    );
    worker.phase_progress = 0;
    worker.completed_at_ms = None;
    worker.generated_track_id = None;
    repo.create_job(&worker).unwrap();

    let mut cancelled = worker.clone();
    cancelled.status = TranscriptionJobStatus::Cancelled;
    cancelled.completed_at_ms = Some(11);
    cancelled.updated_at_ms = 11;
    assert!(matches!(
        repo.transition_job(TranscriptionJobStatus::Queued, &cancelled)
            .unwrap(),
        TranscriptionJobTransition::Applied(_)
    ));

    worker.status = TranscriptionJobStatus::Extracting;
    worker.phase_progress = 5;
    worker.updated_at_ms = 12;
    assert_eq!(
        repo.transition_job(TranscriptionJobStatus::Queued, &worker)
            .unwrap(),
        TranscriptionJobTransition::Rejected(cancelled.clone())
    );
    assert_eq!(
        repo.get_job(&worker.id).unwrap().unwrap().status,
        TranscriptionJobStatus::Cancelled
    );
}

#[test]
fn cancellation_before_import_rejects_the_workers_import_claim() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let mut worker = transcription_job(
        "job-cancel-import",
        "import-race",
        TranscriptionJobStatus::Transcribing,
        20,
    );
    worker.phase_progress = 35;
    worker.completed_at_ms = None;
    worker.generated_track_id = None;
    repo.create_job(&worker).unwrap();

    let mut cancelled = worker.clone();
    cancelled.status = TranscriptionJobStatus::Cancelled;
    cancelled.completed_at_ms = Some(21);
    cancelled.updated_at_ms = 21;
    assert!(matches!(
        repo.transition_job(TranscriptionJobStatus::Transcribing, &cancelled)
            .unwrap(),
        TranscriptionJobTransition::Applied(_)
    ));

    worker.status = TranscriptionJobStatus::Importing;
    worker.phase_progress = 90;
    worker.updated_at_ms = 22;
    assert_eq!(
        repo.transition_job(TranscriptionJobStatus::Transcribing, &worker)
            .unwrap(),
        TranscriptionJobTransition::Rejected(cancelled)
    );
    assert_eq!(
        repo.get_job(&worker.id).unwrap().unwrap().status,
        TranscriptionJobStatus::Cancelled
    );
}

#[test]
fn importing_is_the_irreversible_commit_point_for_cancellation() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let mut job = transcription_job(
        "job-import-commit",
        "import-commit",
        TranscriptionJobStatus::Transcribing,
        30,
    );
    job.phase_progress = 35;
    job.completed_at_ms = None;
    job.generated_track_id = None;
    repo.create_job(&job).unwrap();

    let mut importing = job.clone();
    importing.status = TranscriptionJobStatus::Importing;
    importing.phase_progress = 90;
    importing.updated_at_ms = 31;
    assert!(matches!(
        repo.transition_job(TranscriptionJobStatus::Transcribing, &importing)
            .unwrap(),
        TranscriptionJobTransition::Applied(_)
    ));

    let mut stale_cancel = job;
    stale_cancel.status = TranscriptionJobStatus::Cancelled;
    stale_cancel.completed_at_ms = Some(32);
    stale_cancel.updated_at_ms = 32;
    assert_eq!(
        repo.transition_job(TranscriptionJobStatus::Transcribing, &stale_cancel)
            .unwrap(),
        TranscriptionJobTransition::Rejected(importing)
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
fn activating_word_timeline_if_absent_activates_candidate_and_updates_compatibility_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let candidate = word_timeline(
        "timeline-if-absent",
        &track,
        TimelineStatus::Candidate,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&candidate).unwrap();

    let active = repo
        .activate_word_timeline_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, candidate.id);
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_word_timeline(&track.id).unwrap().unwrap().id,
        candidate.id
    );
    let compatibility_timings = repo.get_word_timings(&sentence_id).unwrap();
    assert_eq!(compatibility_timings.len(), 1);
    assert_eq!(compatibility_timings[0].provider_id, "mms-fa");
}

#[test]
fn activating_word_timeline_if_absent_preserves_existing_active_and_legacy_timings() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    let sentence_id = track.sentences[0].id.clone();
    repo.save_track(&track).unwrap();
    let existing = word_timeline(
        "timeline-existing-active",
        &track,
        TimelineStatus::Candidate,
        "user-selected",
        120,
        300,
    );
    let candidate = word_timeline(
        "timeline-foundation-candidate",
        &track,
        TimelineStatus::Candidate,
        "foundation",
        150,
        260,
    );
    repo.save_word_timeline(&existing).unwrap();
    repo.activate_word_timeline(&existing.id).unwrap();
    repo.save_word_timeline(&candidate).unwrap();

    let active = repo
        .activate_word_timeline_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, existing.id);
    assert_eq!(
        repo.get_word_timeline(&candidate.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
    let compatibility_timings = repo.get_word_timings(&sentence_id).unwrap();
    assert_eq!(compatibility_timings.len(), 1);
    assert_eq!(compatibility_timings[0].provider_id, "user-selected");
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

    let sg_active = sense_group_analysis("sg-active-unique-1", &track, TimelineStatus::Active);
    let sg_duplicate = sense_group_analysis("sg-active-unique-2", &track, TimelineStatus::Active);
    repo.save_sense_group_analysis(&sg_active).unwrap();
    assert!(repo.save_sense_group_analysis(&sg_duplicate).is_err());
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
fn activating_chunk_timeline_if_absent_activates_candidate() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let parent = word_timeline(
        "timeline-parent-if-absent",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&parent).unwrap();
    let candidate = chunk_timeline(
        "chunk-timeline-if-absent",
        &track,
        &parent,
        TimelineStatus::Candidate,
    );
    repo.save_chunk_timeline(&candidate).unwrap();

    let active = repo
        .activate_chunk_timeline_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, candidate.id);
    assert_eq!(active.status, TimelineStatus::Active);
}

#[test]
fn activating_chunk_timeline_if_absent_preserves_existing_active() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let parent = word_timeline(
        "timeline-parent-preserve",
        &track,
        TimelineStatus::Active,
        "mms-fa",
        150,
        260,
    );
    repo.save_word_timeline(&parent).unwrap();
    let existing = chunk_timeline(
        "chunk-timeline-existing-active",
        &track,
        &parent,
        TimelineStatus::Active,
    );
    let candidate = chunk_timeline(
        "chunk-timeline-foundation-candidate",
        &track,
        &parent,
        TimelineStatus::Candidate,
    );
    repo.save_chunk_timeline(&existing).unwrap();
    repo.save_chunk_timeline(&candidate).unwrap();

    let active = repo
        .activate_chunk_timeline_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, existing.id);
    assert_eq!(
        repo.get_chunk_timeline(&candidate.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
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

fn sense_group_analysis(
    id: &str,
    track: &SubtitleTrack,
    status: TimelineStatus,
) -> SenseGroupAnalysis {
    SenseGroupAnalysis {
        id: SenseGroupAnalysisId::parse(id).unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        parent_word_timeline_id: None,
        provider_id: "rule-based-sense-group".into(),
        provider_version: "v1".into(),
        algorithm: "punctuation_length_rule_v1".into(),
        status,
        created_by: TimelineCreator::Algorithm,
        metrics_json: serde_json::json!({}).into(),
        groups: vec![SenseGroup {
            id: SenseGroupId::parse(format!("{id}-sg-1")).unwrap(),
            sentence_id: track.sentences[0].id.clone(),
            group_index: 0,
            start_token_index: 0,
            end_token_index: 0,
            text: "hello".into(),
            label: None,
            head_token_index: None,
            confidence: 0.5,
            sources: vec![SenseGroupSource::Rule],
        }],
        created_at_ms: 1,
        updated_at_ms: 1,
    }
}

#[test]
fn activating_sense_group_analysis_updates_active_resource() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let older = sense_group_analysis("sg-analysis-1", &track, TimelineStatus::Active);
    let newer = sense_group_analysis("sg-analysis-2", &track, TimelineStatus::Candidate);
    repo.save_sense_group_analysis(&older).unwrap();
    repo.save_sense_group_analysis(&newer).unwrap();

    let active = repo.activate_sense_group_analysis(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_sense_group_analysis(&track.id)
            .unwrap()
            .unwrap()
            .id,
        newer.id
    );
    assert_eq!(
        repo.get_sense_group_analysis(&older.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
    assert_eq!(repo.list_sense_group_analyses(&track.id).unwrap().len(), 2);
}

#[test]
fn activating_sense_group_analysis_if_absent_activates_candidate() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let candidate =
        sense_group_analysis("sg-analysis-if-absent", &track, TimelineStatus::Candidate);
    repo.save_sense_group_analysis(&candidate).unwrap();

    let active = repo
        .activate_sense_group_analysis_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, candidate.id);
    assert_eq!(active.status, TimelineStatus::Active);
}

#[test]
fn activating_sense_group_analysis_if_absent_preserves_existing_active() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let existing = sense_group_analysis(
        "sg-analysis-existing-active",
        &track,
        TimelineStatus::Active,
    );
    let candidate = sense_group_analysis(
        "sg-analysis-foundation-candidate",
        &track,
        TimelineStatus::Candidate,
    );
    repo.save_sense_group_analysis(&existing).unwrap();
    repo.save_sense_group_analysis(&candidate).unwrap();

    let active = repo
        .activate_sense_group_analysis_if_absent(&candidate.id)
        .unwrap();

    assert_eq!(active.id, existing.id);
    assert_eq!(
        repo.get_sense_group_analysis(&candidate.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
}

#[test]
fn rule_and_syntax_sense_group_providers_keep_independent_runs() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let rule = sense_group_analysis("sg-rule-v1", &track, TimelineStatus::Candidate);
    let mut syntax = sense_group_analysis("sg-syntax-v1", &track, TimelineStatus::Candidate);
    syntax.provider_id = "syntax-aware-sense-group".into();
    syntax.provider_version = "v1".into();
    syntax.algorithm = "dependency_teaching_partition_v1".into();
    syntax.metrics_json = serde_json::json!({
        "syntactic_analysis_id": "syntax-artifact-1",
        "chunk_timeline_dependency": false
    })
    .into();
    repo.save_sense_group_analysis(&rule).unwrap();
    repo.save_sense_group_analysis(&syntax).unwrap();

    let runs = repo.list_sense_group_analyses(&track.id).unwrap();
    assert_eq!(runs.len(), 2);
    assert!(
        runs.iter()
            .any(|run| run.provider_id == "rule-based-sense-group")
    );
    assert!(runs.iter().any(|run| {
        let metrics = run.metrics_json.as_object();
        run.provider_id == "syntax-aware-sense-group"
            && metrics
                .get("syntactic_analysis_id")
                .and_then(|value| value.as_str())
                == Some("syntax-artifact-1")
            && metrics
                .get("chunk_timeline_dependency")
                .and_then(|value| value.as_bool())
                == Some(false)
    }));
}

#[test]
fn archiving_and_deleting_sense_group_analysis_updates_repository() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let analysis = sense_group_analysis("sg-analysis-delete", &track, TimelineStatus::Candidate);
    repo.save_sense_group_analysis(&analysis).unwrap();

    let archived = repo.archive_sense_group_analysis(&analysis.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    let deleted = repo.delete_sense_group_analysis(&analysis.id).unwrap();
    assert_eq!(deleted.id, analysis.id);
    assert!(
        repo.get_sense_group_analysis(&analysis.id)
            .unwrap()
            .is_none()
    );
}

#[test]
fn sense_group_analysis_json_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();

    let mut analysis = sense_group_analysis("sg-roundtrip", &track, TimelineStatus::Candidate);
    analysis.groups.push(SenseGroup {
        id: SenseGroupId::parse("sg-roundtrip-sg-2").unwrap(),
        sentence_id: track.sentences[0].id.clone(),
        group_index: 1,
        start_token_index: 1,
        end_token_index: 3,
        text: "round trip test".into(),
        label: Some("NP".into()),
        head_token_index: Some(2),
        confidence: 0.8,
        sources: vec![SenseGroupSource::Punctuation, SenseGroupSource::LengthLimit],
    });
    repo.save_sense_group_analysis(&analysis).unwrap();

    let loaded = repo
        .get_sense_group_analysis(&analysis.id)
        .unwrap()
        .expect("analysis should be saved");
    assert_eq!(loaded.id, analysis.id);
    assert_eq!(loaded.provider_id, "rule-based-sense-group");
    assert_eq!(loaded.algorithm, "punctuation_length_rule_v1");
    assert_eq!(loaded.groups.len(), 2);
    assert_eq!(loaded.groups[0].text, "hello");
    assert_eq!(loaded.groups[1].text, "round trip test");
    assert_eq!(loaded.groups[1].label, Some("NP".into()));
    assert_eq!(
        loaded.groups[1].sources,
        vec![SenseGroupSource::Punctuation, SenseGroupSource::LengthLimit]
    );
}

fn lltimeline_fixture() -> LLTimelineDocument {
    serde_json::from_str(include_str!(
        "../../../../testdata/lltimeline/v1-minimal.lltimeline.json"
    ))
    .unwrap()
}

fn lltimeline_import_services() -> (Arc<SqliteRepository>, application::MediaAnalysisUseCases) {
    let repo = Arc::new(SqliteRepository::in_memory().unwrap());
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_corpus_index_repository(repo.clone());
    (repo, services.media_analysis())
}

fn assert_no_lltimeline_import_rows(repo: &SqliteRepository) {
    let connection = repo.connection.lock();
    for table in [
        "media_items",
        "subtitle_tracks",
        "subtitle_sentences",
        "lltimeline_resources",
        "word_timeline_runs",
        "phone_timeline_runs",
        "chunk_timeline_runs",
        "sense_group_analysis_runs",
        "corpus_occurrences",
    ] {
        let count = connection
            .query_row(&format!("SELECT count(*) FROM {table}"), [], |row| {
                row.get::<_, u64>(0)
            })
            .unwrap();
        assert_eq!(count, 0, "{table} must remain empty after failed import");
    }
}

#[test]
fn lltimeline_validation_failures_happen_before_any_durable_write() {
    let mut cases = Vec::new();

    let mut wrong_source = lltimeline_fixture();
    wrong_source.word_timelines[0].track_id = SubtitleTrackId::parse("wrong-track").unwrap();
    cases.push(wrong_source);

    let mut missing_parent = lltimeline_fixture();
    missing_parent.word_timelines[0].parent_timeline_id =
        Some(WordTimelineId::parse("missing-parent").unwrap());
    cases.push(missing_parent);

    let mut missing_active = lltimeline_fixture();
    missing_active.active_word_timeline_id = Some(WordTimelineId::parse("missing-active").unwrap());
    cases.push(missing_active);

    for document in cases {
        let (repo, media) = lltimeline_import_services();
        assert!(media.import_lltimeline_document(document).is_err());
        assert_no_lltimeline_import_rows(&repo);
    }
}

#[test]
fn lltimeline_repository_and_reindex_failures_roll_back_the_whole_import() {
    for (table, operation) in [
        ("lltimeline_resources", "INSERT"),
        ("word_timeline_runs", "INSERT"),
        ("corpus_occurrences", "INSERT"),
    ] {
        let (repo, media) = lltimeline_import_services();
        repo.connection
            .lock()
            .execute_batch(&format!(
                "CREATE TRIGGER fail_import BEFORE {operation} ON {table}
                 BEGIN SELECT RAISE(ABORT, 'injected LLTimeline import failure'); END;"
            ))
            .unwrap();

        assert!(
            media
                .import_lltimeline_document(lltimeline_fixture())
                .is_err(),
            "{table} failure must reach the caller"
        );
        assert_no_lltimeline_import_rows(&repo);
    }
}

fn corpus_snapshot(repo: &SqliteRepository) -> Vec<String> {
    let connection = repo.connection.lock();
    let mut statement = connection
        .prepare(
            "SELECT json_object(
               'id',id,'language',language,'kind',kind,'normalized_key',normalized_key,
               'display_text',display_text,'media_id',media_id,'track_id',track_id,
               'sentence_id',sentence_id,'start_ms',start_ms,'end_ms',end_ms,
               'source_snapshot',source_snapshot
             )
             FROM corpus_occurrences ORDER BY id",
        )
        .unwrap();
    statement
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
}

#[test]
fn lltimeline_import_rebuilds_legacy_word_timings_and_canonical_corpus() {
    let (repo, media) = lltimeline_import_services();
    let track = media
        .import_lltimeline_document(lltimeline_fixture())
        .unwrap();
    let active = repo
        .active_word_timeline(&track.id)
        .unwrap()
        .expect("fixture has an active word timeline");
    let sentence_id = track.sentences[0].id.clone();
    assert_eq!(
        repo.get_word_timings(&sentence_id).unwrap(),
        active
            .words
            .iter()
            .filter(|word| word.sentence_id == sentence_id)
            .cloned()
            .collect::<Vec<_>>()
    );

    let mut reimport = media.export_lltimeline_document(&track.id).unwrap();
    let mut duplicate = reimport.rhythm_frames[0].clone();
    duplicate.id = RhythmFrameId::parse("untrusted-duplicate-frame").unwrap();
    duplicate.status = TimelineStatus::Archived;
    reimport.rhythm_frames.push(duplicate);
    media.import_lltimeline_document(reimport).unwrap();

    let imported = corpus_snapshot(&repo);
    media.rebuild_corpus_index().unwrap();
    assert_eq!(
        corpus_snapshot(&repo),
        imported,
        "import projection must equal the canonical subsequent rebuild"
    );

    let mut without_active = media.export_lltimeline_document(&track.id).unwrap();
    without_active.active_word_timeline_id = None;
    for timeline in &mut without_active.word_timelines {
        timeline.status = TimelineStatus::Candidate;
    }
    media.import_lltimeline_document(without_active).unwrap();
    assert!(
        repo.get_word_timings(&sentence_id).unwrap().is_empty(),
        "removing the active word timeline clears legacy compatibility rows"
    );
}

#[test]
fn lltimeline_cross_source_resource_id_reuse_rolls_back() {
    let (repo, media) = lltimeline_import_services();
    let original = media
        .import_lltimeline_document(lltimeline_fixture())
        .unwrap();
    let original_timeline = repo
        .active_word_timeline(&original.id)
        .unwrap()
        .expect("fixture active timeline");

    let mut conflicting = lltimeline_fixture();
    let other_media_id = MediaId::parse("other-media").unwrap();
    let other_track_id = SubtitleTrackId::parse("other-track").unwrap();
    conflicting.metadata.media.id = other_media_id.clone();
    conflicting.metadata.media.fingerprint = "other-media-fingerprint".into();
    conflicting.metadata.extra["track_id"] = serde_json::json!(other_track_id.as_str());
    conflicting.metadata.extra["track_fingerprint"] = serde_json::json!("other-track-fingerprint");
    conflicting.word_timelines[0].media_id = other_media_id.clone();
    conflicting.word_timelines[0].track_id = other_track_id;

    assert!(media.import_lltimeline_document(conflicting).is_err());
    assert!(
        repo.get(&other_media_id).unwrap().is_none(),
        "the conflicting import media write must roll back"
    );
    assert_eq!(
        repo.get_word_timeline(&original_timeline.id)
            .unwrap()
            .expect("original resource remains")
            .track_id,
        original.id
    );
}
