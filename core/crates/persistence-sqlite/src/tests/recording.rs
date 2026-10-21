use super::*;
use application::{
    AppServices, CompleteShadowingAttempt, CreatePracticeItem, CreatePracticeSession,
    CreateRecordingAsset,
};
use domain::{
    PlayableSegment, PlayableSegmentAvailability, PracticeKind, PracticeMode, PracticeTarget,
    PracticeTargetKind, RecordingAudioMetadata,
};
use std::sync::Arc;

#[test]
fn shadowing_completion_links_recording_without_claiming_a_score_or_observation() {
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
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_recording_repository(repo.clone());

    let target = PracticeTarget {
        kind: PracticeTargetKind::Sentence,
        id: Some("cue-1".into()),
        sentence_id: Some(domain::SubtitleSentenceId::parse("cue-1").unwrap()),
        start_ms: Some(100),
        end_ms: Some(900),
    };
    let session = services
        .practice_learning()
        .create_practice_session(CreatePracticeSession {
            mode: PracticeMode::Intensive,
            media_id: None,
            track_id: None,
            source: Some("shadowing_test".into()),
        })
        .unwrap();
    let item = services
        .practice_learning()
        .create_practice_item(CreatePracticeItem {
            session_id: Some(session.id),
            kind: PracticeKind::Shadowing,
            target: target.clone(),
            prompt_snapshot: "A learner-selected source line.".into(),
            expected_text: "A learner-selected source line.".into(),
            anchors: Vec::new(),
        })
        .unwrap();
    let recording = services
        .recordings()
        .create_recording_asset(CreateRecordingAsset {
            file_path: "/tmp/shadowing-test.wav".into(),
            duration_ms: 800,
            target,
            source_segment: PlayableSegment {
                media_id: None,
                start_ms: 100,
                end_ms: 900,
                label: "A learner-selected source line.".into(),
                subtitle_snapshot: "A learner-selected source line.".into(),
                availability: PlayableSegmentAvailability::MissingMedia,
            },
            language: domain::LanguageCode::parse("en").unwrap(),
            audio: RecordingAudioMetadata {
                container: "wav".into(),
                codec: "pcm_s16le".into(),
                sample_rate_hz: 16_000,
                channels: 1,
                sample_format: "s16".into(),
                byte_length: 4,
                content_sha256: "a".repeat(64),
            },
            recorder_version: "test-recorder".into(),
        })
        .unwrap();

    let attempt = services
        .recordings()
        .complete_shadowing_attempt(CompleteShadowingAttempt {
            item_id: item.id,
            recording_id: recording.id.clone(),
        })
        .unwrap();
    assert_eq!(attempt.result, domain::PracticeResult::Completed);
    assert_eq!(attempt.score, None);
    assert!(attempt.generated_observation_ids.is_empty());
    assert!(attempt.generated_review_item_ids.is_empty());

    let saved_recording = services
        .recordings()
        .recording_asset(&recording.id)
        .unwrap()
        .unwrap();
    assert_eq!(saved_recording.practice_attempt_id, Some(attempt.id));
    let connection = repo.connection.lock();
    let observations: i64 = connection
        .query_row("SELECT COUNT(*) FROM learning_observations", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(observations, 0);
    let review_items: i64 = connection
        .query_row("SELECT COUNT(*) FROM review_items", [], |row| row.get(0))
        .unwrap();
    assert_eq!(review_items, 0);
}
