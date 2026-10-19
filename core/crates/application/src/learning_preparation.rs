use std::sync::Arc;

use domain::{MediaId, SubtitleTrackId};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::ApplicationError;

const FOUNDATION_PLANNER_VERSION: &str = "foundation-v2";
const INPUTS_CHANGED_ERROR: &str = "preparation inputs or plan changed";

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct LearningPreparationRunId(String);

impl LearningPreparationRunId {
    pub fn parse(value: impl Into<String>) -> Result<Self, ApplicationError> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(ApplicationError::Validation(
                "learning preparation run identifier",
            ));
        }
        Ok(Self(value))
    }

    pub fn from_fingerprint(fingerprint: &str) -> Self {
        Self(digest_fields("learning-preparation-run", &[fingerprint]))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationPreparationTarget {
    pub media_id: MediaId,
    pub media_fingerprint: String,
    pub subtitle_track_id: SubtitleTrackId,
    pub subtitle_fingerprint: String,
}

impl FoundationPreparationTarget {
    pub fn target_key(&self) -> String {
        digest_fields(
            "learning-preparation-target",
            &[self.media_id.as_str(), self.subtitle_track_id.as_str()],
        )
    }

    pub fn input_fingerprint(&self) -> String {
        digest_fields(
            FOUNDATION_PLANNER_VERSION,
            &[
                self.media_id.as_str(),
                &self.media_fingerprint,
                self.subtitle_track_id.as_str(),
                &self.subtitle_fingerprint,
            ],
        )
    }

    fn validate(&self) -> Result<(), ApplicationError> {
        if self.media_fingerprint.trim().is_empty() || self.subtitle_fingerprint.trim().is_empty() {
            return Err(ApplicationError::Invalid(
                "preparation target fingerprints must not be empty".into(),
            ));
        }
        Ok(())
    }
}

fn digest_fields(namespace: &str, fields: &[&str]) -> String {
    let mut digest = Sha256::new();
    digest.update((namespace.len() as u64).to_be_bytes());
    digest.update(namespace.as_bytes());
    for field in fields {
        digest.update((field.len() as u64).to_be_bytes());
        digest.update(field.as_bytes());
    }
    hex::encode(digest.finalize())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FoundationPreparationIntent {
    RecommendedFoundation,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationPreparationRequest {
    pub intent: FoundationPreparationIntent,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SelectionRequiredReason {
    SubtitleTrackUnavailable,
    SubtitleTrackAmbiguous,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "state")]
pub enum FoundationSourceInspection {
    Selected(FoundationInputs),
    SelectionRequired { reason: SelectionRequiredReason },
    Unavailable { reason: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReusableFoundationArtifact {
    pub artifact_ref: String,
    pub input_fingerprint: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "state")]
pub enum FoundationAssetAvailability {
    Reusable(ReusableFoundationArtifact),
    Buildable,
    Unavailable { reason: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WordTimelinePrecision {
    Exact,
    Estimated,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "state")]
pub enum FoundationDerivedAvailability {
    Available,
    Unavailable { reason: String },
}

impl Default for FoundationDerivedAvailability {
    fn default() -> Self {
        Self::Unavailable {
            reason: "audible_structure_capability_unknown".into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationInputs {
    pub word_timeline: FoundationAssetAvailability,
    pub word_timeline_precision: WordTimelinePrecision,
    /// The Prosodic Chunk foundation slot. Its single semantic source is a
    /// package-native Prosody Analysis resource. Legacy `ChunkTimeline` is not
    /// accepted as this slot and Core does not regenerate it as a fallback.
    #[serde(alias = "chunk_timeline")]
    pub prosody: FoundationAssetAvailability,
    #[serde(alias = "rule_sense_group")]
    pub sense_group: FoundationAssetAvailability,
    #[serde(default)]
    pub audible_structure: FoundationDerivedAvailability,
}

pub trait FoundationPreparationInspector: Send + Sync {
    fn inspect(
        &self,
        target: &FoundationPreparationTarget,
    ) -> Result<FoundationSourceInspection, ApplicationError>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PreparationRequirement {
    Required,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "state")]
pub enum PreparationStepState {
    Pending,
    Running,
    Ready {
        artifact_ref: String,
        input_fingerprint: String,
        reused: bool,
    },
    Skipped {
        reason: String,
    },
    Failed {
        reason: String,
    },
    Cancelled,
}

impl PreparationStepState {
    fn is_terminal(&self) -> bool {
        matches!(
            self,
            Self::Ready { .. } | Self::Skipped { .. } | Self::Failed { .. } | Self::Cancelled
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WordTimelinePreparation {
    pub requirement: PreparationRequirement,
    pub precision: WordTimelinePrecision,
    pub state: PreparationStepState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProsodyPreparation {
    pub requirement: PreparationRequirement,
    pub state: PreparationStepState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SenseGroupPreparation {
    pub requirement: PreparationRequirement,
    pub state: PreparationStepState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationPreparationPlan {
    pub word_timeline: WordTimelinePreparation,
    #[serde(alias = "chunk_timeline")]
    pub prosody: ProsodyPreparation,
    #[serde(alias = "rule_sense_group")]
    pub sense_group: SenseGroupPreparation,
    #[serde(default)]
    pub audible_structure: FoundationDerivedAvailability,
}

impl FoundationPreparationPlan {
    fn from_inputs(inputs: FoundationInputs) -> Self {
        let word_timeline = WordTimelinePreparation {
            requirement: PreparationRequirement::Required,
            precision: inputs.word_timeline_precision,
            state: initial_state(inputs.word_timeline),
        };
        let mut prosody = ProsodyPreparation {
            requirement: PreparationRequirement::Required,
            state: initial_state(inputs.prosody),
        };
        if matches!(
            word_timeline.state,
            PreparationStepState::Skipped { .. } | PreparationStepState::Failed { .. }
        ) && matches!(prosody.state, PreparationStepState::Pending)
        {
            prosody.state = PreparationStepState::Skipped {
                reason: "word_timeline_unavailable".into(),
            };
        }
        let sense_group = SenseGroupPreparation {
            requirement: PreparationRequirement::Required,
            state: initial_state(inputs.sense_group),
        };
        Self {
            word_timeline,
            prosody,
            sense_group,
            audible_structure: inputs.audible_structure,
        }
    }

    fn all_terminal(&self) -> bool {
        self.word_timeline.state.is_terminal()
            && self.prosody.state.is_terminal()
            && self.sense_group.state.is_terminal()
    }

    fn has_required_failure(&self) -> bool {
        [
            &self.word_timeline.state,
            &self.prosody.state,
            &self.sense_group.state,
        ]
        .into_iter()
        .any(|state| matches!(state, PreparationStepState::Failed { .. }))
    }
}

fn initial_state(availability: FoundationAssetAvailability) -> PreparationStepState {
    match availability {
        FoundationAssetAvailability::Reusable(artifact) => PreparationStepState::Ready {
            artifact_ref: artifact.artifact_ref,
            input_fingerprint: artifact.input_fingerprint,
            reused: true,
        },
        FoundationAssetAvailability::Buildable => PreparationStepState::Pending,
        FoundationAssetAvailability::Unavailable { reason } => {
            PreparationStepState::Failed { reason }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LearningPreparationRunStatus {
    Queued,
    Running,
    Cancelling,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "state")]
pub enum PreparationReadiness {
    Ready,
    Preparing,
    Unavailable { reason: String },
    Failed { reason: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationActivityReadiness {
    pub word_following: PreparationReadiness,
    pub prosodic_chunking: PreparationReadiness,
    pub sense_groups: PreparationReadiness,
    pub citation_structure: PreparationReadiness,
    pub predicted_structure: PreparationReadiness,
}

impl LearningPreparationRunStatus {
    pub fn is_active(self) -> bool {
        matches!(self, Self::Queued | Self::Running | Self::Cancelling)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LearningPreparationRun {
    pub id: LearningPreparationRunId,
    pub target: FoundationPreparationTarget,
    pub target_key: String,
    pub input_fingerprint: String,
    pub plan_fingerprint: String,
    pub intent: FoundationPreparationIntent,
    pub status: LearningPreparationRunStatus,
    pub plan: FoundationPreparationPlan,
    pub revision: u64,
    pub retry_of_run_id: Option<LearningPreparationRunId>,
    pub error: Option<String>,
    pub created_at_ms: u64,
    pub updated_at_ms: u64,
}

impl LearningPreparationRun {
    pub fn readiness(&self) -> FoundationActivityReadiness {
        let word = readiness_for(&self.plan.word_timeline.state);
        let prosody = readiness_for(&self.plan.prosody.state);
        let audible_structure = derived_readiness(&word, &self.plan.audible_structure);
        FoundationActivityReadiness {
            word_following: word,
            prosodic_chunking: prosody,
            sense_groups: readiness_for(&self.plan.sense_group.state),
            citation_structure: audible_structure.clone(),
            predicted_structure: audible_structure,
        }
    }

    pub fn start(&mut self, now_ms: u64) -> Result<(), ApplicationError> {
        if self.status != LearningPreparationRunStatus::Queued {
            return Err(ApplicationError::Conflict(
                "learning preparation run is not queued",
            ));
        }
        self.status = LearningPreparationRunStatus::Running;
        self.bump(now_ms);
        Ok(())
    }

    pub fn request_cancel(&mut self, now_ms: u64) -> Result<(), ApplicationError> {
        if !self.status.is_active() {
            return Err(ApplicationError::Conflict(
                "learning preparation run is already terminal",
            ));
        }
        self.status = LearningPreparationRunStatus::Cancelling;
        self.bump(now_ms);
        Ok(())
    }

    pub fn begin_word_timeline(&mut self, now_ms: u64) -> Result<(), ApplicationError> {
        ensure_running(self.status)?;
        begin_step(&mut self.plan.word_timeline.state)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn complete_word_timeline(
        &mut self,
        artifact: ReusableFoundationArtifact,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        complete_step(&mut self.plan.word_timeline.state, artifact)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn fail_word_timeline(
        &mut self,
        reason: impl Into<String>,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        fail_step(&mut self.plan.word_timeline.state, reason)?;
        if matches!(self.plan.prosody.state, PreparationStepState::Pending) {
            self.plan.prosody.state = PreparationStepState::Skipped {
                reason: "word_timeline_failed".into(),
            };
        }
        self.bump(now_ms);
        Ok(())
    }

    pub fn begin_prosody(&mut self, now_ms: u64) -> Result<(), ApplicationError> {
        ensure_running(self.status)?;
        if !matches!(
            self.plan.word_timeline.state,
            PreparationStepState::Ready { .. }
        ) {
            return Err(ApplicationError::Conflict(
                "prosody preparation requires a ready word timeline",
            ));
        }
        begin_step(&mut self.plan.prosody.state)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn complete_prosody(
        &mut self,
        artifact: ReusableFoundationArtifact,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        complete_step(&mut self.plan.prosody.state, artifact)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn fail_prosody(
        &mut self,
        reason: impl Into<String>,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        fail_step(&mut self.plan.prosody.state, reason)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn begin_sense_group(&mut self, now_ms: u64) -> Result<(), ApplicationError> {
        ensure_running(self.status)?;
        begin_step(&mut self.plan.sense_group.state)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn complete_sense_group(
        &mut self,
        artifact: ReusableFoundationArtifact,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        complete_step(&mut self.plan.sense_group.state, artifact)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn fail_sense_group(
        &mut self,
        reason: impl Into<String>,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        fail_step(&mut self.plan.sense_group.state, reason)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn invalidate_word_timeline_artifact(&mut self, now_ms: u64) {
        invalidate_ready_step(&mut self.plan.word_timeline.state);
        invalidate_dependent_step(&mut self.plan.prosody.state);
        self.bump(now_ms);
    }

    pub fn invalidate_prosody_artifact(&mut self, now_ms: u64) {
        invalidate_ready_step(&mut self.plan.prosody.state);
        self.bump(now_ms);
    }

    pub fn invalidate_sense_group_artifact(&mut self, now_ms: u64) {
        invalidate_ready_step(&mut self.plan.sense_group.state);
        self.bump(now_ms);
    }

    pub fn finish_cancellation(&mut self, now_ms: u64) {
        cancel_non_terminal(&mut self.plan.word_timeline.state);
        cancel_non_terminal(&mut self.plan.prosody.state);
        cancel_non_terminal(&mut self.plan.sense_group.state);
        self.status = LearningPreparationRunStatus::Cancelled;
        self.bump(now_ms);
    }

    pub fn recover_after_restart(&mut self, now_ms: u64) {
        if self.status == LearningPreparationRunStatus::Running {
            reset_running(&mut self.plan.word_timeline.state);
            reset_running(&mut self.plan.prosody.state);
            reset_running(&mut self.plan.sense_group.state);
            self.status = LearningPreparationRunStatus::Queued;
            self.bump(now_ms);
        }
    }

    pub fn invalidate(&mut self, now_ms: u64) {
        cancel_non_terminal(&mut self.plan.word_timeline.state);
        cancel_non_terminal(&mut self.plan.prosody.state);
        cancel_non_terminal(&mut self.plan.sense_group.state);
        self.status = LearningPreparationRunStatus::Failed;
        self.error = Some(INPUTS_CHANGED_ERROR.into());
        self.bump(now_ms);
    }

    pub fn fail_execution(&mut self, reason: impl Into<String>, now_ms: u64) {
        if !matches!(
            self.status,
            LearningPreparationRunStatus::Queued | LearningPreparationRunStatus::Running
        ) {
            return;
        }
        let reason = reason.into();
        fail_non_terminal(&mut self.plan.word_timeline.state, &reason);
        fail_non_terminal(&mut self.plan.prosody.state, &reason);
        fail_non_terminal(&mut self.plan.sense_group.state, &reason);
        self.status = LearningPreparationRunStatus::Failed;
        self.error = Some(reason);
        self.bump(now_ms);
    }

    pub fn settle(&mut self, now_ms: u64) {
        if self.status == LearningPreparationRunStatus::Running && self.plan.all_terminal() {
            self.status = if self.plan.has_required_failure() {
                LearningPreparationRunStatus::Failed
            } else {
                LearningPreparationRunStatus::Completed
            };
            self.bump(now_ms);
        }
    }

    fn bump(&mut self, now_ms: u64) {
        self.revision += 1;
        self.updated_at_ms = now_ms;
    }
}

fn ensure_running(status: LearningPreparationRunStatus) -> Result<(), ApplicationError> {
    if status != LearningPreparationRunStatus::Running {
        return Err(ApplicationError::Conflict(
            "learning preparation run is not running",
        ));
    }
    Ok(())
}

fn begin_step(state: &mut PreparationStepState) -> Result<(), ApplicationError> {
    if !matches!(state, PreparationStepState::Pending) {
        return Err(ApplicationError::Conflict(
            "learning preparation step is not pending",
        ));
    }
    *state = PreparationStepState::Running;
    Ok(())
}

fn complete_step(
    state: &mut PreparationStepState,
    artifact: ReusableFoundationArtifact,
) -> Result<(), ApplicationError> {
    if !matches!(state, PreparationStepState::Running) {
        return Err(ApplicationError::Conflict(
            "learning preparation step is not running",
        ));
    }
    *state = PreparationStepState::Ready {
        artifact_ref: artifact.artifact_ref,
        input_fingerprint: artifact.input_fingerprint,
        reused: false,
    };
    Ok(())
}

fn fail_step(
    state: &mut PreparationStepState,
    reason: impl Into<String>,
) -> Result<(), ApplicationError> {
    if !matches!(state, PreparationStepState::Running) {
        return Err(ApplicationError::Conflict(
            "learning preparation step is not running",
        ));
    }
    *state = PreparationStepState::Failed {
        reason: reason.into(),
    };
    Ok(())
}

fn invalidate_ready_step(state: &mut PreparationStepState) {
    if matches!(state, PreparationStepState::Ready { .. }) {
        *state = PreparationStepState::Pending;
    }
}

fn invalidate_dependent_step(state: &mut PreparationStepState) {
    if matches!(
        state,
        PreparationStepState::Pending
            | PreparationStepState::Running
            | PreparationStepState::Ready { .. }
    ) {
        *state = PreparationStepState::Pending;
    }
}

fn readiness_for(state: &PreparationStepState) -> PreparationReadiness {
    match state {
        PreparationStepState::Ready { .. } => PreparationReadiness::Ready,
        PreparationStepState::Pending | PreparationStepState::Running => {
            PreparationReadiness::Preparing
        }
        PreparationStepState::Skipped { reason } => PreparationReadiness::Unavailable {
            reason: reason.clone(),
        },
        PreparationStepState::Cancelled => PreparationReadiness::Unavailable {
            reason: "preparation_cancelled".into(),
        },
        PreparationStepState::Failed { reason } => PreparationReadiness::Failed {
            reason: reason.clone(),
        },
    }
}

fn derived_readiness(
    word_timeline: &PreparationReadiness,
    availability: &FoundationDerivedAvailability,
) -> PreparationReadiness {
    match availability {
        FoundationDerivedAvailability::Available => word_timeline.clone(),
        FoundationDerivedAvailability::Unavailable { reason } => {
            PreparationReadiness::Unavailable {
                reason: reason.clone(),
            }
        }
    }
}

fn cancel_non_terminal(state: &mut PreparationStepState) {
    if !state.is_terminal() {
        *state = PreparationStepState::Cancelled;
    }
}

fn fail_non_terminal(state: &mut PreparationStepState, reason: &str) {
    if !state.is_terminal() {
        *state = PreparationStepState::Failed {
            reason: reason.into(),
        };
    }
}

fn reset_running(state: &mut PreparationStepState) {
    if matches!(state, PreparationStepState::Running) {
        *state = PreparationStepState::Pending;
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CreateLearningPreparationRun {
    Created(LearningPreparationRun),
    Existing(LearningPreparationRun),
    InputChanged(LearningPreparationRun),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LearningPreparationRunTransition {
    Applied(LearningPreparationRun),
    Rejected(LearningPreparationRun),
}

pub trait LearningPreparationRunRepository: Send + Sync {
    fn create_active(
        &self,
        run: &LearningPreparationRun,
    ) -> Result<CreateLearningPreparationRun, ApplicationError>;
    fn get(
        &self,
        id: &LearningPreparationRunId,
    ) -> Result<Option<LearningPreparationRun>, ApplicationError>;
    fn transition(
        &self,
        expected_revision: u64,
        run: &LearningPreparationRun,
    ) -> Result<LearningPreparationRunTransition, ApplicationError>;
    fn recover_active(&self, now_ms: u64) -> Result<Vec<LearningPreparationRun>, ApplicationError>;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FoundationPreparationInspection {
    pub target: FoundationPreparationTarget,
    pub input_fingerprint: String,
    pub source: FoundationSourceInspection,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PrepareFoundationResult {
    Run(Box<LearningPreparationRun>),
    Replaced {
        run: Box<LearningPreparationRun>,
        invalidated_run_id: LearningPreparationRunId,
    },
    SelectionRequired(SelectionRequiredReason),
    Unavailable(String),
}

pub struct LearningPreparationUseCases {
    runs: Arc<dyn LearningPreparationRunRepository>,
    inspector: Arc<dyn FoundationPreparationInspector>,
}

impl LearningPreparationUseCases {
    pub fn new(
        runs: Arc<dyn LearningPreparationRunRepository>,
        inspector: Arc<dyn FoundationPreparationInspector>,
    ) -> Self {
        Self { runs, inspector }
    }

    pub fn inspect(
        &self,
        target: FoundationPreparationTarget,
    ) -> Result<FoundationPreparationInspection, ApplicationError> {
        target.validate()?;
        let input_fingerprint = target.input_fingerprint();
        let source = self.inspector.inspect(&target)?;
        Ok(FoundationPreparationInspection {
            target,
            input_fingerprint,
            source,
        })
    }

    pub fn prepare(
        &self,
        target: FoundationPreparationTarget,
        request: FoundationPreparationRequest,
        now_ms: u64,
    ) -> Result<PrepareFoundationResult, ApplicationError> {
        let inspection = self.inspect(target)?;
        let inputs = match inspection.source {
            FoundationSourceInspection::Selected(inputs) => inputs,
            FoundationSourceInspection::SelectionRequired { reason } => {
                return Ok(PrepareFoundationResult::SelectionRequired(reason));
            }
            FoundationSourceInspection::Unavailable { reason } => {
                return Ok(PrepareFoundationResult::Unavailable(reason));
            }
        };
        let plan = FoundationPreparationPlan::from_inputs(inputs);
        let plan_fingerprint = plan_fingerprint(request.intent, &plan.audible_structure);
        let run = LearningPreparationRun {
            id: LearningPreparationRunId::from_fingerprint(&format!(
                "{}:{plan_fingerprint}:{now_ms}",
                inspection.input_fingerprint,
            )),
            target_key: inspection.target.target_key(),
            input_fingerprint: inspection.input_fingerprint,
            plan_fingerprint,
            target: inspection.target,
            intent: request.intent,
            status: LearningPreparationRunStatus::Queued,
            plan,
            revision: 0,
            retry_of_run_id: None,
            error: None,
            created_at_ms: now_ms,
            updated_at_ms: now_ms,
        };
        let (run, invalidated_run_id) = self.create_replacing_stale_input(run, now_ms)?;
        Ok(match invalidated_run_id {
            Some(invalidated_run_id) => PrepareFoundationResult::Replaced {
                run: Box::new(run),
                invalidated_run_id,
            },
            None => PrepareFoundationResult::Run(Box::new(run)),
        })
    }

    pub fn get_run(
        &self,
        id: &LearningPreparationRunId,
    ) -> Result<LearningPreparationRun, ApplicationError> {
        self.runs
            .get(id)?
            .ok_or(ApplicationError::NotFound("learning preparation run"))
    }

    pub fn cancel(
        &self,
        id: &LearningPreparationRunId,
        now_ms: u64,
    ) -> Result<LearningPreparationRun, ApplicationError> {
        let mut run = self.get_run(id)?;
        loop {
            if run.status == LearningPreparationRunStatus::Cancelling {
                return Ok(run);
            }
            let expected_revision = run.revision;
            run.request_cancel(now_ms)?;
            match self.runs.transition(expected_revision, &run)? {
                LearningPreparationRunTransition::Applied(run) => return Ok(run),
                LearningPreparationRunTransition::Rejected(current) => run = current,
            }
        }
    }

    pub fn retry(
        &self,
        id: &LearningPreparationRunId,
        now_ms: u64,
    ) -> Result<LearningPreparationRun, ApplicationError> {
        let previous = self.get_run(id)?;
        if previous.status.is_active()
            || previous.status == LearningPreparationRunStatus::Completed
            || previous.error.as_deref() == Some(INPUTS_CHANGED_ERROR)
        {
            return Err(ApplicationError::Conflict(
                "learning preparation run cannot be retried",
            ));
        }
        let inputs = match self.inspector.inspect(&previous.target)? {
            FoundationSourceInspection::Selected(inputs) => inputs,
            FoundationSourceInspection::SelectionRequired { .. } => {
                return Err(ApplicationError::Conflict(
                    "learning preparation source selection changed before retry",
                ));
            }
            FoundationSourceInspection::Unavailable { .. } => {
                return Err(ApplicationError::Conflict(
                    "learning preparation source is unavailable before retry",
                ));
            }
        };
        let mut refreshed_plan = FoundationPreparationPlan::from_inputs(inputs);
        preserve_ready(
            &mut refreshed_plan.word_timeline.state,
            &previous.plan.word_timeline.state,
        );
        preserve_ready(
            &mut refreshed_plan.prosody.state,
            &previous.plan.prosody.state,
        );
        preserve_ready(
            &mut refreshed_plan.sense_group.state,
            &previous.plan.sense_group.state,
        );
        let mut run = previous.clone();
        run.id = LearningPreparationRunId::from_fingerprint(&format!(
            "{}:retry:{now_ms}",
            previous.id.as_str()
        ));
        run.status = LearningPreparationRunStatus::Queued;
        run.revision = 0;
        run.retry_of_run_id = Some(previous.id);
        run.error = None;
        run.plan = refreshed_plan;
        run.plan_fingerprint = plan_fingerprint(run.intent, &run.plan.audible_structure);
        run.created_at_ms = now_ms;
        run.updated_at_ms = now_ms;
        match self.runs.create_active(&run)? {
            CreateLearningPreparationRun::Created(run)
            | CreateLearningPreparationRun::Existing(run) => Ok(run),
            CreateLearningPreparationRun::InputChanged(_) => Err(ApplicationError::Conflict(
                "learning preparation inputs changed before retry",
            )),
        }
    }

    pub fn recover_startup(
        &self,
        now_ms: u64,
    ) -> Result<Vec<LearningPreparationRun>, ApplicationError> {
        self.runs.recover_active(now_ms)
    }

    fn create_replacing_stale_input(
        &self,
        run: LearningPreparationRun,
        now_ms: u64,
    ) -> Result<(LearningPreparationRun, Option<LearningPreparationRunId>), ApplicationError> {
        match self.runs.create_active(&run)? {
            CreateLearningPreparationRun::Created(run)
            | CreateLearningPreparationRun::Existing(run) => Ok((run, None)),
            CreateLearningPreparationRun::InputChanged(mut previous) => {
                let invalidated_run_id = previous.id.clone();
                let expected_revision = previous.revision;
                previous.invalidate(now_ms);
                match self.runs.transition(expected_revision, &previous)? {
                    LearningPreparationRunTransition::Applied(_) => {}
                    LearningPreparationRunTransition::Rejected(_) => {
                        return Err(ApplicationError::Conflict(
                            "learning preparation run changed concurrently",
                        ));
                    }
                }
                match self.runs.create_active(&run)? {
                    CreateLearningPreparationRun::Created(run)
                    | CreateLearningPreparationRun::Existing(run) => {
                        Ok((run, Some(invalidated_run_id)))
                    }
                    CreateLearningPreparationRun::InputChanged(_) => {
                        Err(ApplicationError::Conflict(
                            "learning preparation inputs changed concurrently",
                        ))
                    }
                }
            }
        }
    }
}

fn plan_fingerprint(
    intent: FoundationPreparationIntent,
    audible_structure: &FoundationDerivedAvailability,
) -> String {
    let audible_structure = match audible_structure {
        FoundationDerivedAvailability::Available => "audible-structure:available".into(),
        FoundationDerivedAvailability::Unavailable { reason } => {
            format!("audible-structure:unavailable:{reason}")
        }
    };
    digest_fields(
        FOUNDATION_PLANNER_VERSION,
        &[
            match intent {
                FoundationPreparationIntent::RecommendedFoundation => "recommended_foundation",
            },
            "word:required",
            "prosody:required",
            "sense-group:required",
            "citation-structure:derived",
            "predicted-structure:derived",
            &audible_structure,
        ],
    )
}

fn preserve_ready(current: &mut PreparationStepState, previous: &PreparationStepState) {
    if matches!(previous, PreparationStepState::Ready { .. }) {
        *current = previous.clone();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reusable(name: &str) -> FoundationAssetAvailability {
        FoundationAssetAvailability::Reusable(ReusableFoundationArtifact {
            artifact_ref: name.into(),
            input_fingerprint: format!("{name}-fp"),
        })
    }

    fn inputs() -> FoundationInputs {
        FoundationInputs {
            word_timeline: reusable("word"),
            word_timeline_precision: WordTimelinePrecision::Exact,
            prosody: FoundationAssetAvailability::Buildable,
            sense_group: FoundationAssetAvailability::Buildable,
            audible_structure: FoundationDerivedAvailability::Available,
        }
    }

    #[test]
    fn all_foundation_resources_are_required() {
        let plan = FoundationPreparationPlan::from_inputs(inputs());

        assert_eq!(
            plan.word_timeline.requirement,
            PreparationRequirement::Required
        );
        assert_eq!(plan.prosody.requirement, PreparationRequirement::Required);
        assert_eq!(
            plan.sense_group.requirement,
            PreparationRequirement::Required
        );
    }

    #[test]
    fn unavailable_word_skips_dependent_prosody_but_not_sense_group() {
        let plan = FoundationPreparationPlan::from_inputs(FoundationInputs {
            word_timeline: FoundationAssetAvailability::Unavailable {
                reason: "word timeline unavailable".into(),
            },
            prosody: FoundationAssetAvailability::Buildable,
            sense_group: reusable("sense"),
            ..inputs()
        });

        assert!(plan.all_terminal());
        assert!(plan.has_required_failure());
        assert_eq!(
            plan.prosody.state,
            PreparationStepState::Skipped {
                reason: "word_timeline_unavailable".into()
            }
        );
        assert!(matches!(
            plan.sense_group.state,
            PreparationStepState::Ready { .. }
        ));
    }

    #[test]
    fn invalid_ready_artifacts_return_to_pending_for_rebuild() {
        let mut run = LearningPreparationRun {
            id: LearningPreparationRunId::parse("run").unwrap(),
            target: FoundationPreparationTarget {
                media_id: MediaId::parse("media").unwrap(),
                media_fingerprint: "media-fp".into(),
                subtitle_track_id: SubtitleTrackId::parse("track").unwrap(),
                subtitle_fingerprint: "subtitle-fp".into(),
            },
            target_key: "target".into(),
            input_fingerprint: "input".into(),
            plan_fingerprint: "plan".into(),
            intent: FoundationPreparationIntent::RecommendedFoundation,
            status: LearningPreparationRunStatus::Running,
            plan: FoundationPreparationPlan::from_inputs(FoundationInputs {
                prosody: reusable("prosody"),
                sense_group: reusable("sense"),
                ..inputs()
            }),
            revision: 0,
            retry_of_run_id: None,
            error: None,
            created_at_ms: 1,
            updated_at_ms: 1,
        };

        run.invalidate_word_timeline_artifact(2);
        run.invalidate_sense_group_artifact(3);

        assert_eq!(run.plan.word_timeline.state, PreparationStepState::Pending);
        assert_eq!(run.plan.prosody.state, PreparationStepState::Pending);
        assert_eq!(run.plan.sense_group.state, PreparationStepState::Pending);
    }

    #[test]
    fn language_capability_changes_the_plan_identity() {
        assert_ne!(
            plan_fingerprint(
                FoundationPreparationIntent::RecommendedFoundation,
                &FoundationDerivedAvailability::Available,
            ),
            plan_fingerprint(
                FoundationPreparationIntent::RecommendedFoundation,
                &FoundationDerivedAvailability::Unavailable {
                    reason: "unsupported:zh-hans".into(),
                },
            )
        );
    }

    #[test]
    fn legacy_persisted_plan_with_chunk_timeline_field_still_deserializes() {
        // R3 renamed the foundation chunk slot to `prosody`; previously
        // persisted run JSON used `chunk_timeline` and must keep parsing.
        let json = serde_json::json!({
            "word_timeline": {
                "requirement": "required",
                "precision": "exact",
                "state": { "state": "ready", "artifact_ref": "word", "input_fingerprint": "w", "reused": true }
            },
            "chunk_timeline": {
                "requirement": "required",
                "state": { "state": "ready", "artifact_ref": "chunk", "input_fingerprint": "c", "reused": true }
            },
            "sense_group": {
                "requirement": "required",
                "state": { "state": "ready", "artifact_ref": "sense", "input_fingerprint": "s", "reused": true }
            },
            "audible_structure": { "state": "unavailable", "reason": "unsupported_language" }
        });
        let plan: FoundationPreparationPlan = serde_json::from_value(json).unwrap();
        let PreparationStepState::Ready { artifact_ref, .. } = &plan.prosody.state else {
            panic!("legacy chunk_timeline slot must map to the prosody slot");
        };
        assert_eq!(artifact_ref, "chunk");
    }
}
