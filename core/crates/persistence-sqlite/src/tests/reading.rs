use application::ReadingPositionRepository;
use domain::ReadingPosition;

use super::*;

#[test]
fn reading_position_round_trips_and_upserts() {
    let repo = SqliteRepository::in_memory().unwrap();
    let track_id = SubtitleTrackId::parse("track-1").unwrap();
    assert_eq!(repo.get_reading_position(&track_id).unwrap(), None);

    let position = ReadingPosition {
        track_id: track_id.clone(),
        media_id: Some(MediaId::parse("media-1").unwrap()),
        anchor_cue_id: SubtitleSentenceId::parse("cue-a").unwrap(),
        paragraph_index: 3,
        updated_at_ms: 10,
    };
    repo.save_reading_position(&position).unwrap();
    assert_eq!(
        repo.get_reading_position(&track_id).unwrap(),
        Some(position)
    );

    // The cursor is one overwritable row per track: a later save replaces the
    // anchor instead of accumulating history (deliberately not append-only).
    let moved = ReadingPosition {
        track_id: track_id.clone(),
        media_id: None,
        anchor_cue_id: SubtitleSentenceId::parse("cue-b").unwrap(),
        paragraph_index: 7,
        updated_at_ms: 20,
    };
    repo.save_reading_position(&moved).unwrap();
    assert_eq!(repo.get_reading_position(&track_id).unwrap(), Some(moved));
}

#[test]
fn reading_positions_are_independent_per_track() {
    let repo = SqliteRepository::in_memory().unwrap();
    let track_a = SubtitleTrackId::parse("track-a").unwrap();
    let track_b = SubtitleTrackId::parse("track-b").unwrap();
    let position_a = ReadingPosition {
        track_id: track_a.clone(),
        media_id: None,
        anchor_cue_id: SubtitleSentenceId::parse("cue-1").unwrap(),
        paragraph_index: 0,
        updated_at_ms: 5,
    };
    repo.save_reading_position(&position_a).unwrap();
    assert_eq!(repo.get_reading_position(&track_b).unwrap(), None);
    assert_eq!(
        repo.get_reading_position(&track_a).unwrap(),
        Some(position_a)
    );
}

#[test]
fn reading_use_case_rejects_empty_anchor() {
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
    .with_reading_position_repository(repo.clone());
    let result = services
        .reading()
        .save_reading_position("track-1", None, "  ", 0);
    assert!(matches!(
        result,
        Err(application::ApplicationError::Invalid(_))
    ));
}

fn observation_count(repo: &SqliteRepository, table: &str) -> i64 {
    repo.connection
        .lock()
        .unwrap()
        .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
            row.get(0)
        })
        .unwrap()
}

#[test]
fn reading_marking_writes_one_reading_observation_and_nothing_else() {
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
    );
    let entry = upsert_word_asset(&services, "en", "quake", "quake", None, None);
    let sentence_id = SubtitleSentenceId::parse("cue-1").unwrap();

    services
        .lexical_learning()
        .record_reading_marking(
            &entry.entry.id,
            Some(&sentence_id),
            "quakes",
            None,
            true,
            false,
        )
        .unwrap();

    let reading = repo
        .list_learning_observations(&entry.entry.id, Some(LexicalCapability::Reading), 10, 0)
        .unwrap();
    assert_eq!(reading.len(), 1);
    let observation = &reading[0];
    assert_eq!(observation.capability, LexicalCapability::Reading);
    assert_eq!(
        observation.task_type,
        domain::ObservationTaskType::ReadingContextMarking
    );
    assert_eq!(observation.outcome, domain::ObservationOutcome::Failure);
    // Translation was visible, so this can never alone support acquired.
    assert_eq!(observation.assistance, domain::AssistanceLevel::FullText);
    assert_eq!(observation.surface_form.as_deref(), Some("quakes"));
    assert_eq!(observation.origin, domain::ObservationOrigin::UserMarking);

    // Negative wall: the reading mark never leaks into the listening
    // channel, the legacy observation table, projections, or history.
    let listening = repo
        .list_learning_observations(&entry.entry.id, Some(LexicalCapability::Listening), 10, 0)
        .unwrap();
    assert!(listening.is_empty());
    assert_eq!(observation_count(&repo, "lexical_observations"), 0);
    assert_eq!(observation_count(&repo, "lexical_capability_states"), 0);
    assert_eq!(observation_count(&repo, "lexical_capability_history"), 0);
}

#[test]
fn reading_marking_without_translation_is_unassisted_success() {
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
    );
    let entry = upsert_word_asset(&services, "en", "strike", "strike", None, None);
    services
        .lexical_learning()
        .record_reading_marking(&entry.entry.id, None, "struck", None, false, true)
        .unwrap();
    let reading = repo
        .list_learning_observations(&entry.entry.id, Some(LexicalCapability::Reading), 10, 0)
        .unwrap();
    assert_eq!(reading.len(), 1);
    assert_eq!(reading[0].assistance, domain::AssistanceLevel::None);
    assert_eq!(reading[0].outcome, domain::ObservationOutcome::Success);
    assert_eq!(reading[0].sentence_id, None);
}

#[test]
fn reading_marking_rejects_unknown_entry() {
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
    );
    let missing = LexicalEntryId::parse("no-such-entry").unwrap();
    let result = services
        .lexical_learning()
        .record_reading_marking(&missing, None, "word", None, false, true);
    assert!(matches!(
        result,
        Err(application::ApplicationError::NotFound(_))
    ));
    assert_eq!(observation_count(&repo, "learning_observations"), 0);
}
