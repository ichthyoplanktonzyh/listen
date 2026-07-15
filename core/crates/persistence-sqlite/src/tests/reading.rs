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
