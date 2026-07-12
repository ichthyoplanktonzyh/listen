//! Phase 3.11 minimal semantic-task surface: exactly the write/read paths the
//! 3.13+ Studios need to start, nothing more. All resources are append-only —
//! there are intentionally no update or delete routes.

use crate::*;
use domain::{
    AttemptResponse, JudgmentAbstain, JudgmentAdjudication, PointJudgment, PointVerdict,
    PracticeAnchor, PracticeTarget, RubricPoint, RubricRevisionNote, RubricSource,
    SemanticAttemptStatus, SemanticGeneratorProvenance, SemanticJudgment, SemanticJudgmentId,
    SemanticRubric, SemanticRubricId, SemanticTaskAttempt, SemanticTaskAttemptId,
    SemanticTaskConditions, SemanticTaskKind, judgment_adjudication_id, semantic_judgment_id,
    semantic_rubric_id, semantic_task_attempt_id,
};

#[derive(Debug, Deserialize)]
pub(crate) struct CreateSemanticRubricRequest {
    pub purpose: SemanticTaskKind,
    pub source: RubricSource,
    pub response_language: LanguageCode,
    pub points: Vec<RubricPoint>,
    #[serde(default = "default_rubric_version")]
    pub version: u32,
    pub provenance: SemanticGeneratorProvenance,
    #[serde(default)]
    pub revision: Option<RubricRevisionNote>,
}

fn default_rubric_version() -> u32 {
    1
}

pub(crate) async fn create_semantic_rubric(
    State(state): State<ApiState>,
    Json(request): Json<CreateSemanticRubricRequest>,
) -> Result<Json<SemanticRubric>, ApiError> {
    let id = semantic_rubric_id(
        request.source.media_id.as_ref(),
        request.source.start_ms,
        request.source.end_ms,
        request.purpose,
        &request.source.language,
        &request.response_language,
        &request.source.transcript_snapshot,
    );
    let rubric = SemanticRubric {
        id,
        purpose: request.purpose,
        source: request.source,
        response_language: request.response_language,
        points: request.points,
        version: request.version,
        provenance: request.provenance,
        revision: request.revision,
        created_at_ms: application::now_ms(),
    };
    state
        .services
        .save_semantic_rubric(rubric)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct SemanticRubricQuery {
    version: Option<u32>,
}

pub(crate) async fn semantic_rubric(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Query(query): Query<SemanticRubricQuery>,
) -> Result<Json<SemanticRubric>, ApiError> {
    let id = SemanticRubricId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .semantic_rubric(&id, query.version)
        .map_err(ApiError::from)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("semantic rubric"))
}

pub(crate) async fn semantic_rubric_attempts(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<SemanticTaskAttempt>>, ApiError> {
    let id = SemanticRubricId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .semantic_attempts_for_rubric(&id)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateSemanticAttemptRequest {
    pub kind: SemanticTaskKind,
    pub target: PracticeTarget,
    #[serde(default)]
    pub anchors: Vec<PracticeAnchor>,
    pub rubric_id: String,
    pub rubric_version: u32,
    pub conditions: SemanticTaskConditions,
    pub responses: Vec<AttemptResponse>,
    pub status: SemanticAttemptStatus,
    pub started_at_ms: u64,
    #[serde(default)]
    pub ended_at_ms: Option<u64>,
}

pub(crate) async fn create_semantic_attempt(
    State(state): State<ApiState>,
    Json(request): Json<CreateSemanticAttemptRequest>,
) -> Result<Json<SemanticTaskAttempt>, ApiError> {
    let rubric_id = SemanticRubricId::parse(request.rubric_id).map_err(ApplicationError::from)?;
    let id = semantic_task_attempt_id(
        &rubric_id,
        request.rubric_version,
        request.kind,
        request.started_at_ms,
        &request.responses,
    );
    let attempt = SemanticTaskAttempt {
        id,
        kind: request.kind,
        target: request.target,
        anchors: request.anchors,
        rubric_id,
        rubric_version: request.rubric_version,
        conditions: request.conditions,
        responses: request.responses,
        status: request.status,
        started_at_ms: request.started_at_ms,
        ended_at_ms: request.ended_at_ms,
    };
    state
        .services
        .record_semantic_attempt(attempt)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn semantic_attempt(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<SemanticTaskAttempt>, ApiError> {
    let id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .semantic_attempt(&id)
        .map_err(ApiError::from)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("semantic attempt"))
}

pub(crate) async fn semantic_attempt_judgments(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<SemanticJudgment>>, ApiError> {
    let id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .semantic_judgments_for_attempt(&id)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateSemanticJudgmentRequest {
    pub attempt_id: String,
    pub response_revision: u32,
    pub rubric_id: String,
    pub rubric_version: u32,
    pub rubric_source_sha256: String,
    pub response_transcript_sha256: String,
    #[serde(default)]
    pub points: Vec<PointJudgment>,
    #[serde(default)]
    pub abstain: Option<JudgmentAbstain>,
    pub provenance: SemanticGeneratorProvenance,
    #[serde(default)]
    pub raw_output: serde_json::Value,
    pub evidence_class: String,
}

pub(crate) async fn create_semantic_judgment(
    State(state): State<ApiState>,
    Json(request): Json<CreateSemanticJudgmentRequest>,
) -> Result<Json<SemanticJudgment>, ApiError> {
    let attempt_id =
        SemanticTaskAttemptId::parse(request.attempt_id).map_err(ApplicationError::from)?;
    let rubric_id = SemanticRubricId::parse(request.rubric_id).map_err(ApplicationError::from)?;
    let created_at_ms = application::now_ms();
    let id = semantic_judgment_id(
        &attempt_id,
        request.response_revision,
        request.rubric_version,
        request.provenance.kind,
        created_at_ms,
    );
    let judgment = SemanticJudgment {
        id,
        attempt_id,
        response_revision: request.response_revision,
        rubric_id,
        rubric_version: request.rubric_version,
        rubric_source_sha256: request.rubric_source_sha256,
        response_transcript_sha256: request.response_transcript_sha256,
        points: request.points,
        abstain: request.abstain,
        provenance: request.provenance,
        raw_output: request.raw_output,
        evidence_class: request.evidence_class,
        created_at_ms,
    };
    state
        .services
        .record_semantic_judgment(judgment)
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn semantic_judgment_adjudications(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<JudgmentAdjudication>>, ApiError> {
    let id = SemanticJudgmentId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .judgment_adjudications(&id)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct CreateJudgmentAdjudicationRequest {
    pub judgment_id: String,
    pub point_id: String,
    pub prior_verdict: PointVerdict,
    pub user_verdict: PointVerdict,
    #[serde(default)]
    pub note: Option<String>,
}

pub(crate) async fn create_judgment_adjudication(
    State(state): State<ApiState>,
    Json(request): Json<CreateJudgmentAdjudicationRequest>,
) -> Result<Json<JudgmentAdjudication>, ApiError> {
    let judgment_id =
        SemanticJudgmentId::parse(request.judgment_id).map_err(ApplicationError::from)?;
    let occurred_at_ms = application::now_ms();
    let id = judgment_adjudication_id(
        &judgment_id,
        &request.point_id,
        request.user_verdict,
        occurred_at_ms,
    );
    let adjudication = JudgmentAdjudication {
        id,
        judgment_id,
        point_id: request.point_id,
        prior_verdict: request.prior_verdict,
        user_verdict: request.user_verdict,
        note: request.note,
        occurred_at_ms,
    };
    state
        .services
        .record_judgment_adjudication(adjudication)
        .map(Json)
        .map_err(ApiError::from)
}
