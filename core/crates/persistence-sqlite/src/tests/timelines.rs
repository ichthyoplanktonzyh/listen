use super::*;

fn content_package_candidate_fixture() -> ContentPackageCandidateImport {
    let mut document = lltimeline_fixture();
    let media = MediaItem {
        id: document.metadata.media.id.clone(),
        path: "/tmp/package-fixture.mp4".into(),
        fingerprint: document.metadata.media.fingerprint.clone(),
        title: document.metadata.media.title.clone(),
        kind: MediaKind::Video,
        duration: document.metadata.media.duration_ms.map(TimeMs::new),
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    let track = SubtitleTrack {
        id: SubtitleTrackId::parse(document.metadata.extra["track_id"].as_str().unwrap()).unwrap(),
        media_id: media.id.clone(),
        fingerprint: document.metadata.extra["track_fingerprint"]
            .as_str()
            .unwrap()
            .into(),
        language: document.metadata.language.clone(),
        source: "listen-resource-package-v1".into(),
        status: SubtitleTrackStatus::Available,
        sentences: document
            .segments
            .iter()
            .map(|segment| SubtitleSentence {
                id: segment.id.clone(),
                index: segment.index,
                start: TimeMs::new(segment.start_ms),
                end: TimeMs::new(segment.end_ms),
                original_text: segment.text.clone(),
                display_text: segment.display_text.clone(),
                tokens: segment
                    .tokens
                    .iter()
                    .map(|token| SubtitleToken {
                        index: token.index,
                        kind: token.kind,
                        text: token.text.clone(),
                        normalized: token.normalized.clone(),
                        start_char: token.start_char,
                        end_char: token.end_char,
                    })
                    .collect(),
            })
            .collect(),
    };
    for timeline in &mut document.word_timelines {
        timeline.status = TimelineStatus::Candidate;
    }
    for timeline in &mut document.phone_timelines {
        timeline.status = TimelineStatus::Candidate;
    }
    for timeline in &mut document.chunk_timelines {
        timeline.status = TimelineStatus::Candidate;
    }
    for analysis in &mut document.sense_group_analyses {
        analysis.status = TimelineStatus::Candidate;
    }
    for analysis in &mut document.prosody_analyses {
        analysis.status = TimelineStatus::Candidate;
    }
    ContentPackageCandidateImport {
        track,
        metadata: document.metadata,
        artifacts: document.artifacts,
        word_timelines: document.word_timelines,
        phone_timelines: document.phone_timelines,
        chunk_timelines: document.chunk_timelines,
        sense_group_analyses: document.sense_group_analyses,
        prosody_analyses: document.prosody_analyses,
        corpus_occurrences: Vec::new(),
    }
}

fn seed_content_package_media(repo: &SqliteRepository, import: &ContentPackageCandidateImport) {
    repo.upsert(&MediaItem {
        id: import.track.media_id.clone(),
        path: "/tmp/package-fixture.mp4".into(),
        fingerprint: import.metadata.media.fingerprint.clone(),
        title: import.metadata.media.title.clone(),
        kind: MediaKind::Video,
        duration: import.metadata.media.duration_ms.map(TimeMs::new),
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    })
    .unwrap();
}

#[test]
fn content_package_import_is_idempotent_and_never_selects_active() {
    let repo = SqliteRepository::in_memory().unwrap();
    let import = content_package_candidate_fixture();
    seed_content_package_media(&repo, &import);
    let track_id = import.track.id.clone();
    repo.import_content_package_candidates(&import).unwrap();
    let track_before = repo.get_track(&track_id).unwrap().unwrap();
    repo.import_content_package_candidates(&import).unwrap();

    assert_eq!(repo.get_track(&track_id).unwrap().unwrap(), track_before);
    assert_eq!(repo.list_word_timelines(&track_id).unwrap().len(), 1);
    assert_eq!(repo.list_phone_timelines(&track_id).unwrap().len(), 0);
    assert_eq!(repo.list_sense_group_analyses(&track_id).unwrap().len(), 0);
    assert!(repo.active_word_timeline(&track_id).unwrap().is_none());
    assert!(repo.active_phone_timeline(&track_id).unwrap().is_none());
    assert!(
        repo.active_sense_group_analysis(&track_id)
            .unwrap()
            .is_none()
    );
}

#[test]
fn content_package_import_preserves_existing_active_bytes_and_adds_candidate() {
    let repo = SqliteRepository::in_memory().unwrap();
    let import = content_package_candidate_fixture();
    seed_content_package_media(&repo, &import);
    let track_id = import.track.id.clone();
    repo.import_content_package_candidates(&import).unwrap();
    let original = repo.list_word_timelines(&track_id).unwrap().remove(0);
    let active = repo.activate_word_timeline(&original.id).unwrap();
    let active_json = serde_json::to_value(&active).unwrap();
    let track_before = repo.get_track(&track_id).unwrap().unwrap();
    let corpus_before = corpus_count_for_track(&repo, &track_id);

    let mut additional = import;
    additional.word_timelines[0].id =
        WordTimelineId::parse("additional-package-candidate").unwrap();
    additional.track.sentences.clear();
    repo.import_content_package_candidates(&additional).unwrap();

    let timelines = repo.list_word_timelines(&track_id).unwrap();
    assert_eq!(timelines.len(), 2);
    assert_eq!(
        serde_json::to_value(repo.active_word_timeline(&track_id).unwrap().unwrap()).unwrap(),
        active_json
    );
    assert_eq!(repo.get_track(&track_id).unwrap().unwrap(), track_before);
    assert_eq!(corpus_count_for_track(&repo, &track_id), corpus_before);
    assert!(
        timelines
            .iter()
            .any(|value| { value.id != active.id && value.status == TimelineStatus::Candidate })
    );
}

#[test]
fn content_package_cross_source_resource_conflict_rolls_back_every_write() {
    let repo = SqliteRepository::in_memory().unwrap();
    let import = content_package_candidate_fixture();
    seed_content_package_media(&repo, &import);
    repo.import_content_package_candidates(&import).unwrap();
    let original = import.word_timelines[0].clone();
    let other_media = MediaItem {
        id: MediaId::parse("content-package-other-media").unwrap(),
        fingerprint: "other-content-package-fingerprint".into(),
        path: "/tmp/other.mp4".into(),
        title: "Other".into(),
        kind: MediaKind::Video,
        duration: None,
        availability: MediaAvailability::Available,
        created_at_ms: 2,
        updated_at_ms: 2,
    };
    repo.upsert(&other_media).unwrap();
    let media_before = repo.get(&other_media.id).unwrap().unwrap();
    let mut other_track = import.track;
    other_track.id = SubtitleTrackId::parse("content-package-other-track").unwrap();
    other_track.media_id = other_media.id.clone();
    other_track.fingerprint = "other-track-fingerprint".into();
    other_track.sentences.clear();
    let mut conflicting = original;
    conflicting.track_id = other_track.id.clone();
    conflicting.media_id = other_media.id.clone();

    let result = repo.import_content_package_candidates(&ContentPackageCandidateImport {
        track: other_track.clone(),
        metadata: import.metadata,
        artifacts: Vec::new(),
        word_timelines: vec![conflicting],
        phone_timelines: Vec::new(),
        chunk_timelines: Vec::new(),
        sense_group_analyses: Vec::new(),
        prosody_analyses: Vec::new(),
        corpus_occurrences: Vec::new(),
    });
    assert!(result.is_err());
    assert_eq!(repo.get(&other_media.id).unwrap().unwrap(), media_before);
    assert!(repo.get_track(&other_track.id).unwrap().is_none());
}

#[test]
fn content_package_sentence_ownership_conflict_rolls_back_without_moving_sentence() {
    let repo = SqliteRepository::in_memory().unwrap();
    let import = content_package_candidate_fixture();
    seed_content_package_media(&repo, &import);
    repo.import_content_package_candidates(&import).unwrap();
    let original_track = repo.get_track(&import.track.id).unwrap().unwrap();
    let sentence_id = original_track.sentences[0].id.clone();
    let word_count = repo.list_word_timelines(&import.track.id).unwrap().len();

    let other_media = MediaItem {
        id: MediaId::parse("sentence-conflict-media").unwrap(),
        path: "/tmp/sentence-conflict.mp4".into(),
        fingerprint: "sentence-conflict-media-fingerprint".into(),
        title: "Sentence conflict".into(),
        kind: MediaKind::Video,
        duration: None,
        availability: MediaAvailability::Available,
        created_at_ms: 3,
        updated_at_ms: 3,
    };
    repo.upsert(&other_media).unwrap();
    let mut conflict = content_package_candidate_fixture();
    conflict.track.id = SubtitleTrackId::parse("sentence-conflict-track").unwrap();
    conflict.track.media_id = other_media.id.clone();
    conflict.track.fingerprint = "sentence-conflict-track-fingerprint".into();
    conflict.word_timelines[0].id = WordTimelineId::parse("sentence-conflict-word").unwrap();
    conflict.word_timelines[0].track_id = conflict.track.id.clone();
    conflict.word_timelines[0].media_id = other_media.id.clone();

    assert!(repo.import_content_package_candidates(&conflict).is_err());
    assert_eq!(
        repo.sentence_track_id(&sentence_id).unwrap(),
        Some(original_track.id.clone())
    );
    assert_eq!(
        repo.get_track(&original_track.id).unwrap().unwrap(),
        original_track
    );
    assert!(repo.get_track(&conflict.track.id).unwrap().is_none());
    assert_eq!(
        repo.list_word_timelines(&original_track.id).unwrap().len(),
        word_count
    );
    assert_eq!(corpus_count_for_track(&repo, &conflict.track.id), 0);
}

#[test]
fn content_package_enriched_reimport_merges_artifacts_idempotently() {
    let repo = SqliteRepository::in_memory().unwrap();
    let mut import = content_package_candidate_fixture();
    seed_content_package_media(&repo, &import);
    import.artifacts = vec![LLTimelineArtifact {
        kind: "fixture".into(),
        provider_id: Some("first".into()),
        provider_version: Some("1".into()),
        payload: serde_json::json!({"resource_id": "artifact-first", "value": 1}),
    }];
    repo.import_content_package_candidates(&import).unwrap();
    let original_metadata = repo
        .get_lltimeline_resource(&import.track.id)
        .unwrap()
        .unwrap()
        .0;

    let mut enriched = import.clone();
    enriched.artifacts = vec![LLTimelineArtifact {
        kind: "rhythm_word_acoustic_cues".into(),
        provider_id: Some("acoustics".into()),
        provider_version: Some("1".into()),
        payload: serde_json::json!({"resource_id": "artifact-acoustics", "cues": []}),
    }];
    repo.import_content_package_candidates(&enriched).unwrap();
    repo.import_content_package_candidates(&enriched).unwrap();

    let (metadata, artifacts) = repo
        .get_lltimeline_resource(&import.track.id)
        .unwrap()
        .unwrap();
    assert_eq!(metadata, original_metadata);
    assert_eq!(artifacts.len(), 2);
    assert!(
        artifacts
            .iter()
            .any(|value| { value.payload["resource_id"] == serde_json::json!("artifact-first") })
    );
    assert!(
        artifacts.iter().any(|value| {
            value.payload["resource_id"] == serde_json::json!("artifact-acoustics")
        })
    );
}

#[test]
fn public_content_package_use_case_inspects_projects_and_imports_atomically() {
    let (repo, media) = lltimeline_import_services();
    let source = MediaItem {
        id: MediaId::parse("content-package-media").unwrap(),
        path: "/tmp/content-package-media.mp4".into(),
        fingerprint: format!("sha256:{}", "a".repeat(64)),
        title: "Content package media".into(),
        kind: MediaKind::Video,
        duration: Some(TimeMs::new(2_500)),
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    repo.upsert(&source).unwrap();
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../contracts/content-package/v1/examples/minimal");

    let first = media
        .import_content_package_path(&source.id, &path)
        .unwrap();
    let second = media
        .import_content_package_path(&source.id, &path)
        .unwrap();

    assert_eq!(first.track.id, second.track.id);
    assert_eq!(repo.list_word_timelines(&first.track.id).unwrap().len(), 1);
    assert!(
        repo.active_word_timeline(&first.track.id)
            .unwrap()
            .is_none()
    );
    assert!(corpus_count_for_track(&repo, &first.track.id) > 0);
}

#[test]
fn public_content_package_reimport_returns_the_preserved_archived_track() {
    let (repo, media) = lltimeline_import_services();
    let source = MediaItem {
        id: MediaId::parse("content-package-archived-media").unwrap(),
        path: "/tmp/content-package-archived.mp4".into(),
        fingerprint: format!("sha256:{}", "a".repeat(64)),
        title: "Archived package media".into(),
        kind: MediaKind::Video,
        duration: Some(TimeMs::new(2_500)),
        availability: MediaAvailability::Available,
        created_at_ms: 1,
        updated_at_ms: 1,
    };
    repo.upsert(&source).unwrap();
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../contracts/content-package/v1/examples/minimal");
    let first = media
        .import_content_package_path(&source.id, &path)
        .unwrap();
    let archived = repo
        .set_track_status(&first.track.id, SubtitleTrackStatus::Archived)
        .unwrap();

    let repeated = media
        .import_content_package_path(&source.id, &path)
        .unwrap();

    assert_eq!(repeated.track, archived);
    assert_eq!(
        repo.get_track(&first.track.id).unwrap().unwrap().status,
        SubtitleTrackStatus::Archived
    );
    assert_eq!(repo.list_word_timelines(&first.track.id).unwrap().len(), 1);
    assert!(
        repo.active_word_timeline(&first.track.id)
            .unwrap()
            .is_none()
    );
}

fn corpus_count_for_track(repo: &SqliteRepository, track_id: &SubtitleTrackId) -> u64 {
    repo.connection
        .lock()
        .query_row(
            "SELECT count(*) FROM corpus_occurrences WHERE track_id=?1",
            [track_id.as_str()],
            |row| row.get(0),
        )
        .unwrap()
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

    let prosody_active =
        prosody_analysis("prosody-active-unique-1", &track, TimelineStatus::Active);
    let prosody_duplicate =
        prosody_analysis("prosody-active-unique-2", &track, TimelineStatus::Active);
    repo.save_prosody_analysis(&prosody_active).unwrap();
    assert!(repo.save_prosody_analysis(&prosody_duplicate).is_err());
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

fn prosody_analysis(id: &str, track: &SubtitleTrack, status: TimelineStatus) -> ProsodyAnalysis {
    ProsodyAnalysis {
        id: ProsodyAnalysisId::parse(id).unwrap(),
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        parent_word_timeline_id: None,
        provider_id: "listen-gen".into(),
        provider_version: "0.1.0".into(),
        algorithm: "prosody-v1".into(),
        status,
        created_by: TimelineCreator::Algorithm,
        metrics_json: serde_json::json!({}).into(),
        chunks: vec![domain::ProsodicChunk {
            sentence_id: track.sentences[0].id.clone(),
            chunk_index: 0,
            start_token_index: 0,
            end_token_index: 0,
            nucleus_token_index: Some(0),
            confidence: 0.9,
        }],
        anchors: vec![ProsodyAnchor {
            word_ref: ProsodyWordRef {
                sentence_id: track.sentences[0].id.clone(),
                token_index: 0,
            },
            syllable_index: None,
            lexical_stress: LexicalStress::Primary,
            realized_prominence: 0.8,
            utterance_role: UtteranceRole::Nucleus,
            evidence: vec![ProsodyEvidence::Energy, ProsodyEvidence::Pitch],
            confidence: 0.9,
        }],
        created_at_ms: 1,
        updated_at_ms: 1,
    }
}

#[test]
fn activating_prosody_analysis_updates_active_resource() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let older = prosody_analysis("prosody-analysis-1", &track, TimelineStatus::Active);
    let newer = prosody_analysis("prosody-analysis-2", &track, TimelineStatus::Candidate);
    repo.save_prosody_analysis(&older).unwrap();
    repo.save_prosody_analysis(&newer).unwrap();

    let active = repo.activate_prosody_analysis(&newer.id).unwrap();
    assert_eq!(active.status, TimelineStatus::Active);
    assert_eq!(
        repo.active_prosody_analysis(&track.id).unwrap().unwrap().id,
        newer.id
    );
    assert_eq!(
        repo.get_prosody_analysis(&older.id)
            .unwrap()
            .unwrap()
            .status,
        TimelineStatus::Candidate
    );
    assert_eq!(repo.list_prosody_analyses(&track.id).unwrap().len(), 2);
}

#[test]
fn archiving_and_deleting_prosody_analysis_updates_repository() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();
    let analysis = prosody_analysis("prosody-analysis-delete", &track, TimelineStatus::Candidate);
    repo.save_prosody_analysis(&analysis).unwrap();

    let archived = repo.archive_prosody_analysis(&analysis.id).unwrap();
    assert_eq!(archived.status, TimelineStatus::Archived);
    assert!(repo.activate_prosody_analysis(&analysis.id).is_err());
    let deleted = repo.delete_prosody_analysis(&analysis.id).unwrap();
    assert_eq!(deleted.id, analysis.id);
    assert!(repo.get_prosody_analysis(&analysis.id).unwrap().is_none());
}

#[test]
fn prosody_analysis_json_round_trip() {
    let repo = SqliteRepository::in_memory().unwrap();
    MediaRepository::upsert(&repo, &transcription_media()).unwrap();
    let track = word_timeline_track();
    repo.save_track(&track).unwrap();

    let mut analysis = prosody_analysis("prosody-roundtrip", &track, TimelineStatus::Candidate);
    analysis.anchors.push(ProsodyAnchor {
        word_ref: ProsodyWordRef {
            sentence_id: track.sentences[0].id.clone(),
            token_index: 1,
        },
        syllable_index: Some(0),
        lexical_stress: LexicalStress::Secondary,
        realized_prominence: 0.4,
        utterance_role: UtteranceRole::Prenuclear,
        evidence: vec![ProsodyEvidence::Duration],
        confidence: 0.7,
    });
    repo.save_prosody_analysis(&analysis).unwrap();

    let loaded = repo
        .get_prosody_analysis(&analysis.id)
        .unwrap()
        .expect("analysis should be saved");
    assert_eq!(loaded.id, analysis.id);
    assert_eq!(loaded.provider_id, "listen-gen");
    assert_eq!(loaded.anchors.len(), 2);
    assert_eq!(loaded.anchors[0].utterance_role, UtteranceRole::Nucleus);
    assert_eq!(
        loaded.anchors[0].evidence,
        vec![ProsodyEvidence::Energy, ProsodyEvidence::Pitch]
    );
    assert_eq!(loaded.anchors[1].lexical_stress, LexicalStress::Secondary);
    assert_eq!(loaded.anchors[1].syllable_index, Some(0));
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
        "prosody_analysis_runs",
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
