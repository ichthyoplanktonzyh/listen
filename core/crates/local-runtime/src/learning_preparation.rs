use std::sync::Arc;

use application::{
    AppServices, ApplicationError, FoundationAssetAvailability, FoundationDerivedAvailability,
    FoundationInputs, FoundationPreparationInspection, FoundationPreparationInspector,
    FoundationPreparationRequest, FoundationPreparationTarget, FoundationSourceInspection,
    LearningPreparationRun, LearningPreparationRunId, LearningPreparationRunRepository,
    LearningPreparationRunStatus, LearningPreparationRunTransition, LearningPreparationUseCases,
    PreparationStepState, PrepareFoundationResult, ReusableFoundationArtifact,
    WordTimelinePrecision, foundation_rule_sense_group_policy, now_ms,
};
use domain::{
    MediaAvailability, ProsodyAnalysisId, SenseGroupAnalysisId, SubtitleTokenKind, SubtitleTrack,
    SubtitleTrackStatus, TimelineStatus, TimingSource, WordTimeline, WordTimelineId,
};
use sha2::{Digest, Sha256};

const WORD_POLICY: &str = "foundation-pronunciation-timing:v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InvalidReadyArtifact {
    WordTimeline,
    Prosody,
    SenseGroup,
}

trait FoundationPreparationExecution: FoundationPreparationInspector {
    fn validate_ready_artifacts(
        &self,
        run: &LearningPreparationRun,
    ) -> Result<Option<InvalidReadyArtifact>, ApplicationError>;
    fn build_word_timeline(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<ReusableFoundationArtifact, ApplicationError>;
    fn build_prosody(
        &self,
        target: &FoundationPreparationTarget,
        parent_word_timeline_id: &str,
    ) -> Result<ReusableFoundationArtifact, ApplicationError>;
    fn build_sense_group(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<ReusableFoundationArtifact, ApplicationError>;
}

struct LocalFoundationPreparationExecution {
    services: AppServices,
}

impl LocalFoundationPreparationExecution {
    fn validate_target(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<(), ApplicationError> {
        let analysis = self.services.media_analysis();
        let media = analysis
            .read_media(&target.media_id)?
            .ok_or(ApplicationError::NotFound("media"))?;
        if media.fingerprint != target.media_fingerprint
            || media.availability != MediaAvailability::Available
        {
            return Err(ApplicationError::Conflict(
                "learning preparation media snapshot changed",
            ));
        }
        let track = analysis
            .read_subtitle_track(&target.subtitle_track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        if track.media_id != target.media_id
            || track.fingerprint != target.subtitle_fingerprint
            || track.status != SubtitleTrackStatus::Available
        {
            return Err(ApplicationError::Conflict(
                "learning preparation subtitle snapshot changed",
            ));
        }
        Ok(())
    }

    fn text_input_fingerprint(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<String, ApplicationError> {
        self.services
            .media_analysis()
            .foundation_text_input_fingerprint(&target.subtitle_track_id)
    }

    fn analysis_input_fingerprint(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<String, ApplicationError> {
        self.services
            .media_analysis()
            .foundation_analysis_input_fingerprint(&target.subtitle_track_id)
    }
}

impl FoundationPreparationInspector for LocalFoundationPreparationExecution {
    fn inspect(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<FoundationSourceInspection, ApplicationError> {
        self.validate_target(target)?;
        let analysis = self.services.media_analysis();
        let track = analysis
            .read_subtitle_track(&target.subtitle_track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let text_input_fingerprint = self.text_input_fingerprint(target)?;
        let analysis_input_fingerprint = self.analysis_input_fingerprint(target)?;
        let expected_word_fingerprint =
            step_fingerprint(&text_input_fingerprint, "word", &[WORD_POLICY]);
        let timelines = analysis.list_word_timelines(&target.subtitle_track_id)?;
        let word = timelines
            .iter()
            .filter(|timeline| {
                timeline.status != TimelineStatus::Archived
                    && timeline.track_id == target.subtitle_track_id
                    && timeline.media_id == target.media_id
                    && word_timeline_matches_track(timeline, &track)
            })
            .find(|timeline| timeline.status == TimelineStatus::Active)
            .or_else(|| {
                timelines.iter().find(|timeline| {
                    timeline.status != TimelineStatus::Archived
                        && timeline.track_id == target.subtitle_track_id
                        && timeline.media_id == target.media_id
                        && word_timeline_matches_track(timeline, &track)
                        && timeline
                            .metrics_json
                            .as_object()
                            .get("preparation_input_fingerprint")
                            .and_then(serde_json::Value::as_str)
                            == Some(expected_word_fingerprint.as_str())
                })
            });
        let word_precision = if word.as_ref().is_none_or(|timeline| {
            timeline
                .words
                .iter()
                .any(|word| word.timing_source == TimingSource::Estimated)
        }) {
            WordTimelinePrecision::Estimated
        } else {
            WordTimelinePrecision::Exact
        };
        let word_availability = word
            .as_ref()
            .map(|timeline| {
                FoundationAssetAvailability::Reusable(ReusableFoundationArtifact {
                    artifact_ref: timeline.id.as_str().into(),
                    input_fingerprint: expected_word_fingerprint.clone(),
                })
            })
            .unwrap_or(FoundationAssetAvailability::Buildable);

        // Prosodic Chunk foundation slot. The single semantic source is a
        // Prosody Analysis: an imported package resource whose parent Word
        // Timeline matches the selected timeline satisfies the slot without
        // Core regenerating an equivalent resource. Imported prosody is used
        // as a candidate and is never activated by readiness; only when no
        // matching imported analysis exists the slot is honestly unavailable;
        // Core does not regenerate the equivalent content-bound resource.
        let prosody_analyses = analysis.list_prosody_analyses(&target.subtitle_track_id)?;
        let imported_prosody = prosody_analyses.iter().find(|item| {
            item.status != TimelineStatus::Archived
                && !item.chunks.is_empty()
                && item.track_id == target.subtitle_track_id
                && item.media_id == target.media_id
                && item.parent_word_timeline_id.as_ref().is_some_and(|parent| {
                    word.as_ref().is_some_and(|selected| selected.id == *parent)
                })
        });
        let prosody = if let Some(analysis) = imported_prosody {
            let parent = analysis
                .parent_word_timeline_id
                .as_ref()
                .expect("validated imported prosody parent");
            FoundationAssetAvailability::Reusable(ReusableFoundationArtifact {
                artifact_ref: analysis.id.as_str().into(),
                input_fingerprint: prosody_fingerprint(
                    &analysis_input_fingerprint,
                    parent.as_str(),
                    analysis.id.as_str(),
                ),
            })
        } else {
            FoundationAssetAvailability::Unavailable {
                reason: "prosody_analysis_candidate_required".into(),
            }
        };

        let sense_fingerprint = sense_group_fingerprint(&analysis_input_fingerprint);
        let (sense_provider, sense_version, sense_algorithm) = foundation_rule_sense_group_policy();
        let sense_groups = analysis.list_sense_group_analyses(&target.subtitle_track_id)?;
        let sense_group = sense_groups
            .iter()
            .filter(|item| {
                item.status != TimelineStatus::Archived
                    && !item.groups.is_empty()
                    && item.track_id == target.subtitle_track_id
                    && item.media_id == target.media_id
            })
            .find(|item| item.status == TimelineStatus::Active)
            .or_else(|| {
                sense_groups.iter().find(|item| {
                    item.status != TimelineStatus::Archived
                        && !item.groups.is_empty()
                        && item.track_id == target.subtitle_track_id
                        && item.media_id == target.media_id
                        && item.provider_id == sense_provider
                        && item.provider_version == sense_version
                        && item.algorithm == sense_algorithm
                        && item
                            .metrics_json
                            .as_object()
                            .get("preparation_input_fingerprint")
                            .and_then(serde_json::Value::as_str)
                            == Some(sense_fingerprint.as_str())
                })
            })
            .map(|item| {
                FoundationAssetAvailability::Reusable(ReusableFoundationArtifact {
                    artifact_ref: item.id.as_str().into(),
                    input_fingerprint: sense_fingerprint.clone(),
                })
            })
            .unwrap_or(FoundationAssetAvailability::Buildable);
        let audible_structure =
            audible_structure_availability(track.language.as_ref().map(|value| value.as_str()));

        Ok(FoundationSourceInspection::Selected(FoundationInputs {
            word_timeline: word_availability,
            word_timeline_precision: word_precision,
            prosody,
            sense_group,
            audible_structure,
        }))
    }
}

impl FoundationPreparationExecution for LocalFoundationPreparationExecution {
    fn validate_ready_artifacts(
        &self,
        run: &LearningPreparationRun,
    ) -> Result<Option<InvalidReadyArtifact>, ApplicationError> {
        self.validate_target(&run.target)?;
        let analysis = self.services.media_analysis();
        let track = analysis
            .read_subtitle_track(&run.target.subtitle_track_id)?
            .ok_or(ApplicationError::NotFound("subtitle track"))?;
        let text_input = self.text_input_fingerprint(&run.target)?;
        let analysis_input = self.analysis_input_fingerprint(&run.target)?;

        if let Some((artifact_ref, input_fingerprint)) =
            ready_artifact(&run.plan.word_timeline.state)
        {
            let expected = step_fingerprint(&text_input, "word", &[WORD_POLICY]);
            let Ok(id) = WordTimelineId::parse(artifact_ref) else {
                return Ok(Some(InvalidReadyArtifact::WordTimeline));
            };
            let Some(timeline) = analysis.get_word_timeline(&id)? else {
                return Ok(Some(InvalidReadyArtifact::WordTimeline));
            };
            if input_fingerprint != expected
                || timeline.status == TimelineStatus::Archived
                || timeline.track_id != run.target.subtitle_track_id
                || timeline.media_id != run.target.media_id
                || !word_timeline_matches_track(&timeline, &track)
            {
                return Ok(Some(InvalidReadyArtifact::WordTimeline));
            }
        }

        if let Some((artifact_ref, _input_fingerprint)) = ready_artifact(&run.plan.prosody.state) {
            // An imported Prosody Analysis satisfies the slot as a candidate;
            // it is validated by resource identity and its Word Timeline
            // parent, never by the local producer fingerprint.
            if let Ok(id) = ProsodyAnalysisId::parse(artifact_ref)
                && let Some(imported) = analysis.get_prosody_analysis(&id)?
            {
                let Some(parent_id) = imported.parent_word_timeline_id.as_ref() else {
                    return Ok(Some(InvalidReadyArtifact::Prosody));
                };
                if ready_artifact_ref(&run.plan.word_timeline.state) != Some(parent_id.as_str()) {
                    return Ok(Some(InvalidReadyArtifact::Prosody));
                }
                let Some(parent) = analysis.get_word_timeline(parent_id)? else {
                    return Ok(Some(InvalidReadyArtifact::Prosody));
                };
                if imported.status == TimelineStatus::Archived
                    || imported.track_id != run.target.subtitle_track_id
                    || imported.media_id != run.target.media_id
                    || imported.chunks.is_empty()
                    || parent.status == TimelineStatus::Archived
                    || !word_timeline_matches_track(&parent, &track)
                {
                    return Ok(Some(InvalidReadyArtifact::Prosody));
                }
            } else {
                return Ok(Some(InvalidReadyArtifact::Prosody));
            }
        }

        if let Some((artifact_ref, input_fingerprint)) = ready_artifact(&run.plan.sense_group.state)
        {
            let expected = sense_group_fingerprint(&analysis_input);
            let Ok(id) = SenseGroupAnalysisId::parse(artifact_ref) else {
                return Ok(Some(InvalidReadyArtifact::SenseGroup));
            };
            let Some(item) = analysis.get_sense_group_analysis(&id)? else {
                return Ok(Some(InvalidReadyArtifact::SenseGroup));
            };
            let (provider, version, algorithm) = foundation_rule_sense_group_policy();
            if input_fingerprint != expected
                || item.status == TimelineStatus::Archived
                || item.track_id != run.target.subtitle_track_id
                || item.media_id != run.target.media_id
                || item.groups.is_empty()
                || (item.status != TimelineStatus::Active
                    && (item.provider_id != provider
                        || item.provider_version != version
                        || item.algorithm != algorithm
                        || item
                            .metrics_json
                            .as_object()
                            .get("preparation_input_fingerprint")
                            .and_then(serde_json::Value::as_str)
                            != Some(expected.as_str())))
            {
                return Ok(Some(InvalidReadyArtifact::SenseGroup));
            }
        }

        Ok(None)
    }

    fn build_word_timeline(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<ReusableFoundationArtifact, ApplicationError> {
        self.validate_target(target)?;
        let text_input_fingerprint = self.text_input_fingerprint(target)?;
        let fingerprint = step_fingerprint(&text_input_fingerprint, "word", &[WORD_POLICY]);
        let timeline = self
            .services
            .media_analysis()
            .create_foundation_word_timeline(&target.subtitle_track_id, &fingerprint)?;
        Ok(ReusableFoundationArtifact {
            artifact_ref: timeline.id.as_str().into(),
            input_fingerprint: fingerprint,
        })
    }

    fn build_prosody(
        &self,
        target: &FoundationPreparationTarget,
        parent_word_timeline_id: &str,
    ) -> Result<ReusableFoundationArtifact, ApplicationError> {
        let _ = (target, parent_word_timeline_id);
        Err(ApplicationError::Invalid(
            "prosody analysis must be imported as a package candidate".into(),
        ))
    }

    fn build_sense_group(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<ReusableFoundationArtifact, ApplicationError> {
        self.validate_target(target)?;
        let analysis_input_fingerprint = self.analysis_input_fingerprint(target)?;
        let fingerprint = sense_group_fingerprint(&analysis_input_fingerprint);
        let analysis = self
            .services
            .media_analysis()
            .generate_rule_sense_group_analysis(
                &target.subtitle_track_id,
                Some(TimelineStatus::Candidate),
                &fingerprint,
            )?;
        Ok(ReusableFoundationArtifact {
            artifact_ref: analysis.id.as_str().into(),
            input_fingerprint: fingerprint,
        })
    }
}

/// Internal owner of durable preparation execution. It intentionally exposes
/// no HTTP contract.
pub struct LearningPreparationCoordinator {
    use_cases: Arc<LearningPreparationUseCases>,
    runs: Arc<dyn LearningPreparationRunRepository>,
    execution: Arc<dyn FoundationPreparationExecution>,
}

impl LearningPreparationCoordinator {
    pub fn new(
        services: AppServices,
        runs: Arc<dyn LearningPreparationRunRepository>,
    ) -> Result<Arc<Self>, ApplicationError> {
        let execution = Arc::new(LocalFoundationPreparationExecution { services });
        Self::new_with_execution(runs, execution)
    }

    fn new_with_execution(
        runs: Arc<dyn LearningPreparationRunRepository>,
        execution: Arc<dyn FoundationPreparationExecution>,
    ) -> Result<Arc<Self>, ApplicationError> {
        let inspector: Arc<dyn FoundationPreparationInspector> = execution.clone();
        let use_cases = Arc::new(LearningPreparationUseCases::new(runs.clone(), inspector));
        let recovered = use_cases.recover_startup(now_ms())?;
        let coordinator = Arc::new(Self {
            use_cases,
            runs,
            execution,
        });
        if tokio::runtime::Handle::try_current().is_ok() {
            for run in recovered {
                coordinator.clone().start(run.id);
            }
        }
        Ok(coordinator)
    }

    pub fn inspect(
        &self,
        target: FoundationPreparationTarget,
    ) -> Result<FoundationPreparationInspection, ApplicationError> {
        self.use_cases.inspect(target)
    }

    pub fn prepare(
        self: &Arc<Self>,
        target: FoundationPreparationTarget,
        request: FoundationPreparationRequest,
    ) -> Result<PrepareFoundationResult, ApplicationError> {
        let result = self.use_cases.prepare(target, request, now_ms())?;
        match &result {
            PrepareFoundationResult::Run(run) | PrepareFoundationResult::Replaced { run, .. } => {
                self.clone().start(run.id.clone())
            }
            PrepareFoundationResult::SelectionRequired(_)
            | PrepareFoundationResult::Unavailable(_) => {}
        }
        Ok(result)
    }

    pub fn get(
        &self,
        id: &LearningPreparationRunId,
    ) -> Result<LearningPreparationRun, ApplicationError> {
        self.use_cases.get_run(id)
    }

    pub fn cancel(
        self: &Arc<Self>,
        id: &LearningPreparationRunId,
    ) -> Result<LearningPreparationRun, ApplicationError> {
        let run = self.use_cases.cancel(id, now_ms())?;
        self.clone().start(run.id.clone());
        Ok(run)
    }

    pub fn retry(
        self: &Arc<Self>,
        id: &LearningPreparationRunId,
    ) -> Result<LearningPreparationRun, ApplicationError> {
        let run = self.use_cases.retry(id, now_ms())?;
        self.clone().start(run.id.clone());
        Ok(run)
    }

    fn start(self: Arc<Self>, id: LearningPreparationRunId) {
        tokio::spawn(async move {
            if let Err(error) = self.execute(id.clone()).await {
                let _ = self.record_execution_failure(&id, error.to_string());
            }
        });
    }

    fn record_execution_failure(
        &self,
        id: &LearningPreparationRunId,
        reason: String,
    ) -> Result<(), ApplicationError> {
        let Some(mut run) = self.runs.get(id)? else {
            return Ok(());
        };
        loop {
            if !matches!(
                run.status,
                LearningPreparationRunStatus::Queued | LearningPreparationRunStatus::Running
            ) {
                return Ok(());
            }
            let expected = run.revision;
            run.fail_execution(reason.clone(), now_ms());
            match self.runs.transition(expected, &run)? {
                LearningPreparationRunTransition::Applied(_) => return Ok(()),
                LearningPreparationRunTransition::Rejected(current) => run = current,
            }
        }
    }

    async fn execute(&self, id: LearningPreparationRunId) -> Result<(), ApplicationError> {
        let mut run = self.use_cases.get_run(&id)?;
        if run.status == LearningPreparationRunStatus::Queued {
            let expected = run.revision;
            run.start(now_ms())?;
            run = self.persist(expected, run)?;
        }
        loop {
            if run.status == LearningPreparationRunStatus::Cancelling {
                let expected = run.revision;
                run.finish_cancellation(now_ms());
                let _ = self.persist(expected, run)?;
                return Ok(());
            }
            if run.status != LearningPreparationRunStatus::Running {
                return Ok(());
            }

            if let Some(invalid) = self.execution.validate_ready_artifacts(&run)? {
                let expected = run.revision;
                match invalid {
                    InvalidReadyArtifact::WordTimeline => {
                        run.invalidate_word_timeline_artifact(now_ms())
                    }
                    InvalidReadyArtifact::Prosody => run.invalidate_prosody_artifact(now_ms()),
                    InvalidReadyArtifact::SenseGroup => {
                        run.invalidate_sense_group_artifact(now_ms())
                    }
                }
                run = self.persist(expected, run)?;
                continue;
            }

            if matches!(run.plan.word_timeline.state, PreparationStepState::Pending) {
                let expected = run.revision;
                run.begin_word_timeline(now_ms())?;
                run = self.persist(expected, run)?;
                let expected = run.revision;
                match self.execution.build_word_timeline(&run.target) {
                    Ok(artifact) => run.complete_word_timeline(artifact, now_ms())?,
                    Err(error) => run.fail_word_timeline(error.to_string(), now_ms())?,
                }
                run = self.persist(expected, run)?;
                continue;
            }

            // Sense-group partitioning is independent of the word/chunk path,
            // so a word-timing failure does not hide a usable text resource.
            if matches!(run.plan.sense_group.state, PreparationStepState::Pending) {
                let expected = run.revision;
                run.begin_sense_group(now_ms())?;
                run = self.persist(expected, run)?;
                let expected = run.revision;
                match self.execution.build_sense_group(&run.target) {
                    Ok(artifact) => run.complete_sense_group(artifact, now_ms())?,
                    Err(error) => run.fail_sense_group(error.to_string(), now_ms())?,
                }
                run = self.persist(expected, run)?;
                continue;
            }

            if matches!(run.plan.prosody.state, PreparationStepState::Pending) {
                let source = ready_artifact_ref(&run.plan.word_timeline.state)
                    .ok_or(ApplicationError::Conflict("prosody source is not ready"))?;
                let source = source.to_owned();
                let expected = run.revision;
                run.begin_prosody(now_ms())?;
                run = self.persist(expected, run)?;
                let expected = run.revision;
                match self.execution.build_prosody(&run.target, &source) {
                    Ok(artifact) => run.complete_prosody(artifact, now_ms())?,
                    Err(error) => run.fail_prosody(error.to_string(), now_ms())?,
                }
                run = self.persist(expected, run)?;
                continue;
            }

            let expected = run.revision;
            run.settle(now_ms());
            if run.revision != expected {
                let _ = self.persist(expected, run)?;
            }
            return Ok(());
        }
    }

    fn persist(
        &self,
        expected_revision: u64,
        run: LearningPreparationRun,
    ) -> Result<LearningPreparationRun, ApplicationError> {
        match self.runs.transition(expected_revision, &run)? {
            LearningPreparationRunTransition::Applied(run) => Ok(run),
            LearningPreparationRunTransition::Rejected(current) => Ok(current),
        }
    }
}

fn ready_artifact_ref(state: &PreparationStepState) -> Option<&str> {
    match state {
        PreparationStepState::Ready { artifact_ref, .. } => Some(artifact_ref),
        _ => None,
    }
}

fn ready_artifact(state: &PreparationStepState) -> Option<(&str, &str)> {
    match state {
        PreparationStepState::Ready {
            artifact_ref,
            input_fingerprint,
            ..
        } => Some((artifact_ref, input_fingerprint)),
        _ => None,
    }
}

fn step_fingerprint(input_fingerprint: &str, step: &str, fields: &[&str]) -> String {
    let mut digest = Sha256::new();
    for field in ["learning-preparation-step-v1", input_fingerprint, step]
        .into_iter()
        .chain(fields.iter().copied())
    {
        digest.update((field.len() as u64).to_be_bytes());
        digest.update(field.as_bytes());
    }
    hex::encode(digest.finalize())
}

fn prosody_fingerprint(
    analysis_input_fingerprint: &str,
    parent: &str,
    resource_id: &str,
) -> String {
    step_fingerprint(
        analysis_input_fingerprint,
        "prosody",
        &[parent, resource_id],
    )
}

fn sense_group_fingerprint(analysis_input_fingerprint: &str) -> String {
    let (provider, version, algorithm) = foundation_rule_sense_group_policy();
    step_fingerprint(
        analysis_input_fingerprint,
        "rule-sense-group",
        &[provider, version, algorithm],
    )
}

fn audible_structure_availability(language: Option<&str>) -> FoundationDerivedAvailability {
    match language {
        Some(language) if language == "en" || language.starts_with("en-") => {
            FoundationDerivedAvailability::Available
        }
        Some(language) => FoundationDerivedAvailability::Unavailable {
            reason: format!(
                "citation and predicted audible structure are not supported for {language}"
            ),
        },
        None => FoundationDerivedAvailability::Unavailable {
            reason: "subtitle language is unknown".into(),
        },
    }
}

fn word_timeline_matches_track(timeline: &WordTimeline, track: &SubtitleTrack) -> bool {
    let expected = track
        .sentences
        .iter()
        .flat_map(|sentence| {
            sentence.tokens.iter().filter_map(move |token| {
                (token.kind == SubtitleTokenKind::Word).then_some((
                    sentence.id.as_str(),
                    token.index,
                    token.text.as_str(),
                ))
            })
        })
        .collect::<Vec<_>>();
    let mut actual = timeline
        .words
        .iter()
        .map(|word| {
            (
                word.sentence_id.as_str(),
                word.token_index,
                word.text.as_str(),
            )
        })
        .collect::<Vec<_>>();
    actual.sort_unstable();
    let mut expected = expected;
    expected.sort_unstable();
    !expected.is_empty() && actual == expected
}

#[cfg(test)]
mod tests {
    use std::sync::Mutex;
    use std::time::Duration;

    use application::FoundationPreparationIntent;
    use domain::{MediaId, SubtitleTrackId};
    use persistence_sqlite::SqliteRepository;

    use super::*;

    struct ScriptedExecution {
        calls: Mutex<Vec<&'static str>>,
    }

    impl FoundationPreparationInspector for ScriptedExecution {
        fn inspect(
            &self,
            _target: &FoundationPreparationTarget,
        ) -> Result<FoundationSourceInspection, ApplicationError> {
            Ok(FoundationSourceInspection::Selected(FoundationInputs {
                word_timeline: FoundationAssetAvailability::Buildable,
                word_timeline_precision: WordTimelinePrecision::Estimated,
                prosody: FoundationAssetAvailability::Buildable,
                sense_group: FoundationAssetAvailability::Buildable,
                audible_structure: FoundationDerivedAvailability::Available,
            }))
        }
    }

    impl FoundationPreparationExecution for ScriptedExecution {
        fn validate_ready_artifacts(
            &self,
            _run: &LearningPreparationRun,
        ) -> Result<Option<InvalidReadyArtifact>, ApplicationError> {
            Ok(None)
        }

        fn build_word_timeline(
            &self,
            _target: &FoundationPreparationTarget,
        ) -> Result<ReusableFoundationArtifact, ApplicationError> {
            self.calls.lock().unwrap().push("word");
            Ok(artifact("word"))
        }

        fn build_prosody(
            &self,
            _target: &FoundationPreparationTarget,
            parent_word_timeline_id: &str,
        ) -> Result<ReusableFoundationArtifact, ApplicationError> {
            assert_eq!(parent_word_timeline_id, "word");
            self.calls.lock().unwrap().push("prosody");
            Ok(artifact("prosody"))
        }

        fn build_sense_group(
            &self,
            _target: &FoundationPreparationTarget,
        ) -> Result<ReusableFoundationArtifact, ApplicationError> {
            self.calls.lock().unwrap().push("sense");
            Ok(artifact("sense"))
        }
    }

    fn artifact(name: &str) -> ReusableFoundationArtifact {
        ReusableFoundationArtifact {
            artifact_ref: name.into(),
            input_fingerprint: format!("{name}-fingerprint"),
        }
    }

    fn target() -> FoundationPreparationTarget {
        FoundationPreparationTarget {
            media_id: MediaId::parse("media").unwrap(),
            media_fingerprint: "media-fingerprint".into(),
            subtitle_track_id: SubtitleTrackId::parse("track").unwrap(),
            subtitle_fingerprint: "subtitle-fingerprint".into(),
        }
    }

    async fn wait_terminal(
        coordinator: &LearningPreparationCoordinator,
        id: &LearningPreparationRunId,
    ) -> LearningPreparationRun {
        for _ in 0..100 {
            let run = coordinator.get(id).unwrap();
            if !run.status.is_active() {
                return run;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        panic!("preparation did not become terminal");
    }

    #[tokio::test]
    async fn foundation_execution_builds_only_the_three_fast_resources() {
        let repository = Arc::new(SqliteRepository::in_memory().unwrap());
        let execution = Arc::new(ScriptedExecution {
            calls: Mutex::new(Vec::new()),
        });
        let coordinator =
            LearningPreparationCoordinator::new_with_execution(repository, execution.clone())
                .unwrap();
        let PrepareFoundationResult::Run(created) = coordinator
            .prepare(
                target(),
                FoundationPreparationRequest {
                    intent: FoundationPreparationIntent::RecommendedFoundation,
                },
            )
            .unwrap()
        else {
            panic!("expected preparation run");
        };

        let completed = wait_terminal(&coordinator, &created.id).await;

        assert_eq!(completed.status, LearningPreparationRunStatus::Completed);
        assert_eq!(
            execution.calls.lock().unwrap().as_slice(),
            ["word", "sense", "prosody"]
        );
        assert!(matches!(
            completed.plan.audible_structure,
            FoundationDerivedAvailability::Available
        ));
    }

    #[test]
    fn audible_structure_capability_is_honest_for_non_english_tracks() {
        assert_eq!(
            audible_structure_availability(Some("en-au")),
            FoundationDerivedAvailability::Available
        );
        assert!(matches!(
            audible_structure_availability(Some("zh-hans")),
            FoundationDerivedAvailability::Unavailable { .. }
        ));
        assert!(matches!(
            audible_structure_availability(None),
            FoundationDerivedAvailability::Unavailable { .. }
        ));
    }

    fn imported_prosody_track(repo: &SqliteRepository) -> FoundationPreparationTarget {
        use application::MediaRepository;
        use application::ProsodyAnalysisRepository;
        use application::SubtitleTrackRepository;
        use application::WordTimelineRepository;
        use domain::{
            LanguageCode, LexicalStress, MediaAvailability, MediaItem, MediaKind, ProsodyAnalysis,
            ProsodyAnalysisId, ProsodyAnchor, ProsodyEvidence, ProsodyWordRef, SubtitleSentence,
            SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, SubtitleTrack,
            SubtitleTrackStatus, TimeMs, TimelineCreator, TimelineMetrics, TimelineStatus,
            TimingSource, UtteranceRole, WordTimeline, WordTimelineId, WordTiming,
        };

        let media = MediaItem {
            id: MediaId::parse("media-imported").unwrap(),
            path: "/tmp/imported.mp4".into(),
            fingerprint: "media-imported-fingerprint".into(),
            title: "Imported media".into(),
            kind: MediaKind::Video,
            duration: Some(TimeMs::new(2_500)),
            availability: MediaAvailability::Available,
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        repo.upsert(&media).unwrap();
        let track = SubtitleTrack {
            id: SubtitleTrackId::parse("track-imported").unwrap(),
            media_id: media.id.clone(),
            fingerprint: "track-imported-fingerprint".into(),
            language: Some(LanguageCode::parse("en").unwrap()),
            source: "listen-resource-package-v1".into(),
            status: SubtitleTrackStatus::Available,
            sentences: vec![SubtitleSentence {
                id: SubtitleSentenceId::parse("sentence-1").unwrap(),
                index: 0,
                start: TimeMs::new(100),
                end: TimeMs::new(500),
                original_text: "Hello world".into(),
                display_text: "Hello world".into(),
                tokens: vec![
                    SubtitleToken {
                        index: 0,
                        kind: SubtitleTokenKind::Word,
                        text: "Hello".into(),
                        normalized: Some("hello".into()),
                        start_char: 0,
                        end_char: 5,
                    },
                    SubtitleToken {
                        index: 1,
                        kind: SubtitleTokenKind::Word,
                        text: "world".into(),
                        normalized: Some("world".into()),
                        start_char: 6,
                        end_char: 11,
                    },
                ],
            }],
        };
        repo.save_track(&track).unwrap();
        let sentence_id = track.sentences[0].id.clone();
        let word_timeline = WordTimeline {
            id: WordTimelineId::parse("word-timeline-imported").unwrap(),
            track_id: track.id.clone(),
            media_id: media.id.clone(),
            algorithm_id: "foundation-pronunciation-timing".into(),
            algorithm_version: "v1".into(),
            config_hash: "config".into(),
            parent_timeline_id: None,
            created_by: TimelineCreator::Algorithm,
            status: TimelineStatus::Active,
            metrics_json: TimelineMetrics::default(),
            words: vec![
                WordTiming {
                    sentence_id: sentence_id.clone(),
                    token_index: 0,
                    text: "Hello".into(),
                    start_ms: 100,
                    end_ms: 250,
                    confidence: Some(1.0),
                    timing_source: TimingSource::AsrAligned,
                    provider_id: "listen-gen".into(),
                    provider_version: "0.2.0".into(),
                },
                WordTiming {
                    sentence_id: sentence_id.clone(),
                    token_index: 1,
                    text: "world".into(),
                    start_ms: 260,
                    end_ms: 500,
                    confidence: Some(1.0),
                    timing_source: TimingSource::AsrAligned,
                    provider_id: "listen-gen".into(),
                    provider_version: "0.2.0".into(),
                },
            ],
            created_at_ms: 1,
            updated_at_ms: 1,
        };
        repo.save_word_timeline(&word_timeline).unwrap();
        let _ = repo.save_prosody_analysis(&ProsodyAnalysis {
            id: ProsodyAnalysisId::parse("prosody-imported").unwrap(),
            track_id: track.id.clone(),
            media_id: media.id.clone(),
            parent_word_timeline_id: Some(word_timeline.id.clone()),
            provider_id: "listen-gen".into(),
            provider_version: "0.2.0".into(),
            algorithm: "prosody-v1".into(),
            status: TimelineStatus::Candidate,
            created_by: TimelineCreator::Algorithm,
            metrics_json: TimelineMetrics::default(),
            chunks: vec![domain::ProsodicChunk {
                sentence_id: sentence_id.clone(),
                chunk_index: 0,
                start_token_index: 0,
                end_token_index: 1,
                nucleus_token_index: Some(0),
                confidence: 0.9,
            }],
            anchors: vec![
                ProsodyAnchor {
                    word_ref: ProsodyWordRef {
                        sentence_id: sentence_id.clone(),
                        token_index: 0,
                    },
                    syllable_index: None,
                    lexical_stress: LexicalStress::Primary,
                    realized_prominence: 0.8,
                    utterance_role: UtteranceRole::Nucleus,
                    evidence: vec![ProsodyEvidence::Energy],
                    confidence: 0.9,
                },
                ProsodyAnchor {
                    word_ref: ProsodyWordRef {
                        sentence_id: sentence_id.clone(),
                        token_index: 1,
                    },
                    syllable_index: None,
                    lexical_stress: LexicalStress::Unstressed,
                    realized_prominence: 0.3,
                    utterance_role: UtteranceRole::Postnuclear,
                    evidence: vec![ProsodyEvidence::Pitch],
                    confidence: 0.8,
                },
            ],
            created_at_ms: 1,
            updated_at_ms: 1,
        });
        FoundationPreparationTarget {
            media_id: media.id,
            media_fingerprint: media.fingerprint,
            subtitle_track_id: track.id,
            subtitle_fingerprint: track.fingerprint,
        }
    }

    #[tokio::test]
    async fn imported_prosody_satisfies_the_foundation_slot_without_regeneration_or_activation() {
        use application::ProsodyAnalysisRepository;
        let repo = Arc::new(SqliteRepository::in_memory().unwrap());
        let target = imported_prosody_track(&repo);
        let services = application::AppServices::new(
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
            repo.clone(),
        );
        let coordinator = LearningPreparationCoordinator::new(services, repo.clone()).unwrap();

        let inspection = coordinator.inspect(target.clone()).unwrap();
        let FoundationSourceInspection::Selected(inputs) = inspection.source else {
            panic!("expected selected foundation inputs");
        };
        let FoundationAssetAvailability::Reusable(prosody) = inputs.prosody else {
            panic!("imported prosody must satisfy the foundation prosody slot");
        };
        assert_eq!(prosody.artifact_ref, "prosody-imported");

        let PrepareFoundationResult::Run(created) = coordinator
            .prepare(
                target.clone(),
                FoundationPreparationRequest {
                    intent: FoundationPreparationIntent::RecommendedFoundation,
                },
            )
            .unwrap()
        else {
            panic!("expected preparation run");
        };
        let completed = wait_terminal(&coordinator, &created.id).await;

        assert_eq!(completed.status, LearningPreparationRunStatus::Completed);
        let PreparationStepState::Ready {
            artifact_ref,
            reused,
            ..
        } = &completed.plan.prosody.state
        else {
            panic!("prosody slot must be ready");
        };
        assert_eq!(artifact_ref, "prosody-imported");
        assert_eq!(reused, &true);
        // The imported analysis satisfies the slot as a candidate: no
        // ChunkTimeline family exists anymore (R5 retirement) and the
        // prosody analysis was not activated.
        let imported = repo
            .get_prosody_analysis(&ProsodyAnalysisId::parse("prosody-imported").unwrap())
            .unwrap()
            .unwrap();
        assert_eq!(imported.status, TimelineStatus::Candidate);
    }
}
