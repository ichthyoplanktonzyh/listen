use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use application::{
    CreateLearningPreparationRun, ExactAudioTrack, FoundationAssetAvailability, FoundationInputs,
    FoundationPreparationInspector, FoundationPreparationIntent, FoundationPreparationRequest,
    FoundationPreparationTarget, FoundationSourceInspection, LearningPreparationRunRepository,
    LearningPreparationRunStatus, LearningPreparationRunTransition, LearningPreparationUseCases,
    PreparationConsent, PreparationReadiness, PreparationStepState, PrepareFoundationResult,
    ReusableFoundationArtifact, SelectionRequiredReason, WordTimelinePrecision,
};
use domain::{MediaId, SubtitleTrackId};

use crate::SqliteRepository;

struct ScriptedFoundationAdapter {
    inspections: AtomicUsize,
    result: FoundationSourceInspection,
}

impl ScriptedFoundationAdapter {
    fn selected() -> Self {
        Self {
            inspections: AtomicUsize::new(0),
            result: FoundationSourceInspection::Selected(FoundationInputs {
                word_timeline: FoundationAssetAvailability::Reusable(ReusableFoundationArtifact {
                    artifact_ref: "word-active".into(),
                    input_fingerprint: "word-fp".into(),
                }),
                word_timeline_precision: WordTimelinePrecision::Exact,
                sound_line: FoundationAssetAvailability::Buildable {
                    requires_download: true,
                },
                chunk_timeline: FoundationAssetAvailability::Buildable {
                    requires_download: false,
                },
                rule_sense_group: FoundationAssetAvailability::Buildable {
                    requires_download: false,
                },
            }),
        }
    }
}

impl FoundationPreparationInspector for ScriptedFoundationAdapter {
    fn inspect(
        &self,
        _target: &FoundationPreparationTarget,
    ) -> Result<FoundationSourceInspection, application::ApplicationError> {
        self.inspections.fetch_add(1, Ordering::SeqCst);
        Ok(self.result.clone())
    }
}

fn target(media_fingerprint: &str) -> FoundationPreparationTarget {
    FoundationPreparationTarget {
        media_id: MediaId::parse("media").unwrap(),
        media_fingerprint: media_fingerprint.into(),
        subtitle_track_id: SubtitleTrackId::parse("track").unwrap(),
        subtitle_fingerprint: "subtitle-fp".into(),
        audio_track: ExactAudioTrack {
            stream_index: 0,
            fingerprint: "audio-fp".into(),
        },
    }
}

fn request(allow_downloads: bool) -> FoundationPreparationRequest {
    FoundationPreparationRequest {
        intent: FoundationPreparationIntent::RecommendedFoundation,
        consent: PreparationConsent { allow_downloads },
    }
}

fn prepared(
    use_cases: &LearningPreparationUseCases,
    media_fingerprint: &str,
    now_ms: u64,
) -> application::LearningPreparationRun {
    match use_cases
        .prepare(target(media_fingerprint), request(false), now_ms)
        .unwrap()
    {
        PrepareFoundationResult::Run(run) => *run,
        other => panic!("expected run, got {other:?}"),
    }
}

#[test]
fn sqlite_is_single_flight_authority_for_concurrent_prepare() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let adapter = Arc::new(ScriptedFoundationAdapter::selected());
    let use_cases = Arc::new(LearningPreparationUseCases::new(
        repository.clone(),
        adapter,
    ));

    let handles = (0..8)
        .map(|index| {
            let use_cases = use_cases.clone();
            std::thread::spawn(move || prepared(&use_cases, "media-fp", 100 + index))
        })
        .collect::<Vec<_>>();
    let runs = handles
        .into_iter()
        .map(|handle| handle.join().unwrap())
        .collect::<Vec<_>>();

    assert!(runs.windows(2).all(|pair| pair[0].id == pair[1].id));
    let count: u64 = repository
        .connection
        .lock()
        .query_row(
            "SELECT COUNT(*) FROM learning_preparation_runs",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn changed_input_invalidates_active_run_before_creating_replacement() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let first = prepared(&use_cases, "media-fp-v1", 100);
    let second = prepared(&use_cases, "media-fp-v2", 200);

    assert_ne!(first.id, second.id);
    assert_eq!(
        repository.get(&first.id).unwrap().unwrap().status,
        LearningPreparationRunStatus::Failed
    );
    assert_eq!(
        repository.get(&first.id).unwrap().unwrap().error.as_deref(),
        Some("preparation inputs or plan changed")
    );
}

#[test]
fn consent_and_selection_are_resolved_before_any_child_work_is_planned() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let selected = Arc::new(ScriptedFoundationAdapter::selected());
    let selected_use_cases = LearningPreparationUseCases::new(repository.clone(), selected.clone());
    let run = prepared(&selected_use_cases, "media-fp", 100);
    assert_eq!(
        run.plan.sound_line.state,
        PreparationStepState::Skipped {
            reason: "download_consent_required".into()
        }
    );

    let ambiguous_repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let ambiguous = Arc::new(ScriptedFoundationAdapter {
        inspections: AtomicUsize::new(0),
        result: FoundationSourceInspection::SelectionRequired {
            reason: SelectionRequiredReason::AudioTrackAmbiguous,
        },
    });
    let ambiguous_use_cases =
        LearningPreparationUseCases::new(ambiguous_repository.clone(), ambiguous.clone());
    assert_eq!(
        ambiguous_use_cases
            .prepare(target("media-fp"), request(true), 100)
            .unwrap(),
        PrepareFoundationResult::SelectionRequired(SelectionRequiredReason::AudioTrackAmbiguous)
    );
    let count: u64 = ambiguous_repository
        .connection
        .lock()
        .query_row(
            "SELECT COUNT(*) FROM learning_preparation_runs",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0);
    assert_eq!(ambiguous.inspections.load(Ordering::SeqCst), 1);
}

#[test]
fn partial_optional_failure_does_not_promote_real_listening_flow_or_fail_parent() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let mut run = prepared(&use_cases, "media-fp", 100);
    let expected = run.revision;
    run.start(110).unwrap();
    run.plan.sound_line.state = PreparationStepState::Failed {
        reason: "sound-line model failed".into(),
    };
    run.plan.chunk_timeline.state = PreparationStepState::Ready {
        artifact_ref: "chunk-from-word".into(),
        input_fingerprint: "chunk-fp".into(),
        reused: false,
    };
    run.plan.rule_sense_group.state = PreparationStepState::Ready {
        artifact_ref: "sense-rule".into(),
        input_fingerprint: "sense-fp".into(),
        reused: false,
    };
    run.settle(120);

    assert_eq!(run.status, LearningPreparationRunStatus::Completed);
    assert!(!matches!(
        run.plan.sound_line.state,
        PreparationStepState::Ready { .. }
    ));
    assert!(matches!(
        repository.transition(expected, &run).unwrap(),
        LearningPreparationRunTransition::Applied(_)
    ));
}

#[test]
fn typed_state_machine_enforces_foundation_dependencies() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository,
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let mut run = match use_cases
        .prepare(target("media-fp"), request(true), 100)
        .unwrap()
    {
        PrepareFoundationResult::Run(run) => run,
        other => panic!("expected run, got {other:?}"),
    };
    run.start(110).unwrap();

    assert!(run.begin_chunk_timeline(120).is_err());
    run.begin_rule_sense_group(121).unwrap();
    run.begin_sound_line("sound-line-job", 122).unwrap();
    run.complete_sound_line(
        ReusableFoundationArtifact {
            artifact_ref: "sound-line".into(),
            input_fingerprint: "sound-fp".into(),
        },
        123,
    )
    .unwrap();
    run.begin_chunk_timeline(124).unwrap();
}

#[test]
fn estimated_words_support_following_but_never_real_listening_flow() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository,
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let mut run = prepared(&use_cases, "media-fp", 100);
    run.plan.word_timeline.precision = WordTimelinePrecision::Estimated;
    run.plan.sound_line.state = PreparationStepState::Ready {
        artifact_ref: "sound-line".into(),
        input_fingerprint: "sound-fp".into(),
        reused: false,
    };
    run.plan.chunk_timeline.state = PreparationStepState::Ready {
        artifact_ref: "chunk".into(),
        input_fingerprint: "chunk-fp".into(),
        reused: false,
    };

    let readiness = run.readiness();
    assert_eq!(readiness.word_following, PreparationReadiness::Ready);
    assert_eq!(
        readiness.real_listening_flow,
        PreparationReadiness::Unavailable {
            reason: "estimated_word_timeline".into()
        }
    );
}

#[test]
fn restart_cancel_and_retry_preserve_completed_slots() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let mut run = prepared(&use_cases, "media-fp", 100);
    let expected = run.revision;
    run.start(110).unwrap();
    run.plan.chunk_timeline.state = PreparationStepState::Running;
    assert!(matches!(
        repository.transition(expected, &run).unwrap(),
        LearningPreparationRunTransition::Applied(_)
    ));

    let recovered = use_cases.recover_startup(120).unwrap();
    assert_eq!(recovered.len(), 1);
    assert_eq!(recovered[0].status, LearningPreparationRunStatus::Queued);
    assert_eq!(
        recovered[0].plan.chunk_timeline.state,
        PreparationStepState::Pending
    );
    assert!(matches!(
        recovered[0].plan.word_timeline.state,
        PreparationStepState::Ready { reused: true, .. }
    ));

    let cancelling = use_cases.cancel(&run.id, 130).unwrap();
    let expected = cancelling.revision;
    let mut cancelled = cancelling;
    cancelled.finish_cancellation(140);
    assert!(matches!(
        repository.transition(expected, &cancelled).unwrap(),
        LearningPreparationRunTransition::Applied(_)
    ));
    let retry = use_cases.retry(&run.id, 150).unwrap();
    assert_eq!(
        retry.retry_of_run_id.as_ref().map(|id| id.as_str()),
        Some(run.id.as_str())
    );
    assert!(matches!(
        retry.plan.word_timeline.state,
        PreparationStepState::Ready { reused: true, .. }
    ));
    assert_eq!(
        retry.plan.chunk_timeline.state,
        PreparationStepState::Pending
    );
}

#[test]
fn restart_preserves_an_acknowledged_cancellation_request() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let run = prepared(&use_cases, "media-fp", 100);
    let cancelling = use_cases.cancel(&run.id, 110).unwrap();

    let recovered = use_cases.recover_startup(120).unwrap();

    assert_eq!(recovered, vec![cancelling]);
    assert_eq!(
        repository.get(&run.id).unwrap().unwrap().status,
        LearningPreparationRunStatus::Cancelling
    );
}

#[test]
fn stale_revision_cannot_overwrite_cancellation() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let stale = prepared(&use_cases, "media-fp", 100);
    let cancelled = use_cases.cancel(&stale.id, 110).unwrap();
    let mut stale_completion = stale.clone();
    stale_completion.status = LearningPreparationRunStatus::Completed;
    stale_completion.revision += 1;
    assert_eq!(
        repository
            .transition(stale.revision, &stale_completion)
            .unwrap(),
        LearningPreparationRunTransition::Rejected(cancelled)
    );
}

#[test]
fn repository_rejects_mutated_target_identity() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let mut run = prepared(&use_cases, "media-fp", 100);
    run.target.media_fingerprint = "changed-outside-planner".into();
    run.revision += 1;

    assert!(matches!(
        repository.transition(0, &run),
        Err(application::ApplicationError::Invalid(_))
    ));
}

#[test]
fn create_active_rejects_terminal_records() {
    let repository = SqliteRepository::in_memory().unwrap();
    let adapter = Arc::new(ScriptedFoundationAdapter::selected());
    let use_cases = LearningPreparationUseCases::new(Arc::new(repository), adapter);
    let mut run = prepared(&use_cases, "media-fp", 100);
    run.status = LearningPreparationRunStatus::Completed;
    let repository = SqliteRepository::in_memory().unwrap();
    assert!(matches!(
        repository.create_active(&run),
        Err(application::ApplicationError::Invalid(_))
    ));
    let _ = CreateLearningPreparationRun::Created(run);
}
