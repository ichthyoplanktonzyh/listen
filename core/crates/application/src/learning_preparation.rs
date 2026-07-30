use std::sync::Arc;

use domain::{MediaId, SubtitleTrackId};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::ApplicationError;

const FOUNDATION_PLANNER_VERSION: &str = "foundation-v1";
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
pub struct ExactAudioTrack {
    pub stream_index: u32,
    pub fingerprint: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationPreparationTarget {
    pub media_id: MediaId,
    pub media_fingerprint: String,
    pub subtitle_track_id: SubtitleTrackId,
    pub subtitle_fingerprint: String,
    pub audio_track: ExactAudioTrack,
}

impl FoundationPreparationTarget {
    pub fn target_key(&self) -> String {
        digest_fields(
            "learning-preparation-target",
            &[
                self.media_id.as_str(),
                self.subtitle_track_id.as_str(),
                &self.audio_track.stream_index.to_string(),
            ],
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
                &self.audio_track.stream_index.to_string(),
                &self.audio_track.fingerprint,
            ],
        )
    }

    fn validate(&self) -> Result<(), ApplicationError> {
        if self.media_fingerprint.trim().is_empty()
            || self.subtitle_fingerprint.trim().is_empty()
            || self.audio_track.fingerprint.trim().is_empty()
        {
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PreparationConsent {
    pub allow_downloads: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationPreparationRequest {
    pub intent: FoundationPreparationIntent,
    pub consent: PreparationConsent,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SelectionRequiredReason {
    SubtitleTrackUnavailable,
    AudioTrackUnavailable,
    AudioTrackAmbiguous,
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
    Buildable { requires_download: bool },
    Unavailable { reason: String },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WordTimelinePrecision {
    Exact,
    Estimated,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationInputs {
    pub word_timeline: FoundationAssetAvailability,
    pub word_timeline_precision: WordTimelinePrecision,
    pub sound_line: FoundationAssetAvailability,
    pub chunk_timeline: FoundationAssetAvailability,
    pub rule_sense_group: FoundationAssetAvailability,
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
    Optional,
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
pub struct SoundLinePreparation {
    pub requirement: PreparationRequirement,
    pub child_job_ref: Option<String>,
    pub state: PreparationStepState,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChunkTimelineInput {
    WordTimeline,
    SoundLine,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChunkTimelinePreparation {
    pub requirement: PreparationRequirement,
    pub input: ChunkTimelineInput,
    pub state: PreparationStepState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuleSenseGroupPreparation {
    pub requirement: PreparationRequirement,
    pub state: PreparationStepState,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FoundationPreparationPlan {
    pub word_timeline: WordTimelinePreparation,
    pub sound_line: SoundLinePreparation,
    pub chunk_timeline: ChunkTimelinePreparation,
    pub rule_sense_group: RuleSenseGroupPreparation,
}

impl FoundationPreparationPlan {
    fn from_inputs(inputs: FoundationInputs, consent: PreparationConsent) -> Self {
        let word_timeline = WordTimelinePreparation {
            requirement: PreparationRequirement::Required,
            precision: inputs.word_timeline_precision,
            state: initial_state(inputs.word_timeline, consent, true),
        };
        let mut sound_line = SoundLinePreparation {
            requirement: PreparationRequirement::Optional,
            child_job_ref: None,
            state: initial_state(inputs.sound_line, consent, false),
        };
        let sound_line_available = !matches!(
            sound_line.state,
            PreparationStepState::Skipped { .. } | PreparationStepState::Failed { .. }
        );
        let mut chunk_timeline = ChunkTimelinePreparation {
            requirement: PreparationRequirement::Required,
            input: if sound_line_available {
                ChunkTimelineInput::SoundLine
            } else {
                ChunkTimelineInput::WordTimeline
            },
            state: initial_state(inputs.chunk_timeline, consent, true),
        };
        if matches!(
            word_timeline.state,
            PreparationStepState::Skipped { .. } | PreparationStepState::Failed { .. }
        ) {
            if matches!(sound_line.state, PreparationStepState::Pending) {
                sound_line.state = PreparationStepState::Skipped {
                    reason: "word_timeline_unavailable".into(),
                };
            }
            if matches!(chunk_timeline.state, PreparationStepState::Pending) {
                chunk_timeline.state = PreparationStepState::Skipped {
                    reason: "word_timeline_unavailable".into(),
                };
            }
        }
        let rule_sense_group = RuleSenseGroupPreparation {
            requirement: PreparationRequirement::Required,
            state: initial_state(inputs.rule_sense_group, consent, true),
        };
        Self {
            word_timeline,
            sound_line,
            chunk_timeline,
            rule_sense_group,
        }
    }

    fn all_terminal(&self) -> bool {
        self.word_timeline.state.is_terminal()
            && self.sound_line.state.is_terminal()
            && self.chunk_timeline.state.is_terminal()
            && self.rule_sense_group.state.is_terminal()
    }

    fn has_required_failure(&self) -> bool {
        [
            &self.word_timeline.state,
            &self.chunk_timeline.state,
            &self.rule_sense_group.state,
        ]
        .into_iter()
        .any(|state| matches!(state, PreparationStepState::Failed { .. }))
    }
}

fn initial_state(
    availability: FoundationAssetAvailability,
    consent: PreparationConsent,
    required: bool,
) -> PreparationStepState {
    match availability {
        FoundationAssetAvailability::Reusable(artifact) => PreparationStepState::Ready {
            artifact_ref: artifact.artifact_ref,
            input_fingerprint: artifact.input_fingerprint,
            reused: true,
        },
        FoundationAssetAvailability::Buildable {
            requires_download: true,
        } if !consent.allow_downloads => PreparationStepState::Skipped {
            reason: "download_consent_required".into(),
        },
        FoundationAssetAvailability::Buildable { .. } => PreparationStepState::Pending,
        FoundationAssetAvailability::Unavailable { reason } if required => {
            PreparationStepState::Failed { reason }
        }
        FoundationAssetAvailability::Unavailable { reason } => {
            PreparationStepState::Skipped { reason }
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
    pub approximate_chunking: PreparationReadiness,
    pub real_listening_flow: PreparationReadiness,
    pub rule_sense_groups: PreparationReadiness,
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
        let chunk = readiness_for(&self.plan.chunk_timeline.state);
        let sound_line = readiness_for(&self.plan.sound_line.state);
        let real_listening_flow = match (&sound_line, &chunk) {
            (PreparationReadiness::Ready, PreparationReadiness::Ready) => {
                if self.plan.word_timeline.precision == WordTimelinePrecision::Exact {
                    PreparationReadiness::Ready
                } else {
                    PreparationReadiness::Unavailable {
                        reason: "estimated_word_timeline".into(),
                    }
                }
            }
            (PreparationReadiness::Failed { reason }, _)
            | (_, PreparationReadiness::Failed { reason }) => PreparationReadiness::Failed {
                reason: reason.clone(),
            },
            (PreparationReadiness::Unavailable { reason }, _)
            | (_, PreparationReadiness::Unavailable { reason }) => {
                PreparationReadiness::Unavailable {
                    reason: reason.clone(),
                }
            }
            _ => PreparationReadiness::Preparing,
        };
        FoundationActivityReadiness {
            word_following: word,
            approximate_chunking: chunk,
            real_listening_flow,
            rule_sense_groups: readiness_for(&self.plan.rule_sense_group.state),
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
        self.bump(now_ms);
        Ok(())
    }

    pub fn begin_sound_line(
        &mut self,
        child_job_ref: impl Into<String>,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        ensure_running(self.status)?;
        if !matches!(
            self.plan.word_timeline.state,
            PreparationStepState::Ready { .. }
        ) {
            return Err(ApplicationError::Conflict(
                "sound-line preparation requires a ready word timeline",
            ));
        }
        let child_job_ref = child_job_ref.into();
        if child_job_ref.trim().is_empty() {
            return Err(ApplicationError::Validation(
                "sound-line child job reference",
            ));
        }
        begin_step(&mut self.plan.sound_line.state)?;
        self.plan.sound_line.child_job_ref = Some(child_job_ref);
        self.bump(now_ms);
        Ok(())
    }

    pub fn complete_sound_line(
        &mut self,
        artifact: ReusableFoundationArtifact,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        complete_step(&mut self.plan.sound_line.state, artifact)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn fail_sound_line(
        &mut self,
        reason: impl Into<String>,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        fail_step(&mut self.plan.sound_line.state, reason)?;
        if matches!(
            self.plan.word_timeline.state,
            PreparationStepState::Ready { .. }
        ) {
            self.plan.chunk_timeline.input = ChunkTimelineInput::WordTimeline;
        }
        self.bump(now_ms);
        Ok(())
    }

    pub fn begin_chunk_timeline(&mut self, now_ms: u64) -> Result<(), ApplicationError> {
        ensure_running(self.status)?;
        let input_ready = match self.plan.chunk_timeline.input {
            ChunkTimelineInput::WordTimeline => matches!(
                self.plan.word_timeline.state,
                PreparationStepState::Ready { .. }
            ),
            ChunkTimelineInput::SoundLine => matches!(
                self.plan.sound_line.state,
                PreparationStepState::Ready { .. }
            ),
        };
        if !input_ready {
            return Err(ApplicationError::Conflict(
                "chunk preparation input is not ready",
            ));
        }
        begin_step(&mut self.plan.chunk_timeline.state)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn complete_chunk_timeline(
        &mut self,
        artifact: ReusableFoundationArtifact,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        complete_step(&mut self.plan.chunk_timeline.state, artifact)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn fail_chunk_timeline(
        &mut self,
        reason: impl Into<String>,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        fail_step(&mut self.plan.chunk_timeline.state, reason)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn begin_rule_sense_group(&mut self, now_ms: u64) -> Result<(), ApplicationError> {
        ensure_running(self.status)?;
        begin_step(&mut self.plan.rule_sense_group.state)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn complete_rule_sense_group(
        &mut self,
        artifact: ReusableFoundationArtifact,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        complete_step(&mut self.plan.rule_sense_group.state, artifact)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn fail_rule_sense_group(
        &mut self,
        reason: impl Into<String>,
        now_ms: u64,
    ) -> Result<(), ApplicationError> {
        fail_step(&mut self.plan.rule_sense_group.state, reason)?;
        self.bump(now_ms);
        Ok(())
    }

    pub fn finish_cancellation(&mut self, now_ms: u64) {
        cancel_non_terminal(&mut self.plan.word_timeline.state);
        cancel_non_terminal(&mut self.plan.sound_line.state);
        cancel_non_terminal(&mut self.plan.chunk_timeline.state);
        cancel_non_terminal(&mut self.plan.rule_sense_group.state);
        self.status = LearningPreparationRunStatus::Cancelled;
        self.bump(now_ms);
    }

    pub fn recover_after_restart(&mut self, now_ms: u64) {
        if self.status == LearningPreparationRunStatus::Running {
            reset_running(&mut self.plan.word_timeline.state);
            reset_running(&mut self.plan.sound_line.state);
            reset_running(&mut self.plan.chunk_timeline.state);
            reset_running(&mut self.plan.rule_sense_group.state);
            self.status = LearningPreparationRunStatus::Queued;
            self.bump(now_ms);
        }
    }

    pub fn invalidate(&mut self, now_ms: u64) {
        cancel_non_terminal(&mut self.plan.word_timeline.state);
        cancel_non_terminal(&mut self.plan.sound_line.state);
        cancel_non_terminal(&mut self.plan.chunk_timeline.state);
        cancel_non_terminal(&mut self.plan.rule_sense_group.state);
        self.status = LearningPreparationRunStatus::Failed;
        self.error = Some(INPUTS_CHANGED_ERROR.into());
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

fn cancel_non_terminal(state: &mut PreparationStepState) {
    if !state.is_terminal() {
        *state = PreparationStepState::Cancelled;
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
        let plan = FoundationPreparationPlan::from_inputs(inputs, request.consent);
        let plan_fingerprint = plan_fingerprint(&plan)?;
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
        self.create_replacing_stale_input(run, now_ms)
            .map(Box::new)
            .map(PrepareFoundationResult::Run)
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
        let expected_revision = run.revision;
        run.request_cancel(now_ms)?;
        match self.runs.transition(expected_revision, &run)? {
            LearningPreparationRunTransition::Applied(run) => Ok(run),
            LearningPreparationRunTransition::Rejected(_) => Err(ApplicationError::Conflict(
                "learning preparation run changed concurrently",
            )),
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
        let mut run = previous.clone();
        run.id = LearningPreparationRunId::from_fingerprint(&format!(
            "{}:retry:{now_ms}",
            previous.id.as_str()
        ));
        run.status = LearningPreparationRunStatus::Queued;
        run.revision = 0;
        run.retry_of_run_id = Some(previous.id);
        run.error = None;
        run.created_at_ms = now_ms;
        run.updated_at_ms = now_ms;
        reset_retryable(&mut run.plan.word_timeline.state);
        reset_retryable(&mut run.plan.sound_line.state);
        if matches!(run.plan.sound_line.state, PreparationStepState::Pending) {
            run.plan.sound_line.child_job_ref = None;
        }
        reset_retryable(&mut run.plan.chunk_timeline.state);
        reset_retryable(&mut run.plan.rule_sense_group.state);
        run.plan_fingerprint = plan_fingerprint(&run.plan)?;
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
    ) -> Result<LearningPreparationRun, ApplicationError> {
        match self.runs.create_active(&run)? {
            CreateLearningPreparationRun::Created(run)
            | CreateLearningPreparationRun::Existing(run) => Ok(run),
            CreateLearningPreparationRun::InputChanged(mut previous) => {
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
                    | CreateLearningPreparationRun::Existing(run) => Ok(run),
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

fn plan_fingerprint(plan: &FoundationPreparationPlan) -> Result<String, ApplicationError> {
    let encoded = serde_json::to_vec(plan)
        .map_err(|error| ApplicationError::Repository(error.to_string()))?;
    let encoded = hex::encode(encoded);
    Ok(digest_fields(FOUNDATION_PLANNER_VERSION, &[&encoded]))
}

fn reset_retryable(state: &mut PreparationStepState) {
    if matches!(
        state,
        PreparationStepState::Failed { .. } | PreparationStepState::Cancelled
    ) {
        *state = PreparationStepState::Pending;
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
            sound_line: FoundationAssetAvailability::Buildable {
                requires_download: true,
            },
            chunk_timeline: FoundationAssetAvailability::Buildable {
                requires_download: false,
            },
            rule_sense_group: FoundationAssetAvailability::Buildable {
                requires_download: false,
            },
        }
    }

    #[test]
    fn no_download_consent_uses_word_timeline_for_chunks() {
        let plan = FoundationPreparationPlan::from_inputs(
            inputs(),
            PreparationConsent {
                allow_downloads: false,
            },
        );
        assert_eq!(
            plan.sound_line.state,
            PreparationStepState::Skipped {
                reason: "download_consent_required".into()
            }
        );
        assert_eq!(plan.chunk_timeline.input, ChunkTimelineInput::WordTimeline);
    }

    #[test]
    fn optional_sound_line_failure_does_not_fail_completed_parent() {
        let mut plan = FoundationPreparationPlan::from_inputs(
            FoundationInputs {
                sound_line: FoundationAssetAvailability::Unavailable {
                    reason: "model unavailable".into(),
                },
                chunk_timeline: reusable("chunk"),
                rule_sense_group: reusable("sense"),
                ..inputs()
            },
            PreparationConsent {
                allow_downloads: true,
            },
        );
        assert_eq!(plan.chunk_timeline.input, ChunkTimelineInput::WordTimeline);
        assert!(plan.all_terminal());
        assert!(!plan.has_required_failure());

        plan.word_timeline.precision = WordTimelinePrecision::Estimated;
        assert!(!matches!(
            plan.sound_line.state,
            PreparationStepState::Ready { .. }
        ));
    }
}
