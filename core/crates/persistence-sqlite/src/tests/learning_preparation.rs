use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use application::{
    CreateLearningPreparationRun, FoundationAssetAvailability, FoundationDerivedAvailability,
    FoundationInputs, FoundationPreparationInspector, FoundationPreparationIntent,
    FoundationPreparationRequest, FoundationPreparationTarget, FoundationSourceInspection,
    LearningPreparationRunRepository, LearningPreparationRunStatus,
    LearningPreparationRunTransition, LearningPreparationUseCases, PreparationReadiness,
    PreparationStepState, PrepareFoundationResult, ReusableFoundationArtifact,
    SelectionRequiredReason, WordTimelinePrecision,
};
use domain::{MediaId, SubtitleTrackId};

use crate::SqliteRepository;

struct ScriptedFoundationAdapter {
    inspections: AtomicUsize,
    result: FoundationSourceInspection,
}

#[derive(Default)]
struct ChangingFoundationAdapter {
    inspections: AtomicUsize,
}

struct ConflictOncePreparationRepository {
    inner: Arc<SqliteRepository>,
    reject_next_transition: std::sync::atomic::AtomicBool,
}

impl LearningPreparationRunRepository for ConflictOncePreparationRepository {
    fn create_active(
        &self,
        run: &application::LearningPreparationRun,
    ) -> Result<CreateLearningPreparationRun, application::ApplicationError> {
        self.inner.create_active(run)
    }

    fn get(
        &self,
        id: &application::LearningPreparationRunId,
    ) -> Result<Option<application::LearningPreparationRun>, application::ApplicationError> {
        self.inner.get(id)
    }

    fn transition(
        &self,
        expected_revision: u64,
        run: &application::LearningPreparationRun,
    ) -> Result<LearningPreparationRunTransition, application::ApplicationError> {
        if self.reject_next_transition.swap(false, Ordering::SeqCst) {
            let mut concurrent = self.inner.get(&run.id)?.unwrap();
            let concurrent_expected = concurrent.revision;
            concurrent.revision += 1;
            concurrent.updated_at_ms += 1;
            assert!(matches!(
                self.inner.transition(concurrent_expected, &concurrent)?,
                LearningPreparationRunTransition::Applied(_)
            ));
            return Ok(LearningPreparationRunTransition::Rejected(concurrent));
        }
        self.inner.transition(expected_revision, run)
    }

    fn recover_active(
        &self,
        now_ms: u64,
    ) -> Result<Vec<application::LearningPreparationRun>, application::ApplicationError> {
        self.inner.recover_active(now_ms)
    }
}

impl FoundationPreparationInspector for ChangingFoundationAdapter {
    fn inspect(
        &self,
        _target: &FoundationPreparationTarget,
    ) -> Result<FoundationSourceInspection, application::ApplicationError> {
        let generated = self.inspections.fetch_add(1, Ordering::SeqCst) > 0;
        let availability = |name: &str| {
            if generated {
                FoundationAssetAvailability::Reusable(ReusableFoundationArtifact {
                    artifact_ref: format!("{name}-ready"),
                    input_fingerprint: format!("{name}-fp"),
                })
            } else {
                FoundationAssetAvailability::Buildable
            }
        };
        Ok(FoundationSourceInspection::Selected(FoundationInputs {
            word_timeline: availability("word"),
            word_timeline_precision: WordTimelinePrecision::Estimated,
            prosody: availability("prosody"),
            sense_group: availability("sense"),
            audible_structure: FoundationDerivedAvailability::Available,
        }))
    }
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
                prosody: FoundationAssetAvailability::Buildable,
                sense_group: FoundationAssetAvailability::Buildable,
                audible_structure: FoundationDerivedAvailability::Available,
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
    }
}

fn request() -> FoundationPreparationRequest {
    FoundationPreparationRequest {
        intent: FoundationPreparationIntent::RecommendedFoundation,
    }
}

fn prepared(
    use_cases: &LearningPreparationUseCases,
    media_fingerprint: &str,
    now_ms: u64,
) -> application::LearningPreparationRun {
    match use_cases
        .prepare(target(media_fingerprint), request(), now_ms)
        .unwrap()
    {
        PrepareFoundationResult::Run(run) | PrepareFoundationResult::Replaced { run, .. } => *run,
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
fn generated_artifacts_do_not_change_the_active_run_plan_identity() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ChangingFoundationAdapter::default()),
    );

    let before_generation = prepared(&use_cases, "media-fp", 100);
    let after_generation = prepared(&use_cases, "media-fp", 200);

    assert_eq!(after_generation.id, before_generation.id);
    assert_eq!(
        repository
            .get(&before_generation.id)
            .unwrap()
            .unwrap()
            .status,
        LearningPreparationRunStatus::Queued
    );
}

#[test]
fn cancellation_retries_revision_conflicts_until_the_intent_is_durable() {
    let inner = Arc::new(SqliteRepository::in_memory().unwrap());
    let repository = Arc::new(ConflictOncePreparationRepository {
        inner: inner.clone(),
        reject_next_transition: std::sync::atomic::AtomicBool::new(false),
    });
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let run = prepared(&use_cases, "media-fp", 100);
    repository
        .reject_next_transition
        .store(true, Ordering::SeqCst);

    let cancelling = use_cases.cancel(&run.id, 200).unwrap();

    assert_eq!(cancelling.status, LearningPreparationRunStatus::Cancelling);
    assert_eq!(
        inner.get(&run.id).unwrap().unwrap().status,
        LearningPreparationRunStatus::Cancelling
    );
    assert!(cancelling.revision >= 2);
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
fn selection_is_resolved_before_any_foundation_work_is_planned() {
    let ambiguous_repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let ambiguous = Arc::new(ScriptedFoundationAdapter {
        inspections: AtomicUsize::new(0),
        result: FoundationSourceInspection::SelectionRequired {
            reason: SelectionRequiredReason::SubtitleTrackAmbiguous,
        },
    });
    let ambiguous_use_cases =
        LearningPreparationUseCases::new(ambiguous_repository.clone(), ambiguous.clone());
    assert_eq!(
        ambiguous_use_cases
            .prepare(target("media-fp"), request(), 100)
            .unwrap(),
        PrepareFoundationResult::SelectionRequired(SelectionRequiredReason::SubtitleTrackAmbiguous)
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
fn derived_audible_structure_is_not_a_foundation_step() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository.clone(),
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let mut run = prepared(&use_cases, "media-fp", 100);
    let expected = run.revision;
    run.start(110).unwrap();
    run.plan.prosody.state = PreparationStepState::Ready {
        artifact_ref: "prosody-from-word".into(),
        input_fingerprint: "prosody-fp".into(),
        reused: false,
    };
    run.plan.sense_group.state = PreparationStepState::Ready {
        artifact_ref: "sense-rule".into(),
        input_fingerprint: "sense-fp".into(),
        reused: false,
    };
    run.plan.audible_structure = FoundationDerivedAvailability::Unavailable {
        reason: "unsupported_language".into(),
    };
    run.settle(120);

    assert_eq!(run.status, LearningPreparationRunStatus::Completed);
    assert_eq!(
        run.readiness().citation_structure,
        PreparationReadiness::Unavailable {
            reason: "unsupported_language".into()
        }
    );
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
        .prepare(target("media-fp"), request(), 100)
        .unwrap()
    {
        PrepareFoundationResult::Run(run) => run,
        other => panic!("expected run, got {other:?}"),
    };
    run.start(110).unwrap();
    run.plan.word_timeline.state = PreparationStepState::Pending;

    assert!(run.begin_prosody(120).is_err());
    run.begin_sense_group(121).unwrap();
    run.begin_word_timeline(122).unwrap();
    run.complete_word_timeline(
        ReusableFoundationArtifact {
            artifact_ref: "word".into(),
            input_fingerprint: "word-fp".into(),
        },
        123,
    )
    .unwrap();
    run.begin_prosody(124).unwrap();
}

#[test]
fn audible_structure_readiness_is_derived_from_word_and_language_capability() {
    let repository = Arc::new(SqliteRepository::in_memory().unwrap());
    let use_cases = LearningPreparationUseCases::new(
        repository,
        Arc::new(ScriptedFoundationAdapter::selected()),
    );
    let mut run = prepared(&use_cases, "media-fp", 100);
    run.plan.word_timeline.precision = WordTimelinePrecision::Estimated;

    let readiness = run.readiness();
    assert_eq!(readiness.word_following, PreparationReadiness::Ready);
    assert_eq!(readiness.citation_structure, PreparationReadiness::Ready);
    assert_eq!(readiness.predicted_structure, PreparationReadiness::Ready);

    run.plan.audible_structure = FoundationDerivedAvailability::Unavailable {
        reason: "unsupported_language".into(),
    };
    let readiness = run.readiness();
    assert_eq!(
        readiness.citation_structure,
        PreparationReadiness::Unavailable {
            reason: "unsupported_language".into()
        }
    );
    assert_eq!(
        readiness.predicted_structure,
        PreparationReadiness::Unavailable {
            reason: "unsupported_language".into()
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
    run.plan.prosody.state = PreparationStepState::Running;
    assert!(matches!(
        repository.transition(expected, &run).unwrap(),
        LearningPreparationRunTransition::Applied(_)
    ));

    let recovered = use_cases.recover_startup(120).unwrap();
    assert_eq!(recovered.len(), 1);
    assert_eq!(recovered[0].status, LearningPreparationRunStatus::Queued);
    assert_eq!(
        recovered[0].plan.prosody.state,
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
    assert_eq!(retry.plan.prosody.state, PreparationStepState::Pending);
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
