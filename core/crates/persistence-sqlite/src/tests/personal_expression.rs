use std::sync::Arc;

use application::{AppServices, PersonalExpressionRepository};
use domain::{
    LanguageCode, PatternSourceKind, PatternSourceSnapshot, PersonalExpressionAssistance,
    PersonalExpressionAttempt, PersonalExpressionAttemptId, PersonalExpressionChannel,
    PersonalExpressionSelfAssessment, RecordingAssetId, SemanticTaskAttemptId,
    UserSentencePatternAsset, UserSentencePatternId, UserSentencePatternSlot,
    UserSentencePatternVersion, UserSentencePatternVersionId,
};

use super::SqliteRepository;

fn asset() -> UserSentencePatternAsset {
    let id = UserSentencePatternId::parse("pattern-1").unwrap();
    UserSentencePatternAsset {
        id: id.clone(),
        language: LanguageCode::parse("en").unwrap(),
        source: PatternSourceSnapshot {
            kind: PatternSourceKind::Reading,
            text: "I ended up fixing it on Sunday.".into(),
            title: Some("A real source".into()),
            media_id: Some(domain::MediaId::parse("deleted-media").unwrap()),
            media_fingerprint: Some("immutable-media-fingerprint".into()),
            track_id: Some(domain::SubtitleTrackId::parse("deleted-track").unwrap()),
            sentence_id: Some(domain::SubtitleSentenceId::parse("deleted-sentence").unwrap()),
            semantic_attempt_id: None,
            start_ms: Some(100),
            end_ms: Some(200),
            candidate_ref: None,
        },
        current_version: UserSentencePatternVersion {
            id: UserSentencePatternVersionId::parse("pattern-version-1").unwrap(),
            pattern_id: id,
            version: 1,
            name: "I ended up".into(),
            pattern_text: "I ended up {result}.".into(),
            slots: vec![UserSentencePatternSlot {
                name: "result".into(),
                prompt: None,
                example_value: Some("fixing it on Sunday".into()),
                required: true,
            }],
            note: None,
            system_construction_id: None,
            created_at_ms: 1,
        },
        created_at_ms: 1,
        updated_at_ms: 1,
    }
}

fn long_term_writer_counts(repo: &SqliteRepository) -> (u32, u32, u32, u32) {
    let connection = repo.connection.lock().unwrap();
    let count = |table: &str| {
        connection
            .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                row.get::<_, u32>(0)
            })
            .unwrap()
    };
    (
        count("learning_observations"),
        count("lexical_capability_states"),
        count("lexical_capability_history"),
        count("upgrade_suggestions"),
    )
}

#[test]
fn durable_pattern_versions_and_channel_attempts_are_independent() {
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
    .with_personal_expression_repository(repo.clone());
    let use_cases = services.personal_expression();
    let original = use_cases.create(asset()).unwrap();
    assert_eq!(original.source.media_id.unwrap().as_str(), "deleted-media");

    let next = UserSentencePatternVersion {
        id: UserSentencePatternVersionId::parse("pattern-version-2").unwrap(),
        pattern_id: original.id.clone(),
        version: 2,
        name: "Ended up".into(),
        pattern_text: "I ended up {result} because {reason}.".into(),
        slots: vec![
            UserSentencePatternSlot {
                name: "result".into(),
                prompt: None,
                example_value: None,
                required: true,
            },
            UserSentencePatternSlot {
                name: "reason".into(),
                prompt: None,
                example_value: None,
                required: true,
            },
        ],
        note: Some("My weekend stories".into()),
        system_construction_id: None,
        created_at_ms: 2,
    };
    let revised = use_cases.revise(&original.id, next.clone(), 2).unwrap();
    assert_eq!(revised.source.text, original.source.text);
    assert_eq!(repo.list_pattern_versions(&original.id).unwrap().len(), 2);

    let before = long_term_writer_counts(&repo);
    for (channel, recording) in [
        (PersonalExpressionChannel::Writing, None),
        (
            PersonalExpressionChannel::Speaking,
            Some(RecordingAssetId::parse("recording-1").unwrap()),
        ),
    ] {
        use_cases
            .record_attempt(PersonalExpressionAttempt {
                id: PersonalExpressionAttemptId::parse(format!("attempt-{channel:?}")).unwrap(),
                pattern_id: original.id.clone(),
                pattern_version_id: next.id.clone(),
                channel,
                assistance: PersonalExpressionAssistance::NoText,
                response_text: "I ended up shipping the fix after dinner.".into(),
                raw_transcript: recording.as_ref().map(|_| "raw words".into()),
                recording_asset_id: recording,
                semantic_attempt_id: (channel == PersonalExpressionChannel::Speaking)
                    .then(|| SemanticTaskAttemptId::parse("semantic-speaking-1").unwrap()),
                self_assessment: PersonalExpressionSelfAssessment::PartlyExpressed,
                context_note: None,
                completed_at_ms: 3,
            })
            .unwrap();
    }
    let attempts = use_cases.attempts(&original.id).unwrap();
    assert_eq!(attempts.len(), 2);
    assert_ne!(attempts[0].channel, attempts[1].channel);
    assert_eq!(
        attempts
            .iter()
            .find(|attempt| attempt.channel == PersonalExpressionChannel::Speaking)
            .and_then(|attempt| attempt.semantic_attempt_id.as_ref())
            .map(SemanticTaskAttemptId::as_str),
        Some("semantic-speaking-1")
    );
    let after = long_term_writer_counts(&repo);
    assert_eq!(
        before, after,
        "3.16 attempts must not write observations, projections, or proposals"
    );
}

#[test]
fn writing_attempt_cannot_smuggle_speaking_recording() {
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
    .with_personal_expression_repository(repo);
    let use_cases = services.personal_expression();
    let pattern = use_cases.create(asset()).unwrap();
    let error = use_cases
        .record_attempt(PersonalExpressionAttempt {
            id: PersonalExpressionAttemptId::parse("bad").unwrap(),
            pattern_id: pattern.id,
            pattern_version_id: pattern.current_version.id,
            channel: PersonalExpressionChannel::Writing,
            assistance: PersonalExpressionAssistance::TemplateVisible,
            response_text: "my text".into(),
            raw_transcript: None,
            recording_asset_id: Some(RecordingAssetId::parse("wrong-channel").unwrap()),
            semantic_attempt_id: None,
            self_assessment: PersonalExpressionSelfAssessment::NeedsWork,
            context_note: None,
            completed_at_ms: 2,
        })
        .unwrap_err();
    assert!(error.to_string().contains("writing use cannot carry"));
}
