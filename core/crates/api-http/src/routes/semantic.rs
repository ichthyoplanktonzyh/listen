//! Phase 3.11 minimal semantic-task surface: exactly the write/read paths the
//! 3.13+ Studios need to start, nothing more. All resources are append-only —
//! there are intentionally no update or delete routes.

use crate::{
    ApiError, ApiState, ApplicationError, Deserialize, Json, LanguageCode, Path, Query,
    RecordSpeakingProduction, State, StatusCode,
};
use domain::{
    AsrReliability, AssistanceLevel, AttemptResponse, JudgmentAbstain, JudgmentAdjudication,
    LexicalEntryId, PointJudgment, PointVerdict, PracticeAnchor, PracticeTarget, RubricPoint,
    RubricRevisionNote, RubricSource, SemanticAttemptStatus, SemanticGeneratorProvenance,
    SemanticJudgment, SemanticJudgmentId, SemanticRubric, SemanticRubricId, SemanticTaskAttempt,
    SemanticTaskAttemptId, SemanticTaskConditions, SemanticTaskKind, SpeakingAssistanceLevel,
    SubtitleSentenceId, judgment_adjudication_id, semantic_judgment_id, semantic_rubric_id,
    semantic_task_attempt_id,
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
        .semantic()
        .save_semantic_rubric(rubric)
        .map(Json)
        .map_err(ApiError::from)
}

#[derive(Debug, Deserialize)]
pub(crate) struct SemanticRubricQuery {
    version: Option<u32>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct SemanticRubricLookupQuery {
    media_id: Option<String>,
    start_ms: u64,
    end_ms: u64,
    purpose: SemanticTaskKind,
    response_language: String,
    source_sha256: String,
}

/// Read-side rubric lookup by source identity (Phase 3.13): the client knows
/// the segment and snapshot hash but not the server-minted fingerprint id.
pub(crate) async fn lookup_semantic_rubric(
    State(state): State<ApiState>,
    Query(query): Query<SemanticRubricLookupQuery>,
) -> Result<Json<Option<SemanticRubric>>, ApiError> {
    state
        .services
        .semantic()
        .find_rubric_for_source(
            query.media_id.as_deref(),
            query.start_ms,
            query.end_ms,
            query.purpose,
            &query.response_language,
            &query.source_sha256,
        )
        .map(Json)
        .map_err(ApiError::from)
}

pub(crate) async fn semantic_rubric(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Query(query): Query<SemanticRubricQuery>,
) -> Result<Json<SemanticRubric>, ApiError> {
    let id = SemanticRubricId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .semantic()
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
        .semantic()
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
        .semantic()
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
        .semantic()
        .semantic_attempt(&id)
        .map_err(ApiError::from)?
        .map(Json)
        .ok_or_else(|| ApiError::not_found("semantic attempt"))
}

#[derive(Debug, Deserialize)]
pub(crate) struct ConfirmSpeakingTargetRequest {
    lexical_entry_id: String,
    surface_form: String,
    #[serde(default)]
    sentence_id: Option<String>,
}

pub(crate) async fn confirm_speaking_target(
    State(state): State<ApiState>,
    Path(id): Path<String>,
    Json(request): Json<ConfirmSpeakingTargetRequest>,
) -> Result<StatusCode, ApiError> {
    let attempt_id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    let attempt = state
        .services
        .semantic()
        .semantic_attempt(&attempt_id)?
        .ok_or_else(|| ApiError::not_found("semantic attempt"))?;
    if !matches!(
        attempt.kind,
        SemanticTaskKind::L2Retelling | SemanticTaskKind::RoleReply
    ) || attempt.status != SemanticAttemptStatus::Completed
    {
        return Err(ApplicationError::Validation("constructed speaking attempt").into());
    }
    let response = attempt
        .responses
        .first()
        .ok_or(ApplicationError::Validation("speaking response"))?;
    if response.asr_reliability == Some(AsrReliability::Unreliable) {
        return Err(ApplicationError::Validation("reliable speaking transcript").into());
    }
    let surface = request.surface_form.trim();
    if surface.is_empty() || !contains_literal_target(&response.transcript, surface) {
        return Err(ApplicationError::Validation("literal target in speaking response").into());
    }
    let assistance = match attempt.kind {
        SemanticTaskKind::L2Retelling => AssistanceLevel::None,
        SemanticTaskKind::RoleReply => match attempt.conditions.speaking_assistance {
            Some(SpeakingAssistanceLevel::FullSentence) => AssistanceLevel::FullText,
            Some(SpeakingAssistanceLevel::Keywords) => AssistanceLevel::PartialText,
            Some(SpeakingAssistanceLevel::NoText) => AssistanceLevel::None,
            None => return Err(ApplicationError::Validation("role reply assistance").into()),
        },
        _ => unreachable!(),
    };
    let rubric = state
        .services
        .semantic()
        .semantic_rubric(&attempt.rubric_id, Some(attempt.rubric_version))?
        .ok_or_else(|| ApiError::not_found("semantic rubric"))?;
    let lexical_entry_id =
        LexicalEntryId::parse(request.lexical_entry_id).map_err(ApplicationError::from)?;
    let sentence_id = request
        .sentence_id
        .map(SubtitleSentenceId::parse)
        .transpose()
        .map_err(ApplicationError::from)?;
    let source_ref = format!(
        "speaking:{}:{}",
        attempt.id.as_str(),
        lexical_entry_id.as_str()
    );
    state
        .services
        .lexical_learning()
        .record_speaking_production(RecordSpeakingProduction {
            lexical_entry_id,
            sentence_id,
            surface_form: surface.to_owned(),
            media_id: rubric.source.media_id,
            assistance,
            source_ref,
            occurred_at_ms: attempt.ended_at_ms.unwrap_or(attempt.started_at_ms),
        })?;
    Ok(StatusCode::NO_CONTENT)
}

fn contains_literal_target(transcript: &str, surface: &str) -> bool {
    let transcript = transcript.to_lowercase();
    let surface = surface.to_lowercase();
    if !surface.is_ascii() {
        return transcript.contains(&surface);
    }
    transcript.match_indices(&surface).any(|(start, value)| {
        let before = transcript[..start].chars().next_back();
        let after = transcript[start + value.len()..].chars().next();
        before.is_none_or(|character| !character.is_alphanumeric())
            && after.is_none_or(|character| !character.is_alphanumeric())
    })
}

pub(crate) async fn semantic_attempt_judgments(
    State(state): State<ApiState>,
    Path(id): Path<String>,
) -> Result<Json<Vec<SemanticJudgment>>, ApiError> {
    let id = SemanticTaskAttemptId::parse(id).map_err(ApplicationError::from)?;
    state
        .services
        .semantic()
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
        .semantic()
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
        .semantic()
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
        .semantic()
        .record_judgment_adjudication(adjudication)
        .map(Json)
        .map_err(ApiError::from)
}
